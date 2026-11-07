#!/usr/bin/env bash
# TD-218: the cadence check's `gates` row — ledgerboard v2.4's tripwire() and uncovered_decisions() over a PR's
# merge-base and head (check_cadence.py row_gates). The verdicts' own cases are ledgerboard's fixtures
# (tests/ledgerboard/verdict, run by test_ledgerboard_fixtures.sh); this suite lays a few of them into a git
# repo and reads the row: what fails it, what is a ⚠, and that it reads commits, not the working tree.
# Offline: temp git repos with a bare origin; HOME/XDG_CONFIG_HOME are temp. The fixtures' dates are
# ledgerboard's own and are not judged by these two verdicts (no date window), so they do not rot (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
V="$DC/tests/ledgerboard/verdict"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/widgets"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"
cp -r "$V/base/docs" "$R/docs"; echo x > "$R/other.txt"
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null

row() {  # $1 = state (open|merged): the row on HEAD
  python3 - "$R" "$1" "$S" <<'EOF'
import sys
root, state, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
base = C.git(["rev-parse", "origin/main"], cwd=root).strip()
rng = f"{sha}^..{sha}" if state == "merged" else f"{base}..{sha}"
files = sorted(set(C.git(["diff", "--name-only", rng], cwd=root).split()))
pr = {"state": state, "head_sha": sha, "merge_sha": sha, "files": files}
r = C.row_gates(pr, root)
print(r["status"], r["detail"])
EOF
}
case_pr() {  # $1 = a verdict case's name, $2 = the commit's subject: a topic branch off main carrying its head
  git -C "$R" switch -q -C topic origin/main
  cp -r "$V/cases/$1/head/docs/." "$R/docs/"
  git -C "$R" add -A; git -C "$R" commit -qm "$2"
}

# a decide lift — the board's Decided: and the ledger's answer line in one commit — passes
case_pr "a lift, closed in the same write" "board: decide Warm the cache nightly?: Go (session w-1)"
st=$(row open); [ "${st%% *}" = pass ] && ok "a decide lift passes the row" || bad "decide lift: $st"

# a gate removed by hand fails, naming the entry and the gate; the same PR merged fails too
case_pr "a gate removed by hand" "ledger: set TD-150 (session w-1)"
st=$(row open); [ "${st%% *}" = fail ] && echo "$st" | grep -q "TD-150 drops decision (pat) with no answer logged" \
  && ok "a gate removed with no answer fails the row, named" || bad "hand removal: $st"
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic >/dev/null 2>&1; git -C "$R" commit -qm "ledger: set TD-150 (#5)"
st=$(row merged); [ "${st%% *}" = pass ] && echo "$st" | grep -q "⚠ TD-150 drops decision (pat)" \
  && ok "the same change merged is a ⚠, read off its merge commit against its parent (a sweep never fails history)" || bad "merged: $st"
git -C "$R" reset -q --hard origin/main
# it reads commits, not the disk: the working tree put back to the base leaves the verdict the commit's
case_pr "a gate removed by hand" "ledger: set TD-150 (session w-1)"
git -C "$R" show origin/main:docs/ledger/TD-150.md > "$R/docs/ledger/TD-150.md"
st=$(row open); [ "${st%% *}" = fail ] && ok "the row judges the commit, not the working tree" || bad "disk read: $st"
git -C "$R" checkout -q -- docs

# an open PR is judged on its merge-base, not its last commit: the gate dropped in commit 1, an unrelated commit 2
case_pr "a gate removed by hand" "ledger: set TD-150 (session w-1)"
echo z >> "$R/other.txt"; git -C "$R" commit -qam "unrelated"
st=$(row open); [ "${st%% *}" = fail ] && echo "$st" | grep -q "TD-150 drops" \
  && ok "a two-commit PR is judged from its merge-base (the gate dropped in its first commit fails)" || bad "two-commit: $st"

# the one-time migrate commit is exempt, by its subject alone
case_pr "a gate removed by hand" "ledger: migrate v2.4 (9 entries)"
st=$(row open); [ "${st%% *}" = pass ] && ok "a gate removed in the migrate commit passes (exempt by subject)" || bad "migrate: $st"

# a lift by someone other than the gate's person is review's to decide: a ⚠, never a fail
case_pr "a lift by someone other than the gate's person, owner board" "ledger: set TD-150 (session w-1)"
st=$(row open); [ "${st%% *}" = pass ] && echo "$st" | grep -q "⚠ TD-150 lifts decision (pat) by sam" \
  && ok "a lift by another than the gate's person is a ⚠ (review decides)" || bad "tripwire-by: $st"

# a decision added with no board item is refused; one filed with its item passes
case_pr "a new decision with no item" "ledger: set TD-160 (session w-1)"
st=$(row open); [ "${st%% *}" = fail ] && echo "$st" | grep -q "TD-160 gains decision (pat) and no open decide item" \
  && ok "a decision added with no board item fails the row" || bad "uncovered: $st"
echo "$st" | grep -qF 'board_edit.py add --board docs/user_attention.md --kind decide --context "TD-160 decision (pat)"' \
  && echo "$st" | grep -qF -- "--detail '{\"context\": [...], \"question\": ..., \"recommended\": ...}' --no-commit" \
  && ok "the uncovered refusal prints the command that files its item (TD-244)" || bad "uncovered fix: $st"
case_pr "a new decision, its item filed with it" "ledger: set TD-160 (session w-1)"
st=$(row open); [ "${st%% *}" = pass ] && ok "a decision added with its board item passes" || bad "covered: $st"
# a new gate item none of whose answers lifts is refused
case_pr "a new decision item with no lifting answer" "board: add (session w-1)"
st=$(row open); [ "${st%% *}" = fail ] && echo "$st" | grep -q "none of its answers lifts it" \
  && ok "a new gate item with no lifting answer fails the row" || bad "no-lift: $st"
echo "$st" | grep -qF 'give it `--lift <the answer that ends the wait>`' && ok "the no-lift refusal names its cure (TD-244)" || bad "no-lift fix: $st"
# a person this repo's board does not list: coverage rests on another board — a ⚠, never a fail
case_pr "a new decision covered on another repo's board" "ledger: set TD-170 (session w-1)"
st=$(row open); [ "${st%% *}" = pass ] && echo "$st" | grep -q "⚠ TD-170 gains decision (kim)" \
  && ok "a decision for someone this board does not list is a ⚠" || bad "elsewhere: $st"

# na on a PR that touches neither the ledger nor the board
git -C "$R" switch -q -C topic origin/main; echo y >> "$R/other.txt"; git -C "$R" commit -qam other
st=$(row open); [ "${st%% *}" = na ] && ok "the row is na on a PR touching neither ledger nor board" || bad "na: $st"

# check_pr carries the row
grep -q '("gates", lambda: row_gates(pr, root))' "$S/check_cadence.py" && ok "check_pr runs the gates row" || bad "check_pr has no gates row"

echo "test_gates_row.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
