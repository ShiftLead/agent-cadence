#!/usr/bin/env bash
# cadence_changes.py — convention changes reach a session once per worktree (cadence §3,
# 2026-09-11). Offline: a clone with a bare origin; "origin moved on" is simulated by
# pushing from a second clone and fetching, never by network. Dates derive from the run
# date (TD-24). The hook must print once, then stay silent, and never write into the repo.
set -u
export TZ=UTC  # TD-209: the fixtures below are UTC dates, and the script's today must be too (west of UTC they differ after its date rolls over)
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/cadence_changes.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset SHIFTLEAD_SESSION CADENCE_ATTENTION_SCOPE  # an unattended session's scope must not leak in (TD-077)
PASS=0; FAIL=0
cmd=""
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date -u +%F); OLD=$(date -u -d "40 days ago" +%F); RECENT=$(date -u -d "3 days ago" +%F)

R="$TMP/repo"; W="$TMP/writer"
git init -q --bare -b main "$R.git"
git clone -q "$R.git" "$R" 2>/dev/null; git clone -q "$R.git" "$W" 2>/dev/null
for d in "$R" "$W"; do git -C "$d" config user.email t@t; git -C "$d" config user.name t; git -C "$d" checkout -q -b main 2>/dev/null; done
mkdir -p "$R/docs" "$R/scripts"; cp "$SCRIPT" "$R/scripts/"
cat > "$R/docs/cadence-changes.md" <<M
# Cadence changes
## $OLD — an old rule
Do: the old thing.
See: cadence.md §1.
M
( cd "$R" && git add . && git commit -qm base && git push -q -u origin main )
git -C "$W" pull -q origin main 2>/dev/null; git -C "$W" checkout -q main 2>/dev/null

# origin moves on: the writer adds a new entry and pushes; the repo only fetches
cat > "$W/docs/cadence-changes.md" <<M
# Cadence changes
## $RECENT — the review leaves evidence on the PR
Do: post the cadence-review: comment.
See: cadence.md §4.
## $OLD — an old rule
Do: the old thing.
See: cadence.md §1.
M
( cd "$W" && git add . && git commit -qm "new rule" && git push -q origin main )
git -C "$R" fetch -q origin

hook() { ( cd "${1:-$R}" && python3 "$SCRIPT" --hook 2>&1 ); }

# --- 1) entry on origin, absent locally -> printed with the behind line; the old one is not
out=$(hook); rc=$?
echo "$out" | grep -q "1 cadence change this worktree" && echo "$out" | grep -q "review leaves evidence" && ! echo "$out" | grep -q "an old rule" && echo "$out" | grep -q "behind origin/main" && [ $rc -eq 0 ] && ok "unseen origin entry printed once with behind line" || bad "first hook: rc=$rc
$out"
# --- 2) second session start in the same worktree: silent (marker), and the marker is outside the tree
out=$(hook); [ -z "$out" ] && ok "second start is silent" || bad "second start printed: $out"
[ -f "$R/.git/cadence-changes-seen" ] && [ -z "$(git -C "$R" status --porcelain)" ] && ok "marker lives in .git, tree untouched" || bad "marker: $(ls -a "$R/.git" | grep seen) status=$(git -C "$R" status --porcelain)"

# --- 3) a new worktree of the same repo: its own marker, so it prints once too, then silent
git -C "$R" worktree add -q -b topic "$R/.claude/worktrees/topic" origin/main
out=$(hook "$R/.claude/worktrees/topic"); echo "$out" | grep -q "review leaves evidence" && ok "new worktree prints once" || bad "worktree first: $out"
out=$(hook "$R/.claude/worktrees/topic"); [ -z "$out" ] && ok "new worktree then silent" || bad "worktree second: $out"
[ -f "$R/.git/worktrees/topic/cadence-changes-seen" ] && ok "worktree marker is per-worktree" || bad "worktree marker missing"
# the worktree is up to date with origin (recent entry present locally), so no behind line
out=$(cd "$R/.claude/worktrees/topic" && rm -f "$R/.git/worktrees/topic/cadence-changes-seen" && python3 "$SCRIPT" --hook)
echo "$out" | grep -q "review leaves evidence" && ! echo "$out" | grep -q "behind" && ok "up-to-date worktree: recent entry printed, no behind line" || bad "recent rule: $out"

# --- 4) only old entries anywhere -> silent, exit 0
rm -f "$R/.git/worktrees/topic/cadence-changes-seen"
cat > "$W/docs/cadence-changes.md" <<M
# Cadence changes
## $OLD — an old rule
Do: the old thing.
M
( cd "$W" && git add . && git commit -qm "only old" && git push -q origin main ); git -C "$R" fetch -q origin
git -C "$R/.claude/worktrees/topic" pull -q --ff-only origin main 2>/dev/null
out=$(hook "$R/.claude/worktrees/topic"); rc=$?; [ -z "$out" ] && [ $rc -eq 0 ] && ok "only old entries: silent" || bad "old only: rc=$rc $out"

# --- 5) origin has no such file -> silent, exit 0; not a git repo -> silent, exit 0
( cd "$W" && git rm -q docs/cadence-changes.md && git commit -qm rm && git push -q origin main ); git -C "$R" fetch -q origin
out=$(hook); rc=$?; [ -z "$out" ] && [ $rc -eq 0 ] && ok "no file on origin: silent" || bad "no file: rc=$rc $out"
out=$(cd "$TMP" && python3 "$SCRIPT" --hook 2>&1); rc=$?; [ -z "$out" ] && [ $rc -eq 0 ] && ok "outside a repo: silent" || bad "no repo: rc=$rc $out"

# --- 6) malformed file -> no traceback
mkdir -p "$W/docs"; cat > "$W/docs/cadence-changes.md" <<M
## not-a-date — broken
## $RECENT — fine one
Do: x.
M
( cd "$W" && git add . && git commit -qm bad && git push -q origin main ); git -C "$R" fetch -q origin; rm -f "$R/.git/cadence-changes-seen"
out=$(hook); rc=$?; ! echo "$out" | grep -q Traceback && echo "$out" | grep -q "fine one" && [ $rc -eq 0 ] && ok "malformed heading skipped, no traceback" || bad "malformed: rc=$rc $out"

# --- 7) --list / --since / --json (no marker written)
rm -f "$R/.git/cadence-changes-seen"
out=$(cd "$R" && python3 "$SCRIPT" --list --since 7d); echo "$out" | grep -q "fine one" && [ ! -f "$R/.git/cadence-changes-seen" ] && ok "--list --since, no marker" || bad "list: $out"
out=$(cd "$R" && python3 "$SCRIPT" --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); e=d["entries"][0]; assert d["ref"]=="origin/main" and e["title"]=="fine one" and e["landed"] and "Do: x." in e["body"]' && ok "--json has heading, body, landed" || bad "json: $out"
out=$(cd "$R" && python3 "$SCRIPT" --list --since garbage 2>&1); rc=$?; [ $rc -eq 2 ] && ok "bad --since exits 2" || bad "since rc=$rc"

# --- 8) the runner (what the seeded settings line calls) names this hook; run through the runner in a
#        worktree (the line runs the MAIN checkout's runner, TD-055 b — the worktree carries none)
#        with the script -> prints once; with the script removed -> silent, exit 0
"$DC/files/scripts/cadence_hooks.sh" --list | grep -qx "scripts/cadence_changes.py --hook" && ok "runner set includes cadence_changes.py --hook" || bad "runner --list lacks this hook"
[ -n "$cmd" ] || cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][0]["command"])' "$DC/files/.claude/settings.json")
W2="$R/.claude/worktrees/topic"; cp "$DC/files/scripts/cadence_hooks.sh" "$R/scripts/"; rm -f "$W2/scripts/cadence_hooks.sh"; rm -f "$R/.git/worktrees/topic/cadence-changes-seen"
out=$(cd "$W2" && CLAUDE_PROJECT_DIR="$W2" bash -c "$cmd" </dev/null 2>&1); rc=$?
echo "$out" | grep -q "cadence change this worktree has not seen" && [ $rc -eq 0 ] && ok "seeded line via the runner prints the unseen entry" || bad "runner line: rc=$rc $out"
mv "$R/scripts/cadence_changes.py" "$TMP/cc.keep"; rm -f "$R/.git/worktrees/topic/cadence-changes-seen"
out=$(cd "$W2" && CLAUDE_PROJECT_DIR="$W2" bash -c "$cmd" </dev/null 2>&1); rc=$?
mv "$TMP/cc.keep" "$R/scripts/cadence_changes.py"
[ -z "$out" ] && [ $rc -eq 0 ] && ok "seeded line without the script (in the main checkout): silent, exit 0" || bad "settings line: rc=$rc $out"

# --- 9) default branch is `trunk` and origin/HEAD is unset: --hook still finds the file; nothing resolvable -> --list exits 2
T="$TMP/trunk"; git init -q --bare -b trunk "$T.git"; git clone -q "$T.git" "$T" 2>/dev/null
( cd "$T" && git config user.email t@t && git config user.name t && git checkout -q -b trunk 2>/dev/null && mkdir -p docs && printf '## %s — trunk rule\nDo: y.\n' "$RECENT" > docs/cadence-changes.md && git add . && git commit -qm t && git push -q -u origin trunk && git remote set-head origin trunk )
out=$(cd "$T" && python3 "$SCRIPT" --hook); echo "$out" | grep -q "trunk rule" && ok "default branch trunk via origin/HEAD" || bad "trunk: $out"
( cd "$T" && git remote set-head origin -d )
out=$(cd "$T" && python3 "$SCRIPT" --list 2>&1); rc=$?; [ $rc -eq 2 ] && echo "$out" | grep -q "cannot read origin" && ok "no resolvable default branch: --list says so, exit 2" || bad "unresolvable: rc=$rc $out"
out=$(cd "$T" && rm -f .git/cadence-changes-seen && python3 "$SCRIPT" --hook 2>&1); rc=$?; [ -z "$out" ] && [ $rc -eq 0 ] && ok "no resolvable default branch: --hook silent, exit 0" || bad "unresolvable hook: rc=$rc $out"


# --- TD-038: the changes file is found beside the script's ../docs when it runs from inside
# the repo — scripts/ -> docs/ in a consumer, files/scripts/ -> files/docs/ in agent-cadence
# itself, where a hardcoded docs/ read nothing and the hook was silent forever.
D="$TMP/dc"; git init -q --bare -b main "$D.git"; git clone -q "$D.git" "$D" 2>/dev/null
git -C "$D" config user.email t@t; git -C "$D" config user.name t; git -C "$D" checkout -q -b main 2>/dev/null
mkdir -p "$D/files/docs" "$D/files/scripts"; cp "$SCRIPT" "$D/files/scripts/"
printf '# Cadence changes\n## %s — a dogfooded rule\nDo: it.\nSee: here.\n' "$RECENT" > "$D/files/docs/cadence-changes.md"
( cd "$D" && git add . && git commit -qm base && git push -q -u origin main )
out=$(cd "$D" && python3 files/scripts/cadence_changes.py --hook 2>&1)
echo "$out" | grep -q "a dogfooded rule" && ok "files/scripts copy reads files/docs/cadence-changes.md" || bad "files layout: $out"
out=$(cd "$R" && python3 scripts/cadence_changes.py --list 2>&1)
ref=$(cd "$R" && python3 "$SCRIPT" --list 2>&1)
[ -n "$out" ] && [ "$out" = "$ref" ] && ok "consumer's scripts/ copy reads docs/cadence-changes.md, same as the out-of-tree run" || bad "consumer layout: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
