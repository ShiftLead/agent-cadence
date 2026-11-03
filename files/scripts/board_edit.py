#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/board_edit.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""Make one tool-made edit to one attention-board item, the same way for every tool (TD-036).

    board_edit.py snooze --board PATH --line N --expect HEAD --to YYYY-MM-DD
    board_edit.py due    --board PATH --line N --expect HEAD --to YYYY-MM-DD
    board_edit.py done   --board PATH --line N --expect HEAD [--why TEXT]
    board_edit.py decide --board PATH --line N --expect HEAD --answer TEXT [--by NAME]
    board_edit.py reply  --board PATH --line N --expect HEAD --text TEXT [--by NAME]
        [--tool NAME] [--session NAME] [--no-commit]

A wrapper (TD-213): every edit is ledgerboard's board writer's (``ledgerboard/board.py``'s
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
        board — closing never deletes (TD-062); a sweep archives closed items later.
decide  records the person's answer: ``Decided: TEXT (by NAME) (today).`` at the end of the
        line, replacing an earlier one. TEXT may be one of the item's ``Answers:`` or any
        free text. NAME (``--by``) is who answered, never git's ``user.name``: on a board
        whose ``People:`` line names one person it defaults to them; otherwise it is
        required, and must be on that line. A decided item stays on the board, and stays
        due, until a session acts on it and closes it — the session's work order (cadence.md §3).
reply   appends what the person says back to the item's session, on the item's own line
        (TD-075): `` — NAME, today: TEXT``, after any earlier reply and ahead of the
        trailing ``Answers:``/``Decided:`` fields, which keep their place and their
        meaning. NAME (``--by``) is who says it: by default the checkout's git
        ``user.name``, else ``the person``. A reply decides nothing and closes nothing —
        the item stays the person's, or the session's, exactly as it was. Refused when
        TEXT carries a field's name (``Context:``, ``Hide until:``, ``Answers:``,
        ``Decided:``, ``Closed:``), or a ``Due:`` on an item that has none (the reader
        would take it for the item's).

``--line`` is the 1-based line ``nudge_user_attention.py --report --json`` prints for
the item, and ``--expect`` the start of its text (or of the raw line) as the tool last
showed it. The edit is refused, exit 3, when line N is not an open item or no longer
starts with HEAD — the board moved under the tool — or when the board declares a newer major
of the format than the vendored ledgerboard reads (``Ledgerboard: N``, TD-133). Only line N is
rewritten; the ``Swept:``/``Swept-deep:`` stamps and every other line keep their bytes.

Unless ``--no-commit``, the edit is committed on its own, board file only, with the
fixed message of cadence.md §4's tool-made-edit carve-out —
``<tool>: <action> <item head>[ to <date> | : <answer>] (session <name>)`` (a reply's
words stay on the board, never in the message) — where
``<name>`` is the session the item names (``(session <id> …``), or ``--session``. A
board with uncommitted changes is refused before anything is written, since the commit
would carry them. The script never pushes: the tool runs it in a tree of its own at
origin's head and lands the commit by a PR it opens and squash-merges at once, titled
with this message (cadence.md §4.5, TD-083) — or, where the forge takes a direct push,
pushes it under ``ALLOW_MAIN_PUSH=1``.

Exit: 0 edited (and committed); 1 git failed (the board is restored); 2 usage; 3 refused.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
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


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("action", choices=("snooze", "due", "done", "decide", "reply"))
    ap.add_argument("--board", required=True, help="the board file (docs/user_attention.md)")
    ap.add_argument("--line", type=int, required=True, help="1-based line of the item")
    ap.add_argument("--expect", required=True, help="the start of the item's text as last shown")
    ap.add_argument("--to", help="snooze: hide until this date; due: the new Due: date (YYYY-MM-DD)")
    ap.add_argument("--answer", help="decide: the person's answer")
    ap.add_argument("--why", help="done: why it is closed, for the Closed: field")
    ap.add_argument("--text", help="reply: what the person says back to the item's session")
    ap.add_argument("--by", help="reply: who says it (default: git user.name, else 'the person'); "
                                 "decide: who answered (default: the board's one People: name)")
    ap.add_argument("--tool", default="board_edit", help="names the tool in the commit message")
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
    root = None
    try:
        if not a.no_commit:
            r = _git(board.parent, "rev-parse", "--show-toplevel")
            if r.returncode != 0:
                raise Refused(f"{board} is not in a git work tree (pass --no-commit to edit only)")
            root = Path(r.stdout.strip())
        by = a.by
        if a.action == "reply" and not (by or "").strip():
            by = _git(board.parent, "config", "user.name").stdout.strip() or "the person"
        plan = LBB.plan_edit(str(board), a.action, a.line, a.expect, to=a.to, why=a.why, answer=a.answer,
                             text=a.text, by=by, tool=a.tool, session=a.session)
        if root is not None:
            r = _git(root, "status", "--porcelain", "--", str(board))
            if r.returncode != 0 or r.stdout.strip():
                raise Refused(f"{board} has uncommitted changes; the carve-out commit would carry "
                              "them — commit or discard them first")
    except Refused as e:
        print(f"board_edit: refused: {e}", file=sys.stderr)
        return 3

    what = (f" to {a.to}" if a.action in ("snooze", "due")
            else f": {' '.join(a.answer.split())}" if a.action == "decide" else "")
    raw = board.read_bytes()
    try:
        LBB.apply(plan)
    except OSError as e:
        print(f"board_edit: cannot write {board}: {e}", file=sys.stderr)
        return 1
    if a.no_commit:
        print(f"board_edit: {a.action} line {a.line}{what} (not committed)")
        return 0
    r = _git(root, "commit", "-q", "-m", plan.subject, "--", str(board))
    if r.returncode != 0:
        board.write_bytes(raw)
        print(f"board_edit: git commit failed, board restored: {r.stderr.strip()}", file=sys.stderr)
        return 1
    sha = _git(root, "rev-parse", "--short", "HEAD").stdout.strip()
    print(f"board_edit: {a.action} line {a.line}{what} — committed {sha} (not pushed; "
          "cadence.md §4.5: land it by its own PR, or push with ALLOW_MAIN_PUSH=1)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
