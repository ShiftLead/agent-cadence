#!/usr/bin/env bash
# list_sessions.py — munge() and project_dirs(), the two functions that decide WHICH
# transcripts a person sees when looking for a session to resume. munge() has regressed
# once already (README: a repo path with `_` mapped to a project dir that does not exist,
# and the index said "no project dirs" — indistinguishable from a repo with no sessions).
# Offline: HOME is a temp dir, so the real ~/.claude/projects is never read.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$HOME/.claude/projects"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

py() { local c="$1"; shift; PYTHONPATH="$DC/files/scripts" python3 -c "import sys; from pathlib import Path; import list_sessions as L; $c" "$@"; }

# --- 1) munge: every non-alphanumeric character becomes '-', not only '/' and '.'
while IFS='|' read -r in want; do
    got=$(py "print(L.munge(Path(sys.argv[1])))" "$in" 2>&1)
    [ "$got" = "$want" ] && ok "munge '$in' -> '$want'" || bad "munge '$in': got '$got', want '$want'"
done <<'CASES'
/workspaces/my_repo|-workspaces-my-repo
/home/u/agent-cadence|-home-u-agent-cadence
/home/u/repo/.claude/worktrees/topic|-home-u-repo--claude-worktrees-topic
/home/u/my repo+x|-home-u-my-repo-x
CASES

# --- 1b) TD-11: Claude Code counts UTF-16 code units and caps the name at 200 with a hash.
#         Every expectation below is Claude Code 2.1.283's own JS (`k`/`qx`/`Le`/`KJ`, copied
#         from its bundle) run under node — not this script's output.
LONG="/home/u/$(printf 'a%.0s' $(seq 1 230))/repo"
B192="/home/u/$(printf 'b%.0s' $(seq 1 192))"
while IFS='|' read -r label in want; do
    got=$(py "print(L.munge(Path(sys.argv[1])))" "$in" 2>&1)
    [ "$got" = "$want" ] && ok "munge: $label" || bad "munge $label: got '$got', want '$want'"
done <<CASES
accented letter (NFC) is one dash|/home/u/café|-home-u-caf-
decomposed accent is letter plus one dash|/home/u/caf$(printf 'e\xcc\x81')|-home-u-cafe-
CJK: one dash each|/home/u/中文/r|-home-u----r
emoji (outside the BMP) is TWO dashes|/home/u/x😀y|-home-u-x--y
exactly 200 units: no cap|$B192|-home-u-$(printf 'b%.0s' $(seq 1 192))
past 200: cut at 200, base-36 hash of the whole path|$LONG|-home-u-$(printf 'a%.0s' $(seq 1 192))-voz9t2
CASES

# --- 2) project_dirs: the repo's own dir plus its worktrees' dirs, and nothing that
#        merely shares a prefix with the repo's name
P="$HOME/.claude/projects"
mkdir -p "$P/-home-u-repo" "$P/-home-u-repo--claude-worktrees-a" "$P/-home-u-repo--claude-worktrees-b-c" \
         "$P/-home-u-repo2" "$P/-home-u-repo-other"
got=$(py "print(' '.join(sorted(d.name for d in L.project_dirs(Path('/home/u/repo')))))" 2>&1)
want="-home-u-repo -home-u-repo--claude-worktrees-a -home-u-repo--claude-worktrees-b-c"
[ "$got" = "$want" ] && ok "project_dirs: own dir + worktree dirs, not repo2 / repo-other" || bad "project_dirs: got '$got'"
# ... and a repo with no dir of its own still finds its worktrees' sessions
rm -rf "$P/-home-u-repo"
got=$(py "print(' '.join(sorted(d.name for d in L.project_dirs(Path('/home/u/repo')))))" 2>&1)
[ "$got" = "-home-u-repo--claude-worktrees-a -home-u-repo--claude-worktrees-b-c" ] \
    && ok "project_dirs: worktree dirs found without the repo's own" || bad "project_dirs without own dir: got '$got'"
# ... and no projects dir at all is an empty list, not a traceback
rm -rf "$P"
got=$(py "print(len(L.project_dirs(Path('/home/u/repo'))))" 2>&1)
[ "$got" = "0" ] && ok "project_dirs: no ~/.claude/projects -> []" || bad "no projects dir: got '$got'"

# --- 3) transcripts (TD-046): two sessions — one in the repo, one in a worktree — plus a
#        degenerate one and an old one, read end to end through main(). Dates derive from now.
R="$TMP/repo"; mkdir -p "$R/docs" "$HOME/.claude/sessions"
P="$HOME/.claude/projects"; OWN="$P/$(py "print(L.munge(Path(sys.argv[1])))" "$R")"; WT="$OWN--claude-worktrees-topic"
mkdir -p "$OWN" "$WT"
A=aaaaaaaa-1111-2222-3333-444444444444; B=bbbbbbbb-1111-2222-3333-444444444444
D=dddddddd-1111-2222-3333-444444444444; O=00000000-1111-2222-3333-444444444444
T0=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S.000Z)
cat > "$OWN/$A.jsonl" <<J
{"type":"user","timestamp":"$T0","gitBranch":"main","slug":"fix-parser","message":{"content":"<command-name>/clear</command-name>"}}
{"type":"user","timestamp":"$T0","message":{"content":[{"type":"text","text":"Fix the   parser bug in nudge"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at it."}]}}
{"type":"user","message":{"content":[{"type":"text","text":"also rename the helper"}]}}
{"type":"summary","summary":"Parser fix session"}
{"type":"user","isCompactSummary":true,"message":{"content":[{"type":"text","text":"This session is being continued from a previous conversation that ran out of context. The conversation is summarized below: Recap: parser fixed, tests added"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Done: parser fixed and PR opened"}]}}
J
cat > "$WT/$B.jsonl" <<J
{"type":"user","timestamp":"$T0","gitBranch":"td099-topic","message":{"content":"Start the topic work"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"WIP on the topic"}]}}
J
printf '%s\n' '{"type":"user","message":{"content":"<system-reminder>noise</system-reminder>"}}' > "$OWN/$D.jsonl"
cat > "$OWN/$O.jsonl" <<J
{"type":"user","timestamp":"$T0","message":{"content":"an old session"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"old answer"}]}}
J
touch -d '1 hour ago' "$OWN/$A.jsonl"; touch -d '10 minutes ago' "$WT/$B.jsonl"; touch -d '40 days ago' "$OWN/$O.jsonl"
echo "- [ ] $(date +%F) (session ${B:0:8} on testhost) — review the topic. Due: $(date +%F)." > "$R/docs/user_attention.md"
out=$(PYTHONPATH="$DC/files/scripts" python3 "$DC/files/scripts/list_sessions.py" --repo "$R" 2>&1); rc=$?
ids=$(grep -o '^● [0-9a-f-]*' <<< "$out" | sed 's/^● //')
[ $rc -eq 0 ] && [ "$(echo $ids)" = "$B $A $O" ] && ok "three sessions, newest first; the degenerate one (harness noise only) dropped" || bad "order/set rc=$rc: $(echo $ids)"
blk() { awk -v id="$1" '/^● /{on = index($0, id) > 0} on' <<< "$out"; }
blk "$A" | grep -q "started: Fix the parser bug in nudge" && ! blk "$A" | grep -q "command-name\|rename the helper" \
    && ok "started: the first REAL user message, whitespace folded, the slash-command wrapper skipped" || bad "A started: $(blk "$A")"
blk "$A" | grep -q "ended:   Done: parser fixed and PR opened" && ok "ended: the LAST assistant text" || bad "A ended: $(blk "$A")"
blk "$A" | grep -q "recap:   Recap: parser fixed, tests added" && ! blk "$A" | grep -q "being continued" && blk "$A" | grep -q "summary: Parser fix session" && blk "$A" | grep -q "(fix-parser)" \
    && ok "recap (the continuation boilerplate stripped), summary and slug read" || bad "A recap/summary/slug: $(blk "$A")"
blk "$B" | grep -q "PARKED ITEMS ON BOARD, .*/repo/.claude/worktrees/topic, branch:td099-topic" \
    && blk "$B" | grep -q "parked:  .*review the topic" \
    && ok "the worktree session: where = the worktree, its branch, and its board item" || bad "B flags: $(blk "$B")"
out=$(PYTHONPATH="$DC/files/scripts" python3 "$DC/files/scripts/list_sessions.py" --repo "$R" --days 30 --format md 2>&1)
! grep -q "${O:0:8}" <<< "$out" && grep -q "^| \[\`${B:0:8}\`\](#${B:0:8})" <<< "$out" && grep -q "^### ${A:0:8} — fix-parser" <<< "$out" \
    && ok "--days 30 drops the 40-day-old session; --format md links each row to its details" || bad "md/days: $(head -5 <<< "$out")"
out=$(PYTHONPATH="$DC/files/scripts" python3 "$DC/files/scripts/list_sessions.py" --repo "$TMP/elsewhere" 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "No session transcripts found" <<< "$out" && ok "a repo with no project dirs: says so, exit 1" || bad "no dirs rc=$rc: $out"

# --- 4) generate_session_index.sh: the cron wrapper writes the md index atomically, and a
#        failed run leaves the previous index as it was (never a truncated file)
GEN="$DC/files/scripts/generate_session_index.sh"; IDX="$TMP/index.md"
"$GEN" "$R" "$IDX" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && head -1 "$IDX" | grep -q "^# Claude Code session index — $R$" && grep -q "^| \[\`${A:0:8}\`\]" "$IDX" \
    && ok "generate_session_index: header + the md table for the repo" || bad "gen rc=$rc: $(head -3 "$IDX" 2>&1)"
cp "$IDX" "$TMP/index.before"
PYTHON=false "$GEN" "$R" "$IDX" >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && cmp -s "$IDX" "$TMP/index.before" && [ ! -e "$IDX.tmp" ] \
    && ok "generate_session_index: a failing run exits non-zero, keeps the old index, leaves no .tmp" || bad "gen failure rc=$rc"
"$GEN" "$R" "$IDX" "$TMP/other" >/dev/null 2>&1
head -1 "$IDX" | grep -q "^# Claude Code session index — $R, $TMP/other$" && ok "generate_session_index: extra repos join the header" || bad "gen multi: $(head -1 "$IDX")"
# run through the launcher (TD-129) the script sits in a cached tree, not the repo: with no REPO
# argument it indexes the repo CADENCE_REPO_ROOT names, never the tree's parent
mkdir -p "$TMP/tree/files" && cp -r "$DC/files/scripts" "$TMP/tree/files/"
rm -f "$R/docs/session_index.md"
(cd "$R" && CADENCE_REPO_ROOT="$R" bash "$TMP/tree/files/scripts/generate_session_index.sh" >/dev/null 2>&1); rc=$?
[ $rc -eq 0 ] && head -1 "$R/docs/session_index.md" 2>/dev/null | grep -q "^# Claude Code session index — $R$" && [ ! -e "$TMP/tree/files/docs" ] \
    && ok "generate_session_index: no REPO argument — the repo CADENCE_REPO_ROOT names" || bad "gen CADENCE_REPO_ROOT rc=$rc: $(ls "$R/docs" "$TMP/tree/files")"

# --- 5) TD-28: work on repo A done from a session in repo B — --mentioning finds it there,
#        --roster reads the machine roster (cadence §9: canonicalized, deduped, gone paths skipped).
#        Its own fixture (P may have been removed above).
P="$HOME/.claude/projects"; mkdir -p "$P"
RA="$TMP/ra"; RB="$TMP/rb"; mkdir -p "$RA" "$RB"
DA="$P/$(py "print(L.munge(Path(sys.argv[1])))" "$RA")"; DB="$P/$(py "print(L.munge(Path(sys.argv[1])))" "$RB")"; mkdir -p "$DA" "$DB"
T5=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z)
S1=11111111-1111-2222-3333-444444444444; M=eeeeeeee-1111-2222-3333-444444444444; N=ffffffff-1111-2222-3333-444444444444
jl() { printf '{"type":"user","timestamp":"%s","message":{"content":"%s"}}\n{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n' "$T5" "$2" > "$1"; }
jl "$DA/$S1.jsonl" "work in $RA itself"
jl "$DB/$M.jsonl" "patch the reaper in $RA/files/scripts"
jl "$DB/$N.jsonl" "unrelated work here"
LS="$DC/files/scripts/list_sessions.py"
ids=$(python3 "$LS" --repo "$RB" --mentioning "$RA" 2>&1 | grep -o '^● [0-9a-f-]*' | sed 's/^● //')
[ "$(echo $ids)" = "$M" ] && ok "--mentioning: the session in another repo that names this repo's path, and only it" || bad "mentioning: $(echo $ids)"
mkdir -p "$XDG_CONFIG_HOME/agent-cadence"
printf '%s\n%s\n%s/\n%s\n' "$RA" "$RB" "$RB" "$TMP/gone" > "$XDG_CONFIG_HOME/agent-cadence/repos.txt"
ids=$(python3 "$LS" --roster --mentioning "$RA" --days 30 2>/dev/null | grep -o '^● [0-9a-f-]*' | sed 's/^● //')
[ "$(echo $ids | tr ' ' '\n' | sort | tr '\n' ' ')" = "$(printf '%s\n' "$S1" "$M" | sort | tr '\n' ' ')" ] \
    && ok "--roster --mentioning: candidates from every roster repo (a duplicate spelling and a gone path tolerated)" \
    || bad "roster mentioning: $(echo $ids)"
# the forms a session actually writes: ~/-relative (a repo under HOME), from a WORKTREE of
# the repo (maps to the main checkout), never a longer name that merely starts with the path
RH="$HOME/rh"; git init -q -b main "$RH"; git -C "$RH" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
git -C "$RH" worktree add -q "$RH/.claude/worktrees/wt" -b wt 2>/dev/null
Q=12121212-1111-2222-3333-444444444444; X=34343434-1111-2222-3333-444444444444
jl "$DB/$Q.jsonl" "edited ~/rh/scripts/x.sh from here"
jl "$DB/$X.jsonl" "worked in $HOME/rh2 and ~/rh.old only"
ids=$(python3 "$LS" --repo "$RB" --mentioning "$RH/.claude/worktrees/wt" 2>&1 | grep -o '^● [0-9a-f-]*' | sed 's/^● //')
[ "$(echo $ids)" = "$Q" ] && ok "--mentioning from a worktree matches the main checkout's ~/-relative path; ~/rh2 and ~/rh.old do not match ~/rh" \
    || bad "tilde/worktree/prefix: $(echo $ids)"
rm "$DB/$Q.jsonl" "$DB/$X.jsonl"
# --days by mtime before any read: an old file that would match is never listed
jl "$DB/$Q.jsonl" "old work in $RA"; touch -d '40 days ago' "$DB/$Q.jsonl"
ids=$(python3 "$LS" --repo "$RB" --mentioning "$RA" --days 30 2>&1 | grep -o '^● [0-9a-f-]*' | sed 's/^● //')
[ "$(echo $ids)" = "$M" ] && ok "--days drops an old matching transcript" || bad "days+mentioning: $(echo $ids)"
rm "$XDG_CONFIG_HOME/agent-cadence/repos.txt"
out=$(python3 "$LS" --roster 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "roster is empty or missing" <<< "$out" && ok "--roster with no roster and no --repo: says so, exit 1" || bad "no roster rc=$rc: $out"

# --- 6) TD-28's stronger signals: a commit of the repo made while the session ran, and a
#        worktree of the repo outside its dir. Each candidate says on `via:` what made it one.
gc() { git -C "$RH" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"; git -C "$RH" rev-parse --short=7 HEAD; }
NEW=$(gc fresh)
OLD=$(GIT_COMMITTER_DATE="$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%S)" gc old)
C1=56565656-1111-2222-3333-444444444444; C2=78787878-1111-2222-3333-444444444444; C3=9a9a9a9a-1111-2222-3333-444444444444
jl "$DB/$C1.jsonl" "[main $NEW] fresh"
jl "$DB/$C2.jsonl" "[main $OLD] old — made before this session began"
FULL=$(git -C "$RH" rev-parse "$NEW"); [ "${FULL: -1}" = 0 ] && BADLAST=1 || BADLAST=0
jl "$DB/$C3.jsonl" "hashes holding one: aaaaaaaa$FULL ${FULL}aaaaaaaa 0${NEW}0ff ${FULL:0:39}$BADLAST"
out=$(python3 "$LS" --repo "$RB" --mentioning "$RH" 2>&1)
ids=$(grep -o '^● [0-9a-f-]*' <<< "$out" | sed 's/^● //')
[ "$(echo $ids)" = "$C1" ] && ok "commit signal: a transcript naming a commit made here in its window, not one from before it nor a hex run containing one" \
    || bad "commit signal: $(echo $ids)"
grep -q "via:     names commit $NEW, made there while this session ran" <<< "$out" && ok "commit signal: via names the commit" || bad "commit via: $out"
rm "$DB/$C1.jsonl" "$DB/$C2.jsonl" "$DB/$C3.jsonl"
# a worktree outside the repo's dir: named in another session's transcript, and a session started in it
WO="$TMP/rh-out"; git -C "$RH" worktree add -q "$WO" -b out 2>/dev/null
DW="$P/$(py "print(L.munge(Path(sys.argv[1])))" "$WO")"; mkdir -p "$DW"
W1=bcbcbcbc-1111-2222-3333-444444444444; W2=dededede-1111-2222-3333-444444444444
jl "$DB/$W1.jsonl" "edited $WO/scripts/x.sh"
jl "$DW/$W2.jsonl" "work in the worktree"
out=$(python3 "$LS" --repo "$RB" --mentioning "$RH" 2>&1)
ids=$(grep -o '^● [0-9a-f-]*' <<< "$out" | sed 's/^● //')
[ "$(echo $ids | tr ' ' '\n' | sort | tr '\n' ' ')" = "$(printf '%s\n' "$W1" "$W2" | sort | tr '\n' ' ')" ] \
    && ok "worktree signal: a transcript naming an outside worktree, and a session started in one" || bad "worktree signal: $(echo $ids)"
grep -q "via:     ran in a worktree of it" <<< "$out" && grep -q "via:     names its path" <<< "$out" \
    && ok "worktree signal: via says which" || bad "worktree via: $out"
RE="$TMP/re"; mkdir -p "$RE"   # a repo with no transcripts of its own: the outside worktree's session still lists
ids=$(python3 "$LS" --repo "$RE" --mentioning "$RH" 2>/dev/null | grep -o '^● [0-9a-f-]*' | sed 's/^● //')
[ "$(echo $ids)" = "$W2" ] && ok "worktree signal: listed even when every --repo has no transcripts" || bad "elsewhere-only: $(echo $ids)"
python3 "$LS" --repo "$RB" 2>&1 | grep -q "via:" && bad "via: printed without --mentioning" || ok "no via line without --mentioning"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
