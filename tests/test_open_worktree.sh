#!/usr/bin/env bash
# open_worktree.sh (TD-046): a topic's worktree is cut from origin/<default> (cadence §1,
# §9's default-branch rule), an existing branch or worktree is reused, and the VS Code step
# never opens a second window on a topic that already has one.
#
# Offline: a fixture clone with a bare origin whose default is `trunk`. `code` is ALWAYS a
# PATH shim (it records its argv and answers --status from a file), never a real editor;
# the no-`code` case runs under a minimal PATH of symlinked tools. HOME/XDG and git's
# global config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset VSCODE_IPC_HOOK_CLI
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"
git init -q --bare -b trunk "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
git -C "$R" checkout -q -b trunk 2>/dev/null; mkdir -p "$R/scripts"
cp "$DC/files/scripts/open_worktree.sh" "$R/scripts/"
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q -u origin trunk
git -C "$R" remote set-head origin -a >/dev/null
# origin moves on after the clone: the worktree must start from the FETCHED origin/trunk
w="$TMP/w"; git clone -q "$R.git" "$w" 2>/dev/null; git -C "$w" commit -q --allow-empty -m later; git -C "$w" push -q origin HEAD:trunk
tip=$(git -C "$R.git" rev-parse trunk)

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/code" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$CODE_LOG"
if [ "$1" = --status ]; then [ -f "$CODE_STATUS" ] || exit 1; cat "$CODE_STATUS"; fi
exit 0
SHIM
chmod +x "$BIN/code"
export CODE_LOG="$TMP/code.log" CODE_STATUS="$TMP/code.status"
SOCK="$TMP/vscode-ipc-test.sock"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$SOCK"
run() { ( cd "$R" && PATH="$BIN:$PATH" "$@" 2>&1 ); }

# --- 1) a topic name outside the charset is refused
out=$(run scripts/open_worktree.sh "bad topic"); rc=$?
[ $rc -eq 2 ] && grep -q "topic may contain only" <<< "$out" && ok "a topic with a space: refused, exit 2" || bad "bad topic rc=$rc: $out"

# --- 2) a new topic: worktree on a new branch from the fetched origin/<default> (trunk)
out=$(run scripts/open_worktree.sh t1); rc=$?
[ $rc -eq 0 ] && [ "$(git -C "$R/.claude/worktrees/t1" rev-parse HEAD)" = "$tip" ] \
    && [ "$(git -C "$R/.claude/worktrees/t1" branch --show-current)" = t1 ] && grep -q "(from origin/trunk)" <<< "$out" \
    && ok "new topic: branch t1 cut from the fetched origin/trunk" || bad "new topic rc=$rc: $out"
grep -q "no live VS Code window found — open this manually" <<< "$out" && ! grep -q -- "-n " "$CODE_LOG" 2>/dev/null \
    && ok "no live VS Code socket: says so, opens nothing" || bad "no socket: $out / $(cat "$CODE_LOG" 2>/dev/null)"

# --- 3) an existing worktree is reused, not recreated
out=$(run scripts/open_worktree.sh t1); rc=$?
[ $rc -eq 0 ] && grep -q "worktree exists: $R/.claude/worktrees/t1" <<< "$out" && ok "an existing worktree: reused" || bad "reuse rc=$rc: $out"

# --- 4) an existing branch without a worktree is checked out, not re-cut
git -C "$R" branch t2 "$tip~1"
out=$(run scripts/open_worktree.sh t2); rc=$?
[ $rc -eq 0 ] && [ "$(git -C "$R/.claude/worktrees/t2" rev-parse HEAD)" = "$(git -C "$R" rev-parse "$tip~1")" ] \
    && grep -q "branch t2 exists" <<< "$out" && ok "an existing branch: checked out as it is" || bad "existing branch rc=$rc: $out"

# --- 5) a live VS Code: open a new window, unless one is already on the topic
: > "$CODE_LOG"; echo "    Window (README.md - other-t3x - Visual Studio Code)" > "$CODE_STATUS"
out=$( cd "$R" && PATH="$BIN:$PATH" VSCODE_IPC_HOOK_CLI="$SOCK" scripts/open_worktree.sh t3 2>&1 ); rc=$?
[ $rc -eq 0 ] && grep -qx -- "-n $R/.claude/worktrees/t3" "$CODE_LOG" && grep -q "opened a new VS Code window on t3" <<< "$out" \
    && ok "a live window elsewhere: code -n on the new worktree" || bad "open rc=$rc: $out / $(cat "$CODE_LOG")"
: > "$CODE_LOG"; echo "    Window (README.md - t3 - Visual Studio Code)" > "$CODE_STATUS"
out=$( cd "$R" && PATH="$BIN:$PATH" VSCODE_IPC_HOOK_CLI="$SOCK" scripts/open_worktree.sh t3 2>&1 ); rc=$?
[ $rc -eq 0 ] && ! grep -q -- "^-n " "$CODE_LOG" && grep -q "a window is already open on t3" <<< "$out" \
    && ok "a window already on the topic: no second window" || bad "already-open rc=$rc: $out / $(cat "$CODE_LOG")"

# --- 6) no `code` CLI at all: the path to open by hand is printed
MIN="$TMP/min"; mkdir -p "$MIN"
for t in bash env git python3 dirname basename sed grep ls head timeout cat mkdir pwd rm mv cp awk tr date sort cut readlink realpath; do
    p=$(command -v "$t") && ln -sf "$p" "$MIN/$t"
done
out=$( cd "$R" && PATH="$MIN" scripts/open_worktree.sh t4 2>&1 ); rc=$?
[ $rc -eq 0 ] && grep -q "no 'code' CLI on PATH — open this manually: $R/.claude/worktrees/t4" <<< "$out" \
    && ok "no code CLI: prints the path to open" || bad "no-code rc=$rc: $out"

# --- 7) siblings (hydrate, the workspace generator): the repo's scripts/ copy first, then the
# main checkout's copy at this script's repo-relative directory (files/scripts/ in agent-cadence),
# then the copy beside this one — all a repo running its pinned tree has (TD-129)
stub() {  # stub <path> <tag>: a sibling that records which copy ran, and with what
    mkdir -p "$(dirname "$1")"
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$SIB_LOG"\n' "$2" > "$1"; chmod +x "$1"
}
export SIB_LOG="$TMP/sib.log"
TREE="$TMP/cache/trees/abc/files/scripts"; mkdir -p "$TREE"
cp "$DC/files/scripts/open_worktree.sh" "$TREE/"
stub "$TREE/hydrate_worktree.sh" tree; stub "$TREE/generate_workspace.sh" tree-ws
: > "$SIB_LOG"; out=$(run "$TREE/open_worktree.sh" t5); rc=$?
[ $rc -eq 0 ] && grep -qx "tree $R/.claude/worktrees/t5" "$SIB_LOG" && grep -q "^tree-ws --topic $R/.claude/worktrees/t5" "$SIB_LOG" \
    && ok "no scripts/ copy in the repo: the hydrate and generator beside the script run" || bad "beside rc=$rc: $out / $(cat "$SIB_LOG")"
stub "$R/scripts/hydrate_worktree.sh" repo
: > "$SIB_LOG"; out=$(run "$TREE/open_worktree.sh" t6); rc=$?
[ $rc -eq 0 ] && grep -qx "repo $R/.claude/worktrees/t6" "$SIB_LOG" && ! grep -q "^tree " "$SIB_LOG" \
    && ok "the repo's scripts/ copy wins over the one beside the script" || bad "repo-first rc=$rc: $out / $(cat "$SIB_LOG")"
rm -f "$R/scripts/hydrate_worktree.sh"
mkdir -p "$R/files/scripts"; cp "$DC/files/scripts/open_worktree.sh" "$R/files/scripts/"
stub "$R/files/scripts/hydrate_worktree.sh" main-files
WT7="$R/.claude/worktrees/t1"; mkdir -p "$WT7/files/scripts"; cp "$DC/files/scripts/open_worktree.sh" "$WT7/files/scripts/"
stub "$WT7/files/scripts/hydrate_worktree.sh" worktree-files
: > "$SIB_LOG"; out=$( cd "$WT7" && PATH="$BIN:$PATH" files/scripts/open_worktree.sh t7 2>&1 ); rc=$?
[ $rc -eq 0 ] && grep -qx "main-files $R/.claude/worktrees/t7" "$SIB_LOG" && ! grep -q "^worktree-files" "$SIB_LOG" \
    && ok "agent-cadence's layout, run from a worktree: the main checkout's files/scripts/ hydrate runs, not the worktree's" \
    || bad "files/scripts rc=$rc: $out / $(cat "$SIB_LOG")"

# 8. its usage says it is the person's, and what a session uses for its own worktree (TD-139, cadence.md §1.1)
out=$(bash "$DC/files/scripts/open_worktree.sh" 2>&1); rc=$?
[ $rc -eq 2 ] && grep -q "opens an editor window: for a worktree the person will open" <<< "$out" && grep -qF 'git worktree add` + hydrate_worktree.sh' <<< "$out" \
    && ok "usage: for the person's worktree; a session's own is git worktree add + hydrate" || bad "usage rc=$rc: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
