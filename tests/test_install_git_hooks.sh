#!/usr/bin/env bash
# install_git_hooks.sh (TD-055): the git hooks run in EVERY worktree of a clone, from the
# main checkout, whatever branch the worktree is on. The cases that motivated it are real
# pushes into a bare remote, asserting what the remote holds afterwards (as test_pre_push
# does): a worktree on a branch without scripts/git-hooks/, and one on a branch whose
# pre-push was edited to let everything through — both used to push main unguarded.
#
# Isolation: HOME, XDG_CONFIG_HOME, DEV_CADENCE_REG_DIR and the global/system git config
# point into the tmpdir, so nothing here touches the machine roster and a
# machine's own core.hooksPath cannot leak in.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" \
       GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$DEV_CADENCE_REG_DIR"
unset ALLOW_MAIN_PUSH
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# A consumer-layout clone: main carries scripts/ (installer + hooks); branch `old` forks
# before them, as a pre-adoption branch does.
mkclone() {  # $1 dir
    local c="$1"
    git init -q --bare -b main "$c.git"; git clone -q "$c.git" "$c" 2>/dev/null
    git -C "$c" config user.email t@t; git -C "$c" config user.name t
    git -C "$c" checkout -q -b main 2>/dev/null
    git -C "$c" commit -q --allow-empty -m root
    git -C "$c" branch old
    mkdir -p "$c/scripts/git-hooks"
    cp "$DC/files/scripts/install_git_hooks.sh" "$c/scripts/"
    cp "$DC/files/scripts/git-hooks/pre-push" "$DC/files/scripts/git-hooks/post-merge" "$c/scripts/git-hooks/"
    git -C "$c" add -A; git -C "$c" commit -qm hooks
    git -C "$c" push -q origin main old 2>/dev/null
}
remote() { git -C "$1.git" rev-parse -q --verify "refs/heads/$2" 2>/dev/null; }
blocked() {  # $1 label, $2 clone, $3 worktree dir, rest: push args
    local label="$1" c="$2" w="$3" before out rc; shift 3
    before=$(remote "$c" main)
    out=$(git -C "$w" push "$@" 2>&1); rc=$?
    if [ $rc -ne 0 ] && [ "$(remote "$c" main)" = "$before" ] && grep -q "pre-push: BLOCKED" <<< "$out"; then
        ok "$label"
    else
        bad "$label: rc=$rc main ${before:-absent} -> $(remote "$c" main || echo absent)
$out"
    fi
}

# --- 1) the old way (relative hooksPath) is replaced: shims in, hooksPath unset
C="$TMP/c1"; mkclone "$C"
git -C "$C" config core.hooksPath scripts/git-hooks
out=$(bash "$C/scripts/install_git_hooks.sh" "$C" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -qF "dev-cadence hook shim (TD-055)" "$C/.git/hooks/pre-push" && [ -x "$C/.git/hooks/pre-push" ] \
  && [ -x "$C/.git/hooks/post-merge" ] && [ -z "$(git -C "$C" config core.hooksPath)" ] && grep -q "core.hooksPath (scripts/git-hooks) unset" <<< "$out" \
  && ok "install: shims for pre-push and post-merge, the relative hooksPath unset" || bad "install rc=$rc: $out"
out=$(bash "$C/scripts/install_git_hooks.sh" "$C" 2>&1)
grep -q "pre-push: shim already in place" <<< "$out" && ! grep -q "WARN" <<< "$out" \
  && ok "install: a rerun is a no-op" || bad "rerun: $out"
out=$(cd "$C" && bash scripts/install_git_hooks.sh 2>&1); [ $? -eq 0 ] && grep -q "already in place" <<< "$out" \
  && ok "install: REPO defaults to the current directory" || bad "default repo: $out"

# --- 2) the TD-055 reproduction: a worktree on a branch WITHOUT scripts/git-hooks
git -C "$C" worktree add -q "$TMP/c1-old" old
[ ! -e "$TMP/c1-old/scripts" ] || bad "fixture: branch old should predate scripts/"
git -C "$TMP/c1-old" commit -q --allow-empty -m direct
# old is behind main, so only a force push gets past git's own fast-forward check to the hook
blocked "a worktree on a hook-less branch cannot force-push HEAD:main" "$C" "$TMP/c1-old" --force origin HEAD:main

# --- 3) a branch that EDITS its pre-push runs the main checkout's copy, not its edit
git -C "$C" worktree add -q -b loose "$TMP/c1-loose" main
printf '#!/bin/sh\nexit 0\n' > "$TMP/c1-loose/scripts/git-hooks/pre-push"
git -C "$TMP/c1-loose" commit -qam "loosen the guard"
blocked "a branch that edits pre-push still gets the main checkout's guard" "$C" "$TMP/c1-loose" origin HEAD:main
out=$(git -C "$TMP/c1-loose" push -q origin HEAD:refs/heads/loose 2>&1); rc=$?
[ $rc -eq 0 ] && [ -n "$(remote "$C" loose)" ] && ok "a topic-branch push still goes through the shim" || bad "topic push rc=$rc: $out"

# --- 4) the main checkout's hook gone: the shim says so and does not block
mv "$C/scripts/git-hooks/pre-push" "$TMP/pp.aside"
out=$(git -C "$TMP/c1-loose" push origin HEAD:refs/heads/loose2 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "git hook shim: .*scripts/git-hooks/pre-push is missing" <<< "$out" \
  && ok "shim: a missing main-checkout hook is named, not silent" || bad "missing hook rc=$rc: $out"
mv "$TMP/pp.aside" "$C/scripts/git-hooks/pre-push"

# --- 5) a hook of the clone's own in .git/hooks is kept, and the old hooksPath with it
C="$TMP/c2"; mkclone "$C"
git -C "$C" config core.hooksPath scripts/git-hooks
printf '#!/bin/sh\necho mine\n' > "$C/.git/hooks/pre-push"; chmod +x "$C/.git/hooks/pre-push"
out=$(bash "$C/scripts/install_git_hooks.sh" "$C" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "echo mine" "$C/.git/hooks/pre-push" && grep -q "is a hook of this clone's own — kept" <<< "$out" \
  && [ "$(git -C "$C" config core.hooksPath)" = scripts/git-hooks ] && grep -q "left set" <<< "$out" \
  && grep -qF "dev-cadence hook shim" "$C/.git/hooks/post-merge" \
  && ok "never clobbers: an own pre-push kept, hooksPath left set, post-merge still shimmed" || bad "own hook rc=$rc: $out"

# --- 6) a hooksPath of the clone's own (.husky) is left alone
C="$TMP/c3"; mkclone "$C"
git -C "$C" config core.hooksPath .husky
out=$(bash "$C/scripts/install_git_hooks.sh" "$C" 2>&1)
[ "$(git -C "$C" config core.hooksPath)" = .husky ] && grep -q "WARN  core.hooksPath is '.husky'" <<< "$out" \
  && ok "a foreign hooksPath is left alone and named" || bad "husky: $out"

# --- 7) nothing to install into: a bare repo, a non-repo
out=$(bash "$DC/files/scripts/install_git_hooks.sh" "$TMP/c3.git" 2>&1); rc=$?
[ $rc -eq 2 ] && grep -q "not a checkout's .git directory" <<< "$out" && ok "bare repo: exit 2, nothing written" || bad "bare rc=$rc: $out"
mkdir -p "$TMP/plain"; out=$(bash "$DC/files/scripts/install_git_hooks.sh" "$TMP/plain" 2>&1); rc=$?
[ $rc -eq 2 ] && ok "not a clone: exit 2" || bad "plain rc=$rc: $out"

# --- 7b) run through a symlink: it follows the link to the hooks, never a silent no-op
C="$TMP/c4"; mkclone "$C"; mkdir -p "$TMP/bin"; ln -s "$C/scripts/install_git_hooks.sh" "$TMP/bin/install_git_hooks.sh"
out=$(cd "$TMP" && bash "$TMP/bin/install_git_hooks.sh" "$C" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -qF 'scripts/git-hooks/${0##*/}"' "$C/.git/hooks/pre-push" && ok "symlinked installer: shims installed" || bad "symlink rc=$rc: $out"
cp "$DC/files/scripts/install_git_hooks.sh" "$TMP/bin/lonely.sh"
out=$(bash "$TMP/bin/lonely.sh" "$C" 2>&1); rc=$?
[ $rc -eq 2 ] && grep -q "no hooks found" <<< "$out" && ok "no hooks beside the installer: exit 2 and says so" || bad "lonely rc=$rc: $out"

# --- 8) dev-cadence's own layout: hooks under files/scripts/git-hooks
C="$TMP/dc"; git init -q -b main "$C"; mkdir -p "$C/files/scripts/git-hooks"
cp "$DC/files/scripts/install_git_hooks.sh" "$C/files/scripts/"; cp "$DC/files/scripts/git-hooks/pre-push" "$C/files/scripts/git-hooks/"
git -C "$C" config core.hooksPath files/scripts/git-hooks
out=$(bash "$C/files/scripts/install_git_hooks.sh" "$C" 2>&1)
grep -qF '/files/scripts/git-hooks/${0##*/}"' "$C/.git/hooks/pre-push" && [ -z "$(git -C "$C" config core.hooksPath)" ] \
  && ok "files/ layout: the shim runs files/scripts/git-hooks, hooksPath unset" || bad "files layout: $out"

# --- 10) TD-129: the dual mode. A [dev-cadence] pin in the MAIN checkout's docs/cadence.toml runs
# `dev-cadence hook <name>` (a stub launcher here, offline) and never the copy; a launcher exit 2
# fails open with a warning, any other exit is the hook's own; no launcher prints the install line.
# The pre-push shim's inline main guard holds in every mode: launcher absent, broken (exit 2) or
# letting everything through, and the copy missing.
NOLAUNCH=$(printf '%s\n' "${PATH//:/$'\n'}" | while read -r d; do [ -n "$d" ] && [ ! -e "$d/dev-cadence" ] && echo "$d"; done | paste -sd: -)
mkdir -p "$TMP/lbin"
stub_launcher() {  # $1 exit code: records its args, cwd and stdin, never runs a hook
    printf '#!/usr/bin/env bash\n{ echo "args:$*"; echo "cwd:$PWD"; echo "stdin:$(cat)"; } >> "%s/launched"\nexit %s\n' "$TMP" "$1" > "$TMP/lbin/dev-cadence"
    chmod +x "$TMP/lbin/dev-cadence"; : > "$TMP/launched"
}
C="$TMP/pin"; mkclone "$C"
cp "$DC/files/scripts/git-hooks/prepare-commit-msg" "$C/scripts/git-hooks/"
bash "$C/scripts/install_git_hooks.sh" "$C" >/dev/null 2>&1
mkdir -p "$C/docs"; printf '# settings\n[dev-cadence]  # pinned\nsource = "/x"\nref = "%040d"\n' 0 > "$C/docs/cadence.toml"
git -C "$C" worktree add -q -b topic "$TMP/pin-w" main
# the copy announces itself if it ever runs, so a pinned shim that falls back to it shows
printf '#!/usr/bin/env bash\necho COPY-RAN >> "%s/launched"\ncat >/dev/null\nexit 0\n' "$TMP" > "$C/scripts/git-hooks/pre-push"
git -C "$TMP/pin-w" commit -q --allow-empty -m w
stub_launcher 0
out=$(PATH="$TMP/lbin:$NOLAUNCH" git -C "$TMP/pin-w" push origin HEAD:refs/heads/topic 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "^args:hook pre-push origin $C.git$" "$TMP/launched" && grep -q "^cwd:$TMP/pin-w$" "$TMP/launched" \
  && grep -q "^stdin:HEAD [0-9a-f]* refs/heads/topic [0-9a-f]*$" "$TMP/launched" && ! grep -q COPY-RAN "$TMP/launched" \
  && ok "pinned: the shim runs dev-cadence hook pre-push from the worktree, refs on stdin, never the copy" || bad "pinned launch rc=$rc: $out $(cat "$TMP/launched")"
: > "$TMP/launched"
PATH="$TMP/lbin:$NOLAUNCH" git -C "$TMP/pin-w" commit -q --allow-empty -m w2 2>/dev/null
grep -q "^args:hook prepare-commit-msg .*COMMIT_EDITMSG" "$TMP/launched" && grep -q "^stdin:$" "$TMP/launched" \
  && ok "pinned: another hook gets its own name and args through the launcher" || bad "prepare-commit-msg: $(cat "$TMP/launched")"
stub_launcher 1
out=$(PATH="$TMP/lbin:$NOLAUNCH" git -C "$TMP/pin-w" push origin HEAD:refs/heads/topic2 2>&1); rc=$?
[ $rc -ne 0 ] && [ -z "$(remote "$C" topic2)" ] && ok "pinned: the hook's own refusal (exit 1) is kept" || bad "hook exit 1 rc=$rc: $out"
stub_launcher 2
out=$(PATH="$TMP/lbin:$NOLAUNCH" git -C "$TMP/pin-w" push origin HEAD:refs/heads/topic3 2>&1); rc=$?
[ $rc -eq 0 ] && [ -n "$(remote "$C" topic3)" ] && grep -q "could not run this repo's pin" <<< "$out" \
  && ok "pinned: a launcher exit 2 fails open, with a warning" || bad "launcher exit 2 rc=$rc: $out"
PATH="$TMP/lbin:$NOLAUNCH" blocked "pinned, launcher exit 2: main is still guarded" "$C" "$TMP/pin-w" origin HEAD:main
stub_launcher 0
PATH="$TMP/lbin:$NOLAUNCH" blocked "pinned, a launcher that lets everything through: main is still guarded" "$C" "$TMP/pin-w" origin HEAD:main
: > "$TMP/launched"
out=$(PATH="$NOLAUNCH" git -C "$TMP/pin-w" push origin HEAD:refs/heads/topic4 2>&1); rc=$?
[ $rc -eq 0 ] && [ -n "$(remote "$C" topic4)" ] && grep -q "no dev-cadence launcher is on PATH .*install -m 755 launcher/dev_cadence.py" <<< "$out" \
  && ! grep -q COPY-RAN "$TMP/launched" && ok "pinned, no launcher: the install line, fail open, never the copy" || bad "no launcher rc=$rc: $out"
PATH="$NOLAUNCH" blocked "pinned, no launcher: main is still guarded" "$C" "$TMP/pin-w" origin HEAD:main
out=$(PATH="$NOLAUNCH" ALLOW_MAIN_PUSH=1 git -C "$TMP/pin-w" push origin HEAD:main 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(remote "$C" main)" = "$(git -C "$TMP/pin-w" rev-parse HEAD)" ] && ok "pinned, no launcher: ALLOW_MAIN_PUSH=1 still overrides the inline guard" || bad "override rc=$rc: $out"
# no pin, the copy gone: the inline guard still holds main (it used to fail open entirely)
rm "$C/docs/cadence.toml"; mv "$C/scripts/git-hooks/pre-push" "$TMP/pp.aside"
git -C "$TMP/pin-w" commit -q --allow-empty -m w3
PATH="$NOLAUNCH" blocked "no pin, the copy missing: main is still guarded" "$C" "$TMP/pin-w" --force origin HEAD:main
mv "$TMP/pp.aside" "$C/scripts/git-hooks/pre-push"
# a [dev-cadence] that is not a table header (a comment, a key) is no pin
printf '# [dev-cadence]\nx = "[dev-cadence]"\n' > "$C/docs/cadence.toml"; : > "$TMP/launched"
PATH="$TMP/lbin:$NOLAUNCH" git -C "$TMP/pin-w" push -q origin HEAD:refs/heads/topic5 2>/dev/null
grep -q COPY-RAN "$TMP/launched" && ! grep -q "^args:" "$TMP/launched" && ok "no table header, no pin: the copy runs, not the launcher" || bad "near-miss pin: $(cat "$TMP/launched")"
# the default branch is the §9 rule's, taken verbatim from pre-push: a trunk repo guards trunk
T="$TMP/trunk"; git init -q --bare -b trunk "$T.git"; git clone -q "$T.git" "$T" 2>/dev/null
git -C "$T" config user.email t@t; git -C "$T" config user.name t; git -C "$T" checkout -q -b trunk 2>/dev/null
mkdir -p "$T/scripts/git-hooks" "$T/docs"; cp "$DC/files/scripts/install_git_hooks.sh" "$T/scripts/"; cp "$DC/files/scripts/git-hooks/pre-push" "$T/scripts/git-hooks/"
git -C "$T" add -A; git -C "$T" commit -qm base; git -C "$T" push -q origin trunk 2>/dev/null; git -C "$T" remote set-head origin -a >/dev/null 2>&1
bash "$T/scripts/install_git_hooks.sh" "$T" >/dev/null 2>&1
printf '[dev-cadence]\nsource = "/x"\nref = "%040d"\n' 0 > "$T/docs/cadence.toml"; git -C "$T" commit -q --allow-empty -m d
before=$(remote "$T" trunk); out=$(PATH="$NOLAUNCH" git -C "$T" push origin HEAD:trunk 2>&1); rc=$?
[ $rc -ne 0 ] && [ "$(remote "$T" trunk)" = "$before" ] && grep -q "BLOCKED — direct push to trunk" <<< "$out" \
  && ok "pinned, no launcher, a trunk repo: the inline guard blocks trunk (the §9 rule)" || bad "trunk rc=$rc: $out"

# a pre-push with no default_branch() (an old or a hand-made one): the shim still guards main, and says so
C="$TMP/nofn"; mkclone "$C"; printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$C/scripts/git-hooks/pre-push"
out=$(bash "$C/scripts/install_git_hooks.sh" "$C" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "inline guard holds main only" <<< "$out" && ok "a pre-push with no default_branch(): installed, said" || bad "nofn rc=$rc: $out"
git -C "$C" commit -q --allow-empty -m x
blocked "a pre-push with no default_branch(): main is still guarded" "$C" "$C" origin HEAD:main

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
