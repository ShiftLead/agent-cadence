#!/usr/bin/env bash
# TD-043 — the guards degrade toward a redundant warning, never toward silence
# (cadence.md containers appendix). Two paths used to do the opposite:
#   1. no procfs (macOS): every registry entry read as dead — the anchor guard went
#      silent and the reaper's idle gate called a live session's worktree idle;
#   2. a git failure other than "not a git repository" (devcontainer dubious
#      ownership, a timeout, no git) returned 0 with nothing printed.
# And list_sessions carried its own naive liveness test (bare /proc/<pid>), which a
# reused pid fools; it now asks the session adapter (agent_sessions.py, TD-100).
#
# Offline: HOME is a temp dir, `git` is PATH-shimmed where a failure is simulated,
# and "no procfs" is simulated by patching procfs_available() — /proc itself is
# never touched.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
PIDS=""
trap '[ -n "$PIDS" ] && kill $PIDS 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
REG="$HOME/.claude/sessions"; mkdir -p "$REG"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

REPO="$TMP/repo"; git init -q -b main "$REPO"; git -C "$REPO" commit -q --allow-empty -m init
DEADPID=999999; while [ -e "/proc/$DEADPID" ]; do DEADPID=$((DEADPID-1)); done
printf '{"sessionId":"dead-1","pid":%s,"cwd":"%s"}\n' "$DEADPID" "$REPO" > "$REG/$DEADPID.json"

# --- 1) no procfs: a registry entry is KEPT (undeterminable), with procfs it is dropped
out=$(PYTHONPATH="$S" python3 -c '
import agent_sessions as A
print(len(A.live_sessions()))
A.procfs_available = lambda: False
print(len(A.live_sessions()))' 2>&1)
[ "$out" = $'0\n1' ] && ok "a dead pid is dropped with procfs, kept (undeterminable) without" || bad "no-procfs liveness: $out"

# ... and the anchor guard therefore WARNS rather than going silent
out=$(cd "$REPO" && echo '{"session_id":"me","cwd":"'"$REPO"'"}' | PYTHONPATH="$S" python3 -c '
import sys, agent_sessions, check_anchor as A
agent_sessions.procfs_available = lambda: False
sys.argv = ["check_anchor.py", "--hook"]
sys.exit(A.main())' 2>&1)
grep -q "ANCHOR CONFLICT" <<< "$out" && ok "no procfs: the anchor guard warns (redundantly) instead of going silent" \
    || bad "no procfs: guard output '$out'"
rm -f "$REG/$DEADPID.json"

# --- 2) the reaper: no procfs -> idle=? and nothing reaped, never idle=yes
R="$TMP/rr"; git init -q --bare -b main "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
( cd "$R" && git checkout -q -b main 2>/dev/null; mkdir -p scripts
  sed 's/^def procfs_available() -> bool:/def procfs_available() -> bool:\n    return False  # test: simulate a host without procfs/' "$S/agent_sessions.py" > scripts/agent_sessions.py
  cp "$S/check_anchor.py" "$S/cadence_config.py" scripts/
  cp "$S/reap_worktrees.sh" scripts/; echo b > b.txt; git add .; git commit -qm b; git push -q -u origin main
  git worktree add -q -b wt .claude/worktrees/wt origin/main
  ( cd .claude/worktrees/wt && echo w >> b.txt && git commit -qam w )
  git merge -q --squash wt && git commit -qm "wt (#1)" && git push -q origin main && git fetch -q origin )
out=$(cd "$R" && scripts/reap_worktrees.sh --reap 2>&1)
grep -q "idle=?" <<< "$out" && grep -q "could not read the live-session registry" <<< "$out" && [ -d "$R/.claude/worktrees/wt" ] \
    && ok "no procfs: the reaper reports idle=?, reaps nothing" || bad "reaper without procfs: $out"

# --- 3) git failures other than "not a repo": one line, not silence
mkdir -p "$TMP/shim"
printf '#!/bin/sh\necho "fatal: detected dubious ownership in repository at '"'"'/x'"'"'" >&2\nexit 128\n' > "$TMP/shim/git"
chmod +x "$TMP/shim/git"
out=$(cd "$REPO" && echo '{"session_id":"me","cwd":"'"$REPO"'"}' | PATH="$TMP/shim:$PATH" python3 "$S/check_anchor.py" --hook 2>&1); rc=$?
grep -q "anchor check did not run: fatal: detected dubious ownership" <<< "$out" && [ $rc -eq 0 ] \
    && ok "anchor guard: dubious ownership -> one line, exit 0" || bad "anchor dubious: rc=$rc '$out'"
out=$(cd "$REPO" && PATH="$TMP/shim:$PATH" python3 "$S/cadence_changes.py" --hook 2>&1); rc=$?
grep -q "cadence-changes check did not run: fatal: detected dubious ownership" <<< "$out" && [ $rc -eq 0 ] \
    && ok "changes hook: dubious ownership -> one line, exit 0" || bad "changes dubious: rc=$rc '$out'"
# ... git missing entirely
mkdir -p "$TMP/nogit"; for b in python3 sh env; do ln -sf "$(command -v $b)" "$TMP/nogit/$b"; done
out=$(cd "$REPO" && echo '{}' | PATH="$TMP/nogit" python3 "$S/check_anchor.py" --hook 2>&1)
grep -q "anchor check did not run: git could not run" <<< "$out" && ok "anchor guard: no git on PATH -> one line" || bad "no git: '$out'"
# ... a bare repo, and GIT_DIR without a work tree, are "no checkout here", not failures
git init -q --bare "$TMP/bare.git"
out=$(cd "$TMP/bare.git" && echo '{"cwd":"'"$TMP/bare.git"'"}' | python3 "$S/check_anchor.py" --hook 2>&1; cd "$TMP/bare.git" && python3 "$S/cadence_changes.py" --hook 2>&1)
[ -z "$out" ] && ok "a bare repo: both hooks stay silent" || bad "bare repo printed: '$out'"
mkdir -p "$TMP/gd"
out=$(cd "$TMP/gd" && echo '{"cwd":"'"$TMP/gd"'"}' | GIT_DIR="$TMP/bare.git" python3 "$S/check_anchor.py" --hook 2>&1)
[ -z "$(grep 'did not run' <<< "$out")" ] && ok "GIT_DIR at a bare repo, no work tree: no 'did not run' line" || bad "GIT_DIR printed: '$out'"
# ... a non-English locale does not turn "not a repo" into a warning (the call runs in C)
mkdir -p "$TMP/plain2"
printf '#!/bin/sh
if [ "$LC_ALL" = C ]; then echo "fatal: not a git repository (or any of the parent directories): .git" >&2; else echo "fatal: kein Git-Repository" >&2; fi
exit 128
' > "$TMP/shim/git"
out=$(cd "$TMP/plain2" && echo '{"cwd":"'"$TMP/plain2"'"}' | LANG=de_DE.UTF-8 PATH="$TMP/shim:$PATH" python3 "$S/check_anchor.py" --hook 2>&1; cd "$TMP/plain2" && LANG=de_DE.UTF-8 PATH="$TMP/shim:$PATH" python3 "$S/cadence_changes.py" --hook 2>&1)
[ -z "$out" ] && ok "a translated git: 'not a repo' still read as such (C locale)" || bad "locale printed: '$out'"
# ... and a plain non-repo directory stays silent in both
mkdir -p "$TMP/plain"
out=$(cd "$TMP/plain" && echo '{"cwd":"'"$TMP/plain"'"}' | python3 "$S/check_anchor.py" --hook 2>&1; cd "$TMP/plain" && python3 "$S/cadence_changes.py" --hook 2>&1)
[ -z "$out" ] && ok "not a git repo: both hooks stay silent" || bad "not-a-repo printed: '$out'"

# --- 4) list_sessions asks check_anchor: a live pid whose procStart does not match is
#        a REUSED pid, not the session — the naive /proc/<pid> test called it active
sleep 300 & SP=$!; PIDS="$SP"
printf '{"sessionId":"reused","pid":%s,"procStart":"1","cwd":"%s"}\n' "$SP" "$REPO" > "$REG/$SP.json"
out=$(PYTHONPATH="$S" python3 -c 'import list_sessions as L; print(sorted(L.active_sessions()))' 2>&1)
[ "$out" = "[]" ] && ok "list_sessions: a reused pid is not an active session" || bad "list_sessions active: $out"
real=$(awk '{print $22}' "/proc/$SP/stat" 2>/dev/null)
printf '{"sessionId":"real","pid":%s,"procStart":"%s","cwd":"%s"}\n' "$SP" "$real" "$REPO" > "$REG/$SP.json"
out=$(PYTHONPATH="$S" python3 -c 'import list_sessions as L; print(sorted(L.active_sessions()))' 2>&1)
[ "$out" = "['real']" ] && ok "list_sessions: a corroborated pid is active" || bad "list_sessions corroborated: $out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
