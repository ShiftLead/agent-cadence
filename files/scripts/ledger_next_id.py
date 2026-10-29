#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/ledger_next_id.py
# Edit it there: a repo runs it from its pinned dev-cadence (`dev-cadence path`), and a fix reaches it by a bump PR.
"""Hand out the next ledger id from the counter on origin (TD-124, cadence.md §2.10).

    ledger_next_id.py [--count n] [--by who] [--branch name] [--floor N] [--prs] [--ledger PATH] [--archive PATH] [--json]
    ledger_next_id.py --claim TD-N [--by who] [--branch name] [--json]

The counter is a branch on origin, ``cadence/ledger-ids``: never merged, never checked out, never a
local branch. Its tip's tree holds one file, ``LAST``, the last id given as a number. A take is one
commit whose parent is the tip it read, pushed with a plain (fast-forward) push: the server takes it
only if nobody moved the tip, so the branch is a lock with no server of ours. The design is
docs/plans/2026-10-22-ledger-ids.md in dev-cadence.

1. Probe ``git ls-remote --heads origin cadence/ledger-ids``: present, absent (the first take), or
   failed — the last goes to the fallback.
2. Fetch ``origin/<default>`` and, when present, the counter, in one ``git fetch``.
3. The next id is one above the highest of ``LAST`` (absent or not a number: ignored, a warning), the
   ids in the ledger and archive on ``origin/<default>`` (headings and table rows, read as numbers, so
   ``TD-28`` is 28; a v2 ledger's entry file names and headings, TD-160 — ``--ledger`` names either
   layout, and main is read in the one it has), and ``--floor``. The first take also reads the open PRs (``--prs`` forces it on
   a later one): before the counter exists, ids typed by hand into open PRs are the only ones it
   cannot otherwise see. A PR it could not read is named in ``unread``; the take still reserves.
4. Write the commit (``git commit-tree``, no checkout; author and committer fixed, so a clone with no
   git identity can write it) and push it with ``git push --porcelain``.
5. On any refusal, probe again rather than trust the reason's text. The tip moved: a race — back to
   1 after a short random wait, until 30 seconds have passed, then refuse (exit 2). The tip did not
   move: the refusal is the push's own (protected, permission, hook) — the fallback.

The fallback reads main, the counter if it could be fetched, and the open PRs; it pushes nothing and
exits 3 with ``why`` naming the cause. A ledger or archive on main that declares a newer major of
the format than ``ledgerboard.py`` reads (``Ledgerboard: N``) is not read: exit 2, no id (TD-133);
an open PR whose ledger does is named in ``unread`` — its ids are not seen. What it cannot see (an id given and not pushed, a PR opened
after the read) is left to the cadence check's ``ledger`` row, the backstop for every unreserved id.

The commit's subject is the id or the range (``TD-967..TD-968``) then ``[skip ci]``; its body says
``by`` (``--by``, else the Claude Code session's own id, ``CLAUDE_CODE_SESSION_ID``, the id its
transcript carries as ``sessionId``, else ``git config user.email`` — the same for every session on a machine — else unknown), ``branch`` (``--branch``, else the current
branch; left out when detached), ``take`` (a nonce, so no two takes are ever one commit) and ``host`` (left out in a cloud session or a container, and when the repo's ``docs/cadence.toml``
says ``ledger-ids-host = "off"``). The cadence check's ``ledger`` row and ``ledger.py --check --since`` decide on
them through ``judge()`` (TD-145):
``read_takes()`` maps each id to the take that gave it; a new id in a PR that no take gave fails, one
whose entry's ``**Taken by:**`` is not its take's ``by`` fails naming the ``by``, one with no
``**Taken by:**`` warns, and one whose take names a branch that is neither the default nor the PR's
warns. A reserved take prints the line to write in each entry's header: ``**Taken by:** <by>``.

``--claim TD-N`` takes exactly that id, for one the fallback printed and could not reserve: the same
push, refused with exit 2 when a take already gave TD-N or main holds it. ``LAST`` becomes the
higher of N and the tip's, so a later take still goes above both.

Output: the ids, one a line, and on stderr the ``**Taken by:**`` line when reserved; ``--json``:
``{ids, reserved, taken_by, why, unread, warnings}`` (``taken_by`` the take's ``by``, null when nothing was reserved). Exit 0 reserved
on the counter; 3 printed but not reserved (the fallback); 2 refused, nothing printed (a fetch of
``origin/<default>`` failed, so main cannot be the floor; or 30 seconds of a moving tip) — with
``--json`` the object still prints, its ``ids`` empty and ``why`` saying why. Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cadence_config as C  # noqa: E402  # sibling SYNC script: the one settings reader (§9.18)
import forge as F  # noqa: E402  # sibling SYNC script: the forge's open PRs and their head refs
import ledger as L  # noqa: E402  # sibling SYNC script: the ledger paths and the format's readers

COUNTER = "cadence/ledger-ids"
COUNTER_REF = f"refs/heads/{COUNTER}"
TRACKING_REF = f"refs/remotes/origin/{COUNTER}"
PR_NS = "refs/cadence/pr"          # where the PR read fetches heads; deleted afterwards
RACE_SECONDS = float(os.environ.get("LEDGER_IDS_RACE_SECONDS", "30"))   # tests shorten it
PR_BUDGET = 30.0
PR_LIMIT = 100
MAX_COUNT = 10
IDENTITY = {"GIT_AUTHOR_NAME": "cadence", "GIT_AUTHOR_EMAIL": "cadence@noreply",
            "GIT_COMMITTER_NAME": "cadence", "GIT_COMMITTER_EMAIL": "cadence@noreply"}
_QUIET = {"GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": os.environ.get(
    "GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=10")}


def git(root: Path, *args: str, timeout: float = 60, env: dict | None = None,
        stdin: str | None = None) -> subprocess.CompletedProcess:
    """One git call; a timeout or a missing git reads as a failed call (rc 124), never raises."""
    try:
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True,
                              timeout=max(timeout, 1), check=False, input=stdin,
                              env={**os.environ, **_QUIET, **(env or {})})
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(args, 124, "", str(e))


def ids_in(text: str | None) -> set[int]:
    """Every id a ledger or archive holds, as numbers: its headings and its table rows."""
    t = L.LB.COMMENT_RE.sub("", text or "")
    return L.LB.heading_nums(t) | {int(m.group(2)) for m in L.ROW_RE.finditer(t)}


def ids_at(root: Path, ref: str, ledger: str, archive: str) -> set[int]:
    """Every id the ledger and archive at ``ref`` hold, in whichever layout ``ref`` has them
    (``ledger.layout_at()``): a v1 pair's headings and rows, or a v2 directory's (TD-160) entry file
    names and the headings in them. A ref that cannot be listed holds none."""
    under = os.path.commonpath([PurePosixPath(p).parent.as_posix() for p in (ledger, archive)])
    io = L.git_io(root, ref, "" if under in (".", "") else under)   # both paths listed, wherever they are
    if io is None:
        return set()
    ls, read = io
    rel, arel = L.layout_at(ledger, archive, io)
    names = ls(rel)
    if names is None:
        out: set[int] = set()
        for p in (rel, arel or L.LB.archive_path(rel)):
            t = read(p)
            if t is not None:   # a newer major of the format is not read (TD-133): FormatTooNew
                out |= ids_in(L.N.checked(t, f"{ref}:{p}"))
        return out
    text, arch = L.LB.load(rel, ls, read)
    out = ids_in(L.N.checked(text, f"{ref}:{rel}")) | ids_in(L.N.checked(arch, f"{ref}:{rel}/archive"))
    sub = f"{rel.rstrip('/')}/{L.LB.LEDGER_ARCHIVE}"
    for n in names + (ls(sub) or []):
        m = L.LB.ENTRY_FILE_RE.match(n)
        if m:
            out.add(int(m.group(1)))
    return out


def tid(n: int) -> str:
    """§2.2's width: three digits, more past 999."""
    return f"TD-{n:03d}"


# -- the open PRs: one read, shared with check_cadence.py's ledger row -------------------------

def read_prs(root: Path, ledger: str, archive: str, budget: float = PR_BUDGET, base: bool = False,
             notes: list | None = None, be=None) -> tuple[dict, list]:
    """({n: {"head": ids, "base": ids | None, "sha": head}}, unread) for the forge's open PRs. Each head is
    fetched by the forge's head_ref into PR_NS (one fetch, head by head if the batch fails), and
    its ledger and archive read whole. With base, the ids at each head's merge-base with
    origin/<default> too (more history fetched where a shallow clone lacks it); None where there is
    none. unread names what was not read: a PR whose head could not be fetched, one past the
    budget, a list cut at the limit, a list that could not be had. With no forge to ask (none,
    other, no CLI) the read is skipped and ``notes`` says so; nothing is unread. ``be`` is a
    caller's own forge backend (check_cadence.py's), asked as it is instead of origin's."""
    say = notes.append if notes is not None else (lambda _m: None)
    end = time.monotonic() + budget
    if be is None:
        kind, host = F.origin_forge(root)
        if kind in ("none", "other"):
            say("open PRs not read: " + ("origin names no forge" if kind == "none"
                                         else F.forge_unread_line(host or "?")))
            return {}, []
        try:
            be = F.backend(root, cwd=str(root))
        except F.ForgeUnreadable as e:
            say(f"open PRs not read: {e}")
            return {}, []
    gone = be.missing()
    if gone:
        say(f"open PRs not read: {gone}")
        return {}, []
    try:
        listed = be.open_prs(PR_LIMIT, max(end - time.monotonic(), 1))
    except (F.ForgeUnreadable, ValueError, TypeError) as e:
        return {}, [f"the open PR list ({e})"]
    unread: list[str] = []
    if len(listed) >= PR_LIMIT:
        unread.append(f"the list (cut at {PR_LIMIT})")
    nums = [p["number"] for p in listed if p.get("number") is not None]
    local = {n: f"{PR_NS}/{n}" for n in nums}
    default = L.N.default_branch(root)
    out: dict = {}
    try:
        if nums:
            specs = [f"+{be.head_ref(n)}:{local[n]}" for n in nums]
            r = git(root, "fetch", "--quiet", "--no-tags", "origin", *specs,
                    timeout=end - time.monotonic())
            fetched = set(nums) if r.returncode == 0 else set()
            if r.returncode != 0:   # one PR closed between the list and the fetch aborts the batch
                for n in nums:
                    left = end - time.monotonic()
                    if left <= 0.5:
                        break
                    if git(root, "fetch", "--quiet", "--no-tags", "origin",
                           f"+{be.head_ref(n)}:{local[n]}", timeout=left).returncode == 0:
                        fetched.add(n)
            deepened = False
            for n in nums:
                if n not in fetched:
                    unread.append(be.ref(n))
                    continue
                try:
                    head_ids = ids_at(root, local[n], ledger, archive)
                except L.N.FormatTooNew:
                    unread.append(f"{be.ref(n)} (its ledger is in a newer format)")
                    continue
                rec = {"head": head_ids, "base": None,
                       "sha": git(root, "rev-parse", local[n]).stdout.strip()}
                if base:
                    mb = git(root, "merge-base", local[n], f"refs/remotes/origin/{default}")
                    if mb.returncode != 0 and not deepened and end - time.monotonic() > 1 and git(
                            root, "rev-parse", "--is-shallow-repository").stdout.strip() == "true":
                        deepened = True
                        git(root, "fetch", "--quiet", "--no-tags", "--unshallow", "origin",
                            f"+refs/heads/{default}:refs/remotes/origin/{default}",
                            *[f"+{be.head_ref(m)}:{local[m]}" for m in sorted(fetched)],
                            timeout=end - time.monotonic())
                        mb = git(root, "merge-base", local[n], f"refs/remotes/origin/{default}")
                    if mb.returncode == 0:
                        try:
                            rec["base"] = ids_at(root, mb.stdout.strip(), ledger, archive)
                        except L.N.FormatTooNew:
                            unread.append(f"{be.ref(n)} (its merge-base's ledger is in a newer format)")
                    else:
                        unread.append(f"{be.ref(n)} (no merge-base with {default})")
                out[n] = rec
    finally:
        for n in nums:
            git(root, "update-ref", "-d", local[n])
    return out, unread


# -- the take ------------------------------------------------------------------------------

def probe(root: Path) -> str | None:
    """The counter's sha on origin, "" when there is none, None when origin could not be asked."""
    r = git(root, "ls-remote", "--heads", "origin", COUNTER_REF, timeout=30)
    if r.returncode != 0:
        return None
    for line in r.stdout.splitlines():
        sha, _, ref = line.partition("\t")
        if ref.strip() == COUNTER_REF:
            return sha.strip()
    return ""


TAKE_RE = re.compile(r"^TD-(\d+)(?:\.\.TD-(\d+))? \[skip ci\]$")   # message()'s subject


def read_takes(root: Path, ref: str = TRACKING_REF) -> dict[int, dict] | None:
    """Every id the counter at ``ref`` gave, mapped to its take: ``sha``, ``date`` and the body's
    fields (``by``, ``branch``, ``take``, ``host``, those it has). The first take of an id wins, so
    a counter hand-edited to give one twice reads as the earlier. None when the log cannot be read;
    a commit whose subject is not a take's (a hand-made LAST) gives nothing."""
    r = git(root, "log", "--reverse", "--format=%H%x00%cI%x00%s%x00%b%x1e", ref)
    if r.returncode != 0:
        return None
    takes: dict[int, dict] = {}
    for rec in r.stdout.split("\x1e"):
        parts = rec.strip("\n").split("\x00", 3)
        if len(parts) != 4:
            continue
        sha, date, subject, body = parts
        m = TAKE_RE.match(subject.strip())
        if not m:
            continue
        lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
        fields = {k.strip(): v.strip() for k, sep, v in (ln.partition(":") for ln in body.splitlines()) if sep}
        for n in range(lo, hi + 1):
            takes.setdefault(n, {"sha": sha, "date": date, **fields})
    return takes


def counter_takes(root: Path) -> tuple[dict[int, dict] | None, str]:
    """(the counter's takes, fetched from origin into its tracking ref, ""), ``{}`` when origin has no
    counter (a repo with none is judged by nothing), or (None, why) when they could not be had."""
    tip = probe(root)
    if tip is None:
        return None, "the ledger-id counter was not read (origin did not answer)"
    if not tip:
        return {}, ""
    r = git(root, "fetch", "-q", "--no-tags", "origin", f"+{COUNTER_REF}:{TRACKING_REF}")
    takes = read_takes(root, TRACKING_REF) if r.returncode == 0 else None
    if takes is None:
        return None, "the ledger-id counter was not fetched"
    if not takes:
        return None, "the ledger-id counter holds no take it can read, so no id was judged against it"
    return takes, ""


def judge(new: set[int], takes: dict[int, dict], texts: list[str], branch: str, default: str
          ) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """TD-145: new ids against the counter's takes, for the cadence check's ``ledger`` row and
    ``ledger.py --check --since`` alike. ``texts`` are the ledger and archive holding the new entries,
    ``branch`` the one they are for, ``default`` the default branch. Returns (fails, warns), each a list
    of (kind, text). A new id no take gave fails (nobody handed it out); one below the counter's first
    take predates the counter and warns. An id a take gave: its entry's ``**Taken by:**`` naming another
    than the take's ``by`` fails, naming the ``by`` (the #2370 case — an id typed by hand that another
    session was later handed); none warns, except where the ledger declares a ``Fields:`` vocabulary,
    whose check would refuse a field the format does not define yet; a take naming a branch neither
    the default nor ``branch`` warns — a session may take an id on one branch for an entry it files in
    another PR."""
    LB = L.LB
    fails: list[tuple[str, str]] = []
    warns: list[tuple[str, str]] = []
    first = min(takes)
    nobody = sorted(n for n in new if n not in takes and n >= first)
    before = sorted(n for n in new if n not in takes and n < first)
    if nobody:
        fails.append(("id-untaken", f"{', '.join(map(tid, nobody))} handed out by nobody: the counter gave no such id — "
                      "take ids from the front end or ledger_next_id.py, and an id its fallback printed "
                      "with ledger_next_id.py --claim (cadence §2.10)"))
    if before:
        warns.append(("id-before-counter", f"{', '.join(map(tid, before))} below the counter's first take "
                      f"({tid(first)}): older than the counter, not judged against it"))
    taker: dict[int, str | None] = {}
    for t in texts:
        for e in LB.entries(t):
            taker.setdefault(int(e["id"][3:]), e["fields"].get("taken by"))
    writable = "taken by" in LB.CADENCE_FIELDS or not LB.declared(texts[0] if texts else "")[0]
    mismatch, missing, elsewhere = [], [], []
    for n in sorted(n for n in new if n in takes):
        by = (takes[n].get("by") or "").strip()
        if n in taker:
            if not LB.first_word(taker[n]):   # absent, or a value of only marks
                if writable and by:
                    missing.append(f"{tid(n)} (`**Taken by:** {by}`)")
            elif by and LB.first_word(taker[n]) != LB.first_word(by):
                mismatch.append(f"{tid(n)} was handed to {by}, not {LB.first_word(taker[n])}")
        took = (takes[n].get("branch") or "").strip()
        if took and took not in (default, branch or ""):
            elsewhere.append(f"{tid(n)} ({took})")
    if mismatch:
        fails.append(("id-taken-by", "; ".join(mismatch) + " — an id is the session's the counter handed it to; "
                      "take this entry its own (cadence §2.10)"))
    if missing:
        warns.append(("id-no-taken-by", f"no **Taken by:** on {', '.join(missing)} — write its take's by in the "
                      "header (cadence §2.10)"))
    if elsewhere:
        warns.append(("id-branch", f"taken for another branch: {', '.join(elsewhere)}"))
    return fails, warns


def read_last(root: Path, tip: str, warnings: list) -> int:
    r = git(root, "show", f"{tip}:LAST")
    raw = r.stdout.strip() if r.returncode == 0 else ""
    if raw.isascii() and raw.isdigit():
        return int(raw)
    warnings.append(f"the counter's LAST is {'not a number (' + raw[:20] + ')' if raw else 'absent'}"
                    " — ignored; the ledger, archive and --floor decide")
    return 0


def host_line(root: Path, warnings: list) -> str | None:
    if os.environ.get("CLAUDE_CODE_REMOTE") or any(
            os.path.exists(p) for p in ("/.dockerenv", "/run/.containerenv")):
        return None
    try:
        v, _ = C.resolve("ledger-ids-host", C.sources(str(root)))
    except C.ConfigError as e:
        warnings.append(f"host left out: {e}")
        return None
    if str(v or "").strip().lower() == "off":
        return None
    return socket.gethostname() or None


def message(ids: list[int], by: str, branch: str | None, host: str | None) -> str:
    subject = tid(ids[0]) if len(ids) == 1 else f"{tid(ids[0])}..{tid(ids[-1])}"
    # take: a nonce, so two takes from the same tip in the same second (fixed identity, same by,
    # branch and host) are never one commit — the second push would read "[up to date]" and exit 0
    body = ([f"by: {by}"] + ([f"branch: {branch}"] if branch else []) + ([f"host: {host}"] if host else [])
            + [f"take: {uuid.uuid4().hex}"])
    return f"{subject} [skip ci]\n\n" + "\n".join(body) + "\n"


def commit(root: Path, last: int, parent: str | None, msg: str) -> str | None:
    blob = git(root, "hash-object", "-w", "--stdin", stdin=f"{last}\n")
    if blob.returncode != 0:
        return None
    tree = git(root, "mktree", stdin=f"100644 blob {blob.stdout.strip()}\tLAST\n")
    if tree.returncode != 0:
        return None
    r = git(root, "commit-tree", tree.stdout.strip(), *(["-p", parent] if parent else []), "-F", "-",
            stdin=msg, env=IDENTITY)
    return r.stdout.strip() if r.returncode == 0 else None


def pushed(out: str) -> bool:
    """The push moved the counter: its porcelain line's flag is `*` (new) or ` ` (fast-forward),
    never `=` (up to date: somebody else's identical commit is already there)."""
    return any(COUNTER_REF in ln and ln[:1] in ("*", " ") for ln in out.splitlines())


def porcelain_line(out: str, err: str) -> str:
    """The push's own line for the counter (``!\t<src>:<dst>\t[rejected] (why)``), else its error."""
    for line in out.splitlines():
        if COUNTER_REF in line:
            return line.strip()
    lines = [ln.strip() for ln in (err or out).splitlines() if ln.strip()]
    return lines[-1] if lines else "push failed"


def take(root: Path, a: argparse.Namespace) -> tuple[int, dict]:
    res: dict = {"ids": [], "reserved": False, "taken_by": None, "why": "", "unread": [], "warnings": []}
    warnings = res["warnings"]
    default = L.N.default_branch(root)
    main_ref = f"refs/remotes/origin/{default}"
    by = (a.by or os.environ.get("CLAUDE_CODE_SESSION_ID", "").strip()
          or git(root, "config", "user.email").stdout.strip() or "unknown")
    branch = getattr(a, "branch", None) or git(root, "branch", "--show-current").stdout.strip() or None
    start = time.monotonic()
    written: set[str] = set()   # this run's own take commits: a push that timed out but landed

    def fallback(why: str, counter_fetched: bool) -> tuple[int, dict]:
        known = ids_at(root, main_ref, a.ledger, a.archive)
        if counter_fetched:
            known.add(read_last(root, TRACKING_REF, []))
        prs, unread = read_prs(root, a.ledger, a.archive, notes=warnings)
        for rec in prs.values():
            known |= rec["head"]
        first = getattr(a, "claim", None) or max([*known, a.floor or 0]) + 1
        res.update(ids=list(range(first, first + a.count)), reserved=False, why=why, unread=unread)
        return 3, res

    while True:
        tip = probe(root)
        if tip is None:
            r = git(root, "fetch", "--quiet", "--no-tags", "origin", f"+refs/heads/{default}:{main_ref}")
            if r.returncode != 0:
                res["why"] = f"could not fetch origin/{default}: {porcelain_line('', r.stderr)}"
                return 2, res
            return fallback("origin could not be asked about the counter (ls-remote failed)", False)
        specs = [f"+refs/heads/{default}:{main_ref}"] + ([f"+{COUNTER_REF}:{TRACKING_REF}"] if tip else [])
        r = git(root, "fetch", "--quiet", "--no-tags", "origin", *specs)
        if r.returncode != 0 and tip and probe(root) not in (None, tip) \
                and time.monotonic() - start <= RACE_SECONDS:
            continue   # the counter moved (or went) between the probe and the fetch: probe again
        if r.returncode != 0:
            res["why"] = f"could not fetch origin/{default}: {porcelain_line('', r.stderr)}"
            return 2, res
        parent = None
        known = ids_at(root, main_ref, a.ledger, a.archive)
        if tip:
            parent = git(root, "rev-parse", "--verify", "-q", TRACKING_REF).stdout.strip() or None
            known.add(read_last(root, parent or tip, warnings))
        res["unread"] = []
        if not tip or a.prs:
            prs, res["unread"] = read_prs(root, a.ledger, a.archive, notes=warnings)
            for rec in prs.values():
                known |= rec["head"]
        first = max([*known, a.floor or 0]) + 1
        ids = list(range(first, first + a.count))
        last = ids[-1]
        claim = getattr(a, "claim", None)
        if claim:
            given = read_takes(root, parent) if parent else {}
            if given is None:
                res["why"] = "the counter's log could not be read, so TD-N cannot be judged free"
                return 2, res
            if claim in given and given[claim]["sha"] in written:
                res.update(ids=[claim], reserved=True, taken_by=by, why="")
                return 0, res
            if claim in given:
                res["why"] = f"{tid(claim)} was already handed to {given[claim].get('by', 'unknown')}"
                return 2, res
            if claim in ids_at(root, main_ref, a.ledger, a.archive):
                res["why"] = f"{tid(claim)} is already on origin/{default}"
                return 2, res
            ids, last = [claim], max(claim, read_last(root, parent, []) if parent else 0)
        sha = commit(root, last, parent, message(ids, by, branch, host_line(root, warnings)))
        if sha is not None:
            written.add(sha)
        if sha is None:
            res["why"] = "could not write the counter's commit"
            res["ids"] = ids
            return 3, res
        # A push that timed out here but landed there reads as refused; the probe below then sees
        # the tip moved and retries — one id is burnt, never given twice.
        p = git(root, "push", "--porcelain", "origin", f"{sha}:{COUNTER_REF}")
        if p.returncode == 0 and pushed(p.stdout):
            git(root, "update-ref", TRACKING_REF, sha)
            res.update(ids=ids, reserved=True, taken_by=by, why="")
            return 0, res
        why = porcelain_line(p.stdout, p.stderr)
        now = probe(root)
        if now is None:
            return fallback(f"the push was refused and origin could not be asked again: {why}", bool(tip))
        if now == (parent or ""):
            return fallback(f"the push was refused with the counter unmoved: {why}", bool(tip))
        if time.monotonic() - start > RACE_SECONDS:
            res.update(ids=[], why=f"the counter kept moving for {RACE_SECONDS:g}s; nothing taken")
            return 2, res
        time.sleep(random.uniform(0.05, 0.5))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--count", type=int, default=1, help=f"how many ids, 1 to {MAX_COUNT}")
    ap.add_argument("--by", help="who takes them (a front end passes its caller's name); default the "
                                       "Claude Code session's id, else git config user.email")
    ap.add_argument("--branch", help="the branch the ids are for, when not the current one")
    ap.add_argument("--floor", type=int, help="a front end's own last-given id: every id is above it")
    ap.add_argument("--prs", action="store_true", help="read the open PRs on a later take too")
    ap.add_argument("--ledger", default=L.LEDGER_REL)
    ap.add_argument("--archive", default=L.ARCHIVE_REL)
    ap.add_argument("--claim", metavar="TD-N",
                    help="take exactly this id (one the fallback printed), if no take gave it and main lacks it")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    if a.claim is not None:
        m = re.fullmatch(r"(?:TD-)?(\d+)", a.claim.strip())
        if not m or int(m.group(1)) < 1:
            ap.error("--claim is an id: TD-N")
        if a.count != 1 or a.floor is not None or a.prs:
            ap.error("--claim takes one id; --count, --floor and --prs do not apply")
        a.claim = int(m.group(1))
    if not 1 <= a.count <= MAX_COUNT:
        ap.error(f"--count is 1 to {MAX_COUNT}")
    if a.floor is not None and a.floor < 0:
        ap.error("--floor is a number of 0 or more")
    top = git(Path.cwd(), "rev-parse", "--show-toplevel")
    if top.returncode != 0 or not top.stdout.strip():
        print("ledger_next_id: not inside a git work tree", file=sys.stderr)
        return 2
    try:
        rc, res = take(Path(top.stdout.strip()), a)
    except L.N.FormatTooNew as e:   # main's ledger: no id can be judged free (TD-133)
        rc, res = 2, {"ids": [], "reserved": False, "taken_by": None, "why": f"not read — {e}", "unread": [], "warnings": []}
    if rc == 2:
        res["ids"] = []
    res["warnings"] = list(dict.fromkeys(res["warnings"]))   # a retried pass repeats its warnings
    if a.json:
        print(json.dumps({**res, "ids": [tid(n) for n in res["ids"]]}, indent=1))
    else:
        for n in res["ids"]:
            print(tid(n))
        if res["taken_by"]:
            print(f"ledger_next_id: write `**Taken by:** {res['taken_by']}` in each entry's header (cadence §2.10)",
                  file=sys.stderr)
        for w in res["warnings"]:
            print(f"ledger_next_id: {w}", file=sys.stderr)
        if res["unread"]:
            print("ledger_next_id: open PRs not read: " + ", ".join(res["unread"]), file=sys.stderr)
        if rc == 3:
            print(f"ledger_next_id: NOT reserved — {res['why']}", file=sys.stderr)
        elif rc == 2:
            print(f"ledger_next_id: refused — {res['why']}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
