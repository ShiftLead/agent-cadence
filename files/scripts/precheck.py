#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/precheck.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""precheck: run the repo's own checks on a PR's head, in a clean worktree, and record the
verdict on the PR (TD-117, cadence.md §4.12).

    precheck.py --pr N          run the repo's `precheck` command (docs/cadence.toml) on PR N's
                                head commit, then record a `cadence/precheck` commit status on it
    precheck.py --commit SHA    the same on a commit of origin's default branch (TD-151): its
                                head, for an orchestrator that promotes only a green main
    precheck.py --pr N --expect SHA
                                the same, refusing (exit 2) unless the PR's head is SHA (a
                                full sha or a prefix) — the commit just pushed (TD-186)
    precheck.py ... --no-record run it and record nothing (a trial)
    precheck.py --pr N --fork-ok
                                run it on a fork's PR, which is otherwise refused (TD-207) —
                                the person's flag, after reading the diff, never a session's

The merge gate runs it: the session that runs the cadence check (docs/procedures/cadence.md)
runs this first when `precheck` is set, and check_cadence.py's ci row reads the status. A
`--no-verify` push or a cloud session's push skips a hook; it cannot skip the gate.

The command is the repo's, read from the checkout this runs in (its docs/cadence.toml, never
the PR's — a PR cannot change the check it is judged by before it merges). It runs with bash
from the root of a detached worktree at the head commit, fetched from origin as the forge
serves it — with --commit, origin's default branch is fetched and the
commit must be on it (an ancestor of its tip, or the tip), stdin closed, its output streamed; that worktree is
removed afterwards, also when the precheck is stopped by SIGTERM or SIGHUP (`timeout`, a stopped background
task; one the caller ignores, as under `nohup`, stays ignored), which then kills the command's process group,
exits 128 + the signal and records nothing (TD-210). A fresh worktree has no installed dependencies, so the command sets up
what it needs (`pdm install && pdm run test`).

The head is the forge's, and the forge sees a push seconds after it (TD-186): a precheck started
in the same breath would test the previous head and pass it. So --pr re-reads the PR for up to
30s (PRECHECK_HEAD_WAIT, 0–600) while the head is not --expect's commit, or — without --expect —
while origin's branch (`git ls-remote`) is at another commit, or this checkout, on that branch,
holds a commit the head lacks; then it refuses, naming both shas. A fork's PR is not compared. The PASS/FAIL line and the recorded line name the full sha tested.

A fork's PR is refused (TD-207): its head is a stranger's code, and the command would run it here
with the person's credentials in reach — the clean worktree is no sandbox. So --pr reads whether
the head is a fork's (the forge's `cross_repo`) and, when it is or the forge does not say, exits 2
before fetching it. --fork-ok runs it anyway, and the recorded status's description says so.

A PR may get a narrower command (TD-155): `[precheck-paths]` in docs/cadence.toml maps globs to a
command, and when every file the PR changes (a three-dot diff against its base branch, fetched
from origin) matches one entry's globs, that entry's command runs instead of `precheck` — the
first such entry, in the file's order. A file no entry covers, a diff that cannot be read, or
--commit runs the full `precheck`. The status's description names the command that ran.

The status is a commit status, not a CI run: it uses no Actions minutes, and it stays on the
commit after the session ends. Its description names the command's exit code, the time it
took and the host it ran on.

Exit: 0 the command passed and the status is recorded (or --no-record); 1 it failed (a failure
status is recorded); 2 nothing ran — no `precheck` set, the PR is not open, its head cannot
be fetched, its head is a fork's without --fork-ok (TD-207), its head is not the pushed commit (TD-186), a --commit that is not on origin's default branch, or a usage error; 3 it passed but the status could not be recorded (the ci row
will not see it). Stdlib only.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cadence_config as C  # noqa: E402
import forge as F  # noqa: E402


def _stopped(signum: int, _frame: object) -> None:
    # TD-210: Python's default SIGTERM/SIGHUP ends the process at once, skipping every `finally`, so the
    # clean worktree was left registered in the clone; raised as an exit, the `finally` removes it
    print(f"precheck: stopped by signal {signum} — removing the clean worktree", file=sys.stderr, flush=True)
    raise SystemExit(128 + signum)


HEAD_WAIT = 30.0   # TD-186: seconds to wait for the forge to see a push (PRECHECK_HEAD_WAIT)
CONTEXT = "cadence/precheck"   # parity (cadence.md §7.9): check_cadence.py's row_ci reads this name


def git(*args: str, cwd: str | Path, timeout: float = 300) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                          timeout=timeout, check=False)


def on_default(root: str, commit: str) -> str | None:
    """TD-151: the full sha of ``commit`` once origin's default branch is fetched and the commit is
    on it (its tip or an ancestor), else None, having said why. A commit not on the default branch
    is a PR's to check, by --pr."""
    import nudge_user_attention as N  # sibling SYNC script: the default-branch rule (§9)
    base = N.default_branch(Path(root))
    ref = f"refs/remotes/origin/{base}"
    try:
        f = git("fetch", "-q", "--no-tags", "origin", f"+refs/heads/{base}:{ref}", cwd=root)
        why = (f.stderr.strip().splitlines() or ["not served"])[-1]
    except subprocess.TimeoutExpired:
        f, why = None, "git fetch timed out"
    if f is None or f.returncode != 0:
        print(f"precheck: cannot fetch origin/{base} ({why})", file=sys.stderr)
        return None
    r = git("rev-parse", "--verify", "-q", f"{commit}^{{commit}}", cwd=root)
    sha = r.stdout.strip()
    if r.returncode != 0 or not sha:
        print(f"precheck: no commit {commit!r} here, after fetching origin/{base}", file=sys.stderr)
        return None
    if git("merge-base", "--is-ancestor", sha, ref, cwd=root).returncode != 0:
        print(f"precheck: {sha[:7]} is not on origin/{base} — --commit checks the default branch; "
              "a PR's head is checked by --pr", file=sys.stderr)
        return None
    return sha


def changed_files(root: str, base: str | None, sha: str) -> list[str] | None:
    """TD-155: the paths the PR changes — ``origin/<base>...<sha>``, renames as their two paths —
    after fetching the base branch; None when that cannot be read."""
    if not base:
        return None
    ref = f"refs/remotes/origin/{base}"
    try:
        if git("fetch", "-q", "--no-tags", "origin", f"+refs/heads/{base}:{ref}", cwd=root).returncode != 0:
            return None
        d = git("diff", "--name-only", "--no-renames", "-z", f"{ref}...{sha}", cwd=root)
    except subprocess.TimeoutExpired:
        return None
    return [p for p in d.stdout.split("\0") if p] if d.returncode == 0 else None


def narrow(entries: list[tuple[list[str], str]], paths: list[str] | None) -> tuple[list[str], str] | None:
    """The first [precheck-paths] entry whose globs cover every path; None when none does, or
    there is nothing to cover (an empty or unreadable diff takes the full command)."""
    if not paths:
        return None
    for globs, cmd in entries:
        if all(any(fnmatch.fnmatchcase(p, g) for g in globs) for p in paths):
            return globs, cmd
    return None


def read_head(fg, n: int, root: str, fork_ok: bool = False) -> tuple[dict, str] | int:
    """(the PR, its head sha) once that head is fetched from origin, else the exit code, having
    said why. A fork's head, or one the forge does not say is not a fork's, is refused before it
    is fetched unless `fork_ok` (TD-207)."""
    try:
        pr = fg.pr(n)
    except F.ForgeUnreadable as e:
        print(f"precheck: cannot read PR {n}: {e}", file=sys.stderr)
        return 2
    sha = pr.get("head_sha")
    if pr.get("state") != "open" or not sha:
        print(f"precheck: PR {n} is {pr.get('state') or 'unreadable'} — only an open PR's head is checked",
              file=sys.stderr)
        return 2
    if pr.get("cross_repo") is not False and not fork_ok:
        what = ("is a fork's" if pr.get("cross_repo") else
                "may be a fork's (the forge did not say whether it is)")
        print(f"precheck: PR {n}'s head {sha[:7]} {what} — its commands would run on this machine "
              "with your credentials, and nothing ran. Read its diff and see the forge's CI green on "
              "it first; then the person runs it with --fork-ok (cadence.md §4.12, TD-207)",
              file=sys.stderr)
        return 2
    try:
        f = git("fetch", "-q", "origin", fg.head_ref(n), cwd=root)
        have = f.returncode == 0 and git("cat-file", "-e", f"{sha}^{{commit}}", cwd=root).returncode == 0
        why = (f.stderr.strip().splitlines() or ["not served"])[-1]
    except subprocess.TimeoutExpired:
        have, why = False, "git fetch timed out"
    if not have:
        print(f"precheck: cannot fetch PR {n}'s head {sha[:7]} from origin ({why})", file=sys.stderr)
        return 2
    return pr, sha


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Run the repo's precheck on a PR's head (TD-117), "
                                             "or on a commit of the default branch (TD-151).")
    which = ap.add_mutually_exclusive_group(required=True)
    which.add_argument("--pr", type=int)
    which.add_argument("--commit", metavar="SHA", help="a commit of origin's default branch")
    ap.add_argument("--no-record", action="store_true", help="run it, record no status")
    ap.add_argument("--expect", metavar="SHA", help="with --pr: the head you just pushed; refuse any other")
    ap.add_argument("--fork-ok", action="store_true",
                    help="with --pr: run a fork's PR (refused without it) — the person's, after reading the diff")
    a = ap.parse_args(argv)
    if a.expect is not None and a.pr is None:
        ap.error("--expect goes with --pr")
    if a.fork_ok and a.pr is None:
        ap.error("--fork-ok goes with --pr")

    root = C.repo_root(".")
    if not root:
        print("precheck: not in a git repository", file=sys.stderr)
        return 2
    try:
        files = C.sources(root)
        cmd, _ = C.resolve("precheck", files)
        entries = C.precheck_paths(files)
    except C.ConfigError as e:
        print(f"precheck: {e}", file=sys.stderr)
        return 2
    if not cmd:
        print("precheck: no `precheck` in docs/cadence.toml — nothing to run (cadence.md §4.12)")
        return 2
    cmd = str(cmd)   # resolve() typed it object; a repo key is a checked non-empty string

    fork = False
    if a.commit is not None:
        sha = on_default(root, a.commit)
        if sha is None:
            return 2
        fg = None   # asked only to record: a --no-record trial needs no forge
        if not a.no_record:
            try:
                fg = F.backend(root)
            except F.ForgeUnreadable as e:
                print(f"precheck: cannot read the forge: {e}", file=sys.stderr)
                return 2
        what = "commit"
    else:
        try:
            fg = F.backend(root)
        except F.ForgeUnreadable as e:
            print(f"precheck: cannot read PR {a.pr}: {e}", file=sys.stderr)
            return 2
        expect = None
        if a.expect is not None:
            if a.expect.startswith("-"):
                print(f"precheck: --expect {a.expect!r} is no sha", file=sys.stderr)
                return 2
            r = git("rev-parse", "--verify", "-q", f"{a.expect}^{{commit}}", cwd=root)
            expect = r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else a.expect.lower()
            if not re.fullmatch(r"[0-9a-f]{7,64}", expect):
                print(f"precheck: --expect {a.expect!r} is no commit here and no sha", file=sys.stderr)
                return 2
        # TD-186: the forge's head lags a push by seconds, and a precheck started in the same breath
        # would test and pass the previous head. Re-read until the head is the commit we expect.
        try:
            wait = float(os.environ.get("PRECHECK_HEAD_WAIT", HEAD_WAIT))
        except ValueError:
            wait = float("nan")
        if not 0 <= wait <= 600:   # nan and inf fail it too
            print(f"precheck: PRECHECK_HEAD_WAIT={os.environ.get('PRECHECK_HEAD_WAIT')!r} is no "
                  "number of seconds from 0 to 600", file=sys.stderr)
            return 2
        end = time.monotonic() + wait
        while True:
            got = read_head(fg, a.pr, root, a.fork_ok)
            if isinstance(got, int):
                return got
            pr, sha = got
            if expect is not None:
                lag = None if sha.startswith(expect) else ("--expect", expect)
            else:
                lag = F.head_lag(root, pr)
            if lag is None:
                break
            if time.monotonic() >= end:
                print(f"precheck: PR {a.pr}'s head on the forge is {sha}, but {lag[0]} is {lag[1]} — "
                      f"the PR has not caught up with that commit after {wait:.0f}s (a push it has not "
                      "seen, one never made, or a later push); nothing ran. Run it again once they agree",
                      file=sys.stderr)
                return 2
            time.sleep(max(0.05, min(3.0, wait / 10)))
        what = f"PR {a.pr}"
        fork = pr.get("cross_repo") is not False   # only --fork-ok gets here with one
        if fork:
            what += " (a fork's head, run under --fork-ok)"
        if entries:
            paths = changed_files(root, pr.get("base"), sha)
            hit = narrow(entries, paths)
            if hit:
                cmd = hit[1]
                print(f"precheck: every file PR {a.pr} changes ({len(paths)}) matches "
                      f"[precheck-paths] \"{' '.join(hit[0])}\" — its command runs, not `precheck`")
            elif paths is None:
                print(f"precheck: cannot read PR {a.pr}'s changed files — the full `precheck` runs")

    # TD-210: a stop becomes an exit, so the `finally` below removes the worktree; a signal the caller
    # already ignores (`nohup`) stays ignored, and each is restored as it was once the worktree is gone
    saved = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGHUP)}
    for sig, was in saved.items():
        if was is not signal.SIG_IGN:
            signal.signal(sig, _stopped)
    tmp = tempfile.mkdtemp(prefix=f"precheck-{a.pr if a.commit is None else sha[:7]}-")
    wt = Path(tmp) / "head"
    try:
        w = git("worktree", "add", "-q", "--detach", str(wt), sha, cwd=root)
        if w.returncode != 0:
            print(f"precheck: cannot make a worktree at {sha[:7]}: {w.stderr.strip()}", file=sys.stderr)
            return 2
        print(f"precheck: {what} at {sha[:7]}: {cmd}", flush=True)
        t0 = time.monotonic()
        # the launcher's CADENCE_REPO_ROOT names the checkout this ran from, not the clean worktree: a
        # suite that inherits it reads the live checkout in place of its fixtures (agent-cadence's own did)
        env = {k: v for k, v in os.environ.items() if k != "CADENCE_REPO_ROOT"}
        # its own session, so a stop takes the command's whole process group with it, never leaving a
        # grandchild (the suite, a `sleep`) running in a worktree that is about to be removed
        p = subprocess.Popen(["bash", "-c", cmd], cwd=wt, env=env, stdin=subprocess.DEVNULL, start_new_session=True)
        try:
            rc = p.wait()
        except BaseException:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.wait()
            raise
        took = time.monotonic() - t0
    finally:
        for sig in saved:   # a second signal must not cut the cleanup short
            signal.signal(sig, signal.SIG_IGN)
        if wt.exists():
            git("worktree", "remove", "--force", str(wt), cwd=root)
        else:   # stopped inside `git worktree add`: drop the half-registered entry
            git("worktree", "prune", cwd=root)
        shutil.rmtree(tmp, ignore_errors=True)
        for sig, was in saved.items():
            signal.signal(sig, was)

    ok = rc == 0
    verdict = "passed" if ok else f"failed (exit {rc})"
    print(f"precheck: {verdict} in {took:.0f}s, on {sha}")
    if a.no_record:
        return 0 if ok else 1
    desc = f"{'passed' if ok else f'exit {rc}'} in {took:.0f}s on {socket.gethostname()}: {cmd}"
    if fork:
        desc = f"--fork-ok, a fork's head: {desc}"
    try:
        fg.set_status(sha, ok, CONTEXT, desc)
    except F.ForgeUnreadable as e:
        print(f"precheck: {verdict}, but the {CONTEXT} status could not be recorded on {sha[:7]}: {e}",
              file=sys.stderr)
        return 3 if ok else 1
    print(f"precheck: recorded {CONTEXT} = {'success' if ok else 'failure'} on {sha}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
