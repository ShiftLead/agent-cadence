#!/usr/bin/env bash
# P1 machine-registry acceptance tests (plan 2026-08-10). Uses an XDG_CONFIG_HOME
# override so the real ~/.config/agent-cadence/repos.txt is never touched.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
export XDG_CONFIG_HOME="$TMP/config"
# A fresh CI runner has no global git identity (TD-047): the fixtures commit with this one.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
REG="$XDG_CONFIG_HOME/agent-cadence/repos.txt"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

mkrepo() { # $1=path
  git init -q -b main "$1"
  mkdir -p "$1/docs"
  git -C "$1" commit -q --allow-empty -m init
}

# --- 1) the roster's writer (`agent-cadence adopt`'s _register, sync.sh's step until TD-129) twice
#        -> exactly one line; the worktree-to-main and symlink cases are adopt's (tests/test_adopt.sh)
reg() { CADENCE_TEMP_ROOTS=/nonexistent python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import words; words._register(sys.argv[2])' "$DC/launcher" "$1" >/dev/null 2>&1; }
T1="$TMP/repo1"; mkrepo "$T1"
want=$(realpath "$T1")
reg "$want"; reg "$want"
lines=$(grep -c . "$REG" 2>/dev/null)
if [ "$lines" = 1 ] && grep -qxF "$want" "$REG"; then ok "register twice -> one line"; else bad "register twice -> got $lines line(s): $(cat "$REG" 2>/dev/null)"; fi

# --- 2) two concurrent writers -> exactly one line (flock'd check-then-append)
rm -f "$REG"
reg "$want" & p1=$!
reg "$want" & p2=$!
wait $p1 $p2
if [ "$(grep -c . "$REG")" = 1 ]; then ok "concurrent writers -> one line"; else bad "concurrent writers -> $(cat "$REG")"; fi

# --- guard tests: run check #6 via the full guard, grep for the roster warn
GUARD="$DC/files/scripts/check_claude_memory.sh"
board() { printf '# board\n\n- [ ] 2026-08-10 (n/a) — thing. Due: 2026-08-12.\n' > "$1/docs/user_attention.md"; }
run_guard() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GUARD" 2>/dev/null); }

T2="$TMP/repo2"; mkrepo "$T2"; board "$T2"
git -C "$T2" remote add origin https://github.com/example/repo2.git

# --- 5) no registry file -> no roster warn
rm -f "$REG"
if ! run_guard "$T2" | grep -q "roster"; then ok "no registry -> silent"; else bad "no registry but warned"; fi

# --- 6) registry exists, repo not listed, open items -> warn
printf '%s\n' "$(realpath "$T1")" > "$REG"
if run_guard "$T2" | grep -q "roster"; then ok "uncovered repo warns"; else bad "uncovered repo did not warn"; fi

# --- 7) listed repo -> no warn (even via a symlink spelling in the registry)
printf '%s\n' "$TMP/../$(basename "$TMP")/repo2" > "$REG"   # non-canonical spelling
if ! run_guard "$T2" | grep -q "roster"; then ok "listed (non-canonical spelling) -> silent"; else bad "listed repo warned"; fi

# --- 8) clean board (no open items) -> no warn even when uncovered
T3="$TMP/repo3"; mkrepo "$T3"
printf '# board\n\n- [x] done thing\n' > "$T3/docs/user_attention.md"
printf '%s\n' "$(realpath "$T1")" > "$REG"
if ! run_guard "$T3" | grep -q "roster"; then ok "clean board -> silent"; else bad "clean board warned"; fi

# --- 9) origin-URL coverage: second checkout of a registered repo's origin -> silent
T4="$TMP/repo4"; mkrepo "$T4"; board "$T4"
git -C "$T4" remote add origin git@github.com:example/repo2.git   # ssh form of T2's origin
printf '%s\n' "$(realpath "$T2")" > "$REG"                        # T2 (https form) is registered
if ! run_guard "$T4" | grep -q "roster"; then ok "same-origin checkout covered -> silent"; else bad "same-origin checkout warned"; fi

# --- 10) registry line pointing at a deleted path degrades silently (still warns for uncovered T4? no — just: guard doesn't crash)
printf '%s\n%s\n' "$TMP/gone-repo" "$(realpath "$T2")" > "$REG"
if ! run_guard "$T4" | grep -q "roster"; then ok "dead registry line skipped, coverage still found"; else bad "dead line broke coverage"; fi

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
