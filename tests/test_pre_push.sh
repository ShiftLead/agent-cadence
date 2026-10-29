#!/usr/bin/env bash
# pre-push — the one GATE the system ships (cadence §4 "give the rule teeth"), and the
# thing both main-push carve-outs lean on. Every case is a real `git push` through
# core.hooksPath into a bare remote, and asserts what the remote holds afterwards, not
# just the exit code: a hook that exits 1 after git already sent the ref would pass an
# rc-only test.
#
# Isolation: HOME, XDG_CONFIG_HOME and the global/system git config are all pointed away,
# so a machine's own init.templateDir or core.hooksPath cannot leak in (TD-046).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$DC/files/scripts/git-hooks/pre-push"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
unset ALLOW_MAIN_PUSH
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

O="$TMP/origin.git"; C="$TMP/clone"
git init -q --bare -b main "$O"
git clone -q "$O" "$C" 2>/dev/null
cd "$C" || exit 1
git config user.email t@t; git config user.name t
git checkout -q -b main 2>/dev/null
mkdir -p scripts/git-hooks && cp "$HOOK" scripts/git-hooks/ && chmod +x scripts/git-hooks/pre-push
git add . && git commit -qm base
git push -q origin main 2>/dev/null   # seed the remote BEFORE the guard is on
git config core.hooksPath scripts/git-hooks

remote() { git -C "$O" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
blocked() { # $1 label, $2 ref that must be unchanged on the remote, rest: push args
    local label="$1" ref="$2" before out rc; shift 2
    before=$(remote "$ref")
    out=$(git push "$@" 2>&1); rc=$?
    if [ $rc -ne 0 ] && [ "$(remote "$ref")" = "$before" ] && grep -q "pre-push: BLOCKED" <<< "$out"; then
        ok "$label"
    else
        bad "$label: rc=$rc remote $ref ${before:-absent} -> $(remote "$ref" || echo absent)
$out"
    fi
}

# --- 1) the plain case: a commit on main, pushed
git commit -q --allow-empty -m direct
blocked "push main -> blocked, remote main unchanged" main origin main

# --- 2) the refspec a session actually types from a worktree branch
git checkout -q -b topic
git commit -q --allow-empty -m topic-work
blocked "push HEAD:main from a topic branch -> blocked" main origin HEAD:main
blocked "push topic:refs/heads/main -> blocked" main origin topic:refs/heads/main

# --- 3) deleting main is a push to main too
blocked "push --delete main -> blocked, main survives" main origin --delete main
blocked "push :main -> blocked" main origin :main

# --- 4) one main ref in a multi-ref push stops the whole push (git's pre-push contract)
git checkout -q -b other; git commit -q --allow-empty -m other; git checkout -q topic
blocked "push other + HEAD:main together -> blocked" main origin other HEAD:main
[ -z "$(remote other)" ] && ok "  ... and the other ref in that push was not sent either" \
    || bad "a multi-ref push sent 'other' although the main ref was blocked"

# --- 5) the override is exactly ALLOW_MAIN_PUSH=1, nothing looser
for v in 0 true yes " 1"; do
    ALLOW_MAIN_PUSH="$v" blocked "ALLOW_MAIN_PUSH='$v' is not the override" main origin HEAD:main
done
before=$(remote main)
out=$(ALLOW_MAIN_PUSH=1 git push origin HEAD:main 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(remote main)" = "$(git rev-parse HEAD)" ] && [ "$(remote main)" != "$before" ] \
    && ok "ALLOW_MAIN_PUSH=1 pushes main" || bad "override: rc=$rc
$out"

# --- 6) everything that is not refs/heads/main passes
out=$(git push -q origin topic 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(remote topic)" = "$(git rev-parse topic)" ] && ok "a topic branch pushes" || bad "topic push: rc=$rc $out"
git checkout -q -b main-backup
out=$(git push -q origin main-backup 2>&1); rc=$?
[ $rc -eq 0 ] && [ -n "$(remote main-backup)" ] && ok "main-backup (a prefix of main) pushes — exact match only" || bad "main-backup: rc=$rc $out"
out=$(git push -q origin HEAD:refs/heads/feature/main 2>&1); rc=$?
[ $rc -eq 0 ] && [ -n "$(remote feature/main)" ] && ok "feature/main (main as a suffix) pushes" || bad "feature/main: rc=$rc $out"
git tag v1
out=$(git push -q origin v1 2>&1); rc=$?
[ $rc -eq 0 ] && git -C "$O" rev-parse -q --verify refs/tags/v1 >/dev/null && ok "a tag pushes" || bad "tag: rc=$rc $out"
out=$(git push -q origin --delete topic 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$(remote topic)" ] && ok "deleting a topic branch pushes" || bad "delete topic: rc=$rc $out"

# --- 7) The gate guards the DEFAULT branch (cadence §9 rule, TD-042) plus main — here the
#     default is main, so a branch that happens to be called `master` is an ordinary branch.
#     A `trunk`/`master` default is guarded: tests/test_default_branch.sh pins that.
out=$(git push -q origin HEAD:master 2>&1); rc=$?
[ $rc -eq 0 ] && ok "a non-default branch named master is not guarded (the default here is main)" \
    || bad "a push to a non-default master was blocked: $out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
