#!/usr/bin/env bash
# check_cadence.py — the cadence check (cadence §4, 2026-09-11). Fully offline:
# `gh` is a PATH shim answering from JSON fixtures written per case; git state
# comes from a real clone with a bare origin (worktree/pushed rows are defined
# against origin/main, so a fixture without a remote would test something else).
# Timestamps are derived from the run date (TD-24), never hardcoded.
set -u
export TZ=UTC  # TD-209: `date -d 'N days'` from now is N×24h, an hour short across DST; UTC has none, and the scripts under test inherit it
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/check_cadence.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAKE="$TMP/fake"; BIN="$TMP/bin"; mkdir -p "$FAKE" "$BIN"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- fake gh: dispatches on the argv shape the script uses --------------------
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
F="$FAKE_DIR"
case "$1 $2" in
  "pr view")   cat "$F/pr_$3.json" ;;
  "pr list")
     for a in "$@"; do [ "$a" = "--head" ] && { cat "$F/prlist_head.json"; exit 0; }; done
     cat "$F/prlist_since.json" ;;
  "api "*|"api --paginate")
     p=""; for a in "$@"; do case "$a" in repos/*) p="$a";; esac; done
     case "$p" in
       */issues/*/comments) n=${p#*/issues/}; n=${n%%/*}
          [ -f "$F/ratelimit" ] && { echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1; }
          cat "$F/comments_$n.json" ;;
       */actions/runs*) [ -f "$F/wfruns.json" ] && python3 -c 'import json,sys; [print(json.dumps(r)) for r in json.load(open(sys.argv[1]))]' "$F/wfruns.json" || { echo "gh: HTTP 404" >&2; exit 1; } ;;
       */actions/workflows) [ -f "$F/workflows" ] && cat "$F/workflows" || { echo "gh: HTTP 404" >&2; exit 1; } ;;
       */check-runs/*/annotations) i=${p#*/check-runs/}; i=${i%%/*}; [ -f "$F/annotations_$i.json" ] && cat "$F/annotations_$i.json" || { echo "gh: HTTP 404" >&2; exit 1; } ;;
       */commits/*/check-runs*) s=${p#*/commits/}; s=${s%%/*}
          [ -f "$F/checks_forbidden" ] && { cat "$F/checks_forbidden" >&2; exit 1; }   # TD-156
          [ -f "$F/checks_$s.json" ] && python3 -c 'import json,sys; [print(json.dumps(r)) for r in json.load(open(sys.argv[1]))["check_runs"]]' "$F/checks_$s.json" || { echo "gh: HTTP 422: No commit found for SHA: $s" >&2; exit 1; } ;;
       */commits/*/status\?*) s=${p#*/commits/}; s=${s%%/*}   # TD-117: none unless a case writes them
          [ -f "$F/status_unreadable" ] && { echo "gh: HTTP 502" >&2; exit 1; }
          [ -f "$F/statuses_$s.json" ] && python3 -c 'import json,sys; [print(json.dumps(r)) for r in json.load(open(sys.argv[1]))["statuses"]]' "$F/statuses_$s.json"; exit 0 ;;
       */commits/*) s=${p#*/commits/}; cat "$F/commit_$s.json" ;;
       */rules/branches/*)   # TD-178: rulesets; none unless a case writes them
          [ -f "$F/plan_lacks" ] && { echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1; }
          [ -f "$F/rules_unreadable" ] && { echo "gh: HTTP 502" >&2; exit 1; }
          [ -f "$F/rules.json" ] && python3 -c 'import json,sys; [print(json.dumps(r)) for r in json.load(open(sys.argv[1]))]' "$F/rules.json"; true ;;
       */branches/*)         # TD-178: the branch and its protection; unprotected unless a case writes one
          [ -f "$F/branch.json" ] && cat "$F/branch.json" || echo '{"name":"main","protected":false,"protection":{"enabled":false,"required_status_checks":{"enforcement_level":"off","contexts":[],"checks":[]}}}' ;;
       *) echo "gh-shim: unhandled api $p" >&2; exit 64 ;;
     esac ;;
  *) echo "gh-shim: unhandled: $*" >&2; exit 64 ;;
esac
SHIM
chmod +x "$BIN/gh"
export FAKE_DIR="$FAKE"
export PATH="$BIN:$PATH"

# --- time fixtures derived from now ----------------------------------------------
ts() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }
MERGED=$(ts "2 hours ago"); BEFORE=$(ts "3 hours ago"); AFTER=$(ts "1 hour ago")

# --- git fixture ------------------------------------------------------------------
R="$TMP/repo"
git init -q --bare -b main "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
( cd "$R" && git config user.email t@t && git config user.name t && git checkout -q -b main 2>/dev/null \
  && mkdir -p docs scripts && echo base > base.txt && printf '# ledger\n' > docs/technical_debt.md \
  && git add . && git commit -qm base && git push -q -u origin main )
mkwt() { git -C "$R" worktree add -q -b "$1" "$R/.claude/worktrees/$1" origin/main; }
squash() { ( cd "$R" && git merge -q --squash "$1" >/dev/null && git commit -qm "$1 (#1)" && git push -q origin main && git fetch -q origin ); }

# --- PR fixture writer ------------------------------------------------------------
# pr <n> <state> <branch> <title> [files...]   (BASE=… and BODY=… override the defaults)
pr() {
  local n=$1 state=$2 br=$3 title=$4; shift 4
  local files="" ; for f in "$@"; do files="$files{\"path\":\"$f\"},"; done; files="[${files%,}]"
  local merged='null' mc='null'
  if [ "$state" = MERGED ]; then merged="\"$MERGED\""; mc='{"oid":"mmm1111"}'; fi
  cat > "$FAKE/pr_$n.json" <<J
{"number":$n,"url":"https://x/pr/$n","state":"$state","title":"$title","body":"${BODY:-}","baseRefName":"${BASE:-main}","headRefName":"$br","headRefOid":"hhh2222","mergedAt":$merged,"mergeCommit":$mc,"files":$files}
J
}
comments() { local n=$1; shift; printf '[%s]' "$(IFS=,; echo "$*")" > "$FAKE/comments_$n.json"; }
c() { printf '{"body":"%s","created_at":"%s","updated_at":"%s","user":{"login":"t"}}' "$1" "$2" "$3"; }
echo '{"parents":[{"sha":"a"}]}' > "$FAKE/commit_mmm1111.json"
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"},{"name":"lint","status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"

run() { ( cd "$R" && python3 "$SCRIPT" "$@" 2>&1 ); }
rowstat() { echo "$1" | awk -v r="$2" '$2==r {print $1}'; }

# --- 1) merged, reviewed before merge, ledger touched, worktree gone -> PASS rc 0
pr 1 MERGED td001-x "TD-001: fix" docs/technical_debt.md src/a.py
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '\[PASS\]' && ok "clean merged PR passes (rc 0)" || bad "clean merged PR: rc=$rc
$out"
[ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "self-attested" && ok "review row says self-attested" || bad "review row: $out"

# --- 2) no review comment -> review FAIL rc 1
comments 1
out=$(run --pr 1); rc=$?
[ $rc -eq 1 ] && [ "$(rowstat "$out" review)" = FAIL ] && ok "missing review comment fails" || bad "missing review: rc=$rc $out"

# --- 3) review posted after the merge -> FAIL
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$AFTER" "$AFTER")"
out=$(run --pr 1); rc=$?; [ $rc -eq 1 ] && [ "$(rowstat "$out" review)" = FAIL ] && echo "$out" | grep -q "merged with no review" && ok "review after merge fails" || bad "review after merge: rc=$rc $out"
# TD-076: that fail can never clear, so it is marked — text and JSON — for a caller that acts
# on a repeated fail. Still a fail, still rc 1: acknowledged is not forgiven.
echo "$out" | grep -q "^  FAIL    review    acknowledged" && echo "$out" | grep -q "^ACKNOWLEDGED: 1 of 1 failing PR(s).*#1" && ok "a late review is an acknowledged fail (text)" || bad "acknowledged text: $out"
out=$(run --pr 1 --json); rc=$?
echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=[x for x in d["prs"][0]["rows"] if x["rule"]=="review"][0]; assert r["status"]=="fail" and r["acknowledged"] is True and d["acknowledged"]==[1] and d["verdict"]=="fail"' && [ $rc -eq 1 ] && ok "a late review is an acknowledged fail (json), rc 1" || bad "acknowledged json: rc=$rc $out"
# a late BLOCK is something to act on: a plain fail, never acknowledged
comments 1 "$(c 'cadence-review: BLOCK · sonnet · code · 1 finding' "$AFTER" "$AFTER")"
out=$(run --pr 1 --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=[x for x in d["prs"][0]["rows"] if x["rule"]=="review"][0]; assert r["status"]=="fail" and "acknowledged" not in r and "acknowledged" not in d and "late one says BLOCK" in r["detail"]' && ok "a late BLOCK is a plain fail, not acknowledged" || bad "late BLOCK: $out"
# no comment at all is a fail a session CAN act on: never marked
comments 1
out=$(run --pr 1 --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); r=[x for x in d["prs"][0]["rows"] if x["rule"]=="review"][0]; assert r["status"]=="fail" and "acknowledged" not in r and "acknowledged" not in d' && ok "a missing review is a plain fail, not acknowledged" || bad "plain fail marked: $out"
# a review before the merge plus a comment after it: the one before decides, as it did
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$BEFORE")" "$(c 'cadence-review: FIXED · opus (author) · code · note' "$AFTER" "$AFTER")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = PASS ] && ! echo "$out" | grep -q "acknowledged\|opus" && ok "a post-merge comment beside a pre-merge review changes nothing" || bad "post-merge extra: $out"
# an acknowledged fail beside another fail: the PR is not in the acknowledged list
pr 8 MERGED td008-q "TD-008: fix" src/a.py; comments 8 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$AFTER" "$AFTER")"
out=$(run --pr 8 --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); rows={x["rule"]:x for x in d["prs"][0]["rows"]}; assert rows["ledger"]["status"]=="fail" and rows["review"].get("acknowledged") and "acknowledged" not in d' && ok "an acknowledged fail beside a real one leaves the PR actionable" || bad "mixed fails: $out"

# --- 4) review created before but edited after the merge -> FAIL (the edit loophole)
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$AFTER")"
out=$(run --pr 1); echo "$out" | grep -q "edited after the merge" && ok "review edited after merge fails" || bad "edited after merge: $out"

# --- 5) latest review says BLOCK -> FAIL; an older SHIP does not rescue it
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$(ts '4 hours ago')" "$(ts '4 hours ago')")" "$(c 'cadence-review: BLOCK · sonnet · code · 2 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); echo "$out" | grep -q "says BLOCK" && ok "BLOCK verdict fails" || bad "BLOCK: $out"

# --- 6) verdict word is case-insensitive and FIXED passes
comments 1 "$(c 'cadence-review: fixed · sonnet · docs · 2 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = PASS ] && ok "FIXED passes" || bad "FIXED: $out"

# --- 6b) TD-116: a verdict outside SHIP/FIXED/BLOCK is never a review, and the row says so
comments 1 "$(c 'cadence-review: CLEAN · sonnet · docs · 0 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); rc=$?
[ $rc -eq 1 ] && [ "$(rowstat "$out" review)" = FAIL ] && echo "$out" | grep -q "a review comment says CLEAN: the verdict is SHIP, FIXED or BLOCK. Post a new one." \
  && ok "a CLEAN-only review fails, naming the word and the cure" || bad "CLEAN only: rc=$rc $out"
comments 1 "$(c 'notes first\ncadence-review: CLEAN · sonnet · docs' "$BEFORE" "$BEFORE")" "$(c 'cadence-review: LGTM' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); echo "$out" | grep -q "2 review comments say CLEAN / LGTM: the verdict is" && ok "several odd verdicts are each named" || bad "odd several: $out"
comments 1 "$(c 'cadence-review: CLEAN · sonnet · docs' "$(ts '4 hours ago')" "$(ts '4 hours ago')")" "$(c 'cadence-review: SHIP · sonnet · docs · 0 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); line=$(echo "$out" | awk '$2=="review"')
[ "$(rowstat "$out" review)" = PASS ] && echo "$line" | grep -q "review    SHIP · sonnet" && echo "$line" | grep -q "1 not read, its verdict not SHIP, FIXED or BLOCK: CLEAN" \
  && ok "a stale CLEAN beside a real review: the review passes, the CLEAN is listed" || bad "CLEAN beside SHIP: $line"
comments 1 "$(c 'cadence-review: BLOCKED · sonnet · code' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = FAIL ] && echo "$out" | grep -q "says BLOCKED: the verdict is" && ok "BLOCKED is not BLOCK, and not a pass" || bad "BLOCKED: $out"
# TD-076: the row names the FIRST review; the author's follow-up is listed, never the review
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 2 findings' "$(ts '4 hours ago')" "$(ts '4 hours ago')")" "$(c 'cadence-review: FIXED · opus (author) · code · 2 findings addressed' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); line=$(echo "$out" | awk '$2=="review"')
[ "$(rowstat "$out" review)" = PASS ] && echo "$line" | grep -q "review    SHIP · sonnet · code · 2 findings · 120 min before merge; then 1 later, not the review: FIXED · opus (author)" \
  && ok "review row names the first comment, lists the later one" || bad "first review: $line"
# …and a BLOCK the reviewer later lifts passes, named as the BLOCK it was
comments 1 "$(c 'cadence-review: BLOCK · sonnet · code · 2 findings' "$(ts '4 hours ago')" "$(ts '4 hours ago')")" "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "BLOCK · sonnet · code · 2 findings · .*then 1 later.*SHIP" && ok "a lifted BLOCK passes and both are named" || bad "lifted BLOCK: $out"
# the first of two comments edited after the merge is still the edit loophole
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$(ts '4 hours ago')" "$AFTER")" "$(c 'cadence-review: FIXED · opus · code · 0' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); echo "$out" | grep -q "edited after the merge" && ok "the first review edited after the merge fails" || bad "first edited: $out"
# TD-087: a report that ends with its verdict is a review; several verdict lines, the last decides;
# a verdict mentioned mid-line is prose, not a review
comments 1 "$(c 'Findings:\n1. none\n\ncadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "review    SHIP · sonnet · code · 0 findings" && ok "a verdict on the comment's last line passes" || bad "last-line verdict: $out"
comments 1 "$(c 'cadence-review: BLOCK · sonnet · code · 1 finding\nfixed it:\n  cadence-review: FIXED · sonnet · code · 1 finding' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "review    FIXED · sonnet · code · 1 finding" && ok "of two verdict lines in one comment, the last is read" || bad "two verdict lines: $out"
# TD-211: the evidence comment's signature line (cadence §4.9) is no verdict and names no reviewer
comments 1 "$(c 'cadence-review: FIXED · sonnet · code · 1 finding\n- fixed\n\n— ac-grinder (claude-code/claude-opus-5-5)' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); line=$(echo "$out" | awk '$2=="review"')
[ "$(rowstat "$out" review)" = PASS ] && echo "$line" | grep -q "review    FIXED · sonnet · code · 1 finding" && ! echo "$line" | grep -q "ac-grinder" \
  && ok "a signed evidence comment reads as its verdict line alone" || bad "signed comment: $line"
comments 1 "$(c 'the reviewer will post cadence-review: SHIP · sonnet · code · 0 here' "$BEFORE" "$BEFORE")"
out=$(run --pr 1); [ "$(rowstat "$out" review)" = FAIL ] && ok "a verdict mentioned mid-line is not a review" || bad "mid-line verdict: $out"
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$BEFORE")"

# --- 7) TD in title, ledger untouched -> ledger FAIL; no TD in title -> NA; body mentions ignored
pr 2 MERGED td002-y "TD-002: fix" src/a.py; comments 2 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
out=$(run --pr 2); [ "$(rowstat "$out" ledger)" = FAIL ] && ok "TD named, ledger untouched fails" || bad "ledger: $out"
pr 3 MERGED chore "tidy imports" src/a.py; comments 3 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
out=$(run --pr 3); [ "$(rowstat "$out" ledger)" = NA ] && ok "no TD in title is n/a" || bad "ledger na: $out"
pr 4 MERGED td004-z "TD-4 and TD-005: two" docs/technical_debt_archive.md; comments 4 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
out=$(run --pr 4); echo "$out" | grep -q "TD-004, TD-005 named; touches docs/technical_debt_archive.md" && ok "TD refs canonicalised, archive counts" || bad "canon: $out"

# --- 8) two-parent merge commit -> pr FAIL
echo '{"parents":[{"sha":"a"},{"sha":"b"}]}' > "$FAKE/commit_mmm1111.json"
out=$(run --pr 1); [ "$(rowstat "$out" pr)" = FAIL ] && ok "merge commit with two parents fails" || bad "two parents: $out"
echo '{"parents":[{"sha":"a"}]}' > "$FAKE/commit_mmm1111.json"

# --- 9) check runs gone (deleted head) -> ci UNKNOWN, not fail — and rc 3, never 0 (TD-041:
# the old rc 0 here let "merge only on exit 0" merge on no CI evidence at all)
mv "$FAKE/checks_hhh2222.json" "$FAKE/checks.bak"
out=$(run --pr 1); rc=$?
[ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && echo "$out" | grep -q '\[UNKNOWN\]' && ok "missing check runs are unknown, rc 3" || bad "ci unknown: rc=$rc $out"
mv "$FAKE/checks.bak" "$FAKE/checks_hhh2222.json"
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"failure"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = FAIL ] && ok "red check run fails" || bad "ci red: $out"
echo '{"check_runs":[]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = NA ] && ok "no check runs is n/a" || bad "ci na: $out"
# TD-079: on an OPEN PR "no check run listed" is na only when nothing says one is coming.
# upd <n> <when>: stamp the fixture PR's updatedAt (the shim's pr view serves the file as is).
upd() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["updatedAt"]=sys.argv[2]; json.dump(d,open(p,"w"))' "$FAKE/pr_$1.json" "$2"; }
cirow() { echo "$1" | awk '$2=="ci"'; }
pr 30 OPEN topic30 "open, no checks yet" src/a.py; comments 30 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
upd 30 "$(ts '20 seconds ago')"
out=$(run --pr 30); rc=$?; [ "$(rowstat "$out" ci)" = NA ] && [ $rc -eq 0 ] && ok "ci: an open PR, no check runs, gh says nothing about workflows: n/a as before" || bad "ci open plain: rc=$rc $(cirow "$out")"
echo 1 > "$FAKE/workflows"
out=$(run --pr 30); rc=$?; [ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && cirow "$out" | grep -q "too early to call it no CI" && ok "ci: just pushed, the repo has a workflow, no run listed yet: unknown, rc 3 — never a merge-on-0" || bad "ci grace: rc=$rc $(cirow "$out")"
upd 30 "$(ts '10 minutes ago')"
out=$(run --pr 30); rc=$?; [ "$(rowstat "$out" ci)" = NA ] && [ $rc -eq 0 ] && ok "ci: past the grace with still no run, it is n/a — a repo whose workflows skip PRs is not locked out" || bad "ci past grace: rc=$rc $(cirow "$out")"
echo 0 > "$FAKE/workflows"; upd 30 "$(ts '20 seconds ago')"
out=$(run --pr 30); [ "$(rowstat "$out" ci)" = NA ] && ok "ci: just pushed in a repo with no active workflow: n/a" || bad "ci no workflows: $(cirow "$out")"
# a workflow run registered for the head, its check run not listed yet: unknown whatever the age
upd 30 "$(ts '10 minutes ago')"; echo '[{"status":"queued","conclusion":null}]' > "$FAKE/wfruns.json"
out=$(run --pr 30); rc=$?; [ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && cirow "$out" | grep -q "1 workflow run(s) registered for hhh2222 with no check run listed yet" && ok "ci: a registered workflow run with no check run yet is unknown" || bad "ci registered: rc=$rc $(cirow "$out")"
echo '[{"status":"completed","conclusion":"startup_failure"}]' > "$FAKE/wfruns.json"
out=$(run --pr 30); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ended (startup_failure) without a check run" && ok "ci: a workflow run that ended with no check run is unknown, and says to look" || bad "ci startup failure: $(cirow "$out")"
# a MERGED PR is history: the window is long past, the row is n/a as it was
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = NA ] && ok "ci: a merged PR with no check runs stays n/a (no grace on history)" || bad "ci merged na: $(cirow "$out")"
rm -f "$FAKE/wfruns.json" "$FAKE/workflows"
echo '{"check_runs":[{"name":"test","status":"in_progress","conclusion":null}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); rc=$?; [ "$(rowstat "$out" ci)" = UNKNOWN ] && echo "$out" | grep -q "still running" && [ $rc -eq 3 ] && ok "unfinished check run is unknown, rc 3 — not fail, not pass" || bad "ci pending: rc=$rc $out"
out=$(run --pr 1 --json); rc=$?
echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["verdict"]=="unknown" and d["prs"][0]["verdict"]=="unknown"' 2>/dev/null && [ $rc -eq 3 ] \
  && ok "--json: one unknown row makes the PR and the run unknown" || bad "ci pending json: rc=$rc $out"

# A SKIPPED check must not fail the row — a job a workflow deliberately gates off cannot be
# a merge blocker — but it must not read as "green" either. Found live 2026-09-18: a consumer
# turned CI on for pull requests, its two heavy jobs are gated behind a credential probe, and
# the row said "4 check run(s) green" for a commit where the suite never ran.
echo '{"check_runs":[{"name":"Lint","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"skipped"},{"name":"Typecheck","status":"completed","conclusion":"skipped"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); rc=$?
[ "$(rowstat "$out" ci)" = PASS ] && [ $rc -eq 0 ] && ok "a skipped check does not fail the row" || bad "ci skip status: rc=$rc $out"
echo "$out" | grep -q "NOT RUN" && echo "$out" | grep -q "Test" && echo "$out" | grep -q "Typecheck" \
  && ok "a skipped check is named, not counted as green" || bad "ci skip wording: $out"
echo "$out" | grep -q "1 green" && ok "only the checks that ran are counted green" || bad "ci skip count: $out"

# ALL skipped is a different thing from some skipped: nothing ran, so there is no evidence,
# and a session that self-merges on this row would otherwise read a misconfigured trigger
# exactly as it reads a clean suite. `unknown` is what this file reserves for no-evidence.
# Raised by PR #90's reviewer, who argued the boundary case back at the fix for the mixed one.
echo '{"check_runs":[{"name":"Test","status":"completed","conclusion":"skipped"},{"name":"Typecheck","status":"completed","conclusion":"skipped"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); rc=$?
[ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && ok "an all-skipped workflow is unknown (rc 3), not pass" || bad "ci all-skipped: rc=$rc $out"
echo "$out" | grep -q "no check ran" && ok "an all-skipped workflow says nothing ran" || bad "ci all-skipped wording: $out"

# A check run with no `name` must not crash the row. Every other branch reaches a name only
# for a run it is already reporting, so this was impossible before the message change; it is
# a property worth keeping rather than a shape GitHub actually sends.
echo '{"check_runs":[{"status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); rc=$?
[ "$(rowstat "$out" ci)" = PASS ] && [ $rc -eq 0 ] && ok "a nameless check run does not crash the row" || bad "ci nameless: rc=$rc $out"

# The control: with nothing skipped the message keeps its old shape, so the branch above
# cannot pass by rewording every run.
echo '{"check_runs":[{"name":"Lint","status":"completed","conclusion":"success"},{"name":"Test","status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1)
echo "$out" | grep -q "2 check run(s) green" && ! echo "$out" | grep -q "NOT RUN" \
  && ok "an all-green run is unchanged" || bad "ci all-green wording: $out"

# TD-115: a job GitHub Actions refused to start (billing / spending limit) is reported as
# conclusion "failure" with no steps; only its annotation says why. Shaped like the API's
# answer, trimmed to the fields read: Lint and Setup refused, Test and Typecheck skipped
# behind them. It is no evidence, not a red build.
cat > "$FAKE/checks_hhh2222.json" <<'J'
{"total_count":4,"check_runs":[
 {"id":1001,"name":"Test","status":"completed","conclusion":"skipped","output":{"title":null,"summary":null,"text":null,"annotations_count":0}},
 {"id":1002,"name":"Typecheck","status":"completed","conclusion":"skipped","output":{"title":null,"summary":null,"text":null,"annotations_count":0}},
 {"id":1003,"name":"Setup","status":"completed","conclusion":"failure","output":{"title":null,"summary":null,"text":null,"annotations_count":2}},
 {"id":1004,"name":"Lint","status":"completed","conclusion":"failure","output":{"title":null,"summary":null,"text":null,"annotations_count":2}}]}
J
NOTSTARTED='[{"path":".github","start_line":1,"end_line":1,"annotation_level":"failure","title":"","message":"The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the '"'"'Billing & plans'"'"' section in your settings","raw_details":""},{"path":".github","start_line":1,"end_line":1,"annotation_level":"notice","title":"","message":"A newer runner image is available.","raw_details":""}]'
echo "$NOTSTARTED" > "$FAKE/annotations_1003.json"; echo "$NOTSTARTED" > "$FAKE/annotations_1004.json"
out=$(run --pr 1); rc=$?
[ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && cirow "$out" | grep -q "never ran — GitHub did not start the job: The job was not started because recent account payments have failed or your spending limit needs to be increased (the account's billing or spending limit" \
  && cirow "$out" | grep -q "Setup, Lint on hhh2222" \
  && ok "ci: jobs GitHub refused to start (billing) are unknown with the reason, rc 3 — not a red build" || bad "ci not started: rc=$rc $(cirow "$out")"
# the control: a failed run whose annotations say something else stays red — and so does one
# whose annotations cannot be read
echo '[{"annotation_level":"failure","message":"Process completed with exit code 1."}]' > "$FAKE/annotations_1004.json"
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = FAIL ] && cirow "$out" | grep -q "not green on hhh2222: Lint" && ! cirow "$out" | grep -q Setup \
  && ok "ci: a failed run with an ordinary annotation is still red" || bad "ci ordinary annotation: $(cirow "$out")"
rm "$FAKE/annotations_1004.json"
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = FAIL ] && cirow "$out" | grep -q "not green on hhh2222: Lint" \
  && ok "ci: a failed run whose annotations are unreadable is still red" || bad "ci unreadable annotations: $(cirow "$out")"
rm -f "$FAKE"/annotations_*.json

# TD-117: precheck. A repo with `precheck` in docs/cadence.toml is judged on an OPEN PR by the
# cadence/precheck commit status precheck.py records; commit statuses are read beside check runs.
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"
rm -f "$FAKE/workflows" "$FAKE/wfruns.json"
st() { printf '{"statuses":[{"context":"%s","state":"%s","description":"d"}]}' "$1" "$2" > "$FAKE/statuses_hhh2222.json"; }
pr 31 OPEN topic31 "open, precheck" src/a.py; comments 31 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
printf 'precheck = "make check"\n' > "$R/docs/cadence.toml"
out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && cirow "$out" | grep -q "precheck is set (docs/cadence.toml) and hhh2222 carries no cadence/precheck status — run scripts/precheck.py --pr 31" \
  && ok "ci: precheck set, an open PR's head has no cadence/precheck status: unknown, naming the command to run — CI green is not enough" || bad "ci precheck missing: rc=$rc $(cirow "$out")"
out=$(CADENCE_REPO_ROOT="$R" run --pr 31)
cirow "$out" | grep -q "carries no cadence/precheck status — run agent-cadence run precheck.py --pr 31" \
  && ok "ci: from a pin, the command named is the launcher's word (TD-164)" || bad "ci precheck pinned hint: $(cirow "$out")"
st cadence/precheck success; out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = PASS ] && [ $rc -eq 0 ] && cirow "$out" | grep -q "2 check run(s) green" \
  && ok "ci: a cadence/precheck success status passes the row, read beside the check runs" || bad "ci precheck success: rc=$rc $(cirow "$out")"
st cadence/precheck failure; out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = FAIL ] && [ $rc -eq 1 ] && cirow "$out" | grep -q "not green on hhh2222: cadence/precheck" \
  && ok "ci: a failed precheck fails the row — the merge waits" || bad "ci precheck failure: rc=$rc $(cirow "$out")"
st cadence/precheck pending; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "still running on hhh2222: cadence/precheck" \
  && ok "ci: a pending status is still running" || bad "ci status pending: $(cirow "$out")"
st other/ci error; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "carries no cadence/precheck" \
  && ok "ci: another context's status does not stand in for precheck" || bad "ci other status: $(cirow "$out")"
touch "$FAKE/status_unreadable"; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "unreadable" \
  && ok "ci: statuses that cannot be read are unknown, never an empty list" || bad "ci status unreadable: $(cirow "$out")"
rm -f "$FAKE/status_unreadable" "$FAKE/statuses_hhh2222.json"
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: a MERGED PR is not asked for a precheck it may predate" || bad "ci merged precheck: $(cirow "$out")"
printf 'precheck = [\n' > "$R/docs/cadence.toml"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "cannot tell whether a precheck is required" \
  && ok "ci: an unreadable docs/cadence.toml is unknown, never read as no precheck" || bad "ci precheck unreadable cfg: $(cirow "$out")"
printf 'ledger-ids-host = "on"\n' > "$R/docs/cadence.toml"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: no precheck set: the row reads as before" || bad "ci no precheck: $(cirow "$out")"
rm -f "$R/docs/cadence.toml"

_out=$out   # the TD-148 block below reads PR 31's run above
# TD-186: run from a checkout of the PR's branch whose tip the forge's head lacks (a push it has
# not seen yet), the row is unknown — a stale head's green is not the PR's
git -C "$R" checkout -q -b topic32 origin/main
echo a > "$R/a32.txt"; git -C "$R" add a32.txt; git -C "$R" commit -qm a32; A32=$(git -C "$R" rev-parse HEAD)
echo b > "$R/b32.txt"; git -C "$R" add b32.txt; git -C "$R" commit -qm b32; B32=$(git -C "$R" rev-parse HEAD)
pr 32 OPEN topic32 "open, just pushed" a32.txt; comments 32 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
sed -i "s/hhh2222/$A32/" "$FAKE/pr_32.json"; cp "$FAKE/checks_hhh2222.json" "$FAKE/checks_$A32.json"
out=$(run --pr 32)
[ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "the forge's head ${A32:0:7} is not this checkout's topic32, at ${B32:0:7} — the PR has not caught up" \
  && ok "ci: the checkout's branch is ahead of the forge's head: unknown, naming both — never the stale head's green" || bad "ci unseen push: $(cirow "$out")"
git -C "$R" checkout -q main
out=$(run --pr 32); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: from another branch the head is judged as before" || bad "ci unseen push other branch: $(cirow "$out")"
git -C "$R" checkout -q topic32; git -C "$R" reset -q --hard "$A32"
out=$(run --pr 32); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: the checkout at the forge's head: judged as before" || bad "ci unseen push same: $(cirow "$out")"
git -C "$R" checkout -q main; git -C "$R" push -q origin "$B32:refs/heads/topic32"
out=$(run --pr 32); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "is not origin's topic32, at ${B32:0:7}" \
  && ok "ci: origin's branch ahead of the forge's head, from any checkout: unknown, naming both" || bad "ci origin ahead: $(cirow "$out")"
git -C "$R" push -q origin --delete topic32; git -C "$R" branch -q -D topic32; rm -f "$FAKE/checks_$A32.json"; out=$_out
# TD-178: the base branch's required checks decide an open PR's ci row, as ShiftLead's
# `done --pr` reads them: branch protection (read from the branch, no admin) and rulesets.
prot() { printf '{"name":"main","protected":true,"protection":{"enabled":true,"required_status_checks":{"enforcement_level":"everyone","contexts":["%s"],"checks":[{"context":"%s","app_id":null}]}}}' "$1" "$1" > "$FAKE/branch.json"; }
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"},{"name":"lint","status":"completed","conclusion":"failure"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = FAIL ] && cirow "$out" | grep -q "not green on hhh2222: lint" \
  && ok "ci (TD-178): nothing required: every run is judged, as before" || bad "ci nothing required: $(cirow "$out")"
prot test; out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = PASS ] && cirow "$out" | grep -q "judged on what main requires (test); not required, not green: lint" \
  && ok "ci (TD-178): the required check passed, one nothing requires failed: pass, the failed one named" || bad "ci required pass: rc=$rc $(cirow "$out")"
prot lint; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = FAIL ] && cirow "$out" | grep -q "not green on hhh2222: lint; judged on what main requires (lint)" \
  && ok "ci (TD-178): a required check failed: fail" || bad "ci required fail: $(cirow "$out")"
prot e2e; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "main requires e2e, not reported on hhh2222" \
  && ok "ci (TD-178): a required check that never reported: unknown — the forge holds the merge for it" || bad "ci required missing: $(cirow "$out")"
rm -f "$FAKE/branch.json"
echo '[{"type":"deletion"},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"test"}]}}]' > "$FAKE/rules.json"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && cirow "$out" | grep -q "judged on what main requires (test); not required, not green: lint" \
  && ok "ci (TD-178): a ruleset's required_status_checks is read too" || bad "ci ruleset: $(cirow "$out")"
printf 'precheck = "make check"\n' > "$R/docs/cadence.toml"; st cadence/precheck failure
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = FAIL ] && cirow "$out" | grep -q "not green on hhh2222: cadence/precheck" \
  && ok "ci (TD-178): the precheck still gates when the forge requires something else" || bad "ci required + precheck: $(cirow "$out")"
rm -f "$R/docs/cadence.toml" "$FAKE/statuses_hhh2222.json" "$FAKE/rules.json"
touch "$FAKE/plan_lacks"; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = FAIL ] && cirow "$out" | grep -q "not green on hhh2222: lint" \
  && ok "ci (TD-178): the plan's 403 (no rulesets on a private free repo) reads as nothing required" || bad "ci plan 403: $(cirow "$out")"
rm -f "$FAKE/plan_lacks"; touch "$FAKE/rules_unreadable"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "the checks main requires are unreadable (gh: HTTP 502)" \
  && ok "ci (TD-178): a required set that cannot be read is unknown, never a pass" || bad "ci required unreadable: $(cirow "$out")"
rm -f "$FAKE/rules_unreadable"
out=$(run --pr 1); [ "$(rowstat "$out" ci)" = FAIL ] && ok "ci (TD-178): a MERGED PR is judged on every run, as before" || bad "ci merged required: $(cirow "$out")"
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 31)   # the open PR with no precheck, as the next case reads it

# TD-148: the detector. On an OPEN PR the ci row names a repo with no precheck and each TRACKED
# workflow that runs on every pull_request or push to the default branch — never in its verdict.
cirow "$out" | grep -qF "⚠ no \`precheck\` in docs/cadence.toml" \
  && ok "ci: no precheck on an open PR: a ⚠ says set it, and the verdict stands" || bad "ci no-precheck warn: $(cirow "$out")"
out=$(run --pr 1); ! cirow "$out" | grep -q "⚠" && ok "ci: a MERGED PR carries no TD-148 warning" || bad "ci merged warn: $(cirow "$out")"
mkdir -p "$R/.github/workflows"
printf 'name: ci\non:\n  pull_request:\n  push:\n    branches: [main]\njobs: {}\n' > "$R/.github/workflows/ci.yml"
printf 'on:\n  push:\n    tags: ["v*"]\n  workflow_dispatch:\n' > "$R/.github/workflows/release.yml"
printf 'on: [pull_request]\n' > "$R/.github/workflows/stray.yml"   # never added: not the repo's
git -C "$R" add .github/workflows/ci.yml .github/workflows/release.yml
printf 'precheck = "make check"\n' > "$R/docs/cadence.toml"; st cadence/precheck success
out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = PASS ] && [ $rc -eq 0 ] \
  && cirow "$out" | grep -qF "⚠ .github/workflows/ci.yml runs on every pull_request and push to main — trigger it by path, tag or hand" \
  && ! cirow "$out" | grep -q "release.yml\|stray.yml\|no \`precheck\`" \
  && ok "ci: a tracked workflow on every PR and push to main is named; a tag/dispatch one and an untracked one are not; the verdict stands" \
  || bad "ci workflow warn: rc=$rc $(cirow "$out")"
printf 'on:\n  pull_request:\n    paths: ["docs/**"]\n  workflow_dispatch:\n' > "$R/.github/workflows/ci.yml"
out=$(run --pr 31); ! cirow "$out" | grep -q "⚠" && ok "ci: a path-filtered workflow and a precheck: no warning" || bad "ci path filter: $(cirow "$out")"
# the shapes a block-only reader misses (review of #363): a flow mapping keeps its filters, a
# `!` branch pattern excludes, `types:` ends a filter list, and `- push` may sit at column 0
got=$(cd "$DC/files/scripts" && python3 -c '
import check_cadence as c
for t in ("on: {pull_request: {paths: [a]}, push: {tags: [v1]}}", "on:\n  push:\n    branches: [\"**\", \"!main\"]",
          "on:\n  push:\n    branches-ignore:\n      - x\n    types:\n      - main", "on:\n- push\n- pull_request\njobs: {}"):
    print(c.gating_events(c.workflow_triggers(t) or {}, "main"))')
[ "$got" = "$(printf '%s\n' '[]' '[]' "['push to main']" "['every pull_request', 'push to main']")" ] \
  && ok "ci: workflow triggers read in flow form, with a negated branch, past types:, and as a column-0 list" || bad "ci trigger shapes: $got"
FORKCI='on:
  pull_request:
  workflow_dispatch:
jobs:
  suite:
    if: github.event_name == '"'"'workflow_dispatch'"'"' || github.event.pull_request.head.repo.full_name != github.repository
    runs-on: ubuntu-latest
    steps:
      - if: always()
        run: true
  lint:
    if: ${{ github.event.pull_request.head.repo.full_name != github.repository }}
    runs-on: ubuntu-latest
'
# TD-207: a pull_request workflow whose every job's `if:` needs a fork's head runs on no same-repo
# PR (cadence.md §4.12's fork-only form): no ⚠. One job without it, or one that names the event, warns.
printf '%s' "$FORKCI" > "$R/.github/workflows/ci.yml"
out=$(run --pr 31); ! cirow "$out" | grep -q "⚠" && ok "ci (TD-207): a fork-only pull_request workflow: no warning" || bad "ci fork-only: $(cirow "$out")"
printf '%s  other:\n    runs-on: ubuntu-latest\n' "$FORKCI" > "$R/.github/workflows/ci.yml"
out=$(run --pr 31); cirow "$out" | grep -qF "⚠ .github/workflows/ci.yml runs on every pull_request" \
  && ok "ci (TD-207): one job with no fork condition: the workflow still warns" || bad "ci fork-only one job: $(cirow "$out")"
got=$(cd "$DC/files/scripts" && python3 -c '
import check_cadence as c
for x in ("github.event_name == \"pull_request\" || github.event.pull_request.head.repo.full_name != github.repository",
          "(github.event.pull_request.head.repo.full_name != github.repository) || true", "always()",
          "github.repository != github.event.pull_request.head.repo.full_name && github.actor != \"bot\"", "\"${{ github.event_name == '"'"'push'"'"' }}\""):
    print(c._fork_only_if(x))
print(c.fork_only("on: pull_request\njobs:\n  a:\n    if: >\n      github.event.pull_request.head.repo.full_name != github.repository\n"))
F = "github.event.pull_request.head.repo.full_name != github.repository"
print(c.fork_only(f"on: pull_request\njobs:\n  a:\n    if: {F}\n# a section\n  b:\n    runs-on: x\n"))
print(c.fork_only(f"on: pull_request\njobs:\n  a:\n    if: {F} &&\n      github.actor == x || true\n"))
print(c.fork_only(f"on: pull_request\njobs:\n  a:\n    if: {F} && contains(github.event.pull_request.title, \" #x\") || true\n"))
print(c.fork_only(f"on: pull_request\njobs:\n  a:\n    if: {F}\n# a section\n  b:\n    if: {F}\n    steps:\n      - if: always()\n"))')
[ "$got" = "$(printf '%s\n' False False False True True False False False False True)" ] \
  && ok "ci (TD-207): the fork condition read by its terms — the event named, a parenthesis, a narrowing &&, a block scalar, a job past a column-0 comment, a wrapped condition, a #" || bad "ci fork-only shapes: $got"
printf '%s' "$FORKCI" | sed 's/^  pull_request:$/  pull_request_target:/' > "$R/.github/workflows/ci.yml"
out=$(run --pr 31); ! cirow "$out" | grep -q "⚠" && ok "ci (TD-207): a fork-only pull_request_target workflow: no warning" || bad "ci fork-only target: $(cirow "$out")"
git -C "$R" reset -q -- .github; rm -rf "$R/.github" "$FAKE/statuses_hhh2222.json"
rm -f "$R/docs/cadence.toml"

# TD-156: a fine-grained token gets 403 on check-runs (it can hold no Checks permission) but reads
# commit statuses. They stand in only when they are the whole gate: precheck set, its status on the
# head, and no workflow AT THE HEAD (one the PR adds counts) that may post a check run on a PR.
# mkhead <ci.yml text or ""> prints a real commit on main with that workflow, main untouched.
mkhead() { ( cd "$R" && export GIT_INDEX_FILE="$TMP/idx156" && git read-tree HEAD \
  && { [ -z "$1" ] || git update-index --add --cacheinfo "100644,$(printf '%s' "$1" | git hash-object -w --stdin),.github/workflows/ci.yml"; } \
  && git commit-tree "$(git write-tree)" -p HEAD -m head ); }
at() { H=$1; sed -i "s/\"headRefOid\":\"[^\"]*\"/\"headRefOid\":\"$H\"/" "$FAKE/pr_31.json"; }
sth() { printf '{"statuses":[{"context":"%s","state":"%s","description":"d"}]}' "$1" "$2" > "$FAKE/statuses_$H.json"; }
echo 'gh: Resource not accessible by personal access token (HTTP 403)' > "$FAKE/checks_forbidden"
printf 'precheck = "make check"\n' > "$R/docs/cadence.toml"
at "$(mkhead "")"; sth cadence/precheck success
out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = PASS ] && [ $rc -eq 0 ] && cirow "$out" | grep -q "1 check run(s) green on ${H:0:7}.*check runs unreadable (.*HTTP 403.*the token lacks Checks) — judged on commit statuses" \
  && ok "ci: 403 on check-runs, a precheck success status and no workflow: passes, saying it was judged on statuses" || bad "ci 403 pass: rc=$rc $(cirow "$out")"
sth cadence/precheck failure; out=$(run --pr 31); rc=$?
[ "$(rowstat "$out" ci)" = FAIL ] && [ $rc -eq 1 ] && ok "ci: 403 on check-runs and a failed precheck: fails" || bad "ci 403 fail: rc=$rc $(cirow "$out")"
sth cadence/precheck success; prot test; out=$(run --pr 31)
[ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "main requires test, not reported on ${H:0:7} — among the commit statuses; its check runs are unreadable (the token lacks Checks)" \
  && ok "ci (TD-178): 403 on check-runs and a required check run: unknown, saying the runs were unreadable" || bad "ci 403 required: $(cirow "$out")"
rm -f "$FAKE/branch.json"
sth other/ci success; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "carries no cadence/precheck status" \
  && ok "ci: 403 on check-runs, no precheck status on the head: unknown" || bad "ci 403 no status: $(cirow "$out")"
at "$(mkhead 'on:
  workflow_dispatch:
')"; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: 403, a by-hand workflow only: still passes on the statuses" || bad "ci 403 dispatch: $(cirow "$out")"
# TD-163: every event outside the safe set (workflow_dispatch, schedule, workflow_call) counts — a
# run on issue_comment or workflow_run can post to any sha; a list nobody kept fails closed
at "$(mkhead 'on:
  schedule:
    - cron: "0 3 * * *"
  workflow_call:
  workflow_dispatch:
')"; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: 403, a workflow on schedule, workflow_call and by hand only: passes on the statuses" || bad "ci 403 safe set: $(cirow "$out")"
at "$(mkhead 'on: [workflow_dispatch,
  issue_comment]
')"; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" \
  && ok "ci: 403 and an on: list wrapped over lines: unread, so unknown — never the first line alone" || bad "ci 403 wrapped on: $(cirow "$out")"
for ev in pull_request_review issue_comment workflow_run create merge_group; do
  at "$(mkhead "on: [workflow_dispatch, $ev]
")"; sth cadence/precheck success
  out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" \
    && ok "ci: 403 and a workflow on $ev: unknown — it may post on the head" || bad "ci 403 $ev: $(cirow "$out")"
done
at "$(mkhead 'on:
  pull_request:
    paths: ["src/**"]
')"; sth cadence/precheck success
out=$(run --pr 31); rc=$?; [ "$(rowstat "$out" ci)" = UNKNOWN ] && [ $rc -eq 3 ] && cirow "$out" | grep -q "statuses alone cannot stand in — .github/workflows/ci.yml may post check runs" \
  && ok "ci: 403 and a workflow on pull_request (path-filtered) at the head — one the PR adds, not on main: unknown, naming it" || bad "ci 403 workflow: rc=$rc $(cirow "$out")"
at "$(mkhead 'name: no trigger this reads
')"; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" \
  && ok "ci: 403 and a workflow whose triggers cannot be read: unknown" || bad "ci 403 unreadable workflow: $(cirow "$out")"
# TD-207: a fork-only pull_request workflow skips its jobs on a same-repo PR (a skipped check run
# cannot fail it), so it stands in only when the forge says the PR is not a fork's
xr() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); v=sys.argv[2]
if v == "unset": d.pop("isCrossRepository", None)
else: d["isCrossRepository"] = v == "true"
json.dump(d, open(p, "w"), separators=(",", ":"))' "$FAKE/pr_31.json" "$1"; }
at "$(mkhead "$FORKCI")"; sth cadence/precheck success
xr false; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && cirow "$out" | grep -q "judged on commit statuses" \
  && ok "ci (TD-207): 403 and a fork-only workflow on a same-repo PR: passes on the statuses" || bad "ci 403 fork-only same repo: $(cirow "$out")"
xr true; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" \
  && ok "ci (TD-207): 403 and a fork-only workflow on a fork's PR: unknown — its jobs run there" || bad "ci 403 fork-only fork: $(cirow "$out")"
xr unset; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" \
  && ok "ci (TD-207): 403, a fork-only workflow, and a forge that does not say: unknown" || bad "ci 403 fork-only unsaid: $(cirow "$out")"
at "$(mkhead "$(printf '%s' "$FORKCI" | sed 's/^  pull_request:$/  pull_request_target:/')")"; sth cadence/precheck success
xr false; out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] \
  && ok "ci (TD-207): 403 and a fork-only pull_request_target workflow on a same-repo PR: passes on the statuses" || bad "ci 403 fork-only target: $(cirow "$out")"
xr unset
# the amendment: a push filtered to the default branch alone cannot post on a PR's head on another
# branch (a consumer's build-ci-image.yml shape) — exempt; any wider or looser filter still counts
CM='on:
  push:
    branches: [main]
    paths: ["Dockerfile"]
  workflow_dispatch:
'
at "$(mkhead "$CM")"; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && cirow "$out" | grep -q "judged on commit statuses" \
  && ok "ci: 403 and a push filtered to main alone (path-filtered, PR on another branch): passes on the statuses" || bad "ci 403 main-only push: $(cirow "$out")"
for t in 'branches: ["**"]' 'branches: [main, dev]' 'branches: [ma*]' 'branches: ["!dev", main]' $'branches: [main]\n    tags: [v*]' $'branches: [main]\n    branches-ignore: [x]' \
         $'branches: [main,\n      \'**\']' $'branches: [main]\n    "tags": [v*]' 'branches: [main'; do
  at "$(mkhead "on:
  push:
    $t
")"; sth cadence/precheck success
  out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" \
    && ok "ci: 403 and a push filter that is not main alone ($(echo "$t" | tr '\n' ' ')): unknown" || bad "ci 403 push filter $t: $(cirow "$out")"
done
at "$(mkhead "$CM  pull_request:
")"; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && ok "ci: 403, a main-only push beside a pull_request trigger: unknown" || bad "ci 403 main push + PR: $(cirow "$out")"
at "$(mkhead "$CM")"; sth cadence/precheck success; sed -i 's/"headRefName":"topic31"/"headRefName":"main","isCrossRepository":true/' "$FAKE/pr_31.json"   # a fork's main: not origin's (TD-186)
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" && ok "ci: 403, a main-only push and a PR whose head branch is main: unknown" || bad "ci 403 head main: $(cirow "$out")"
sed -i 's/"headRefName":"main"/"headRefName":"topic31"/' "$FAKE/pr_31.json"
OM=$(git -C "$R" rev-parse origin/main); git -C "$R" update-ref refs/remotes/origin/main "$H"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" && ok "ci: 403, a main-only push and a head already on main: unknown — it carries that push's checks" || bad "ci 403 head on main: $(cirow "$out")"
git -C "$R" update-ref -d refs/remotes/origin/main
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "ci.yml may post" && ok "ci: 403, a main-only push and no origin/main to verify the default against: unknown" || bad "ci 403 default unverified: $(cirow "$out")"
git -C "$R" update-ref refs/remotes/origin/main "$OM"
at hhh2222; sth cadence/precheck success
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "no clone holding hhh2222" \
  && ok "ci: 403 and a head this clone does not hold: unknown — its workflows cannot be read" || bad "ci 403 head missing: $(cirow "$out")"
at "$(mkhead "")"; sth cadence/precheck success
printf 'ledger-ids-host = "on"\n' > "$R/docs/cadence.toml"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "sets no \`precheck\`" \
  && ok "ci: 403 in a repo with no precheck: unknown — there is nothing to judge on instead" || bad "ci 403 no precheck: $(cirow "$out")"
printf 'precheck = "make check"\n' > "$R/docs/cadence.toml"
echo 'gh: API rate limit exceeded for user ID 1. (HTTP 403)' > "$FAKE/checks_forbidden"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "a deleted head reads this way" \
  && ok "ci: a rate-limit 403 is not a permission: unreadable as before" || bad "ci 403 rate limit: $(cirow "$out")"
echo 'gh: Resource not accessible by personal access token (HTTP 403)' > "$FAKE/checks_forbidden"; touch "$FAKE/status_unreadable"
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = UNKNOWN ] && cirow "$out" | grep -q "unreadable" && ! cirow "$out" | grep -q "judged on" \
  && ok "ci: 403 on check-runs and statuses unreadable too: unknown" || bad "ci 403 both: $(cirow "$out")"
rm -f "$FAKE/checks_forbidden" "$FAKE/status_unreadable" "$FAKE/statuses_$H.json" "$R/docs/cadence.toml"; at hhh2222
out=$(run --pr 31); [ "$(rowstat "$out" ci)" = PASS ] && ok "ci: TD-156 cases leave the fixture as they found it" || bad "ci 403 cleanup: $(cirow "$out")"

echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"

# --- 9b) merged PR whose mergedAt is null -> review UNKNOWN (never placed before a merge that has no time)
python3 - "$FAKE/pr_1.json" <<'P'
import json,sys; d=json.load(open(sys.argv[1])); d["mergedAt"]=None; json.dump(d, open(sys.argv[1],"w"))
P
out=$(run --pr 1); [ "$(rowstat "$out" review)" = UNKNOWN ] && echo "$out" | grep -q "no mergedAt" && ok "merged without mergedAt is unknown" || bad "null mergedAt: $out"
pr 1 MERGED td001-x "TD-001: fix" docs/technical_debt.md src/a.py

# --- 9b') a rate-limited comments call -> review UNKNOWN, rc 3 (a fail elsewhere still wins)
touch "$FAKE/ratelimit"
out=$(run --pr 1); rc=$?
[ "$(rowstat "$out" review)" = UNKNOWN ] && echo "$out" | grep -q "rate limit" && [ $rc -eq 3 ] && ok "rate-limited comments are unknown, rc 3" || bad "ratelimit: rc=$rc $out"
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"failure"}]}' > "$FAKE/checks_hhh2222.json"
out=$(run --pr 1); rc=$?; [ $rc -eq 1 ] && ok "a fail row beats an unknown row (rc 1)" || bad "fail+unknown: rc=$rc $out"
echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' > "$FAKE/checks_hhh2222.json"
rm "$FAKE/ratelimit"

# --- 9c) a comment missing a field is an unknown row, not a traceback
printf '[{"body":"cadence-review: SHIP · sonnet · code · 0"}]' > "$FAKE/comments_1.json"
out=$(run --pr 1); rc=$?; [ "$(rowstat "$out" review)" = UNKNOWN ] && ! echo "$out" | grep -q Traceback && ok "malformed comment is unknown, no traceback" || bad "malformed: rc=$rc $out"
comments 1 "$(c 'cadence-review: SHIP · sonnet · code · 0 findings' "$BEFORE" "$BEFORE")"

# --- 10) worktree after merge: gone -> pass; clean+landed -> pass (reapable); dirty -> fail; unlanded -> fail
mkwt td001-x; ( cd "$R/.claude/worktrees/td001-x" && echo w > w.txt && git add w.txt && git commit -qm w ); squash td001-x
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = PASS ] && echo "$out" | grep -q reapable && ok "clean landed worktree is reapable (pass)" || bad "reapable: $out"
# TD-059: main edits the landed file again — the strict test now says "not on main", but the
# content DID land (the squash's patch-id is the branch's own): pass, named as such
( cd "$R" && echo "edited on main" >> w.txt && git commit -qam "a later edit (#2)" && git push -q origin main && git fetch -q origin )
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = PASS ] && echo "$out" | grep -q "main has edited its files since" \
  && ok "landed, since edited on main: pass (TD-059), not 'not on main'" || bad "since-edited: $out"
# the exact path: the PR data names the real squash commit
setoid() { python3 - "$FAKE/pr_1.json" "$1" <<'P'
import json, sys
d = json.load(open(sys.argv[1])); d["mergeCommit"] = {"oid": sys.argv[2]}; json.dump(d, open(sys.argv[1], "w"))
P
echo '{"parents":[{"sha":"a"}]}' > "$FAKE/commit_$1.json"; }
SQ=$(git -C "$R" log --format=%H --grep='^td001-x (#1)$' -1 origin/main); setoid "$SQ"
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = PASS ] && echo "$out" | grep -q "main has edited its files since" \
  && ok "the PR's own squash (on main, same files): landed, since edited" || bad "exact squash: $out"
# a 'squash' that exists but was merged elsewhere, never on main: not landed
( cd "$R" && git checkout -q -b side "$(git merge-base origin/main td001-x)" && cp "$R/.claude/worktrees/td001-x/w.txt" w.txt \
  && git add w.txt && git commit -qm side && git checkout -q main )
setoid "$(git -C "$R" rev-parse side)"
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = FAIL ] && ok "a matching commit that is not on main does not count as landed" || bad "side squash: $out"
git -C "$R" branch -qD side; setoid "$SQ"
# main reverts it: landed, then undone — FAIL, never "done"
( cd "$R" && git rm -q w.txt && git commit -qm "revert td001-x (#3)" && git push -q origin main && git fetch -q origin )
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = FAIL ] && echo "$out" | grep -q "main has since reverted it" \
  && ok "landed and later reverted on main: fail, not cleared" || bad "reverted: $out"
( cd "$R" && git revert --no-edit HEAD >/dev/null && git commit -q --amend -m "re-land td001-x (#4)" && git push -q origin main && git fetch -q origin )
setoid mmm1111   # back to the fixture's merge oid, which later cases expect
echo scratch > "$R/.claude/worktrees/td001-x/notes.txt"
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = FAIL ] && echo "$out" | grep -q "untracked" && ok "dirty worktree after merge fails" || bad "dirty: $out"
rm "$R/.claude/worktrees/td001-x/notes.txt"
( cd "$R/.claude/worktrees/td001-x" && echo more > w.txt && git commit -qam more )
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = FAIL ] && echo "$out" | grep -q "not on origin/main" && ok "unlanded worktree after merge fails" || bad "unlanded: $out"
git -C "$R" worktree remove --force "$R/.claude/worktrees/td001-x"
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = PASS ] && ok "worktree gone (local branch kept) passes" || bad "gone: $out"
git -C "$R" branch -qD td001-x
# No local branch at all: the PR was made on another machine, whose worktree this check
# cannot see — n/a, never a pass (TD-041; the docstring always said na).
out=$(run --pr 1); [ "$(rowstat "$out" worktree)" = NA ] && echo "$out" | grep -q "not a local branch" && ok "another machine's branch is n/a, not pass" || bad "not local: $out"

# --- 11) open PR: pushed row — unpushed commit fails, pushed passes; worktree n/a
pr 5 OPEN topic5 "open work" src/a.py; comments 5 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
mkwt topic5; ( cd "$R/.claude/worktrees/topic5" && echo t > t.txt && git add t.txt && git commit -qm t )
out=$(run --pr 5); [ "$(rowstat "$out" pushed)" = FAIL ] && [ "$(rowstat "$out" worktree)" = NA ] && ok "open PR with unpushed commit fails pushed, worktree n/a" || bad "unpushed: $out"
( cd "$R/.claude/worktrees/topic5" && git push -q -u origin topic5 )
out=$(run --pr 5); rc=$?; [ "$(rowstat "$out" pushed)" = PASS ] && [ $rc -eq 0 ] && ok "pushed open PR passes" || bad "pushed: rc=$rc $out"

# --- 11b) closed without merging: says so, never "open PR"
pr 7 CLOSED topic7 "abandoned" src/a.py; comments 7 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
out=$(run --pr 7)
[ "$(rowstat "$out" pr)" = NA ] && echo "$out" | grep -q "closed without merging" && ! echo "$out" | grep -q "open PR" \
  && [ "$(rowstat "$out" worktree)" = NA ] && [ "$(rowstat "$out" pushed)" = NA ] && ok "closed-unmerged PR is named, not 'open'" || bad "closed: $out"

# --- 12) --branch resolves the open PR for a head; --json shape
printf '[{"number":5,"state":"OPEN"}]' > "$FAKE/prlist_head.json"
out=$(run --branch topic5 --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["prs"][0]["pr"]==5 and d["verdict"]=="pass" and {r["rule"] for r in d["prs"][0]["rows"]}=={"pr","review","ci","base","ledger","worktree","pushed","deploy"}' && ok "--branch + --json" || bad "--branch json: $out"
# 12b) the person's cadence layers (TD-126): one line after the rows, a "layers" key in --json;
# the verdict never moves, and a machine with none set prints nothing of them
printf '[{"number":5,"state":"OPEN"}]' > "$FAKE/prlist_head.json"
LREG="$TMP/layer-reg"; mkdir -p "$LREG"; printf '§4.8 override: review with haiku\n§9.99 add: nothing\n' > "$TMP/layer.md"
printf '[[layers]]\npath = "%s"\n' "$TMP/layer.md" > "$LREG/cadence.toml"
out=$(AGENT_CADENCE_REG_DIR="$LREG" run --branch topic5); rc=$?
[ $rc -eq 0 ] && grep -qF "layers: 1 active on this machine" <<< "$out" && grep -qF "1. $TMP/layer.md (own) — §4.8: layer 1 overrides; §9.99: layer 1 adds — 1 warning — cadence_layer.py --effective shows each" <<< "$out" \
  && ok "12b the active layers are one line after the rows; the verdict is the PR's" || bad "12b rc=$rc $out"
out=$(AGENT_CADENCE_REG_DIR="$LREG" run --branch topic5 --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); l=d["layers"]; assert d["verdict"]=="pass" and l["layers"][0]["n"]==1 and l["warnings"]==1 and l["by_section"][0].startswith("§4.8")' \
  && ok "12c --json carries the layers apart from the verdict" || bad "12c $out"
echo 'layers = [{path = "relative.md"}]' > "$LREG/cadence.toml"
out=$(AGENT_CADENCE_REG_DIR="$LREG" run --branch topic5); rc=$?
[ $rc -eq 0 ] && grep -q '^layers: not read — ' <<< "$out" && ok "12d a setting that cannot be read is said, and costs nothing else" || bad "12d rc=$rc $out"
out=$(AGENT_CADENCE_REG_DIR="$TMP/no-reg" run --branch topic5 --json)
! grep -q 'layers' <<< "$out" && ! grep -q '^layers' <<< "$(AGENT_CADENCE_REG_DIR="$TMP/no-reg" run --branch topic5)" && ok "12e no layers set: nothing of them" || bad "12e $out"
printf '[]' > "$FAKE/prlist_head.json"
out=$(run --branch nothing); rc=$?; [ $rc -eq 2 ] && echo "$out" | grep -q "no PR with head" && ok "--branch with no PR exits 2" || bad "no head: rc=$rc $out"

# --- 13) --since covers every merged PR, rc 1 if any fails, and an empty window is rc 2
printf '[{"number":1},{"number":2}]' > "$FAKE/prlist_since.json"
out=$(run --since 7d); rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -c '^PR #' | grep -q 2 && ok "--since reports both PRs, rc 1 on the failing one" || bad "since: rc=$rc $out"
printf '[]' > "$FAKE/prlist_since.json"
out=$(run --since 7d); rc=$?; [ $rc -eq 2 ] && echo "$out" | grep -q "no PRs in the window" && ok "empty window is rc 2" || bad "empty since: rc=$rc"
# --json must not collapse "nothing to check" (2) into the "look" verdict (3)
out=$(run --since 7d --json); rc=$?
echo "$out" | python3 -c 'import json,sys; assert json.load(sys.stdin)["verdict"]=="none"' 2>/dev/null && [ $rc -eq 2 ] && ok "--json empty window says none, rc 2" || bad "empty since json: rc=$rc $out"
# a window that fills the list limit was cut short: say so, and never exit 0 on it
python3 -c 'import json; print(json.dumps([{"number":3}]*200))' > "$FAKE/prlist_since.json"
out=$(run --since 7d); rc=$?; [ $rc -eq 3 ] && echo "$out" | grep -q "TRUNCATED" && ok "a full --since list is truncated, rc 3" || bad "truncated: rc=$rc $(echo "$out" | tail -2)"
out=$(run --since 2026-13-45); rc=$?; [ $rc -eq 2 ] && ok "garbage --since exits 2" || bad "garbage since rc=$rc"

# --- 14) deploy hook: consumer-owned script drives the row
cat > "$R/scripts/cadence_deploy_check.sh" <<'H'
#!/usr/bin/env bash
echo "hook saw pr=$1 sha=$2"; exit "${DEPLOY_RC:-0}"
H
chmod +x "$R/scripts/cadence_deploy_check.sh"
out=$(run --pr 1); [ "$(rowstat "$out" deploy)" = PASS ] && echo "$out" | grep -q "pr=1 sha=mmm1111" && ok "deploy hook pass with pr and merge sha" || bad "deploy pass: $out"
out=$(DEPLOY_RC=1 run --pr 1); rc=$?; [ "$(rowstat "$out" deploy)" = FAIL ] && [ $rc -eq 1 ] && ok "deploy hook exit 1 fails" || bad "deploy fail: $out"
out=$(DEPLOY_RC=2 run --pr 1); [ "$(rowstat "$out" deploy)" = NA ] && ok "deploy hook exit 2 is n/a" || bad "deploy na: $out"
out=$(DEPLOY_RC=7 run --pr 1); [ "$(rowstat "$out" deploy)" = UNKNOWN ] && ok "deploy hook other exit is unknown" || bad "deploy unknown: $out"
rm "$R/scripts/cadence_deploy_check.sh"

# --- 14b) TD-076: the hook is compared with origin/main's — a checkout BEHIND origin whose
# hook is missing or differs answers unknown, never na and never a stale hook's verdict.
H2="$TMP/hookrepo"; git init -q --bare -b main "$H2.git"; git clone -q "$H2.git" "$H2" 2>/dev/null
hgit() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
( cd "$H2" && echo base > base.txt && hgit . add . && hgit . commit -qm base && git push -q -u origin HEAD:main ) 2>/dev/null
git clone -q "$H2.git" "$TMP/hookold" 2>/dev/null; OLD="$TMP/hookold"
mkdir -p "$H2/scripts"; printf '#!/usr/bin/env bash\necho "v1 pr=$1"; exit 1\n' > "$H2/scripts/cadence_deploy_check.sh"; chmod +x "$H2/scripts/cadence_deploy_check.sh"
( cd "$H2" && hgit . add . && hgit . commit -qm "ship the deploy hook" && git push -q origin HEAD:main && git fetch -q origin )
hrun() { ( cd "$1" && python3 "$SCRIPT" --pr 1 2>&1 ); }
out=$(hrun "$H2"); [ "$(rowstat "$out" deploy)" = FAIL ] && ok "deploy: an up-to-date checkout runs the hook" || bad "deploy current: $out"
# $OLD was cloned before the hook landed and never pulled: the check fetches, sees origin's hook
out=$(hrun "$OLD"); rc=$?; line=$(echo "$out" | awk '$2=="deploy"')
[ "$(rowstat "$out" deploy)" = UNKNOWN ] && echo "$line" | grep -q "behind origin/main and has none" && ok "deploy: a checkout behind origin, hook not yet pulled, is unknown — not na" || bad "deploy behind/missing: rc=$rc $line"
# behind, with an older copy of the hook: its verdict is not origin's
( cd "$OLD" && git pull -q )
printf '#!/usr/bin/env bash\necho "v2 pr=$1"; exit 0\n' > "$H2/scripts/cadence_deploy_check.sh"
( cd "$H2" && hgit . commit -qam "hook v2" && git push -q origin HEAD:main )
out=$(hrun "$OLD"); line=$(echo "$out" | awk '$2=="deploy"')
[ "$(rowstat "$out" deploy)" = UNKNOWN ] && echo "$line" | grep -q "has a different one" && ! echo "$out" | grep -q "v1 pr=" && ok "deploy: a checkout behind origin with a stale hook is unknown, the stale hook not run" || bad "deploy behind/stale: $line"
( cd "$OLD" && git pull -q ); out=$(hrun "$OLD"); [ "$(rowstat "$out" deploy)" = PASS ] && echo "$out" | grep -q "v2 pr=1" && ok "deploy: once pulled, the hook runs" || bad "deploy pulled: $out"
# merely behind, hook identical: no false unknown
echo more > "$H2/base.txt"; ( cd "$H2" && hgit . commit -qam "main moves, hook untouched" && git push -q origin HEAD:main )
out=$(hrun "$OLD"); [ "$(rowstat "$out" deploy)" = PASS ] && ok "deploy: behind origin with the same hook still runs it" || bad "deploy behind/same: $out"
# a branch that edits the hook and is BEHIND main (main moved, its hook did not): the branch's own
( cd "$OLD" && git checkout -q -b diverged && printf '#!/usr/bin/env bash\necho "v2b pr=$1"; exit 1\n' > scripts/cadence_deploy_check.sh && hgit . commit -qam "hook v2b" )
out=$(hrun "$OLD"); [ "$(rowstat "$out" deploy)" = FAIL ] && echo "$out" | grep -q "v2b pr=1" && ok "deploy: a diverged branch's own hook edit runs — origin's hook did not move" || bad "deploy diverged: $out"
( cd "$OLD" && git checkout -q main && git pull -q )
# a branch that contains origin/main and edits the hook is judged as it stands (not behind)
( cd "$OLD" && git checkout -q -b edit-hook && printf '#!/usr/bin/env bash\necho "v3 pr=$1"; exit 2\n' > scripts/cadence_deploy_check.sh && hgit . commit -qam "hook v3" )
out=$(hrun "$OLD"); [ "$(rowstat "$out" deploy)" = NA ] && echo "$out" | grep -q "v3 pr=1" && ok "deploy: a branch ahead of origin runs its own hook" || bad "deploy ahead: $out"
# …and one that removes it reads na, as a repo with no hook does
( cd "$OLD" && git rm -q scripts/cadence_deploy_check.sh && hgit . commit -qm "drop hook" )
out=$(hrun "$OLD"); [ "$(rowstat "$out" deploy)" = NA ] && echo "$out" | grep -q "no executable" && ok "deploy: a branch that removes the hook is na" || bad "deploy removed: $out"

# --- 15) gh absent -> rc 2, says so
NOGH="$TMP/nogh"; mkdir -p "$NOGH"; for t in python3 git bash awk grep date; do ln -sf "$(command -v $t)" "$NOGH/$t"; done
out=$( cd "$R" && PATH="$NOGH" python3 "$SCRIPT" --pr 1 2>&1 ); rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "gh is not installed" && ok "gh absent exits 2" || bad "gh absent: rc=$rc $out"

# --- 16) no clone at all: base/worktree/pushed/deploy n/a, still checks gh rows
pr 6 OPEN nowhere "outside" src/a.py; comments 6 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
out=$( cd "$TMP" && python3 "$SCRIPT" --pr 6 2>&1 ); rc=$?
[ $rc -eq 0 ] && [ "$(rowstat "$out" base)" = NA ] && [ "$(rowstat "$out" pushed)" = NA ] && [ "$(rowstat "$out" deploy)" = NA ] && ok "no clone: local rows n/a, rc 0" || bad "no clone: rc=$rc $out"

# --- 17) TD-040: direct commits on main — the carve-outs pass, anything else fails
EDIT="$DC/files/scripts/board_edit.py"
D="$TMP/direct"; git init -q --bare -b main "$D.git"; git clone -q "$D.git" "$D" 2>/dev/null
dgit() { git -C "$D" -c user.email=t@t -c user.name=t "$@"; }
dcommit() { dgit add -A && dgit commit -qm "$1" && dgit push -q origin HEAD:main; }
TODAY=$(date +%F); FUTD=$(date -d "5 days" +%F); OLDD=$(date -d "2 days ago" +%F)
dgit checkout -q -b main 2>/dev/null; mkdir -p "$D/docs" "$D/scripts"
printf '# ledger\n' > "$D/docs/technical_debt.md"
printf '# board\n\nSwept: %s (h, quick)\n\n## Needs the user\n\n- [ ] %s (session aaaa1111 on h) — decide X. Due: %s.\n\n## In-flight (parked by a session)\n\n- (none)\n' "$OLDD" "$OLDD" "$FUTD" > "$D/docs/user_attention.md"
dcommit base                                                       # root: never listed
sed -i "s/^Swept: .*/Swept: $TODAY (h, quick)/" "$D/docs/user_attention.md"; dcommit "board: sweep stamp"        # stamp
echo old > "$D/scripts/old.sh"; GIT_COMMITTER_DATE="$(date -d '3 days ago' -R)" dcommit "backdated"   # out of window by date:
# not listed, and must not hide the in-window stamp beneath it (git log --since stops walking there)
sed -i "s/^Swept: .*/Swept: $TODAY (h, deep)/" "$D/docs/user_attention.md"; echo "- a ledger line" >> "$D/docs/technical_debt.md"
dcommit "board: stamp plus a ledger line"                          # fail: two files
ins() {  # ins <after-this-exact-line> <new line>: insert below it
  python3 - "$D/docs/user_attention.md" "$1" "$2" <<'P'
import sys
p, after, new = sys.argv[1:]
L = open(p).read().split("\n"); L.insert(L.index(after) + 1, new); open(p, "w").write("\n".join(L))
P
}
ins "## Needs the user" "- [ ] $TODAY (n/a) — a bot's event. Due: $FUTD."; ins "## Needs the user" ""; dcommit "bot: append"   # board-append (+ a blank line)
python3 - "$D/docs/user_attention.md" "- [ ] $TODAY (n/a) — parked. Due: $FUTD." <<'P'
import sys
p, new = sys.argv[1:]; s = open(p).read(); assert "- (none)" in s; open(p, "w").write(s.replace("- (none)", new))
P
dcommit "bot: append in-flight"                                    # fail: replaces a line
line=$(grep -n "decide X" "$D/docs/user_attention.md" | cut -d: -f1)
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" decide --board "$D/docs/user_attention.md" --line "$line" --expect "$OLDD (session aaaa1111" --answer yes --tool shiftlead >/dev/null \
  && dgit push -q origin HEAD:main                                 # board-edit, the real writer's message
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" snooze --board "$D/docs/user_attention.md" --line "$line" --expect "$OLDD (session aaaa1111" --to "$(date -d '9 days' +%F)" >/dev/null \
  && dgit push -q origin HEAD:main                                 # board-edit: a snooze
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" reply --board "$D/docs/user_attention.md" --line "$line" --expect "$OLDD (session aaaa1111" --text "not before Friday" --by Alex --tool shiftlead >/dev/null \
  && dgit push -q origin HEAD:main                                 # board-edit: a reply (TD-075)
sed -i -E "s/not before Friday/not before Monday/" "$D/docs/user_attention.md"; dcommit "shiftlead: reworded the reply by hand"   # fail: no fixed message
sed -i -E "s/Due: [0-9-]+\. — Alex/Due: $TODAY. — Alex/" "$D/docs/user_attention.md"; dcommit "snoozed it by hand"   # fail: no fixed message
echo x > "$D/scripts/a.sh"; dcommit "a script, straight to main"   # fail: a straight push's shape, off the board
echo y > "$D/scripts/b.sh"; dcommit "a merged PR (#9)"             # a PR's squash: not listed
printf '[]' > "$FAKE/prlist_since.json"
out=$( cd "$D" && python3 "$SCRIPT" --since 1d --json 2>&1 ); rc=$?
chk=$(printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
got = [(c["class"], c["subject"]) for c in d["direct"]["commits"]]
want = [("fail", "a script, straight to main"), ("fail", "snoozed it by hand"), ("fail", "shiftlead: reworded the reply by hand"),
        ("board-edit", "shiftlead: reply decide X. (session aaaa1111)"), ("board-edit", None), ("board-edit", None),
        ("fail", "bot: append in-flight"), ("board-append", "bot: append"),
        ("fail", "board: stamp plus a ledger line"), ("stamp", "board: sweep stamp")]
assert len(got) == len(want), got
for (gc, gs), (wc, ws) in zip(got, want):
    assert gc == wc and (ws is None or gs == ws), (gc, gs, wc, ws)
assert got[4][1].startswith("board_edit: snooze decide X. to "), got[4]
assert got[5][1] == "shiftlead: decide decide X.: yes (session aaaa1111)", got[5]
assert d["verdict"] == "fail" and d["direct"]["status"] == "fail", d["verdict"]
print("ok")' 2>&1)
[ "$chk" = ok ] && [ $rc -eq 1 ] && ok "--since: direct commits classified (stamp, board-append, board_edit.py's board-edit pass, a reply among them; stamp+ledger, a removed line, a hand edit, a hand-reworded reply, a script fail; root and (#N) skipped), rc 1" \
  || bad "direct classify rc=$rc: $chk"
out=$( cd "$D" && python3 "$SCRIPT" --since 1d 2>&1 )
echo "$out" | grep -q "^Direct commits on origin/main (no PR) — 10 direct commit(s)  \[FAIL\]" && echo "$out" | grep -q "PASS    board-edit" \
  && ok "--since text: the Direct commits section" || bad "direct text: $(echo "$out" | tail -9)"
git init -q -b main "$TMP/noorigin"; ( cd "$TMP/noorigin" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root )
out=$( cd "$TMP/noorigin" && python3 "$SCRIPT" --since 1d --json 2>&1 ); rc=$?
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["verdict"]=="unknown" and d["direct"]["status"]=="unknown", d' 2>/dev/null \
  && [ $rc -eq 3 ] && ok "--since with an unreadable history: unknown, rc 3 — never an empty window" || bad "unreadable direct rc=$rc: $out"
out=$( cd "$TMP" && python3 "$SCRIPT" --since 1d 2>&1 ); rc=$?
echo "$out" | grep -q "direct commits: n/a" && [ $rc -eq 2 ] && ok "--since with no clone: direct is n/a, empty window still rc 2" || bad "direct no clone rc=$rc: $out"

# --- 17b) TD-083, cadence §4.5: a tool lands its board edit by a PR of its own, merged at once
# with no review comment. The review row passes it only when the title is board_edit.py's message,
# the PR touches the board alone, and its squash is a one-item edit — the direct audit's rules.
bepr() {  # bepr <n> <title> <sha> [files...]: a merged PR fixture whose squash is <sha>
  local n=$1 title=$2 sha=$3; shift 3
  local files="" ; for f in "$@"; do files="$files{\"path\":\"$f\"},"; done; files="[${files%,}]"
  printf '{"number":%s,"url":"https://x/pr/%s","state":"MERGED","title":"%s","body":"","baseRefName":"main","headRefName":"board-edit-%s","headRefOid":"hhh2222","mergedAt":"%s","mergeCommit":{"oid":"%s"},"files":%s}\n' \
    "$n" "$n" "$title" "$n" "$MERGED" "$sha" "$files" > "$FAKE/pr_$n.json"
  [ "${OPEN:-}" ] && python3 - "$FAKE/pr_$n.json" "$sha" <<'J'
import json, sys
p, sha = sys.argv[1:]; d = json.load(open(p))
d.update(state="OPEN", mergedAt=None, mergeCommit=None, headRefOid=sha); json.dump(d, open(p, "w"))
J
  printf '{"parents":[{"sha":"a"}]}' > "$FAKE/commit_$sha.json"; comments "$n"
}
dgit checkout -q -b tool-tree origin/main
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" done --board "$D/docs/user_attention.md" --line "$line" --expect "$OLDD (session aaaa1111" --why "shipped" --tool shiftlead >/dev/null
btitle=$(dgit log -1 --format=%s)
dgit checkout -q main && dgit merge -q --squash tool-tree >/dev/null && dgit commit -qm "$btitle (#21)" && dgit push -q origin HEAD:main
bsha=$(dgit rev-parse HEAD)
bepr 21 "$btitle" "$bsha" docs/user_attention.md
out=$( cd "$D" && python3 "$SCRIPT" --pr 21 2>&1 ); rc=$?
[ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "cadence §4.5 carve-out" && [ $rc -eq 0 ] \
  && ok "a tool-made board PR (board_edit.py's message, one item) passes review with no comment, rc 0" || bad "board-edit PR rc=$rc: $out"
out=$( cd "$D" && python3 "$SCRIPT" --since 1d --json 2>&1 )
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert not [c for c in d["direct"]["commits"] if c["subject"].endswith("(#21)")], d["direct"]' 2>/dev/null \
  && ok "its squash is a PR's, never listed among the direct commits" || bad "board-edit squash listed as direct: $out"
bepr 22 "a board tidy" "$bsha" docs/user_attention.md                       # the same edit, not the tool's message
out=$( cd "$D" && python3 "$SCRIPT" --pr 22 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && echo "$out" | grep -q "no \`cadence-review:\` comment" && ok "a one-item board PR without the fixed message needs a review" || bad "untitled board PR: $out"
echo z > "$D/scripts/z.sh"; dcommit "$btitle (#23)"; zsha=$(dgit rev-parse HEAD)
bepr 23 "$btitle" "$zsha" docs/user_attention.md                            # the files list lies; the commit is a script
out=$( cd "$D" && python3 "$SCRIPT" --pr 23 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "the fixed message on a commit that is not the board edit needs a review" || bad "message on a script: $out"
bepr 24 "$btitle" "$bsha" docs/user_attention.md docs/technical_debt.md      # more than the board
out=$( cd "$D" && python3 "$SCRIPT" --pr 24 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a PR touching more than the board needs a review" || bad "board+ledger PR: $out"
bepr 25 "$btitle" "0123456789abcdef0123456789abcdef01234567" docs/user_attention.md   # not in this clone
out=$( cd "$D" && python3 "$SCRIPT" --pr 25 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a board PR whose commit this clone cannot read needs a review — never a pass on the title" || bad "unreadable board PR: $out"
# found in review (PR #207): only a one-commit PR is read whole by its one commit
ins "## Needs the user" "- [ ] $TODAY (session bbbb2222 on h) — look at Y. Due: $FUTD."; dcommit "bot: append Y (#29)"
dgit checkout -q -B tool-open origin/main
bline=$(grep -n "look at Y" "$D/docs/user_attention.md" | cut -d: -f1)
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" snooze --board "$D/docs/user_attention.md" --line "$bline" --expect "$TODAY (session bbbb2222" --to "$(date -d '12 days' +%F)" --tool shiftlead >/dev/null
otitle=$(dgit log -1 --format=%s); osha=$(dgit rev-parse HEAD)
OPEN=1 bepr 26 "$otitle" "$osha" docs/user_attention.md
out=$( cd "$D" && python3 "$SCRIPT" --pr 26 2>&1 )
[ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "cadence §4.5 carve-out" && ok "an open one-commit board PR is read by its head and passes" || bad "open board PR: $out"
dgit reset -q --hard origin/main
sed -i '/^## In-flight/,$d' "$D/docs/user_attention.md"; dgit commit -qam "wipe a section"   # commit 1: anything at all
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" snooze --board "$D/docs/user_attention.md" --line "$bline" --expect "$TODAY (session bbbb2222" --to "$(date -d '12 days' +%F)" --tool shiftlead >/dev/null
OPEN=1 bepr 27 "$(dgit log -1 --format=%s)" "$(dgit rev-parse HEAD)" docs/user_attention.md
out=$( cd "$D" && python3 "$SCRIPT" --pr 27 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "an open two-commit board PR needs a review — its head alone hides the first commit" || bad "two-commit open PR: $out"
bepr 28 "$(dgit log -1 --format=%s)" "$(dgit rev-parse HEAD)" docs/user_attention.md   # a rebase merge's last commit: no (#n)
out=$( cd "$D" && python3 "$SCRIPT" --pr 28 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a merged board PR whose commit is no (#n) squash needs a review" || bad "rebase-merged board PR: $out"
dgit checkout -q main

# --- 17c) TD-119, cadence §2.4: a tool (ShiftLead's Queue) lands a rank edit by a PR of its own,
# under ledgerboard's `queue:` subject. The review row passes it (queue-edit) only when it and its one
# commit change the rank file alone, every changed line is `TD-NNN: <key>`, and the file reads clean.
RANKF=docs/technical_debt_rank.yml
LBDIR="$DC/files/scripts"
rankset() {  # rankset <TD=key|TD=> …: set lines in the rank file through ledgerboard's writer
  python3 - "$D/$RANKF" "$LBDIR" "$@" <<'PY'
import os, sys
path, lbdir, *pairs = sys.argv[1:]
sys.path.insert(0, lbdir); import ledgerboard as L
text = open(path).read() if os.path.exists(path) else ""
lines = {t: (k or None) for t, _, k in (p.partition("=") for p in pairs)}
open(path, "w").write(L.set_rank(text, lines))
PY
}
qtitle() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ledgerboard as L; print(L.queue_subject("shiftlead", sys.argv[2], sys.argv[3:]))' "$LBDIR" "$@"; }
dgit checkout -q -B rank-tree origin/main
rankset TD-005=0h TD-002=2a; qt=$(qtitle rank TD-005 TD-002); dgit add "$RANKF" && dgit commit -qm "$qt"
dgit checkout -q main && dgit merge -q --squash rank-tree >/dev/null && dgit commit -qm "$qt (#31)" && dgit push -q origin HEAD:main
qsha=$(dgit rev-parse HEAD)
bepr 31 "$qt" "$qsha" "$RANKF"
out=$( cd "$D" && python3 "$SCRIPT" --pr 31 2>&1 ); rc=$?
[ "$(rowstat "$out" review)" = PASS ] && [ "$(rowstat "$out" ledger)" = NA ] && echo "$out" | grep -q "queue-edit" && [ $rc -eq 0 ] \
  && ok "a tool-made rank PR (queue: subject, the rank file alone, new file with its header) passes review with no comment, ledger row n/a" || bad "queue-edit PR rc=$rc: $out"
bepr 32 "$qt" "$qsha" "$RANKF" scripts/x.sh                                  # more than the rank file
out=$( cd "$D" && python3 "$SCRIPT" --pr 32 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && [ "$(rowstat "$out" ledger)" = FAIL ] \
  && ok "a queue: PR touching more than the rank file needs a review, and its ids the ledger rule" || bad "rank+script PR: $out"
bepr 33 "rank tidy" "$qsha" "$RANKF"                                          # not the queue subject
out=$( cd "$D" && python3 "$SCRIPT" --pr 33 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a rank-only PR without the queue: subject needs a review" || bad "untitled rank PR: $out"
rankset TD-007=1i; echo y > "$D/scripts/y.sh"; qt=$(qtitle rank TD-007); dcommit "$qt (#34)"
bepr 34 "$qt" "$(dgit rev-parse HEAD)" "$RANKF"                               # the files list lies; the commit has a script
out=$( cd "$D" && python3 "$SCRIPT" --pr 34 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a queue: commit that also changes a script needs a review" || bad "rank+script commit: $out"
printf '# a comment on an existing file\n' >> "$D/$RANKF"; qt=$(qtitle prune TD-007); dcommit "$qt (#35)"
bepr 35 "$qt" "$(dgit rev-parse HEAD)" "$RANKF"
out=$( cd "$D" && python3 "$SCRIPT" --pr 35 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a queue: commit adding a line that is not TD-NNN: <key> needs a review" || bad "rank comment line: $out"
sed -i '$d' "$D/$RANKF"; dcommit "undo the comment (#36)"
printf 'TD-009 3a\n' >> "$D/$RANKF"; qt=$(qtitle join TD-009); dcommit "$qt (#37)"
bepr 37 "$qt" "$(dgit rev-parse HEAD)" "$RANKF"
out=$( cd "$D" && python3 "$SCRIPT" --pr 37 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a queue: commit with an unreadable rank line needs a review" || bad "bad rank line: $out"
sed -i '$d' "$D/$RANKF"; dcommit "undo the bad line (#38)"
dgit checkout -q -B rank-open origin/main
rankset TD-005=; qt=$(qtitle prune TD-005); dgit add "$RANKF" && dgit commit -qm "$qt"
OPEN=1 bepr 39 "$qt" "$(dgit rev-parse HEAD)" "$RANKF"
out=$( cd "$D" && python3 "$SCRIPT" --pr 39 2>&1 )
[ "$(rowstat "$out" review)" = PASS ] && echo "$out" | grep -q "queue-edit" && ok "an open one-commit prune PR is read by its head and passes" || bad "open prune PR: $out"
out=$( cd "$D" && python3 "$SCRIPT" --since 1d --json 2>&1 )
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert not [c for c in d["direct"]["commits"] if c["subject"].endswith("(#31)")], d["direct"]' 2>/dev/null \
  && ok "a rank PR squash is a PR's, never listed among the direct commits" || bad "rank squash listed as direct: $out"
dgit checkout -q main
dgit rm -q "$RANKF"; qt=$(qtitle prune TD-002); dcommit "$qt (#40)"
bepr 40 "$qt" "$(dgit rev-parse HEAD)" "$RANKF"                               # the whole file deleted
out=$( cd "$D" && python3 "$SCRIPT" --pr 40 2>&1 )
[ "$(rowstat "$out" review)" = FAIL ] && ok "a queue: commit deleting the rank file needs a review" || bad "rank file deleted: $out"
# TD-170: in a split ledger (TD-160) the rank file is docs/ledger/rank.yml, named from the tree the PR's commit holds
dgit checkout -q -B rank-v2 origin/main
mkdir -p "$D/docs/ledger"; printf '# ledger\n\nLedgerboard: 2\n' > "$D/docs/ledger/README.md"; dgit add -A && dgit commit -qm "split"
RANKF=docs/ledger/rank.yml rankset TD-005=0h; qt=$(qtitle rank TD-005); dgit add -A && dgit commit -qm "$qt (#41)"
bepr 41 "$qt" "$(dgit rev-parse HEAD)" docs/ledger/rank.yml
out=$( cd "$D" && python3 "$SCRIPT" --pr 41 2>&1 )
[ "$(rowstat "$out" review)" = PASS ] && [ "$(rowstat "$out" ledger)" = NA ] && echo "$out" | grep -q "queue-edit" \
  && ok "a rank PR in a split ledger (docs/ledger/rank.yml) passes review and its ledger row is n/a" || bad "v2 rank PR: $out"
dgit push -q -f origin HEAD~1:main   # the split lands; an open rank PR is then read by its head
dgit checkout -q -B rank-v2-open HEAD~1; RANKF=docs/ledger/rank.yml rankset TD-002=1a; qt=$(qtitle rank TD-002); dgit add -A && dgit commit -qm "$qt"
OPEN=1 bepr 42 "$qt" "$(dgit rev-parse HEAD)" docs/ledger/rank.yml
out=$( cd "$D" && python3 "$SCRIPT" --pr 42 2>&1 )
[ "$(rowstat "$out" review)" = PASS ] && [ "$(rowstat "$out" ledger)" = NA ] \
  && ok "an open one-commit rank PR in a split ledger is read by its head and passes" || bad "open v2 rank PR: $out"
dgit push -q -f origin main:main   # the fixture's main as it was, for the rows below
dgit checkout -q main

# --- base row (TD-037): the wrong-base stack of §1, named at the PR, not as "not landed"
comments 7 "$(c 'cadence-review: SHIP · sonnet · code · 0' "$BEFORE" "$BEFORE")"
pr 7 MERGED topic7 "stacked" src/a.py
out=$(run --pr 7); [ "$(rowstat "$out" base)" = PASS ] && echo "$out" | grep -q "base is main" && ok "base: main passes" || bad "base main: $out"
BASE=td001-x pr 7 MERGED topic7 "stacked" src/a.py
out=$(run --pr 7); rc=$?
# topic7 is no local branch here, so the worktree row is n/a — the exact blind spot TD-037 names
[ "$(rowstat "$out" base)" = FAIL ] && [ "$(rowstat "$out" worktree)" = NA ] && [ $rc -eq 1 ] \
  && echo "$out" | grep -q "merged into td001-x, not main" && echo "$out" | grep -q "one more PR td001-x → main" \
  && ok "base: a merge into a topic branch fails and says the recovery, with no worktree on the head" || bad "base wrong merged rc=$rc: $out"
BASE=td001-x pr 7 OPEN topic7 "stacked" src/a.py
out=$(run --pr 7); grep -qF "gh api -X PATCH repos/{owner}/{repo}/pulls/7 -f base=main" <<< "$out" && ! grep -q "gh pr edit" <<< "$out" && grep -q "before deleting the old base" <<< "$out" && [ "$(rowstat "$out" base)" = FAIL ] && ok "base: an open wrong-base PR fails with the retarget" || bad "base wrong open: $out"
BASE=td001-x BODY='Summary\n\ncadence-stack: needs the parser from #6 first' pr 7 OPEN topic7 "stacked" src/a.py
out=$(run --pr 7); [ "$(rowstat "$out" base)" = PASS ] && echo "$out" | grep -q "on purpose (needs the parser from #6 first)" && echo "$out" | grep -q "only when td001-x lands" \
  && ok "base: a cadence-stack: body line passes a deliberate stack and names what it waits on" || bad "base stack: $out"
BASE=td001-x BODY='we do not use cadence-stack: here' pr 7 OPEN topic7 "stacked" src/a.py
out=$(run --pr 7); [ "$(rowstat "$out" base)" = FAIL ] && ok "base: the marker counts only at the start of a line" || bad "base marker mid-line: $out"
BASE=td001-x pr 7 CLOSED topic7 "stacked" src/a.py
out=$(run --pr 7); [ "$(rowstat "$out" base)" = NA ] && ok "base: closed unmerged is n/a" || bad "base closed: $out"
pr 7 OPEN topic7 "stacked" src/a.py
sed -i 's/"baseRefName":"main",//' "$FAKE/pr_7.json"
out=$(run --pr 7); rc=$?; [ "$(rowstat "$out" base)" = UNKNOWN ] && [ $rc -eq 3 ] && ok "base: gh gave no base — unknown, rc 3" || bad "base missing rc=$rc: $out"
# a clone whose origin has none of origin/HEAD, init.defaultBranch, main, master: never a guessed main
N="$TMP/nodefault"; git init -q --bare -b trunk "$N.git"; git clone -q "$N.git" "$N" 2>/dev/null
( cd "$N" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root && git push -q origin HEAD:trunk && git fetch -q origin \
  && git remote set-head origin -d 2>/dev/null; git config init.defaultBranch "" )
BASE=main pr 7 OPEN topic7 "stacked" src/a.py
out=$( cd "$N" && python3 "$SCRIPT" --pr 7 2>&1 ); [ "$(rowstat "$out" base)" = UNKNOWN ] && echo "$out" | grep -q "cannot tell the default branch" \
  && ok "base: no resolvable default branch is unknown, not an assumed main" || bad "base no default: $out"


# --- 18) TD-073: the ledger row runs `ledger.py --check --since` on the PR's own ledger edit,
# read from commits (head vs its merge-base; merged: the merge commit vs its parent).
LR="$TMP/ledrepo"; git init -q --bare -b main "$LR.git"; git clone -q "$LR.git" "$LR" 2>/dev/null
lgit() { git -C "$LR" -c user.email=t@t -c user.name=t "$@"; }
lent() { printf '## %s: entry\n\n**Priority:** Low\n%s\n**Status:** Open\n\n**Why:** x.\n\n---\n\n' "$1" "$2"; }
mkdir -p "$LR/docs"; { printf '# ledger\n\n'; lent TD-001 '**Type:** chore'; } > "$LR/docs/technical_debt.md"   # a standing bad field
( cd "$LR" && lgit add -A && lgit commit -qm base && git push -q -u origin HEAD:main && git fetch -q origin ) 2>/dev/null
lbranch() { # name, type-line of the entry it adds
  ( cd "$LR" && git checkout -q -b "$1" origin/main && lent TD-002 "$2" >> docs/technical_debt.md && lgit commit -qam "$1" && git rev-parse HEAD )
}
GOOD=$(lbranch led-good '**Type:** debt'); BADC=$(lbranch led-bad '**Type:** chore2')
sethead() { python3 - "$FAKE/pr_$1.json" "$2" "${3:-}" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["headRefOid"] = sys.argv[2]
if sys.argv[3]: d["mergeCommit"] = {"oid": sys.argv[3]}
json.dump(d, open(p, "w"))
PY
}
lrun() { ( cd "$LR" && python3 "$SCRIPT" "$@" 2>&1 ); }
lrow() { echo "$1" | awk '$2=="ledger"'; }
pr 20 OPEN led-good "TD-002: a clean entry" docs/technical_debt.md; sethead 20 "$GOOD"
comments 20 "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"
out=$(lrun --pr 20); [ "$(rowstat "$out" ledger)" = PASS ] && lrow "$out" | grep -q "ledger fields checked" && ok "ledger: a clean edit passes though the ledger has a standing bad field" || bad "ledger clean edit: $(lrow "$out")"
pr 21 OPEN led-bad "TD-002: a bad entry" docs/technical_debt.md; sethead 21 "$BADC"
comments 21 "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"
out=$(lrun --pr 21); rc=$?; [ "$(rowstat "$out" ledger)" = FAIL ] && [ $rc -eq 1 ] && lrow "$out" | grep -q "1 bad field(s): ⚠ TD-002: unknown Type 'chore2'" && ! lrow "$out" | grep -q "TD-001" \
  && ok "ledger: a bad field in the PR's own entry fails the row with the flag's text" || bad "ledger bad edit: rc=$rc $(lrow "$out")"
# no TD in the title: the title rule is na, the edit is still checked
pr 21 OPEN led-bad "tidy the ledger" docs/technical_debt.md; sethead 21 "$BADC"
out=$(lrun --pr 21); [ "$(rowstat "$out" ledger)" = FAIL ] && ok "ledger: a bad edit fails with no TD in the title" || bad "ledger untitled bad: $(lrow "$out")"
pr 20 OPEN led-good "tidy the ledger" docs/technical_debt.md; sethead 20 "$GOOD"
out=$(lrun --pr 20); [ "$(rowstat "$out" ledger)" = NA ] && lrow "$out" | grep -q "no TD named in the title; ledger fields checked" && ok "ledger: a clean untitled edit stays na, and says it was checked" || bad "ledger untitled clean: $(lrow "$out")"
# the PR does not touch the ledger: nothing is checked, the row is as it was
pr 21 OPEN led-bad "TD-002: code only" src/a.py; sethead 21 "$BADC"
out=$(lrun --pr 21); [ "$(rowstat "$out" ledger)" = FAIL ] && lrow "$out" | grep -q "touches neither ledger file" && ok "ledger: a PR that does not touch the ledger is not field-checked" || bad "ledger untouched: $(lrow "$out")"
# run from a checkout on another branch: the answer comes from the commits, not the working tree
pr 21 OPEN led-bad "TD-002: a bad entry" docs/technical_debt.md; sethead 21 "$BADC"
( cd "$LR" && git checkout -q led-good )
out=$(lrun --pr 21); [ "$(rowstat "$out" ledger)" = FAIL ] && ok "ledger: checked from another branch's checkout, the PR's commit is what is read" || bad "ledger other checkout: $(lrow "$out")"
# merged: the merge commit against its parent
SQ=$( cd "$LR" && git checkout -q -B main origin/main && git merge -q --squash led-bad >/dev/null && lgit commit -qm "led-bad (#22)" && git push -q origin HEAD:main && git fetch -q origin && git rev-parse HEAD )
pr 22 MERGED led-bad "TD-002: a bad entry" docs/technical_debt.md; sethead 22 "$BADC" "$SQ"; echo '{"parents":[{"sha":"a"}]}' > "$FAKE/commit_$SQ.json"
comments 22 "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"
out=$(lrun --pr 22); [ "$(rowstat "$out" ledger)" = FAIL ] && lrow "$out" | grep -q "TD-002: unknown Type 'chore2'" && ok "ledger: a merged PR is judged merge commit vs its parent" || bad "ledger merged: $(lrow "$out")"
# a later PR on top of that main: TD-002's bad field is now standing, and does not fail it
NEXT=$( cd "$LR" && git checkout -q -b led-next origin/main && lent TD-003 '**Type:** feature' >> docs/technical_debt.md && lgit commit -qam next && git rev-parse HEAD )
pr 23 OPEN led-next "TD-003: next" docs/technical_debt.md; sethead 23 "$NEXT"
comments 23 "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"
out=$(lrun --pr 23); [ "$(rowstat "$out" ledger)" = PASS ] && ok "ledger: a bad field merged earlier is standing — it never locks the next PR out" || bad "ledger standing: $(lrow "$out")"
# a commit this clone does not have: not checked, said, never a fail
sethead 23 0123456789abcdef0123456789abcdef01234567
out=$(lrun --pr 23); [ "$(rowstat "$out" ledger)" = PASS ] && lrow "$out" | grep -q "ledger fields not checked: 0123456 is not in this clone" && ok "ledger: an unknown head commit is not checked, and the row says so" || bad "ledger unknown head: $(lrow "$out")"
# --- TD-122: an entry the PR adds or edits that waits on the person with no **Ask:** line warns in the
# ledger row, never fails it; an archived entry, an unchanged one and one with an Ask: below its header do not
AR="$TMP/askrepo"; git init -q --bare -b main "$AR.git"; git clone -q "$AR.git" "$AR" 2>/dev/null
agit() { git -C "$AR" -c user.email=t@t -c user.name=t "$@"; }
aent() { printf '## %s: entry\n\n**Priority:** Low\n**Type:** debt\n%s\n**Status:** Open\n\n**Why:** x.\n%b\n---\n\n' "$1" "$2" "${3:-}"; }
mkdir -p "$AR/docs"; { printf '# ledger\n\n'; aent TD-010 '**Blocked by:** decision (Alex)'; } > "$AR/docs/technical_debt.md"
printf '# archive\n\n' > "$AR/docs/technical_debt_archive.md"
( cd "$AR" && agit add -A && agit commit -qm base && git push -q -u origin HEAD:main && git fetch -q origin ) 2>/dev/null
abranch() { # name, then a command run in the clone that edits the ledger
  ( cd "$AR" && git checkout -q -b "$1" origin/main && eval "$2" && agit commit -qam "$1" && git rev-parse HEAD )
}
ADD=$(abranch ask-add 'aent TD-011 "**Owner:** person" >> docs/technical_debt.md')
OKA=$(abranch ask-ok 'aent TD-012 "**Blocked by:** decision (alex)" "\n**Ask:** Should it? Yes or no.\n" >> docs/technical_debt.md')
HDR=$(abranch ask-hdr 'aent TD-013 "**Ask:** Should it?" "\n**Answers:** yes | no\n" >> docs/technical_debt.md')
EDT=$(abranch ask-edit 'sed -i "s/^\*\*Status:\*\* Open/**Status:** Open, still/" docs/technical_debt.md')
ARC=$(abranch ask-arch '{ cat docs/technical_debt.md | sed 1,2d | sed "s/Open/Resolved/"; } >> docs/technical_debt_archive.md; printf "# ledger\n\n" > docs/technical_debt.md')
arun() { ( cd "$AR" && python3 "$SCRIPT" "$@" 2>&1 ); }
apr() { # n, branch, head
  pr "$1" OPEN "$2" "TD-0$1: ask" docs/technical_debt.md docs/technical_debt_archive.md; sethead "$1" "$3"
  comments "$1" "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"
}
apr 11 ask-add "$ADD"; out=$(arun --pr 11); rc=$?
[ "$(rowstat "$out" ledger)" = PASS ] && lrow "$out" | grep -qF "⚠ TD-011 waits on the person (Owner: person) with no **Ask:** line" && ! lrow "$out" | grep -q "TD-010" \
  && ok "ledger: an added entry owned by the person with no Ask: warns, the row stays PASS; the unchanged one on main does not" || bad "ask added: rc=$rc $(lrow "$out")"
apr 12 ask-ok "$OKA"; out=$(arun --pr 12)
[ "$(rowstat "$out" ledger)" = PASS ] && ! lrow "$out" | grep -q "Ask:" && ok "ledger: an added entry with an Ask: line below its header does not warn" || bad "ask ok: $(lrow "$out")"
apr 13 ask-hdr "$HDR"; out=$(arun --pr 13)
[ "$(rowstat "$out" ledger)" = PASS ] && lrow "$out" | grep -qF "TD-013 waits on the person (Answers:; its Ask: is in the header)" \
  && ok "ledger: an Answers: entry whose Ask: sits in the header block warns, and says where it is" || bad "ask header: $(lrow "$out")"
apr 10 ask-edit "$EDT"; out=$(arun --pr 10)
[ "$(rowstat "$out" ledger)" = PASS ] && lrow "$out" | grep -qF "TD-010 waits on the person (decision (Alex))" \
  && ok "ledger: an edited entry blocked on a decision with no Ask: warns" || bad "ask edited: $(lrow "$out")"
apr 14 ask-arch "$ARC"; out=$(arun --pr 14)
[ "$(rowstat "$out" ledger)" = PASS ] && ! lrow "$out" | grep -q "waits on the person" && ok "ledger: an entry moved to the archive does not warn" || bad "ask archived: $(lrow "$out")"
( cd "$AR" && git checkout -q ask-add ) && out=$( cd "$AR" && python3 "$DC/files/scripts/ledger.py" --check --since origin/main ); rc=$?
[ $rc -eq 0 ] && grep -qF "ℹ TD-011 waits on the person" <<< "$out" && ! grep -q "TD-010" <<< "$out" \
  && ok "ledger.py --check --since: the no-ask ℹ names the new entry, rc 0, and the unchanged one is standing" || bad "ask --check: rc=$rc $out"

# --- 19) TD-124: the ledger row on an open PR judges the ids it adds — head's ledger and archive
# minus its merge-base's. Main holds unpadded TD-1..TD-3, and TD-10 only as an archive table row.
IR="$TMP/idrepo"; git init -q --bare -b main "$IR.git"; git clone -q "$IR.git" "$IR" 2>/dev/null
igit() { git -C "$IR" -c user.email=t@t -c user.name=t "$@"; }
ient() { printf '\n## %s: entry\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** x.\n' "$1"; }
mkdir -p "$IR/docs"; { printf '# ledger\n'; ient TD-1; ient TD-2; ient TD-3; } > "$IR/docs/technical_debt.md"
printf '# archive\n\n| TD-10 | old | Low | done |\n' > "$IR/docs/technical_debt_archive.md"
( igit add -A && igit commit -qm base && git -C "$IR" push -q -u origin HEAD:main && git -C "$IR" fetch -q origin ) 2>/dev/null
ibranch() { # ibranch <name> <from> <n> <ids...>: a branch off <from> adding those entries, pushed as PR <n>'s head
  local name=$1 from=$2 n=$3; shift 3
  ( cd "$IR" && git checkout -q -b "$name" "$from" && for i in "$@"; do ient "$i" >> docs/technical_debt.md; done \
    && igit commit -qam "$name" && git push -q origin "HEAD:refs/pull/$n/head" && git rev-parse HEAD )
}
plist() { python3 -c 'import json, sys; print(json.dumps([{"number": int(n), "title": "t"} for n in sys.argv[1:]]))' "$@" > "$FAKE/prlist_since.json"; }
irun() { ( cd "$IR" && python3 "$SCRIPT" "$@" 2>&1 ); }
irow() { echo "$1" | awk '$2=="ledger"'; }
idpr() { pr "$1" OPEN "$2" "$3" docs/technical_debt.md; sethead "$1" "$4"; comments "$1" "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"; }
A=$(ibranch id-a origin/main 31 TD-011)
C=$(ibranch id-c origin/main 33 TD-011)
F=$(ibranch id-f id-a 36 TD-014)          # stacked on id-a: it carries id-a's TD-011 too
idpr 31 id-a "TD-011: a" "$A"
plist 31
out=$(irun --pr 31); [ "$(rowstat "$out" ledger)" = PASS ] && ! irow "$out" | grep -q "⚠" \
  && ok "ids: a new id nobody else holds passes (unpadded and row-form ids read as numbers)" || bad "ids clean: $(irow "$out")"
plist 31 33
out=$(irun --pr 31); rc=$?; [ "$(rowstat "$out" ledger)" = FAIL ] && [ $rc -eq 1 ] && irow "$out" | grep -q "TD-011 also added by #33" \
  && ok "ids: a new id another open PR also adds fails, naming that PR" || bad "ids other PR: rc=$rc $(irow "$out")"
idpr 36 id-f "TD-014: f" "$F"; plist 31 36
out=$(irun --pr 36); [ "$(rowstat "$out" ledger)" = PASS ] \
  && ok "ids: a PR stacked on another is not a collision with it" || bad "ids stacked: $(irow "$out")"
H=$(ibranch id-h id-a 39 TD-016)          # a sibling of id-f: both stacked on id-a, both carry its TD-011
plist 31 36 39
out=$(irun --pr 36); [ "$(rowstat "$out" ledger)" = PASS ] && ! irow "$out" | grep -q "#39" \
  && ok "ids: two PRs stacked on one parent do not collide over the parent's id" || bad "ids siblings: $(irow "$out")"
plist 31 99
out=$(irun --pr 31); [ "$(rowstat "$out" ledger)" = PASS ] && irow "$out" | grep -q "⚠ open PRs not read for ids: #99" \
  && ok "ids: an open PR whose head could not be read warns, naming it — never a silent pass" || bad "ids unread: $(irow "$out")"
plist 31
# main moves on: TD-011 lands by another route while PR 31 still adds it
( cd "$IR" && git checkout -q -B main origin/main && ient TD-011 >> docs/technical_debt.md && igit commit -qam "TD-011 elsewhere" \
  && git push -q origin HEAD:main && git fetch -q origin )
G=$(ibranch id-g origin/main 38 TD-015)   # cut after main got TD-011: its head holds TD-011, its base too
plist 31 38
out=$(irun --pr 31); [ "$(rowstat "$out" ledger)" = FAIL ] && irow "$out" | grep -q "TD-011 already on origin/main" \
  && ! irow "$out" | grep -q "#38" \
  && ok "ids: a new id main already holds fails — and another PR holding it from main is not named" || bad "ids on main: $(irow "$out")"
plist 31
# an archive move (TD-2 to an archive row) and main merged into the head add nothing new
D=$( cd "$IR" && git checkout -q -b id-d "$A" && git merge -q origin/main -m "merge main" 2>/dev/null; \
     sed -i '/^## TD-2: entry$/,/^\*\*Why:\*\* x\.$/d' docs/technical_debt.md && echo '| TD-2 | moved | Low | done |' >> docs/technical_debt_archive.md \
     && sed -i '/^## TD-011: entry$/,/^\*\*Why:\*\* x\.$/d' docs/technical_debt.md && igit commit -qam "archive TD-2" && git push -q origin HEAD:refs/pull/34/head && git rev-parse HEAD )
idpr 34 id-d "TD-002: archived" "$D"; plist 34
out=$(irun --pr 34); [ "$(rowstat "$out" ledger)" = PASS ] && ! irow "$out" | grep -q "⚠" \
  && ok "ids: an archive move and main merged into the head are not new ids" || bad "ids archive move: $(irow "$out")"
# the counter on origin (TD-145): an id no take gave fails, whatever LAST says
take_commit() {  # $1 = LAST, $2 = subject, $3 = parent (optional) -> the commit
    ( cd "$IR" && t=$(printf '100644 blob %s\tLAST\n' "$(printf '%s\n' "$1" | git hash-object -w --stdin)" | git mktree) \
      && igit commit-tree "$t" ${3:+-p "$3"} -m "$2" -m "by: someone-else${4:+
$4}" )
}
T12=$(take_commit 12 'TD-012 [skip ci]')
( cd "$IR" && git push -q -f origin "$T12:refs/heads/cadence/ledger-ids" )
E=$(ibranch id-e origin/main 35 TD-012 TD-013)
idpr 35 id-e "TD-012: e" "$E"; plist 35
out=$(irun --pr 35); rc=$?; [ "$(rowstat "$out" ledger)" = FAIL ] && [ $rc -eq 1 ] && irow "$out" | grep -q "TD-013 handed out by nobody" \
  && ! irow "$out" | grep -q "TD-012 handed" && irow "$out" | grep -q -- "--claim" \
  && ok "ids: a new id no take gave fails, naming --claim; one a take gave does not" || bad "ids counter: rc=$rc $(irow "$out")"
# the #2370 shape: LAST has moved past the hand-typed id (a claim skipped 13–14), so LAST alone passed it
T15=$(take_commit 15 'TD-015 [skip ci]' "$T12")
( cd "$IR" && git push -q -f origin "$T15:refs/heads/cadence/ledger-ids" )
out=$(irun --pr 35); [ "$(rowstat "$out" ledger)" = FAIL ] && irow "$out" | grep -q "TD-013 handed out by nobody" \
  && ok "ids: a hand-typed id below a later LAST still fails — the takes decide, not LAST" || bad "ids below LAST: $(irow "$out")"
# a range take gives each id in it; an id older than the counter's first take only warns
T17=$(take_commit 17 'TD-013..TD-014 [skip ci]' "$T15")
( cd "$IR" && git push -q -f origin "$T17:refs/heads/cadence/ledger-ids" )
J=$(ibranch id-j origin/main 40 TD-013 TD-009)
idpr 40 id-j "TD-013: j" "$J"; plist 40
out=$(irun --pr 40); [ "$(rowstat "$out" ledger)" = PASS ] && irow "$out" | grep -q "⚠ TD-009 below the counter's first take (TD-012)" \
  && ! irow "$out" | grep -q "handed out by nobody" \
  && ok "ids: an id in a range take passes; one older than the counter warns" || bad "ids range/before: $(irow "$out")"
irow "$out" | grep -q "no \*\*Taken by:\*\* on TD-013 (\`\*\*Taken by:\*\* someone-else\`)" \
  && ok "ids: an entry with no Taken by warns, naming its take's by" || bad "ids no taken-by: $(irow "$out")"
# TD-145 slice 2: the entry's **Taken by:** against its take's by — the #2370 case fails, naming the by
tbranch() { # tbranch <name> <n> <id> <taken-by> [preamble line]: a branch adding one entry with that field (none when empty)
  ( cd "$IR" && git checkout -q -b "$1" origin/main && { [ -z "${5:-}" ] || sed -i "1a $5" docs/technical_debt.md; } \
    && printf '\n## %s: entry\n\n**Priority:** Low\n**Status:** Open\n%s\n**Why:** x.\n' "$3" "${4:+**Taken by:** $4
}" >> docs/technical_debt.md \
    && igit commit -qam "$1" && git push -q origin "HEAD:refs/pull/$2/head" && git rev-parse HEAD )
}
K=$(tbranch id-k 41 TD-013 '`someone-else` (the take)'); idpr 41 id-k "TD-013: k" "$K"; plist 41
out=$(irun --pr 41); [ "$(rowstat "$out" ledger)" = PASS ] && ! irow "$out" | grep -q "Taken by" \
  && ok "ids: an entry whose Taken by is its take's by passes, a comment after the value read as free" || bad "ids taken-by match: $(irow "$out")"
M=$(tbranch id-m 42 TD-013 me); idpr 42 id-m "TD-013: m" "$M"; plist 42
out=$(irun --pr 42); rc=$?; [ "$(rowstat "$out" ledger)" = FAIL ] && [ $rc -eq 1 ] && irow "$out" | grep -q "TD-013 was handed to someone-else, not me" \
  && ok "ids: an entry whose Taken by is not its take's by fails, naming the take's by (#2370)" || bad "ids taken-by mismatch: rc=$rc $(irow "$out")"
Q=$(tbranch id-q 43 TD-013 '' 'Fields: Owner = grinder | designer'); idpr 43 id-q "TD-013: q" "$Q"; plist 43
out=$(irun --pr 43); [ "$(rowstat "$out" ledger)" = PASS ] && ! irow "$out" | grep -q "no \*\*Taken by" \
  && ok "ids: a ledger that declares Fields: is not told to write a field its format check would refuse" || bad "ids fields-declared: $(irow "$out")"
# a take that names a branch: the default or the PR's own is silent, another warns
T18=$(take_commit 18 'TD-018 [skip ci]' "$T17" "branch: main"); T19=$(take_commit 19 'TD-019 [skip ci]' "$T18" "branch: id-r")
T20=$(take_commit 20 'TD-020 [skip ci]' "$T19" "branch: elsewhere")
( cd "$IR" && git push -q -f origin "$T20:refs/heads/cadence/ledger-ids" )
R=$(ibranch id-r origin/main 44 TD-018 TD-019 TD-020); idpr 44 id-r "TD-018: r" "$R"; plist 44
out=$(irun --pr 44); [ "$(rowstat "$out" ledger)" = PASS ] && irow "$out" | grep -q "taken for another branch: TD-020 (elsewhere)" \
  && ! irow "$out" | grep -q "another branch: [^;]*TD-01[89]" \
  && ok "ids: a take for another branch warns; one for the default or this PR's branch does not" || bad "ids branch: $(irow "$out")"
plist 35
# a counter holding no take it can read: said as such, never "nobody handed it out"
( cd "$IR" && git push -q -f origin "$(take_commit x bad):refs/heads/cadence/ledger-ids" )
out=$(irun --pr 35); irow "$out" | grep -q "holds no take it can read" && ! irow "$out" | grep -q "handed out by nobody" \
  && ok "ids: a counter with no readable take is said, not read as giving nothing" || bad "ids bad counter: $(irow "$out")"
# a merged PR is history: its ids are not judged
pr 37 MERGED id-a "TD-011: a" docs/technical_debt.md; sethead 37 "$A" "$A"; comments 37 "$(c 'cadence-review: SHIP · sonnet · docs · 0' "$BEFORE" "$BEFORE")"
out=$(irun --pr 37); ! irow "$out" | grep -q "already on\|also added\|⚠" && ok "ids: a merged PR's ids are not judged" || bad "ids merged: $(irow "$out")"
printf '[]' > "$FAKE/prlist_since.json"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
