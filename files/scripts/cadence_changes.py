#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/cadence_changes.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""Tell a session which cadence conventions changed since this worktree last heard.

    cadence_changes.py --hook          SessionStart: print unseen entries once per worktree, then remember them
    cadence_changes.py --list [--since 30d]   plain listing of origin's entries (no marker written)
    cadence_changes.py --json          origin's entries as JSON: heading, date, body, landed (commit time on origin)

Source of truth is ``docs/cadence-changes.md`` on ``origin/<default>`` — read with
``git show``. The attention hook that runs just before this one fetches this repo
FIRST under its budget (TD-044), so ``--hook`` normally reads a fresh ref and does not
fetch. It fetches only when that did not happen — this repo is not on the machine
roster, or the budget ran out — judged by ``FETCH_HEAD`` older than FETCH_FRESH_S:
then one bounded fetch of the default branch (FETCH_TIMEOUT s, SIGTERM before SIGKILL
so no .lock survives, never --prune). Offline, the ref is whatever the last fetch
left, and that is fine — a convention change is not urgent by the minute.

Why origin and not the worktree's file: a worktree created before a sync PR merged has
old docs, and its sessions would otherwise never hear about the change until they
rebase. Why a per-worktree marker (``<git-dir>/cadence-changes-seen``, one heading per
line, untracked, gone with the worktree) and not a time window: an entry printed at
every session start for two weeks is an entry that gets skimmed past.

In a pinned repo (cadence.md §9.19, TD-250) — this script run from the launcher's tree, outside
the repo, and ``docs/cadence.toml`` on ``origin/<default>`` holding a valid ``[agent-cadence]``
pin — the repo has no changes file: the entries are the source's
``files/docs/cadence-changes.md`` at origin's pin, read from the launcher's cache (the tree on
disk, else its bare clone of the source), never the repo. ``--json``/``--list`` fetch or clone
once when the cache lacks that commit (the cache's lock taken without blocking, LOCK_DEADLINE),
and exit 2 when that fails; ``landed`` is the time of the commit on origin whose pin last
brought the heading in. ``--hook`` fetches no source and takes no lock: the worktree's own file
is its own pin's (or, branched before the migration, its retired copy); an entry is unseen as
below, or when absent from the pin before the oldest bump within RECENT_DAYS, so a bump's
entries reach a session started after it; and a *behind* line compares the worktree's pin with
origin's, once per worktree per origin pin. A worktree whose own file cannot be read hears only
what is recent. No pin on origin (this repo, a synced copy) reads as below.

What counts as unseen in ``--hook``: a heading in origin's copy that is not in this
worktree's copy of the file (missing file → all of them), or dated within the last
14 days (a fresh, up-to-date worktree still hears about this week's change) — minus
the headings in the marker. Entries are append-only (an amendment is a new dated
entry), which is what makes a heading diff sufficient.

Silent when nothing. Exit 0 on every path; never a traceback into a session's context.
Stdlib only. In --hook: local git plumbing calls, each bounded to 5 s against a hang (not to
fit a sum: with every one at its bound the total passes 25 s), and at most one network
fetch (above). The runner's 25 s child bound (cadence_hooks.sh) is the real ceiling — it
stops the child, and a detector stopped early says nothing rather than something wrong.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import time

CHANGES = "docs/cadence-changes.md"
MARKER = "cadence-changes-seen"
RECENT_DAYS = 14
HEADING_RE = re.compile(r"^## (\d{4}-\d{2}-\d{2}) — (.+?)\s*$")


def git(args, cwd=None, timeout=5):
    try:
        p = subprocess.run(
            ["git", *args],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return p.stdout if p.returncode == 0 else None


def parse(text):
    """[{heading, date, title, body}] in file order (newest first by convention)."""
    entries, cur = [], None
    for line in (text or "").splitlines():
        m = HEADING_RE.match(line)
        if m:
            cur = {
                "heading": line.strip(),
                "date": m.group(1),
                "title": m.group(2),
                "body": [],
            }
            entries.append(cur)
        elif cur is not None and line.strip():
            cur["body"].append(line.rstrip())
    for e in entries:
        e["body"] = "\n".join(e["body"])
    return entries


def default_branch(root):
    """The repo's default branch NAME — cadence.md §9 "Default-branch rule": the first of
    origin/HEAD's target, init.defaultBranch, main, master that exists on origin (an
    unset or dangling origin/HEAD falls through); else main. Parity: the shell default_branch() copies and the other Python scripts
    follow the same rule; tests/test_default_branch.sh runs every copy."""
    head = git(["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"], cwd=root)
    cfg = git(["config", "init.defaultBranch"], cwd=root)
    for b in ((head or "").strip().removeprefix("origin/"), (cfg or "").strip(), "main", "master"):
        if b and git(["rev-parse", "--verify", "-q", f"refs/remotes/origin/{b}"], cwd=root) is not None:
            return b
    return "main"


def origin_default(root):
    """default_branch(), or None when origin has no such ref here (never a guess that misfires)."""
    b = default_branch(root)
    ok = git(["rev-parse", "--verify", "-q", f"refs/remotes/origin/{b}"], cwd=root) is not None
    return b if ok else None


def changes_path(root):
    """The changes file's path in the repo: beside this script's ``../docs`` when the
    script lives inside ``root`` (``scripts/`` in a consumer, ``files/scripts/`` in
    agent-cadence itself, TD-038), else the consumer layout."""
    if script_in_repo(root):
        here = os.path.realpath(os.path.dirname(os.path.abspath(__file__)))
        return os.path.relpath(os.path.join(here, "..", CHANGES), os.path.realpath(root)).replace(os.sep, "/")
    return CHANGES


def origin_entries(root, with_landed=False):
    branch = origin_default(root)
    if branch is None:
        return None, []
    ref = f"origin/{branch}"
    text = git(["show", f"{ref}:{changes_path(root)}"], cwd=root)
    entries = parse(text)
    if with_landed:
        for e in entries:
            # the commit that introduced the heading on origin's default branch — the earliest -S hit
            log = git(
                ["log", "--format=%cI", "-S", e["heading"], ref, "--", changes_path(root)],
                cwd=root,
                timeout=15,
            )
            e["landed"] = log.strip().splitlines()[-1] if log and log.strip() else None
    return ref, entries


# --- a pinned repo (cadence.md §9.19, TD-250) ------------------------------------------------
# Run from a pinned tree (outside the repo), the repo has no changes file of its own: the
# entries are the source's `files/docs/cadence-changes.md` at the commit origin's pin names,
# read from the launcher's cache — never the repo. The cache's layout is the launcher's frozen
# interface (launcher/agent_cadence.py): trees/<commit>/, sources/<sha256(source)[:16]>.git and
# one cache-wide lock, taken here only to clone or fetch. SOURCE_RE and COMMIT_RE are the
# launcher's (tests/test_parity.sh 6d).
PIN_CHANGES = "files/docs/cadence-changes.md"
PIN_FILE = "docs/cadence.toml"
COMMIT_RE = re.compile(r"[0-9a-f]{40}")
SOURCE_RE = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://\S+|[^/\s:]+:\S+|/\S*")
LOCK_DEADLINE = 20.0  # the cache lock, non-blocking: a launcher's clone may hold it for minutes
FETCH_NET = 60        # a fetch holds the machine-wide cache lock
CLONE_NET = 300       # the launcher's own bound on a clone


class PinMiss(Exception):
    """--json/--list could not read origin's pin: exit 2 with this as the last stderr line."""


def script_in_repo(root):
    here = os.path.realpath(os.path.dirname(os.path.abspath(__file__)))
    top = os.path.realpath(root)
    return os.path.commonpath([here, top]) == top


def parse_pin(text):
    """(source, ref) from a cadence.toml's [agent-cadence] table, or None — a table that fails
    the launcher's checks, or a Python without tomllib, is no pin."""
    if not text:
        return None
    try:
        import tomllib

        table = tomllib.loads(text).get("agent-cadence")
    except (ImportError, ValueError):
        return None
    if not isinstance(table, dict):
        return None
    source, ref = table.get("source"), table.get("ref")
    if not (isinstance(source, str) and SOURCE_RE.fullmatch(source.strip())):
        return None
    if not (isinstance(ref, str) and COMMIT_RE.fullmatch(ref)):
        return None
    return source.strip(), ref


def pin_at(root, rev):
    return parse_pin(git(["show", f"{rev}:{PIN_FILE}"], cwd=root))


def worktree_pin(root):
    try:
        with open(os.path.join(root, PIN_FILE), encoding="utf-8") as f:
            return parse_pin(f.read())
    except (OSError, UnicodeDecodeError):
        return None


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "agent-cadence")


def source_bare(source):
    import hashlib

    return os.path.join(cache_dir(), "sources", hashlib.sha256(source.encode()).hexdigest()[:16] + ".git")


def has_commit(source, commit):
    bare = source_bare(source)
    return os.path.isdir(bare) and git(["--git-dir", bare, "cat-file", "-e", f"{commit}^{{commit}}"]) is not None


def pin_text(source, commit):
    """The changes file at commit: the tree on disk, else the clone's object; None when neither
    has it. Reads only — no lock, no network."""
    path = os.path.join(cache_dir(), "trees", commit, PIN_CHANGES)
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                return f.read()
        except (OSError, UnicodeDecodeError):
            pass
    bare = source_bare(source)
    if not os.path.isdir(bare):
        return None
    return git(["--git-dir", bare, "show", f"{commit}:{PIN_CHANGES}"], timeout=15)


def ensure_commit(source, commit):
    """Make commit readable from the cache's clone: one clone (to a .tmp, then renamed, as the
    launcher does) or one fetch, under the cache's lock taken without blocking. Raises PinMiss,
    an OSError (no git, a cache it cannot write) included."""
    try:
        _ensure_commit(source, commit)
    except OSError as e:
        raise PinMiss(f"the agent-cadence cache: {e.strerror or e}{f' ({e.filename})' if e.filename else ''}") from None


def _ensure_commit(source, commit):
    import fcntl

    if has_commit(source, commit):
        return
    cache = cache_dir()
    bare = source_bare(source)
    os.makedirs(os.path.dirname(bare), exist_ok=True)
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    with open(os.path.join(cache, "lock"), "a") as lock:
        deadline = time.monotonic() + LOCK_DEADLINE
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise PinMiss(f"the agent-cadence cache's lock ({cache}/lock) was held for {LOCK_DEADLINE:.0f}s") from None
                time.sleep(0.2)
        if has_commit(source, commit):  # another run made it while this one waited
            return
        if not os.path.isdir(bare):
            cmd, net = ["clone", "--bare", "--quiet", "--", source, bare + ".tmp"], CLONE_NET
            subprocess.run(["rm", "-rf", "--", bare + ".tmp"], check=False)
        else:
            cmd, net = ["--git-dir", bare, "fetch", "--quiet", "--", source,
                        "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*"], FETCH_NET
        try:
            p = subprocess.run(["git", *cmd], capture_output=True, text=True, timeout=net,
                               stdin=subprocess.DEVNULL, env=env, check=False)
            err = (p.stderr or "").strip().splitlines()[-1:] if p.returncode else None
        except subprocess.TimeoutExpired:
            err = [f"no answer in {net}s"]
        if err is not None:
            raise PinMiss(f"{'cloning' if cmd[0] == 'clone' else 'fetching'} {source} failed ({' '.join(err)})")
        if cmd[0] == "clone":
            os.rename(bare + ".tmp", bare)
    if not has_commit(source, commit):
        raise PinMiss(f"commit {commit} is not in {source}")


def heading_set(text):
    return {e["heading"] for e in parse(text)} if text is not None else None


def pinned_entries(root, ref, pin, with_landed=False):
    """Origin's entries in a pinned repo: the file at origin's pin. With landed, each heading's
    `landed` is the commit time, on ref, of the commit whose pin last brought it in — one
    first-parent walk of the commits changing docs/cadence.toml; a commit with no readable pin,
    another source, or a pinned commit the cache cannot give is skipped, and a skipped commit
    neither starts nor ends a heading's run."""
    source, commit = pin
    text = pin_text(source, commit)
    if text is None:
        ensure_commit(source, commit)
        text = pin_text(source, commit) or ""  # the commit is there; a file it lacks is no entries
    entries = parse(text)
    if with_landed:
        landed, prev, seen = {}, None, {}
        log = git(["log", "--first-parent", "--reverse", "--format=%H %cI", ref, "--", PIN_FILE],
                  cwd=root, timeout=15) or ""
        for line in log.splitlines():
            sha, _, when = line.partition(" ")
            p = pin_at(root, sha)
            if p is None or p[0] != source:
                continue
            if p[1] not in seen:
                seen[p[1]] = heading_set(pin_text(source, p[1]))
            heads = seen[p[1]]
            if heads is None:
                continue
            for h in heads:
                if prev is None or h not in prev:
                    landed[h] = when
            prev = heads
        for e in entries:
            e["landed"] = landed.get(e["heading"])
    return entries


def bump_base(root, ref):
    """The headings of the pin before the oldest bump within RECENT_DAYS on ref, or None. A bump
    is a first-parent commit whose pin names another ref than its parent's readable pin (so a
    migration or an adopt, whose parent has none, is never one, and a settings edit is passed
    over). Reads the cache only."""
    log = git(["log", "--first-parent", f"--since={RECENT_DAYS}.days", "--format=%H", ref, "--", PIN_FILE],
              cwd=root) or ""
    base = None
    for sha in log.split():  # newest first: the last bump found is the oldest
        cur, par = pin_at(root, sha), pin_at(root, f"{sha}^")
        if cur and par and cur[1] != par[1]:
            base = par
    return heading_set(pin_text(*base)) if base else None


def hook_pinned(root, ref, pin):
    """--hook in a pinned repo: no source fetch, no lock; what the cache cannot give says nothing."""
    source, oref = pin
    entries = parse(pin_text(source, oref) or "")
    wpin = worktree_pin(root)
    retired = os.path.join(root, CHANGES)
    if wpin is not None:
        own = heading_set(pin_text(*wpin))
    elif os.path.isfile(retired):  # a worktree branched before the migration
        try:
            with open(retired, encoding="utf-8") as f:
                own = heading_set(f.read())
        except (OSError, UnicodeDecodeError):
            own = None
    else:
        own = None
    base = bump_base(root, ref) if own is not None else None
    mp = marker_path(root)
    seen = read_marker(mp or "")
    today = dt.date.today()  # noqa: DTZ011  # local, like nudge's due dates (TD-053)
    new = [
        e
        for e in entries
        if e["heading"] not in seen
        and (recent(e, today) or (own is not None and (e["heading"] not in own or (base is not None and e["heading"] not in base))))
    ]
    behind = None
    wref = wpin[1] if wpin else None
    if f"pin {oref}" not in seen and wref != oref:
        bare = source_bare(source)
        ahead = wref and os.path.isdir(bare) and git(
            ["--git-dir", bare, "merge-base", "--is-ancestor", oref, wref]) is not None
        if not ahead:
            if wpin:
                now = f"this worktree pins {wref[:7]}, {ref} pins {oref[:7]}"
                tail = "; `agent-cadence path cadence.md` prints the path of the rules it runs now"
            elif own is not None:
                now, tail = f"this worktree carries its own copy; {ref} pins {oref[:7]}", ""
            else:
                now, tail = f"this worktree runs no agent-cadence; {ref} pins {oref[:7]}", ""
            behind = f"{now} — rebase{tail}"
    if new:
        n = len(new)
        print(f"📣 {n} cadence change{'s' if n != 1 else ''} this worktree has not seen ({PIN_CHANGES} at the pin on {ref}):")
        for e in new:
            print(f"  {e['heading']}")
            for line in e["body"].splitlines():
                print(f"    {line}")
        if behind:
            print(f"  ({behind})")
    elif behind:
        print(f"📣 ({behind})")
    if mp:
        write_marker(mp, [e["heading"] for e in new] + ([f"pin {oref}"] if f"pin {oref}" not in seen else []))
    return 0


def origin_pin(root):
    """(ref, pin) when this script runs from a pinned tree and origin's cadence.toml pins; else
    (ref or None, None) — the repo then reads as before (a synced copy, this repo, no pin)."""
    if script_in_repo(root):
        return None, None
    branch = origin_default(root)
    if branch is None:
        return None, None
    ref = f"origin/{branch}"
    return ref, pin_at(root, ref)


def local_headings(root):
    path = os.path.join(root, changes_path(root))
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return {e["heading"] for e in parse(f.read())}
    except OSError:
        return None


def marker_path(root):
    gd = git(["rev-parse", "--git-dir"], cwd=root)
    if not gd:
        return None
    gd = gd.strip()
    return (
        os.path.join(root, gd, MARKER)
        if not os.path.isabs(gd)
        else os.path.join(gd, MARKER)
    )


def read_marker(path):
    try:
        with open(path, encoding="utf-8") as f:
            return {line.rstrip("\n") for line in f if line.strip()}
    except OSError:
        return set()


def write_marker(path, headings):
    try:
        with open(path, "a", encoding="utf-8") as f:
            for h in headings:
                f.write(h + "\n")
    except OSError:
        pass  # a marker that cannot be written costs one repeat, never a failure


def recent(entry, today):
    try:
        return (today - dt.date.fromisoformat(entry["date"])).days <= RECENT_DAYS
    except ValueError:
        return False


FETCH_FRESH_S = 300  # FETCH_HEAD younger than this: the attention hook fetched this start
FETCH_TIMEOUT = 5.0
FETCH_TERM_GRACE = 1.0


def fetch_if_stale(root):
    """TD-044: one bounded, unpruned fetch of the default branch when nothing fetched this
    repo recently. Never raises; a failure leaves the ref as the last fetch left it."""
    common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root)
    if not common:
        return
    try:
        age = time.time() - os.path.getmtime(os.path.join(common.strip(), "FETCH_HEAD"))
    except OSError:
        age = None
    if age is not None and age < FETCH_FRESH_S:
        return
    # From the MAIN checkout: in a linked worktree `git -C <worktree> fetch` writes the
    # per-worktree FETCH_HEAD, which the check above never reads, and every start refetched.
    # An explicit refspec updates origin/<branch> even where remote.origin.fetch is narrowed.
    main = os.path.dirname(common.strip())
    branch = default_branch(main)
    cmd = ["git", "-C", main, "fetch", "-q", "--no-prune", "origin",
           f"+refs/heads/{branch}:refs/remotes/origin/{branch}"]
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0",
           "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=5"}
    try:
        with subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, env=env, start_new_session=True) as p:
            try:
                p.wait(timeout=FETCH_TIMEOUT)
            except subprocess.TimeoutExpired:
                # the whole group (git and its ssh/helper children); git removes its .lock
                # files on SIGTERM, SIGKILL leaves them
                os.killpg(p.pid, signal.SIGTERM)
                try:
                    p.wait(timeout=FETCH_TERM_GRACE)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGKILL)
                    p.wait()
    except OSError:  # ProcessLookupError/PermissionError included: the group already went
        pass


def hook(root):
    fetch_if_stale(root)
    ref, pin = origin_pin(root)
    if pin is not None:
        return hook_pinned(root, ref, pin)
    ref, entries = origin_entries(root)
    if not entries:
        return 0
    local = local_headings(root)
    mp = marker_path(root)
    seen = read_marker(mp or "")
    today = dt.date.today()  # noqa: DTZ011  # local, like nudge's due dates (TD-053)
    new = [
        e
        for e in entries
        if (local is None or e["heading"] not in local or recent(e, today))
        and e["heading"] not in seen
    ]
    if not new:
        return 0
    behind = local is None or any(e["heading"] not in local for e in entries)
    n = len(new)
    print(
        f"📣 {n} cadence change{'s' if n != 1 else ''} this worktree has not seen (docs/cadence-changes.md on {ref}):"
    )
    for e in new:
        print(f"  {e['heading']}")
        for line in e["body"].splitlines():
            print(f"    {line}")
    if behind:
        print(
            f"  (this worktree's docs/ are behind {ref} — rebase, or read `git show {ref}:docs/cadence.md`)"
        )
    if mp:
        write_marker(mp, [e["heading"] for e in new])
    return 0


def listing(root, since, as_json):
    ref, pin = origin_pin(root)
    if pin is not None:
        try:
            entries = pinned_entries(root, ref, pin, with_landed=as_json)
        except PinMiss as e:
            print(f"cannot read origin's pin {pin[1][:7]} ({PIN_CHANGES}): {e}", file=sys.stderr)
            return 2
    else:
        ref, entries = origin_entries(root, with_landed=as_json)
    if ref is None:
        print(
            "cannot read origin: no default branch on origin here (cadence.md §9 rule; git fetch origin; git remote set-head origin -a)",
            file=sys.stderr,
        )
        return 2
    if since:
        m = re.fullmatch(r"(\d+)d", since)
        days = int(m.group(1)) if m else None
        if days is None:
            print(f"bad --since {since!r}: use Nd", file=sys.stderr)
            return 2
        today = dt.date.today()  # noqa: DTZ011  # local, like nudge's due dates (TD-053)
        entries = [
            e
            for e in entries
            if (today - dt.date.fromisoformat(e["date"])).days <= days
        ]
    if as_json:
        print(json.dumps({"ref": ref, "entries": entries}, indent=1))
        return 0
    if not entries:
        print("no cadence changes")
        return 0
    for e in entries:
        print(e["heading"])
        for line in e["body"].splitlines():
            print(f"  {line}")
    return 0


def _not_a_repo_or_error():
    """None when cwd is simply not a git repo; else the first line of why git failed."""
    try:
        p = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5, check=False,
            env={**os.environ, "LC_ALL": "C", "LANGUAGE": ""},  # git's text is matched below
        )
    except subprocess.TimeoutExpired:
        return "git rev-parse timed out after 5s"
    except OSError as e:
        return f"git could not run ({e.strerror or e})"
    err = (p.stderr or "").strip()
    # silent when there is simply no checkout here (same pair as check_anchor's NOT_A_CHECKOUT)
    if p.returncode == 0 or "not a git repository" in err or "must be run in a work tree" in err:
        return None
    return (err.splitlines() or [f"git rev-parse exited {p.returncode}"])[0]


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="cadence convention changes a session has not seen"
    )
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument(
        "--hook",
        action="store_true",
        help="SessionStart: print unseen entries once per worktree",
    )
    g.add_argument("--list", action="store_true", help="list origin's entries")
    g.add_argument(
        "--json", action="store_true", help="origin's entries as JSON with landed times"
    )
    ap.add_argument("--since", help="with --list: only entries dated within Nd")
    args = ap.parse_args(argv)
    root = git(["rev-parse", "--show-toplevel"])
    if not root:
        why = _not_a_repo_or_error()
        if args.hook:
            # silent only when this is simply not a repo; any other git failure
            # (dubious ownership, timeout, no git) says so in one line (TD-043)
            if why:
                print(f"⚠ cadence-changes check did not run: {why}")
            return 0
        print(why or "not in a git repo", file=sys.stderr)
        return 2
    root = root.strip()
    try:
        if args.hook:
            return hook(root)
        return listing(root, args.since, args.json)
    except Exception as e:  # never a traceback into a session's context
        if args.hook:
            return 0
        print(f"cadence_changes: {type(e).__name__}: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
