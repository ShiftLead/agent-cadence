#!/usr/bin/env bash
# P2 --report acceptance tests (plan 2026-08-10). XDG_CONFIG_HOME override keeps
# the real registry untouched.
set -u
export TZ=UTC  # TD-209: `date -d 'N days'` from now is N×24h, an hour short across DST; UTC has none, and the scripts under test inherit it
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/files/scripts/nudge_user_attention.py"
TMP=$(mktemp -d)

# No real `gh` from this suite (TD-052): --due-only --fetch asks gh for this repo's open PRs,
# and a run from inside a real clone would ask GitHub. A stub that always fails = offline.
mkdir -p "$TMP/nogh"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nogh/gh"; chmod +x "$TMP/nogh/gh"
export PATH="$TMP/nogh:$PATH"
export XDG_CONFIG_HOME="$TMP/config"
# A fresh CI runner has no global git identity (TD-047): the fixtures commit with this one.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
REG_DIR="$XDG_CONFIG_HOME/agent-cadence"; REG="$REG_DIR/repos.txt"
PASS=0; FAIL=0
# TD-24: every Due: a test asserts against is derived from the run date —
# hardcoded calendar dates rot (case 5 went red the day after it was written).
# Authored dates in item prefixes are genuinely fixed and stay literal.
TODAY=$(date +%F)
VLATE=$(date -d '11 days ago' +%F)
FUT=$(date -d '+18 days' +%F)
TMRW=$(date -d '+1 day' +%F)
FUT2=$(date -d '+20 days' +%F)
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Fixture repos: r1 overdue+today+future+undated items w/ Nudge claim; r2 open item, no claim; r3 no board.
mk() { git init -q -b main "$1"; mkdir -p "$1/docs"; git -C "$1" commit -q --allow-empty -m init; }
R1="$TMP/alpha"; mk "$R1"
cat > "$R1/docs/user_attention.md" <<EOF
# board

- [ ] 2026-08-01 (n/a) — very late thing. Due: $VLATE.
- [ ] 2026-08-10 (n/a) — today thing. Due: $TODAY.
- [ ] 2026-08-10 (n/a) — future thing. Due: $FUT.
- [ ] 2026-08-10 (n/a) — undated thing.
EOF
R2="$TMP/beta"; mk "$R2"
printf '# board\n\n- [ ] 2026-08-10 (n/a) — unclaimed thing. Due: %s.\n' "$TMRW" > "$R2/docs/user_attention.md"
R3="$TMP/gamma"; mk "$R3"

# --- 1) nudge mode --dry-run --force-weekly: weekly summary intact, the Monday
#        /stranded-work reminder retired (TD-7; the byte-identical-vs-main check
#        this replaced was only valid while nudge output was frozen)
out1=$(python3 "$NEW" --board "$R1/docs/user_attention.md" --dry-run --force-weekly 2>/dev/null); rc1=$?
if [ "$rc1" = 0 ] && echo "$out1" | grep -q "Weekly board review" \
   && echo "$out1" | grep -q "Snooze: edit" \
   && ! echo "$out1" | grep -q "Reminder: run /stranded-work"; then
  ok "nudge dry-run: weekly summary kept, Monday reminder retired"
else bad "nudge dry-run content (rc=$rc1): $(echo "$out1" | head -5)"; fi

# --- 2) nudge mode with two --board flags errors out
if python3 "$NEW" --board "$R1/docs/user_attention.md" --board "$R2/docs/user_attention.md" --dry-run >/dev/null 2>&1; then
  bad "two --board in nudge mode did not error"; else ok "two --board in nudge mode errors"; fi

# --- 3) --fetch without --report errors
if python3 "$NEW" --fetch >/dev/null 2>&1; then bad "--fetch alone did not error"; else ok "--fetch requires --report"; fi

# --- 4) --report with registry covers all entries; degrades per-row
mkdir -p "$REG_DIR"
printf '%s\n%s\n%s\n%s\n' "$R1" "$R2" "$R3" "$TMP/nonexistent" > "$REG"
out=$(python3 "$NEW" --report 2>/dev/null); rc=$?
echo "$out" > "$TMP/report.txt"
e() { echo "$out" | grep -qF "$1"; }
if [ "$rc" = 0 ] && e "== alpha" && e "== beta" && e "== gamma" && e "no board (docs/user_attention.md not found)" \
   && e "roster path missing" && ! e "Nudge:" && ! e "no Nudge: claim" ; then
  ok "--report covers all registry rows with per-row degradation (claims retired, TD-7)"
else bad "--report registry coverage (rc=$rc)"; echo "$out" | head -30; fi

# --- 5) header counts + overdue-first ordering + 4-way tags
if e "5 open item(s)" && e "2 due/overdue" \
   && echo "$out" | grep -q "d overdue) 2026-08-01" \
   && e "(due today) 2026-08-10 (n/a) — today thing" \
   && e "(due $FUT)" && e "(no due date)"; then
  first=$(echo "$out" | grep -n "very late thing" | cut -d: -f1)
  last=$(echo "$out" | grep -n "undated thing" | cut -d: -f1)
  if [ "$first" -lt "$last" ]; then ok "header counts, ordering, 4-way tags"; else bad "ordering wrong"; fi
else bad "header counts / tags missing"; echo "$out" | head -30; fi

# --- 6) --report never delivers even with channels configured
rm -f "$TMP/delivered"
NUDGE_COMMAND="touch $TMP/delivered" TELEGRAM_BOT_TOKEN=x TELEGRAM_CHAT_ID=y python3 "$NEW" --report >/dev/null 2>&1
if [ ! -e "$TMP/delivered" ]; then ok "--report never invokes delivery"; else bad "--report delivered!"; fi

# --- 7) no registry -> single-board fallback (script's own checkout board)
rm -f "$REG"
out=$(python3 "$NEW" --report 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "no machine roster" && echo "$out" | grep -q "== files"; then
  ok "no registry -> current-checkout fallback"; else bad "no-registry fallback (rc=$rc): $(echo "$out" | head -3)"; fi

# --- 8) explicit --board rows (repeatable) without registry
out=$(python3 "$NEW" --report --board "$R1/docs/user_attention.md" --board "$TMP/missing/docs/user_attention.md" 2>/dev/null)
if echo "$out" | grep -q "== alpha" && echo "$out" | grep -q "missing board file"; then
  ok "repeatable --board with missing-path note"; else bad "explicit boards: $(echo "$out" | head -5)"; fi

# --- 9) unreadable board degrades to a note without hiding other repos
chmod 000 "$R2/docs/user_attention.md"
printf '%s\n%s\n' "$R1" "$R2" > "$REG"
out=$(python3 "$NEW" --report 2>/dev/null); rc=$?
chmod 644 "$R2/docs/user_attention.md"
if [ "$rc" = 0 ] && echo "$out" | grep -q "unreadable board" && echo "$out" | grep -q "== alpha"; then
  ok "unreadable board degrades per-row"; else bad "unreadable board handling (rc=$rc)"; fi

# --- 10) --fetch: unreachable ssh origin -> 'fetch skipped' within budget, no hang
git -C "$R1" remote add origin git@192.0.2.1:fake/fake.git   # TEST-NET-1, never routes
printf '%s\n' "$R1" > "$REG"
start=$(date +%s)
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
took=$(( $(date +%s) - start ))
if echo "$out" | grep -q "fetch skipped" && [ "$took" -le 45 ]; then
  ok "--fetch degrades to skip note in ${took}s"; else bad "--fetch hang/degradation (took ${took}s): $(echo "$out" | grep -i fetch)"; fi

# --- 11) --fetch: real local origin, matching + differing board
BARE="$TMP/origin.git"; git init -q --bare -b main "$BARE"
R4="$TMP/delta"; mk "$R4"
printf '# board\n\n- [ ] 2026-08-10 (n/a) — synced thing. Due: %s.\n' "$FUT2" > "$R4/docs/user_attention.md"
git -C "$R4" add -A && git -C "$R4" commit -q -m board
git -C "$R4" remote add origin "$BARE" && git -C "$R4" push -q -u origin main 2>/dev/null
git -C "$R4" remote set-head origin main 2>/dev/null
printf '%s\n' "$R4" > "$REG"
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "board matches origin/main"; then ok "--fetch match detection"; else bad "--fetch match: $(echo "$out" | grep -i fetch)"; fi
echo "- [ ] 2026-08-10 (n/a) — local-only edit." >> "$R4/docs/user_attention.md"
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "DIFFERS from origin/main"; then ok "--fetch differ detection"; else bad "--fetch differ: $(echo "$out" | grep -i fetch)"; fi

# --- 12) TD-030: three-way board compare — a clone that is merely BEHIND reads origin's board
git -C "$R4" checkout -q -- docs/user_attention.md            # drop the local-only edit from 11
R7="$TMP/delta-elsewhere"; git clone -q "$BARE" "$R7" 2>/dev/null
printf -- '- [ ] 2026-08-26 (n/a) — bot-appended customer. Due: %s.\n' "$TODAY" >> "$R7/docs/user_attention.md"
git -C "$R7" commit -q -am "bot append" && git -C "$R7" push -q origin main 2>/dev/null
# 12a) full report: reads origin's board, labels the row, item text visible
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "== delta .* — showing origin/main" && echo "$out" | grep -q "bot-appended customer" \
   && echo "$out" | grep -q "local clone is behind — showing origin/main"; then
  ok "--fetch: behind clone reads origin's board and says so"
else bad "--fetch behind-clone: $(echo "$out" | grep -i 'delta\|fetch\|bot')"; fi
# 12b) --due-only --fetch surfaces the origin-only due item with a source tag
out=$(python3 "$NEW" --report --due-only --fetch 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "delta \[origin/main — local clone behind, pull\]: (due today) .*bot-appended customer"; then
  ok "--due-only --fetch surfaces origin-only due item"
else bad "--due-only --fetch (rc=$rc): $(echo "$out" | head -3)"; fi
# 12c) without --fetch the default stays offline: the origin-only item is invisible (documented contract)
out=$(python3 "$NEW" --report --due-only 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "--due-only without --fetch stays offline/local"; else bad "--due-only fetched without being asked: $out"; fi
# 12d) both sides changed -> read LOCAL, flag divergence, never show origin's line as local
echo "- [ ] 2026-08-10 (n/a) — local-only edit." >> "$R4/docs/user_attention.md"
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "DIFFERS from origin/main (both sides changed)" && echo "$out" | grep -q "local-only edit" \
   && ! echo "$out" | grep -q "bot-appended customer" && ! echo "$out" | grep -q "showing origin/main"; then
  ok "--fetch: two-sided divergence reads local and flags it"
else bad "--fetch diverged: $(echo "$out" | grep -i 'delta\|fetch\|edit')"; fi
# 12e) local edits not pushed (origin == base) -> read local, say push
git -C "$R4" checkout -q -- docs/user_attention.md && git -C "$R4" pull -q --ff-only origin main 2>/dev/null
echo "- [ ] 2026-08-10 (n/a) — local-only edit." >> "$R4/docs/user_attention.md"   # local == origin + an unpushed edit
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "DIFFERS from origin/main (local edits not pushed)" && echo "$out" | grep -q "local-only edit"; then
  ok "--fetch: local-only edits read local and say push"
else bad "--fetch local-ahead: $(echo "$out" | grep -i 'fetch')"; fi
git -C "$R4" checkout -q -- docs/user_attention.md
# 12h) board MISSING locally (clone predates its first commit), present on origin -> origin's copy fills the row
R8="$TMP/delta-fresh"; git clone -q "$BARE" "$R8" 2>/dev/null
git -C "$R8" reset -q --hard "$(git -C "$R8" rev-list --max-parents=0 HEAD)"   # back to the empty init commit
[ ! -e "$R8/docs/user_attention.md" ] || bad "fixture: board should be absent in $R8"
printf '%s\n' "$R8" > "$REG"
out=$(python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "== delta-fresh .* — showing origin/main" && echo "$out" | grep -q "bot-appended customer" \
   && ! echo "$out" | grep -q "no board (docs/user_attention.md not found)"; then
  ok "--fetch: locally-missing board is read from origin"
else bad "--fetch missing-local board: $(echo "$out" | grep -i 'delta\|fetch\|board')"; fi
out=$(python3 "$NEW" --report --due-only --fetch 2>/dev/null)
if echo "$out" | grep -q "delta-fresh \[origin/main — local clone behind, pull\]: (due today)"; then
  ok "--due-only --fetch: locally-missing board surfaces origin's due item"
else bad "--due-only --fetch missing-local: $(echo "$out" | head -3)"; fi
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "no board (docs/user_attention.md not found)"; then ok "without --fetch the missing board stays a note"; else bad "no-fetch missing board: $(echo "$out" | grep delta-fresh -A2)"; fi

# 12f) --due-only --fetch aggregate budget: unreachable origin + real origin, near-zero budget -> fast, exit 0,
#      and no row claims origin as its source (every fetch was skipped; R4 is clean at origin's commit after 12e)
printf '%s\n%s\n' "$R1" "$R4" > "$REG"
start=$(date +%s)
out=$(ATTENTION_DUE_FETCH_BUDGET=0.01 python3 "$NEW" --report --due-only --fetch 2>/dev/null); rc=$?
took=$(( $(date +%s) - start ))
if [ "$rc" = 0 ] && [ "$took" -le 5 ] && echo "$out" | grep -q "very late thing" && ! echo "$out" | grep -q "\[origin/main"; then
  ok "--due-only --fetch honors the aggregate budget (${took}s)"
else bad "--due-only --fetch budget (rc=$rc, ${took}s): $(echo "$out" | head -3)"; fi
# 12g) the full report never applies the due-only budget: the real origin still fetches with budget=0.01 in env
out=$(ATTENTION_DUE_FETCH_BUDGET=0.01 python3 "$NEW" --report --fetch 2>/dev/null)
if echo "$out" | grep -q "board matches origin/main"; then ok "full --fetch ignores the due-only budget"; else bad "full --fetch budgeted: $(echo "$out" | grep -i fetch)"; fi

# --- 13) invalid UTF-8 in one board degrades to that row only (no traceback)
R5="$TMP/epsilon"; mk "$R5"
printf '# board\n\n- [ ] 2026-08-10 (n/a) — ok item. Due: %s.\n\xff\xfe garbage\n' "$TODAY" > "$R5/docs/user_attention.md"
printf '%s\n%s\n' "$R5" "$R4" > "$REG"
out=$(python3 "$NEW" --report 2>&1); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "== epsilon" && echo "$out" | grep -q "== delta" \
   && echo "$out" | grep -q "ok item" && ! echo "$out" | grep -q "Traceback"; then
  ok "invalid UTF-8 board degrades per-row"; else bad "invalid UTF-8 crashed report (rc=$rc)"; fi

# --- 14-16) TD-12 sweep stamp: absent -> never-swept warn; fresh -> silent; stale -> aged warn
R6="$TMP/zeta"; mk "$R6"
printf '# board\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$FUT2" > "$R6/docs/user_attention.md"
printf '%s\n' "$R6" > "$REG"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "never swept"; then ok "absent Swept: warns never-swept"; else bad "no never-swept warn"; fi

printf '# board\n\nSwept: %s (testhost, deep)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if ! echo "$out" | grep -qi "swept\|sweep"; then ok "fresh Swept: stays silent"; else bad "fresh stamp warned: $(echo "$out" | grep -i swep)"; fi

printf '# board\n\nSwept: %s (testhost, quick)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d '30 days ago' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "last sweep 30d ago" && echo "$out" | grep -q "testhost, quick"; then
  ok "stale Swept: warns with age and mode"; else bad "stale stamp: $(echo "$out" | grep -i sweep)"; fi

# --- 17) future-dated Swept: warns instead of reading fresh forever
printf '# board\n\nSwept: %s (testhost, deep)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d '400 days' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "date is in the future"; then ok "future-dated Swept: warns"; else bad "future stamp read as fresh"; fi

# --- 18-20) the mode marker is load-bearing: a date alone is not a coverage claim
printf '# board\n\nSwept: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "claims no quick|deep mode"; then ok "fresh stamp without a mode warns"; else bad "modeless stamp read as healthy"; fi

printf '# board\n\nSwept: %s (testhost, banana)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "claims no quick|deep mode"; then ok "unrecognized mode warns"; else bad "garbage mode read as healthy"; fi

# staleness outranks a missing mode — re-running the sweep fixes both, so show the urgent one
printf '# board\n\nSwept: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d '30 days ago' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "last sweep 30d ago" && ! echo "$out" | grep -q "claims no quick|deep"; then
  ok "stale outranks missing-mode"; else bad "wrong precedence: $(echo "$out" | grep -i swept)"; fi

# --- 21) delimiter-adjacent host is not a mode claim; future+modeless shows the future line
printf '# board\n\nSwept: %s (deep-box)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "claims no quick|deep mode"; then ok "host deep-box is not a mode claim"; else bad "deep-box read as deep mode"; fi
printf '# board\n\nSwept: %s (somehost)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d '400 days' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "date is in the future" && ! echo "$out" | grep -q "claims no quick|deep"; then
  ok "future outranks modeless"; else bad "future+modeless precedence"; fi

# --- 22-27) TD-13 Swept-deep: deep coverage keeps its own recency slot
# fresh quick stamp + fresh Swept-deep -> silent
printf '# board\n\nSwept: %s (testhost, quick)\nSwept-deep: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if ! echo "$out" | grep -qi "sweep\|swept"; then ok "fresh quick + fresh deep stays silent"; else bad "fresh pair warned: $(echo "$out" | grep -i swe)"; fi

# fresh quick stamp, no deep record -> never-deep warning
printf '# board\n\nSwept: %s (testhost, quick)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "no deep sweep on record"; then ok "quick-only warns no-deep-on-record"; else bad "quick-only silent about deep"; fi

# fresh quick + stale (40d) Swept-deep -> aged deep warning
printf '# board\n\nSwept: %s (testhost, quick)\nSwept-deep: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$(date -d '40 days ago' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "last deep sweep 40d ago"; then ok "stale deep warns with age"; else bad "stale deep: $(echo "$out" | grep -i swe)"; fi

# fresh DEEP-mode Swept: without a Swept-deep header (pre-TD-13 writer) -> silent
printf '# board\n\nSwept: %s (testhost, deep)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if ! echo "$out" | grep -qi "sweep\|swept"; then ok "deep-mode Swept: counts as deep recency"; else bad "pre-TD-13 deep stamp warned: $(echo "$out" | grep -i swe)"; fi

# future-dated Swept-deep -> warns
printf '# board\n\nSwept: %s (testhost, quick)\nSwept-deep: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$(date -d '400 days' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "Swept-deep: date is in the future"; then ok "future Swept-deep warns"; else bad "future deep read as fresh"; fi

# --- TD-15) one day of timezone skew is not "the future": tomorrow-dated stamps stay silent
printf '# board\n\nSwept: %s (testhost, deep)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d 'tomorrow' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if ! echo "$out" | grep -q "date is in the future"; then ok "tomorrow-dated Swept: tolerated (tz skew)"; else bad "tomorrow stamp warned future"; fi

printf '# board\n\nSwept: %s (testhost, quick)\nSwept-deep: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$(date -d 'tomorrow' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if ! echo "$out" | grep -q "date is in the future"; then ok "tomorrow-dated Swept-deep: tolerated (tz skew)"; else bad "tomorrow deep warned future"; fi

# +2 days is beyond any real timezone spread -> still warns
printf '# board\n\nSwept: %s (testhost, deep)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d '2 days' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "date is in the future"; then ok "+2d Swept: still warns"; else bad "+2d stamp read as fresh"; fi

printf '# board\n\nSwept: %s (testhost, quick)\nSwept-deep: %s\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$(date -d '2 days' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "Swept-deep: date is in the future"; then ok "+2d Swept-deep: still warns"; else bad "+2d deep stamp read as fresh"; fi

# precedence: stale main stamp outranks the missing deep record
printf '# board\n\nSwept: %s (testhost, quick)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date -d '30 days ago' +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report 2>/dev/null)
if echo "$out" | grep -q "last sweep 30d ago" && ! echo "$out" | grep -q "no deep sweep on record"; then
  ok "stale main stamp outranks deep-missing"; else bad "deep precedence: $(echo "$out" | grep -i swe)"; fi

# --- 28-30) TD-7: --due-only SessionStart line
printf '%s\n%s\n' "$R1" "$R2" > "$REG"
out=$(python3 "$NEW" --report --due-only 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "attention item(s) due across this machine" \
   && echo "$out" | grep -q "alpha: (" && echo "$out" | grep -q "very late thing" \
   && ! echo "$out" | grep -q "future thing"; then
  ok "--due-only lists only due/overdue items"
else bad "--due-only content (rc=$rc): $(echo "$out" | head -5)"; fi

printf '%s\n' "$R6" > "$REG"
printf '# board\n\nSwept: %s (testhost, deep)\n\n- [ ] 2026-08-10 (n/a) — item. Due: %s.\n' "$(date +%F)" "$FUT2" > "$R6/docs/user_attention.md"
out=$(python3 "$NEW" --report --due-only 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then
  ok "--due-only is silent when nothing is due"
else bad "--due-only not silent (rc=$rc): $(echo "$out" | head -3)"; fi

if python3 "$NEW" --due-only >/dev/null 2>&1; then
  bad "--due-only alone did not error"; else ok "--due-only requires --report"; fi


# --- --report --json: one object, board line numbers, parsed due dates; --due-only filters
printf '%s\n%s\n%s\n' "$R1" "$R2" "$R3" > "$REG"
cat > "$R1/docs/user_attention.md" <<EOF
# board

- [ ] 2026-08-01 (n/a) — very late thing. Due: $VLATE.
- [x] 2026-08-02 (n/a) — done thing. Due: $VLATE.
- [ ] 2026-08-10 (n/a) — undated thing.
EOF
outj=$(python3 "$NEW" --report --json 2>/dev/null); rc=$?
chk=$(printf '%s' "$outj" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = {r["label"]: r for r in d["boards"]}
a = rows["alpha"]["items"]
assert [i["line"] for i in a] == [3, 5], a
assert a[0]["due"] == sys.argv[1] and a[0]["overdue_days"] == 11 and a[0]["due_tag"] == "11d overdue", a[0]
assert a[1]["due"] is None and a[1]["overdue_days"] is None, a[1]
assert rows["gamma"]["board"] is None and "no board" in rows["gamma"]["note"], rows["gamma"]
assert rows["alpha"]["sweep"], rows["alpha"]
print("ok")' "$VLATE" 2>&1)
if [ "$rc" = 0 ] && [ "$chk" = ok ]; then ok "--report --json: rows, line numbers, due dates"
else bad "--report --json (rc=$rc): $chk"; fi

outj=$(python3 "$NEW" --report --json --due-only 2>/dev/null)
n=$(printf '%s' "$outj" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["due_only"], sum(len(r["items"]) for r in d["boards"]))')
if [ "$n" = "True 1" ]; then ok "--report --json --due-only keeps only due items"
else bad "--json --due-only filter: $n"; fi

if python3 "$NEW" --json >/dev/null 2>&1; then bad "--json alone did not error"; else ok "--json requires --report"; fi
if python3 "$NEW" --report --json --remote >/dev/null 2>&1; then bad "--json --remote did not error"; else ok "--json refuses --remote"; fi

# --json --due-only with no roster and no default board: TD-7's silent exit still owes JSON an
# object (review finding on #82). Run a copy of the script from a bare tree so its own checkout's
# board is out of reach.
mkdir -p "$TMP/nowhere/files/scripts" && cp "$NEW" "$(dirname "$NEW")/ledgerboard.py" "$TMP/nowhere/files/scripts/"
rm -f "$REG"
outj=$(USER_ATTENTION_BOARD="$TMP/absent.md" python3 "$TMP/nowhere/files/scripts/nudge_user_attention.py" --report --json --due-only 2>/dev/null); rc=$?
n=$(printf '%s' "$outj" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["due_only"], len(d["boards"]))' 2>&1)
if [ "$rc" = 0 ] && [ "$n" = "True 0" ]; then ok "--json --due-only with no roster/board prints an empty object, not nothing"
else bad "--json roster-less (rc=$rc): $n"; fi

# staleness_line(None): a roster repo with no board must return None by DECISION, not by
# exception. Until 2026-09-18 the annotation said `Path`, `None.parent` raised, and the
# blanket `except Exception` turned it into the same return value — so the check was
# structurally unreachable for those repos and looked fine. Asserted by monkeypatching the
# blanket handler away: with the guard present this returns None; without it, it raises.
chk=$(python3 - "$NEW" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("nudge", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
assert mod.staleness_line(None) is None, "staleness_line(None) must be None"
# and it must not be None *because* something raised: the guard returns before the try block,
# so removing every handler leaves the same answer.
import inspect
src = inspect.getsource(mod.staleness_line)
assert "if board is None:" in src, "the None case must be handled explicitly, not by except"
assert src.index("if board is None:") < src.index("try:"), "the guard must precede the try block"
print("OK")
PYEOF
) 2>&1
if [ "$chk" = OK ]; then ok "staleness_line(None) returns None by guard, not by exception"
else bad "staleness_line(None): $chk"; fi

# An unexpected exception inside the check is logged at WARNING, not DEBUG — a cron shows
# warnings and swallows debug, which is how a five-month-unreachable check stays unnoticed.
# Asserted by EXECUTION: the first version of this test read the source text for
# "logger.warning" after the narrow except, and PR #92's reviewer built a variant that put
# that string in a trailing comment while the broad arm still called logger.debug — it passed.
# A test whose subject is "which level did it log at" has to make it log.
chk=$(python3 - "$NEW" <<'PYEOF'
import importlib.util, logging, subprocess, sys
spec = importlib.util.spec_from_file_location("nudge", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

class Capture(logging.Handler):
    def __init__(self): super().__init__(); self.records = []
    def emit(self, record): self.records.append(record)

def run_with(exc, board):
    cap = Capture()
    mod.logger.addHandler(cap); mod.logger.setLevel(logging.DEBUG)
    try:
        mod.subprocess = type("S", (), {
            "run": staticmethod(lambda *a, **k: (_ for _ in ()).throw(exc)),
            "SubprocessError": subprocess.SubprocessError,
            "TimeoutExpired": subprocess.TimeoutExpired,
        })
        out = mod.staleness_line(board)
    finally:
        mod.subprocess = subprocess
        mod.logger.removeHandler(cap)
    return out, [r.levelno for r in cap.records]

import pathlib, tempfile
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / "docs").mkdir()
board = tmp / "docs" / "user_attention.md"; board.write_text("x")
(tmp / "docs" / "cadence.toml").write_text(
    '[agent-cadence]\nsource = "https://github.com/ShiftLead/agent-cadence"\nref = "' + "a" * 40 + '"\n')

# A member of the best-effort family: expected, so DEBUG and nothing louder.
out, levels = run_with(subprocess.TimeoutExpired("git", 5), board)
assert out is None, out
assert logging.WARNING not in levels, f"a timeout must not warn: {levels}"
assert logging.DEBUG in levels, f"a timeout must still be recorded: {levels}"

# Anything else is a defect in this function and must be visible in a cron.
out, levels = run_with(RuntimeError("boom"), board)
assert out is None, out
assert logging.WARNING in levels, f"an unexpected error must warn: {levels}"
print("OK")
PYEOF
) 2>&1
if [ "$chk" = OK ]; then ok "an unexpected staleness failure warns; an expected one only debugs"
else bad "staleness except arms: $chk"; fi

# --json --fetch: fetched rows carry fetch_note/source and a stale slot (staleness is best-effort
# and network-only, so offline it is null — the key must still be there for consumers)
printf '%s\n' "$R4" > "$REG"
outj=$(python3 "$NEW" --report --json --fetch 2>/dev/null); rc=$?
chk=$(printf '%s' "$outj" | python3 -c '
import json, sys
d = json.load(sys.stdin)
r = d["boards"][0]
assert r["label"] == "delta" and r["source"] is None, r  # R4 sits at origin HEAD by now (12e)
assert "matches origin/main" in r["fetch_note"], r["fetch_note"]
assert "stale" in r and r["stale"] is None, r
assert any("bot-appended customer" in i["text"] for i in r["items"]), r["items"]
print("ok")' 2>&1)
if [ "$rc" = 0 ] && [ "$chk" = ok ]; then ok "--report --json --fetch: fetch_note, stale slot, origin-landed items"
else bad "--json --fetch (rc=$rc): $chk"; fi

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
