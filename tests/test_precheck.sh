#!/usr/bin/env bash
# precheck.py (TD-117): the repo's own checks, run on a PR's head in a clean worktree, the
# verdict recorded as a cadence/precheck commit status. Offline: `gh` is a PATH shim answering
# `pr view` from a fixture and logging status POSTs; origin is a bare repo serving the PR's
# head under refs/pull/<n>/head, as GitHub does. HOME and git's global config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/precheck.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CADENCE_FORGE
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

FAKE="$TMP/fake"; BIN="$TMP/bin"; mkdir -p "$FAKE" "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
F="$FAKE_DIR"
case "$1 $2" in
  "pr view") n=$(cat "$F/lag_$3" 2>/dev/null || echo 0)   # TD-186: the forge serves the old head for n reads
             if [ "$n" -gt 0 ]; then echo $((n-1)) > "$F/lag_$3"; cat "$F/pr_$3.old.json"; else cat "$F/pr_$3.json"; fi ;;
  "api -X")  [ -f "$F/post_fails" ] && { echo "gh: HTTP 403: Resource not accessible by integration" >&2; exit 1; }
             printf '%s\n' "$*" >> "$F/posts"; echo '{}' ;;
  *) echo "gh-shim: unhandled: $*" >&2; exit 64 ;;
esac
SHIM
chmod +x "$BIN/gh"
export FAKE_DIR="$FAKE" PATH="$BIN:$PATH"

# --- a repo with a bare origin; PR 7's head is a commit only origin's refs/pull/7/head serves
R="$TMP/repo"
git init -q --bare -b main "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
git -C "$R" checkout -q -b main 2>/dev/null; echo base > "$R/base.txt"; git -C "$R" add -A; git -C "$R" commit -qm base
git -C "$R" push -q -u origin main
git -C "$R" checkout -q -b topic; echo head > "$R/only-in-head.txt"; git -C "$R" add -A; git -C "$R" commit -qm head
HEAD_SHA=$(git -C "$R" rev-parse HEAD)
git -C "$R" push -q origin "HEAD:refs/pull/7/head"
git -C "$R" checkout -q main; git -C "$R" branch -q -D topic
git -C "$R" cat-file -e "$HEAD_SHA" 2>/dev/null && git -C "$R" reflog expire --expire=now --all && git -C "$R" gc -q --prune=now 2>/dev/null
git -C "$R" remote set-url origin "$R.git"
pr() { printf '{"number":%s,"url":"u","state":"%s","title":"t","body":"","baseRefName":"main","headRefName":"topic","headRefOid":"%s","files":[]}' "$1" "$2" "$3" > "$FAKE/pr_$1.json"; }
pr 7 OPEN "$HEAD_SHA"; pr 8 MERGED "$HEAD_SHA"
run() { ( cd "$R" && python3 "$SCRIPT" "$@" 2>&1 ); }
cfg() { mkdir -p "$R/docs"; printf 'precheck = "%s"\n' "$1" > "$R/docs/cadence.toml"; }
mkdir -p "$R/docs"
wts() { git -C "$R" worktree list | wc -l; }

# 1. no precheck set: nothing runs, exit 2, no status
out=$(run --pr 7); rc=$?
[ $rc -eq 2 ] && grep -q "no \`precheck\` in docs/cadence.toml" <<< "$out" && [ ! -e "$FAKE/posts" ] \
  && ok "1 no precheck set: exit 2, nothing recorded" || bad "1 rc=$rc $out"

# 2. a passing command runs at the PR's head (a file only the head has), in a worktree that is gone after
cfg 'test -f only-in-head.txt && echo ran-at-head && pwd > $FAKE_DIR/where'
out=$(run --pr 7); rc=$?
[ $rc -eq 0 ] && grep -q "ran-at-head" <<< "$out" && [ "$(wts)" = 1 ] && [ ! -e "$(cat "$FAKE/where")" ] \
  && [ "$(cat "$FAKE/where")" != "$R" ] && [ ! -e "$R/only-in-head.txt" ] \
  && ok "2 passes: run at the head commit fetched from refs/pull/7/head, in a worktree removed afterwards" || bad "2 rc=$rc $out"
grep -q "api -X POST repos/{owner}/{repo}/statuses/$HEAD_SHA -f state=success -f context=cadence/precheck -f description=passed in " "$FAKE/posts" \
  && grep -q "recorded cadence/precheck = success on ${HEAD_SHA:0:7}" <<< "$out" \
  && ok "2b a cadence/precheck success status is recorded on the head" || bad "2b $(cat "$FAKE/posts" 2>&1) / $out"

# 3. a failing command: exit 1, a failure status naming the exit code
: > "$FAKE/posts"; cfg 'echo boom; exit 4'
out=$(run --pr 7); rc=$?
[ $rc -eq 1 ] && grep -q "boom" <<< "$out" && grep -q "failed (exit 4)" <<< "$out" \
  && grep -q "state=failure -f context=cadence/precheck -f description=exit 4 in " "$FAKE/posts" && [ "$(wts)" = 1 ] \
  && ok "3 fails: exit 1, a failure status with the exit code, worktree removed" || bad "3 rc=$rc $out / $(cat "$FAKE/posts")"

# 4. passed but the status cannot be recorded: exit 3, saying so
: > "$FAKE/posts"; cfg 'true'; touch "$FAKE/post_fails"
out=$(run --pr 7); rc=$?; rm -f "$FAKE/post_fails"
[ $rc -eq 3 ] && grep -q "passed, but the cadence/precheck status could not be recorded" <<< "$out" \
  && ok "4 passed, unrecorded: exit 3 — the ci row will not see it" || bad "4 rc=$rc $out"

# 5. --no-record: runs, records nothing
: > "$FAKE/posts"
out=$(run --pr 7 --no-record); rc=$?
[ $rc -eq 0 ] && [ ! -s "$FAKE/posts" ] && ok "5 --no-record: runs, nothing recorded" || bad "5 rc=$rc $out"

# 6. a PR that is not open, and a head origin does not serve: exit 2, nothing run
cfg 'echo SHOULD-NOT-RUN'
out=$(run --pr 8); rc=$?
[ $rc -eq 2 ] && grep -q "PR 8 is merged" <<< "$out" && ! grep -q SHOULD-NOT-RUN <<< "$out" && ok "6 a merged PR: exit 2, nothing run" || bad "6 rc=$rc $out"
pr 9 OPEN 0123456789abcdef0123456789abcdef01234567
out=$(run --pr 9); rc=$?
[ $rc -eq 2 ] && grep -q "cannot fetch PR 9's head 0123456" <<< "$out" && ! grep -q SHOULD-NOT-RUN <<< "$out" \
  && ok "6b a head origin does not serve: exit 2, nothing run" || bad "6b rc=$rc $out"

# 7. the command is the checkout's, never the PR's: a head that rewrites docs/cadence.toml changes nothing
git -C "$R" checkout -q -b evil; printf 'precheck = "true"\n' > "$R/docs/cadence.toml"; git -C "$R" add -A; git -C "$R" commit -qm evil
EVIL=$(git -C "$R" rev-parse HEAD); git -C "$R" push -q origin "HEAD:refs/pull/10/head"; git -C "$R" checkout -q main; git -C "$R" branch -q -D evil
mkdir -p "$R/docs"; printf '%s\n' "precheck = 'test \"\$(grep -c true docs/cadence.toml)\" = 1 && echo head-has-its-own; exit 5'" > "$R/docs/cadence.toml"
pr 10 OPEN "$EVIL"
out=$(run --pr 10); rc=$?
[ $rc -eq 1 ] && grep -q "head-has-its-own" <<< "$out" && ok "7 the checkout's precheck runs, not the one the PR's head carries" || bad "7 rc=$rc $out"

# 8. TD-151: --commit runs on a commit of origin's default branch (its tip, or an ancestor) and records
# the status on it; one not on that branch is refused (exit 2), nothing run; --pr and --commit exclude
cfg 'test -f base.txt && echo ran-on-main && pwd > $FAKE_DIR/where'
echo two > "$R/two.txt"; git -C "$R" add two.txt; git -C "$R" commit -qm two; git -C "$R" push -q origin main
TIP=$(git -C "$R" rev-parse HEAD); OLD=$(git -C "$R" rev-parse HEAD~1)
git -C "$R" reset -q --hard "$OLD"   # the checkout behind origin: --commit fetches the default branch itself
: > "$FAKE/posts"
out=$(run --commit "$TIP"); rc=$?
[ $rc -eq 0 ] && grep -q "ran-on-main" <<< "$out" && grep -q "commit at ${TIP:0:7}" <<< "$out" && [ "$(wts)" = 1 ] \
  && [[ "$(basename "$(dirname "$(cat "$FAKE/where")")")" == precheck-${TIP:0:7}-* ]] \
  && grep -q "statuses/$TIP -f state=success -f context=cadence/precheck" "$FAKE/posts" \
  && ok "8 --commit on origin/main's tip: runs there, in precheck-<sha7>-…/head, records the status" || bad "8 rc=$rc $out / $(cat "$FAKE/posts")"
: > "$FAKE/posts"
out=$(run --commit "${OLD:0:9}" --no-record); rc=$?
[ $rc -eq 0 ] && grep -q "commit at ${OLD:0:7}" <<< "$out" && [ ! -s "$FAKE/posts" ] \
  && ok "8b --commit on an ancestor, by a short sha, with --no-record: runs, nothing recorded" || bad "8b rc=$rc $out"
: > "$FAKE/posts"; cfg 'echo boom; exit 4'
out=$(run --commit "$TIP"); rc=$?
[ $rc -eq 1 ] && grep -q "failed (exit 4)" <<< "$out" && grep -q "statuses/$TIP -f state=failure -f context=cadence/precheck -f description=exit 4 in " "$FAKE/posts" \
  && ok "8b' --commit that fails: exit 1, a failure status on that commit" || bad "8b' rc=$rc $out / $(cat "$FAKE/posts")"
git -C "$R" checkout -q -b side; echo side > "$R/side.txt"; git -C "$R" add -A; git -C "$R" commit -qm side
SIDE=$(git -C "$R" rev-parse HEAD); git -C "$R" checkout -q main; cfg 'echo SHOULD-NOT-RUN'; : > "$FAKE/posts"
out=$(run --commit "$SIDE"); rc=$?
[ $rc -eq 2 ] && grep -q "${SIDE:0:7} is not on origin/main" <<< "$out" && ! grep -q SHOULD-NOT-RUN <<< "$out" && [ ! -s "$FAKE/posts" ] \
  && ok "8c --commit not on the default branch: exit 2, nothing run or recorded" || bad "8c rc=$rc $out"
out=$(run --commit 0123456789abcdef0123456789abcdef01234567); rc=$?
[ $rc -eq 2 ] && grep -q "no commit '0123456789abcdef0123456789abcdef01234567' here" <<< "$out" \
  && ok "8d --commit of an unknown sha: exit 2" || bad "8d rc=$rc $out"
out=$(run --commit "$TIP" --pr 7); rc=$?
[ $rc -eq 2 ] && grep -q "not allowed with" <<< "$out" && ok "8e --pr and --commit together: a usage error" || bad "8e rc=$rc $out"

# 9. TD-155: [precheck-paths] — a PR whose every changed file matches one entry's globs runs that
# entry's command and names it in the status; a PR that also changes an unmatched file runs the
# full precheck; a diff that cannot be read (its base not on origin) and --commit run the full one
paths_cfg() { cat > "$R/docs/cadence.toml" <<'TOML'
precheck = "echo FULL-RAN"
[precheck-paths]
"src/*.py" = "echo WRONG-ENTRY"
"docs/technical_debt*.md docs/user_attention*.md" = "echo NARROW-RAN"
TOML
}
git -C "$R" fetch -q origin
mkpr() {   # mkpr N FILE... : PR N's head is origin/main plus a commit touching FILE..., served at refs/pull/N/head
  local n=$1; shift
  git -C "$R" checkout -q -b "p$n" origin/main
  for f in "$@"; do mkdir -p "$R/$(dirname "$f")"; echo "$n" >> "$R/$f"; done
  git -C "$R" add -- "$@"; git -C "$R" commit -qm "p$n"
  git -C "$R" push -q origin "HEAD:refs/pull/$n/head"; local h; h=$(git -C "$R" rev-parse HEAD)
  git -C "$R" checkout -q main; git -C "$R" branch -q -D "p$n"; pr "$n" OPEN "$h"; echo "$h"
}
H11=$(mkpr 11 docs/technical_debt.md docs/user_attention.md)
H12=$(mkpr 12 docs/technical_debt.md src/code.py)
H13=$(mkpr 13 docs/technical_debt_archive.md)
paths_cfg; : > "$FAKE/posts"
out=$(run --pr 11); rc=$?
[ $rc -eq 0 ] && grep -q NARROW-RAN <<< "$out" && ! grep -q FULL-RAN <<< "$out" \
  && grep -q 'every file PR 11 changes (2) matches \[precheck-paths\] "docs/technical_debt\*.md docs/user_attention\*.md"' <<< "$out" \
  && grep -q "statuses/$H11 -f state=success -f context=cadence/precheck -f description=passed in .*: echo NARROW-RAN" "$FAKE/posts" \
  && ok "9 a ledger-and-board PR runs the matching entry's command; the status names it" || bad "9 rc=$rc $out / $(cat "$FAKE/posts")"
: > "$FAKE/posts"
out=$(run --pr 12); rc=$?
[ $rc -eq 0 ] && grep -q FULL-RAN <<< "$out" && ! grep -q "NARROW-RAN\|WRONG-ENTRY" <<< "$out" \
  && grep -q "statuses/$H12 .*description=passed in .*: echo FULL-RAN" "$FAKE/posts" \
  && ok "9b a PR also changing a file no single entry covers runs the full precheck" || bad "9b rc=$rc $out"
out=$(run --pr 13 --no-record); rc=$?
[ $rc -eq 0 ] && grep -q NARROW-RAN <<< "$out" && ok "9c a glob's * covers a suffix (technical_debt_archive.md)" || bad "9c rc=$rc $out"
printf '{"number":14,"url":"u","state":"OPEN","title":"t","body":"","baseRefName":"gone","headRefName":"x","headRefOid":"%s","files":[]}' "$H11" > "$FAKE/pr_14.json"
git -C "$R" push -q origin "$H11:refs/pull/14/head"
out=$(run --pr 14 --no-record); rc=$?
[ $rc -eq 0 ] && grep -q FULL-RAN <<< "$out" && grep -q "cannot read PR 14's changed files — the full \`precheck\` runs" <<< "$out" \
  && ok "9d a base origin does not serve: the diff is unread, the full precheck runs" || bad "9d rc=$rc $out"
out=$(run --commit "$TIP" --no-record); rc=$?
[ $rc -eq 0 ] && grep -q FULL-RAN <<< "$out" && ok "9e --commit always runs the full precheck" || bad "9e rc=$rc $out"
git -C "$R" checkout -q -b p15 origin/main; git -C "$R" mv two.txt docs/technical_debt_moved.md; git -C "$R" commit -qm p15
git -C "$R" push -q origin "HEAD:refs/pull/15/head"; pr 15 OPEN "$(git -C "$R" rev-parse HEAD)"; git -C "$R" checkout -q main; git -C "$R" branch -q -D p15
out=$(run --pr 15 --no-record); rc=$?
[ $rc -eq 0 ] && grep -q FULL-RAN <<< "$out" && ! grep -q NARROW-RAN <<< "$out" \
  && ok "9g a rename into a matched path counts its old path too: the full precheck runs" || bad "9g rc=$rc $out"
printf 'precheck = "true"\n[precheck-paths]\n"docs/*.md" = ""\n' > "$R/docs/cadence.toml"
out=$(run --pr 11 --no-record); rc=$?
[ $rc -eq 2 ] && grep -q "\[precheck-paths\] 'docs/\*.md' must name globs" <<< "$out" \
  && ok "9f an entry with an empty command: exit 2, nothing run" || bad "9f rc=$rc $out"

# 10. TD-186: the forge's head lags a push. Run from a checkout of the PR's branch whose tip the
# head lacks, --pr re-reads the PR until the head catches up, else refuses naming both shas; --expect
# names the commit outright; a checkout behind the head (someone else pushed) is no lag
cfg 'echo RAN16'
git -C "$R" checkout -q -b t16 origin/main; echo a > "$R/a16.txt"; git -C "$R" add a16.txt; git -C "$R" commit -qm a16
A16=$(git -C "$R" rev-parse HEAD); git -C "$R" push -q origin "HEAD:refs/pull/16/head"
echo b > "$R/b16.txt"; git -C "$R" add b16.txt; git -C "$R" commit -qm b16; B16=$(git -C "$R" rev-parse HEAD)
pj() { printf '{"number":16,"url":"u","state":"OPEN","title":"t","body":"","baseRefName":"main","headRefName":"t16","headRefOid":"%s","files":[]}' "$1"; }
pj "$A16" > "$FAKE/pr_16.json"; : > "$FAKE/posts"
out=$(PRECHECK_HEAD_WAIT=0.3 run --pr 16); rc=$?
[ $rc -eq 2 ] && grep -q "PR 16's head on the forge is $A16, but this checkout's t16 is $B16" <<< "$out" \
  && ! grep -q RAN16 <<< "$out" && [ ! -s "$FAKE/posts" ] \
  && ok "10 a head the local branch is ahead of, for the whole wait: exit 2 naming both shas, nothing run or recorded" || bad "10 rc=$rc $out"
git -C "$R" push -q -f origin "HEAD:refs/pull/16/head"; pj "$A16" > "$FAKE/pr_16.old.json"; pj "$B16" > "$FAKE/pr_16.json"; echo 2 > "$FAKE/lag_16"
out=$(PRECHECK_HEAD_WAIT=5 run --pr 16); rc=$?
[ $rc -eq 0 ] && grep -q RAN16 <<< "$out" && grep -q "passed in .*, on $B16" <<< "$out" \
  && grep -q "recorded cadence/precheck = success on $B16" <<< "$out" && grep -q "statuses/$B16 " "$FAKE/posts" \
  && ! grep -q "statuses/$A16 " "$FAKE/posts" && [ "$(cat "$FAKE/lag_16")" = 0 ] \
  && ok "10b the forge catches up after two reads: the pushed head is tested, its full sha printed and recorded" || bad "10b rc=$rc $out"
git -C "$R" checkout -q main
pj "$A16" > "$FAKE/pr_16.json"; git -C "$R" push -q -f origin "$A16:refs/pull/16/head"; : > "$FAKE/posts"
out=$(PRECHECK_HEAD_WAIT=0.3 run --pr 16 --expect "${B16:0:10}"); rc=$?
[ $rc -eq 2 ] && grep -q "head on the forge is $A16, but --expect is $B16" <<< "$out" && ! grep -q RAN16 <<< "$out" \
  && ok "10c --expect a commit the head is not, from another branch: exit 2 naming both" || bad "10c rc=$rc $out"
out=$(run --pr 16 --expect "$A16" --no-record); rc=$?
[ $rc -eq 0 ] && grep -q RAN16 <<< "$out" && ok "10d --expect the head itself: runs" || bad "10d rc=$rc $out"
out=$(run --pr 16 --expect zzzz); rc=$?
[ $rc -eq 2 ] && grep -q "is no commit here and no sha" <<< "$out" && ok "10e --expect that is no sha: exit 2" || bad "10e rc=$rc $out"
out=$(run --commit "$TIP" --expect "$TIP"); rc=$?
[ $rc -eq 2 ] && grep -q "\-\-expect goes with --pr" <<< "$out" && ok "10f --expect with --commit: a usage error" || bad "10f rc=$rc $out"
git -C "$R" checkout -q -B t16 "$A16"; pj "$B16" > "$FAKE/pr_16.json"; git -C "$R" push -q -f origin "$B16:refs/pull/16/head"
out=$(PRECHECK_HEAD_WAIT=0.3 run --pr 16 --no-record); rc=$?
[ $rc -eq 0 ] && grep -q "passed in .*, on $B16" <<< "$out" \
  && ok "10g a checkout behind the head (another push it has not pulled): no lag, the head runs" || bad "10g rc=$rc $out"
git -C "$R" checkout -q main
# origin's branch (git sees a push at once) ahead of the PR's head: refused from any checkout;
# a fork's PR is never compared; PRECHECK_HEAD_WAIT that is no bounded number is a usage error
git -C "$R" push -q -f origin "$B16:refs/heads/t16"; pj "$A16" > "$FAKE/pr_16.json"; git -C "$R" push -q -f origin "$A16:refs/pull/16/head"
out=$(PRECHECK_HEAD_WAIT=0.3 run --pr 16); rc=$?
[ $rc -eq 2 ] && grep -q "head on the forge is $A16, but origin's t16 is $B16" <<< "$out" && ! grep -q RAN16 <<< "$out" \
  && ok "10h origin's branch at a commit the PR's head is not, run from main: exit 2 naming both" || bad "10h rc=$rc $out"
sed 's/"files":\[\]}/"files":[],"isCrossRepository":true}/' "$FAKE/pr_16.json" > "$FAKE/pr_16.x"; mv "$FAKE/pr_16.x" "$FAKE/pr_16.json"
out=$(PRECHECK_HEAD_WAIT=0.3 run --pr 16 --no-record); rc=$?
[ $rc -eq 0 ] && grep -q "on $A16" <<< "$out" && ok "10i a fork's PR (isCrossRepository): origin's same-named branch is not its head" || bad "10i rc=$rc $out"
for v in abc inf nan -1; do
  out=$(PRECHECK_HEAD_WAIT=$v run --pr 16 --no-record); rc=$?
  [ $rc -eq 2 ] && grep -q "PRECHECK_HEAD_WAIT='$v' is no number of seconds" <<< "$out" && ! grep -q RAN16 <<< "$out" \
    && ok "10j PRECHECK_HEAD_WAIT=$v: exit 2, nothing run" || bad "10j $v rc=$rc $out"
done
out=$(run --pr 16 --expect=-x); rc=$?
[ $rc -eq 2 ] && grep -q "is no sha" <<< "$out" && ok "10k --expect starting with a dash: exit 2" || bad "10k rc=$rc $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
