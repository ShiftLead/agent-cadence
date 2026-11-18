#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/board_edit.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""Write the attention board, the same way for every tool and every session (TD-036, TD-206, TD-263).

    board_edit.py add    --board PATH --text TEXT [ledgerboard's add flags] [--no-commit] [--json]
    board_edit.py snooze --board PATH --id ID --to YYYY-MM-DD
    board_edit.py due    --board PATH --id ID --to YYYY-MM-DD
    board_edit.py done   --board PATH --id ID [--why TEXT]
    board_edit.py decide --board PATH --id ID --answer TEXT [--by NAME] [--delegate NAME] [--ledger DIR | --board-only]
    board_edit.py reply  --board PATH --id ID --text TEXT [--by NAME]
        [--tool NAME] [--session NAME] [--today YYYY-MM-DD] [--no-commit] [--json]
    board_edit.py fmt    --board PATH
    board_edit.py list   --board PATH [--json]
    board_edit.py show   --board PATH [--hidden]

The action comes first. A wrapper (TD-213): every write is ledgerboard's board writer's (``ledgerboard/board.py``,
the vendored ShiftLead/ledgerboard v3.0 — the board is a directory of item files, ``<id>.md``, closed ones under
``archive/<YYYY-MM>/``; the formats and their edits defined once, imported, never re-typed); its flags are
``board.py``'s own, passed through unchanged. What this script adds is git — the clean-files check and the
commit under cadence.md §4.5's fixed message — and three things of the cadence's own: a reply's form press, the
person-session refusal on a decide lift, and ``reply``'s ``--by`` defaulting to the board's one ``People:`` name.

``--board`` is the board: its directory (``docs/user_attention/``) or the stub beside it
(``docs/user_attention.md``), which name one board. A write needs a v3 board; a v2 board file is refused with
``board.py``'s ``not a v3 board: a v2 board (split first: board.py split)``. ``list`` and ``show`` read either.

add     a new item file, as ledgerboard's ``item_file()`` writes it, its id drawn (or ``--id``); the flags
        are ``board.py``'s (``--kind``, ``--text``, ``--context``, ``--due``, ``--answer`` repeated,
        ``--default`` its 0-based index, ``--lift``, ``--parts``, ``--detail`` a JSON object of the detail
        block's parts, ``--doer`` an act's ``Doer:``, ``--scope`` a decide's ``Scope:``
        (the kind of decision a delegate may answer, v3.4), ``--hide-until``, ``--session``, ``--host``,
        ``--said``/``--decided`` with ``--by``, ``--today``). Prints the id it wrote. Committed under
        ``<tool>: append <id> <head> (session <name>)``; it rides the session's own reviewed PR (cadence.md §3.4).
snooze  hides the item until the date (``Hide until:``) and leaves ``Due:``, the real deadline, as it is.
due     moves the item's ``Due:`` date (adds one when it has none).
done    closes the item: its file, with ``Closed: YYYY-MM-DD[ — TEXT]`` (``--why``), moves to
        ``archive/<YYYY-MM>/`` in the same write — closing never deletes (TD-062).
decide  records the person's answer (``Decided:``); an answer that begins with a form's head and its colon
        fills that form (``fill_form()``, TD-254). ``--by`` is who answered, never git's ``user.name``: on a
        board whose ``People:`` names one person it defaults to them. An item whose Context names one entry of
        this repo and its gate (``TD-n decision (<p>)``) is the decide lift: a lifting answer also lifts the gate
        in ``ledger/`` beside the board (or ``--ledger``), item and entry in the one commit, and a closing answer
        archives the item — refused unless the running session is a person's own (``agent_sessions``'
        ``person_session_refusal()``, TD-218). ``--delegate NAME`` (ledgerboard v3.4, TD-292) writes a delegate's
        answer for ``--by`` in the delegated form, ``Decided: <date> by <delegate> for <person> (<scope>) —
        <answer>``, refused unless the item has a ``Scope:`` and the board's ``Delegates:`` grant covers it
        (cadence.md §3.4); the person-session refusal holds for a delegated decide lift too.
reply   appends what the person says back to the item's Log (``- <today>: <by>: <words>``). ``--by`` defaults
        to the board's one ``People:`` name. A reply decides nothing — except a form's press (TD-254, ShiftLead
        TD-1557): on an open, undecided ``decide`` or ``look`` item (or a ``watch`` carrying the look's *Works* /
        ``Not right:`` pair), TEXT that begins with one of its forms' heads and its colon is that form filled,
        and the edit is the decide, by decide's own road (``reply_fills_form()``).
fmt     rewrites each open item file into the writers' form and lists the files it kept; commits nothing.
list    the open items: id, due tag and words, or ``--json``.  show: the board for a person.

``--plan`` (every write) prints the write as JSON and makes none.

ledgerboard v3.0 retired, here as in the module: ``--line`` and ``--expect`` (an item is named by ``--id``, as
``list`` and ``nudge_user_attention.py --report --json`` print it), ``archive`` (``done`` archives the item
itself) and ``replay`` (TD-248: there is no single board file left to replay a conflict into; two writes to one
board touch two files, or conflict on the one item both edited). Each is refused by name, exit 2.

Unless ``--no-commit``, the write is committed on its own, the files it changed alone, with the fixed message of
cadence.md §4's tool-made-edit carve-out — ``<tool>: <action> <id> <head>[ to <date> | : <answer>] (session
<name>)`` (ledgerboard's ``subject()``; a reply's words stay on the board, never in the message) — where
``<name>`` is ``--session``, else the item's ``Session``. A file the write changes that has uncommitted changes is
refused before anything is written, since the commit would carry them. The script never pushes: the tool runs it
in a tree of its own at origin's head and lands the commit by a PR it opens and squash-merges at once, titled with
this message (cadence.md §4.5, TD-083) — or, where the forge takes a direct push, pushes it under
``ALLOW_MAIN_PUSH=1``.

Exit, by ledgerboard's one table for its writers (SPEC *The board writer*; TD-215): 0 written (and committed);
1 refused; 2 usage (a bad ``--today``, a ledger that cannot be used, a retired flag or command); 4 a write or git
failed (the files are restored). It never exits 3, the ledger writer's ``needs``.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agent_sessions  # noqa: E402  # sibling SYNC script: the session adapter — who is running a lift (TD-218)
import ledgerboard as LB  # noqa: E402  # sibling SYNC package: the board format (ShiftLead/ledgerboard; the vendored tag is tests/ledgerboard.MANIFEST's)
import person_text as PT  # noqa: E402  # sibling SYNC script: text a person reads, checked at its writer (TD-268)
from ledgerboard import (
    Refused,  # noqa: E402,F401  # re-exported: tests reach it as board_edit.Refused
)
from ledgerboard import (
    board as LBB,  # noqa: E402  # sibling SYNC package: the board writer (ShiftLead/ledgerboard v3.0)
)

TOOL = "board_edit"
ACTIONS = ("add", "snooze", "due", "done", "decide", "reply", "fmt", "list", "show")  # board.py's, as they are
WRITES = ("add", *LBB.EDITS)  # the writes this script commits (fmt's caller names its commit)
RETIRED = {
    "archive": "ledgerboard v3.0 retired `archive`: `done` moves the item's file into archive/ itself",
    "replay": "ledgerboard v3.0 retired `replay` (TD-248): the board is a directory of item files, so there is no "
              "single file to replay a conflict into — keep both sides' item files",
}
RETIRED_FLAGS = ("--line", "--expect")


def _git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=30, check=False)


def _root(board: Path) -> Path:
    here = board if board.is_dir() else board.parent
    r = _git(here, "rev-parse", "--show-toplevel")
    if r.returncode != 0:
        raise Refused(f"{board} is not in a git work tree (pass --no-commit to write only)")
    return Path(r.stdout.strip())


def _clean(root: Path, paths: list[str]) -> None:
    r = _git(root, "status", "--porcelain", "--", *paths)
    if r.returncode != 0 or r.stdout.strip():
        raise Refused(f"{', '.join(paths)} has uncommitted changes; the commit would carry "
                      "them — commit or discard them first")


def _commit(root: Path, plan: LBB.Plan) -> str | None:
    """Make the plan's writes (a removal among them) and commit those files alone under its subject; the short
    sha, or None with every file put back as it was (a file the plan created is removed) when git fails."""
    olds = {p: (Path(p).read_bytes() if Path(p).exists() else None) for p in plan.changes}
    LBB.apply(plan)
    paths = list(plan.changes)
    r = _git(root, "add", "-A", "--", *paths)
    if r.returncode == 0:
        r = _git(root, "commit", "-q", "-m", plan.subject, "--", *paths)
    if r.returncode != 0:
        _git(root, "reset", "-q", "--", *paths)
        for p, old in olds.items():
            if old is None:
                Path(p).unlink(missing_ok=True)
            else:
                Path(p).parent.mkdir(parents=True, exist_ok=True)
                Path(p).write_bytes(old)
        print(f"board_edit: git commit failed, files restored: {r.stderr.strip()}", file=sys.stderr)
        return None
    return _git(root, "rev-parse", "--short", "HEAD").stdout.strip()


def reply_fills_form(item: LB.BoardItem | None, text: str) -> str | None:
    """The filled form a reply's ``text`` presses on ``item``, or None when it is a reply (TD-254, ShiftLead
    TD-1557 §4.4 *A Reply that fills a form decides*). On an open, undecided ``decide`` or ``look`` item, or a
    ``watch`` carrying the look's pair (*Works* and a ``Not right:`` form), words that begin with one of the
    item's forms' heads and its colon (any case) are that form's press, filled by ledgerboard's ``fill_form()``;
    an empty fill raises its ``Refused`` (*<head> needs its words*) and never falls back to a reply."""
    if item is None or item.decided is not None or not any(LB.is_form(a) for a in item.answers):
        return None
    pair = (len(item.answers) == 2 and item.answers[0].lower() == "works"
            and LB.is_not_right_form(item.answers[1]))
    if item.kind not in ("decide", "look") and not (item.kind == "watch" and pair):
        return None
    return LB.fill_form(text, item.answers)


def person_text_refused(a) -> bool:
    """TD-268: an ``add`` of a ``decide`` or ``act`` line is held to the person-text rules (``person_text.py``):
    every problem printed, True when one refuses the write (rules 1–3; rule 4 warns)."""
    if a.action != "add" or a.kind not in ("decide", "act"):
        return False
    try:
        detail = json.loads(a.detail) if a.detail else None
    except ValueError:
        detail = None  # the writer refuses a detail that is not JSON, in its own words
    try:
        people = [n for n in LB.board_people(LBB.load_v3(a.board)) or [] if n.strip()]
    except (OSError, ValueError, Refused):
        people = []  # a board the writer refuses says so itself, below
    problems = PT.board_problems(a.kind, a.text or "", a.answer, detail if isinstance(detail, dict) else None, people)
    return PT.report("board_edit", f"the {a.kind} line", problems)


def _parse(argv: list[str]):
    ap = LBB.parser()
    ap.prog = "board_edit.py"
    ap.description = __doc__.split("\n", 1)[0]
    ap.add_argument("--no-commit", action="store_true", help="a write: write the files only")
    ap.set_defaults(tool=TOOL)
    a = ap.parse_args(argv)
    if a.action not in ACTIONS:
        ap.error(f"{a.action}: board_edit.py's commands are {', '.join(ACTIONS)} (`{a.action}` is board.py's: "
                 "run ledgerboard/board.py for it)")
    if a.action == "show" and (a.json or a.plan):
        ap.error("show prints the board as text: it takes no --json or --plan")
    defaults = {**LBB.DEFAULTS, "tool": TOOL}
    given = {k for k, v in vars(a).items()
             if k not in ("action", "plan", "json", "no_commit") and v is not None and v != defaults.get(k)}
    extra = sorted(given - LBB.TAKES[a.action])
    if a.no_commit and a.action not in WRITES:
        extra.append("no_commit")
    if extra:
        ap.error(f"{a.action} does not take {', '.join('--' + e.replace('_', '-') for e in extra)}")
    needs = [o for o in LBB.NEEDS_OPT[a.action] if not (a.action == "reply" and o == "by")]  # by: the People: default
    missing = [o for o in needs if getattr(a, o) in (None, [])]
    if missing:
        ap.error(f"{a.action} needs {', '.join('--' + o for o in missing)}")
    return a


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] in RETIRED:
        print(f"board_edit: {RETIRED[argv[0]]}", file=sys.stderr)
        return 2
    old = sorted({f for f in RETIRED_FLAGS for x in argv if x == f or x.startswith(f + "=")})
    if old:
        print(f"board_edit: {' and '.join(old)} retired with ledgerboard v3.0: name the item by --id, as "
              "`board_edit.py list` or `nudge_user_attention.py --report --json` prints it", file=sys.stderr)
        return 2
    a = _parse(argv)
    a.board = str(Path(a.board).resolve())
    try:
        if a.action == "list":
            got = LBB.items(a.board, a.today)
            if a.json:
                print(json.dumps({"action": "list", "items": got}, ensure_ascii=False, default=str))
            else:
                for r in got:
                    print(f"{r['id'] or '-'}\t{r['due_tag'] or '-'}\t{r['text']}")
            return 0
        if a.action == "show":
            sys.stdout.write(LBB.show(a.board, a.today, a.hidden))
            return 0
        if a.action == "reply":
            board = LBB.load_v3(a.board)
            if not (a.by or "").strip():
                try:
                    a.by = LBB.who_answered(board, None)
                except Refused as e:
                    raise Refused(f"reply needs --by, who says it ({e})") from None
            item = next((it for it in board.items if it.id == a.id), None)
            filled = reply_fills_form(item, a.text)
            if filled is not None:  # a form's press: the decide, never a reply (TD-254)
                a.action, a.answer, a.text = "decide", [filled], None
                print(f"board_edit: the reply fills the form {filled.split(':', 1)[0]}: — decided, not replied",
                      file=sys.stderr)
        if person_text_refused(a):
            raise Refused("text a person reads breaks the rules above, so nothing was written — a decide's opening "
                          "is one plain question, an act opens with its task in bold, an answer says who acts "
                          "(cadence.md §3.3, §3.5)")
        root = _root(Path(a.board)) if a.action in WRITES and not (a.no_commit or a.plan) else None
        plan = LBB.build(a)
        if a.action == "decide" and plan.info.get("entries"):   # the two-file decide lift (TD-218)
            why = agent_sessions.person_session_refusal()
            if why:
                raise Refused(f"the answer lifts {', '.join(plan.info['entries'])}: {why} (a decide records the "
                              "person's words; where they are already on origin's board, `ledger.py set TD-n "
                              "--blocked-by … --by <person> --answer <label>` applies them, TD-260)")
        if root is not None and plan.changes:
            _clean(root, list(plan.changes))
    except Refused as e:
        from ledgerboard import (
            ledger as LBL,  # loaded here, as board.py does: the ledger writer imports it
        )
        code = 2 if isinstance(e, (LBB.BadToday, LBL.Unusable)) else 1
        if a.json or a.plan:
            print(json.dumps({"action": a.action, "refused": str(e)}, ensure_ascii=False))
        print(f"board_edit: refused: {e}", file=sys.stderr)
        return code
    for w in plan.warn:
        print(f"board_edit: {w}", file=sys.stderr)
    if a.plan:
        print(json.dumps(plan.as_json(), ensure_ascii=False))
        return 0
    for n in plan.info.get("item_notes", []):
        print(f"{n['id']}: ℹ {n['note']}", file=sys.stderr)
    if a.action == "fmt":
        try:
            LBB.apply(plan)
        except OSError as e:
            print(f"board_edit: cannot write {a.board}: {e}", file=sys.stderr)
            return 4
        for r in plan.info["refused"]:
            print(f"board_edit: fmt: {r['id']} kept as it is: {r['why']}", file=sys.stderr)
        fixed = plan.info["fixed"]
        print(f"board_edit: fmt rewrote {len(fixed)} item(s){': ' + ', '.join(fixed) if fixed else ''}, "
              f"kept {len(plan.info['refused'])} (not committed: commit it in your PR)")
        return 0
    if not plan.changes:  # nothing to write (a --board-only lift left open)
        if a.json:
            print(json.dumps({"action": plan.action, "subject": None, "paths": [], **plan.info}, ensure_ascii=False))
        return 0
    item_id = plan.info.get("id")
    to = f" to {a.to}" if a.action in ("snooze", "due") else ""
    sha = None
    try:
        if root is None:
            LBB.apply(plan)
        else:
            sha = _commit(root, plan)
            if sha is None:
                return 4
    except OSError as e:
        print(f"board_edit: cannot write: {e}", file=sys.stderr)
        return 4
    if a.json:
        print(json.dumps({"action": plan.action, "subject": plan.subject, "paths": list(plan.changes),
                          "commit": sha, **plan.info}, ensure_ascii=False))
    elif sha is None:
        print(f"board_edit: {plan.action} {item_id}{to} (not committed)")
    else:
        print(f"board_edit: {plan.action} {item_id}{to} — committed {sha}: {plan.subject} (not pushed; "
              "cadence.md §4.5: land it by its own PR, or push with ALLOW_MAIN_PUSH=1)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
