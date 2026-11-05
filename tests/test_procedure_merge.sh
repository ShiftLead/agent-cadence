#!/usr/bin/env bash
# TD-233 (TD-177's design 2 and 7): the procedure's step 5 line, taken from
# files/docs/procedures/cadence.md as written and run whole against a gh and a glab shim. The
# GitHub form passes --squash --match-head-commit --subject --body-file and the GitLab form
# --yes --squash --sha --squash-message, with subject and body in the one string. Neither ever passes
# --delete-branch. A gate that did not pass, or one that wrote nothing, reaches no merge.
#
# The real forge.py composes the message. check_cadence.py is a stub that writes the gate file the
# test names, since the gate's own rows are tests/test_check_cadence.sh's.
# Offline: HOME, XDG_CONFIG_HOME, AGENT_CADENCE_REG_DIR and git config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
PROC="$DC/files/docs/procedures/cadence.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
unset AGENT_MODEL_FILE CADENCE_FORGE
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# step 5's two lines: the ```bash blocks between "5. Merge only on exit 0" and the next step's
# section, the one whose line merges with gh and the one that merges with glab
blocks=$(awk '/^5\. Merge only on exit 0/ { on = 1 } on && /^## / { exit }
              on && /^ *```bash/ { inb = 1; next } on && inb && /^ *```/ { inb = 0; next }
              on && inb { sub(/^ +/, ""); print }' "$PROC")
GH_LINE=$(grep -m1 ' gh pr merge ' <<< "$blocks")
GL_LINE=$(grep -m1 ' glab mr merge ' <<< "$blocks")
[ -n "$GH_LINE" ] && [ -n "$GL_LINE" ] && [ "$(wc -l <<< "$blocks")" -eq 2 ] \
  && ok "step 5 holds two lines, a GitHub one and a GitLab one" || bad "step 5's lines: '$blocks'"
for l in "$GH_LINE" "$GL_LINE"; do
  case "$l" in *--delete-branch*) bad "a step 5 line passes --delete-branch: $l" ;; esac
done
ok "neither step 5 line passes --delete-branch"

BIN="$TMP/bin"; mkdir -p "$BIN"
# gh: the reads forge.py makes, and `pr merge` logged one argument a line with the body file's text
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  "pr view"*) cat "$F/pr.json" ;;
  "api --paginate repos/{owner}/{repo}/pulls/"*"/commits") cat "$F/commits.json" ;;
  "api repos/{owner}/{repo}/pulls/"*) echo '{"commits":2}' ;;
  "pr merge"*)
    printf '%s\n' "$@" > "$F/merge.args"
    prev=""; for a in "$@"; do [ "$prev" = --body-file ] && cat "$a" > "$F/merge.body"; prev=$a; done ;;
  *) echo "gh-shim: unhandled: $*" >&2; exit 64 ;;
esac
SHIM
# glab: the same reads through `glab api`, and `mr merge` logged
cat > "$BIN/glab" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  "api "*"projects/"*"/merge_requests/9/commits"*) cat "$F/gl_commits.json" ;;
  "api "*"projects/"*"/merge_requests/9/diffs"*) echo '[]' ;;
  "api "*"projects/"*"/merge_requests/9") echo '{"iid":9,"title":"Add a thing","state":"opened","sha":"abc1234"}' ;;
  "mr merge"*) printf '%s\n' "$@" > "$F/merge.args" ;;
  *) echo "glab-shim: unhandled: $*" >&2; exit 64 ;;
esac
SHIM
# the gate stub: writes $GATE_TEXT to the --trailers file and exits $GATE_RC
mkdir -p "$TMP/stub"
cat > "$TMP/stub/check_cadence.py" <<'STUB'
import os, sys
path = sys.argv[sys.argv.index("--trailers") + 1]
open(path, "w").write(os.environ.get("GATE_TEXT", ""))
sys.exit(int(os.environ.get("GATE_RC", "0")))
STUB
chmod +x "$BIN/gh" "$BIN/glab"
F="$TMP/f"; mkdir -p "$F"
printf '%s%s' '[{"commit":{"message":"one\n\nCo-Authored-By: g1 <g1@x>\nAgent-Model: a/b\n","author":{"name":"Pat","email":"pat@x"}}}]' \
  '[{"commit":{"message":"two\n","author":{"name":"Pat","email":"pat@x"}}}]' > "$F/commits.json"
echo '{"number":9,"title":"Add a thing","state":"OPEN","headRefOid":"abc1234","commits":[{},{}]}' > "$F/pr.json"
echo '[{"message":"two\n","author_name":"Pat","author_email":"pat@x"},{"message":"one\n\nCo-Authored-By: g1 <g1@x>\n","author_name":"Pat","author_email":"pat@x"}]' > "$F/gl_commits.json"

repo() {  # <origin url>: a consumer-shaped clone whose scripts/ holds the stub gate and the real forge.py
  R="$TMP/r$RANDOM"; git init -q -b main "$R"; git -C "$R" remote add origin "$1"
  git -C "$R" config user.name "Pat Person"
  mkdir -p "$R/scripts"; ln -s "$S/forge.py" "$R/scripts/forge.py"   # its imports resolve beside the real file
  cp "$TMP/stub/check_cadence.py" "$R/scripts/check_cadence.py"
}
run() {  # <line> — step 5's line for PR 9, run whole by bash in $R
  rm -f "$F/merge.args" "$F/merge.body"
  (cd "$R" && PATH="$BIN:$PATH" F="$F" AGENT_NAME=g1 AGENT_MODEL=a/b bash -c "${1//<n>/9}" >"$F/out" 2>&1)
}
PASSED=$'pr 9\nexpect abc1234\nReview: sonnet (SHIP)\nPrecheck: abc1234\n'
FAILED=$'pr 9\nexpect abc1234\nunverified 1 ci\n'

# 1. GitHub, a gate that passed: one merge, the composed message, pinned to the gate's head
repo git@github.com:o/r.git
GATE_TEXT="$PASSED" GATE_RC=0 run "$GH_LINE"; rc=$?
args=$(cat "$F/merge.args" 2>/dev/null)
[ $rc -eq 0 ] && [ "$(sed -n 1,3p <<< "$args" | tr '\n' ' ')" = "pr merge 9 " ] \
  && grep -qx -- --squash <<< "$args" && grep -A1 -x -- --match-head-commit <<< "$args" | grep -qx abc1234 \
  && grep -A1 -x -- --subject <<< "$args" | grep -qx "Add a thing (#9)" && grep -qx -- --body-file <<< "$args" \
  && ! grep -q -- --delete-branch <<< "$args" \
  && ok "1 GitHub: gh pr merge 9 --squash --match-head-commit <the gate's head> --subject '<title> (#9)' --body-file" \
  || bad "1 rc=$rc args: $args | $(cat "$F/out")"
[ "$(tail -1 "$F/merge.body" 2>/dev/null)" = "Merged-by: g1 (a/b)" ] && grep -qx "Review: sonnet (SHIP)" "$F/merge.body" \
  && ok "1b the body file is the composed message: the gate's Review: in it, Merged-by: last" || bad "1b body: $(cat "$F/merge.body" 2>/dev/null)"

# 2. GitHub, a gate that did not pass, run without --unverified: no merge
GATE_TEXT="$FAILED" GATE_RC=1 run "$GH_LINE"; rc=$?
[ $rc -ne 0 ] && [ ! -e "$F/merge.args" ] && grep -q "refused" "$F/out" \
  && ok "2 GitHub: a gate that did not pass reaches no merge" || bad "2 rc=$rc merged=$(cat "$F/merge.args" 2>/dev/null) $(cat "$F/out")"
# 2b. with step 5's allowance (--unverified added to squash-message), it merges and says why
GATE_TEXT="$FAILED" GATE_RC=3 run "${GH_LINE/--out \"\$m\"/--out \"\$m\" --unverified \"the runner is down\"}"; rc=$?
[ $rc -eq 0 ] && [ -e "$F/merge.args" ] && grep -qx "Merge-override: 1 ci — the runner is down" "$F/merge.body" \
  && ok "2b GitHub: --unverified added to squash-message merges, with a Merge-override: line" || bad "2b rc=$rc $(cat "$F/out") $(cat "$F/merge.body" 2>/dev/null)"
# 2c. a gate that wrote nothing (it could not read the PR): no merge
GATE_TEXT="" GATE_RC=2 run "$GH_LINE"; rc=$?
[ $rc -ne 0 ] && [ ! -e "$F/merge.args" ] && ok "2c GitHub: an empty gate file reaches no merge" || bad "2c rc=$rc $(cat "$F/out")"

# 3. GitLab, a gate that passed: glab mr merge 9 --yes --squash --sha <head> --squash-message "<subject>\n\n<body>"
repo git@gitlab.com:g/r.git
GATE_TEXT="$PASSED" GATE_RC=0 run "$GL_LINE"; rc=$?
args=$(cat "$F/merge.args" 2>/dev/null)
msg=$(python3 -c 'import sys; a=open(sys.argv[1]).read().split("\n"); i=a.index("--squash-message"); print("\n".join(a[i+1:]).rstrip("\n"))' "$F/merge.args" 2>/dev/null)
[ $rc -eq 0 ] && [ "$(sed -n 1,3p <<< "$args" | tr '\n' ' ')" = "mr merge 9 " ] && grep -qx -- --yes <<< "$args" \
  && grep -qx -- --squash <<< "$args" && grep -A1 -x -- --sha <<< "$args" | grep -qx abc1234 \
  && [ "$(head -2 <<< "$msg")" = "$(printf 'Add a thing (!9)\n')" ] && [ "$(tail -1 <<< "$msg")" = "Merged-by: g1 (a/b)" ] \
  && ! grep -q -- --delete-branch <<< "$args" \
  && ok "3 GitLab: glab mr merge 9 --yes --squash --sha <the gate's head> --squash-message, subject and body in one string" \
  || bad "3 rc=$rc args: $args | $(cat "$F/out")"
# 4. GitLab, a gate that did not pass: no merge
GATE_TEXT="$FAILED" GATE_RC=1 run "$GL_LINE"; rc=$?
[ $rc -ne 0 ] && [ ! -e "$F/merge.args" ] && ok "4 GitLab: a gate that did not pass reaches no merge" || bad "4 rc=$rc $(cat "$F/out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
