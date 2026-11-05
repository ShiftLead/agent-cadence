#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/gate_sweep.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""The gate sweep: what nothing-waits-silently files, closes and lifts in this repo now, as a plan or, with
``--apply``, as PRs (TD-219; ledgerboard's target design §3.2, §1.2, §4.4).

    gate_sweep.py [--apply] [--json] [--timeout S] [--reask-days N] [--event-age-days N]

Every gate in ``**Blocked by:**`` has a way out (a decision is answered, an ``until`` date comes, an event's
check passes); the sweep is what notices one that is stuck. **What it decides is ledgerboard's ``sweep()``**,
a pure function; this script is the I/O around it:

- **What it reads.** This repo's ledger and archive, and every board on this machine's roster
  (``docs/user_attention.md`` and ``docs/user_attention_archive.md``, ``$AGENT_CADENCE_REG_DIR`` honoured) —
  each read from its clone's ``origin/<default>`` where that ref exists (what is merged, never a session's
  edit in progress), else its working tree. Nothing is fetched: a stale clone reads stale, and a board
  missing from a clone counts as not covering (§3.2). This repo's own board must be there: event items go
  on it. A clone whose origin is this repo's (another worktree) is read once, as this repo.
- **The event checks.** Each open ``event (<name>)`` gate's check runs through ``event_checks.py`` (its
  host rules and four outcomes), and its outcomes are ``sweep()``'s ``results``.
- **A ``host-log`` gate no host answers** (TD-230; ``unanswered()``): ``sweep()`` gets no outcome for it and
  so says nothing, and it would wait silently. Past the event age, with no item on any board read naming
  it (open, decided or closed — what a host that answered would have left), it gets one ``act`` item on
  this board, ``Context: TD-n event (<name>) unanswered``, filed once ever and closed by the sweep once
  this host answers, another item names the gate, or the gate is on no open entry.
- **What it prints.** The plan: each item to file (on which board, its kind, text and ``Context:``), each
  item to close (by board and key), and each host lift (``until`` reached, an event passed, with its
  evidence). ``--json``: ``{repo, source, boards: [{board, source}], unread, checks, to_file, to_close, lifts}``.
  A board that is there and cannot be read (a git call failed or timed out) is left out and named under
  ``unread``, never read as absent; this repo's own ledger or board unreadable is no plan at all.

**Without --apply it writes nothing.** **With --apply** it makes the writes on this repo's forge (§4.4's host
column), from temporary worktrees at ``origin/<default>`` — the checkout it runs in is never touched:

- **Each lift is its own tool PR**, on ``lift/TD-n/<event name>`` (``…/until``), written by ``ledger.py lift``
  (the gate removed, the ``gate lifted`` Log line with the host's token, ``$CADENCE_HOST`` else this machine's
  short name, and the evidence a reviewer re-runs). Idempotent: nothing when a PR on that branch is open, or
  when another open PR's diff already logs ``gate lifted: <gate>`` in the entry; a PR on that branch closed
  unmerged is never reopened — an ``act`` item "Lift of <gate> on TD-n was closed" (``Context: TD-n <gate>
  lift``) asks why, once: not when an item with that Context is on the board, open or closed, or in a sweep
  PR open or merged since (origin not fetched yet). (ledgerboard
  v2.4's Context reader names no ``until`` gate, so its sweep never closes such an item for an ``until``.)
- **This repo's own board** gets the items to file and the closes as one sweep PR on ``sweep/<UTC date>``
  (each item due today, under the session ``$SHIFTLEAD_SESSION`` else ``gate-sweep``); while an earlier
  ``sweep/…`` PR is open, nothing more is filed.
- **Another roster repo's board** gets its items and closes as one PR in that repo (TD-229, as ``ledger.py
  set``'s notices do): a temporary worktree of its clone at its ``origin/<default>``, the branch
  ``notices/<this repo>-sweep-<UTC date>``, opened on that repo's forge and left for its review; each item's
  ``Context:`` (and a bare ``TD-n`` in its words) names ``<this repo>#TD-n``. Nothing while an earlier such
  PR from this repo is open there, and nothing on a board more visible than this repo (the items carry this
  repo's entries' words; each repo's visibility is read on its own forge, github.com or GitLab, as the event
  checks read it); each is said. That clone is not fetched either: its PR is built on its ``origin/<default>``
  as last fetched, and a stale one shows as a conflict on that PR.
- The PRs are reviewed and merged like any (cadence.md §4). Findings reach the person as every board item
  does, through the session-start report. A push is never forced: a branch left on origin with no PR is
  named, to delete; a PR the forge would not open has its pushed branch deleted again. **What runs the sweep is the person's choice** (cadence.md §2.14): by hand,
  a session, or daily from the timer ``gate_sweep_timer.sh`` writes, which fetches first. The plan reads what is fetched: fetch first.

The re-ask window and the event age
are the consumer's numbers (``--reask-days``, ``--event-age-days``; default 30 each, §3.2). Today is the
UTC date for the ledger and this machine's local date for the boards (§3.1).

Exit 0 when the plan was made (whatever it holds) and every write asked for was made or rightly skipped;
1 when a write was not done (each says why: ``not done — …``); 2 when there is no plan (no ledger, no own
board, a format ``sweep()`` refuses) or ``--apply`` cannot ask the forge. ``--json`` adds ``applied``, the
lines. Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import event_checks as E  # noqa: E402  # sibling SYNC script: the event runner
import forge as F  # noqa: E402  # sibling SYNC script: the one place a forge's CLI runs
import ledger as L  # noqa: E402  # sibling SYNC script: the ledger's readers and the roster
import ledgerboard as LB  # noqa: E402  # sibling SYNC file: the formats and sweep(), defined once
import nudge_user_attention as N  # noqa: E402  # sibling SYNC script: the roster and default-branch readers
from ledgerboard import board as LBB  # noqa: E402  # the package's board writer


class Unreadable(Exception):
    """A tree or file that is there and could not be read (a git call failed or timed out): never read as absent."""


def tree_io(root: Path) -> tuple[tuple[LB.Ls, LB.Read], str]:
    """((ls, read) over ``root``'s ``origin/<default>`` where it exists, else its working tree; its name).
    Unreadable when the ref exists and its tree cannot be listed: never a silent fall back to the work tree."""
    ref = f"origin/{N.default_branch(root)}"
    if L._git(root, "rev-parse", "--verify", "-q", ref) is not None:
        io = L.git_io(root, ref, "docs")
        if io is None:
            raise Unreadable(f"{root.name}: {ref}'s tree could not be listed")
        return io, ref
    fls, fread = L.fs_io()
    return ((lambda p: fls(str(root / p))), (lambda p: fread(str(root / p)))), "working tree"


def read(io: tuple[LB.Ls, LB.Read], path: str, where: str) -> str | None:
    """``path``'s text; None when the tree has no such file; Unreadable when it has and the read failed."""
    text = io[1](path)
    if text is None and Path(path).name in (io[0](str(Path(path).parent)) or []):
        raise Unreadable(f"{where}: {path} is there and could not be read")
    return text


def origin_url(root: Path) -> str:
    return (L._git(root, "remote", "get-url", "origin") or "").strip()


def board_of(root: Path) -> tuple[tuple | None, str]:
    """(``(origin_url, basename, text, archive_text)`` of the board at ``root``, as ``sweep()`` takes it, or None
    when it has none; where it was read). Unreadable when the board or its archive is there and cannot be read."""
    io, source = tree_io(root)
    where = f"{root.name} ({source})"
    text = read(io, LB.BOARD_PATH, where)
    if text is None:
        return None, source
    return (origin_url(root), root.name, text, read(io, LB.BOARD_ARCHIVE_PATH, where) or ""), source


def plan(top: Path, roster: list[Path], runner: E.Runner, *, today_utc: date, today_local: date,
         reask_days: int = LB.SWEEP_REASK_DAYS, event_age_days: int = LB.SWEEP_EVENT_AGE_DAYS) -> dict:
    """The sweep's plan for the repo at ``top``: sweep()'s ``{to_file, to_close, lifts}``, with ``repo``,
    ``source``, ``boards`` (each board read, by its sweep name) and ``checks`` (each event gate's outcome).
    Raises LB.Refused when it cannot be made."""
    url = origin_url(top)
    repo = LB.origin_path(url) or top.name
    try:
        io, source = tree_io(top)
        rel = L.ledger_at(top, io)
        arel = L.ARCHIVE_REL if rel == L.LEDGER_REL else None
        if rel == L.LEDGER_REL:
            read(io, rel, top.name)
            read(io, arel, top.name)
        else:   # every entry file and archived one: a failed read is no plan, never a missing entry
            for d in (rel, f"{rel}/{LB.LEDGER_ARCHIVE}"):
                for name in io[0](d) or []:
                    read(io, f"{d}/{name}", top.name)
        text, arch = L.read_pair(rel, arel, io)
        # host-log (TD-230): the repo's sources from the same tree as the ledger, never the checkout's
        runner.log_sources = read(io, E.LOG_SOURCES, top.name) or ""
        own, _ = board_of(top)
    except Unreadable as e:
        raise LB.Refused(str(e)) from None
    if text is None:
        raise LB.Refused(f"no ledger at {rel} ({source})")
    if own is None:
        raise LB.Refused(f"no {LB.BOARD_PATH} ({source}): the sweep's event items go on this repo's own board")
    boards, seen = [own], {LB.origin_key(url) or str(top.resolve())}
    read_from = [{"board": LB.origin_key(url) or top.name, "source": source}]
    unread: list[str] = []
    for root in roster:
        key = LB.origin_key(origin_url(root)) or str(root.resolve())
        if key in seen:
            continue   # this repo's other worktrees, and a second clone of one repo, are read once
        try:
            b, src = board_of(root)
        except Unreadable as e:
            unread.append(str(e))   # left out, and said: it may hold the item that covers a gate
            continue
        if b is None:
            continue   # no board there: a later clone of the same origin may still have one
        seen.add(key)
        boards.append(b)
        read_from.append({"board": LB.origin_key(b[0]) or b[1], "source": src})
    checks = [{**g, **runner.run(g)} for g in E.gates(text)]
    results = {(c["id"], c["name"]): (c["outcome"], c["evidence"]) for c in checks
               if c["outcome"] is not None}   # no outcome (a host-log check this host does not answer): left out
    out = LB.sweep([text, arch], boards, results, today_utc, today_local, reask_days=reask_days,
                   event_age_days=event_age_days, repo=repo)
    filing, closing = unanswered(text, checks, boards, repo, today_utc, event_age_days)
    name = LB._board_name(own)
    for it in filing:
        out["to_file"].setdefault(name, []).append(it)
    for k in closing:
        if k not in out["to_close"].setdefault(name, []):
            out["to_close"][name].append(k)
    return {"repo": repo, "source": source, "boards": read_from, "unread": unread,
            "checks": [{k: c[k] for k in ("id", "name", "outcome", "evidence", "why")} for c in checks], **out}


UNANSWERED = "unanswered"  # the warning item's Context qualifier: TD-n event (<name>) unanswered (TD-230 Fix 4)


def unanswered(text: str, checks: list[dict], boards: list, repo: str, today_utc: date,
               event_age_days: int) -> tuple[list[dict], list[str]]:
    """The host-side warning for a ``host-log`` gate no host has answered (TD-230 Fix 4; ledgerboard's
    ``docs/plans/TD-045-host-log.md``, *The builds*): ``(items to file, keys to close)`` on this repo's own board.

    ``sweep()`` gets no outcome for a gate no host answers, so it neither lifts it nor files anything, and
    such a gate waits silently (a source only an unselected profile declares passes ``validate --ledger``).
    One host cannot hear another, so *no host has ever answered* is read off the boards: a host that answers
    a gate past the event age lifts it (passed) or files an item about it (*Still waiting*, *Event check
    broken*, *can no longer happen*), and those items stay in the board's archive once closed. So a
    ``host-log`` gate this host gives no outcome, older than ``event_age_days`` (``gate_age()``), that no
    item on any board read names — open, decided or closed — gets one ``act`` item, ``Context: TD-n event
    (<name>) unanswered``, filed once: never again while one with that Context is on a board or in its
    archive. ``sweep()`` never closes it (its qualifier is not one sweep() reads); this does, once the gate
    is no longer an open entry's, this host answers it, or another item names it."""
    reads = LB._read_boards(boards, repo)
    texts = LB._entry_texts(text)
    silent: set[tuple[int, str]] = set()
    filing: list[dict] = []
    for c in checks:
        if not c["check"] or c["check"].get("type") != "host-log":
            continue
        tid, gate = c["id"], f"event ({c['name']})"
        num, key = LB._num(tid), LB._gate_key(gate)
        named = [r for r in reads if r["ctx"] is not None and r["ctx"][:2] == (num, key)]
        if c["outcome"] is not None or any(r["ctx"][2] != UNANSWERED for r in named):
            continue   # this host answers it, or some host did: the sweep's own items say the rest
        try:
            age = LB.gate_age(texts.get(tid, ""), gate)
        except LB.Refused:
            age = None
        if age is None or (today_utc - age).days <= event_age_days:
            continue
        if (num, key) in silent or named:   # a gate checked twice warns once; one item, ever (its own closed too)
            silent.add((num, key))
            continue
        silent.add((num, key))
        filing.append({"text": f"No host has answered {gate} on {tid} for more than {event_age_days} days: declare "
                               "its source on a host that sweeps this ledger (that host's host-log.toml), or "
                               "rewrite the gate.",
                       "context": f"{tid} {gate} {UNANSWERED}", "kind": "act", "answers": None, "default": None,
                       "detail": None, "lifts": None})
    closing = [LB.item_key(r["line"]) for r in reads
               if r["own"] and r["state"] in ("open", "decided") and r["ctx"] is not None
               and r["ctx"][2] == UNANSWERED and r["ctx"][:2] not in silent]
    return filing, list(dict.fromkeys(closing))


# -- --apply: the writes (TD-219 slice 3; target design §4.4's host column) ------------------------------------

SWEEP_BRANCH = "sweep/"          # the board PR's branch: sweep/<UTC date>
LIFT_BRANCH = "lift/"            # a lift PR's: lift/TD-n/<event name> | until (§4.4)
GIT_TIMEOUT = 60.0


def lift_branch(tid: str, gate: str) -> str:
    """§4.4's key: ``lift/TD-n/<event name>``, ``…/until``, ``…/decision-<person lower-cased>``."""
    if gate.startswith("event ("):
        return f"{LIFT_BRANCH}{tid}/{gate[len('event ('):-1]}"
    if gate.startswith("until "):
        return f"{LIFT_BRANCH}{tid}/until"
    return f"{LIFT_BRANCH}{tid}/decision-{gate[gate.index('(') + 1:-1].lower()}"


def host_token() -> str:
    """Who lifts, in the Log: ``$CADENCE_HOST``, else this machine's short name — a token of [A-Za-z0-9_.@/-]."""
    raw = os.environ.get("CADENCE_HOST", "").strip() or socket.gethostname().split(".")[0]
    return re.sub(r"[^A-Za-z0-9_.@/-]", "-", raw) or "host"


def _git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, timeout=GIT_TIMEOUT,
                          check=False)


class Scratch:
    """A temporary worktree of ``top`` at ``base`` on a new ``branch``, removed on leaving — whatever happened."""

    def __init__(self, top: Path, base: str, branch: str) -> None:
        self.top, self.base, self.branch = top, base, branch
        self.dir = Path(tempfile.mkdtemp(prefix="gate-sweep-"))
        self.made = False

    def __enter__(self) -> Path:
        if _git(self.top, "rev-parse", "--verify", "-q", f"refs/heads/{self.branch}").returncode == 0:
            self.__exit__()
            raise RuntimeError(f"a local branch {self.branch} exists — someone's work: left alone")
        r = _git(self.top, "worktree", "add", "-q", "-b", self.branch, str(self.dir), self.base)
        if r.returncode != 0:
            self.__exit__()
            raise RuntimeError(f"git worktree add {self.branch}: {(r.stderr or r.stdout).strip()}")
        self.made = True
        return self.dir

    def __exit__(self, *_: object) -> None:
        def quiet(*args: str) -> None:   # each step runs whatever the one before it did
            try:
                _git(self.top, *args)
            except (OSError, subprocess.SubprocessError):
                pass
        quiet("worktree", "remove", "--force", str(self.dir))
        shutil.rmtree(self.dir, ignore_errors=True)
        quiet("worktree", "prune")
        if self.made:   # pushed or not, the branch this made is the PR's, never a save-point
            quiet("branch", "-D", self.branch)


def _ship(top: Path, wt: Path, be, branch: str, base: str, subject: str, body: str) -> str:
    """Commit everything in ``wt``, push ``branch``, open its PR; the PR's URL."""
    for args in (("add", "-A"), ("commit", "-q", "-m", subject)):
        r = _git(wt, *args)
        if r.returncode != 0:
            raise RuntimeError(f"git {args[0]}: {(r.stderr or r.stdout).strip()}")
    r = _git(wt, "push", "-q", "origin", f"HEAD:refs/heads/{branch}")
    if r.returncode != 0:   # most often a branch left on origin with no PR: this never forces over it
        raise RuntimeError(f"git push {branch}: {(r.stderr or r.stdout).strip()} — if origin holds {branch} with no "
                           f"PR on it, delete it there (git push origin --delete {branch}) and sweep again")
    try:
        return be.create_pr(branch, base, subject, body)
    except (F.ForgeUnreadable, RuntimeError, OSError, subprocess.SubprocessError) as e:   # no PR: take the pushed branch back, or the next sweep's push is refused
        gone = _git(wt, "push", "-q", "origin", "--delete", branch).returncode == 0
        raise F.ForgeUnreadable(f"{e} — the PR was not opened; {branch} "
                                + ("was deleted from origin again" if gone else
                                   f"is left on origin: delete it (git push origin --delete {branch})")) from None


def _closes(board: str, keys: list[str]) -> list[tuple[int, str, str]]:
    """(line, expect, key) of each open item of ``board`` whose ``item_key`` is one of ``keys``."""
    lines = board.splitlines()
    out = []
    for it in LB.parse_board(board, warn=False):
        raw = lines[it.line - 1]
        if LB.item_key(raw) in keys:
            m = LB.ITEM_RE.match(raw)
            out.append((it.line, m.group("text")[:60] if m else raw.strip()[:60], LB.item_key(raw)))
    return out


OTHER_BRANCH = "notices/"        # a PR on another repo's board: notices/<this repo>-sweep-<UTC date> (TD-229)


def _other_board(top: Path, repo: str, board: str, root: str | None, items: list[dict], keys: list[str], be, *,
                 today_local: date, today_utc: date, by: str) -> str:
    """File ``items`` on, and close ``keys`` on, another roster repo's ``board`` by a PR in that repo (TD-229, as
    ``ledger.py set``'s notices do since TD-226): a temporary worktree of its clone at ``root``, at its
    ``origin/<default>``, pushed on ``notices/<this repo>-sweep-<UTC date>`` and opened on that repo's forge, left
    open for its review. Nothing while an earlier such PR from this repo is open there, and nothing written to a
    board more visible than this repo (an item carries this repo's entry's words). One line: what was done."""
    n = f"{len(items)} to file, {len(keys)} to close"
    if not root:
        return f"board {board}: not done — no clone of it on this machine's roster ({n})"
    root_p = Path(root)
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", repo).strip("-")
    prefix = f"{OTHER_BRANCH}{slug}-sweep-"
    try:
        # each repo asked on its own forge, by the slug that forge reads (event_checks.py's rule: github.com or GitLab)
        runner = E.Runner(top)
        vis = {}
        for who, at in (("mine", top), ("theirs", root_p)):
            be_x, s = runner._backend(at)
            vis[who] = (s, be_x.repo_info(s)["visibility"])
        (_, vm), (theirs, vt) = vis["mine"], vis["theirs"]
        if E.VISIBILITY[vt] > E.VISIBILITY[vm]:
            return (f"board {board}: not written — {theirs} is {vt}, more visible than this repo "
                    f"({vm}), and its items carry this repo's entries' words ({n})")
        be2 = F.backend(root_p, cwd=root_p)   # gh infers the repo from its directory: that repo's
        mark = re.compile(rf"{re.escape(prefix)}\d{{4}}-\d\d-\d\d$")   # never a set notices branch of a repo named <x>-sweep
        earlier = [q for q in be2.open_prs_files() if mark.match(str(q["head"] or ""))]
        if earlier:
            return (f"board {board}: an earlier sweep PR #{earlier[0]['number']} from this repo is open there — "
                    f"merge or close it, then sweep ({n} wait)")
        default = N.default_branch(root_p)
        branch = f"{prefix}{today_utc.isoformat()}"
        session = os.environ.get("SHIFTLEAD_SESSION", "").strip() or "gate-sweep"
        with Scratch(root_p, f"origin/{default}", branch) as wt:
            path = str(wt / LB.BOARD_PATH)
            for it in items:
                # sweep() writes the Context as <repo>#TD-n; a bare TD-n in the words would read as that repo's own
                m = re.match(r"\S+#(TD-\d+)\b", it["context"])
                bare = re.compile(rf"(?<![#\w]){re.escape(m.group(1))}\b") if m else None
                fix = (lambda x: bare.sub(f"{repo.lower()}#{m.group(1)}", x)) if bare else (lambda x: x)
                detail = ({k: [fix(x) for x in v] if isinstance(v, list) else fix(v)
                           for k, v in it["detail"].items()} if it["detail"] else None)
                LBB.apply(LBB.plan_add(path, fix(it["text"]), due=today_local.isoformat(), context=it["context"],
                                       kind=it["kind"], answers=it["answers"], default=it["default"],
                                       detail=detail, lifts=it["lifts"], session=session, host=by,
                                       today=today_local, tool="gate-sweep"))
            closed = 0
            for key in keys:   # one at a time: each close may move the lines below it
                hit = _closes(LBB.read(path), [key])
                if hit:
                    line, expect, _ = hit[0]
                    LBB.apply(LBB.plan_edit(path, "done", line, expect, today=today_local, tool="gate-sweep",
                                            why=f"the gate sweep of {repo}: its condition no longer holds"))
                    closed += 1
            subject = f"board: {repo}'s gate sweep {today_utc.isoformat()} — {len(items)} filed, {closed} closed"
            body = "\n".join([f"The gate sweep of {repo} (its TD-219; ledgerboard's target design §3.2) found items "
                              "that belong on this repo's board, whose `People:` names the person (TD-229).", ""]
                             + [f"- file: [{it['kind']}] {it['text']} — Context: {it['context']}" for it in items]
                             + [f"- close: {k}" for k in keys]
                             + ["", "Review it like any PR (cadence.md §4)."])
            url = _ship(root_p, wt, be2, branch, default, subject, body)
        return f"board {board}: opened {url}"
    except (RuntimeError, LB.Refused, F.ForgeUnreadable, KeyError, OSError, subprocess.SubprocessError) as e:
        return f"board {board}: not done — {e}"


def apply(top: Path, p: dict, be, *, today_local: date, today_utc: date, by: str) -> list[str]:
    """Make the plan's writes on this repo's forge (§4.4): each lift as its own tool PR, and the items and
    closes on this repo's own board as one sweep PR. What was done or skipped, one line each; RuntimeError /
    ForgeUnreadable stop only the PR they hit."""
    said: list[str] = []
    if not (p["lifts"] or any(p["to_file"].values()) or any(p["to_close"].values())):
        return said
    default = N.default_branch(top)
    base = f"origin/{default}"
    own = p["boards"][0]["board"]
    opened = be.open_prs_files()
    rel = L.ledger_at(top, tree_io(top)[0])
    extra: list[dict] = []   # the "lift was closed" items, filed with the sweep's own
    # sweep() does not file these (they are forge state), so it cannot de-dupe them: an item with the Context
    # on this board, open, decided or closed (the board and its archive), is not filed again
    io, _ = tree_io(top)
    mine = (read(io, LB.BOARD_PATH, top.name) or "") + "\n" + (read(io, LB.BOARD_ARCHIVE_PATH, top.name) or "")
    asked = {" ".join(c.group("ctx").split()).rstrip(".").lower()
             for it in LB.parse_board(mine, warn=False) + LB.parse_closed_items(mine)
             for c in [LB.CONTEXT_RE.search(it.text)] if c}

    for x in p["lifts"]:
        tid, gate = x["id"], x["gate"]
        branch = lift_branch(tid, gate)
        path = f"{rel}/{tid}.md" if rel == L.LEDGER_DIR_REL else rel
        try:
            mine = [q for q in opened if q["head"] == branch]
            if mine:
                said.append(f"lift {tid} {gate}: PR #{mine[0]['number']} is open — nothing to do")
                continue
            dup = next((q for q in opened if path in q["files"]
                        and re.search(rf"^\+.*gate lifted: {re.escape(gate)} ", be.pr_diff(q["number"]), re.M)), None)
            if dup:
                said.append(f"lift {tid} {gate}: PR #{dup['number']} already lifts it — nothing to do")
                continue
            past = be.prs_for_branch(branch, limit=5)
            if any(q["state"] == "merged" for q in past):
                said.append(f"lift {tid} {gate}: its PR merged and {base} still carries the gate — fetch, then sweep")
                continue
            if any(q["state"] == "closed" for q in past):
                n = next(q["number"] for q in past if q["state"] == "closed")
                ctx = f"{tid} {gate} lift"
                # on the board as fetched, or in a sweep PR open or merged since (an origin not fetched yet)
                if ctx.lower() in asked or any(
                        str(q.get("head") or "").startswith(SWEEP_BRANCH) and q["state"] in ("open", "merged")
                        and f"Context: {ctx}" in str(q.get("body") or "") for q in be.prs_naming(f"Context: {ctx}")):
                    said.append(f"lift {tid} {gate}: its PR #{n} was closed unmerged — not reopened; asked on the board already")
                    continue
                said.append(f"lift {tid} {gate}: its PR #{n} was closed unmerged — not reopened; an act item asks why, "
                            "in the sweep PR")
                extra.append({"text": f"Lift of {gate} on {tid} was closed", "context": f"{tid} {gate} lift",
                              "kind": "act", "answers": None, "default": None, "detail": None, "lifts": None})
                continue
            with Scratch(top, base, branch) as wt:
                argv = ["lift", tid, "--gate", gate, "--by", by, "--ledger", str(wt / L.LEDGER_DIR_REL)]
                if x["kind"] == "event":
                    argv += ["--evidence", x["evidence"]]
                r = subprocess.run([sys.executable, str(Path(__file__).with_name("ledger.py")), *argv], cwd=wt,
                                   capture_output=True, text=True, timeout=GIT_TIMEOUT, check=False)
                if r.returncode != 0:
                    raise RuntimeError(f"ledger.py lift: {(r.stderr or r.stdout).strip()}")
                why = "date reached" if x["kind"] == "until" else f"its check passed: {x['evidence']}"
                url = _ship(top, wt, be, branch, default, f"{tid}: lift {gate} — {why} (gate sweep)",
                            f"The gate sweep (TD-219) lifts `{gate}` from {tid}: {why}.\n\n"
                            "A reviewer re-runs the check from the evidence in the Log line before merging "
                            "(ledgerboard's target design §4.2: a lifted gate never re-arms).")
            said.append(f"lift {tid} {gate}: opened {url}")
        except (RuntimeError, F.ForgeUnreadable, OSError, subprocess.SubprocessError) as e:
            said.append(f"lift {tid} {gate}: not done — {e}")

    roots: dict[str, str] = {}   # each board's clone: the first on the roster of its origin with a board, as plan()
    for root in N.read_registry() or []:
        k = LB.origin_key(origin_url(root))
        if k and k != own and k not in roots and k in {*p["to_file"], *p["to_close"]}:
            try:
                if board_of(root)[0] is not None:
                    roots[k] = str(root)
            except Unreadable:
                continue
    for board in sorted({*p["to_file"], *p["to_close"]} - {own}):
        got, ks = list(p["to_file"].get(board, [])), list(p["to_close"].get(board, []))
        if got or ks:
            said.append(_other_board(top, p["repo"], board, roots.get(board), got, ks, be,
                                     today_local=today_local, today_utc=today_utc, by=by))

    items = list(p["to_file"].get(own, [])) + extra
    keys = list(p["to_close"].get(own, []))
    if not (items or keys):
        return said
    earlier = [q for q in opened if str(q["head"] or "").startswith(SWEEP_BRANCH)]
    if earlier:
        said.append(f"board: an earlier sweep PR #{earlier[0]['number']} is open — merge or close it, then sweep "
                    f"({len(items)} to file, {len(keys)} to close wait)")
        return said
    branch = f"{SWEEP_BRANCH}{today_utc.isoformat()}"
    try:
        with Scratch(top, base, branch) as wt:
            board = str(wt / LB.BOARD_PATH)
            host = by
            session = os.environ.get("SHIFTLEAD_SESSION", "").strip() or "gate-sweep"
            for it in items:
                LBB.apply(LBB.plan_add(board, it["text"], due=today_local.isoformat(), context=it["context"],
                                       kind=it["kind"], answers=it["answers"], default=it["default"],
                                       detail=it["detail"], lifts=it["lifts"], session=session, host=host,
                                       today=today_local, tool="gate-sweep"))
            closed = 0
            for key in keys:   # one at a time: each close may move the lines below it
                hit = _closes(LBB.read(board), [key])
                if hit:
                    line, expect, _ = hit[0]
                    LBB.apply(LBB.plan_edit(board, "done", line, expect, why="the gate sweep: its condition no longer holds",
                                            today=today_local, tool="gate-sweep"))
                    closed += 1
            subject = f"board: gate sweep {today_utc.isoformat()} — {len(items)} filed, {closed} closed (TD-219)"
            body = "\n".join(["The gate sweep (TD-219; ledgerboard's target design §3.2) on this repo's own board.", ""]
                             + [f"- file: [{it['kind']}] {it['text']} — Context: {it['context']}" for it in items]
                             + [f"- close: {k}" for k in keys])
            url = _ship(top, wt, be, branch, default, subject, body)
        said.append(f"board: opened {url}")
    except (RuntimeError, LB.Refused, F.ForgeUnreadable, OSError, subprocess.SubprocessError) as e:
        said.append(f"board: not done — {e}")
    return said


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--timeout", type=float, default=E.TIMEOUT, help="seconds per forge call of an event check")
    ap.add_argument("--reask-days", type=int, default=LB.SWEEP_REASK_DAYS)
    ap.add_argument("--event-age-days", type=int, default=LB.SWEEP_EVENT_AGE_DAYS)
    ap.add_argument("--apply", action="store_true", help="make the writes: a tool PR per lift, one sweep PR for "
                                                         "this repo's own board")
    a = ap.parse_args(argv)
    top = L._toplevel()
    today_utc, today_local = datetime.now(timezone.utc).date(), date.today()  # noqa: DTZ011  # a board's date is the person's own
    try:
        p = plan(top, N.read_registry() or [], E.Runner(top, timeout=a.timeout),
                 today_utc=today_utc, today_local=today_local,
                 reask_days=a.reask_days, event_age_days=a.event_age_days)
    except LB.Refused as e:
        print(f"gate_sweep: no plan — {e}", file=sys.stderr)
        return 2
    done: list[str] | None = None
    if a.apply:
        try:
            done = apply(top, p, F.backend(top), today_local=today_local, today_utc=today_utc, by=host_token())
        except F.ForgeUnreadable as e:
            print(f"gate_sweep: --apply cannot ask the forge — {e}", file=sys.stderr)
            return 2
    if a.json:
        print(json.dumps({**p, **({"applied": done} if done is not None else {})}, indent=2, ensure_ascii=False,
                         default=str))
        return 1 if done and any(": not done — " in d for d in done) else 0
    print(f"gate sweep of {p['repo']} ({p['source']}; {len(p['boards'])} board(s) read) — "
          + ("applied" if a.apply else "a plan: nothing written"))
    for b in p["boards"]:
        print(f"  board {b['board']} ({b['source']})")
    for u in p["unread"]:
        print(f"  ⚠ board not read: {u} — an item there is not seen, so the plan may file it again")
    for c in p["checks"]:
        print(f"  check {c['id']} event ({c['name']}): {c['outcome'] or 'no outcome'} — {c['evidence'] or c['why']}")
    for board, items in p["to_file"].items():
        for it in items:
            print(f"  file on {board}: [{it['kind']}] {it['text']} — Context: {it['context']}")
    for board, keys in p["to_close"].items():
        for k in keys:
            print(f"  close on {board}: {k}")
    for x in p["lifts"]:
        print(f"  lift {x['id']} {x['gate']} — {x['evidence']}")
    if not (p["to_file"] or p["to_close"] or p["lifts"]):
        print("  nothing to file, close or lift")
    for d in done or []:
        print(f"  → {d}")
    return 1 if done and any(": not done — " in d for d in done) else 0


if __name__ == "__main__":
    sys.exit(main())
