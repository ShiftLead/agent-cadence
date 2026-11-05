#!/usr/bin/env bash
# TD-219 (slice 3): gate_sweep.py --apply and ledger.py lift. Each host lift is its own tool PR on
# lift/TD-n/<gate> (ledgerboard's target design §4.4): nothing when that PR is open or another open PR's diff
# already lifts the gate, an act item when its PR was closed unmerged. This repo's own board items and closes
# are one sweep PR on sweep/<date>; another repo's board is skipped (TD-229). The checkout is left as it was.
#
# Offline: origin's fetch URL is only named (never fetched); its push URL is a bare repo here. `gh` is a PATH
# shim: `api` answers from fixture files, `pr list|diff|create` from $FIX and a log.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t CADENCE_HOST=testhost TMPDIR="$TMP"
unset CADENCE_FORGE SHIFTLEAD_SESSION
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BIN="$TMP/bin"; FIX="$TMP/fix"; mkdir -p "$BIN" "$FIX"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
k() { printf %s "$1" | tr '/?=' '___'; }
case "$1 $2" in
  "api "*)
    [ -e "$FIX/$(k "$2").404" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    [ -e "$FIX/$(k "$2")" ] && { cat "$FIX/$(k "$2")"; exit 0; } ;;
  "pr list")
    if [ "$5" = --search ]; then cat "$FIX/search.json" 2>/dev/null || echo '[]'; exit 0; fi
    if [ "$3" = --head ]; then cat "$FIX/head_$(k "$4")" 2>/dev/null || echo '[]'; else cat "$FIX/open.json" 2>/dev/null || echo '[]'; fi
    exit 0 ;;
  "pr diff") cat "$FIX/diff_$3"; exit 0 ;;
  "pr create")
    [ -e "$FIX/create_fail" ] && { echo "pull request create failed: GraphQL: boom" >&2; exit 1; }
    n=$(( $(grep -c '^pr create' "$GH_LOG") + 100 )); echo "https://github.com/o/own/pull/$n"; exit 0 ;;
esac
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" FIX
fx() { printf '%s' "$2" > "$FIX/$(printf %s "$1" | tr '/?=' '___')"; }
fx repos/o/own '{"visibility":"private","default_branch":"main"}'
fx repos/o/oth '{"visibility":"private","default_branch":"main"}'
fx repos/o/oth/pulls/3 '{"state":"closed","merged":true}'

TODAY=$(date -u +%F)
PAST=$(python3 -c 'import datetime as d, sys; print(d.date.fromisoformat(sys.argv[1]) - d.timedelta(days=3))' "$TODAY")
board() { printf '# Attention\n\nPeople: %s\n\n## Needs the user\n\n%s\n' "$1" "${2:-}"; }
entry() {   # entry <dir> <n> <blocked by or -> [more body]
  { printf '## TD-%03d: entry %s\n\n**Priority:** Medium\n**Added:** 2026-01-01\n**Status:** Open\n' "$2" "$2"
    [ "$3" != - ] && printf '**Blocked by:** %s\n' "$3"
    printf '**Location:** x\n\n**Why:** y\n'
    [ -n "${4:-}" ] && printf '\n%s\n' "$4"
  } > "$1/docs/ledger/TD-$(printf %03d "$2").md"
}
mkrepo() {
  git init -q -b main "$1"; git -C "$1" remote add origin "$2"
  mkdir -p "$1/docs/ledger/archive"; printf '# Ledger\n' > "$1/docs/ledger/README.md"
  echo "$1" >> "$AGENT_CADENCE_REG_DIR/repos.txt"
}
publish() { git -C "$1" add -A && git -C "$1" commit -qm fixture && git -C "$1" update-ref refs/remotes/origin/main HEAD; }
OWN="$TMP/own"; mkrepo "$OWN" https://github.com/o/own.git
BARE="$TMP/own.git"; git init -q --bare "$BARE"; git -C "$OWN" remote set-url --push origin "$BARE"
OTH="$TMP/oth"; mkrepo "$OTH" https://github.com/o/oth.git
board sam > "$OTH/docs/user_attention.md"
STALE=$(python3 - "$S" "$TODAY" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import ledgerboard as LB
print(LB.item_line("Lift of event (gone) on TD-007 was closed", sys.argv[2], sys.argv[2], "s", None,
                   "TD-007 event (gone) lift", kind="act"))
PY
)
board alex "$STALE" > "$OWN/docs/user_attention.md"
entry "$OWN" 1 "decision (alex)" '**Ask:** Ship the thing?'
entry "$OWN" 2 "decision (sam)" '**Ask:** Rename it?'
entry "$OWN" 3 "until $PAST"
entry "$OWN" 4 "event (landed)" "$(printf '**Event (landed):** the PR lands.\ncheck: pr-merged o/oth#3')"
entry "$OWN" 7 -
publish "$OWN"; publish "$OTH"
git -C "$OWN" push -q "$BARE" HEAD:refs/heads/main
before=$(git -C "$OWN" rev-parse HEAD); : > "$GH_LOG"

out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1); rc=$?
has() { grep -qF -- "$1" <<< "$out"; }
[ "$rc" = 0 ] && has "— applied" && ok "1a --apply: exit 0" || bad "1a rc=$rc: $out"
shown() { git -C "$BARE" show "$1" 2>/dev/null; }
t3=$(shown "lift/TD-003/until:docs/ledger/TD-003.md")
! grep -q 'Blocked by' <<< "$t3" && grep -q "gate lifted: until $PAST — by testhost; date reached" <<< "$t3" \
  && ok "2a an until reached: its own PR on lift/TD-003/until, the gate gone and logged" || bad "2a: $t3 / $out"
t4=$(shown "lift/TD-004/landed:docs/ledger/TD-004.md")
grep -q "gate lifted: event (landed) — by testhost; pr-merged passed; o/oth#3" <<< "$t4" \
  && ok "2b a passed event: its own PR on lift/TD-004/landed, the evidence logged" || bad "2b: $t4"
[ "$(git -C "$BARE" diff --name-only main lift/TD-004/landed)" = docs/ledger/TD-004.md ] \
  && ok "2c a lift PR changes its entry alone" || bad "2c: $(git -C "$BARE" diff --name-only main lift/TD-004/landed)"
grep -q '^pr create --head lift/TD-004/landed --base main --title TD-004: lift event (landed) — its check passed: o/oth#3 (gate sweep)' "$GH_LOG" \
  && ok "2d the lift PR's title names the entry, the gate and the evidence" || bad "2d: $(grep 'pr create' "$GH_LOG")"
b=$(shown "sweep/$TODAY:docs/user_attention.md")
grep -q 'Ship the thing?.*Context: TD-001 decision (alex)' <<< "$b" && ok "3a the sweep PR files this board's decide item" || bad "3a: $b / $out"
grep -q '^- \[x\] .*Lift of event (gone) on TD-007 was closed.*Closed: .* the gate sweep' <<< "$b" \
  && ok "3b ... and closes an item whose gate is gone" || bad "3b: $b"
! grep -q 'Rename it' <<< "$b" && has "file on github.com/o/oth: 1 item(s) skipped — another repo's board is written by a PR there (TD-229)" \
  && ok "3c another repo's board: skipped, said, TD-229" || bad "3c: $out"
[ "$(git -C "$BARE" diff --name-only main "sweep/$TODAY")" = docs/user_attention.md ] && ok "3d the sweep PR changes the board alone" || bad "3d"
[ "$(git -C "$OWN" rev-parse HEAD)" = "$before" ] && [ -z "$(git -C "$OWN" status --porcelain)" ] \
  && [ "$(git -C "$OWN" worktree list | wc -l)" = 1 ] && [ -z "$(git -C "$OWN" branch --list 'lift/*' 'sweep/*')" ] \
  && [ -z "$(ls "$TMP" | grep gate-sweep-)" ] \
  && ok "4a the checkout as it was: no commit, no edit, no worktree, branch or temp dir left" || bad "4a: $(git -C "$OWN" worktree list; git -C "$OWN" branch)"

# 5. idempotent: the PRs open, a second run opens nothing
printf '[{"number":100,"headRefName":"lift/TD-003/until","files":[]},{"number":101,"headRefName":"lift/TD-004/landed","files":[]},{"number":102,"headRefName":"sweep/%s","files":[]}]' "$TODAY" > "$FIX/open.json"
n0=$(grep -c '^pr create' "$GH_LOG")
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1)
[ "$(grep -c '^pr create' "$GH_LOG")" = "$n0" ] && has "lift TD-003 until $PAST: PR #100 is open — nothing to do" \
  && has "board: an earlier sweep PR #102 is open" && ok "5a a second run: nothing opened, each open PR named" || bad "5a: $out"

# 6. an open PR whose diff already lifts the gate; a lift PR closed unmerged
for b in lift/TD-003/until lift/TD-004/landed "sweep/$TODAY"; do git -C "$BARE" branch -q -D "$b"; done
printf '[{"number":7,"headRefName":"someone","files":[{"path":"docs/ledger/TD-004.md"}]}]' > "$FIX/open.json"
printf -- '--- a/docs/ledger/TD-004.md\n+++ b/docs/ledger/TD-004.md\n+- %s: gate lifted: event (landed) — by elsewhere; pr-merged passed; o/oth#3\n' "$TODAY" > "$FIX/diff_7"
printf '[{"number":9,"state":"CLOSED"}]' > "$FIX/head_lift_TD-003_until"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1)
has "lift TD-004 event (landed): PR #7 already lifts it — nothing to do" && ! git -C "$BARE" rev-parse -q --verify lift/TD-004/landed >/dev/null \
  && ok "6a another open PR's diff lifts the gate: no second lift PR" || bad "6a: $out"
has "lift TD-003 until $PAST: its PR #9 was closed unmerged — not reopened" && ! git -C "$BARE" rev-parse -q --verify lift/TD-003/until >/dev/null \
  && grep -q "Lift of until $PAST on TD-003 was closed.*Context: TD-003 until $PAST lift" <<< "$(shown "sweep/$TODAY:docs/user_attention.md")" \
  && ok "6b a lift PR closed unmerged: not reopened, an act item filed in the sweep PR" || bad "6b: $out"
git -C "$OWN" fetch -q "$BARE" "sweep/$TODAY" && git -C "$OWN" update-ref refs/remotes/origin/main FETCH_HEAD
git -C "$BARE" branch -q -D "sweep/$TODAY"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1)
has "lift TD-003 until $PAST: its PR #9 was closed unmerged — not reopened; asked on the board already" \
  && ! git -C "$BARE" rev-parse -q --verify "sweep/$TODAY" >/dev/null && ok "6c that item on the board: not filed again" || bad "6c: $out"

# 8. a stale origin: a sweep PR that filed the item has merged, a lift PR merged after one was closed
git -C "$BARE" branch -q -D "sweep/$TODAY" 2>/dev/null; echo "[]" > "$FIX/open.json"
git -C "$OWN" update-ref refs/remotes/origin/main "$before"   # the fetch from before that merge
printf '[{"number":120,"state":"MERGED","headRefName":"sweep/%s","body":"- file: [act] Lift of until %s on TD-003 was closed — Context: TD-003 until %s lift"}]' "$TODAY" "$PAST" "$PAST" > "$FIX/search.json"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1)
has "lift TD-003 until $PAST: its PR #9 was closed unmerged — not reopened; asked on the board already" \
  && ! grep -q "Lift of until" <<< "$(shown "sweep/$TODAY:docs/user_attention.md")" \
  && ok "8a origin not fetched since the sweep PR merged: the item is not filed again" || bad "8a: $out"
git -C "$BARE" branch -q -D "sweep/$TODAY" 2>/dev/null
printf '[{"number":9,"state":"CLOSED"},{"number":11,"state":"MERGED"}]' > "$FIX/head_lift_TD-003_until"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1)
has "lift TD-003 until $PAST: its PR merged and origin/main still carries the gate — fetch, then sweep" \
  && ok "8b a closed PR and then a merged one: merged wins, nothing filed" || bad "8b: $out"
git -C "$BARE" branch -q -D "sweep/$TODAY" 2>/dev/null; rm -f "$FIX/head_lift_TD-003_until" "$FIX/search.json"

# 9. a PR the forge will not open, and a branch left on origin with no PR
for b in $(git -C "$BARE" branch --format='%(refname:short)' --list 'lift/*' 'sweep/*'); do git -C "$BARE" branch -q -D "$b"; done
: > "$FIX/create_fail"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1); rc=$?
[ "$rc" = 1 ] && has "lift TD-003 until $PAST: not done — pull request create failed: GraphQL: boom — the PR was not opened; lift/TD-003/until was deleted from origin again" \
  && [ -z "$(git -C "$BARE" branch --list "lift/*")" ] && ok "9a create fails after the push: the branch is taken back, exit 1" || bad "9a rc=$rc: $out / $(git -C "$BARE" branch)"
rm "$FIX/create_fail"; git -C "$BARE" branch -q -D "sweep/$TODAY" 2>/dev/null
git -C "$BARE" branch -q -D lift/TD-004/landed 2>/dev/null
x=$(git -C "$OWN" commit-tree "$before^{tree}" -p "$before" -m "someone's"); git -C "$OWN" push -q "$BARE" "$x:refs/heads/lift/TD-003/until"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" --apply 2>&1)
has "lift TD-003 until $PAST: not done — git push lift/TD-003/until:" && has "delete it there (git push origin --delete lift/TD-003/until)" \
  && [ "$(git -C "$BARE" rev-parse lift/TD-003/until)" = "$x" ] \
  && ok "9b a branch on origin with no PR: never forced over, named to delete" || bad "9b: $out"
[ "$(git -C "$OWN" worktree list | wc -l)" = 1 ] && [ -z "$(git -C "$OWN" branch --list 'lift/*' 'sweep/*')" ] && [ -z "$(ls "$TMP" | grep gate-sweep-)" ] \
  && ok "9c after the failures: no worktree, branch or temp dir left" || bad "9c: $(git -C "$OWN" worktree list; git -C "$OWN" branch)"

# 7. ledger.py lift: a host's lift only
W="$TMP/w"; git clone -q -b main "$BARE" "$W" 2>/dev/null
out=$(cd "$W" && python3 "$S/ledger.py" lift TD-001 --gate "decision (alex)" --by testhost 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "a decision is lifted by its person" <<< "$out" && ok "7a ledger.py lift refuses a decision" || bad "7a rc=$rc: $out"
out=$(cd "$W" && python3 "$S/ledger.py" lift TD-004 --gate "event (landed)" --by testhost --evidence o/oth#4 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "refused, nothing written" <<< "$out" && [ -z "$(git -C "$W" status --porcelain)" ] \
  && ok "7b ... and evidence that is not its own check's" || bad "7b rc=$rc: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
