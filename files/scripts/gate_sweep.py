#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/gate_sweep.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""The gate sweep, as a plan: what nothing-waits-silently would file, close and lift in this repo now
(TD-219; ledgerboard's target design §3.2, §1.2).

    gate_sweep.py [--json] [--timeout S] [--reask-days N] [--event-age-days N]

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
- **What it prints.** The plan: each item to file (on which board, its kind, text and ``Context:``), each
  item to close (by board and key), and each host lift (``until`` reached, an event passed, with its
  evidence). ``--json``: ``{repo, source, boards: [{board, source}], unread, checks, to_file, to_close, lifts}``.
  A board that is there and cannot be read (a git call failed or timed out) is left out and named under
  ``unread``, never read as absent; this repo's own ledger or board unreadable is no plan at all.

**It writes nothing.** Filing the items, closing them and opening the lift PRs (``lift/TD-n/<gate>``,
idempotent, §4.4), and when the sweep runs, are TD-219's next slice. The re-ask window and the event age
are the consumer's numbers (``--reask-days``, ``--event-age-days``; default 30 each, §3.2). Today is the
UTC date for the ledger and this machine's local date for the boards (§3.1).

Exit 0 when the plan was made (whatever it holds), 2 when it could not be (no ledger, no own board, a
format ``sweep()`` refuses). Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import event_checks as E  # noqa: E402  # sibling SYNC script: the event runner
import ledger as L  # noqa: E402  # sibling SYNC script: the ledger's readers and the roster
import ledgerboard as LB  # noqa: E402  # sibling SYNC file: the formats and sweep(), defined once
import nudge_user_attention as N  # noqa: E402  # sibling SYNC script: the roster and default-branch readers


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
    results = {(c["id"], c["name"]): (c["outcome"], c["evidence"]) for c in checks}
    out = LB.sweep([text, arch], boards, results, today_utc, today_local, reask_days=reask_days,
                   event_age_days=event_age_days, repo=repo)
    return {"repo": repo, "source": source, "boards": read_from, "unread": unread,
            "checks": [{k: c[k] for k in ("id", "name", "outcome", "evidence", "why")} for c in checks], **out}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--timeout", type=float, default=E.TIMEOUT, help="seconds per forge call of an event check")
    ap.add_argument("--reask-days", type=int, default=LB.SWEEP_REASK_DAYS)
    ap.add_argument("--event-age-days", type=int, default=LB.SWEEP_EVENT_AGE_DAYS)
    a = ap.parse_args(argv)
    top = L._toplevel()
    try:
        p = plan(top, N.read_registry() or [], E.Runner(top, timeout=a.timeout),
                 today_utc=datetime.now(timezone.utc).date(), today_local=date.today(),  # noqa: DTZ011  # a board's date is the person's own
                 reask_days=a.reask_days, event_age_days=a.event_age_days)
    except LB.Refused as e:
        print(f"gate_sweep: no plan — {e}", file=sys.stderr)
        return 2
    if a.json:
        print(json.dumps(p, indent=2, ensure_ascii=False, default=str))
        return 0
    print(f"gate sweep of {p['repo']} ({p['source']}; {len(p['boards'])} board(s) read) — a plan: nothing written")
    for b in p["boards"]:
        print(f"  board {b['board']} ({b['source']})")
    for u in p["unread"]:
        print(f"  ⚠ board not read: {u} — an item there is not seen, so the plan may file it again")
    for c in p["checks"]:
        print(f"  check {c['id']} event ({c['name']}): {c['outcome']} — {c['evidence'] or c['why']}")
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
