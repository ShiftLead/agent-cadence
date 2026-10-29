#!/usr/bin/env bash
# TD-042: the default-branch rule (cadence.md §9) — the first of origin/HEAD's target,
# init.defaultBranch, main, master that exists on origin; else main. Seven sites carry it
# (four verbatim shell copies, three Python functions); this runs EVERY copy against the
# same fixtures, so a copy that drifts fails here. Then the one gate: real pushes through
# core.hooksPath on a `trunk` repo.
#
# Offline: bare repos under a temp dir. HOME, XDG_CONFIG_HOME and git's global/system
# config point away, so this machine's own init.defaultBranch cannot leak in.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
unset ALLOW_MAIN_PUSH
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SHELL_SITES=(git-hooks/pre-push reap_worktrees.sh open_worktree.sh hydrate_worktree.sh)
fn() { sed -n '/^default_branch() {$/,/^}$/p' "$S/$1"; }

# --- 0) the four shell copies are byte-identical, and no code line hardcodes origin/main
ref=$(fn git-hooks/pre-push)
[ -n "$ref" ] && ok "pre-push carries default_branch()" || bad "pre-push has no default_branch()"
for f in "${SHELL_SITES[@]:1}"; do
    [ "$(fn "$f")" = "$ref" ] && ok "$f: default_branch() is pre-push's, verbatim" || bad "$f: default_branch() drifted from pre-push's"
done
hard=$(grep -n 'origin/main\|refs/heads/main' "$S"/*.sh "$S"/*.py "$S"/git-hooks/* | grep -v ':[0-9]*:\s*#' \
       | grep -v 'refs/heads/main" \] ||' | grep -v 'refs/heads/main\\" \] ||' | grep -v 'e.g. "origin/main"')
[ -z "$hard" ] && ok "no code line under files/scripts/ hardcodes origin/main or refs/heads/main (the gate's own always-main aside)" \
    || bad "hardcoded default branch: $hard"

# --- fixtures: <name> <expected>
mkrepo() {  # mkrepo <dir> <bare default> [branches...] — a clone of a bare origin with a commit on each branch
    local d="$1" def="$2"; shift 2
    git init -q --bare -b "$def" "$d.git"; git clone -q "$d.git" "$d" 2>/dev/null
    git -C "$d" checkout -q -b "$def" 2>/dev/null; git -C "$d" commit -q --allow-empty -m base
    git -C "$d" push -q origin "$def"
    for b in "$@"; do git -C "$d" push -q origin "$def:$b"; done
    git -C "$d" fetch -q origin; git -C "$d" remote set-head origin -a >/dev/null 2>&1
}
F="$TMP/f"; mkdir -p "$F"
mkrepo "$F/trunk" trunk                                                  # origin/HEAD -> trunk
mkrepo "$F/cfg" trunk; git -C "$F/cfg" remote set-head origin -d; git -C "$F/cfg" config init.defaultBranch trunk
mkrepo "$F/master" master; git -C "$F/master" remote set-head origin -d  # nothing but origin/master
mkrepo "$F/cfgdev" main dev; git -C "$F/cfgdev" remote set-head origin -d; git -C "$F/cfgdev" config init.defaultBranch dev
mkrepo "$F/both" main master; git -C "$F/both" remote set-head origin -d  # main before master
git init -q -b work "$F/noorigin"                                        # no origin at all -> main
mkrepo "$F/dangling" master; git -C "$F/dangling" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone  # origin renamed its default
declare -A WANT=([trunk]=trunk [cfg]=trunk [master]=master [cfgdev]=dev [both]=main [noorigin]=main [dangling]=master)

for fx in trunk cfg master cfgdev both noorigin dangling; do
    want=${WANT[$fx]}; got=""
    for f in "${SHELL_SITES[@]}"; do
        g=$(bash -c "$(fn "$f")"$'\n'"default_branch \"\$1\"" _ "$F/$fx" 2>&1)
        [ "$g" = "$want" ] || got="$got $f=$g"
    done
    g=$(cd "$S" && python3 -c '
import sys, pathlib
import check_cadence as K, nudge_user_attention as N, cadence_changes as C
r = sys.argv[1]
print(K.default_branch(r), N.default_branch(pathlib.Path(r)), C.default_branch(r))' "$F/$fx" 2>&1)
    [ "$g" = "$want $want $want" ] || got="$got python=[$g]"
    [ -z "$got" ] && ok "$fx: all seven copies resolve '$want'" || bad "$fx: want $want, got:$got"
done
g=$(cd "$S" && python3 -c 'import sys, check_cadence as K; print(K.default_ref(sys.argv[1]))' "$F/trunk")
[ "$g" = origin/trunk ] && ok "check_cadence.default_ref: origin/trunk" || bad "default_ref: $g"
g=$(cd "$S" && python3 -c 'import sys, cadence_changes as C; print(C.origin_default(sys.argv[1]))' "$F/noorigin")
[ "$g" = None ] && ok "cadence_changes.origin_default: None when origin has no such ref (reads nothing, guesses nothing)" || bad "origin_default noorigin: $g"

# --- 1) the gate on a trunk repo: trunk blocked, main still blocked, a topic passes
C="$F/trunk"
mkdir -p "$C/scripts/git-hooks" && cp "$S/git-hooks/pre-push" "$C/scripts/git-hooks/" && chmod +x "$C/scripts/git-hooks/pre-push"
git -C "$C" add -A && git -C "$C" commit -qm hook && git -C "$C" push -q origin trunk
git -C "$C" config core.hooksPath scripts/git-hooks
git -C "$C" commit -q --allow-empty -m change
rem() { git -C "$C.git" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
b=$(rem trunk); out=$(git -C "$C" push origin HEAD:trunk 2>&1); rc=$?
[ $rc -ne 0 ] && [ "$(rem trunk)" = "$b" ] && grep -q "BLOCKED — direct push to trunk" <<< "$out" \
    && ok "pre-push blocks a push to the default branch trunk" || bad "trunk push rc=$rc: $out"
out=$(git -C "$C" push origin HEAD:main 2>&1); rc=$?
[ $rc -ne 0 ] && [ -z "$(rem main)" ] && ok "pre-push still blocks main in a trunk repo" || bad "main push in trunk repo rc=$rc: $out"
out=$(git -C "$C" push -q origin HEAD:topic 2>&1); rc=$?
[ $rc -eq 0 ] && [ -n "$(rem topic)" ] && ok "a topic branch passes" || bad "topic rc=$rc: $out"
out=$(ALLOW_MAIN_PUSH=1 git -C "$C" push -q origin HEAD:trunk 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(rem trunk)" = "$(git -C "$C" rev-parse HEAD)" ] && ok "ALLOW_MAIN_PUSH=1 overrides on trunk too" || bad "override rc=$rc: $out"

# --- 2) the gate with origin/HEAD unset: init.defaultBranch names it, main stays guarded
C="$F/cfg"
mkdir -p "$C/scripts/git-hooks" && cp "$S/git-hooks/pre-push" "$C/scripts/git-hooks/" && chmod +x "$C/scripts/git-hooks/pre-push"
git -C "$C" config core.hooksPath scripts/git-hooks; git -C "$C" commit -q --allow-empty -m change
out=$(git -C "$C" push origin HEAD:trunk 2>&1); rc=$?
[ $rc -ne 0 ] && grep -q "BLOCKED" <<< "$out" && ok "origin/HEAD unset: init.defaultBranch=trunk is guarded" || bad "cfg trunk push rc=$rc: $out"
out=$(git -C "$C" push origin HEAD:main 2>&1); rc=$?
[ $rc -ne 0 ] && grep -q "BLOCKED" <<< "$out" && ok "origin/HEAD unset: main is still guarded" || bad "cfg main push rc=$rc: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
