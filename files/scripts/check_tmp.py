#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/check_tmp.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
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

Past WARN_PERCENT both modes reap the running user's own known leftovers (TD-223): an entry directly
under the temp directory (never the directory itself) owned by this user, unchanged for REAP_AGE
seconds (a day) — nothing in its tree newer, since a live tree is written at depth — and named as
tempfile and mktemp name directories (``tmp`` + 8, ``tmp.`` + 10) or ``precheck-*`` (precheck.py's clean
worktrees), and ``pytest-*`` under the user's own ``pytest-of-<user>/``, read-only directories made
writable first, within REAP_BUDGET seconds (the rest next time). Nothing is reaped when the directory
is ``/``, or the home directory or above it.
It says what it removed and the entries it freed. Nothing else is removed: the directory is shared,
and every other file may be another session's, so the rest stays a printed cleanup for the person.
Always exits 0 — a detector, never a gate (cadence §7). Stdlib only.
"""

from __future__ import annotations

import argparse
import fnmatch
import math
import os
import re
import shlex
import shutil
import stat
import sys
import time

WARN_PERCENT = 80
CRITICAL_PERCENT = 95
WALK_BUDGET = 10.0   # seconds for --report's walk
TOP = 5              # directories --report names
REAP_AGE = 86400     # seconds an entry is left unchanged before it is reaped (TD-223)
REAP_PATTERNS = ("tmp*", "precheck-*")   # top-level names reaped; and pytest-* under pytest-of-<user>/
# tmp* is only the names tempfile (tmp + 8 of [a-z0-9_]) and mktemp (tmp. + 10 alphanumerics) make
TMP_NAME_RE = re.compile(r"tmp(?:[a-z0-9_]{8}|\.[A-Za-z0-9]{10})")
REAP_BUDGET = 2.0    # seconds of reaping a run spends (the hook runs under a bound); the rest is next time


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


def force_rmtree(path: str) -> bool:
    """Remove ``path`` whole, a read-only directory under it made writable first (a module cache, a
    chmod'd fixture — what ``shutil.rmtree(ignore_errors=True)`` gives up on, TD-223). True when it
    is gone. A symlink is removed, never followed."""
    if os.path.islink(path) or not os.path.isdir(path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        except OSError:
            return False
        return True
    for d, dirs, _ in os.walk(path):
        for name in [d, *(os.path.join(d, x) for x in dirs)]:
            try:
                st = os.lstat(name)
                if stat.S_ISDIR(st.st_mode) and (st.st_mode & 0o700) != 0o700:
                    os.chmod(name, st.st_mode | 0o700)
            except OSError:
                pass
    shutil.rmtree(path, ignore_errors=True)
    return not os.path.lexists(path)


def _entries(path: str) -> int:
    n, stack = 1, [path]
    while stack:
        try:
            with os.scandir(stack.pop()) as it:
                for e in it:
                    n += 1
                    if e.is_dir(follow_symlinks=False):
                        stack.append(e.path)
        except OSError:
            pass
    return n


def _named(name: str, pats: tuple[str, ...]) -> bool:
    return any(TMP_NAME_RE.fullmatch(name) if p == "tmp*" else fnmatch.fnmatchcase(name, p) for p in pats)


def _idle(path: str, cutoff: float, deadline: float) -> bool:
    """Is nothing in the tree at ``path`` (itself included, symlinks not followed) newer than ``cutoff``?
    A live tree is written at depth, where its top's mtime does not move, so every entry is read; a walk
    that cannot finish by ``deadline`` answers no, so a tree too big to judge is kept."""
    stack = [path]
    while stack:
        if time.monotonic() > deadline:
            return False
        d = stack.pop()
        try:
            if os.lstat(d).st_mtime > cutoff:
                return False
            with os.scandir(d) as it:
                for e in it:
                    if e.stat(follow_symlinks=False).st_mtime > cutoff:
                        return False
                    if e.is_dir(follow_symlinks=False):
                        stack.append(e.path)
        except OSError:
            pass
    return True


def _safe_root(path: str) -> bool:
    """Not ``/``, and not the home directory or one above it: a TMPDIR pointed there is no temp dir."""
    real = os.path.realpath(path)
    home = os.path.realpath(os.path.expanduser("~"))
    return real != "/" and not (home + "/").startswith(real.rstrip("/") + "/")


def reapable(path: str, patterns: tuple[str, ...] = REAP_PATTERNS, now: float | None = None,
             budget: float = REAP_BUDGET) -> list[str]:
    """The user's own known leftovers in the temp directory ``path`` (TD-223): entries directly under it
    named by ``patterns`` (``tmp*`` only as tempfile and mktemp name them), and ``pytest-*`` under this
    user's own ``pytest-of-<user>/``, owned by this user, nothing in them changed for REAP_AGE seconds.
    Never ``path`` itself, never another user's, never a symlink, and nothing when ``path`` is ``/`` or the
    home directory or above it."""
    now = time.time() if now is None else now
    deadline = time.monotonic() + budget
    uid, user = os.getuid(), os.environ.get("USER") or os.environ.get("LOGNAME") or ""
    found: list[str] = []
    if not _safe_root(path):
        return found

    def scan(d: str, pats: tuple[str, ...]) -> None:
        try:
            with os.scandir(d) as it:
                for e in it:
                    if not _named(e.name, pats) or e.is_symlink():
                        continue
                    if e.stat(follow_symlinks=False).st_uid == uid and _idle(e.path, now - REAP_AGE, deadline):
                        found.append(e.path)
        except OSError:
            pass
    scan(path, patterns)
    mine = os.path.join(path, f"pytest-of-{user}")
    try:
        st = os.lstat(mine) if user else None
    except OSError:
        st = None
    if st is not None and stat.S_ISDIR(st.st_mode) and st.st_uid == uid:   # a symlink or another's: not read
        scan(mine, ("pytest-*",))
    return sorted(found)


def reap(path: str, patterns: tuple[str, ...] = REAP_PATTERNS) -> tuple[list[str], int, list[str]]:
    """Remove ``reapable(path)`` within REAP_BUDGET seconds: (removed, entries freed, not removed —
    each one that failed, then any left when the budget ran out)."""
    removed, freed, failed = [], 0, []
    deadline = time.monotonic() + REAP_BUDGET
    todo = reapable(path, patterns)
    for i, e in enumerate(todo):
        if time.monotonic() > deadline:
            failed += [f"{x} (left for next time)" for x in todo[i:]]
            break
        n = _entries(e) if os.path.isdir(e) else 1
        if force_rmtree(e):
            removed.append(e)
            freed += n
        else:
            failed.append(e)
    return removed, freed, failed


def reaped_line(removed: list[str], freed: int, failed: list[str]) -> str | None:
    if not removed and not failed:
        return None
    out = (f"  reaped {len(removed)} of your own leftovers older than a day ({freed:,} entries): "
           + ", ".join(os.path.basename(r) for r in removed[:5]) + (" …" if len(removed) > 5 else "")) if removed else "  reaped nothing"
    return out + (f"; could not remove {', '.join(failed[:3])}" if failed else "") + " (TD-223)"


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
    if a.hook and not over:
        return 0
    print(line(path, u), flush=True)   # before the reap, so a hook cut short by its bound still said it
    said = reaped_line(*reap(path)) if over else None
    if said:
        print(said)
    if a.hook:
        return 0
    if over:
        counts, done = largest(path)
        if counts:
            print(f"  the largest directories in {path}, by entries" + ("" if done else f" (the walk stopped at {WALK_BUDGET:.0f}s: counts are at least these, and later directories were not read)") + ":")
            for n, name in counts[:TOP]:
                print(f"    {n:>10,}  {path}/{name}")
        print("  cleanups for the person to run (never run by a session — the files may be other sessions'; "
              "the user's own aged tmp*, precheck-* and pytest-* are reaped above):")
        for c in cleanups(path):
            print(f"    {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
