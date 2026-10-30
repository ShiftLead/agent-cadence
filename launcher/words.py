#!/usr/bin/env python3
"""The launcher's words (TD-129): what `agent-cadence <word>` does, pinned with the tree it is in.

The launcher (launcher/agent_cadence.py, installed per machine and frozen) resolves a repo's pin and
execs this file from the pinned tree with CADENCE_REPO_ROOT set to the repo's root. So every word
here is pinned like the rest of the payload, and a new word is a change to this file, never to
the launcher (docs/plans/2026-10-25-pinned-not-synced.md, *Decision* 3).

    agent-cadence words                 list the words
    agent-cadence run <script> [args…]  run files/scripts/<script> from the pinned tree (.py with
                                      this Python, .sh with bash, anything else as itself), from
                                      the directory the command was run in
    agent-cadence path [<name>]         print the pinned payload's absolute path, or that of a file
                                      in it: <name> relative to files/, else to files/docs/ —
                                      `agent-cadence path cadence.md` is the rules this repo runs
    agent-cadence hook session-start    the SessionStart runner (cadence_hooks.sh --session-start),
                                      the session's stdin passed through
    agent-cadence -C <home> hook session-start --serve <sibling>
                                      the same for a constellation's sibling: the home's pin, the
                                      hooks run in the sibling, the board read from the home
    agent-cadence hook <git-hook> [args…]
                                      a shipped git hook (files/scripts/git-hooks/<git-hook>)
    agent-cadence gc [--apply]          the cached trees no roster repo or worktree pins: listed,
                                      and with --apply removed
    agent-cadence bump [<tag|commit>]   the repo's pin: with no argument, the newer tags of its
                                      source; with one, move the pin there — the ref line and its
                                      tag comment alone — and print what the bump PR's body carries
    agent-cadence -C <clone> adopt <repo>
                                      adopt a NEW repo at this clone's HEAD: the missing SEED files and
                                      skill pointers, the [agent-cadence] pin, the git hook shims, the
                                      roster line — committed by nobody; <repo> is relative to <clone>
                                      like any -C (a synced repo moves by `sync.sh --pin <repo>`)

A script `run` finds its repo from the directory it is run in (git, from the cwd), or — the two
that found it from their own path — from CADENCE_REPO_ROOT. For `hook` the launcher reads the
main checkout's pin, so every worktree's hooks run alike; the hook still judges the checkout it
runs in. A hook this tree does not ship says so on stderr and exits 0; a shipped hook's own exit
code is kept (the pre-push guard's refusal must reach git). A launcher that cannot resolve at all
exits 2 before this file runs, so failing open on that is the shim's job (the next slice), with the
pre-push main guard kept inline
in the shim, *Decision* 6).

`adopt` runs from an agent-cadence clone, never through a target's pin (a repo with no pin resolves
nowhere): the clone must be clean and its HEAD on origin's default branch as last fetched, and the
pin names origin's URL and that commit, with the tag as a comment only when HEAD is exactly at one.
It refuses a repo that carries synced copies, an agent-cadence clone, and a repo whose own ledger or board the
pinned readers cannot read (TD-168: `ledger.py --check`, a shape they skip, a newer format major); it seeds what is missing
(sync.sh's SEED_FILES, less the repo's `[skip-seed]`, and the six skill pointers, which are SEED
once pinned — *Decision* 5 — and lose their synced-file header), appends the pin under a header
written exactly `[agent-cadence]` (the form the shims and the SessionStart line detect), installs the
shims by the tree's install_git_hooks.sh, and registers the repo on the roster, last. It commits
nothing. `adopt --migrate`, which only `sync.sh --pin <repo>` runs, is the migration (*Decision* 11):
the same, on a clean synced checkout, after retiring each synced copy that still matches its lock
hash (an edited one is kept, with a WARN) and the lock; it lists the repo's own files that name
`scripts/` and edits none of them. On a constellation's home (a `docs/nested-repos.txt`) it first reads each sibling's
`.claude/settings.json` (and `settings.local.json`) and refuses, changing nothing, while one calls
the home's `scripts/` (`../scripts/`, `../<dir>/scripts/`) or is not on disk to read — the siblings move first, in their
own PRs, then `--siblings-moved` lets it through with a WARN per sibling still found (TD-147).

`bump` checks the new pin before it writes it: a commit of the pinned source, on its default
branch, descending from the old pin (a rollback is a bump the person makes by hand), and run
through the launcher (it has launcher/INTERFACE). It edits the checkout it runs in — the pin
lines and nothing else, read back to prove it — and commits nothing: the bump is a PR like any
other, reviewed on its compare, never merged unread (*Decision* 7). Once the new pin is checked,
the bump is handed to the new pin's own words.py (TD-174): its tree is made in the cache and its
`bump <commit>` exec'd, so what a bump writes is always the target's, a fix to bump itself included.
"""
import os
import re
import shutil
import sys

TREE = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
PAYLOAD = os.path.join(TREE, "files")
V1_LEDGER = ("docs/technical_debt.md", "docs/technical_debt_archive.md")   # seeds a v2 ledger (docs/ledger/) holds (TD-160)
INSTALL_LINE = ("clone agent-cadence at its latest tag, then run: "
                "install -m 755 launcher/agent_cadence.py ~/.local/bin/agent-cadence")


def fail(msg):
    print(f"agent-cadence: {msg}", file=sys.stderr)
    return 2


HELP = """\
agent-cadence words                 list the words
agent-cadence run <script> [args…]  run files/scripts/<script> from the pinned tree
agent-cadence path [<name>]         the pinned payload's path, or a file's in it (files/, then files/docs/)
agent-cadence hook session-start    the SessionStart runner
agent-cadence hook <git-hook> [args…]  a shipped git hook (fails open)
agent-cadence gc [--apply]          the cached trees nothing on the roster pins (--apply removes them)
agent-cadence bump [<tag|commit>]   the newer tags; with one, move the repo's pin there
agent-cadence -C <clone> adopt <repo>  pin a NEW repo to the clone's HEAD: seeds, pin, hook shims, roster"""


def w_words(args):
    print(HELP)
    return 0


def w_run(args):
    if not args:
        return fail("run needs a script (`agent-cadence run check_cadence.py --pr 12`)")
    name, rest = args[0], args[1:]
    if not name or "/" in name or name.startswith("."):
        return fail(f"run takes a script's name in files/scripts/, not a path: {name!r}")
    script = os.path.join(PAYLOAD, "scripts", name)
    if not os.path.isfile(script):
        return fail(f"no script {name} in {os.path.join(PAYLOAD, 'scripts')}")
    if name.endswith(".py"):
        argv = [sys.executable, script, *rest]
    elif name.endswith(".sh"):
        argv = ["bash", script, *rest]
    else:
        argv = [script, *rest]
    os.execvp(argv[0], argv)
    return 2   # not reached


def w_path(args):
    if len(args) > 1:
        return fail("path takes at most one name")
    if not args:
        print(PAYLOAD)
        return 0
    name = args[0]
    if os.path.isabs(name) or ".." in name.split("/"):
        return fail(f"path takes a name inside the payload, not {name!r}")
    for base in (PAYLOAD, os.path.join(PAYLOAD, "docs")):
        p = os.path.join(base, name)
        if os.path.exists(p):
            print(p)
            return 0
    return fail(f"no {name} in {PAYLOAD} or its docs/")


def w_hook(args):
    if not args:
        return fail("hook needs a name: session-start, or a git hook's")
    name, rest = args[0], args[1:]
    if name == "session-start":
        if rest[:1] == ["--serve"]:
            # a constellation's sibling (TD-147, cadence.md §9.12): the pin is its home's, which the
            # launcher resolved by -C; the hooks judge the sibling, so they run there, and the
            # board they read is the home's (CADENCE_HOME): the checkout -C named, which the
            # launcher left as the cwd — as the line's unpinned branch names it, never the main
            # checkout the pin was read from
            if len(rest) < 2 or not os.path.isdir(rest[1]):
                print(f"agent-cadence: hook session-start --serve needs the sibling's directory, not "
                      f"{rest[1] if len(rest) > 1 else 'nothing'} — the hooks did not run", file=sys.stderr)
                return 0   # a hook fails open
            os.environ["CADENCE_HOME"] = os.getcwd()
            os.chdir(rest[1])
            rest = rest[2:]
        script = os.path.join(PAYLOAD, "scripts", "cadence_hooks.sh")
        argv = ["bash", script, "--session-start", *rest]
    else:
        script = os.path.join(PAYLOAD, "scripts", "git-hooks", name)
        argv = [script, *rest]
    if "/" in name or name.startswith(".") or not (os.path.isfile(script) and os.access(script, os.X_OK)):
        print(f"agent-cadence: no hook {name!r} in {PAYLOAD} — it did not run", file=sys.stderr)
        return 0   # a hook fails open
    os.execvp(argv[0], argv)
    return 0   # not reached


# The cache's layout is the launcher's frozen interface (launcher/agent_cadence.py): trees/<commit>,
# sources/<key>.git, and one cache-wide lock that a launcher holds while it makes a tree.
COMMIT_RE = re.compile(r"[0-9a-f]{40}")
# The pin's other two shapes, each the launcher's or the hooks' own (cadence.md §7.9; tests/test_parity.sh
# 6d holds each to its twin): a source the launcher accepts (its SOURCE_RE), and the header line the
# shims and the seeded SessionStart line grep for, which is the only pin they see
SOURCE_RE = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://\S+|[^/\s:]+:\S+|/\S*")
PIN_HEADER_RE = re.compile(r"^[^\S\n]*\[agent-cadence\][^\S\n]*(#.*)?$", re.M)   # [^\S\n]: as grep's [[:space:]] for what TOML parses


def _cache():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "agent-cadence")


def _roster():
    """The roster's repos (cadence.md §9), or None when there is no roster."""
    d = os.environ.get("AGENT_CADENCE_REG_DIR") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"), "agent-cadence")
    try:
        with open(os.path.join(d, "repos.txt"), encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    return [p for p in (raw.split("#", 1)[0].strip() for raw in lines) if p]


def _pinned(checkout):
    """(the commit a checkout's docs/cadence.toml pins or None, a problem or None). A file that is
    there but cannot be read is a problem, never "no pin": gc errs toward keeping."""
    path = os.path.join(checkout, "docs", "cadence.toml")
    if not os.path.lexists(path):
        return None, None
    try:
        import tomllib
        with open(path, "rb") as f:
            table = tomllib.load(f).get("agent-cadence")
    except (OSError, ValueError, ImportError) as e:
        return None, f"{path}: {e}"
    ref = table.get("ref") if isinstance(table, dict) else None
    if table is not None and not (isinstance(ref, str) and COMMIT_RE.fullmatch(ref)):
        return None, f"{path}: [agent-cadence] ref is not a full commit ({ref!r})"
    return ref, None


def _worktrees(repo):
    import subprocess
    p = subprocess.run(["git", "-C", repo, "worktree", "list", "--porcelain"], capture_output=True,
                       text=True, check=False, stdin=subprocess.DEVNULL)
    if p.returncode != 0:
        return [repo]
    return [ln[len("worktree "):] for ln in p.stdout.splitlines() if ln.startswith("worktree ")]


def _plan(roster):
    """(the trees to keep, the problems that make the plan unsafe, the cached tree names)."""
    keep, problems = set(), []
    for repo in roster:
        if not os.path.isdir(repo):
            problems.append(f"{repo}: on the roster but not here (unmounted, moved, or a stale line)")
            continue
        for wt in _worktrees(repo):
            if not os.path.isdir(wt):
                problems.append(f"{wt}: a worktree of {repo} that is not here (`git worktree prune` if it is gone)")
                continue
            ref, why = _pinned(wt)
            if why:
                problems.append(why)
            elif ref:
                keep.add(ref)
    root = os.environ.get("CADENCE_REPO_ROOT", "").strip()
    if root:
        ref, why = _pinned(root)   # the repo it is run from, on the roster or not
        if why:
            problems.append(why)
        elif ref:
            keep.add(ref)
    trees = os.path.join(_cache(), "trees")
    if os.path.dirname(TREE) == trees:
        keep.add(os.path.basename(TREE))   # the tree this gc runs from
    try:
        names = sorted(n for n in os.listdir(trees) if COMMIT_RE.fullmatch(n))
    except OSError:
        names = []
    return keep, problems, names


def w_gc(args):
    if args not in ([], ["--apply"]):
        return fail("gc takes only --apply")
    roster = _roster()
    if not roster:
        return fail("no roster, or an empty one (cadence.md §9) — cannot tell which trees are pinned, "
                    "so none is removed")
    trees = os.path.join(_cache(), "trees")
    if args != ["--apply"]:
        keep, problems, names = _plan(roster)
        for why in problems:
            print(f"gc: cannot read  {why}")
        drop = [n for n in names if n not in keep]
        for n in drop:
            print(f"gc: unpinned  {os.path.join(trees, n)}")
        if not drop:
            print(f"gc: nothing to remove ({len(names)} cached, {len(keep)} pinned)")
        elif problems:
            print(f"gc: {len(drop)} tree(s) nothing readable pins — --apply refuses until the above is fixed")
        else:
            print(f"gc: {len(drop)} tree(s) nothing pins — `agent-cadence gc --apply` removes them")
        return 0
    import fcntl
    os.makedirs(_cache(), exist_ok=True)
    with open(os.path.join(_cache(), "lock"), "a") as lock:
        # the scan runs under the lock too: a tree a launcher makes for a new pin is either
        # whole before the scan (and the scan sees its pin) or made after the removal
        fcntl.flock(lock, fcntl.LOCK_EX)
        keep, problems, names = _plan(roster)
        if problems:
            for why in problems:
                print(f"gc: cannot read  {why}", file=sys.stderr)
            return fail("a pin could not be read — nothing removed, since that tree may be in use")
        drop = [n for n in names if n not in keep]
        if not drop:
            print(f"gc: nothing to remove ({len(names)} cached, {len(keep)} pinned)")
        for n in drop:
            path = os.path.join(trees, n)
            for d, dirs, _files in os.walk(path):
                for name in [*dirs, "."]:
                    q = os.path.normpath(os.path.join(d, name))
                    if not os.path.islink(q):
                        os.chmod(q, 0o755)
            shutil.rmtree(path, ignore_errors=True)
            print(f"gc: removed   {path}" if not os.path.exists(path) else f"gc: could not remove {path}")
    return 0


PIN_REF_RE = re.compile(r'^(\s*ref\s*=\s*)"([0-9a-f]{40})"[ \t]*(#.*)?$')
TABLE_RE = re.compile(r"^\s*\[")


def _git(*args, timeout=None):
    import subprocess
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        p = subprocess.run(["git", *args], capture_output=True, text=True, check=False,
                           stdin=subprocess.DEVNULL, env=env, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 1, f"no answer in {timeout}s"
    return p.returncode, (p.stdout if p.returncode == 0 else p.stderr).strip()


def _git_bytes(*args):
    """(rc, stdout or stderr as bytes) — _git for a file's content, kept byte for byte."""
    import subprocess
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
    p = subprocess.run(["git", *args], capture_output=True, check=False, stdin=subprocess.DEVNULL, env=env)
    return p.returncode, (p.stdout if p.returncode == 0 else p.stderr)


def _source_clone(source):
    """(the cache's bare clone of source — the launcher's layout — fetched now under the cache's
    lock and made if the cache lost it, a problem or None). Never pruned, as the launcher never
    prunes: a tree's commit stays in the clone."""
    import fcntl
    import hashlib
    bare = os.path.join(_cache(), "sources", hashlib.sha256(source.encode()).hexdigest()[:16] + ".git")
    os.makedirs(os.path.dirname(bare), exist_ok=True)
    with open(os.path.join(_cache(), "lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not os.path.isdir(bare):
            tmp = bare + ".tmp"
            shutil.rmtree(tmp, ignore_errors=True)
            rc, err = _git("clone", "--bare", "--quiet", "--", source, tmp, timeout=300)
            if rc != 0:
                return None, f"cloning {source} failed ({err})"
            os.rename(tmp, bare)
            return bare, None
        rc, err = _git("--git-dir", bare, "fetch", "--quiet", "--", source,
                       "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*", timeout=300)
    return bare, (None if rc == 0 else f"fetching {source} failed ({err})")


def _default_branch(source):
    """The source's default branch, asked of the source now (never the cached clone's HEAD,
    which is the default as it was when the clone was made), or None."""
    rc, out = _git("ls-remote", "--symref", "--", source, "HEAD", timeout=60)
    m = re.match(r"ref: refs/heads/(\S+)\tHEAD", out) if rc == 0 else None
    return m.group(1) if m else None


def _changes(bare, ref):
    """The cadence-changes.md headings at ref, in file order."""
    rc, text = _git("--git-dir", bare, "show", f"{ref}:files/docs/cadence-changes.md")
    return [ln[3:] for ln in text.splitlines() if ln.startswith("## ")] if rc == 0 else []


def _unheadered(body):
    """A pointer as adopt seeds it: the synced-file header gone."""
    return SYNCED_HEADER_RE.sub("\n", body.decode("utf-8", "replace"), count=1).encode("utf-8")


def _pointer_plan(bare, new, root):
    """TD-158: what bump does to each skill pointer of the new pin — [(path, action, body, why)], action
    one of seed | refresh | keep. A pointer is SEED (the pin plan's *Decision* 5), so only one the repo
    never edited is rewritten: equal to a version of files/<path> in the new pin's history, with or
    without its synced-file header. A missing one is seeded as adopt seeds it; an edited one is kept."""
    rc, listed = _git_bytes("--git-dir", bare, "ls-tree", "-r", "-z", "--name-only", new, "--", "files/")
    if rc != 0:
        return None
    paths = sorted(f[len("files/"):] for f in listed.decode("utf-8", "surrogateescape").split("\0")
                   if f.startswith("files/") and POINTER_RE.fullmatch(f[len("files/"):]))
    real_root = os.path.realpath(root)
    plan = []
    for rel in paths:
        rc, body = _git_bytes("--git-dir", bare, "show", f"{new}:files/{rel}")
        if rc != 0:
            continue
        body = _unheadered(body)
        dst = os.path.join(root, rel)
        # a link (the pointer, or a directory above it) is the repo's own arrangement, and writing
        # through it could land outside the repo: never followed
        if os.path.islink(dst) or os.path.realpath(os.path.dirname(dst)) != os.path.join(real_root, os.path.dirname(rel)):
            plan.append((rel, "keep", None, "a symlink, or under one: not touched"))
            continue
        if not os.path.lexists(dst):
            plan.append((rel, "seed", body, "missing"))
            continue
        try:
            with open(dst, "rb") as f:
                have = f.read()
        except OSError as e:
            plan.append((rel, "keep", None, f"cannot be read ({e.strerror}) — not checked"))
            continue
        if have == body:
            plan.append((rel, "keep", None, "already the new pin's text"))
            continue
        _, log = _git("--git-dir", bare, "log", "--format=%H", new, "--", f"files/{rel}")
        match = None
        for c in log.split():
            rc, old = _git_bytes("--git-dir", bare, "show", f"{c}:files/{rel}")
            if rc == 0 and have in (old, _unheadered(old)):
                match = c
                break
        if match:
            plan.append((rel, "refresh", body, f"an unedited copy of {match[:12]}"))
        else:
            plan.append((rel, "keep", None, "edited here (no version of it matches, line endings included): left as it is"))
    return plan


def _hand_off(source, new):
    """TD-174: run the bump in the target's tree, so its checks and its writes are the target's. The
    launcher execs the CURRENT pin's words.py, so a change to what bump writes (TD-158's pointer refresh,
    a format migration under *Decision* 7) would otherwise reach a repo one bump late, silently. The
    target's tree is made by this tree's copy of the launcher (its cache layout is frozen) and its
    interface checked the same way. That tree is trees/<new>, so the target's own bump finds itself
    there and goes on. Returns only when there is nothing to hand off to: an exit code to stop with, or
    None to go on here (this tree is the target, or carries no launcher to make one)."""
    if os.path.basename(TREE) == new:
        return None
    here = os.path.join(TREE, "launcher")
    if not os.path.isfile(os.path.join(here, "agent_cadence.py")):
        print(f"warning: {TREE} has no launcher/agent_cadence.py to make {new[:12]}'s tree: this bump runs "
              "the old pin's code, so a change to bump itself arrives with the next one", file=sys.stderr)
        return None
    if here not in sys.path:
        sys.path.insert(0, here)
    import agent_cadence
    try:
        tree = agent_cadence.ensure_tree(source, new)
        agent_cadence.check_interface(tree)
    except (agent_cadence.Refusal, OSError) as e:
        return fail(f"cannot make {new[:12]}'s tree to run its bump ({e}) — nothing written")
    print(f"bump: running {new[:12]}'s bump, so what it checks and writes is the new pin's (TD-174)", file=sys.stderr)
    sys.stdout.flush()
    sys.stderr.flush()
    os.execve(sys.executable, [sys.executable, os.path.join(tree, "launcher", "words.py"), "bump", new], os.environ)
    return 2   # not reached


def w_bump(args):
    if len(args) > 1 or (args and args[0].startswith("-")):
        return fail("bump takes at most one tag or commit")
    root = os.environ.get("CADENCE_REPO_ROOT", "").strip()
    path = os.path.join(root, "docs", "cadence.toml")
    if not root or not os.path.isfile(path):
        return fail(f"no docs/cadence.toml with a [agent-cadence] pin to move in {root or 'this checkout'} "
                    "(agent-cadence's own repo runs from its tree)")
    try:
        import tomllib
        with open(path, "rb") as f:
            before = f.read()
        table = tomllib.loads(before.decode("utf-8"))
    except (OSError, ValueError, ImportError) as e:
        return fail(f"cannot read the pin in {path}: {e}")
    pin = table.get("agent-cadence")
    if not root or not isinstance(pin, dict) or not COMMIT_RE.fullmatch(str(pin.get("ref"))):
        return fail(f"{path} has no [agent-cadence] pin to move (agent-cadence's own repo runs from its tree)")
    source, old = str(pin.get("source", "")).strip(), pin["ref"]
    bare, warn = _source_clone(source)
    if bare is None:
        return fail(warn)
    if warn and args:
        return fail(f"{warn} — a bump is checked against the source as it is now, so nothing is written")
    if warn:
        print(f"warning: {warn}: listing what the cache has", file=sys.stderr)
    head = _default_branch(source)
    if head is None and args:
        return fail(f"cannot ask {source} for its default branch, so a bump cannot be checked against it")
    if not args:
        if head is None:
            print(f"warning: {source} did not say its default branch: counting from the cache's", file=sys.stderr)
            head = _git("--git-dir", bare, "symbolic-ref", "--short", "HEAD")[1]
        rc, tags = _git("--git-dir", bare, "tag", "--contains", old, "--sort=-creatordate")
        newer = [t for t in tags.split() if _git("--git-dir", bare, "rev-parse", f"{t}^{{commit}}")[1] != old]
        _, ahead = _git("--git-dir", bare, "rev-list", "--count", f"{old}..{head}")
        print(f"pinned at {old}; {ahead or '?'} commit(s) on {source} {head} since"
              + (f"; newer tags: {', '.join(newer)}" if newer else "; no newer tag"))
        print("move the pin with: agent-cadence bump <tag|commit>")
        return 0
    want = args[0]
    rc, new = _git("--git-dir", bare, "rev-parse", "--verify", "--quiet", f"{want}^{{commit}}")
    if rc != 0:
        return fail(f"{want!r} is not a commit or tag of {source}")
    if new == old:
        print(f"already pinned at {new}")
        return 0
    if _git("--git-dir", bare, "merge-base", "--is-ancestor", new, f"refs/heads/{head}")[0] != 0:
        return fail(f"{want} ({new}) is not on {source}'s default branch {head}")
    if _git("--git-dir", bare, "merge-base", "--is-ancestor", old, new)[0] != 0:
        return fail(f"{want} ({new}) does not descend from the pin {old}: a rollback is a bump "
                    "the person makes by hand")
    if _git("--git-dir", bare, "cat-file", "-e", f"{new}:launcher/INTERFACE")[0] != 0:
        return fail(f"{want} ({new}) has no launcher/INTERFACE: it cannot be run through the launcher")
    handed = _hand_off(source, new)
    if handed is not None:
        return handed
    rc, tag = _git("--git-dir", bare, "describe", "--tags", "--exact-match", new)
    tag = tag if rc == 0 else ""
    text = before.decode("utf-8")
    lines = text.splitlines(keepends=True)
    in_pin, at = False, []
    for i, ln in enumerate(lines):
        if TABLE_RE.match(ln):
            in_pin = ln.split("#", 1)[0].strip().replace(" ", "") in ("[agent-cadence]", '["agent-cadence"]')
        elif in_pin and PIN_REF_RE.match(ln.rstrip("\r\n")):
            at.append(i)
    if len(at) != 1:
        return fail(f"{path}: the pin's ref is not one line `ref = \"<commit>\"` in [agent-cadence] — move it to {new} by hand")
    m = PIN_REF_RE.match(lines[at[0]].rstrip("\r\n"))
    nl = lines[at[0]][len(lines[at[0]].rstrip("\r\n")):]
    lines[at[0]] = f'{m.group(1)}"{new}"' + (f"   # {tag}" if tag else "") + nl
    after = "".join(lines)
    expect = dict(table, **{"agent-cadence": dict(pin, ref=new)})
    if tomllib.loads(after) != expect:
        return fail(f"{path} not changed — the edit would not read as the same file with the new ref")
    pointers = _pointer_plan(bare, new, root)
    if pointers is None:
        return fail(f"cannot list {new}'s skill pointers in the cache's clone — nothing written")
    with open(path, "rb") as f:
        if f.read() != before:
            return fail(f"{path} changed while the source was fetched — nothing written; run bump again")
    # the pointers first, each by a rename, and the pin last: a write that fails leaves the pin where it
    # was, so bump runs again (a pointer already written then reads as the new pin's text)
    for rel, action, body, why in pointers:
        if body is not None:
            dst = os.path.join(root, rel)
            try:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                tmp = f"{dst}.bump-{os.getpid()}"
                with open(tmp, "wb") as f:
                    f.write(body)
                os.replace(tmp, dst)
            except OSError as e:
                return fail(f"cannot write {rel} ({e.strerror}) — the pin is not moved; run bump again once it can be")
        elif why.startswith("edited"):
            print(f"warning: {rel} is {why}", file=sys.stderr)
        print(f"  {action:<7} {rel} ({why})")
    tmp = f"{path}.bump-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(after)
    os.replace(tmp, path)
    print(f"pin: {old} -> {new}" + (f" ({tag})" if tag else "") + f" in {path}")
    seen = set(_changes(bare, old))
    fresh = [h for h in _changes(bare, new) if h not in seen]
    print("\n--- the bump PR's body (Decision 7): the reviewer reads the compare, not the one-line change")
    if source.startswith("https://github.com/"):
        print(f"compare: {source.removesuffix('.git')}/compare/{old}...{new}")
    else:
        print(f"compare: git log {old}..{new} in {source}")
    print("cadence-changes since the old pin:" if fresh else "cadence-changes since the old pin: none")
    for h in fresh:
        print(f"- {h}")
    if pointers:
        print("skill pointers (TD-158: an unedited one follows the pin):")
        for rel, action, _, why in pointers:
            print(f"- {action} `{rel}`: {why}")
    return 0


def _sh_array(name):
    """The paths in sync.sh's NAME=( … ) array: one quoted path a line (tests/test_adopt.sh holds
    this reading to bash's own)."""
    with open(os.path.join(TREE, "sync.sh"), encoding="utf-8") as f:
        text = f.read()
    m = re.search(rf"^{name}=\(\n(.*?)^\)$", text, re.S | re.M)
    return re.findall(r'^\s*"([^"]+)"\s*$', m.group(1), re.M) if m else None


def _under_temp(path):
    """The retired copy's under_temp(), in Python (TD-068): is path under a temp root —
    $CADENCE_TEMP_ROOTS (colon-separated), else $TMPDIR, /tmp, /var/tmp."""
    p = os.path.realpath(path)
    roots = os.environ.get("CADENCE_TEMP_ROOTS") or f"{os.environ.get('TMPDIR') or '/tmp'}:/tmp:/var/tmp"
    for t in roots.split(":"):
        t = os.path.realpath(t).rstrip("/") if t else ""
        if t and (p + "/").startswith(t + "/"):   # a root of "/" would call every path temporary
            return True
    return False


def _register(root):
    """Append root to the roster, adopt's last step (cadence.md §9; the retired copy's too): idempotent, under
    flock, never a temp-dir repo onto a roster outside one; a failure is a warning, never fatal."""
    import fcntl
    d = os.environ.get("AGENT_CADENCE_REG_DIR") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"), "agent-cadence")
    reg = os.path.join(d, "repos.txt")
    if _under_temp(root) and not _under_temp(d):
        print(f"  WARN  {root} is in a temp dir and {reg} is not — registration skipped (a fixture on the "
              "machine roster is polled by every roster reader). Set AGENT_CADENCE_REG_DIR=$(mktemp -d) for a test run.")
        return
    try:
        os.makedirs(d, exist_ok=True)
        with open(reg, "a+", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0)
            if root in f.read().splitlines():
                print(f"  reg   already in machine registry ({reg})")
                return
            f.write(root + "\n")
        print(f"  reg   {root} -> machine registry ({reg})")
    except OSError as e:
        print(f"  WARN  could not append to {reg} ({e}) — registration skipped; re-run adopt to retry")


POINTER_RE = re.compile(r"\.(claude|agents)/skills/[^/]+/SKILL\.md")
SYNCED_HEADER_RE = re.compile(r"\n<!-- SYNCED FILE.*?-->\n\n", re.S)


def _sha256(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _retire(dest, lock_path):
    """Remove each synced copy the lock lists that still matches its recorded hash — sync.sh's RETIRED
    rule (TD-057) — keep an edited one with a warning, then the lock; prune the directories left empty."""
    kept, unread = [], 0
    with open(lock_path, encoding="utf-8") as f:
        for line in f:
            m = re.fullmatch(r"file: (.+?) ([0-9a-f]{64})(?: (?:755|644))?", line.rstrip("\n"))  # as --verify parses it
            if not m:
                unread += line.startswith("file:")
                continue
            rel, sha = m.groups()
            path = os.path.join(dest, rel)
            # the lock is committed, so untrusted: a path that leaves the checkout — absolute, a `..`,
            # or through a symlinked directory — is never touched
            parent = os.path.realpath(os.path.dirname(path))
            if os.path.isabs(rel) or ".." in rel.split("/") or not (parent == dest or parent.startswith(dest + os.sep)):
                print(f"  WARN  {rel}: the lock names a path outside the checkout — left alone")
                continue
            if not os.path.lexists(path):
                continue
            if os.path.islink(path) or not os.path.isfile(path):
                print(f"  WARN  {rel}: not a plain file (a symlink?) — left alone; remove it by hand")
                continue
            if _sha256(path) != sha:
                kept.append(rel)
                header = " (its SYNCED FILE header is stale now: nothing overwrites it)" if POINTER_RE.fullmatch(rel) else ""
                print(f"  WARN  {rel}: edited since it was synced — kept{header}; port what it changed and delete it by hand")
                continue
            os.remove(path)
            print(f"  gone  {rel}")
            d = os.path.dirname(path)
            while d != dest and d.startswith(dest + os.sep) and os.path.isdir(d) and not os.listdir(d):
                os.rmdir(d)
                d = os.path.dirname(d)
    if unread:
        print(f"  WARN  {unread} lock line(s) carry no sha256 (a lock older than the hashes): their copies were "
              "left alone — compare each with the pinned payload and delete it by hand")
    os.remove(lock_path)
    print("  gone  docs/cadence-sync.lock")
    return kept


COMMAND_RE = re.compile(r'("command"\s*:\s*)("(?:[^"\\]|\\.)*")')


def _session_line(dest, ref):
    """TD-149: the migration's SessionStart line. A synced repo's `.claude/settings.json` (a SEED, so
    kept) may still run `scripts/cadence_hooks.sh` by an older line, which finds nothing once the copy
    is retired and, by design, says nothing. Each SessionStart command that runs it and is not the
    seed's line becomes the seed's line, as the seed's file writes it — a text edit that keeps every
    other byte, read back as exactly the old settings with those commands changed, or the file is left
    for a person. Returns the seed's literal (the scan below ignores it) and what was done, a line to
    print or ""."""
    import json
    rc, raw = _git_bytes("-C", TREE, "show", f"{ref}:files/.claude/settings.json")
    try:
        seed_text = raw.decode("utf-8") if rc == 0 else ""
        seed_cmds = [h.get("command", "") for e in json.loads(seed_text)["hooks"]["SessionStart"]
                     for h in e.get("hooks", [])]
    except (ValueError, KeyError, TypeError, AttributeError):
        return "", f"  WARN  files/.claude/settings.json at {ref} has no SessionStart line to copy (TD-149)"
    seed_cmd = next((c for c in seed_cmds if "cadence_hooks.sh" in c), None)
    literal = next((m.group(2) for m in COMMAND_RE.finditer(seed_text) if json.loads(m.group(2)) == seed_cmd), None)
    if seed_cmd is None or literal is None:
        return "", f"  WARN  files/.claude/settings.json at {ref} has no SessionStart line to copy (TD-149)"
    path = os.path.join(dest, ".claude", "settings.json")
    by_hand = ("  WARN  .claude/settings.json: {why} — replace each SessionStart command that runs "
               "scripts/cadence_hooks.sh with the seed's line (files/.claude/settings.json) by hand, or no "
               "cadence hook runs at session start (TD-149)")
    if not os.path.lexists(path):
        return literal, ""
    if os.path.islink(path) or not os.path.isfile(path):   # a dotfiles symlink is the person's, never rewritten
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                named = "cadence_hooks.sh" in f.read()
        except OSError:
            named = True   # unreadable: say so rather than pass it
        return literal, by_hand.format(why="it is a symlink, never rewritten") if named else ""
    try:
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        old = json.loads(text)
        entries = old["hooks"]["SessionStart"] if isinstance(old, dict) and isinstance(old.get("hooks"), dict) \
            and "SessionStart" in old["hooks"] else []
        stale = {h["command"] for e in entries for h in e.get("hooks", [])
                 if isinstance(h.get("command"), str) and "cadence_hooks.sh" in h["command"] and h["command"] != seed_cmd}
    except (OSError, ValueError, TypeError, AttributeError, KeyError) as e:
        return literal, by_hand.format(why=f"cannot read it ({type(e).__name__}: {e})")
    if not stale:
        return literal, ""
    want = json.loads(text)
    for e in want["hooks"]["SessionStart"]:
        for h in e.get("hooks", []):
            if h.get("command") in stale:
                h["command"] = seed_cmd
    n = [0]

    def swap(m):
        if json.loads(m.group(2)) in stale:
            n[0] += 1
            return m.group(1) + literal
        return m.group(0)
    after = COMMAND_RE.sub(swap, text)
    try:
        same = json.loads(after) == want
    except ValueError:
        same = False
    if not same:
        return literal, by_hand.format(why="the line would not read back as only that change")
    tmp = f"{path}.pin-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(after)
    shutil.copymode(path, tmp)
    os.replace(tmp, path)
    return literal, (f"  replaced .claude/settings.json: {n[0]} SessionStart command(s) that ran "
                     "scripts/cadence_hooks.sh, now the seed's line (it runs the pin; TD-149)")


SIBLING_CALL_RE = re.compile(rb"\.\./(?:[^/\s\"'`]+/)?scripts/")   # ../scripts/, ../<home>/scripts/


def _gitignore(dest):
    """TD-168, the retired copy's step 3 (tests/fixtures/legacy_sync.sh): the lines a new repo's own .gitignore
    needs — the literal line, not the effective ignore status, since a machine's global gitignore does not
    protect a collaborator's clone. `.claude/worktrees/` sits inside the checkout, so without it every worktree
    is untracked noise a stray `git add -A` reaches into; `*.code-workspace` is generated per topic (§1); a
    `worktree-root` other than the default is ignored too, and `.claude/worktrees/` stays, for `claude
    --worktree`. Appends what is missing, after a final newline the file lacked; never through a symlink."""
    import subprocess
    lines = ["docs/session_index.md", ".claude/settings.local.json", ".claude/worktrees/", "*.code-workspace"]
    p = subprocess.run([sys.executable, os.path.join(PAYLOAD, "scripts", "cadence_config.py"), "get", "worktree-root",
                        "--repo", dest], capture_output=True, text=True, check=False, stdin=subprocess.DEVNULL)
    root = p.stdout.strip() if p.returncode == 0 else ""
    if root and root != ".claude/worktrees":
        lines.append(root.rstrip("/") + "/")
    path = os.path.join(dest, ".gitignore")
    if os.path.islink(path):
        print("  WARN  .gitignore is a symlink — not written through: add by hand " + ", ".join(lines))
        return
    try:
        try:
            with open(path, "rb") as f:
                have = f.read()
        except FileNotFoundError:
            have = b""
        present = set(have.decode("utf-8", "surrogateescape").splitlines())
        add = [ign for ign in lines if ign not in present]
        if add:
            with open(path, "ab") as f:
                f.write((b"\n" if have and not have.endswith(b"\n") else b"") + "".join(i + "\n" for i in add).encode())
    except OSError as e:   # a directory, no permission: said, and adopt goes on to the shims and the roster
        print(f"  WARN  .gitignore not written ({e.strerror or e}): add by hand " + ", ".join(lines))
        return
    for ign in lines:
        if ign in present:
            print(f"  conf  {ign} already in .gitignore")
    if add:
        for ign in add:
            print(f"  conf  {ign} added to .gitignore")


def _seed_warnings(dest, bodies, skip, migrate):
    """TD-168: the retired copy's two detectors (tests/fixtures/legacy_sync.sh, the hook-wiring and
    Gemini-map ones), for a SEED the repo already had, which adopt keeps. Warn, never rewrite, never
    raise: a file nothing can read is said, and adopt goes on. On a migration a cadence line that differs
    is `_session_line`'s, which rewrites it or says why not; a missing one is warned here either way."""
    import json
    unreadable = (OSError, ValueError, AttributeError, TypeError, RecursionError)   # deep nesting: RecursionError

    def commands(raw):
        return [str(h.get("command", "")) for g in json.loads(raw).get("hooks", {}).get("SessionStart", [])
                for h in g.get("hooks", [])]

    out = []
    rel = ".claude/settings.json"
    path = os.path.join(dest, rel)
    if rel not in skip and rel in bodies and os.path.isfile(path):
        want = next((c for c in commands(bodies[rel]) if "cadence_hooks.sh" in c), None)
        try:
            with open(path, "rb") as f:
                cmds = commands(f.read())
        except unreadable:
            out.append(f"  WARN  {rel}: not readable as settings JSON; cannot check the SessionStart hook line")
        else:
            if want is not None and want not in cmds:
                if any("cadence_hooks.sh" in c or "agent-cadence hook" in c for c in cmds):
                    if not migrate:
                        out.append(f"  WARN  {rel}: the cadence SessionStart line differs from the seed — make it "
                                   "byte-identical to files/.claude/settings.json's (cadence §3)")
                else:
                    out.append(f"  WARN  {rel}: SessionStart lacks the cadence line, so no cadence hook runs at "
                               "session start — add the one line from files/.claude/settings.json (cadence §3)")
    rel = ".gemini/settings.json"
    path = os.path.join(dest, rel)
    if rel not in skip and os.path.isfile(path):
        try:
            with open(path, "rb") as f:
                names = (json.loads(f.read()).get("context") or {}).get("fileName")
        except unreadable:
            out.append(f"  WARN  {rel}: not readable as settings JSON; cannot check that Gemini CLI reads AGENTS.md")
        else:
            if "AGENTS.md" not in (names if isinstance(names, list) else [names]):
                out.append(f"  WARN  {rel}: context.fileName does not name AGENTS.md, so a Gemini CLI session gets "
                           'no map and no wake-up — add "AGENTS.md" to it, as files/.gemini/settings.json does '
                           "(cadence §7.6, TD-111)")
    return out


def _home_siblings(dest, root):
    """TD-147: the siblings in a home's docs/nested-repos.txt (cadence.md §9.15) whose .claude/settings.json
    or settings.local.json calls a `scripts/` one directory up (`../scripts/`, `../<dir>/scripts/` — the
    home's, §9.12; any directory name matches, so it errs toward refusing), each as a line to print; one
    not on disk to read is named too, since nothing says it does not. Read in the checkout migrated,
    else in the main checkout, where a worktree's skipped sibling still is. [] for a repo with no list."""
    try:
        with open(os.path.join(dest, "docs", "nested-repos.txt"), encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return []
    out = []
    for line in lines:
        fields = line.split("#", 1)[0].split()
        if not fields:
            continue
        base = next((d for d in (dest, root) if os.path.isdir(os.path.join(d, fields[0]))), None)
        if base is None:
            out.append(f"{fields[0]} (not here to read: check its .claude/settings.json by hand)")
            continue
        for name in ("settings.json", "settings.local.json"):
            rel = os.path.join(fields[0], ".claude", name)
            if not os.path.isfile(os.path.join(base, rel)):
                continue
            try:
                with open(os.path.join(base, rel), "rb") as f:
                    body = f.read(1 << 20)
            except OSError as e:
                out.append(f"{rel} (could not be read: {e})")
                continue
            n = len(SIBLING_CALL_RE.findall(body))
            if n:
                out.append(f"{rel} ({n} call(s) into the home's scripts/)")
    return out


def _format_problems(dest, adopt, skip):
    """TD-133, as the retired copy's first sync did (TD-168): what in the repo's own ledger and board the
    pinned readers cannot read — [problem], empty when nothing. Any one declaring a newer major of the
    formats (`Ledgerboard: N`); for a NEW repo (``adopt``) also a ledger failing `ledger.py --check`, a v1
    or v2 one, and anything the readers would skip — an entry that is not a `## TD-NNN:` body, a summary
    row with no body, a board line that is not a `- [ ]` item. Converting a foreign ledger or board is the
    person's, so adopt refuses on any, before it writes. ``skip``: the repo's skip-seed opt-outs."""
    import json
    import subprocess
    scripts = os.path.join(PAYLOAD, "scripts")
    if scripts not in sys.path:
        sys.path.insert(0, scripts)
    sys.dont_write_bytecode = True   # the clone adopt runs from stays as clean as it was (a pin names a commit)
    import ledgerboard as LB
    LEDGER, ARCHIVE, BOARD = (*V1_LEDGER, "docs/user_attention.md")
    V2 = "docs/ledger"   # TD-160: its README.md carries the version; ledger.py --check reads the directory
    SKIP_HEAD = re.compile(r"^(?!## TD-\d+:)#{1,6}[ \t]*[*_`]*TD-\d+", re.MULTILINE)
    SKIP_ITEM = re.compile(r"^[ \t]*[-*+][ \t]+[*_`]*TD-\d+", re.MULTILINE)
    NO_ID_SHAPE = re.compile(r"^(?:[ \t]*[-*+][ \t]+\S|#{2,6}[ \t]+(?!Summary[ \t]*$)\S)", re.MULTILINE)  # a list line, a section
    SKIP_BOARD = re.compile(r"^[-*+][ \t]+(?!\[[ xX]\][ \t])(?!\(none\))", re.MULTILINE)
    kept = [f for f in (LEDGER, ARCHIVE, BOARD) if os.path.lexists(os.path.join(dest, f)) and f not in skip]
    if os.path.isfile(os.path.join(dest, V2, "README.md")):
        kept.append(f"{V2}/README.md")   # a v2 ledger's version line
    problems, texts = [], {}
    for f in kept:
        try:
            with open(os.path.join(dest, f), encoding="utf-8", errors="replace") as fh:
                texts[f] = fh.read()
        except OSError as e:
            problems.append(f"{f}: cannot read: {e}")
            continue
        why = LB.version_problem(texts[f])
        if why:
            problems.append(f"{f}: {why}")
    if not adopt or problems:
        return problems

    def lineno(text, m):
        return text.count("\n", 0, m.start()) + 1

    def uncommented(text):   # comments blanked, line numbers kept
        return LB.COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)

    def check(label, *ledger_args):
        r = subprocess.run([sys.executable, os.path.join(scripts, "ledger.py"), "--check", "--json", *ledger_args],
                           capture_output=True, text=True, cwd=dest, check=False, stdin=subprocess.DEVNULL,
                           env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        try:
            return [f"{label}: ledger.py --check: {x['text']}" for x in json.loads(r.stdout)["flags"] if x["level"] == "error"]
        except (ValueError, KeyError, TypeError):
            return [f"{label}: ledger.py --check did not run (exit {r.returncode}): {(r.stderr.strip() or r.stdout.strip())[:300]}"]

    for f in (LEDGER, ARCHIVE):
        if f in texts:
            t = uncommented(texts[f])
            for rx, what in ((SKIP_HEAD, "a heading the readers skip — an entry is `## TD-NNN: title`"),
                             (SKIP_ITEM, "a list item the readers skip — an entry is a `## TD-NNN: title` body")):
                problems += [f"{f}:{lineno(t, m)}: {what}" for m in rx.finditer(t)]
    if LEDGER in texts:
        bodies = LB.heading_nums(texts[LEDGER])
        problems += [f"{LEDGER}: summary row {r['id']} has no `## {r['id']}:` body — the readers never see it"
                     for r in LB.rows(texts[LEDGER]) if LB._num(r["id"]) not in bodies]
        if not bodies and not LB.rows(texts[LEDGER]):   # no TD ids at all: entries in a shape of its own?
            t = uncommented(texts[LEDGER])
            problems += [f"{LEDGER}:{lineno(t, m)}: a ledger with no `## TD-NNN:` entry holds this — the readers skip it"
                         for m in NO_ID_SHAPE.finditer(t)]
        problems += check(LEDGER, "--ledger", os.path.join(dest, LEDGER), "--archive", os.path.join(dest, ARCHIVE))
    # the readers take any docs/ledger/ directory as the ledger (ledger_at()), README or not, and
    # before a v1 file beside it — so the directory is checked whenever there is one
    if os.path.isdir(os.path.join(dest, V2)):
        problems += check(f"{V2}/", "--ledger", os.path.join(dest, V2))
    if BOARD in texts:
        t = uncommented(texts[BOARD])
        problems += [f"{BOARD}:{lineno(t, m)}: a list line the readers skip — an item is `- [ ] …`"
                     for m in SKIP_BOARD.finditer(t)]
    return problems


def w_adopt(args):
    """Adopt a repo to a pin: the seeds (with the skill pointers, *Decision* 5), the pin, the hook shims
    and the roster line. A NEW repo, from `agent-cadence -C <clone> adopt <repo>`; a synced one only through
    `sync.sh --pin <repo>` (`adopt --migrate`), the migration's last sync (*Decision* 11), which first
    retires the synced copies and the lock."""
    import subprocess
    migrate = args[:1] == ["--migrate"]
    if migrate:
        args = args[1:]
    moved = migrate and "--siblings-moved" in args
    if moved:
        args = [a for a in args if a != "--siblings-moved"]
    if len(args) != 1 or args[0].startswith("-"):
        return fail("adopt takes the repo to adopt: agent-cadence -C <an agent-cadence clone> adopt <repo>")
    word = "sync.sh --pin" if migrate else "adopt"
    # the source: this tree, as a clean checkout whose HEAD is on origin's default branch — never a
    # commit that exists only here (a pin the source cannot serve resolves nowhere else)
    rc, top = _git("-C", TREE, "rev-parse", "--show-toplevel")
    if rc != 0 or os.path.realpath(top) != os.path.realpath(TREE):
        return fail(f"{word} runs from an agent-cadence clone, and {TREE} is not one (a cached tree has no "
                    "origin to pin): agent-cadence -C <an agent-cadence clone> adopt <repo>")
    rc, dirty = _git("-C", TREE, "status", "--porcelain", "--untracked-files=no")
    if rc != 0 or dirty:
        return fail(f"{TREE} has uncommitted changes: a pin names a commit, so {word} from a clean checkout")
    _, ref = _git("-C", TREE, "rev-parse", "HEAD")
    rc, source = _git("-C", TREE, "remote", "get-url", "origin")
    if rc != 0 or not source:
        return fail(f"{TREE} has no origin remote to pin as the source")
    if not SOURCE_RE.fullmatch(source):
        return fail(f"origin {source!r} is not a git URL or an absolute path, so a pin could not name it")
    # user:secret@ under any scheme, and any userinfo at all over http(s) — a bare token@ is a credential
    # there, where ssh://git@ is not
    if re.match(r"[A-Za-z][A-Za-z0-9+.-]*://[^/]*:[^/]*@", source) or re.match(r"(?i)https?://[^/]*@", source):
        return fail("origin's URL carries a credential (user:secret@ or token@): a pin is committed, so set origin "
                    "to a URL without one first")
    rc, head = _git("-C", TREE, "symbolic-ref", "-q", "refs/remotes/origin/HEAD")
    if rc != 0 or not head:
        return fail(f"{TREE} does not know origin's default branch: run `git -C {TREE} remote set-head origin -a`")
    if _git("-C", TREE, "merge-base", "--is-ancestor", ref, head)[0] != 0:
        return fail(f"HEAD {ref} is not on origin's default branch ({head.rsplit('/', 1)[-1]}, as last fetched): "
                    "push and merge it, or check out a commit it has — a pin names a commit the source serves")
    rc, tag = _git("-C", TREE, "describe", "--tags", "--exact-match", ref)
    tag = tag if rc == 0 else ""
    sync_files, seed_files = _sh_array("SYNC_FILES"), _sh_array("SEED_FILES")
    if not sync_files or not seed_files:
        return fail(f"cannot read SYNC_FILES and SEED_FILES from {os.path.join(TREE, 'sync.sh')}")
    pointers = [f for f in sync_files if POINTER_RE.fullmatch(f)]
    # the target: adopt writes a new repo's main checkout, where the hooks read the pin (*Decision* 4);
    # the migration writes the checkout it is given — a worktree on a branch, for the PR — as the retired copy did
    rc, common = _git("-C", args[0], "rev-parse", "--path-format=absolute", "--git-common-dir")
    if rc != 0:
        return fail(f"{args[0]} is not a git checkout")
    if os.path.basename(common) != ".git":
        return fail(f"{common} is not a checkout's .git directory (a bare repo, a submodule or a "
                    "separate git dir): nothing to adopt into")
    root = os.path.realpath(os.path.dirname(common))
    dest = root
    if migrate:
        dest = os.path.realpath(_git("-C", args[0], "rev-parse", "--show-toplevel")[1])
    if root == os.path.realpath(TREE) or os.path.isfile(os.path.join(root, "launcher", "words.py")):
        return fail(f"{root} is an agent-cadence clone: agent-cadence's own repo has no pin and runs from its tree")
    lock = os.path.join(dest, "docs", "cadence-sync.lock")
    if migrate:
        if not os.path.isfile(lock):
            return fail(f"{dest} has no docs/cadence-sync.lock: it is not a synced repo — adopt a new repo "
                        "with `agent-cadence -C <clone> adopt <repo>`")
        rc, dirty = _git("-C", dest, "status", "--porcelain", "--untracked-files=no")
        if rc != 0 or dirty:
            return fail(f"{dest} has uncommitted changes: the migration is one reviewable change, so start it "
                        f"from a clean checkout (a run that stopped part-way is undone by `git -C {dest} checkout -- .`)")
        # TD-147: a constellation's home — its siblings' SessionStart hooks run the home's scripts/,
        # which this run removes; they move first, in their own PRs (cadence.md §9.12)
        callers = _home_siblings(dest, root)
        if callers and not moved:
            return fail(f"{dest} is a constellation's home (docs/nested-repos.txt), and its siblings run its "
                        "scripts/, which the migration removes:\n"
                        + "".join(f"    {c}\n" for c in callers)
                        + "  move each sibling's SessionStart off the home's scripts/ first, in that sibling's own PR "
                        "(cadence.md §9.12), then rerun with --siblings-moved — nothing changed")
        for c in callers:
            print(f"  WARN  {c} — --siblings-moved given: that sibling's session start breaks until its PR lands")
    toml_path = os.path.join(dest, "docs", "cadence.toml")
    pinned = False
    if os.path.lexists(toml_path):
        try:
            import tomllib
            with open(toml_path, "rb") as f:
                raw = f.read()
            pinned = "agent-cadence" in tomllib.loads(raw.decode("utf-8"))
        except (OSError, ValueError) as e:
            return fail(f"cannot read {toml_path}: {e} — fix it, then {word}")
        # a pin the shims and the SessionStart line cannot see (they grep for this header) would
        # leave every hook running a copy this repo does not have
        if pinned and not PIN_HEADER_RE.search(raw.decode("utf-8")):
            return fail(f"{toml_path} pins agent-cadence in another TOML form (a dotted key, an inline table, "
                        f"[ agent-cadence ]): write it under a header exactly `[agent-cadence]`, which the hooks "
                        f"detect, then {word}")
    if not migrate:
        carried = [f for f in [*sync_files, "docs/cadence-sync.lock"]
                   if f not in pointers and os.path.lexists(os.path.join(root, f))]
        if carried and pinned and "docs/cadence-sync.lock" not in carried:
            # a migrated repo whose edited copies were kept for a person to port: not a synced repo
            print(f"  WARN  {len(carried)} synced path(s) still here ({', '.join(carried[:3])}) — edited copies "
                  "kept by the migration: port each and delete it")
        elif carried:
            return fail(f"{root} carries synced copies ({', '.join(carried[:3])}{', …' if len(carried) > 3 else ''}): "
                        "moving a synced repo to a pin is the migration, `sync.sh --pin <repo>` — adopt is "
                        "for a new repo")
    # the repo's opt-outs (TD-072, TD-096), read by the tree's own helper
    p = subprocess.run([sys.executable, os.path.join(PAYLOAD, "scripts", "cadence_config.py"), "opt-outs",
                        "--repo", dest], capture_output=True, text=True, check=False, stdin=subprocess.DEVNULL)
    if p.returncode != 0:
        return fail(f"the opt-outs in {toml_path} could not be read: {(p.stderr or p.stdout).strip()}")
    skip_seed, skip_hooks = {}, []
    for line in p.stdout.splitlines():
        kind, val, why, src, _ = (line.split("\x1f") + [""] * 5)[:5]
        if kind == "warn":
            print(f"  WARN  {val}")
        elif kind == "skip-seed" and val in seed_files and val != "docs/cadence.toml":
            skip_seed[val] = f"skip-seed: {why or 'no ADR named'} — {src}"
        elif kind == "not-adopted" and val.lstrip("§") == "4":
            skip_hooks.append("pre-push")   # §4's teeth: its only opt-out
    # TD-168: the repo's own ledger and board, read by the pinned readers before anything is written
    problems = _format_problems(dest, not migrate, skip_seed)
    if problems:
        return fail(f"{word} refuses {dest}: " + ("its own ledger or board does not read as the format (ledgerboard "
                    "SPEC.md), and adopt keeps them as they are:" if not migrate else
                    "a ledger or board it keeps declares a format the pinned scripts cannot read:")
                    + "".join(f"\n    {p}" for p in problems)
                    + "\n  convert or fix them (the list above is where to start), then run it again — nothing was written")
    print(("migrating" if migrate else "adopting") + f" {dest}: agent-cadence {source} at {ref}" + (f" ({tag})" if tag else ""))
    # every seed's body read before anything is removed, so a commit missing one fails here, not
    # half-way through a migration
    bodies = {}
    for f in [*seed_files, *pointers]:
        if f in skip_seed:
            continue
        rc, body = _git_bytes("-C", TREE, "show", f"{ref}:files/{f}")
        if rc != 0:
            return fail(f"files/{f} is not in {ref}: {body.decode(errors='replace').strip()}")
        bodies[f] = body
    # the pin, built and read back before anything is removed: appended as the file's last table, the
    # header written exactly [agent-cadence] — the one form the shims and the SessionStart line detect
    if not pinned:
        import tomllib
        if os.path.lexists(toml_path):
            with open(toml_path, encoding="utf-8", newline="") as f:
                before = f.read()
        else:
            before = bodies.get("docs/cadence.toml", b"").decode("utf-8")   # seeded below, then pinned
        block = ("\n# The agent-cadence this repo runs (TD-129): `source` is never moved by a bump, and `ref` is a\n"
                 f"# full commit, moved by `agent-cadence bump` in a reviewed PR. Written by `{word}`.\n"
                 f'[agent-cadence]\nsource = "{source}"\nref = "{ref}"' + (f"   # {tag}" if tag else "") + "\n")
        after = before + ("" if not before or before.endswith("\n") else "\n") + block
        try:
            readback = tomllib.loads(after) == dict(tomllib.loads(before), **{"agent-cadence": {"source": source, "ref": ref}})
        except ValueError:
            readback = False
        if not readback:
            return fail(f"{toml_path}: the pin would not read back as written (origin {source!r}) — nothing "
                        "changed; add it by hand")
    kept = _retire(dest, lock) if migrate else []
    for f in [*seed_files, *pointers]:
        dst = os.path.join(dest, f)
        if f in skip_seed:
            print(f"  skip  {f} ({skip_seed[f]}; never created)")
        elif f in V1_LEDGER and not os.path.lexists(dst) and os.path.isdir(os.path.join(dest, "docs", "ledger")):
            print(f"  skip  {f} (the ledger is docs/ledger/, a directory: never created)")   # TD-160, as the retired copy did
        elif os.path.lexists(dst):
            print(f"  keep  {f} (exists — never overwritten)")
        else:
            # from the pinned commit, never the clone's work tree (an untracked or ignored file there
            # is no part of what the repo pins); a skill pointer loses its synced-file header, since
            # in a pinned repo it is the repo's own (SEED)
            body = bodies[f]
            if f in pointers:
                body = SYNCED_HEADER_RE.sub("\n", body.decode("utf-8"), count=1).encode("utf-8")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as out:
                out.write(body)
            print(f"  seed  {f}")
    # the pin, checked above, replaces the file in one rename
    if pinned:
        print(f"  keep  {toml_path}: it already has a [agent-cadence] pin — left as it is (move it with `agent-cadence bump`)")
    else:
        now = ""
        if os.path.lexists(toml_path):
            with open(toml_path, encoding="utf-8", newline="") as f:
                now = f.read()
        if now != before:
                return fail(f"{toml_path} changed during the run — add the pin by hand")
        tmp = f"{toml_path}.adopt-{os.getpid()}"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(after)
        os.replace(tmp, toml_path)
        print(f"  pin   [agent-cadence] ref = {ref}" + (f" ({tag})" if tag else "") + " (docs/cadence.toml)")
    if not migrate:
        _gitignore(dest)   # a synced repo's were written by its first sync
    # the TD-055 shims, by the tree's own installer. Pinned, each runs `agent-cadence hook`; until the
    # main checkout pins (a migration's PR not yet merged) each runs the main checkout's copy, which a
    # consumer keeps in scripts/git-hooks — so that is the layout the shims name, wherever this tree is
    env = dict(os.environ, CADENCE_HOOKS_SKIP=" ".join(skip_hooks), CADENCE_HOOKS_REL="scripts/git-hooks")
    sys.stdout.flush()   # the installer writes to the same stdout: keep the lines in order
    hooks = subprocess.run(["bash", os.path.join(PAYLOAD, "scripts", "install_git_hooks.sh"), root],
                           env=env, check=False, stdin=subprocess.DEVNULL)
    if hooks.returncode != 0:
        print(f"  WARN  the git hook shims were not installed (above) — rerun {word} once that is fixed")
    seed_line = b""
    if migrate:
        seed_line, said = _session_line(dest, ref)
        seed_line = seed_line.encode("utf-8")
        if said:
            print(said)
    _register(root)   # the last mutating step
    if migrate:
        # Decision 11: the repo's own files that name a retired path move in this same change
        rc, files = _git_bytes("-C", dest, "ls-files", "-z")
        named = []
        for f in (files.decode("utf-8", "surrogateescape").split("\0") if rc == 0 else []):
            if not f or f in kept:   # an edited synced copy: ported and deleted, never moved
                continue
            path = os.path.join(dest, f)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as fh:
                    head = fh.read(1 << 20)   # a large or binary file is not a script's caller
            except OSError:
                continue
            if f == ".claude/settings.json" and seed_line:
                head = head.replace(seed_line, b"")   # the seed's own line, which runs the pin first
            # after any path segment too: `$CLAUDE_PROJECT_DIR/scripts/`, `${r:-…}/scripts/` (TD-149)
            if b"\0" not in head and re.search(rb"(?:^|[\s`'\"(=:/])scripts/", head, re.M):
                named.append(f)
        if named:
            print(f"\n  these files name scripts/, which the pinned repo no longer has — move each to "
                  f"`agent-cadence run <script>` in this change ({len(named)}):")
            for f in named[:40]:
                print(f"    {f}")
            if len(named) > 40:
                print(f"    … and {len(named) - 40} more (git -C \"{dest}\" grep -l scripts/)")
        if kept:
            print(f"\n  {len(kept)} edited copy(ies) kept (above): port each and delete it before the PR")
    warns = _seed_warnings(dest, bodies, skip_seed, migrate)
    if warns:
        print("\n" + "\n".join(warns))
    # TD-187 (cadence.md §7.14): text is LF. adopt converts nothing; it says what the repo does once
    if ".gitattributes" in seed_files and ".gitattributes" not in skip_seed:
        try:
            with open(os.path.join(dest, ".gitattributes"), "rb") as fh:
                attrs = fh.read()
        except OSError:
            attrs = b""
        if not re.search(rb"^\*[ \t]+(?:\S+[ \t]+)*eol=lf\b", attrs, re.M):
            print("\n  the repo's own .gitattributes has no `* text=auto eol=lf` line: add it by hand (cadence.md §7.14)")
        rc, eol = _git_bytes("-C", dest, "ls-files", "--eol")
        crlf = sum(1 for line in eol.splitlines() if line.startswith((b"i/crlf", b"i/mixed"))) if rc == 0 else 0
        if crlf:
            print(f"\n  {crlf} file(s) are CRLF in the index: convert them once, in a PR of their own — "
                  f"git -C \"{dest}\" add --renormalize . (cadence.md §7.14)")
    print(f"""
Next, in {dest}:
  1. git -C "{dest}" diff and git status — nothing is committed; branch, commit, PR (a migration's
     PR also carries the moves listed above)
  2. install the launcher on every machine that works this repo (once per machine):
     {INSTALL_LINE}""" + ("" if migrate else """
  3. the per-clone steps adopt does not do (cadence.md Adoption checklist, TD-168):
     autoMemoryDirectory, and the repo settings (squash-only, auto-delete heads)"""))
    return 0

WORDS = {"words": w_words, "run": w_run, "path": w_path, "hook": w_hook, "gc": w_gc, "bump": w_bump,
         "adopt": w_adopt}


def main(argv):
    if not argv or argv[0] not in WORDS:
        word = argv[0] if argv else ""
        return fail(f"unknown word {word!r} — the words: {', '.join(WORDS)}")
    return WORDS[argv[0]](argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
