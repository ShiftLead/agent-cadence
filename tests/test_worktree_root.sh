#!/usr/bin/env bash
# The worktree-root setting (TD-101): where open_worktree.sh puts worktrees, read through
# cadence_config.py by every script that knows the layout — the anchor guard's exemption,
# the workspace generator's exclude and prune rule (the hydrate scan's prune is
# tests/test_hydrate_worktree.sh case 27). A value that is not a path inside the clone is
# refused, and each reader's fallback for a machine without the helper is the key's default.
#
# Offline: fixture repos under a temp dir, a bare origin, `code` a PATH shim. HOME, XDG and
# git's global config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset VSCODE_IPC_HOOK_CLI CADENCE_WORKTREE_ROOT
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

mkrepo() {  # mkrepo <name> [worktree-root]: a clone of a bare origin, scripts copied in
    local r="$TMP/$1"
    git init -q --bare -b main "$r.git"; git clone -q "$r.git" "$r" 2>/dev/null
    git -C "$r" checkout -q -b main 2>/dev/null
    mkdir -p "$r/scripts" "$r/docs"
    cp "$S/open_worktree.sh" "$S/cadence_config.py" "$S/generate_workspace.sh" "$r/scripts/"
    [ -n "${2:-}" ] && printf 'worktree-root = "%s"\n' "$2" > "$r/docs/cadence.toml"
    git -C "$r" add -A; git -C "$r" commit -qm base; git -C "$r" push -q -u origin main
    git -C "$r" remote set-head origin -a >/dev/null
}
cfg() { python3 "$S/cadence_config.py" "$@" 2>&1; }

# --- 1) the reader: default, a repo value (normalised), env, and what it refuses
mkrepo r1
[ "$(cfg get worktree-root --repo "$TMP/r1")" = ".claude/worktrees" ] && ok "default is .claude/worktrees" || bad "default: $(cfg get worktree-root --repo "$TMP/r1")"
printf 'worktree-root = "wt/"\n' > "$TMP/r1/docs/cadence.toml"
[ "$(cfg get worktree-root --repo "$TMP/r1")" = "wt" ] && ok "a repo value is read, its trailing slash dropped" || bad "repo value: $(cfg get worktree-root --repo "$TMP/r1")"
[ "$(CADENCE_WORKTREE_ROOT=elsewhere/wts cfg get worktree-root --repo "$TMP/r1")" = "elsewhere/wts" ] && ok "env CADENCE_WORKTREE_ROOT wins" || bad "env"
for v in /abs/wt ../out . .. '~/wt' .git .git/wt .claude 'wt*' 'w[t]' '#wt' 'a/!wt' 'w\\t'; do
  printf 'worktree-root = "%s"\n' "$v" > "$TMP/r1/docs/cadence.toml"
  out=$(cfg get worktree-root --repo "$TMP/r1"); rc=$?
  chk=$(cfg --check --repo "$TMP/r1"); crc=$?
  [ $rc -eq 2 ] && grep -q "must be a p" <<< "$out" && [ $crc -eq 1 ] && grep -q "worktree-root must be a p" <<< "$chk" \
    && ok "'$v' is refused by get (exit 2) and named by --check" || bad "'$v': get rc=$rc $out / check rc=$crc $chk"
done
out=$(CADENCE_WORKTREE_ROOT=/abs cfg get worktree-root --repo "$TMP/r1"); [ $? -eq 2 ] && ok "an env value is held to the same rule" || bad "env /abs: $out"

# --- 2) open_worktree.sh creates the worktree under the setting; a bad value creates nothing
BIN="$TMP/bin"; mkdir -p "$BIN"; printf '#!/bin/sh\nexit 0\n' > "$BIN/code"; chmod +x "$BIN/code"
mkrepo r2 wt
( cd "$TMP/r2" && PATH="$BIN:$PATH" scripts/open_worktree.sh topic-a >/dev/null 2>&1 ); rc=$?
[ $rc -eq 0 ] && git -C "$TMP/r2/wt/topic-a" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ ! -e "$TMP/r2/.claude/worktrees/topic-a" ] \
  && ok "open_worktree.sh: worktree-root = wt puts the worktree at wt/<topic>" || bad "open_worktree wt (rc=$rc): $(ls -A "$TMP/r2")"
mkrepo r2d
( cd "$TMP/r2d" && PATH="$BIN:$PATH" scripts/open_worktree.sh topic-b >/dev/null 2>&1 )
[ -d "$TMP/r2d/.claude/worktrees/topic-b" ] && ok "open_worktree.sh: no setting keeps .claude/worktrees" || bad "open_worktree default"
printf 'worktree-root = "../escape"\n' > "$TMP/r2/docs/cadence.toml"
out=$( cd "$TMP/r2" && PATH="$BIN:$PATH" scripts/open_worktree.sh topic-c 2>&1 ); rc=$?
[ $rc -eq 2 ] && grep -q "must be a path inside the clone" <<< "$out" && [ ! -e "$TMP/escape" ] && ! git -C "$TMP/r2" rev-parse -q --verify topic-c >/dev/null \
  && ok "open_worktree.sh: a value outside the clone is an error, and nothing is created" || bad "open_worktree escape (rc=$rc): $out"
# a settings problem that leaves worktree-root unwritten warns and takes the default;
# one in a file that does write it refuses
printf 'review-model = [\n' > "$TMP/r2d/docs/cadence.toml"
out=$( cd "$TMP/r2d" && PATH="$BIN:$PATH" scripts/open_worktree.sh topic-d 2>&1 ); rc=$?
[ $rc -eq 0 ] && [ -d "$TMP/r2d/.claude/worktrees/topic-d" ] && grep -q "worktree-root is not set in them" <<< "$out" \
  && ok "open_worktree.sh: an unreadable settings file without worktree-root warns and uses the default" || bad "unrelated bad toml (rc=$rc): $out"
printf 'worktree-root = "wt"\nreview-model = [\n' > "$TMP/r2d/docs/cadence.toml"
out=$( cd "$TMP/r2d" && PATH="$BIN:$PATH" scripts/open_worktree.sh topic-e 2>&1 ); rc=$?
[ $rc -eq 2 ] && [ ! -e "$TMP/r2d/.claude/worktrees/topic-e" ] && [ ! -e "$TMP/r2d/wt/topic-e" ] \
  && ok "open_worktree.sh: an unreadable settings file that sets worktree-root refuses" || bad "bad toml with key (rc=$rc): $out"
git -C "$TMP/r2d" checkout -q -- . 2>/dev/null; rm -f "$TMP/r2d/docs/cadence.toml"
git -C "$TMP/r2" checkout -q -- docs/cadence.toml

# --- 3) the anchor guard's fast path follows the setting. A path that does not exist is
#        undeterminable to the nested-root test and stays an occupant, so only the exemption
#        can clear it — which is what makes these cases tell the setting apart.
occ() { (cd "$S" && python3 -c 'import sys; from pathlib import Path; import check_anchor as A; print(A.occupies(sys.argv[1], Path(sys.argv[2])))' "$@"); }
R2="$(cd "$TMP/r2" && pwd -P)"
[ "$(occ "$R2/wt/ghost" "$R2")" = False ] && ok "anchor: a session under the set worktree root is not an occupant" || bad "anchor wt: $(occ "$R2/wt/ghost" "$R2")"
[ "$(occ "$R2/.claude/worktrees/ghost" "$R2")" = True ] && ok "anchor: .claude/worktrees is not exempt by name once the setting moves it" || bad "anchor old root: $(occ "$R2/.claude/worktrees/ghost" "$R2")"
[ "$(occ "$R2/wt" "$R2")" = True ] && ok "anchor: the worktree root itself is not a worktree" || bad "anchor root dir"
R2D="$(cd "$TMP/r2d" && pwd -P)"
[ "$(occ "$R2D/.claude/worktrees/ghost" "$R2D")" = False ] && [ "$(occ "$R2D/wt/ghost" "$R2D")" = True ] \
  && ok "anchor: with no setting the default is exempt and wt/ is not" || bad "anchor default"
[ "$(occ "$R2/wt/topic-a" "$R2")" = False ] && ok "anchor: the real worktree open_worktree.sh made is not an occupant" || bad "anchor real wt"
mkrepo r3 '../bad'; R3="$(cd "$TMP/r3" && pwd -P)"
[ "$(occ "$R3/.claude/worktrees/ghost" "$R3")" = False ] && ok "anchor: an invalid setting falls back to the default, never an error" || bad "anchor invalid: $(occ "$R3/.claude/worktrees/ghost" "$R3")"

# --- 4) generate_workspace.sh: the explorer hides the set root (and Claude Code's), and the
#        overview prunes a topic file whose worktree under the set root is gone
( cd "$TMP/r2" && scripts/generate_workspace.sh >/dev/null 2>&1 )
ex=$(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["settings"]["files.exclude"])))' "$TMP/r2/r2.code-workspace" 2>&1)
grep -qw -- "\*\*/wt" <<< "$ex" && grep -qw -- "\*\*/.claude/worktrees" <<< "$ex" && ok "workspace: excludes **/wt and **/.claude/worktrees" || bad "workspace exclude: $ex"
printf '{"folders": [{"path": "wt/gone"}]}\n' > "$TMP/r2/gone.code-workspace"
printf '{"folders": [{"path": ".claude/worktrees/old"}]}\n' > "$TMP/r2/old.code-workspace"
out=$( cd "$TMP/r2" && scripts/generate_workspace.sh 2>&1 )
printf '{"folders": [{"path": "elsewhere/x"}]}\n' > "$TMP/r2/x.code-workspace"
out=$( cd "$TMP/r2" && scripts/generate_workspace.sh 2>&1 )
[ ! -e "$TMP/r2/gone.code-workspace" ] && [ ! -e "$TMP/r2/old.code-workspace" ] && [ -e "$TMP/r2/x.code-workspace" ] \
  && ok "workspace: prunes gone topics under the set root and Claude Code's, never a file it did not write" || bad "workspace prune: $out / $(ls "$TMP/r2"/*.code-workspace)"

# --- 6) each reader's no-helper fallback is the key's default (one value, typed per reader)
def=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import cadence_config as C; print(C.KEYS["worktree-root"][0])' "$S")
for f in open_worktree.sh generate_workspace.sh hydrate_worktree.sh check_anchor.py; do
  lits=$(grep -oE '"\.claude/worktrees"' "$S/$f" | sort -u)
  [ "$lits" = "\"$def\"" ] && ok "$f: its fallback is the default ($def)" || bad "$f fallback literals: $lits"
done

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
