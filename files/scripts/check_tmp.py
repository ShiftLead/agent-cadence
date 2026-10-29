#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/check_tmp.py
# Edit it there: a repo runs it from its pinned dev-cadence (`dev-cadence path`), and a fix reaches it by a bump PR.
"""Is the shared temp filesystem about to run out? (TD-154, cadence.md §3.9)

    check_tmp.py --hook      SessionStart (cadence_hooks.sh): one line, only when the temp
                             filesystem is WARN_PERCENT or more used — of its inodes or its space
    check_tmp.py --report    /attention: the same line always, and past WARN_PERCENT the largest
                             top-level directories by inode count, with the cleanups for the
                             person to run

Every session on a machine shares one temp directory: Claude Code writes each command's output
file and each session's scratchpad there, and test runners their run directories. On 2026-10-26
one machine's /tmp (a tmpfs) ran out of inodes with 7.8 GB of space free: `df -h` looked healthy,
every session could no longer start a command, and the cause was found by hand. The fill took
weeks, so a line at session start names it days early. Inodes and space are both read, because
either one running out stops every session.

The directory is the one Claude Code uses: $CLAUDE_CODE_TMPDIR, else $TMPDIR, else /tmp. Past
CRITICAL_PERCENT the line says sessions are about to fail. --report's walk counts entries under
each top-level directory, one pass, stopped at WALK_BUDGET seconds (a count cut short says so).

Nothing is ever removed: the directory is shared and its files are other sessions'. The
cleanups are printed as commands for the person. Always exits 0 — a detector, never a gate
(cadence §7). Stdlib only.
"""

from __future__ import annotations

import argparse
import math
import os
import shlex
import sys
import time

WARN_PERCENT = 80
CRITICAL_PERCENT = 95
WALK_BUDGET = 10.0   # seconds for --report's walk
TOP = 5              # directories --report names


def tmp_dir() -> str:
    for var in ("CLAUDE_CODE_TMPDIR", "TMPDIR"):
        v = os.environ.get(var, "").strip()
        if v:
            return v
    return "/tmp"


def usage(path: str) -> dict | None:
    """Inode and space use of the filesystem holding ``path`` (df's arithmetic, rounded up as df
    rounds), or None when
    it cannot be read. A filesystem that reports no inode count (f_files 0) has no inode limit."""
    try:
        st = os.statvfs(path)
    except OSError:
        return None
    used_b = st.f_blocks - st.f_bfree
    space = math.ceil(100 * used_b / (used_b + st.f_bavail)) if used_b + st.f_bavail else 0
    used_i = st.f_files - st.f_ffree
    inodes = math.ceil(100 * used_i / st.f_files) if st.f_files else 0
    return {"inodes": inodes, "used_i": used_i, "files": st.f_files,
            "space": space, "used_b": used_b * st.f_frsize, "size_b": (used_b + st.f_bavail) * st.f_frsize}


def _gb(n: float) -> str:
    return f"{n / 1e9:.1f} GB"


def line(path: str, u: dict) -> str:
    worst = max(u["inodes"], u["space"])
    figures = (f"{u['inodes']:.0f}% of its inodes ({u['used_i']:,} of {u['files']:,}) and "
               f"{u['space']:.0f}% of its space ({_gb(u['used_b'])} of {_gb(u['size_b'])})"
               if u["files"] else f"{u['space']:.0f}% of its space ({_gb(u['used_b'])} of {_gb(u['size_b'])}); no inode limit")
    if worst >= CRITICAL_PERCENT:
        return (f"✖ {path} is past {CRITICAL_PERCENT}% — {figures}: sessions on this machine are about to fail "
                "(a command's output file cannot be created). Tell the person now; `/attention` names what fills it (TD-154)")
    if worst >= WARN_PERCENT:
        return (f"⚠ {path} is past {WARN_PERCENT}% — {figures}. Every session on this machine shares it; "
                "tell the person — `/attention` names what fills it (TD-154)")
    return f"{path}: {figures} — fine (warns at {WARN_PERCENT}%)"


def largest(path: str, budget: float | None = None) -> tuple[list[tuple[int, str]], bool]:
    """(entries, top-level name) for each top-level directory, most first, and whether the walk
    finished inside the budget. Symlinks are not followed; unreadable directories count as read."""
    deadline = time.monotonic() + (WALK_BUDGET if budget is None else budget)
    counts: list[tuple[int, str]] = []
    done = True
    try:
        tops = list(os.scandir(path))
    except OSError:
        return [], True
    for top in tops:
        if not top.is_dir(follow_symlinks=False):
            continue
        n, stack = 1, [top.path]
        while stack:
            if time.monotonic() > deadline:
                done = False
                break
            d = stack.pop()
            try:
                with os.scandir(d) as it:
                    for e in it:
                        n += 1
                        if e.is_dir(follow_symlinks=False):
                            stack.append(e.path)
            except OSError:
                pass
        counts.append((n, top.name))
        if not done:
            break
    counts.sort(reverse=True)
    return counts, done


def cleanups(path: str) -> list[str]:
    user = os.environ.get("USER") or os.environ.get("LOGNAME") or "$USER"
    q = shlex.quote
    return [
        f"pytest's run directories, when no test run is going:  rm -rf {q(f'{path}/pytest-of-{user}')}",
        # -mindepth 1: never the temp directory itself, whose own name may match tmp*
        f"your leaked tempfile directories, unchanged (by directory mtime) for a day or more:  "
        f"find {q(path)} -mindepth 1 -maxdepth 1 -type d -user {q(user)} -name 'tmp*' -mmin +1440 -exec rm -rf {{}} +",
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Warn before the shared temp filesystem runs out (TD-154).")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--hook", action="store_true", help="SessionStart: a line only past the threshold")
    mode.add_argument("--report", action="store_true", help="/attention: the line, and the largest directories")
    a = ap.parse_args(argv)
    path = tmp_dir()
    u = usage(path)
    if u is None:
        if a.report:
            print(f"{path}: cannot read its filesystem's use — not checked")
        return 0
    over = max(u["inodes"], u["space"]) >= WARN_PERCENT
    if a.hook:
        if over:
            print(line(path, u))
        return 0
    print(line(path, u))
    if over:
        counts, done = largest(path)
        if counts:
            print(f"  the largest directories in {path}, by entries" + ("" if done else f" (the walk stopped at {WALK_BUDGET:.0f}s: counts are at least these, and later directories were not read)") + ":")
            for n, name in counts[:TOP]:
                print(f"    {n:>10,}  {path}/{name}")
        print("  cleanups for the person to run (never run by a session — the files may be other sessions'):")
        for c in cleanups(path):
            print(f"    {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
