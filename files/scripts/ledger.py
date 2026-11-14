#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/ledger.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""What in the TD ledger may be picked now, and what is blocked on what (TD-064).

    ledger.py --pickable [--ledger PATH] [--archive PATH] [--json]
    ledger.py --summary | --split
    ledger.py fmt [TD-n …] [--check]
    ledger.py new --title T --priority P --why FILE|- [--fix FILE|-] [--done-when FILE|-] [--type …] [--id TD-n] …
    ledger.py set TD-n --FIELD VALUE …  |  note TD-n "words"  |  edit TD-n --section NAME --from FILE|-
    ledger.py lift TD-n --gate "event (<name>)"|"until D" --by HOST [--evidence E]   (a host's lift, TD-219)

An entry may carry one optional field after **Status:** (cadence.md §2):

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
ledgerboard's ``judge_takes()`` through ``ledger_next_id.judge()`` (TD-188): an id no take gave, an entry
with no ``**Id take:**``, and one that is another id's take's nonce or no take's are errors (``Taken by``,
retired, is not read); an id older than the counter and a counter origin did not give are ℹ lines. ``--json``: ``{"flags": [{"level": error|info, "id", "field", "kind", "text", "standing"}],
"errors": N}`` — key on ``kind`` and ``field``, never on the sentence. Kinds: fields-decl, below-header,
type, vocabulary, blocked-item, cross-repo, blocked-unknown, blockers-archived, pickable-disagrees,
undeclared-field, rank (a rank file line), prose-wait (TD-166: a header field that names an id after *waits on/for* or *blocked by*
while its Blocked by does not), no-ask (TD-122: an entry waiting on the person — Owner: person or a
decision holder's name, decision (<who>), an **Answers:** line — with no **Ask:** line in its body), and the ids' id-untaken, id-take, id-before-counter,
id-no-take, id-by-unhashed, id-counter; with ``--since``, archive-loss (an id archived at REF that is now in
neither the ledger nor the archive, TD-179), archive-reopened (ℹ: one back in the ledger) and, in a v2
ledger, not-canonical (TD-201: an entry file that differs from the merge-base's, or is new, and is not in
ledgerboard's canonical form — it names ``ledger.py fmt TD-n``, or the hand fix for one ``canonical()`` refuses). ``check_cadence.py``'s ``ledger`` row runs the same field check on a PR's ledger edit.

``--summary`` prints the summary table a v2 ledger does not store (TD-160): one row per entry in
pick order, its state derived (pickable, or what blocks it). ``--split`` migrates a v1 ledger to v2:
ledgerboard's ``split()`` writes ``docs/ledger/`` (``README.md``, one ``TD-NNN.md`` per entry,
``archive/``) beside the ledger, moves the rank file to ``docs/ledger/rank.yml``, and removes the two v1
files — refused, with nothing written, when ``docs/ledger/`` exists or the round trip would not hold.
Its links are rewritten for their new place (TD-176), entry anchors into the v1 files pointed at the
entries' files there and in the repo's other Markdown, and the archive's summary kept frozen (TD-185).
Commit the result as its own PR.

``fmt`` (TD-197) writes each entry of a v2 ledger — the ones named, else every one in the ledger and
its archive — in ledgerboard's canonical form (``canonical()``, SPEC *Ledger entries and their edits*):
the heading, the header block in its field order, the body byte for byte, LF line endings. An entry
``canonical()`` refuses is named with its hand fix and left alone. ``--check`` prints the entries that
would change and writes nothing. Exit 1 when an entry was refused, or under ``--check`` would change;
2 for a v1 ledger (split first), an id in neither directory, or a ledger ``v2_problems()`` faults.

``new`` (TD-198) files one entry in a v2 ledger: ``docs/ledger/TD-NNN.md`` from ledgerboard's writer,
``plan_new()`` (TD-188), so canonical by construction — a flag per header field (``--priority``, ``--type``,
``--added`` (default today), ``--owner``, ``--kind``, ``--status`` (default Open), ``--blocked-by``,
``--part-of``, ``--location``; ``--field NAME=VALUE`` for a repo's own) and ``--why``, ``--fix``,
``--done-when`` each from a file or ``-`` for stdin. The id is a take from the counter
(``ledger_next_id.py``, ``--by`` passed through) and ``Id take`` its nonce; ``--id TD-n`` files under an
id already taken (written at §2.2's width, ``TD-3`` as ``TD-003``), ``Id take`` that take's nonce (a take
with none, made before the counter wrote one, is refused as the gate fails it) — judged as
the gate judges it, so in a repo whose counter has no take yet an id nobody took is not caught. It refuses the write on every flag the entry brings
that ``--check --since origin/<default>`` counts as an error (``cross-repo`` a note), on a wait written in
prose (``prose-wait``), and on a ``<repo>#TD-n`` blocker whose roster repo was read and has no such entry
and no open PR there that adds it (TD-246: one that does is written, with a note naming the PR) —
all judged once before the take, under a provisional id, so a refusal spends no id, then again with the
id flags. It prints the path and commits nothing. Exit 0 written; 1 refused; 2 a usage error, a v1
ledger (split first), or no id taken (exit 3's unreserved id is printed with the ``--claim`` to run).

``set``, ``note`` and ``edit`` (TD-199) change one open entry through ledgerboard's writer (``plan_edit()``),
in canonical form: ``set`` takes ``new``'s field flags (an empty value removes the field), ``note`` appends
a dated line to the Log, ``edit`` replaces one section (or adds it where SPEC puts it). Each refuses
as ``new`` does — a flag the edit brings that the gate fails, a prose wait on the entry, a ``<repo>#TD-n``
blocker ``set`` adds whose roster repo lacks it — and an entry ``canonical()`` refuses, with its hand fix;
an archived entry is not edited. A ``set`` whose Blocked by drops a ``decision (<person>)`` is that person's
lift (TD-218, ``_set_lift``): it takes ``--by <person>`` (and ``--answer``, default ``Go``), is refused from
any session but a person's own (``agent_sessions.person_session_refusal()``), logs ``gate lifted`` through
ledgerboard's ``lift_gate()``, and answers the covering board item (``board.py decide --board-only``) — or
logs why it could not; ``--why`` swaps the decision for another person's (a reassign) and ``--override WHY``
drops it with anyone's ``--by``, each with the board notices it owes (``_set_moved``) — on another roster repo's
board by a PR opened there and left for its review, its URL printed (TD-226). Exit 0 written; 1
refused; 2 a usage error, an unknown id, or a v1 ledger; 4 a write failed.

``archive`` and ``reopen`` (TD-200) move one entry between the ledger and ``archive/``: ``edit_entry()``'s
archived or reopened form, ``relink()`` for the other directory, then ``git mv`` (a rename for a file git
does not track), the move and its edit staged; a parent with an open part is refused; a link to the moved file
from another file is named, never rewritten. ``renumber TD-old [TD-new]`` takes the new id from
the counter (``TD-new``: one a take gave, else ``--claim``ed) and writes through ledgerboard's ``plan_renumber()``
(TD-188): it moves the file, writes the take's nonce as ``Id take``, rewrites every Blocked by, Part of and
Log ``while`` naming it, its rank line and the ledger's links to it, and lists the references in prose — here,
and as ``<repo>#TD-old`` in the roster's other repos — for the session to judge; an archived entry is not
renumbered (exit 2), and a file ``canonical()`` refuses stops it before any take. Each refuses as ``new`` does, and
commits nothing.

The ledger is a v1 file or a v2 directory (ledgerboard SPEC *The ledger as a directory*, TD-160), and
every read goes through ledgerboard's ``load()``: here with the file system, at a revision (``--since``,
a roster repo's ``origin/<default>``) with ``git_io()`` — one ``ls-tree``, one ``cat-file --batch`` per
directory. A v2 ledger that ``v2_problems()`` faults is not read (exit 2). Defaults: ``docs/ledger/``
when that directory exists, else ``docs/technical_debt.md`` and ``docs/technical_debt_archive.md``, at
the top of the git work tree the command runs in; ``--archive`` applies to a v1 ledger only. Read-only but
for ``--split`` and the writers ``fmt``, ``new`` and ``renumber`` (which also take from the counter), ``set``, ``note``, ``edit``, ``archive``, ``reopen``, and offline except where ``--check --since``'s edit
adds an id: then it asks origin for the counter (``git ls-remote``, and a fetch of its tracking ref). Exit 0 (``--check``: 1 on an error);
2 when the ledger, or ``--since``'s ref, cannot be read or the arguments are unusable, or the
ledger or archive declares a newer major of the format than the ``ledgerboard`` package reads
(``Ledgerboard: N``, TD-133) — then nothing was read. A cross-repo blocker whose ledger declares
one stays blocked, and says why. A detector,
never a gate (cadence.md §7): ``--check`` is what lets a caller choose to gate on it.

``--pickable``, ``--list``, ``--counts``, ``--fields`` and ``--summary`` are ledgerboard's reports
(``ledgerboard.ledger``'s ``run_report``, TD-216): this script finds the ledger and resolves the
``<repo>#TD-n`` ids the package names (its exit 3, ``needs:``) through the roster, as its ``--resolved``
file, until none is needed. Their ``--json`` is one line. ``--check`` stays this script's: its ``--since``
reads a git ref, and it adds the prose-wait, Ask, archive-loss, canonical-form and id flags to the package's.
The reports, ``fmt``, ``set``, ``note``, ``edit``, ``archive``, ``reopen``, ``new`` and ``renumber`` (TD-188) exit by the
package's table: 0 ok, 1 refused, 2 usage or unreadable, 3 needs (an id the run could not resolve, or an archive's
cross-repo successor), 4 a write failed, every file restored. ``--check`` exits 1 when an error flag stands.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections.abc import Mapping
from datetime import date, datetime, timedelta, timezone
from io import StringIO
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledgerboard as LB  # noqa: E402  # sibling SYNC file: the ledger format, defined once (ShiftLead/ledgerboard)
import nudge_user_attention as N  # noqa: E402  # sibling SYNC script: the roster, origin and default-branch readers (§9) — the resolver only
from ledgerboard import (  # noqa: E402,F401  # re-exported: readers and tests reach them as ledger.<name>
    BLOCKED_RE,
    CADENCE_FIELDS,
    COMMENT_RE,
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
from ledgerboard import (
    ledger as LBL,  # noqa: E402  # the package's ledger writer (v2.4): every write goes through it (TD-216)
)

LEDGER_REL, ARCHIVE_REL = "docs/technical_debt.md", "docs/technical_debt_archive.md"
LEDGER_DIR_REL = "docs/ledger"  # a v2 ledger (TD-160): one TD-NNN.md per entry, read through LB.load()
ALIASES = ("type", "owner", "kind")  # --type X is --where type=X, and so on
NEEDS_ID_RE = re.compile(r"[\w.-]+(?:/[\w.-]+)*#TD-\d+")   # an id run_report names after needs: (TD-216)
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
        self._paths: dict[Path, tuple[str, str]] | None = None
        self._read: dict[Path, dict] = {}

    def _find(self, repo: str) -> tuple[Path | None, str]:
        if self._roots is None:
            reg = N.read_registry()
            self._roots = reg or []
            if reg is None:
                return None, "no roster on this machine"
        if "/" in repo:   # an origin path: ledgerboard's origin_path(), an exact match before a suffix one (TD-217)
            want = repo.lower()
            if self._paths is None:   # each clone's origin read once: (its origin_key, its origin_path)
                urls = {r: (_git(r, "remote", "get-url", "origin") or "").strip() for r in self._roots}
                self._paths = {r: (LB.origin_key(u) or "", LB.origin_path(u) or "") for r, u in urls.items()}
            paths = self._paths
            hits = [r for r, (_, p) in paths.items() if p == want] or \
                [r for r, (_, p) in paths.items() if p.endswith("/" + want)] or \
                [r for r, (k, _) in paths.items() if k == want]   # host/owner/name, as the old URL suffix matched
        else:
            hits = [r for r in self._roots if r.name.lower() == repo.lower()]
        if not hits:
            return None, "not on this machine's roster"
        if len(hits) > 1:
            return None, (f"{len(hits)} roster repos are named {repo} — write owner/name")
        return hits[0], ""

    def root(self, repo: str) -> tuple[Path | None, str]:
        """(the roster clone a ``<repo>`` names, why not): an origin path matched exactly before a suffix,
        a bare name by basename — as an id's ``<repo>`` resolves (event_checks.py, TD-219)."""
        return self._find(repo)

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


def _today(today: date | str | None) -> date | str:
    """The day ledgerboard's readers judge an ``until`` gate against: the caller's, else the UTC day, as the
    writers (``lift``, ``set``) and cadence.md §2.4 have it, whatever ``TZ`` is (TD-253; it was this machine's
    local date, so the readers and the home split between local and UTC midnight)."""
    return today if today is not None else datetime.now(timezone.utc).date()


def pickable(ledger: str, archive: str, roster: Roster | None = None, undeclared: bool = False,
             rank_text: str | None = None, today: date | str | None = None) -> dict:
    """ledgerboard's pickable, in rank order, with this machine's roster resolving ``<repo>#TD-NNN`` items."""
    return LB.pickable(ledger, archive, (roster or Roster()).resolve, undeclared, rank_text=rank_text,
                       today=_today(today))


def check(ledger: str, archive: str, old: str | None = None, roster: Roster | None = None,
          rank_text: str | None = None, today: date | str | None = None) -> list[dict]:
    """ledgerboard's check (--check's flags, the rank file's too), with this machine's roster resolving cross-repo items.
    (v2.5 flags a field below an entry's header block, ``below-header``, where v2.4 raised; ledger.py's guard
    for v2.4 is gone, TD-222.)"""
    return LB.check(ledger, archive, old, (roster or Roster()).resolve, rank_text=rank_text, today=_today(today))


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
                old_form = LB.parse_gates(value)["old_form"]  # v2.4: the pointer is the old form's text
                spans = [old_form[1]] if old_form else []
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


def canonical_flags(rel: str, now: tuple[LB.Ls, LB.Read], then: tuple[LB.Ls, LB.Read] | None) -> list[dict]:
    """TD-201: an error for each entry file of the v2 ledger ``rel`` that ``now`` holds and ``then`` (the
    ref the edit started at) does not hold the same — new, a file new in ``archive/`` included — and
    that is not in canonical form, naming the command that writes it; a file ``canonical()`` refuses is
    an error naming its hand fix. Changed means the file, not its header block, so a body edit is
    judged; an entry the edit did not touch never is. Line endings are not judged here: both readers
    give ``\\n`` (TD-187)."""
    recs = []
    for d in (rel, f"{rel}/{LB.LEDGER_ARCHIVE}"):
        for name in LB._entry_names(now[0](d) or []):
            p = f"{d}/{name}"
            text = now[1](p)
            if text is None or (then is not None and then[1](p) == text):
                continue
            tid = name[:-3]
            try:
                ok, why = LB.canonical(text) == text, ""
            except LB.Refused as e:
                ok, why = False, f"{e}; fix it by hand, then `ledger.py fmt {tid}`"
            if not ok:
                recs.append({"level": "error", "id": tid, "field": None, "kind": "not-canonical", "standing": False,
                             "text": f"⚠ {tid}: " + (why or f"{p} is not in canonical form — `ledger.py fmt {tid}` "
                                                     "writes it; a change made with `ledger.py set`, `note` or "
                                                     "`edit` is written so (cadence.md §2.12)")})
    return recs


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
    row's own, ledgerboard's ``judge_takes()``, TD-188): an id nobody handed out, an entry with no
    ``**Id take:**``, or one of another id's take or of none, is an error. The one call here that asks origin, and only when the edit adds an id; a repo with no
    counter, or no ``origin`` remote, is judged by nothing, and a counter origin did not give is an ℹ line."""
    import ledger_next_id as X  # sibling SYNC script: the counter's reader (it imports this one)
    root, _, _ = _rel(ledger)
    then, _ = _at_ref(ledger, ref, archive)
    before = LB.ids_held({f"{ref}:{ledger.name}#{i}": N.checked(t, f"{ref}:{ledger.name}")
                          for i, t in enumerate(then or ("", ""))})   # the package's id reader (TD-217)
    new = LB.ids_held({"ledger": text, "archive": arch}) - before
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


def _toplevel() -> Path:
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                       timeout=10, check=False)
    return Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else Path.cwd()


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
# TD-183: the seed preamble's v1 sentences (files/docs/technical_debt.md), each with what --split writes in its place
# when a repo kept it word for word — a README that names a summary table and an archive file it no longer has
# misdirects the next session. tests/test_ledger_v2.sh holds them to the seed, so a seed edit changes both.
SEED_V1_TO_V2 = (
    ("Once this file is split into `docs/ledger/` (`scripts/ledger.py --split`), every entry is written with "
     "`scripts/ledger.py`",
     "Every entry is written with `scripts/ledger.py`"),
    ("**This file holds open work only.** The summary table below lists exactly the entries that have a body in "
     "this file — one row each, no history. When an entry is fully resolved, move the whole body to "
     "[`technical_debt_archive.md`](technical_debt_archive.md), delete its summary row, and replace **Fix** with the "
     "resolution date plus a pointer to whichever doc/code now carries the lasting content. An entry that is only "
     "*partly* resolved stays here, with what shipped and what remains spelled out in its **Status**.",
     "**This directory holds the ledger:** one `TD-NNN.md` per open entry, and `archive/` (made by the first archive) for "
     "the resolved ones. When an entry is fully resolved, `scripts/ledger.py archive TD-n` moves it there and replaces **Fix** with "
     "the resolution date plus a pointer to whichever doc/code now carries the lasting content. An entry that is only "
     "*partly* resolved stays open, with what shipped and what remains spelled out in its **Status**."),
)


def _seed_to_v2(readme: str) -> str:
    """The README with each seed sentence it still holds verbatim rewritten for the v2 layout (TD-183)."""
    for v1, v2 in SEED_V1_TO_V2:
        readme = readme.replace(v1, v2)
    return readme


def _v1_notes(readme: str) -> list[str]:
    """ledgerboard's split_notes() on the README as written, less the notes on an inline link (``](target)``):
    relink() has rewritten each of those it could resolve and warned on the rest (TD-176). A reference
    definition or an HTML link relink() does not rewrite keeps its note."""
    out = []
    for n, line, why in LB.split_notes(readme):
        m = re.match(r"links (.+?) relatively", why)
        if m and f"]({m.group(1)}" in line:
            continue
        out.append(f"README.md:{n}: {why} — rewrite the line for the v2 layout")
    return out



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
    if "README.md" in files:
        files["README.md"] = _seed_to_v2(files["README.md"])
    if summary:
        heading, _, table = summary.partition("\n")
        files[f"{LB.LEDGER_ARCHIVE}/{FROZEN_SUMMARY}"] = (
            f"# {archive.name}'s summary, frozen at the split\n\n"
            f"This table was the `{heading.strip()}` of `{archive.name}` when the ledger was split into this directory "
            f"(`ledger.py --split`, {datetime.now(timezone.utc).date().isoformat()}). It is not kept up to date: an entry "
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
        if rel == "README.md":
            for w in _v1_notes(new):
                print(f"ledger: --split: {w}", file=sys.stderr)
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


def fmt(argv: list[str]) -> int:
    """``ledger.py fmt``: put entries in canonical form (TD-197) through ledgerboard's ``plan_fmt()`` (TD-216):
    every entry's write made both or neither; exit 1 an entry refused (or, ``--check``, one would change),
    2 unusable, 4 the write failed, every file restored."""
    ap = argparse.ArgumentParser(prog="ledger.py fmt",
                                 description="write each entry of a v2 ledger in canonical form (ledgerboard SPEC)")
    ap.add_argument("ids", nargs="*", metavar="TD-n", help="the entries to format; default: every entry, open and archived")
    ap.add_argument("--check", action="store_true", help="print the entries that would change and exit 1; write nothing")
    ap.add_argument("--ledger", help="a v2 directory; default: docs/ledger/ at the work tree's top")
    a = ap.parse_args(argv)
    for t in a.ids:
        if not ID_ITEM_RE.match(t):
            ap.error(f"an entry's id is TD-n, not {t!r}")
    ledger = Path(a.ledger) if a.ledger else _toplevel() / LEDGER_DIR_REL
    io = fs_io()
    if io[0](str(ledger)) is None:
        print(f"ledger: fmt: {ledger} is not a v2 directory — a v1 ledger: `ledger.py --split` first", file=sys.stderr)
        return 2
    why = v2_unread(str(ledger), io)
    if why:
        print(f"ledger: fmt: not read — {ledger}: {why}", file=sys.stderr)
        return 2
    try:
        plan = LBL.plan_fmt(LBL.Ledger.open(str(ledger)), a.ids)
    except LBL.Unusable as e:
        print(f"ledger: fmt: {e}", file=sys.stderr)
        return 2
    for r in plan.info["refused"]:
        print(f"ledger: fmt: {r['path']}: refused, left alone — {r['why']}", file=sys.stderr)
    if not a.check:
        try:
            LBL.apply(plan)
        except OSError as e:
            print(f"ledger: fmt: the write failed, every file restored: {e}", file=sys.stderr)
            return 4
    n, changed, refused = plan.info["entries"], plan.info["formatted"], len(plan.info["refused"])
    for p in changed:
        print(f"{'would change' if a.check else 'formatted'}: {p}")
    print(f"ledger fmt: {n} entr{'y' if n == 1 else 'ies'}, {len(changed)} "
          f"{'would change' if a.check else 'formatted'}, {refused} refused")
    return 1 if refused or (a.check and changed) else 0


# `new`'s header flags, in the canonical order (ledgerboard ENTRY_ORDER): (option dest, field name)
NEW_FIELDS = (("priority", "Priority"), ("type", "Type"), ("added", "Added"), ("owner", "Owner"), ("kind", "Kind"),
              ("status", "Status"), ("blocked_by", "Blocked by"), ("part_of", "Part of"), ("location", "Location"))


def _gate_flags(ledger: Path, io: tuple[LB.Ls, LB.Read], ref: str, then: tuple[str, str] | None,
                roster: Roster, ids: bool) -> list[dict]:
    """``--check --since ref``'s flags (and prose waits) on the ledger ``io`` reads; ``ids``: the id flags too."""
    text, arch = read_pair(str(ledger), None, io)
    old = then[0] if then else None
    recs = check(text or "", arch, old, roster, io[1](LB.rank_path(str(ledger)))) + prose_wait_flags(text or "", arch, old)
    if then:
        recs += archive_loss_flags(text or "", arch, *then)
    if ids:
        recs += id_flags(ledger, ledger.with_name(Path(ARCHIVE_REL).name), text or "", arch, ref)
    return recs


def _introduced(before: list[dict], after: list[dict], tid: str) -> tuple[list[dict], list[dict]]:
    """(refusals, notes): the flags ``after`` holds that ``before`` does not — the ones this entry
    brings. Every error but ``cross-repo`` refuses, and so does a prose wait on the entry itself;
    ``cross-repo`` and the other ℹ lines are notes."""
    seen = {(r["kind"], r["text"]) for r in before}
    new = [r for r in after if (r["kind"], r["text"]) not in seen and not r.get("standing")]
    refuse = [r for r in new if (r["level"] == "error" and r["kind"] != "cross-repo")
              or (r["kind"] == "prose-wait" and r["id"] == tid)]
    return refuse, [r for r in new if r not in refuse]


XREPO_FORGE_TIMEOUT = 30.0   # the forge read, in all, per missing cross-repo blocker a writer is given (TD-246)


def adding_pr(root: Path, rel: str, tid: str) -> tuple[str | None, str]:
    """(the open PR of the repo at ``root`` that adds entry ``tid``'s file under its split ledger ``rel``, as
    its forge writes a PR's ref, or None; why none, in a few words) — TD-246: one bounded forge read, in that
    clone, so ``gh`` asks that repo's forge. A v1 ledger (one file) or an unreadable forge finds none."""
    if not rel or rel.endswith(".md"):
        return None, f"its ledger is one file ({rel}), so no open PR is read for one entry"
    import forge as F  # sibling SYNC script, imported here: a writer reaches the forge only for this
    want = re.compile(rf"{re.escape(rel.rstrip('/'))}/TD-0*{_num(tid)}\.md")
    try:
        # one budget for the whole read: GitLab's open_prs_files() is a call per open MR
        be = F.backend(root, cwd=root, spent={"t": 0.0, "hit": False}, per_call=XREPO_FORGE_TIMEOUT,
                       total=XREPO_FORGE_TIMEOUT)
        prs = be.open_prs_files()
    except F.ForgeUnreadable as e:
        return None, f"its open PRs could not be read ({e})"
    except (AttributeError, TypeError, KeyError, ValueError) as e:   # an answer not shaped as a PR list
        return None, f"its open PRs could not be read ({type(e).__name__})"
    for p in prs:
        if any(want.fullmatch(f or "") for f in p.get("files") or []):
            return be.ref(p.get("number")), ""
    return None, "no open PR there adds it"


class _Writer:
    """One write command's ledger (TD-198, TD-199): the v2 directory, read as ``--check --since
    origin/<default>`` reads it, and the refusals every writer shares."""

    def __init__(self, cmd: str, ledger: Path, io: tuple[LB.Ls, LB.Read], root: Path, rel: str) -> None:
        self.cmd, self.ledger, self.io, self.root, self.rel = cmd, ledger, io, root, rel
        self.ref = f"origin/{N.default_branch(root)}"
        self.then, _ = _at_ref(ledger, self.ref)  # None (no such ref): every entry counts as new, as in --check
        self.text, self.arch = read_pair(str(ledger), None, io)
        self.roster = Roster()

    @classmethod
    def open(cls, cmd: str, arg: str | None) -> "_Writer | int":
        """The writer over ``arg`` (default docs/ledger/ at the work tree's top), or the exit code, said."""
        ledger = Path(arg) if arg else _toplevel() / LEDGER_DIR_REL
        io = fs_io()
        if io[0](str(ledger)) is None:
            return cls.say(cmd, f"{ledger} is not a v2 directory — a v1 ledger: `ledger.py --split` first", 2)
        why = v2_unread(str(ledger), io)
        if why:
            return cls.say(cmd, f"not read — {ledger}: {why}", 2)
        root, rel, why = _rel(ledger)
        return cls.say(cmd, why, 2) if root is None else cls(cmd, ledger, io, root, rel)

    @staticmethod
    def say(cmd: str, text: str, code: int) -> int:
        print(f"ledger: {cmd}: {text}", file=sys.stderr)
        return code

    def lb_ledgers(self) -> "tuple[LBL.Ledger, LBL.Ledger | None]":
        """(the ledger as the package's writer reads it, the same at origin/<default> — the gate's base — or
        None where that ref holds no v2 ledger): this script keeps the git I/O, the package the edit (TD-216)."""
        led = LBL.Ledger.open(str(self.ledger))
        io = git_io(self.root, self.ref, self.rel)
        if io is None or io[0](self.rel) is None:
            return led, None
        files = {}
        for d in ("", LB.LEDGER_ARCHIVE):
            sub = f"{self.rel}/{d}".rstrip("/")
            for n in io[0](sub) or []:
                t = io[1](f"{sub}/{n}")
                if t is not None:
                    files[os.path.join(str(self.ledger), d, n) if d else os.path.join(str(self.ledger), n)] = t
        return led, LBL.Ledger(str(self.ledger), files, True)

    def xrepo_refused(self, value: str | None, was: str = "") -> bool:
        """A ``<repo>#TD-n`` this Blocked by value adds (not in ``was``) whose roster repo was read and has
        no such entry (TD-153's missing) is refused, saying to fetch there — unless an open PR in that repo
        adds the entry's file (TD-246): then it is written with a note naming the PR. The block holds, since a
        missing entry never lifts, and ``--check`` flags it until the PR merges and the clone is fetched."""
        had = set(parse_blocked(was)[0])
        for item in parse_blocked(value or "")[0]:
            m = XREPO_ITEM_RE.match(item.strip())
            if not m or item in had:
                continue
            repo_root, _ = self.roster._find(m.group(1))
            st = self.roster.state(repo_root, m.group(2), m.group(1)) if repo_root else {"missing": False}
            if st["missing"]:
                pr, why = adding_pr(repo_root, self.roster._repo(repo_root)["rel"], m.group(2))
                if pr:
                    self.say(self.cmd, f"note — Blocked by {item}: {st['why']}, but {m.group(1)}'s open PR {pr} "
                                       f"adds it; written, and the block holds until that PR merges there and "
                                       f"`git -C {repo_root} fetch` reads it (TD-246)", 0)
                    continue
                self.say(self.cmd, f"refused — Blocked by {item}: {st['why']}, and {why}; if it was filed "
                                   f"since, `git -C {repo_root} fetch` and run again", 1)
                return True
        return False

    def refused(self, tid: str, name: str, entry: str, with_ids: bool = True, notes: bool = True) -> bool:
        """Whether ``entry``, written as ``name``, brings a flag the gate fails (or a prose wait on itself);
        each refusal said, and with ``notes`` each new ℹ line."""
        return self.refused_changes(tid, {self.ledger / name: entry}, with_ids, notes)

    def refused_changes(self, tid: str, changes: Mapping[Path, str | None], with_ids: bool = True,
                        notes: bool = True) -> bool:
        """``refused()`` for several files at once, each written with its text or removed (None) — a move."""
        before = _gate_flags(self.ledger, self.io, self.ref, self.then, self.roster, with_ids)
        after = _gate_flags(self.ledger, _overlay(self.io, changes), self.ref, self.then, self.roster, with_ids)
        refuse, info = _introduced(before, after, tid)
        for r in info if notes else []:
            self.say(self.cmd, f"note — {r['text']}", 0)
        for r in refuse:
            self.say(self.cmd, f"refused — {r['text']}", 1)
        return bool(refuse)


def _field_flags(ap: argparse.ArgumentParser, helps: Mapping[str, str]) -> None:
    for dest, name in NEW_FIELDS:
        ap.add_argument(f"--{dest.replace('_', '-')}", dest=dest, metavar=name.upper().replace(" ", "_"),
                        help=helps.get(dest, f"the {name} field"))
    ap.add_argument("--field", action="append", default=[], metavar="NAME=VALUE", help="a repo's own field; repeatable")


def _fields_given(ap: argparse.ArgumentParser, a: argparse.Namespace) -> list[tuple[str, str]]:
    """(name, value) for each field flag given, in NEW_FIELDS order, then the --field ones; a field
    named twice, in any spelling (``field_key``), is a usage error."""
    out = [(name, getattr(a, dest)) for dest, name in NEW_FIELDS if getattr(a, dest) is not None]
    for f in a.field:
        k, eq, v = f.partition("=")
        if not eq or not k.strip():
            ap.error(f"--field takes NAME=VALUE, not {f!r}")
        out.append((k.strip(), v))
    keys = [field_key(n) for n, _ in out]
    dup = sorted({k for k in keys if keys.count(k) > 1})
    if dup:
        ap.error(f"a field is given twice: {', '.join(dup)}")
    return out


def _field_value(fields: list[tuple[str, str]], key: str) -> str | None:
    """The value given for the field ``key`` (a ``field_key``), whatever its spelling, or None."""
    return next((v for n, v in fields if field_key(n) == key), None)


def _read_body(ap: argparse.ArgumentParser, flag: str, src: str) -> str:
    try:
        return sys.stdin.read() if src == "-" else Path(src).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        ap.error(f"{flag}: cannot read {src} ({e.__class__.__name__})")


def new(argv: list[str]) -> int:
    """``ledger.py new``: file one entry from flags, its id from the counter (TD-198)."""
    ap = argparse.ArgumentParser(prog="ledger.py new",
                                 description="file a new entry in a v2 ledger, in canonical form, its id from the counter")
    ap.add_argument("--title", required=True)
    _field_flags(ap, {"added": "default: today", "status": "default: Open"})
    for s in ("why", "fix", "done-when"):
        ap.add_argument(f"--{s}", metavar="FILE", help=f"the {s.replace('-', ' ').capitalize()} section from a file, or - for stdin")
    ap.add_argument("--id", metavar="TD-n", help="file under an id already taken from the counter, instead of taking one")
    ap.add_argument("--by", help="the take's by (ledger_next_id.py --by), for a front end filing for its caller")
    ap.add_argument("--ledger", help="a v2 directory; default: docs/ledger/ at the work tree's top")
    a = ap.parse_args(argv)
    if not a.priority:
        ap.error("--priority is required (High, Medium or Low)")
    if not a.why:
        ap.error("--why is required: the Why is the point of an entry (cadence.md §2)")
    if [a.why, a.fix, a.done_when].count("-") > 1:
        ap.error("only one section can come from stdin")
    if a.id and not ID_ITEM_RE.match(a.id):
        ap.error(f"an entry's id is TD-n, not {a.id!r}")
    sections = []
    for name, src in (("Why", a.why), ("Fix", a.fix), ("Done when", a.done_when)):
        body = _read_body(ap, f"--{name.lower().replace(' ', '-')}", src) if src is not None else ""
        if body.strip():
            sections.append((name, body.strip()))
    if not sections or sections[0][0] != "Why":
        ap.error("--why is empty: the Why is the point of an entry (cadence.md §2)")
    a.added = a.added if a.added is not None else datetime.now(timezone.utc).date().isoformat()
    a.status = a.status if a.status is not None else "Open"
    fields = _fields_given(ap, a)

    w = _Writer.open("new", a.ledger)
    if isinstance(w, int):
        return w
    known = LB.heading_nums(w.text) | LB.heading_nums(w.arch)
    if w.xrepo_refused(_field_value(fields, "blocked by")):
        return 1

    try:
        led, base = w.lb_ledgers()
    except LBL.Unusable as e:
        return w.say("new", str(e), 2)

    def render(tid: str, take: str | None) -> "LBL.Plan | int":
        """The package writer's plan for the entry (TD-188): ``plan_new()`` writes the take's nonce as ``Id
        take``, and never ``Taken by`` (retired, step 4)."""
        try:
            plan = LBL.plan_new(led, tid, a.title, fields, sections, take=take, base=base,
                                resolve=w.roster.resolve)
            out = next(t for t in plan.changes.values() if t is not None)
            if LB.canonical(out) != out:
                raise LB.Refused("the entry would not be in canonical form")
            return plan
        except LBL.Unusable as e:
            return w.say("new", str(e), 2)
        except LB.Refused as e:
            return w.say("new", f"refused — {e}", 1)

    def text_of(plan: "LBL.Plan") -> str:
        return next(t for t in plan.changes.values() if t is not None)

    # Everything but the id is judged first, under a provisional one, so a refusal spends no take.
    provisional = LBL.tid_of(f"TD-{max(known, default=0) + 1}")   # at §2.2's width, as plan_new() writes it
    plan = render(provisional, None)
    if isinstance(plan, int):
        return plan
    if w.refused(provisional, f"{provisional}.md", text_of(plan), with_ids=False, notes=False):  # notes once, below
        return w.say("new", f"no id was taken and nothing was written ({provisional} above is provisional)", 1)

    import ledger_next_id as X  # sibling SYNC script: the counter (it imports this one)
    if a.id:
        tid = X.tid(_num(a.id))  # §2.2's width, as the counter writes it: TD-3 is TD-003
        if _num(tid) in known:
            return w.say("new", f"{tid} is in the ledger or its archive already", 2)
        takes, why = X.counter_takes(w.root)
        if takes is None:
            return w.say("new", f"refused — {why}, so {tid}'s take cannot be named", 2)
        take = (takes.get(_num(tid)) or {}).get("take")
    else:
        cmd = [sys.executable, str(Path(__file__).with_name("ledger_next_id.py")), "--json", "--ledger", w.rel]
        r = subprocess.run(cmd + (["--by", a.by] if a.by else []), cwd=w.root, capture_output=True, text=True,
                           timeout=120, check=False)
        try:
            res = json.loads(r.stdout)
        except ValueError:
            res = {"ids": [], "why": (r.stderr.strip() or f"exit {r.returncode}")}
        if r.returncode == 3 and res.get("ids"):
            t = res["ids"][0]
            return w.say("new", f"{t} was printed but not reserved ({res.get('why')}) — nothing was written; reserve it "
                                f"with `ledger_next_id.py --claim {t}`, then run again with --id {t}", 2)
        if r.returncode != 0 or not res.get("ids"):
            return w.say("new", f"no id was taken — {res.get('why')}", 2)
        tid, take = res["ids"][0], res.get("id_take")
    plan = render(tid, take)
    if isinstance(plan, int) or w.refused(tid, f"{tid}.md", text_of(plan)):
        return w.say("new", f"{tid} is taken and nothing was written — fix the above, then run again with --id {tid}", 1)
    path = w.ledger / f"{tid}.md"
    if path.exists():
        return w.say("new", f"{path} exists — nothing was written", 2)
    try:
        LBL.apply(plan)
    except OSError as e:
        return w.say("new", f"the write failed: {e}", 4)
    print(path)
    return 0


def edit(cmd: str, argv: list[str]) -> int:
    """``ledger.py set|note|edit TD-n …``: one edit of an open entry (TD-199), through ledgerboard's writer
    (``_lb_edit``, TD-216); a ``set`` that drops a ``decision (<person>)`` is the person's lift (``_set_lift``,
    TD-218)."""
    ap = argparse.ArgumentParser(prog=f"ledger.py {cmd}", description={
        "set": "set an open entry's header fields (an empty value removes one)",
        "note": "append a dated line (the UTC day) to an open entry's Log",
        "edit": "replace one section of an open entry (or add it where SPEC puts it)"}[cmd])
    ap.add_argument("id", metavar="TD-n")
    if cmd == "set":
        _field_flags(ap, {})
        ap.add_argument("--by", help="who lifts the decision this Blocked by drops: that gate's person, from a "
                                     "session they started (never git's user.name)")
        ap.add_argument("--answer", help="the lifting answer (default Go): one of the covering board item's Lifts:")
        ap.add_argument("--why", help="a reassign's why (the Blocked by swaps one decision for another)")
        ap.add_argument("--override", metavar="WHY", help="lift the decision by override, --by anyone: its why")
    elif cmd == "note":
        ap.add_argument("words", help="the note, one line")
    else:
        ap.add_argument("--section", required=True, help="the section's name: Why, Fix, Done when, …")
        ap.add_argument("--from", dest="src", required=True, metavar="FILE", help="its new text from a file, or - for stdin")
    ap.add_argument("--ledger", help="a v2 directory; default: docs/ledger/ at the work tree's top")
    a = ap.parse_args(argv)
    if not ID_ITEM_RE.match(a.id):
        ap.error(f"an entry's id is TD-n, not {a.id!r}")
    kw: dict = {"today": datetime.now(timezone.utc).date().isoformat()}  # the UTC day; v2.5 dates a gate a set adds
    if cmd == "set":
        kw["fields"] = dict(given := _fields_given(ap, a))
        if not kw["fields"]:
            ap.error("give at least one field to set")
        for flag, v in (("--answer", a.answer), ("--why", a.why), ("--override", a.override)):
            if v is not None and a.by is None:
                ap.error(f"{flag} is a gate route's: give --by, who answered")
        if a.override is not None and (a.answer is not None or a.why is not None):
            ap.error("--override is its own why: no --answer or --why with it")
        if a.why is not None and a.answer is not None:
            ap.error("--why is a reassign's and --answer a lift's: give one")
    elif cmd == "note":
        kw.update(words=a.words)
    else:
        kw.update(section=a.section, words=_read_body(ap, "--from", a.src).strip())
        if not kw["words"]:
            ap.error("--from is empty: a section is never emptied by edit")

    w = _Writer.open(cmd, a.ledger)
    if isinstance(w, int):
        return w
    if cmd == "set":
        if w.xrepo_refused(_field_value(given, "blocked by"), _blocked_raw(w, a.id)):
            return w.say(cmd, "nothing was written", 1)
        if a.by is not None:
            return _set_lift(w, a.id, kw["fields"], a.by, a.answer, a.why, a.override)
    return _lb_edit(w, cmd, a.id, kw)


def lift(argv: list[str]) -> int:
    """``ledger.py lift TD-n --gate "<gate>" --by <host> [--evidence <repo>#<n>|<repo>@<sha>]``: a host's lift
    (TD-219; ledgerboard's target design §4.2, §3.2): an ``event (<name>)`` whose check passed, with its evidence,
    or an ``until D`` that is reached, written by ledgerboard's ``plan_lift()`` (``lift_gate()``: the gate
    removed and a ``gate lifted`` Log line in its fixed shape). The gate sweep's lift PRs are made with it. A
    person's lift is ``set --by`` (TD-218) or the board's decide, never this: it takes no answer."""
    ap = argparse.ArgumentParser(prog="ledger.py lift", description="a host's lift of an event or until gate")
    ap.add_argument("id", metavar="TD-n")
    ap.add_argument("--gate", required=True, help='"event (<name>)" or "until YYYY-MM-DD"')
    ap.add_argument("--by", required=True, help="the host's token ([A-Za-z0-9_.@/-])")
    ap.add_argument("--evidence", help="an event's: <repo>#<n> (pr-merged) or <repo>@<sha>, where the check passed")
    ap.add_argument("--ledger", help="a v2 directory; default: docs/ledger/ at the work tree's top")
    a = ap.parse_args(argv)
    if not ID_ITEM_RE.match(a.id):
        ap.error(f"an entry's id is TD-n, not {a.id!r}")
    if a.gate.strip().lower().startswith("decision"):
        ap.error("a decision is lifted by its person: ledger.py set --by, or the board's decide")
    w = _Writer.open("lift", a.ledger)
    if isinstance(w, int):
        return w
    try:
        led, base = w.lb_ledgers()
        plan = LBL.plan_lift(led, a.id, a.gate, a.by, evidence=a.evidence, base=base, resolve=w.roster.resolve,
                             today=datetime.now(timezone.utc).date().isoformat())
    except LBL.Unusable as e:
        return w.say("lift", str(e), 2)
    except LB.Refused as e:
        return w.say("lift", f"refused, nothing written — {e}", 1)
    for n in plan.info.get("notes", []):
        w.say("lift", f"note — {n}", 0)
    try:
        LBL.apply(plan)
    except OSError as e:
        return w.say("lift", f"the write failed, every file restored: {e}", 4)
    print(LB.entry_path(str(w.ledger), a.id, w.io[0]))
    return 0


def _blocked_raw(w: "_Writer", tid: str) -> str:
    """The open entry's Blocked by as written, or "" (an unknown or archived id is the writer's to refuse)."""
    found = LB.entry_path(str(w.ledger), tid, w.io[0])
    text = w.io[1](found) if found else None
    return (LB.entries(text)[0]["blocked_raw"] or "") if text and LB.entries(text) else ""


def _lb_plan(w: _Writer, cmd: str, tid: str, kw: dict) -> "LBL.Plan | int":
    """One edit planned by ledgerboard's ``plan_edit()`` (TD-216): the package reads, edits and gates against
    the ledger at origin/<default> (``check()``, with this machine's roster resolving cross-repo items); a
    ``set`` is judged here too, as ``new`` is (``refused_changes()``: the prose waits and id flags the package
    does not read). The plan, or the exit code, said: 1 refused, 2 unusable."""
    try:
        led, base = w.lb_ledgers()
        plan = LBL.plan_edit(led, cmd, tid, base=base, resolve=w.roster.resolve, **kw)
    except LBL.Unusable as e:
        return w.say(cmd, str(e), 2)
    except LB.Refused as e:
        w.say(cmd, f"refused — {e}", 1)
        return w.say(cmd, f"nothing was written to {LB.entry_path(str(w.ledger), tid, w.io[0])}", 1)
    if cmd == "set" and plan.changes and w.refused_changes(
            tid, {Path(p): t for p, t in plan.changes.items()}, notes=False):
        return w.say(cmd, f"nothing was written to {LB.entry_path(str(w.ledger), tid, w.io[0])}", 1)
    for n in plan.info.get("notes", []):
        w.say(cmd, f"note — {n}", 0)
    return plan


def _lb_edit(w: _Writer, cmd: str, tid: str, kw: dict) -> int:
    """``set``/``note``/``edit`` through ``_lb_plan()``, then written; the date is the UTC day. Exit by the
    package's table: 1 refused, 2 unusable, 4 the write failed."""
    plan = _lb_plan(w, cmd, tid, kw)
    if isinstance(plan, int):
        return plan
    try:
        LBL.apply(plan)
    except OSError as e:
        return w.say(cmd, f"the write failed, every file restored: {e}", 4)
    print(LB.entry_path(str(w.ledger), tid, w.io[0]))
    return 0


BOARD_REL, BOARD_ARCHIVE_REL = "docs/user_attention.md", "docs/user_attention_archive.md"  # a repo's board (§3.4)


def _boards(w: _Writer) -> tuple[list[tuple], dict[str, str], str]:
    """What ``covers()`` reads for the ``set`` lift (TD-218; ledgerboard's target design §1.1): this repo's own
    board as the working tree holds it, then every other roster repo's board at its origin/<default>, in
    ``origin_key`` order — ``[(origin_url, basename, text, archive_text)]`` — with {board name: the repo
    the ``; board <repo>`` Log text names, its lowercased ``origin_path`` else its basename} and this repo's."""
    def origin(root: Path) -> str:
        return (_git(root, "remote", "get-url", "origin") or "").strip()

    def named(url: str, root: Path) -> tuple[str, str]:
        return LB.origin_key(url) or root.name, LB.origin_path(url) or root.name

    fread = fs_io()[1]
    url = origin(w.root)
    own = (url, w.root.name, fread(str(w.root / BOARD_REL)) or "", fread(str(w.root / BOARD_ARCHIVE_REL)) or "")
    key, repo = named(url, w.root)
    names = {key: repo}
    others = []
    for root in N.read_registry() or []:
        if root.resolve() == w.root.resolve() or not root.is_dir():
            continue
        u = origin(root)
        io = git_io(root, f"origin/{N.default_branch(root)}", "docs")
        if io is None:
            continue
        text = io[1](BOARD_REL)
        if text is None:
            continue
        k, r = named(u, root)
        if k in names:
            continue
        names[k] = r
        others.append((u, root.name, text, io[1](BOARD_ARCHIVE_REL) or ""))
    others.sort(key=lambda b: (0, LB.origin_key(b[0])) if LB.origin_key(b[0]) else (1, b[1].lower()))  # §3.2: no origin last
    return [own, *others], names, repo


def _set_lift(w: _Writer, tid: str, fields: dict, by: str, answer: str | None, why: str | None = None,
              override: str | None = None) -> int:
    """``set TD-n --blocked-by … --by <person> [--answer <label>]``: the person's lift of the one
    ``decision (<person>)`` the new Blocked by drops (ledgerboard's target design §1.1, §3.1; TD-218). Refused
    unless the running session is a person's own (``agent_sessions.person_session_refusal()``), or (TD-260) the
    lift carries out the gate's person's answer already recorded on the board at origin/<default>
    (``agent_sessions.recorded_answer()``; ``--by`` that person), and then a ``note`` beside the Log's lift line
    names the record; a reassign or an override has no such route. The covering
    board item is picked (``covers()``, open or decided: this repo's own board first — the item whose Context
    names the entry, else the lowest item key — then the other roster boards in ``origin_key`` order), the
    answer must be one of its ``Lifts:`` (``Go`` when it has none), and the Log's suffix follows from it:
    none, the item on this board answered by ``board.py decide --board-only`` (the same label and ``by``);
    ``shared board item left open`` when it still asks about other parts (v2.7: the board half then writes
    nothing — ``paths: []``, ``left_open`` — which is a success: only the ledger path is printed, and the item
    left open is said on stderr);
    ``board <repo>`` when it is another repo's (nothing written there: the gate sweep audits it);
    ``no board item`` when nothing covers. The ledger is written first and the board after it (the board
    writer reads the ledger as it stands to decide the close); a board refusal puts the entry back. Nothing
    is committed: the caller's PR carries both files, and takes ordinary review (it is no carve-out lift).
    A reassign (one decision swapped for another, ``--why``) and an override (``--override``) are
    ``_set_moved()``'s."""
    import agent_sessions  # the session adapter: who is running this
    from ledgerboard import board as LBB
    label = " ".join((answer or "Go").split())
    try:
        led, _ = w.lb_ledgers()
        path, archived = led.entry_file(LBL.tid_of(tid))
    except LBL.Unusable as e:
        return w.say("set", str(e), 2)
    if archived:
        return w.say("set", f"{tid} is archived ({path}) — a gate is lifted only on an open entry", 2)
    text = led.files[path]
    was = LBL._decisions(LB.entries(text)[0]["blocked_raw"])
    value = _field_value(list(fields.items()), "blocked by")
    now = LBL._decisions(value) if value is not None else was
    norm = lambda g: " ".join(g.split()).lower()  # noqa: E731
    gone = [g for g in was if norm(g) not in {norm(x) for x in now}]
    added = [g for g in now if norm(g) not in {norm(x) for x in was}]
    if len(gone) != 1:
        return w.say("set", f"--by lifts one decision this Blocked by drops; it drops {len(gone)} "
                            f"({', '.join(was) or 'the entry has none'}) — lift them one at a time", 2)
    if len(added) > 1:
        return w.say("set", "a reassign replaces one decision by one other: set them one at a time", 2)
    refusal = agent_sessions.person_session_refusal()
    if refusal and (added or override is not None or why is not None):  # a reassign or an override: the person's own
        return w.say("set", f"refused — {refusal}; nothing was written", 1)
    if added and override is not None:
        return w.say("set", "--override drops the decision; a Blocked by that swaps it for another is a reassign "
                            "(--why)", 2)
    if added or override is not None:
        return _set_moved(w, tid, fields, by, gone[0], added[0] if added else None, why, override, led, path, text)
    if why is not None:
        return w.say("set", "--why is a reassign's: a lift takes --answer, or --override with its why", 2)
    gate = gone[0]
    person = gate[len("decision ("):-1]
    by = person if " ".join(by.split()).lower() == person.lower() else by   # the Log and the board spell it as the gate does
    recorded = None
    if refusal:   # TD-260: the person's answer already recorded on the default branch is theirs, whoever applies it
        if by != person:
            return w.say("set", f"refused — {refusal}; a session applies only {person}'s own recorded answer "
                                f"(--by {person}); nothing was written", 1)
        recorded = agent_sessions.recorded_answer(w.root, text, gate, label, w.ref)
        if recorded is None:
            return w.say("set", f"refused — {refusal}, and the board at {w.ref} records no answer {label!r} by "
                                f"{person} to {LBL.tid_of(tid)} {gate} (an open decide item whose Context names it, "
                                "Decided: by them since the gate was added); nothing was written", 1)
    try:
        boards, names, repo = _boards(w)
        got = [(b, it) for b, it, st in LB.covers(text, gate, boards, repo) if st in ("open", "decided")]
    except LB.Refused as e:
        return w.say("set", f"refused — the board items for {gate}: {e}", 1)
    own = LB.origin_key(boards[0][0]) or boards[0][1]
    order = [LB.origin_key(b[0]) or b[1] for b in boards]
    me = _num(tid)

    def rank(t: tuple) -> tuple:
        b, it = t
        ref = LB._item_gate(it.text)[0] or ""
        direct = "#" not in ref and ID_ITEM_RE.match(ref) is not None and _num(ref) == me
        return (order.index(b) if b in order else len(order), not (b == own and direct), LB.item_key(it.text))
    pick = min(got, key=rank) if got else None
    if pick is not None and pick[0] == own and "#" in (LB._item_gate(pick[1].text)[0] or ""):
        return w.say("set", f"refused — the covering item names this entry as another repo's "
                            f"({LB._item_gate(pick[1].text)[0]}), which the board writer will not answer here: "
                            f"write its Context as a bare {LBL.tid_of(tid)} first, "
                            f"then lift — nothing was written: {pick[1].text[:80]!r}", 1)
    if pick is not None and not LB._lifting(label, pick[1].lifts, pick[1].answers):
        return w.say("set", f"refused — {label!r} does not lift the covering item (its Lifts: "
                            f"{', '.join(pick[1].lifts or ['Go'])}): {pick[1].text[:80]!r}", 1)
    suffix = ("no board item" if pick is None else None if pick[0] == own else f"board {names.get(pick[0], pick[0])}")
    kw = {"fields": fields, "by": by, "answer": label, "suffix": suffix}
    plan = _lb_plan(w, "set", tid, kw)
    if isinstance(plan, int):
        return plan
    if pick is not None and pick[0] == own:
        item = pick[1]
        after = _parts_after(led, item, {path: plan.changes.get(path, text)})
        if not LB.closes(item, label, after):   # it still asks about other parts: answered, left open
            plan = _lb_plan(w, "set", tid, {**kw, "suffix": "shared board item left open"})
            if isinstance(plan, int):
                return plan
    try:
        LBL.apply(plan)
    except OSError as e:
        return w.say("set", f"the write failed, every file restored: {e}", 4)
    if recorded:   # TD-260: the Log names the answer the lift carried out, beside the lift's own line
        note = _lb_plan(w, "note", tid, {"words": f"lifted by a session on {recorded}",
                                         "today": datetime.now(timezone.utc).date().isoformat()})
        try:
            if isinstance(note, int):
                raise OSError("the note was refused")
            LBL.apply(note)
        except OSError as e:
            try:
                LBL.apply(LBL.Plan("set", None, {path: text}, {}))
            except OSError as e2:
                return w.say("set", f"the Log note failed ({e}), and putting {path} back failed: {e2}", 4)
            return w.say("set", f"refused — the Log note naming the answer: {e}; {path} put back, nothing was "
                                "written", 1)
    if pick is None or pick[0] != own:
        print(path)
        return 0
    board = str(w.root / BOARD_REL)
    try:
        bplan = LBB.plan_edit(board, "decide", item.line, item.text.strip()[:40], answer=label,
                              by=by, board_only=True, ledger=str(w.ledger))
        written = LBB.apply(bplan)
    except (LB.Refused, LBL.Unusable, OSError) as e:
        try:
            LBL.apply(LBL.Plan("set", None, {path: text}, {}))
        except OSError as e2:
            return w.say("set", f"the board refused ({e}), and putting {path} back failed: {e2}", 4)
        return w.say("set", f"refused — the board half: {e}; {path} put back, nothing was written", 1)
    if "left_open" in bplan.info:   # v2.7: a shared item still asking about other parts — the board is not written
        w.say("set", f"note — the board item on line {item.line} is left open, unanswered: "
                     f"{', '.join(bplan.info['left_open'])} still carry {gate}; nothing was written to {board}", 0)
    print(path)
    for p in written:   # only what the board half wrote (ledgerboard TD-067 plan, *Consumers*)
        print(p)
    return 0


def _person_board(boards: list[tuple], person: str) -> int | None:
    """The index in ``boards`` (``_boards()``'s order: this repo's, then the roster's by ``origin_key``) of
    *the person's board* (ledgerboard's target design §3.2): the first whose ``People:`` lists them, or None."""
    for i, b in enumerate(boards):
        if person.lower() in {x.lower() for x in LB.board_people(b[2]) or []}:
            return i
    return None


REASSIGN_DUE_DAYS = 7  # the new person's decide item is due a week out (the board's local day)


def _set_moved(w: _Writer, tid: str, fields: dict, by: str, gate: str, to: str | None, why: str | None,
               override: str | None, led: "LBL.Ledger", path: str, text: str) -> int:
    """A reassign (``decision (<a>)`` swapped for ``to``, with ``why``) or an override (``decision (<a>)``
    dropped, ``override`` its why, ``by`` anyone) through ``set`` — ledgerboard's ``reassign_gate()`` or
    ``lift_gate(override=)`` — and the board notices the consumer owes for it (target design §3.1, TD-218):
    a reassign is refused when the new person has no board, closes a's items about the gate as moved, files
    the new person's ``decide`` item and gives a an ``fyi``; an override is refused when a has no board to
    notify, and gives a an ``fyi`` (closing a's items about the gate, which the sweep would close once the
    gate is gone) — but never an item that still asks about another part carrying the gate (a shared parent
    snapshot), which stays open. A notice whose person's board is another roster repo's, and a's item about
    the gate on another roster repo's board, go there by a PR in that repo (TD-226, ``_notices_pr()``: a new
    item's ``Context:`` names ``<this repo>#TD-n``), opened and left for that repo's review, never merged from
    here. Ledger first, then this board, then the other repos' PRs; any refusal restores this repo's two
    files (a PR already opened is named, to close)."""
    from ledgerboard import board as LBB
    a = gate[len("decision ("):-1]
    b = to[len("decision ("):-1] if to else None
    try:
        boards, _, repo = _boards(w)
    except LB.Refused as e:
        return w.say("set", f"refused — the boards: {e}", 1)
    needs = [(b, "the new person's item")] if b else []
    needs.append((a, f"{a}'s notice"))
    where = {}
    for who, what in needs:
        i = _person_board(boards, who)
        if i is None:
            return w.say("set", f"refused — {who} has no board (no People: line names them on this repo's board or "
                                f"a roster board), so {what} has nowhere to go; nothing was written", 1)
        where[who] = i
    kw = {"fields": fields, "by": by, **({"why": why} if b else {"override": override})}
    plan = _lb_plan(w, "set", tid, kw)
    if isinstance(plan, int):
        return plan
    board = str(w.root / BOARD_REL)
    index = {LB.origin_key(bd[0]) or bd[1]: i for i, bd in enumerate(boards)}
    try:
        covered = [(index[bd], it) for bd, it, st in LB.covers(text, gate, boards, repo)
                   if st in ("open", "decided") and bd in index
                   and not _still_asked(led, it, LBL.tid_of(tid), gate)]   # a shared item still asks about others
    except LB.Refused as e:
        return w.say("set", f"refused — the board items for {gate}: {e}", 1)
    items = [it for i, it in covered if i == 0]
    closes: dict[int, list] = {}   # board index -> a's items to close there
    for i, it in covered:
        if i:
            closes.setdefault(i, []).append(it)
    roots = {}
    for i in sorted({i for i in where.values() if i} | set(closes)):
        root = _roster_root(boards[i][0], boards[i][1])
        if root is None:
            return w.say("set", f"refused — {boards[i][1]}'s board was read, but no roster clone of it was found to "
                                "open its PR from; nothing was written", 1)
        roots[i] = root
    old_board = LBB.read(board)
    me = LBL.tid_of(tid)
    said = " ".join((why if b else override).split())
    day = datetime.now().astimezone().date()   # a board date is the person's local day
    adds: dict[int, list[dict]] = {}   # board index -> the items to file there, in order
    if b:
        ask = LB._entry_ask(text, LB.entries(text)[0]["title"])
        adds.setdefault(where[b], []).append(dict(
            text=ask, kind="decide", context=f"{me} decision ({b})",
            due=(day + timedelta(days=REASSIGN_DUE_DAYS)).isoformat(), answers=["Go", "Not yet"], default=0,
            detail={"context": [f"{me}'s decision moved from {a} to you, by {by}: {said}."], "question": ask,
                    "recommended": f"{me} becomes pickable", "otherwise": "it stays blocked"}))
        note = f"{me}'s decision moved from you to {b}, by {by}: {said}"
    else:
        note = f"{me}'s decision ({a}) was lifted by override, by {by}: {said}"
    adds.setdefault(where[a], []).append(dict(text=note, kind="fyi", context=me))
    done_why = f"moved to decision ({b}) by {by}" if b else f"lifted by override by {by}"
    opened: list[str] = []
    try:
        LBL.apply(plan)
        for it in items:   # a done keeps every line where it was
            LBB.apply(LBB.plan_edit(board, "done", it.line, it.text.strip()[:40], why=done_why))
        for spec in adds.get(0, []):
            LBB.apply(LBB.plan_add(board, spec.pop("text"), **spec))
        for i in sorted(roots):
            opened.append(_notices_pr(roots[i], adds.get(i, []), closes.get(i, []), done_why, me, repo, gate, to,
                                      by, said))
    except (LB.Refused, LBL.Unusable, OSError, RuntimeError, subprocess.SubprocessError) as e:
        left = (f"; close the PR already opened: {', '.join(opened)}" if opened else "")
        try:
            LBL.apply(LBL.Plan("set", None, {path: text, board: old_board}, {}))
        except OSError as e2:
            return w.say("set", f"the board refused ({e}), and putting the files back failed: {e2}{left}", 4)
        return w.say("set", f"refused — the board: {e}; both files put back, nothing was written here{left}", 1)
    print(path)
    print(board)
    for url in opened:
        print(url)
    return 0


def _roster_root(url: str, name: str) -> Path | None:
    """The roster clone ``_boards()`` read a board from: the one whose origin is ``url`` (by ``origin_key``),
    else, for a board with no readable origin, the one whose basename is ``name``."""
    key = LB.origin_key(url) if url else None
    for root in N.read_registry() or []:
        if not root.is_dir():
            continue
        u = (_git(root, "remote", "get-url", "origin") or "").strip()
        if (key and LB.origin_key(u) == key) or (not key and not LB.origin_key(u) and root.name == name):
            return root
    return None


def _notices_pr(root: Path, specs: list[dict], closes: list, done_why: str, me: str, repo: str, gate: str,
                to: str | None, by: str, said: str) -> str:
    """File ``specs`` on another roster repo's board, and close ``closes`` there (items as read at its
    ``origin/<default>``), by a PR in that repo (TD-226): a temporary worktree at that ref (gate_sweep.py's
    ``Scratch``, its checkout never touched), each close a ``done`` (which keeps every line where it was), each
    item added with ``Context:`` (and any bare ``TD-n`` in its words) naming ``<repo>#TD-n``, pushed on
    ``notices/<repo>-<TD-n>-<new person | override>`` and opened on that repo's forge (``gh`` run there) —
    left open for its review, never merged from here. Its URL; RuntimeError (or the forge's) when it could not."""
    # sibling SYNC scripts, imported here: gate_sweep imports this module
    import forge as F
    import gate_sweep as G
    from ledgerboard import board as LBB
    xid = f"{repo}#{me}"
    default = N.default_branch(root)
    slug = lambda s: re.sub(r"[^A-Za-z0-9._-]+", "-", s).strip("-")   # noqa: E731
    branch = f"notices/{slug(repo)}-{me}-{slug(to[len('decision ('):-1]).lower() if to else 'override'}"
    bare = re.compile(rf"(?<![#\w]){re.escape(me)}\b")   # a bare TD-n on that board would read as its own
    try:
        be = F.backend(root, cwd=root)   # gh infers the repo from its directory: that repo's, never this one
    except F.ForgeUnreadable as e:
        raise RuntimeError(f"{root.name}'s forge: {e}") from None
    with G.Scratch(root, f"origin/{default}", branch) as wt:
        board = str(wt / BOARD_REL)
        for it in closes:
            LBB.apply(LBB.plan_edit(board, "done", it.line, it.text.strip()[:40], why=done_why))
        for spec in specs:
            s = dict(spec)
            s["context"] = re.sub(r"^TD-\d+", xid, s["context"])
            s["text"] = bare.sub(xid, s["text"])
            if s.get("detail"):
                s["detail"] = {k: [bare.sub(xid, x) for x in v] if isinstance(v, list) else bare.sub(xid, v)
                               for k, v in s["detail"].items()}
            LBB.apply(LBB.plan_add(board, s.pop("text"), **s))
        what = f"moved to {to}" if to else "lifted by override"
        subject = f"board: {xid} {gate} {what} — the notices ({repo}'s ledger.py set)"
        body = (f"`ledger.py set` in {repo} changed {xid}'s `{gate}` ({what}, by {by}: {said}), and the notices it owes "
                f"belong on this repo's board, whose `People:` names the person (TD-226):\n\n"
                + "\n".join([*(f"- close: {it.text.strip()[:80]}" for it in closes),
                             *(f"- [{s['kind']}] {s['text']}" for s in specs)])
                + f"\n\nThis PR belongs with {repo}'s PR carrying that ledger change: merge it once that one is "
                  "merged, and close it if that one is closed. Review it like any PR (cadence.md §4).")
        try:
            return G._ship(root, wt, be, branch, default, subject, body)
        except (F.ForgeUnreadable, RuntimeError) as e:
            raise RuntimeError(str(e).replace(" and sweep again", f" in {root.name}, and run set again")) from None


def _still_asked(led: "LBL.Ledger", item: "LB.BoardItem", tid: str, gate: str) -> bool:
    """Whether a covering item still asks about another open entry: its Context entry or a ``Parts:`` id, other
    than ``tid``, that carries ``gate`` — a shared parent snapshot, left open when ``tid``'s gate moves."""
    key = " ".join(gate.split()).lower()
    return any(" ".join(g.split()).lower() == key
               for x, t in _parts_after(led, item, {}).items() if x != tid
               for g in LBL._decisions(LB.entries(t)[0]["blocked_raw"]))


def _parts_after(led: "LBL.Ledger", item: "LB.BoardItem", changed: Mapping[str, str]) -> dict[str, str]:
    """{TD-n: text} of the open entries a covering item asks about — its Context entry and its bare
    ``Parts:`` — as the lift leaves them (``changed``: path to its new text), for ``closes()``."""
    ref = LB._item_gate(item.text)[0] or ""
    out = {}
    for x in [ref, *item.parts]:
        if "#" in x or not ID_ITEM_RE.match(x):
            continue
        try:
            p, archived = led.entry_file(LBL.tid_of(x))
        except LBL.Unusable:
            continue
        if not archived:
            t = changed.get(p, led.files[p])
            out[LB.entries(t)[0]["id"]] = t
    return out


def _overlay(io: tuple[LB.Ls, LB.Read], changes: Mapping[Path, str | None]) -> tuple[LB.Ls, LB.Read]:
    """``io`` with each path in ``changes`` holding its text, or gone for None (TD-200: a move is both)."""
    ls, read = io
    ch = {os.path.normpath(str(p)): t for p, t in changes.items()}

    def ls2(p: str) -> list[str] | None:
        d = os.path.normpath(p)
        mine = {os.path.basename(q): t for q, t in ch.items() if os.path.dirname(q) == d}
        names = ls(p)
        if not mine:
            return names
        kept = set(names or ()) | {n for n, t in mine.items() if t is not None}
        return sorted(kept - {n for n, t in mine.items() if t is None})

    def read2(p: str) -> str | None:
        q = os.path.normpath(p)
        return ch[q] if q in ch else read(p)
    return ls2, read2






def _links_to(root: Path, name: str) -> list[str]:
    """The lines under ``root`` holding a relative link to a file named ``name`` — dead once it moves."""
    return _grep(root, rf"\]\(([^)]*/)?{re.escape(name)}([#)\s]|$)")




def _entry_file(w: "_Writer", cmd: str, tid: str) -> tuple[Path | None, bool, str]:
    """(the entry's file, whether it is archived, its text); the file None (said, exit 2) when it is in neither."""
    found = LB.entry_path(str(w.ledger), tid, w.io[0])
    if found is None:
        w.say(cmd, f"{tid} is in neither {w.ledger} nor its archive", 2)
        return None, False, ""
    path = Path(found)
    with open(path, encoding="utf-8", newline="") as f:
        return path, path.parent.name == LB.LEDGER_ARCHIVE and path.parent != w.ledger, f.read()


def move(cmd: str, argv: list[str]) -> int:
    """``ledger.py archive|reopen TD-n``: the move through ledgerboard's ``plan_archive()``/``plan_reopen()``
    (TD-216): the entry's edit, its relative links rewritten for the other directory, every link to it in
    the ledger repointed, the gate against origin/<default>, the date the UTC day. This script keeps the
    git I/O: a tracked file's move and the ledger files it rewrote are staged. Commits nothing. Exit by the
    package's table: 1 refused, 2 unusable, 3 needs, 4 the write failed."""
    ap = argparse.ArgumentParser(prog=f"ledger.py {cmd}", description={
        "archive": "archive an open entry: its archived form (cadence.md §2.8), then the file moved to archive/",
        "reopen": "reopen an archived entry: its Status reopened, then the file moved back"}[cmd])
    ap.add_argument("id", metavar="TD-n")
    ap.add_argument("--why", required=True, help="one line: what resolved it (archive) or why it is open again (reopen)")
    if cmd == "archive":
        ap.add_argument("--pr", type=int, help="the PR that resolved it, as the forge numbered it")
        ap.add_argument("--pointer", help="where the lasting content now lives (a doc, test or code)")
        ap.add_argument("--as-is", action="store_true", help="keep the Fix, with the Resolved line after it")
        how = ap.add_mutually_exclusive_group()
        how.add_argument("--superseded-by", metavar="TD-n", help="archive as superseded by that entry, Why and Fix kept")
        how.add_argument("--dropped", action="store_true",
                         help="archive as Dropped: not done, and refused while an entry is Blocked by it")
    ap.add_argument("--ledger", help="a v2 directory; default: docs/ledger/ at the work tree's top")
    a = ap.parse_args(argv)
    if not ID_ITEM_RE.match(a.id):
        ap.error(f"an entry's id is TD-n, not {a.id!r}")
    w = _Writer.open(cmd, a.ledger)
    if isinstance(w, int):
        return w
    try:
        led, base = w.lb_ledgers()
        if cmd == "archive":
            plan = LBL.plan_archive(led, a.id, a.why, pr=a.pr, pointer=a.pointer, as_is=a.as_is,
                                    superseded_by=a.superseded_by, dropped=a.dropped, base=base,
                                    resolve=w.roster.resolve)
        else:
            plan = LBL.plan_reopen(led, a.id, a.why, base=base, resolve=w.roster.resolve)
    except LBL.Unusable as e:
        return w.say(cmd, str(e), 2)
    except LBL.Needs as e:
        return w.say(cmd, f"needs: {e} — nothing was written", 3)
    except LB.Refused as e:
        w.say(cmd, f"refused — {e}", 1)
        return w.say(cmd, f"nothing was written to {LB.entry_path(str(w.ledger), a.id, w.io[0])}", 1)
    src, dst = Path(plan.info["moved"]["from"]), Path(plan.info["moved"]["to"])
    tid = plan.info["id"]
    for n in plan.info.get("notes", []):
        w.say(cmd, f"note — {n}", 0)
    tracked = [Path(p) for p in plan.changes if _git(w.root, "ls-files", "--error-unmatch", "--", p) is not None]
    try:
        LBL.apply(plan)
    except OSError as e:
        return w.say(cmd, f"the write failed, every file restored: {e}", 4)
    if src in tracked:   # staged as git mv stages it: the removal and the new file, which git pairs as a rename
        tracked.append(dst)
    for p in tracked:
        _git(w.root, "add", "-A", "--", str(p))
    print(dst)
    for rid in plan.info.get("rewired", []):
        w.say(cmd, f"note — {rid}'s Blocked by now names {plan.info['successor']}", 0)
    written = {Path(p).resolve().relative_to(w.root.resolve()).as_posix() for p in plan.changes}
    for ln in _links_to(w.root, src.name):
        if ln.split(":", 1)[0] not in written:
            w.say(cmd, f"check — a link to the moved file, left as it was: {ln[:200]}", 0)
    if cmd == "reopen":
        w.say(cmd, f"next: `ledger.py edit {tid} --section Fix --from -` with what is left to do", 0)
    return 0


def _ref_rx(tid: str, repo: str | None = None) -> str:
    """An extended regex (``git grep -E``) for ``tid`` in prose — ``TD-7`` is ``TD-007`` — or for ``<repo>#tid``."""
    n = _num(tid)
    if repo:
        return rf"{re.escape(repo)}#TD-0*{n}([^0-9]|$)"
    return rf"(^|[^A-Za-z0-9_#/.-])TD-0*{n}([^0-9]|$)"


def _grep(root: Path, rx: str, icase: bool = False) -> list[str]:
    out = _git(root, "grep", "-n", "-I", "-E", *(["-i"] if icase else []), "-e", rx)
    return [ln for ln in (out or "").splitlines() if ln.strip()]


def renumber(argv: list[str]) -> int:
    """``ledger.py renumber TD-old [TD-new]``: the entry renamed, its new id from the counter, and every
    Blocked by and Part of naming it rewritten, as is its line in the rank file (TD-200). Commits nothing."""
    ap = argparse.ArgumentParser(prog="ledger.py renumber",
                                 description="give an entry another id: the file, its heading, the fields that name it and the rank file")
    ap.add_argument("old", metavar="TD-old")
    ap.add_argument("new", metavar="TD-new", nargs="?",
                    help="an id already taken from the counter, or one to claim there; default: the counter's next")
    ap.add_argument("--by", help="the take's by (ledger_next_id.py --by), for a front end renumbering for its caller")
    ap.add_argument("--ledger", help="a v2 directory; default: docs/ledger/ at the work tree's top")
    a = ap.parse_args(argv)
    for x in filter(None, (a.old, a.new)):
        if not ID_ITEM_RE.match(x):
            ap.error(f"an entry's id is TD-n, not {x!r}")
    w = _Writer.open("renumber", a.ledger)
    if isinstance(w, int):
        return w
    path, _, text = _entry_file(w, "renumber", a.old)
    if path is None:
        return 2
    old = LB.entries(text)[0]["id"] if LB.entries(text) else a.old
    known = LB.heading_nums(w.text) | LB.heading_nums(w.arch)
    import ledger_next_id as X  # sibling SYNC script: the counter (it imports this one)

    try:
        led, base = w.lb_ledgers()
    except LBL.Unusable as e:
        return w.say("renumber", str(e), 2)

    def plan(tid: str, take: str | None) -> "LBL.Plan | int":
        """The package writer's renumber (TD-188): the file, its heading, every Blocked by, Part of and Log
        ``while`` naming it, its rank line and the ledger's links to it; the take's nonce written as ``Id
        take``, and a ``Taken by`` the old id carried dropped (retired, step 4). The exit code (said) when refused."""
        try:
            p = LBL.plan_renumber(led, a.old, tid, take=take, base=base, resolve=w.roster.resolve)
            dst = p.info["moved"]["to"]   # a Taken by the old id carried names another take: dropped
            if "taken by" in (LB.entries(p.changes[dst])[0]["fields"] if LB.entries(p.changes[dst]) else {}):
                p.changes[dst] = LB.edit_entry(p.changes[dst], "set", fields={"Taken by": ""})
            return p
        except LBL.Unusable as e:
            return w.say("renumber", str(e), 2)
        except LB.Refused as e:
            return w.say("renumber", f"refused — {e}", 1)

    def changes_of(p: "LBL.Plan") -> dict[Path, str | None]:
        return {Path(f): t for f, t in p.changes.items()}

    # Everything but the take is judged first, under a provisional id, so a refusal spends no take.
    provisional = LBL.tid_of(a.new or f"TD-{max(known, default=0) + 1}")   # at §2.2's width, as the package writes it
    if a.new and _num(a.new) in known:
        return w.say("renumber", f"{a.new} is in the ledger or its archive already", 2)
    p = plan(provisional, None)
    if isinstance(p, int):
        return w.say("renumber", "no id was taken and nothing was written", p)
    if w.refused_changes(provisional, changes_of(p), with_ids=False, notes=False):
        return w.say("renumber", "no id was taken and nothing was written", 1)

    takes, why = X.counter_takes(w.root)
    if a.new and takes and _num(a.new) in takes:
        tid, take = X.tid(_num(a.new)), takes[_num(a.new)].get("take")
    else:
        cmd = [sys.executable, str(Path(__file__).with_name("ledger_next_id.py")), "--json", "--ledger", w.rel]
        cmd += (["--claim", a.new] if a.new else []) + (["--by", a.by] if a.by else [])
        r = subprocess.run(cmd, cwd=w.root, capture_output=True, text=True, timeout=120, check=False)
        try:
            res = json.loads(r.stdout)
        except ValueError:
            res = {"ids": [], "why": (r.stderr.strip() or f"exit {r.returncode}")}
        if r.returncode != 0 or not res.get("ids"):
            return w.say("renumber", f"no id was taken — {res.get('why') or why}; nothing was written", 2)
        tid, take = res["ids"][0], res.get("id_take")
    p = plan(tid, take)
    if isinstance(p, int) or w.refused_changes(tid, changes_of(p)):
        return w.say("renumber", f"{tid} is taken and nothing was written — fix the above, then run again "
                                 f"with {old} {tid}", 1)
    src, dst = Path(p.info["moved"]["from"]), Path(p.info["moved"]["to"])
    tracked = _git(w.root, "ls-files", "--error-unmatch", "--", str(src)) is not None
    try:
        LBL.apply(p)
    except OSError as e:
        return w.say("renumber", f"the write failed, every file restored: {e}", 4)
    if tracked:   # the move and its edit staged as git mv stages them; the dependents' edits are left as set's are
        _git(w.root, "add", "-A", "--", str(src), str(dst))
    print(dst)
    for f in p.changes:
        if Path(f) not in (src, dst):
            print(f)
    # What no field holds is the session's to judge: prose here, and <repo>#old in the roster's other repos.
    for ln in _grep(w.root, _ref_rx(old)):
        w.say("renumber", f"check — names {old} in prose: {ln[:200]}", 0)
    me = w.root.resolve().name
    for other in N.read_registry() or []:
        if other.resolve() != w.root.resolve() and other.is_dir():
            for ln in _grep(other, _ref_rx(old, me), icase=True):
                w.say("renumber", f"check — {other.name} names {me}#{old}: {ln[:200]}", 0)
    return 0


def archived_dates(root: Path, rel: str) -> dict[str, str]:
    """Each archived entry's archiving date from git: the UTC day of the newest commit that added
    ``<rel>/archive/TD-n.md`` (a reopen and a second archive takes the later), keyed ``TD-n``. Empty when git
    cannot say. ``migrate``'s ``--closed-dates``, read only for an archived Status with no date of its own."""
    out = _git(root, "log", "--diff-filter=A", "--format=@%ct", "--name-only", "--", f"{rel}/{LB.LEDGER_ARCHIVE}")
    dates: dict[str, str] = {}
    when = None
    for ln in (out or "").splitlines():
        if ln.startswith("@"):
            when = datetime.fromtimestamp(int(ln[1:]), timezone.utc).date().isoformat()
        elif ln.strip() and when:
            m = re.fullmatch(r"TD-0*(\d+)\.md", Path(ln.strip()).name)
            if m:
                dates.setdefault(f"TD-{int(m.group(1)):03d}", when)   # git log is newest first
    return dates


def _undated(ledger: Path, dates: Mapping[str, str]) -> dict[str, str]:
    """``dates`` kept only for the archived entries ``migrate_entry()`` finds no date for in their own text:
    an entry's written day outranks git's, whose commit day can be a day off it (a merge late in the evening,
    or the seed commit for an entry archived before this repo began)."""
    day = datetime.now(timezone.utc).date().isoformat()
    out: dict[str, str] = {}
    for tid, d in dates.items():
        p = ledger / LB.LEDGER_ARCHIVE / f"{tid}.md"
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        if "no date for the Status" in LB.migrate_entry(text, archived=True, today=day)["stops"]:
            out[tid] = d
    return out


def migrate(argv: list[str]) -> int:
    """``ledger.py migrate [TD-n …] --release X.Y [--closed-dates FILE] [--stage-kind WORD=KIND]… [--as TD-n=FORM]…
    [--plan|--dry-run] [--json]``: ledgerboard's ``migrate`` (v2.7, SPEC *Migrating to v2.7*) over this repo's
    ``docs/ledger/`` and its archive — each Status into the closed set (``Open``; ``Resolved D``, ``Superseded D
    by TD-n``, ``Dropped D``), its words moved to the Log, a header ``Location`` into the body. Any stop stops
    the run and writes nothing: give that entry a person's ``--as`` (an open entry's form is ``open``), or ask.
    Unless ``--closed-dates`` is given, an archived entry whose own text gives no date for its Status gets git's
    (``archived_dates()``: the UTC day its archive file was added), as this script passes its other dates. Run ``--plan`` (or ``--dry-run``)
    first, then ``--check`` on the result; nothing is committed — ``--json`` prints the commit subject."""
    if any(x in ("-h", "--help") for x in argv):
        return LBL.run_migrate(argv)
    def given(flag: str) -> str | None:
        for i, x in enumerate(argv):
            if x == flag and i + 1 < len(argv):
                return argv[i + 1]
            if x.startswith(flag + "="):
                return x[len(flag) + 1:]
        return None
    ledger = given("--ledger")
    args = list(argv) if ledger else [*argv, "--ledger", str(ledger := str(_toplevel() / LEDGER_DIR_REL))]
    if given("--closed-dates") is None:
        root, rel, _ = _rel(Path(ledger))
        dates = _undated(Path(ledger), archived_dates(root, rel) if root is not None else {})
        if dates:
            fd, tmp = tempfile.mkstemp(prefix="ledger-migrate-", suffix=".json")
            try:
                with os.fdopen(fd, "w") as f:
                    json.dump(dates, f)
                return LBL.run_migrate(args + ["--closed-dates", tmp])
            finally:
                os.unlink(tmp)
    return LBL.run_migrate(args)


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["fmt"]:
        return fmt(argv[1:])
    if argv[:1] == ["new"]:
        return new(argv[1:])
    if argv[:1] in (["set"], ["note"], ["edit"]):
        return edit(argv[0], argv[1:])
    if argv[:1] in (["archive"], ["reopen"]):
        return move(argv[0], argv[1:])
    if argv[:1] == ["renumber"]:
        return renumber(argv[1:])
    if argv[:1] == ["lift"]:
        return lift(argv[1:])
    if argv[:1] == ["migrate"]:
        return migrate(argv[1:])
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
            if v2 and root:   # judged against where the edit started, as the archive is (TD-201)
                at = (lambda p: io[0](str(root / p))), (lambda p: io[1](str(root / p)))
                start = git_io(root, (fork or a.since).strip())
                if start is not None:   # unlisted: not judged, rather than every entry judged new
                    recs += canonical_flags(_rel(ledger)[1], at, start)
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
    return report(argv, ledger, None if v2 else archive)


def report(argv: list[str], ledger: Path, archive: Path | None, roster: Roster | None = None) -> int:
    """--pickable, --list, --counts, --fields, --summary: ledgerboard's ``run_report`` (TD-216), given the
    ledger's path and this machine's roster as its ``--resolved`` file (target design §1.1). The package names
    the ``<repo>#TD-n`` ids it needs (exit 3, ``needs:``), which are resolved and the report run again, until
    nothing is needed; only the last run's output is printed. The day is the UTC day (``_today``, TD-253)."""
    roster = roster or Roster()
    answers: dict[str, dict] = {}
    with tempfile.TemporaryDirectory(prefix="ledger-report-") as tmp:
        path = Path(tmp) / "resolved.json"
        for _ in range(64):   # each round resolves at least one new id, so a supersede chain ends
            path.write_text(json.dumps(answers), encoding="utf-8")
            out, err = StringIO(), StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = LBL.run_report([*argv, "--ledger", str(ledger), *(["--archive", str(archive)] if archive else []),
                                     "--resolved", str(path), "--today", str(_today(None))])
            seen = {k.lower() for k in answers}   # the package reads its keys case-insensitively
            new = [m.group(0) for m in NEEDS_ID_RE.finditer(out.getvalue() + err.getvalue())
                   if m.group(0).lower() not in seen] if rc == 3 else []
            if not new:
                break
            for item in new:
                answers[item] = roster.resolve(item)
    sys.stdout.write(out.getvalue())
    sys.stderr.write(err.getvalue().replace("ledgerboard.ledger: ", "ledger: "))
    return rc


if __name__ == "__main__":
    sys.exit(main())
