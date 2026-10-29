#!/usr/bin/env bash
# check_base.py (TD-061): what a resumed session is told about its own base at SessionStart.
# Offline: a clone with a bare origin; "landing" is a squash commit pushed to origin/main,
# as GitHub's squash merge leaves it. Dates are relative (touch -d), never calendar (TD-24).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/check_base.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
unset CLAUDE_PROJECT_DIR
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"
git init -q --bare -b main "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
g() { git -C "$R" "$@"; }
g config user.email t@t; g config user.name t; g checkout -q -b main 2>/dev/null
printf 'a\nb\nc\n' > "$R/f.txt"; echo x > "$R/other.txt"
g add -A; g commit -qm base; g push -q -u origin main; g fetch -q origin
run() { ( cd "$R" && python3 "$SCRIPT" "$@" 2>&1 ); }
# land <branch>: squash it onto origin/main from a scratch worktree, as a merged PR would
land() {
    local w="$TMP/land-$1"
    g worktree add -q --detach "$w" origin/main
    git -C "$w" merge -q --squash "$1" >/dev/null && git -C "$w" commit -qm "$1 (#1)" && git -C "$w" push -q origin HEAD:main
    g worktree remove --force "$w"; g fetch -q origin
}
main_commit() {  # $1 file, $2 content, $3 message — a commit straight onto origin/main
    local w="$TMP/main-$RANDOM"
    g worktree add -q --detach "$w" origin/main
    printf '%b' "$2" > "$w/$1"; git -C "$w" add -A; git -C "$w" commit -qm "$3"; git -C "$w" push -q origin HEAD:main
    g worktree remove --force "$w"; g fetch -q origin
}

# --- 1) on main, and on a fresh unlanded current branch: silent as a hook
[ -z "$(run --hook)" ] && ok "on the default branch: silent" || bad "on main: $(run --hook)"
g checkout -q -b topic1; echo t1 > "$R/t1.txt"; g add -A; g commit -qm t1
[ -z "$(run --hook)" ] && ok "a current, unlanded branch: silent" || bad "unlanded: $(run --hook)"
run | grep -q "base: nothing to report" && ok "by hand, nothing to say is said once" || bad "by hand: $(run)"
g checkout -q --detach; [ -z "$(run --hook)" ] && ok "detached HEAD: silent" || bad "detached: $(run --hook)"
g checkout -q topic1

# --- 2) the branch landed (squash on main): named, and `git log origin/main..` would still say pending
land topic1
out=$(run --hook)
grep -q "this branch (topic1) has LANDED on origin/main (its files match, by content)" <<< "$out" && grep -q "gh pr list --head topic1 --state merged" <<< "$out" \
  && [ -n "$(g log --oneline origin/main..topic1)" ] \
  && ok "a squash-landed branch is named as landed (where log origin/main.. still lists it)" || bad "landed: $out"

# --- 3) landed, then main edited its file again: TD-059's landed-since-edited
g checkout -q -b topic2 origin/main; printf 'a\nB2\nc\n' > "$R/f.txt"; g commit -qam t2
land topic2
main_commit f.txt 'a\nB2-later\nc\n' "main edits f again"
out=$(run --hook)
grep -q "this branch (topic2) has LANDED on origin/main (main has edited its files since)" <<< "$out" \
  && ok "landed, then edited on main: still landed (TD-059)" || bad "since-edited: $out"

# --- 4) landed, then reverted on main
g checkout -q -b topic3 origin/main; echo t3 > "$R/t3.txt"; g add -A; g commit -qm t3
land topic3
w="$TMP/rev"; g worktree add -q --detach "$w" origin/main; git -C "$w" rm -q t3.txt; git -C "$w" commit -qm "revert t3"; git -C "$w" push -q origin HEAD:main
g worktree remove --force "$w"; g fetch -q origin
out=$(run --hook)
grep -q "landed on origin/main and main has since REVERTED it" <<< "$out" && ok "landed then reverted: said so" || bad "reverted: $out"

# --- 5) unlanded and would conflict with main now
g checkout -q -b topic4 origin/main; printf 'a\nMINE\nc\n' > "$R/f.txt"; g commit -qam t4
main_commit f.txt 'a\nTHEIRS\nc\n' "main edits the same line"
out=$(run --hook)
if git merge-tree -h 2>&1 | grep -q -- '--write-tree'; then
  grep -q "merging topic4 into origin/main now would CONFLICT (f.txt)" <<< "$out" && ok "a conflict with main now is named, with the file" || bad "conflict: $out"
else
  echo "SKIP: git $(git --version) has no merge-tree --write-tree"
fi

# --- 6) main far past the fork point; and a stale fetch said only beside a real fact
g checkout -q -b topic5 origin/main; echo t5 > "$R/t5.txt"; g add -A; g commit -qm t5
for i in $(seq 1 20); do main_commit "m$i.txt" "$i" "main $i"; done
out=$(run --hook)
grep -q "origin/main is 2[0-9] commits past this branch's fork point" <<< "$out" && ! grep -q "last fetched" <<< "$out" \
  && ok "20+ commits on main past the fork point: said; a fresh fetch is not" || bad "behind: $out"
touch -d "3 days ago" "$R/.git/FETCH_HEAD"
out=$(run --hook)
grep -q "origin was last fetched 3.0 days ago" <<< "$out" && ok "a stale fetch is said beside a real fact" || bad "stale beside: $out"
g checkout -q -b topic6 origin/main; echo t6 > "$R/t6.txt"; g add -A; g commit -qm t6
touch -d "3 days ago" "$R/.git/FETCH_HEAD"
[ -z "$(run --hook)" ] && ok "a stale fetch alone is not worth a session's attention: silent" || bad "stale alone: $(run --hook)"

# --- 7) from a linked worktree: its own FETCH_HEAD counts too, and CLAUDE_PROJECT_DIR is honoured
g worktree add -q "$TMP/wt" topic1
git -C "$TMP/wt" fetch -q origin
touch -d "3 days ago" "$R/.git/FETCH_HEAD"
out=$( cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP/wt" python3 "$SCRIPT" --hook 2>&1 )
grep -q "this branch (topic1) has LANDED" <<< "$out" && ! grep -q "last fetched" <<< "$out" \
  && ok "linked worktree via CLAUDE_PROJECT_DIR: landed named; the worktree's fresh fetch counts" || bad "worktree: $out"

# --- 8) no origin/<default> at all: silent, exit 0
N="$TMP/noorigin"; git init -q -b main "$N"; git -C "$N" -c user.email=t@t -c user.name=t commit -q --allow-empty -m r
git -C "$N" checkout -q -b x
out=$( cd "$N" && python3 "$SCRIPT" --hook 2>&1 ); rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok "no origin: silent, exit 0" || bad "no origin rc=$rc: $out"
out=$( cd "$TMP" && python3 "$SCRIPT" --hook 2>&1 ); rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok "outside a repo: silent, exit 0" || bad "outside rc=$rc: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
