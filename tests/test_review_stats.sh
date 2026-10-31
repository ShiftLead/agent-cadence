#!/usr/bin/env bash
# TD-204 (ADR 2026-10-30-review-outcomes rule 4, tests rule 7): review_stats.py rebuilds the review
# outcomes from the roster's docs/reviews/ records and ledgers. Offline: two fixture repos on a
# temporary roster; HOME/XDG_CONFIG_HOME/AGENT_CADENCE_REG_DIR are temp dirs. Dates derive from today.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RS="$DC/files/scripts/review_stats.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
unset CADENCE_DESIGN_ROUNDS CADENCE_DESIGN_ROUNDS_WIDE
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
day() { python3 -c "import datetime,sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))" "$1"; }
TODAY=$(day 0); OLD=$(day 30); RECENT=$(day 2)
A="$TMP/repos/alpha"; B="$TMP/repos/beta"
mkdir -p "$A/docs/reviews" "$B/docs/reviews"
printf '%s\n%s\n' "$A" "$B" > "$AGENT_CADENCE_REG_DIR/repos.txt"

rec() {  # $1 path, $2 class, $3 decided, $4 source, then the tables on stdin
  { printf '# Review record: x\n\n**Design:** docs/plans/x.md\n**Class:** %s\n**Decided:** %s\n**Source:** %s\n\n' "$2" "$3" "$4"; cat; } > "$1"
}
rec "$A/docs/reviews/TD-001.md" in-repo "$OLD" rounds <<'EOF'
| review | round | role | model | tokens | date |
|---|---|---|---|---|---|
| R1 | 1 | fact-check | claude-sonnet-5-5 | 100 | x |
| R2 | 1 | design | claude-sonnet-5-5 | 200 | x |
| R3 | 1 | design | claude-fable-5-1 | 300 | x |
| R4 | 2 | design | claude-sonnet-5-5 | 50 | x |
| R5 | 2 | design | claude-fable-5-1 | 60 | x |
| R6 | 2 | fact-check | claude-sonnet-5-5 | 10 | x |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | t | a false claim | build-changing | applied |
| F2 | 1 | R2 | t | a gap | build-changing | applied |
| F3 | 1 | R3 | t | wording | minor | applied |
| F4 | 2 | R4 | t | wording | minor | applied |
EOF
rec "$A/docs/reviews/TD-002.md" wide pending rounds <<'EOF'
| review | round | role | model | tokens | date |
|---|---|---|---|---|---|
| R1 | 1 | design | sonnet? | ? | x |
| R2 | 1 | design | claude-fable-5-1 | 400 | x |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | t | a gap | build-changing | open |
EOF
rec "$A/docs/reviews/TD-003.md" in-repo "$RECENT" backfill <<'EOF'
| review | round | role | model | tokens | date |
|---|---|---|---|---|---|
| R1 | 1 | design | sonnet? | ? | x |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | ? | (not recorded) | unlabelled | ? |
| F2 | 1 | R1 | ? | (not recorded) | unlabelled | ? |
| F3 | 1 | R1 | ? | (not recorded) | unlabelled | ? |
EOF
rec "$B/docs/reviews/TD-005.md" wide "$OLD" rounds <<'EOF'
| review | round | role | model | tokens | date |
|---|---|---|---|---|---|
| R1 | 1 | design | claude-sonnet-5-5 | 1000 | x |
| R2 | 2 | design | claude-sonnet-5-5 | 500 | x |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | t | x | build-changing | applied |
| F2 | 1 | R1 | t | x | build-changing | applied |
| F3 | 1 | R1 | t | x | minor | applied |
EOF

ent() {  # $1 id, $2 added, then extra header lines and body on stdin
  printf '\n## %s: entry %s\n\n**Priority:** Low\n**Added:** %s\n' "$1" "$1" "$2"; cat; printf '\n'
}
{ printf '# ledger\n'
  ent TD-001 "$OLD" <<< $'**Status:** Open.\n\n**Why:** the design.'
  ent TD-002 "$OLD" <<< $'**Status:** Open.\n\n**Why:** the wide design.'
  ent TD-003 "$OLD" <<< $'**Status:** Open.\n\n**Why:** a backfilled design.'
  ent TD-010 "$TODAY" <<< $'**Escaped from:** TD-001 (missed the case)\n\n**Why:** broke.'
  ent TD-011 "$TODAY" <<< $'**Escaped from:** TD-009\n\n**Why:** broke.'
  ent TD-012 "$TODAY" <<< $'**Escaped from:** gamma#TD-1\n\n**Why:** broke.'
  ent TD-013 "$TODAY" <<< $'**Escaped from:** `BETA#td-5`\n\n**Why:** broke.'
  ent TD-014 "$TODAY" <<< $'**Status:** Open.\n\n**Why:** the build of TD-001 fails on a case.'
  ent TD-015 "$TODAY" <<< $'**Status:** Open.\n\n**Why:** TD-016 left a hole.'
  ent TD-016 "$TODAY" <<< $'**Part of:** TD-001\n\n**Why:** a build.'
  ent TD-017 "$OLD" <<< $'**Status:** Open.\n\n**Why:** an old one citing TD-001.'
  ent TD-018 "$TODAY" <<< $'**Escaped from:** nonsense!\n\n**Why:** broke.'
} > "$A/docs/technical_debt.md"
printf '# archive\n' > "$A/docs/technical_debt_archive.md"
printf '# ledger\n' > "$B/docs/technical_debt.md"
{ printf '# archive\n'; ent TD-020 "$TODAY" <<< $'**Escaped from:** alpha#TD-002\n**Resolved:** '"$TODAY"$'\n\n**Why:** broke.'; } > "$B/docs/technical_debt_archive.md"

snap() { find "$TMP/repos" -type f -exec sha256sum {} + | sort; }
before=$(snap)
OUT="$AGENT_CADENCE_REG_DIR/review-stats"
J="$OUT/design-rounds.json"
q() { python3 -c "import json,sys; D=json.load(open(sys.argv[1])); R={(r['repo'], r['td']): r for r in D}; print($1)" "$J"; }

# 1. a run over the roster writes beside it, and nothing into a repo
out=$(python3 "$RS" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$J" ] && [ -f "$OUT/design-rounds.md" ] && [ -f "$OUT/trial.md" ] && [ "$(snap)" = "$before" ] \
  && ok "1 output lands in review-stats/ beside the roster; no repo file changes" || bad "1 rc=$rc $out"
[ "$(q 'len(D)')" = 4 ] && ok "1b one row per record over both repos" || bad "1b $(q 'len(D)')"

# 2. a record's tables: design reviews, fact-checks apart, a clean review, build-changing per round
[ "$(q "R['alpha','TD-001']['reviews'], R['alpha','TD-001']['fact_checks'], R['alpha','TD-001']['rounds']")" = "4 2 2" ] \
  && ok "2 design reviews and fact-checks counted apart, rounds from the table" || bad "2 $(q "R['alpha','TD-001']")"
[ "$(q "R['alpha','TD-001']['build_changing_per_round']")" = "{'reviews': [1, 0], 'fact_checks': [1, 0]}" ] \
  && ok "2b build-changing per round, reviews' and fact-checks' apart" || bad "2b $(q "R['alpha','TD-001']['build_changing_per_round']")"
[ "$(q "[x['total_findings'] for x in R['alpha','TD-001']['reviews_detail']]")" = "[1, 1, 1, 0]" ] \
  && ok "2c a review with no findings rows is clean" || bad "2c"
[ "$(q "R['alpha','TD-001']['tokens_by_model']")" = "{'claude-sonnet-5-5': 360, 'claude-fable-5-1': 360}" ] \
  && [ "$(q "R['alpha','TD-002']['tokens_unknown']")" = 1 ] \
  && ok "2d tokens summed by model, an unknown one counted apart" || bad "2d $(q "R['alpha','TD-001']['tokens_by_model']")"

# 3. unlabelled rows: the proxy only
[ "$(q "R['alpha','TD-003']['reviews_detail'][0]['build_changing'], R['alpha','TD-003']['reviews_detail'][0]['total_findings'], R['alpha','TD-003']['build_changing_per_round']['reviews']")" = "None 3 [0]" ] \
  && ok "3 unlabelled rows count toward the total-findings proxy, never as build-changing" || bad "3"

# 4. Decided: a date, and pending
[ "$(q "R['alpha','TD-001']['decided'], R['alpha','TD-001']['aged'], R['alpha','TD-002']['decided'], R['alpha','TD-002']['aged'], R['alpha','TD-003']['aged']")" = "$OLD True pending False False" ] \
  && ok "4 Decided read as a date or pending; pending and young designs are not aged" || bad "4"

# 5. Escaped from: resolved (bare and a mixed-case <repo>#), unresolved, out of scope
md="$OUT/design-rounds.md"
grep -qF '| alpha#TD-010 | `TD-001` | resolved | alpha#TD-001 |' "$md" \
  && grep -qF '| alpha#TD-013 | `BETA#td-5` | resolved | beta#TD-005 |' "$md" \
  && ok "5 Escaped from: resolves for TD-NNN and a mixed-case <repo>#TD-NNN" || bad "5 $(grep '^| alpha#' "$md")"
grep -qF '| alpha#TD-011 | `TD-009` | unresolved |' "$md" && grep -qF '| alpha#TD-012 | `gamma#TD-1` | out of scope |' "$md" \
  && grep -qF '| alpha#TD-018 | `nonsense!` | unresolved |' "$md" \
  && ok "5b an unresolved, an unreadable and an out-of-scope value are each listed" || bad "5b"
[ "$(q "[d['where'] for d in R['alpha','TD-001']['post_build_defects']], [d['where'] for d in R['beta','TD-005']['post_build_defects']], [d['where'] for d in R['alpha','TD-002']['post_build_defects']]")" \
  = "['alpha#TD-010'] ['alpha#TD-013'] ['beta#TD-020']" ] \
  && ok "5c only resolved escapes attach to designs, archived defects included" || bad "5c"

# 6. escape rates: aged rounds designs only; pending/young and backfill listed apart
grep -qF '| in-repo | 1 | 1 | 1/1 (100%) | 0 | 1 |' "$md" && grep -qF '| wide | 1 | 1 | 1/1 (100%) | 1 | 0 |' "$md" \
  && ok "6 escape rate over aged rounds designs; a pending design and a backfill record are not rated" || bad "6 $(grep -A4 '^## Escapes' "$md")"

# 7. --candidates: a citing defect, the Part of: hop, a design with no record; --since compares Added:
c=$(python3 "$RS" --candidates --json)
cq() { python3 -c "import json,sys; c=json.loads(sys.argv[1]); print($1)" "$c"; }
[ "$(cq "sorted((x['id'], x['design'], x['where'], x['via']) for x in c['cites'] if x['id'] in ('TD-014', 'TD-015'))")" \
  = "[('TD-014', 'alpha#TD-001', 'Why', None), ('TD-015', 'alpha#TD-001', 'Why', 'TD-016 (Part of: TD-001)')]" ] \
  && ok "7 a defect citing a design, and one citing a build whose Part of: names it (the hop shown)" || bad "7 $(cq "c['cites']")"
[ "$(cq "[x['id'] for x in c['cites'] if x['id'] in ('TD-010', 'TD-013')]")" = "[]" ] \
  && ok "7b an entry already carrying Escaped from: is no candidate" || bad "7b"
[ "$(cq "[(x['id'], x['design']) for x in c['designs_without_record']]")" = "[('TD-011', 'alpha#TD-009')]" ] \
  && ok "7c an Escaped from: design with no record file is listed" || bad "7c $(cq "c['designs_without_record']")"
c=$(python3 "$RS" --candidates --since "$(day 5)" --json)
[ "$(cq "'TD-017' in [x['id'] for x in c['cites']], 'TD-014' in [x['id'] for x in c['cites']]")" = "False True" ] \
  && ok "7d --since keeps entries Added on or after the date" || bad "7d"

# 8. --repo limits the scope
python3 "$RS" --repo "$A" >/dev/null 2>&1
[ "$(q 'len(D)')" = 3 ] && grep -qF '| alpha#TD-013 | `BETA#td-5` | out of scope |' "$md" \
  && ok "8 --repo reads one repo; another repo's design is out of scope" || bad "8 $(q 'len(D)')"

# 9. stateless: an Escaped from: added after a run is counted by the next
python3 - "$A/docs/technical_debt.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("**Added:** %s\n**Status:** Open.\n\n**Why:** the build of TD-001" % s.split("## TD-014")[1].split("**Added:** ")[1][:10],
              "**Added:** %s\n**Escaped from:** TD-001\n\n**Why:** the build of TD-001" % s.split("## TD-014")[1].split("**Added:** ")[1][:10])
open(p, "w").write(s)
PY
grep -q '^\*\*Escaped from:\*\* TD-001$' "$A/docs/technical_debt.md" || bad "9 the fixture edit did not apply"
python3 "$RS" >/dev/null 2>&1
[ "$(q "[d['where'] for d in R['alpha','TD-001']['post_build_defects']]")" = "['alpha#TD-010', 'alpha#TD-014']" ] \
  && ok "9 an Escaped from: added since the last run is counted by the next" || bad "9 $(q "R['alpha','TD-001']['post_build_defects']")"

# 10. the port matches the frozen aggregate.py and trial_rules.py over the same json (run from a copy)
F="$TMP/frozen"; mkdir -p "$F"
cp "$DC/docs/review-data/aggregate.py" "$DC/docs/review-data/trial_rules.py" "$F/"
cp "$J" "$F/design-rounds.json"
(cd "$F" && python3 aggregate.py >/dev/null && python3 trial_rules.py >/dev/null) || bad "10 the frozen scripts did not run"
agg() { grep -E '^\| (in-repo|wide) \| [0-9]+ \| [^|]+ / [^|]+ / [^|]+ \| [^|]+ / [^|]+ / [^|]+ \|$|^- \*\*(Distribution of|In-repo rounds within|Wide rounds within)' "$1"; }
l3()  { grep '^- \*\*Median last review' "$1" | sed 's/.*): in-repo/in-repo/'; }
[ -n "$(agg "$md")" ] && [ "$(agg "$md")" = "$(agg "$F/design-rounds.md" | head -n "$(agg "$md" | wc -l)")" ] \
  && [ "$(l3 "$md")" = "$(l3 "$F/design-rounds.md")" ] \
  && ok "10 the aggregates match aggregate.py's" || bad "10 port:
$(agg "$md"; l3 "$md")
frozen:
$(agg "$F/design-rounds.md"; l3 "$F/design-rounds.md")"
cols() { awk -F'|' -v n="$2" 'NF == n + 2 && $2 !~ /^-/ && $2 !~ /class|cap/' "$1"; }
for n in 13 11 9; do
  p=$(cols "$OUT/trial.md" $n); f=$(cols "$F/trial-rev18.md" $n)
  [ "$n" = 9 ] && f=$(grep -E '^\| [0-9] \| (primary|strict) \|' "$F/trial-rev18.md") && p=$(grep -E '^\| [0-9] \| (primary|strict) \|' "$OUT/trial.md")
  [ -n "$p" ] && [ "$p" = "$f" ] && ok "10b the trial's $n-column table matches trial_rules.py's" || bad "10b $n columns: port:
$p
frozen:
$f"
done

# 11. usage: no roster, a --repo that is no directory
AGENT_CADENCE_REG_DIR="$TMP/none" python3 "$RS" >/dev/null 2>&1; rc1=$?
python3 "$RS" --repo "$TMP/nope" >/dev/null 2>&1; rc2=$?
[ "$rc1" = 2 ] && [ "$rc2" = 2 ] && ok "11 no roster or a missing --repo exits 2" || bad "11 rc=$rc1/$rc2"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
