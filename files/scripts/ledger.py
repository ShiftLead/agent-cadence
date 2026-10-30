#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/ledger.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""What in the TD ledger may be picked now, and what is blocked on what (TD-064).

    ledger.py --pickable [--ledger PATH] [--archive PATH] [--json]
    ledger.py --summary | --split

An entry may carry one optional field, between **Status:** and **Location:** (cadence.md §2):

    **Blocked by:** TD-047, TD-042
    **Blocked by:** decision (person) — docs/user_attention.md, 2026-09-25 item

Comma-separated entry IDs, then optionally ``decision (<who>)`` — last, because the pointer
after it runs to the end of the line and may hold anything. An ID may name another repo's entry
(TD-071), ``<repo>#TD-NNN`` — ``<repo>`` a roster path's basename, or ``owner/name`` (its origin)
when basenames collide:

    **Blocked by:** agent-cadence#TD-036, TD-120

It resolves through this machine's roster (cadence.md §9, ``$AGENT_CADENCE_REG_DIR`` honoured) to
that clone's ledger and archive, read from its ``origin/<default>`` when the ref exists, else its
working tree; it lifts when the entry is in that archive. Anything it cannot resolve keeps the block. **Pickable is derived, never written:** an entry is pickable when
it has no Blocked by field, or every entry it names is archived and it names no decision.
So archiving a blocker makes its dependents pickable with no further edit. A written
``**Pickable:**`` line is only a field: it never overrides the derived one, and a disagreement is flagged.

An entry may also carry ``**Type:** debt | feature`` (cadence.md §2.11); no field reads as debt.
Within one Priority, debt is picked before features.

``--pickable`` prints the pick order — the rank (ledgerboard SPEC *The rank*, TD-119): entries fall into
cards (joined by Blocked by), cards go by key, and within a card an entry follows what it is blocked by. An
entry's key is its line in the rank file beside the ledger (``<ledger stem>_rank.yml``,
``docs/technical_debt_rank.yml``) when it has one, else Priority (High, Medium, Low, then anything else),
then Type (debt before feature), then id; a card's key is its best lined key, else its best one — then
the blocked entries with their blockers, then flags: a rank file line it cannot read, a blocker that names no
entry in the ledger or the archive, an item the field cannot read, a Type it does not know
(read as debt), and a block whose
blockers are all archived (pickable now; the field can go). Which entries a given picker
also excludes (a sibling's lease, a brief's own rules) is the picker's business, not this.
``--list`` prints every entry the filters keep, in the same order; ``--where`` terms are ANDed,
match the first word case-insensitively, and ``FIELD=`` keeps an entry without the field.
``type`` and ``priority`` match the derived value (no Type is debt). ``--counts`` counts per value.
What to *do* with a field (lanes, routing) is the orchestrator's, never this script's.

``--check`` prints only the flags and exits 1 when an error stands (TD-073) — every ⚠: an unknown
Type, a value outside a declared vocabulary, a Blocked by item it cannot read or resolve, a
``Fields:`` line it cannot read. ℹ lines stay information. ``--check --since REF`` judges an edit,
not the ledger: an entry counts only when its header block differs from the one at REF (or is new),
and a ``Fields:`` flag only when the declaration changed, so a ledger that was never clean passes
and the edit that adds one more bad field does not. On a counted entry two more things are errors:
a written Pickable that disagrees with the derived one, and — when the ledger declares vocabularies
at all — a header field that is neither the cadence's nor declared. Standing flags are counted, not
printed. The ids the edit adds (in the ledger or archive, in neither at REF) are judged against the
counter's takes on origin, as the cadence check's ``ledger`` row judges them (TD-145, cadence.md §2.10):
an id no take gave, and one whose ``**Taken by:**`` is not its take's ``by``, are errors; an id older
than the counter, an entry with no ``**Taken by:**``, a take for another branch than this one or the
default, and a counter origin did not give are ℹ lines. ``--json``: ``{"flags": [{"level": error|info, "id", "field", "kind", "text", "standing"}],
"errors": N}`` — key on ``kind`` and ``field``, never on the sentence. Kinds: fields-decl, below-header,
type, vocabulary, blocked-item, cross-repo, blocked-unknown, blockers-archived, pickable-disagrees,
undeclared-field, rank (a rank file line), prose-wait (TD-166: a header field that names an id after *waits on/for* or *blocked by*
while its Blocked by does not), no-ask (TD-122: an entry waiting on the person — Owner: person or a
decision holder's name, decision (<who>), an **Answers:** line — with no **Ask:** line in its body), and the ids' id-untaken, id-taken-by, id-before-counter,
id-no-taken-by, id-branch, id-counter; with ``--since``, archive-loss (an id archived at REF that is now in
neither the ledger nor the archive, TD-179) and archive-reopened (ℹ: one back in the ledger). ``check_cadence.py``'s ``ledger`` row runs the same field check on a PR's ledger edit.

``--summary`` prints the summary table a v2 ledger does not store (TD-160): one row per entry in
pick order, its state derived (pickable, or what blocks it). ``--split`` migrates a v1 ledger to v2:
ledgerboard's ``split()`` writes ``docs/ledger/`` (``README.md``, one ``TD-NNN.md`` per entry,
``archive/``) beside the ledger, moves the rank file to ``docs/ledger/rank.yml``, and removes the two v1
files — refused, with nothing written, when ``docs/ledger/`` exists or the round trip would not hold.
Its links are rewritten for their new place (TD-176), entry anchors into the v1 files pointed at the
entries' files there and in the repo's other Markdown, and the archive's summary kept frozen (TD-185).
Commit the result as its own PR.

The ledger is a v1 file or a v2 directory (ledgerboard SPEC *The ledger as a directory*, TD-160), and
every read goes through ledgerboard's ``load()``: here with the file system, at a revision (``--since``,
a roster repo's ``origin/<default>``) with ``git_io()`` — one ``ls-tree``, one ``cat-file --batch`` per
directory. A v2 ledger that ``v2_problems()`` faults is not read (exit 2). Defaults: ``docs/ledger/``
when that directory exists, else ``docs/technical_debt.md`` and ``docs/technical_debt_archive.md``, at
the top of the git work tree the command runs in; ``--archive`` applies to a v1 ledger only. Read-only, and offline except where ``--check --since``'s edit
adds an id: then it asks origin for the counter (``git ls-remote``, and a fetch of its tracking ref). Exit 0 (``--check``: 1 on an error);
2 when the ledger, or ``--since``'s ref, cannot be read or the arguments are unusable, or the
ledger or archive declares a newer major of the format than ``ledgerboard.py`` reads
(``Ledgerboard: N``, TD-133) — then nothing was read. A cross-repo blocker whose ledger declares
one stays blocked, and says why. A detector,
never a gate (cadence.md §7): ``--check`` is what lets a caller choose to gate on it.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledgerboard as LB  # noqa: E402  # sibling SYNC file: the ledger format, defined once (ShiftLead/ledgerboard)
import nudge_user_attention as N  # noqa: E402  # sibling SYNC script: the roster, origin and default-branch readers (§9) — the resolver only
from ledgerboard import (  # noqa: E402,F401  # re-exported: readers and tests reach them as ledger.<name>
    BLOCKED_RE,
    CADENCE_FIELDS,
    COMMENT_RE,
    DECISION_RE,
    EDIT_ERRORS,
    FIELD_RE,
    FIELDS_DECL_RE,
    HEADING_RE,
    ID_ITEM_RE,
    PRIORITIES,
    PRIORITY_RE,
    ROW_RE,
    SECTION_RE,
    TYPE_RE,
    TYPES,
    WORD_RE,
    XREPO_ITEM_RE,
    _num,
    declared,
    entries,
    field_key,
    first_word,
    header_block,
    parse_blocked,
)
from ledgerboard import heading_nums as _heading_nums  # noqa: E402

LEDGER_REL, ARCHIVE_REL = "docs/technical_debt.md", "docs/technical_debt_archive.md"
LEDGER_DIR_REL = "docs/ledger"  # a v2 ledger (TD-160): one TD-NNN.md per entry, read through LB.load()
ALIASES = ("type", "owner", "kind")  # --type X is --where type=X, and so on
RESOLVED_RE = re.compile(r"^\*\*Resolved:\*\*\s*(\d{4}-\d{2}-\d{2})", re.M)   # an archived entry's date (TD-152)


GIT_TIMEOUT = float(os.environ.get("LEDGER_GIT_TIMEOUT", "10"))  # s per git call into another clone; tests shorten it


def _git(root: Path, *args: str) -> str | None:
    """stdout of one git call in another clone, or None on any failure — a timeout included, so one
    hung roster repo leaves its items unresolved (blocked, flagged) instead of failing the run."""
    try:
        r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, timeout=GIT_TIMEOUT, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.decode("utf-8", errors="replace") if r.returncode == 0 else None


def fs_io() -> tuple[LB.Ls, LB.Read]:
    """(ls, read) over the file system, as ``LB.load()`` takes them."""
    def ls(path: str) -> list[str] | None:
        p = Path(path)
        return sorted(x.name for x in p.iterdir() if x.is_file()) if p.is_dir() else None

    def read(path: str) -> str | None:
        try:
            return Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
    return ls, read


def git_io(root: Path, ref: str, under: str = "") -> tuple[LB.Ls, LB.Read] | None:
    """(ls, read) over the tree at ``ref`` in ``root`` (paths relative to its top), or None when the
    tree cannot be listed: one ``git ls-tree`` of ``under``, and a read fetches every blob of the read
    file's directory in one ``git cat-file --batch``. Newlines read as ``read_text()`` gives them."""
    out = _git(root, "ls-tree", "-r", "-z", "--full-tree", ref, *([under] if under else []))
    if out is None:
        return None
    blobs: dict[str, str] = {}
    for rec in out.split("\0"):
        meta, tab, path = rec.partition("\t")
        if tab and meta.split()[1:2] == ["blob"]:
            blobs[path] = meta.split()[2]
    cache: dict[str, str | None] = {}

    def ls(path: str) -> list[str] | None:
        pre = f"{path.rstrip('/')}/" if path else ""
        if path in blobs or not any(p.startswith(pre) for p in blobs):
            return None
        return sorted(p[len(pre):] for p in blobs if p.startswith(pre) and "/" not in p[len(pre):])

    def read(path: str) -> str | None:
        if path not in blobs:
            return None
        if path not in cache:
            d = path.rpartition("/")[0]
            want = [p for p in blobs if p.rpartition("/")[0] == d and p not in cache]
            try:
                r = subprocess.run(["git", "-C", str(root), "cat-file", "--batch"], capture_output=True,
                                   input="".join(blobs[p] + "\n" for p in want).encode(), timeout=GIT_TIMEOUT,
                                   check=False)
                data = r.stdout if r.returncode == 0 else b""
            except (OSError, subprocess.TimeoutExpired):
                data = b""
            at = 0
            for p in want:
                nl = data.find(b"\n", at)
                head = data[at:nl].split() if nl >= 0 else []
                if len(head) != 3 or head[1] != b"blob":
                    cache[p] = None
                    break
                size = int(head[2])
                body = data[nl + 1: nl + 1 + size]
                cache[p] = body.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
                at = nl + 1 + size + 1
        return cache.get(path)
    return ls, read


def read_pair(ledger: str, archive: str | None, io: tuple[LB.Ls, LB.Read]) -> tuple[str | None, str]:
    """(ledger text, archive text) of a v1 file (its archive ``archive``, else the one beside it) or a
    v2 directory, through ``io``; the ledger's text is None when there is no ledger at all."""
    ls, read = io
    if ls(ledger) is not None:
        return LB.load(ledger, ls, read)
    text = read(ledger)
    return text, (read(archive or LB.archive_path(ledger)) or "") if text is not None else ""


def ledger_at(root: Path, io: tuple[LB.Ls, LB.Read]) -> str:
    """The ledger of the repo ``io`` reads, relative to its top: ``docs/ledger/`` when it is a directory, else v1's file."""
    return LEDGER_DIR_REL if io[0](LEDGER_DIR_REL) is not None else LEDGER_REL


def layout_at(rel: str, arel: str | None, io: tuple[LB.Ls, LB.Read]) -> tuple[str, str | None]:
    """(ledger, archive) as the tree ``io`` reads holds them: ``rel`` and ``arel`` when ``rel`` is there,
    else the other layout's beside it — a split came between (TD-160): a v1 file's ``ledger/``
    directory (its archive inside it, so None), or a directory's v1 file and archive."""
    if io[0](rel) is not None or io[1](rel) is not None:
        return rel, arel
    here = PurePosixPath(rel).parent
    if rel.endswith(".md"):
        return (here / PurePosixPath(LEDGER_DIR_REL).name).as_posix(), None
    led, arch = ((here / PurePosixPath(n).name).as_posix() for n in (LEDGER_REL, ARCHIVE_REL))
    return led, arch


def v2_unread(ledger: str, io: tuple[LB.Ls, LB.Read]) -> str:
    """Why a v2 ledger may not be read as its files say (``LB.v2_problems()``), or "" (a v1 file: always "")."""
    return "; ".join(LB.v2_problems(ledger, *io))


def _resolved_dates(arch: str | None) -> dict[int, str]:
    """Each archived entry's ``**Resolved:** YYYY-MM-DD`` date (TD-152), its body found as ledgerboard
    finds one (``HEADING_RE`` to the next ``SECTION_RE``); an entry with no such line is left out."""
    text = LB.COMMENT_RE.sub("", arch or "")
    out: dict[int, str] = {}
    for m in LB.HEADING_RE.finditer(text):
        nxt = LB.SECTION_RE.search(text, m.end())
        d = RESOLVED_RE.search(text, m.end(), nxt.start() if nxt else len(text))
        if d:
            out.setdefault(_num(m.group(1)), d.group(1))
    return out


class Roster:
    """Resolves ``<repo>#TD-NNN`` through this machine's roster; each repo is read once, and only when asked."""

    def __init__(self) -> None:
        self._roots: list[Path] | None = None
        self._read: dict[Path, dict] = {}

    def _find(self, repo: str) -> tuple[Path | None, str]:
        if self._roots is None:
            reg = N.read_registry()
            self._roots = reg or []
            if reg is None:
                return None, "no roster on this machine"
        if "/" in repo:
            hits = [r for r in self._roots
                    if (N._local_origin(r) or "").rstrip("/").lower().endswith("/" + repo.lower())]
        else:
            hits = [r for r in self._roots if r.name.lower() == repo.lower()]
        if not hits:
            return None, "not on this machine's roster"
        if len(hits) > 1:
            return None, (f"{len(hits)} roster repos are named {repo} — write owner/name")
        return hits[0], ""

    def _repo(self, root: Path) -> dict:
        if root not in self._read:
            branch = N.default_branch(root)
            ref = f"origin/{branch}"
            has_ref = _git(root, "rev-parse", "--verify", "-q", ref) is not None

            if has_ref:   # a hung or failed git call: unreadable, the block stays
                io = git_io(root, ref, "docs") or (lambda p: None, lambda p: None)
            else:
                fls, fread = fs_io()
                io = (lambda p: fls(str(root / p))), (lambda p: fread(str(root / p)))
            rel = ledger_at(root, io)
            led, arch = read_pair(rel, ARCHIVE_REL if rel == LEDGER_REL else None, io)
            newer = v2_unread(rel, io)
            if newer:
                led, arch = None, None
            try:   # a ledger in a newer format is not read at all (TD-133): the block stays
                N.checked(led or "", rel)
                N.checked(arch or "", ARCHIVE_REL if rel == LEDGER_REL else f"{rel}/{LB.LEDGER_ARCHIVE}")
            except N.FormatTooNew as e:
                newer, led, arch = str(e), None, None
            self._read[root] = {"source": ref if has_ref else "working tree", "readable": led is not None, "rel": rel,
                                "newer": newer, "live": _heading_nums(led), "archived": _heading_nums(arch),
                                "resolved": _resolved_dates(arch)}
        return self._read[root]

    def state(self, root: Path, tid: str, repo: str | None = None) -> dict:
        """{state: archived | open | unresolved, resolved: the archive's **Resolved:** date or None, source,
        why, missing: the ledger and archive were read and neither has it (TD-153)} for ``tid`` in the ledger and archive of ``root`` (origin/<default> where fetched, else its
        working tree) — a board's own repo for a bare ``TD-NNN`` (TD-152), a roster repo for ``<repo>#``."""
        info = self._repo(root)
        out = {"state": "unresolved", "resolved": None, "source": info["source"], "why": "", "missing": False}
        n = _num(tid)
        if info["newer"]:
            out["why"] = f"{root} ({info['source']}): {info['newer']}"
        elif not info["readable"]:
            out["why"] = f"no readable {info['rel']} in {root} ({info['source']})"
        elif n in info["archived"]:
            out.update(state="archived", resolved=info["resolved"].get(n))
        elif n in info["live"]:
            out["state"] = "open"
        else:
            out.update(missing=True,
                       why=f"{repo or root.resolve().name} has no {tid} in its ledger or archive ({info['source']})")
        return out

    def resolve(self, item: str) -> dict:
        """{item, repo, root, source, state: archived | open | unresolved, resolved, why} for one ``<repo>#TD-NNN``."""
        repo, tid = XREPO_ITEM_RE.match(item).groups()
        out = {"item": item, "repo": repo, "root": None, "source": None, "state": "unresolved", "resolved": None,
               "why": ""}
        root, why = self._find(repo)
        if root is None:
            out["why"] = why
            return out
        st = self.state(root, tid, repo)
        out.update(root=str(root), source=st["source"], state=st["state"], why=st["why"], resolved=st["resolved"])
        return out


def pickable(ledger: str, archive: str, roster: Roster | None = None, undeclared: bool = False,
             rank_text: str | None = None) -> dict:
    """ledgerboard's pickable, in rank order, with this machine's roster resolving ``<repo>#TD-NNN`` items."""
    return LB.pickable(ledger, archive, (roster or Roster()).resolve, undeclared, rank_text=rank_text)


def check(ledger: str, archive: str, old: str | None = None, roster: Roster | None = None,
          rank_text: str | None = None) -> list[dict]:
    """ledgerboard's check (--check's flags, the rank file's too), with this machine's roster resolving cross-repo items."""
    return LB.check(ledger, archive, old, (roster or Roster()).resolve, rank_text=rank_text)


# TD-166: a wait on another entry belongs in Blocked by (cadence.md §2.4), where --pickable resolves it; one
# written in prose — a Status's "waits on TD-N", a Waits: line naming one — is read by nobody, so the
# entry keeps waiting once that entry is archived. Read through ledgerboard's header block (§2.12).
WAIT_PHRASE_RE = re.compile(r"\b(?:waits?|waiting)\s+(?:on|for)\b|\bblocked\s+by\b", re.I)
WAIT_ID_RE = re.compile(r"(?<![\w#/.-])(?:(?P<repo>[\w.-]+(?:/[\w.-]+)?)#)?TD-0*(?P<n>\d+)\b")
NO_WAIT_FIELDS = {"blocked by", "part of", "related", "location", "taken by", "added", "title"}


def _wait_key(repo: str | None, n: str) -> tuple[str, int]:
    return ((repo or "").lower(), int(n))


def prose_waits(ledger: str, archive: str = "") -> dict[str, list[tuple[str, str]]]:
    """id -> [(field, the id as written)] for each id an entry's header names as a wait — after *waits
    on/for* or *blocked by* in any field but Blocked by, up to the end of that clause — that its Blocked
    by does not name. A Waits: line's event may cite an entry for context; only the phrase makes it a wait. A bare id names an entry here or in the archive, or it is someone
    else's written without its repo (*shiftlead TD-1014*) and not read. TD-172: Blocked by's own decision pointer
    (what follows ``decision (<who>)``, which ``parse_blocked()`` never reads) is read too — every id in it that
    the field's items do not name, phrase or none, as field ``blocked by``."""
    known = LB.heading_nums(ledger) | LB.heading_nums(archive)
    out: dict[str, list[tuple[str, str]]] = {}
    for e in LB.entries(ledger):
        ids, _, _ = LB.parse_blocked(e["fields"].get("blocked by") or "")
        named = {_wait_key(m["repo"], m["n"]) for i in ids if (m := WAIT_ID_RE.fullmatch(i.strip()))}
        named.add(_wait_key(None, e["id"][3:]))
        for field, value in e["fields"].items():
            if field == "blocked by":
                d = LB.DECISION_RE.search(value)
                spans = [value[d.end():]] if d else []
            elif field in NO_WAIT_FIELDS:
                continue
            else:
                spans = [re.split(r"[.;:](?:\s|$)|\(|\)", value[m.end():], maxsplit=1)[0] for m in WAIT_PHRASE_RE.finditer(value)]
            for span in spans:
                for m in WAIT_ID_RE.finditer(span):
                    if m["repo"] is None and int(m["n"]) not in known:
                        continue
                    if _wait_key(m["repo"], m["n"]) not in named and (field, m[0]) not in out.get(e["id"], []):
                        out.setdefault(e["id"], []).append((field, m[0]))
    return out


def prose_wait_flags(ledger: str, archive: str, old: str | None = None) -> list[dict]:
    """--check's ℹ per prose wait (kind prose-wait); with ``old``, one already there at REF is standing."""
    then = prose_waits(old, archive) if old is not None else {}
    return [{"level": "info", "id": tid, "field": field, "kind": "prose-wait", "standing": (field, ref) in then.get(tid, []),
             "text": (f"ℹ {tid}: its Blocked by's decision pointer names {ref}, which no item of it names — move it "
                      f"before the decision ({ref}, decision (…) — …), where --pickable sees it archived (cadence.md §2.4)"
                      if field == "blocked by" else
                      f"ℹ {tid}: its {field.capitalize()} field waits on {ref}, which its Blocked by does not name — "
                      "name it in Blocked by, where --pickable sees it archived (cadence.md §2.4)")}
            for tid, waits in prose_waits(ledger, archive).items() for field, ref in waits]


# TD-122: an entry that waits on the person carries an **Ask:** line in its body, never its header
# (cadence.md §2.3, TD-121) — one with Owner: <person>, Blocked by: decision (<person>) or an
# **Answers:** line. A person is the word `person` or a name some entry's decision (<who>) names,
# here or in the archive: the ledger declares no list of people, and a lane (grinder) is never one.
ASK_RE = re.compile(r"^\*\*Ask:\*\*", re.M)
ANSWERS_RE = re.compile(r"^\*\*Answers:\*\*", re.M)


def _bodies(text: str) -> dict[str, str]:
    """id -> the entry's text below its heading, comments dropped (ledgerboard's entries() bounds)."""
    text = LB.COMMENT_RE.sub("", text or "")
    out = {}
    for m in LB.HEADING_RE.finditer(text):
        nxt = LB.SECTION_RE.search(text, m.end())
        out[m.group(1)] = text[m.end(): nxt.start() if nxt else len(text)]
    return out


def ask_missing(ledger: str, archive: str = "") -> dict[str, str]:
    """id -> why the entry waits on the person (``Owner: person``, ``decision (<who>)``, ``Answers:``), for
    each one with no ``**Ask:**`` line below its header block; the why ends ``; its Ask: is in the header``
    when that is where it is."""
    people = {"person"}
    for e in LB.entries(ledger) + LB.entries(archive):
        people.update(w.lower() for w in LB.parse_blocked(e["blocked_raw"] or "")[1])
    bodies = _bodies(ledger)
    out = {}
    for e in LB.entries(ledger):
        body = bodies.get(e["id"], "")
        owner = LB.first_word(e["fields"].get("owner"))
        who = LB.parse_blocked(e["blocked_raw"] or "")[1]
        why = (f"Owner: {owner}" if owner in people else f"decision ({who[0]})" if who
               else "Answers:" if ANSWERS_RE.search(body) or "answers" in e["fields"] else None)
        if why is None:
            continue
        head = re.split(r"\n[ \t\r]*\n", body.lstrip("\n"), maxsplit=1)
        if ASK_RE.search(head[1] if len(head) > 1 else ""):
            continue
        out[e["id"]] = why + ("; its Ask: is in the header" if "ask" in e["fields"] else "")
    return out


def ask_flags(ledger: str, archive: str, old: str | None = None) -> list[dict]:
    """ℹ per entry waiting on the person with no Ask: line (kind no-ask); with ``old``, one whose text is
    unchanged since REF is standing — the cadence check's ``ledger`` row warns on the rest, never fails."""
    then = _bodies(old) if old is not None else {}
    now = _bodies(ledger)
    return [{"level": "info", "id": tid, "field": "ask", "kind": "no-ask", "standing": then.get(tid) == now.get(tid),
             "text": f"ℹ {tid} waits on the person ({why}) with no **Ask:** line in its body — one sentence a cold "
                     "reader can decide from (cadence.md §2.3)"}
            for tid, why in ask_missing(ledger, archive).items()]


def archive_loss_flags(ledger: str, archive: str, old_ledger: str | None, old_archive: str | None) -> list[dict]:
    """TD-179: the archive only grows (cadence.md §2.8). An id with a ``## TD-NNN:`` heading in the
    archive at REF and in neither the ledger nor the archive now is lost — an error (kind archive-loss),
    one flag naming every such id; an id gone from the archive into the ledger is reopened, ℹ
    (kind archive-reopened). Headings, not files, so a ``--split`` between REF and now loses nothing,
    and an emptied or deleted ``archive/TD-NNN.md`` is a loss like a heading cut from a v1 archive."""
    was = LB.heading_nums(old_archive)
    if not was:
        return []
    arch, live = LB.heading_nums(archive), LB.heading_nums(ledger)
    lost, back = sorted(was - arch - live), sorted((was - arch) & live)
    ids = lambda ns: ", ".join(f"TD-{n:03d}" for n in ns)  # noqa: E731
    out = []
    if lost:
        out.append({"level": "error", "id": None, "field": None, "kind": "archive-loss", "standing": False,
                    "text": f"⚠ the archive lost {ids(lost)}: an archived entry is never removed, so restore "
                            "it from the ref the edit started at (cadence.md §2.8)"})
    if back:
        out.append({"level": "info", "id": None, "field": None, "kind": "archive-reopened", "standing": False,
                    "text": f"ℹ {ids(back)} left the archive for the ledger: reopened, not lost"})
    return out


def _rel(ledger: Path) -> tuple[Path | None, str, str]:
    """(the work tree's top, ``ledger`` relative to it, why not)."""
    top = _git(ledger.parent, "rev-parse", "--show-toplevel")
    if top is None:
        return None, "", f"{ledger} is not in a git work tree"
    root = Path(top.strip())
    try:
        return root, ledger.resolve().relative_to(root.resolve()).as_posix(), ""
    except ValueError:
        return None, "", f"{ledger} is outside {root}"


def _at_ref(ledger: Path, ref: str, archive: Path | None = None) -> tuple[tuple[str, str] | None, str]:
    """((the ledger's text, its archive's) at ``ref``, why not) — a v1 file or a v2 directory, as it
    was at ref. A ledger that did not exist at ref is ("", "") — every entry is new."""
    root, rel, why = _rel(ledger)
    if root is None:
        return None, why
    if _git(root, "rev-parse", "--verify", "-q", f"{ref}^{{commit}}") is None:
        return None, f"no commit {ref!r} in {root}"
    arel = None
    if archive is not None:
        _, arel, _ = _rel(archive)
    io = git_io(root, ref)
    if io is None:
        return None, f"cannot list {ref} in {root}"
    rel, arel = layout_at(rel, arel or None, io)
    text, arch = read_pair(rel, arel, io)
    return (text or "", arch), ""


def id_flags(ledger: Path, archive: Path, text: str, arch: str, ref: str) -> list[dict]:
    """TD-145: the ids this edit adds — in the ledger or archive and in neither at ``ref`` — judged
    against the counter's takes on origin (``ledger_next_id.judge()``, the cadence check's ``ledger``
    row's own): an id nobody handed out, or one handed to another than its ``**Taken by:**``, is an
    error. The one call here that asks origin, and only when the edit adds an id; a repo with no
    counter, or no ``origin`` remote, is judged by nothing, and a counter origin did not give is an ℹ line."""
    import ledger_next_id as X  # sibling SYNC script: the counter's reader (it imports this one)
    root, _, _ = _rel(ledger)
    then, _ = _at_ref(ledger, ref, archive)
    before: set[int] = set()
    for t in then or ("", ""):
        before |= X.ids_in(N.checked(t, f"{ref}:{ledger.name}"))
    new = (X.ids_in(text) | X.ids_in(arch)) - before
    if not new or _git(root, "remote", "get-url", "origin") is None:
        return []   # no origin remote: no counter to ask, so nothing to say
    takes, why = X.counter_takes(root)
    if why:
        return [{"level": "info", "id": None, "field": None, "kind": "id-counter", "text": f"ℹ {why}",
                 "standing": False}]
    if not takes:
        return []
    branch = (_git(root, "symbolic-ref", "-q", "--short", "HEAD") or "").strip()
    fails, warns = X.judge(new, takes, [text, arch], branch, N.default_branch(root))
    return [{"level": lvl, "id": None, "field": None, "kind": kind, "text": f"{mark} {t}", "standing": False}
            for lvl, mark, flags in (("error", "⚠", fails), ("info", "ℹ", warns)) for kind, t in flags]


def value_of(rec: dict, key: str) -> str:
    """What a filter or a count reads: the derived Type and Priority, else the field's first word."""
    if key == "type":
        return rec["type"]
    if key == "priority":
        return rec["priority"].lower()
    return first_word(rec["fields"].get(key))


def select(recs: list[dict], where: list[tuple[str, str]], want_pickable: bool | None) -> list[dict]:
    out = []
    for r in recs:
        if want_pickable is not None and r["pickable"] != want_pickable:
            continue
        if all(value_of(r, k) == v for k, v in where):
            out.append(r)
    return out


def counts(recs: list[dict], by: list[str]) -> list[dict]:
    """One row per combination of values of the ``by`` fields, most entries first; an absent field is ``(none)``."""
    c = Counter(tuple(value_of(r, k) or "(none)" for k in by) for r in recs)
    return [dict(zip(by, vals), count=n) for vals, n in sorted(c.items(), key=lambda kv: (-kv[1], [(v == "(none)", v) for v in kv[0]]))]


def field_summary(res: dict) -> list[dict]:
    """Every field any entry carries, with how many carry it, the values seen, and its vocabulary."""
    seen: dict[str, Counter] = {}
    for r in res["entries"]:
        for k, v in r["fields"].items():
            seen.setdefault(k, Counter())[first_word(v) or "(empty)"] += 1
    keys = [k for k in CADENCE_FIELDS if k in seen] + sorted(k for k in seen if k not in CADENCE_FIELDS)
    keys += [k for k in res["declared"] if k not in seen]
    out = []
    for k in keys:
        vals = seen.get(k, Counter())
        out.append({"field": k, "defined_by": "cadence" if k in CADENCE_FIELDS else
                    ("preamble" if k in res["declared"] else "undeclared"),
                    "entries": sum(vals.values()), "declared": res["declared"].get(k),
                    "values": dict(sorted(vals.items(), key=lambda kv: (-kv[1], kv[0])))})
    return out


def _toplevel() -> Path:
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                       timeout=10, check=False)
    return Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else Path.cwd()


def _row(r: dict) -> str:
    return f"  {r['id']:<7} {r['priority']:<7} {r['type']:<8} {r['title']}"


def _held_by(r: dict) -> str:
    """What a blocked entry waits on, for the text modes: its ``Blocked by`` and, since ledgerboard
    v2.1, its open parts (``parts_open``, kept apart from ``blocked_by``) — so a parent held only by
    its ``Part of`` children never prints an empty reason (TD-167)."""
    why = [", ".join(r["blocked_by"])] if r["blocked_by"] else []
    if r.get("parts_open"):
        why.append(f"parts open: {', '.join(r['parts_open'])}")
    return "; ".join(why)


LINK_RE = re.compile(r"(\]\()([^)\s]+)((?:\s+\"[^\"\n]*\")?\))")   # an inline link, a title kept; not <…> or a reference definition
CODE_SPAN_RE = re.compile(r"`[^`\n]*`")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")   # a fenced code block's opening or closing line
OTHER_LINK_RE = re.compile(r"^ {0,3}\[[^\]\n]+\]:[ \t]*<?([^\s>]+)|href=[\"']([^\"']+)", re.MULTILINE)  # what relink() does not rewrite


def _code_spans(text: str) -> list[tuple[int, int]]:
    """Where ``text`` is code, not prose: each inline span and each fenced block (to the end when unclosed)."""
    spans = [m.span() for m in CODE_SPAN_RE.finditer(text)]
    at, opened = 0, None
    for line in text.splitlines(keepends=True):
        m = FENCE_RE.match(line)
        if m and opened is None:
            opened = (at, m.group(1))
        elif m and m.group(1)[0] == opened[1][0] and len(m.group(1)) >= len(opened[1]) \
                and not line[m.end():].strip():   # CommonMark: the same char, at least as many, no info string
            spans.append((opened[0], at + len(line)))
            opened = None
        at += len(line)
    if opened is not None:
        spans.append((opened[0], len(text)))
    return spans
ANCHOR_RE = re.compile(r"td-0*(\d+)(?:-|$)", re.IGNORECASE)   # an entry heading's GitHub slug: `## TD-21: x` → td-21-x
FROZEN_SUMMARY = "summary-at-split.md"   # the archive's v1 `## Summary`, kept as it stood (TD-185)


def relink(text: str, src: Path, dst: Path, gone: dict[Path, Path], targets: dict[int, Path] | None = None,
           here: Path | None = None) -> tuple[str, list[str]]:
    """TD-176: ``text``'s relative inline links (``](path)``, ``](path "title")``), written from directory ``src``, rewritten to resolve from ``dst``
    (where the split moves it) — (the text, a warning per link left dead). A link inside a code span is
    prose about a link and is left (a fenced block too); so is one that resolved nowhere before (it was not this move's to
    break), a URL and a plain anchor. TD-185: a link into ``gone`` (each v1 file the split removes → the
    directory that replaces it) whose anchor is an entry heading's slug (``#td-21-…``) is pointed at that
    entry's file in ``targets``, as is a bare ``#td-…`` anchor when ``here`` names the v1 file the text
    came from; one with no anchor, at the directory. Any other anchor into ``gone`` is kept and warned.
    With ``src == dst`` (a file the split does not move) only links into ``gone`` change."""
    spans = _code_spans(text)
    warns: list[str] = []
    targets = targets or {}
    for m in OTHER_LINK_RE.finditer(text):   # a reference definition or an HTML link into the v1 files: named, not rewritten
        t = m.group(1) or m.group(2)
        if not any(a <= m.start() < b for a, b in spans) and not re.match(r"[A-Za-z][A-Za-z0-9+.-]*:|/", t) \
                and Path(os.path.normpath(src / t.partition("#")[0])) in gone and t.partition("#")[0]:
            warns.append(f"{t}: a reference or HTML link into the v1 file this split removes — point it at the entry's file by hand")

    def rel(to: Path, slash: bool) -> str:
        return Path(os.path.relpath(to, dst)).as_posix() + ("/" if slash else "")

    def fix(m: re.Match) -> str:
        target = m.group(2)
        path, hash_, frag = target.partition("#")
        if re.match(r"[A-Za-z][A-Za-z0-9+.-]*:", path) or path.startswith("/") \
                or any(a <= m.start() < b for a, b in spans):
            return m.group(0)
        old = here if not path else Path(os.path.normpath(src / path))
        if old is None or not old.exists():
            return m.group(0)
        if old in gone:
            a = ANCHOR_RE.match(frag)
            if a and int(a.group(1)) in targets:
                return f"{m.group(1)}{rel(targets[int(a.group(1))], False)}{m.group(3)}"
            if not hash_:
                return f"{m.group(1)}{rel(gone[old], True)}{m.group(3)}"
            if path:
                warns.append(f"{target}: the v1 file this split removes — point it at the entry's file by hand")
            return m.group(0)
        if not path or src == dst:
            return m.group(0)
        return f"{m.group(1)}{rel(old, path.endswith('/'))}{hash_}{frag}{m.group(3)}"

    return LINK_RE.sub(fix, text), warns


def _lift_summary(archive_text: str) -> tuple[str, str]:
    """TD-185: (the archive without its ``## Summary`` section, the section) — ledgerboard's ``split()``
    refuses one in the archive, and its table (a row per archived entry, often with where each one's
    lasting content went) is kept as a frozen file under ``archive/`` rather than lost."""
    parts = LB._sections(archive_text)
    for i, (tid, part) in enumerate(parts):
        if tid is None and part.partition("\n")[0].strip().lower() == "## summary":
            return "".join(p for j, (_, p) in enumerate(parts) if j != i), part
    return archive_text, ""


def _tracked_md(root: Path) -> list[Path]:
    r = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", "*.md"], capture_output=True,
                       text=True, timeout=30, check=False)
    return [root / f for f in r.stdout.split("\0") if f] if r.returncode == 0 else []


def split(ledger: Path, archive: Path, v2: bool) -> int:
    """--split: write the v2 directory ``docs/ledger/`` beside a v1 ledger (``LB.split()``), move its rank
    file in, and remove the v1 ledger and archive. Nothing is written when anything would be refused.
    TD-185: the archive's ``## Summary``, if any, becomes ``archive/summary-at-split.md``, and the repo's
    other tracked Markdown files have their links into the v1 files pointed at the entries' files."""
    out = ledger.parent / Path(LEDGER_DIR_REL).name
    if v2:
        print(f"ledger: --split: {ledger} is a v2 directory already", file=sys.stderr)
        return 2
    if out.exists():
        print(f"ledger: --split: {out} exists — nothing was split", file=sys.stderr)
        return 2
    _, read = fs_io()
    text, arch = read(str(ledger)), read(str(archive)) or ""
    if text is None:
        print(f"ledger: --split: cannot read {ledger}", file=sys.stderr)
        return 2
    arch, summary = _lift_summary(arch)
    try:
        files = LB.split(text, arch)
    except LB.Refused as e:
        print(f"ledger: --split: {e}", file=sys.stderr)
        return 2
    if summary:
        heading, _, table = summary.partition("\n")
        files[f"{LB.LEDGER_ARCHIVE}/{FROZEN_SUMMARY}"] = (
            f"# {archive.name}'s summary, frozen at the split\n\n"
            f"This table was the `{heading.strip()}` of `{archive.name}` when the ledger was split into this directory "
            f"(`ledger.py --split`, {datetime.now().astimezone().date().isoformat()}). It is not kept up to date: an entry "
            "archived since is not in it, and each entry's own file is the record.\n\n" + table.strip("\n") + "\n")
    rank = Path(LB.rank_path(str(ledger)))
    # the round trip above compared the bytes; the links are rewritten for the files' new place after it
    lp, ap = Path(os.path.normpath(ledger.resolve())), Path(os.path.normpath(archive.resolve()))
    outr = out.resolve()
    gone = {lp: outr, ap: outr / LB.LEDGER_ARCHIVE}
    targets = {int(m.group(1)): outr / k for k in files
               if (m := LB.ENTRY_FILE_RE.match(PurePosixPath(k).name))}
    # every read and rewrite first, every write after: a file that cannot be read is skipped and named,
    # so nothing here can stop the split half done
    relinked, written = 0, []
    for rel, body in files.items():
        here = ap if rel.startswith(LB.LEDGER_ARCHIVE + "/") else lp
        new, warns = relink(body, here.parent, (outr / rel).parent, gone, targets, here)
        relinked += new != body
        for w in warns:
            print(f"ledger: --split: {rel}: {w}", file=sys.stderr)
        written.append((out / rel, new))
    elsewhere = []
    root = _toplevel()
    for f in _tracked_md(root):
        if f.is_symlink() or not f.is_file():
            continue   # a link is read from where it is written; a symlink's target is checked as itself
        fr = Path(os.path.normpath(f.resolve()))
        if fr in gone:
            continue
        try:
            with open(f, encoding="utf-8", newline="") as fh:
                body = fh.read()
        except (OSError, UnicodeDecodeError) as e:
            print(f"ledger: --split: {f.relative_to(root)}: not read ({e.__class__.__name__}) — check its links by hand", file=sys.stderr)
            continue
        new, warns = relink(body, fr.parent, fr.parent, gone, targets)
        for w in warns:
            print(f"ledger: --split: {f.relative_to(root)}: {w}", file=sys.stderr)
        if new != body and not os.access(f, os.W_OK):
            print(f"ledger: --split: {f.relative_to(root)}: not writable — repoint its links into the v1 files by hand", file=sys.stderr)
        elif new != body:
            written.append((f, new))
            elsewhere.append(str(f.relative_to(root)))
    for path, text in written:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
    moved = rank.is_file()
    if moved:
        rank.rename(LB.rank_path(str(out)))
    for p in (ledger, archive):
        p.unlink(missing_ok=True)
    n_arch = sum(1 for k in files if LB.ENTRY_FILE_RE.match(PurePosixPath(k).name) and k.startswith(LB.LEDGER_ARCHIVE + "/"))
    n_open = sum(1 for k in files if LB.ENTRY_FILE_RE.match(k))
    print(f"ledger: split {ledger.name} into {out}/ — {n_open} open, {n_arch} archived"
          + (", the rank file moved in" if moved else "")
          + (f", the archive's summary kept as {LB.LEDGER_ARCHIVE}/{FROZEN_SUMMARY}" if summary else "")
          + (f", relative links rewritten in {relinked} file(s)" if relinked else "")
          + f"; {ledger.name} and {archive.name} removed. Commit it as its own PR.")
    if elsewhere:
        print(f"ledger: --split: links into the v1 files repointed in {len(elsewhere)} other file(s): "
              + ", ".join(elsewhere) + " — review them (a decided ADR may want its link left as written)")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--pickable", nargs="?", const=True, default=None, metavar="yes|no",
                    help="alone: print the pick order, the blocked entries and the flags; "
                         "with --list/--counts: keep only entries whose derived pickable is yes (or no)")
    ap.add_argument("--list", action="store_true", help="print every entry the filters keep, in pick order")
    ap.add_argument("--counts", metavar="FIELD[,FIELD]", help="count the kept entries per value of one or two fields")
    ap.add_argument("--fields", action="store_true", help="every field the entries carry, and each one's vocabulary")
    ap.add_argument("--check", action="store_true", help="print only the flags; exit 1 when an error (⚠) stands")
    ap.add_argument("--summary", action="store_true", help="the summary table, generated: one row per entry in pick order")
    ap.add_argument("--split", action="store_true", help="migrate a v1 ledger to a v2 directory, docs/ledger/ (TD-160)")
    ap.add_argument("--since", metavar="REF", help="with --check: count only entries whose header block differs "
                                                   "from the ledger at REF (e.g. origin/<default>), or is new")
    ap.add_argument("--where", action="append", default=[], metavar="FIELD=VALUE",
                    help="keep entries whose FIELD's first word is VALUE (FIELD= : absent or empty); repeatable")
    for name in ALIASES:
        ap.add_argument(f"--{name}", metavar=name.upper(), help=f"same as --where {name}=VALUE")
    ap.add_argument("--ledger", help="a v1 file or a v2 directory; default: docs/ledger/ at the work tree's top "
                                     "when it exists, else docs/technical_debt.md")
    ap.add_argument("--archive", help="a v1 ledger's archive; default: technical_debt_archive.md beside it")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)

    modes = [m for m in ("list", "counts", "fields", "check", "summary", "split") if getattr(a, m)]
    if a.pickable is not None and not modes:
        if a.pickable is not True:
            ap.error("--pickable yes|no filters --list or --counts; alone, --pickable takes no value")
        modes = ["pickable"]
    if len(modes) != 1:
        ap.error("give exactly one of --pickable, --list, --counts, --fields, --check, --summary, --split")
    mode = modes[0]
    if a.since is not None and mode != "check":
        ap.error("--since applies to --check only")
    want = None
    if mode in ("list", "counts") and a.pickable is not None:
        if a.pickable is True or a.pickable.lower() == "yes":
            want = True
        elif a.pickable.lower() == "no":
            want = False
        else:
            ap.error(f"--pickable takes yes or no, not {a.pickable!r}")
    where = []
    for term in a.where + [f"{n}={getattr(a, n)}" for n in ALIASES if getattr(a, n) is not None]:
        k, eq, v = term.partition("=")
        if not eq or not field_key(k):
            ap.error(f"--where takes FIELD=VALUE, not {term!r}")
        where.append((field_key(k), first_word(v)))
    if (where or want is not None) and mode not in ("list", "counts"):
        ap.error("filters apply to --list and --counts only")
    by = [field_key(x) for x in (a.counts or "").split(",") if x.strip()]
    if mode == "counts" and not 1 <= len(by) <= 2:
        ap.error("--counts takes one or two fields, comma-separated")

    io = fs_io()
    if a.ledger:
        ledger = Path(a.ledger)
    else:
        top = _toplevel()
        ledger = top / ledger_at(top, (lambda p: io[0](str(top / p)), io[1]))
    v2 = io[0](str(ledger)) is not None
    if v2 and a.archive:
        ap.error("--archive applies to a v1 ledger; a v2 directory holds its archive/")
    archive = Path(a.archive) if a.archive else ledger.with_name(Path(ARCHIVE_REL).name)
    if mode == "split":
        return split(ledger, archive, v2)
    text, arch = read_pair(str(ledger), str(archive), io)
    if text is None:
        print(f"ledger: cannot read {ledger}", file=sys.stderr)
        return 2
    why = v2_unread(str(ledger), io)
    if why:
        print(f"ledger: not read — {ledger}: {why}", file=sys.stderr)
        return 2
    try:   # a newer major of the format: read nothing, and say so (TD-133)
        N.checked(text, ledger)
        N.checked(arch, ledger / LB.LEDGER_ARCHIVE if v2 else archive)
    except N.FormatTooNew as e:
        print(f"ledger: not read — {e}", file=sys.stderr)
        return 2
    rank_text = io[1](LB.rank_path(str(ledger)))  # None: no rank file, every entry's key is its implicit one
    if mode == "check":
        old = None
        if a.since is not None:
            then, why = _at_ref(ledger, a.since, None if v2 else archive)
            if then is None:
                print(f"ledger: --since: {why}", file=sys.stderr)
                return 2
            old = then[0]
            try:
                N.checked(old, f"{a.since}:{ledger.name}")
            except N.FormatTooNew as e:
                print(f"ledger: --since: not read — {e}", file=sys.stderr)
                return 2
        recs = check(text, arch, old, rank_text=rank_text) + prose_wait_flags(text, arch, old) + ask_flags(text, arch, old)
        if a.since is not None:
            # what the archive held where this edit started, not at REF's tip: an entry REF archived
            # after the branch left it is not this edit's loss (TD-179)
            root, _, _ = _rel(ledger)
            fork = _git(root, "merge-base", a.since, "HEAD") if root else None
            was, _ = _at_ref(ledger, fork.strip(), None if v2 else archive) if fork else (None, "")
            recs += archive_loss_flags(text, arch, *(was or then))
            try:
                recs += id_flags(ledger, archive, text, arch, a.since)
            except N.FormatTooNew as e:
                print(f"ledger: --since: not read — {e}", file=sys.stderr)
                return 2
        errors = [r for r in recs if r["level"] == "error"]
        if a.json:
            print(json.dumps({"flags": recs, "errors": len(errors)}, indent=2, ensure_ascii=False))
            return 1 if errors else 0
        for r in recs:
            if not r["standing"]:
                print(r["text"])
        standing = sum(r["standing"] for r in recs)
        print(f"ledger check: {len(errors)} error(s)"
              + (f"; {standing} standing flag(s) on entries unchanged since {a.since}, not shown" if standing else ""))
        return 1 if errors else 0
    res = pickable(text, arch, rank_text=rank_text)

    if mode == "summary":
        if a.json:
            print(json.dumps({"entries": res["entries"], "flags": res["flags"]}, indent=2, ensure_ascii=False))
            return 0
        print("| ID | Title | Priority | Type | State |\n|----|-------|----------|------|-------|")
        for r in res["entries"]:
            state = "pickable" if r["pickable"] else f"blocked by {_held_by(r)}"
            print(f"| {r['id']} | {r['title'].replace('|', '/')} | {r['priority']} | {r['type']} | {state} |")
    elif mode == "pickable":
        if a.json:
            print(json.dumps({k: res[k] for k in ("pickable", "blocked", "flags")}, indent=2, ensure_ascii=False))
            return 0
        print(f"Pickable ({len(res['pickable'])}), in pick order:")
        for r in res["pickable"]:
            print(_row(r))
        if not res["pickable"]:
            print("  (none)")
        if res["blocked"]:
            print(f"Blocked ({len(res['blocked'])}):")
            for r in res["blocked"]:
                print(f"{_row(r)} — by {_held_by(r)}")
    elif mode == "list":
        kept = select(res["entries"], where, want)
        if a.json:
            print(json.dumps({"entries": kept, "flags": res["flags"]}, indent=2, ensure_ascii=False))
            return 0
        print(f"Entries ({len(kept)}), in pick order:")
        for r in kept:
            print(_row(r) + ("" if r["pickable"] else f" — blocked by {_held_by(r)}"))
        if not kept:
            print("  (none)")
    elif mode == "counts":
        rows = counts(select(res["entries"], where, want), by)
        if a.json:
            print(json.dumps({"by": by, "counts": rows, "flags": res["flags"]}, indent=2, ensure_ascii=False))
            return 0
        for row in rows:
            print(f"  {row['count']:>4}  " + "  ".join(f"{k}={row[k]}" for k in by))
        if not rows:
            print("     0")
    else:
        fs = field_summary(res)
        if a.json:
            print(json.dumps({"fields": fs, "flags": res["flags"]}, indent=2, ensure_ascii=False))
            return 0
        for f in fs:
            vocab = f" — declared: {' | '.join(f['declared'])}" if f["declared"] else ""
            vals = ", ".join(f"{v} {n}" for v, n in f["values"].items())
            print(f"  {f['field']:<12} {f['defined_by']:<10} {f['entries']:>3} entries  {vals}{vocab}")
    for f in res["flags"]:
        print(f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
