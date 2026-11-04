#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/board_edit.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""Write the attention board, the same way for every tool and every session (TD-036, TD-206).

    board_edit.py snooze --board PATH --line N --expect HEAD --to YYYY-MM-DD
    board_edit.py due    --board PATH --line N --expect HEAD --to YYYY-MM-DD
    board_edit.py done   --board PATH --line N --expect HEAD [--why TEXT]
    board_edit.py decide --board PATH --line N --expect HEAD --answer TEXT [--by NAME]
    board_edit.py reply  --board PATH --line N --expect HEAD --text TEXT [--by NAME]
        [--tool NAME] [--session NAME] [--no-commit]
    board_edit.py add     --board PATH --text TEXT [ledgerboard's add flags] [--no-commit]
    board_edit.py archive --board PATH [--archive PATH] [--no-commit]
    board_edit.py fmt     --board PATH
    board_edit.py list    --board PATH [--json]

The action comes first. A wrapper (TD-213): every edit is ledgerboard's board writer's (``ledgerboard/board.py``'s
``plan_edit()``, ShiftLead/ledgerboard v2.3 — the formats and their edits defined once, imported,
never re-typed); what this script adds is git — the clean-board check, and the commit under
cadence.md §4.5's fixed message.

snooze  hides the item until the date: sets its ``Hide until:`` (ledgerboard v2.3) and leaves
        ``Due:``, the real deadline, as it is. A hidden item stays on the board and is
        left out of what needs the person (``needs_you``: the reports, the SessionStart
        line, the escalation) until then; a decided item is never hidden.
due     moves the item's ``Due:`` date, the real deadline (adds one when it has none).
done    closes the item: ``- [ ]`` becomes ``- [x]`` and ``Closed: YYYY-MM-DD[ — TEXT].``
        is appended (``--why``), and the readers stop listing it. The line stays on the
        board — closing never deletes (TD-062). When the close leaves ``ARCHIVE_AT`` (10)
        or more closed items on the board, the same write archives them (as ``archive``),
        one commit of the board and ``user_attention_archive.md`` beside it, under
        ``<tool>: done <head>; archived <n> (session <name>)`` (TD-206); where the archive
        refuses (a nested or broken detail block) the close lands alone, with a warning.
decide  records the person's answer: ``Decided: TEXT (by NAME) (today).`` at the end of the
        line, replacing an earlier one. TEXT may be one of the item's ``Answers:`` or any
        free text. NAME (``--by``) is who answered, never git's ``user.name``: on a board
        whose ``People:`` line names one person it defaults to them; otherwise it is
        required, and must be on that line. A decided item stays on the board, and stays
        due, until a session acts on it and closes it — the session's work order (cadence.md §3).
reply   appends what the person says back to the item's session, on the item's own line
        (TD-075): `` — NAME, today: TEXT``, after any earlier reply and ahead of the
        trailing ``Answers:``/``Decided:`` fields, which keep their place and their
        meaning. NAME (``--by``) is who says it: on a board whose ``People:`` line names
        one person it defaults to them, as decide's does; otherwise it is required
        (git's ``user.name`` proves nothing, TD-206). A reply decides nothing and closes nothing —
        the item stays the person's, or the session's, exactly as it was. Refused when
        TEXT carries a field's name (``Context:``, ``Hide until:``, ``Answers:``,
        ``Decided:``, ``Closed:``), or a ``Due:`` on an item that has none (the reader
        would take it for the item's).

add     a new item of any kind, at the top of ``## Needs the user`` (or ``--under``), as
        ledgerboard's ``item_line()`` writes it; the flags are ``ledgerboard/board.py``'s
        own, passed through unchanged (``--kind``, ``--text``, ``--context``, ``--due``,
        ``--answer`` repeated, ``--default`` its 0-based index, ``--lift``, ``--detail``
        a JSON object of the detail block's parts, ``--hide-until``, ``--session``,
        ``--host``, ``--said``/``--decided`` with ``--by``, ``--today``). Prints the line
        number it wrote. Committed under ``<tool>: append <head> (session <name>)``; it
        rides the session's own reviewed PR (cadence.md §3.4).
archive moves every closed item, with its detail block and any open twin, to the archive
        (``--archive``, by default ``user_attention_archive.md`` beside the board), one
        commit of the two files under ``<tool>: archive <n> closed items (session <name>)``.
fmt     rewrites each open item line into the writers' form where that keeps its key, and
        lists the lines it kept as they were; it commits nothing (its caller's PR does).
list    the open items: line, due tag and text, or ``--json``.

``--plan`` (add, archive, fmt) prints the write as JSON and makes none.

``--line`` is the 1-based line ``nudge_user_attention.py --report --json`` prints for
the item, and ``--expect`` the start of its text (or of the raw line) as the tool last
showed it. The edit is refused, exit 3, when line N is not an open item or no longer
starts with HEAD — the board moved under the tool — or when the board declares a newer major
of the format than the vendored ledgerboard reads (``Ledgerboard: N``, TD-133). Only line N is
rewritten; the ``Swept:``/``Swept-deep:`` stamps and every other line keep their bytes.

Unless ``--no-commit``, the edit is committed on its own, board file only (with its archive
when a ``done`` archives), with the
fixed message of cadence.md §4's tool-made-edit carve-out —
``<tool>: <action> <item head>[ to <date> | : <answer>] (session <name>)`` (a reply's
words stay on the board, never in the message) — where
``<name>`` is the session the item names (``(session <id> …``), or ``--session``. A
board with uncommitted changes is refused before anything is written, since the commit
would carry them. The script never pushes: the tool runs it in a tree of its own at
origin's head and lands the commit by a PR it opens and squash-merges at once, titled
with this message (cadence.md §4.5, TD-083) — or, where the forge takes a direct push,
pushes it under ``ALLOW_MAIN_PUSH=1``.

Exit: 0 edited (and committed); 1 git failed (the files are restored); 2 usage; 3 refused.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledgerboard as LB  # noqa: E402  # sibling SYNC package: the board format (ShiftLead/ledgerboard v2.3)
from ledgerboard import (  # noqa: E402,F401  # re-exported: tests reach them as board_edit.<name>
    Refused,
    edit_line,
)
from ledgerboard import (
    board as LBB,  # noqa: E402  # sibling SYNC package: the board writer (ShiftLead/ledgerboard v2.3)
)
from ledgerboard import edit_head as item_head  # noqa: E402,F401


def _git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=30, check=False)


TOOL = "board_edit"
PASSTHROUGH = ("add", "archive", "fmt", "list")  # ledgerboard/board.py's own commands, its flags unchanged
COMMITS = ("add", "archive")  # of those, the ones this script commits (fmt's caller names its commit)
ARCHIVE_NAME = "user_attention_archive.md"  # beside the board (cadence.md §3.4)


def _root(path: Path) -> Path:
    r = _git(path.parent, "rev-parse", "--show-toplevel")
    if r.returncode != 0:
        raise Refused(f"{path} is not in a git work tree (pass --no-commit to edit only)")
    return Path(r.stdout.strip())


def _clean(root: Path, paths: list[str]) -> None:
    r = _git(root, "status", "--porcelain", "--", *paths)
    if r.returncode != 0 or r.stdout.strip():
        raise Refused(f"{', '.join(paths)} has uncommitted changes; the commit would carry "
                      "them — commit or discard them first")


def _commit(root: Path, plan: LBB.Plan) -> str | None:
    """Make the plan's writes and commit those files alone under its subject; the short sha, or None
    with every file put back as it was (a file the plan created is removed) when git fails."""
    olds = {p: (Path(p).read_bytes() if Path(p).exists() else None) for p in plan.changes}
    LBB.apply(plan)
    paths = list(plan.changes)
    r = _git(root, "add", "--", *paths)
    if r.returncode == 0:
        r = _git(root, "commit", "-q", "-m", plan.subject, "--", *paths)
    if r.returncode != 0:
        _git(root, "reset", "-q", "--", *paths)
        for p, old in olds.items():
            if old is None:
                Path(p).unlink(missing_ok=True)
            else:
                Path(p).write_bytes(old)
        print(f"board_edit: git commit failed, files restored: {r.stderr.strip()}", file=sys.stderr)
        return None
    return _git(root, "rev-parse", "--short", "HEAD").stdout.strip()


def with_archive(plan: LBB.Plan, board: str, archive: str) -> LBB.Plan:
    """A `done` plan, widened to archive in the same write when the close leaves ARCHIVE_AT or more closed
    items (TD-206): the board and the archive as ``archive_closed()`` leaves them, the subject's ``<n>``
    just before `` (session``. Unchanged, with a warning, when the archive refuses."""
    new = plan.changes[board]
    n = len(LB.closed_items(new))
    if n < LB.ARCHIVE_AT:
        return plan
    try:
        nb, na = LB.archive_closed(new, LBB.read(archive, missing_ok=True))
    except Refused as e:
        print(f"board_edit: warning: {n} closed items, but the archive refused ({e}); closed only — "
              f"run `board_edit.py archive` once the board is fixed by hand", file=sys.stderr)
        return plan
    head, sep, tail = plan.subject.rpartition(" (session ")
    return LBB.Plan(plan.action, f"{head}; archived {n}{sep}{tail}", {archive: na, board: nb},
                    {**plan.info, "archived": n})


def passthrough(argv: list[str]) -> int:
    """add, archive, fmt and list: ledgerboard/board.py's commands with its flags (TAKES), plus the commit."""
    ap = LBB.parser()
    ap.prog = "board_edit.py"
    ap.add_argument("--no-commit", action="store_true", help="add, archive: write the files only")
    ap.set_defaults(tool=TOOL)
    a = ap.parse_args(argv)
    if a.action not in PASSTHROUGH:
        ap.error(f"{a.action}: board_edit.py's own commands are snooze, due, done, decide, reply, "
                 f"{', '.join(PASSTHROUGH)}")
    defaults = {**LBB.DEFAULTS, "tool": TOOL}
    given = {k for k, v in vars(a).items()
             if k not in ("action", "plan", "json", "no_commit") and v is not None and v != defaults.get(k)}
    extra = sorted(given - LBB.TAKES[a.action])
    if a.no_commit and a.action not in COMMITS:
        extra.append("no_commit")
    if extra:
        ap.error(f"{a.action} does not take {', '.join('--' + e.replace('_', '-') for e in extra)}")
    if a.action == "archive" and a.board:  # absolute, so git (run at the root) and the write name one file
        a.archive = str(Path(a.archive).resolve() if a.archive else Path(a.board).resolve().parent / ARCHIVE_NAME)
    missing = [o for o in LBB.NEEDS_OPT[a.action] if getattr(a, o) in (None, [])]
    if missing:
        ap.error(f"{a.action} needs {', '.join('--' + o for o in missing)}")
    a.board = str(Path(a.board).resolve())
    try:
        if a.action == "list":
            got = LBB.items(a.board, a.today)
            if a.json:
                print(json.dumps({"action": "list", "items": got}, ensure_ascii=False, default=str))
            else:
                for r in got:
                    print(f"{r['line']}\t{r['due_tag'] or '-'}\t{r['text']}")
            return 0
        root = _root(Path(a.board)) if a.action in COMMITS and not (a.no_commit or a.plan) else None
        plan = LBB.build(a)
        if root is not None and plan.changes:
            _clean(root, list(plan.changes))
    except Refused as e:
        print(f"board_edit: refused: {e}", file=sys.stderr)
        return 3
    if a.plan:
        print(json.dumps(plan.as_json(), ensure_ascii=False))
        return 0
    if a.action == "fmt":
        try:
            LBB.apply(plan)
        except OSError as e:
            print(f"board_edit: cannot write {a.board}: {e}", file=sys.stderr)
            return 1
        for r in plan.info["refused"]:
            print(f"board_edit: fmt: line {r['line']} kept as it is: {r['why']}", file=sys.stderr)
        fixed = plan.info["fixed"]
        print(f"board_edit: fmt rewrote {len(fixed)} line(s){': ' + ', '.join(map(str, fixed)) if fixed else ''}, "
              f"kept {len(plan.info['refused'])} (not committed: commit it in your PR)")
        return 0
    where = f" line {plan.info['line']}" if "line" in plan.info else f" {plan.info.get('moved')} closed item(s)"
    if root is None:
        try:
            LBB.apply(plan)
        except OSError as e:
            print(f"board_edit: cannot write: {e}", file=sys.stderr)
            return 1
        print(f"board_edit: {a.action}{where} (not committed)")
        return 0
    sha = _commit(root, plan)
    if sha is None:
        return 1
    print(f"board_edit: {a.action}{where} — committed {sha}: {plan.subject} (not pushed)")
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] in PASSTHROUGH:
        return passthrough(argv)
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0],
                                 epilog=f"also: {', '.join(PASSTHROUGH)} — ledgerboard/board.py's own "
                                        "commands, its flags (`board_edit.py <command> --help`)")
    ap.add_argument("action", choices=("snooze", "due", "done", "decide", "reply"))
    ap.add_argument("--board", required=True, help="the board file (docs/user_attention.md)")
    ap.add_argument("--line", type=int, required=True, help="1-based line of the item")
    ap.add_argument("--expect", required=True, help="the start of the item's text as last shown")
    ap.add_argument("--to", help="snooze: hide until this date; due: the new Due: date (YYYY-MM-DD)")
    ap.add_argument("--answer", help="decide: the person's answer")
    ap.add_argument("--why", help="done: why it is closed, for the Closed: field")
    ap.add_argument("--text", help="reply: what the person says back to the item's session")
    ap.add_argument("--by", help="reply: who says it; decide: who answered "
                                 "(both default to the board's one People: name)")
    ap.add_argument("--tool", default=TOOL, help="names the tool in the commit message")
    ap.add_argument("--session", help="the session named in the commit message (default: the item's)")
    ap.add_argument("--no-commit", action="store_true", help="edit the file only")
    a = ap.parse_args(argv)

    if a.action in ("snooze", "due"):
        if not a.to or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", a.to):
            ap.error(f"{a.action} needs --to YYYY-MM-DD")
        try:
            date.fromisoformat(a.to)
        except ValueError:
            ap.error(f"--to {a.to} is not a date")
    elif a.to:
        ap.error("--to is for snooze and due only")
    if a.action == "decide" and a.answer is None:
        ap.error("decide needs --answer")
    if a.action != "decide" and a.answer is not None:
        ap.error("--answer is for decide only")
    if a.action != "done" and a.why is not None:
        ap.error("--why is for done only")
    if a.action == "reply" and a.text is None:
        ap.error("reply needs --text")
    if a.action != "reply" and a.text is not None:
        ap.error("--text is for reply only")
    if a.action not in ("reply", "decide") and a.by is not None:
        ap.error("--by is for reply and decide only")
    if not a.expect.strip():
        ap.error("--expect is empty — pass the item's text as the tool showed it")

    board = Path(a.board).resolve()
    archive = str(board.parent / ARCHIVE_NAME)
    root = None
    try:
        if not a.no_commit:
            root = _root(board)
        by = a.by
        if a.action == "reply" and not (by or "").strip():
            try:
                by = LBB.who_answered(LBB.read(str(board)), None)
            except Refused as e:
                raise Refused(f"reply needs --by, who says it ({e})") from None
        plan = LBB.plan_edit(str(board), a.action, a.line, a.expect, to=a.to, why=a.why, answer=a.answer,
                             text=a.text, by=by, tool=a.tool, session=a.session)
        if a.action == "done":
            plan = with_archive(plan, str(board), archive)
        if root is not None:
            _clean(root, list(plan.changes))
    except Refused as e:
        print(f"board_edit: refused: {e}", file=sys.stderr)
        return 3

    what = (f" to {a.to}" if a.action in ("snooze", "due")
            else f": {' '.join(a.answer.split())}" if a.action == "decide" else "")
    if "archived" in plan.info:
        what += f"; archived {plan.info['archived']} closed items"
    if a.no_commit:
        try:
            LBB.apply(plan)
        except OSError as e:
            print(f"board_edit: cannot write {board}: {e}", file=sys.stderr)
            return 1
        print(f"board_edit: {a.action} line {a.line}{what} (not committed)")
        return 0
    try:
        sha = _commit(root, plan)
    except OSError as e:
        print(f"board_edit: cannot write {board}: {e}", file=sys.stderr)
        return 1
    if sha is None:
        return 1
    print(f"board_edit: {a.action} line {a.line}{what} — committed {sha} (not pushed; "
          "cadence.md §4.5: land it by its own PR, or push with ALLOW_MAIN_PUSH=1)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
