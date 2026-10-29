#!/usr/bin/env bash
# TD-039: board item kinds (decide | act | look | watch | fyi — look is TD-082, one optional word before the date),
# the board-size warning, the overdue escalation, and the SessionStart line's per-kind
# counts and cap — through nudge_user_attention.py --report [--due-only] [--json] --board.
# Existing boards (no kind word) parse unchanged: the other report suites are that check.
#
# Offline: HOME/XDG_CONFIG_HOME/DEV_CADENCE_REG_DIR are temp; dates derive from the run date.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$DC/files/scripts/nudge_user_attention.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg"
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
d() { date -d "$1" +%F; }
T0=$(d today); RAISED=$(d '2 days ago')

B="$TMP/r/docs/user_attention.md"; mkdir -p "$(dirname "$B")"
board() { printf '# board\n\nSwept: %s (h, deep)\n\n' "$T0" > "$B"; cat >> "$B"; }
rep() { python3 "$N" --report --board "$B" "$@" 2>&1; }

# --- 1) kinds: parsed only as a word before the date; fyi ignores Due:, watch apart
board <<EOF
- [ ] decide $RAISED (n/a) — pick a name. Due: $T0.
- [ ] act $RAISED (n/a) — rotate the key. Due: $T0.
- [ ] look $RAISED (session abcdef12 on h) — the page merged; look at it. Due: $T0. Answers: Works | Not right: <what>.
- [ ] $RAISED (n/a) — an unmarked item, act on it. Due: $T0.
- [ ] actually $RAISED (n/a) — not a kind word. Due: $(d '+5 days').
- [ ] watch $RAISED (n/a) — did the backfill drain. Due: $T0.
- [ ] fyi $RAISED (n/a) — heads-up, the API moved. Due: $T0.
- [ ] FYI $RAISED (n/a) — upper-case kind, no Due.
EOF
js=$(rep --json)
kinds=$(python3 -c 'import json,sys; print(" ".join(str(i["kind"]) for i in json.load(sys.stdin)["boards"][0]["items"]))' <<< "$js")
[ "$kinds" = "decide act look None None watch fyi fyi" ] && ok "kind: decide/act/look/watch/fyi before a date, case-folded; 'actually' and prose are not kinds" \
    || bad "kinds parsed: '$kinds'"
out=$(rep --due-only)
grep -q "^⚠ 4 attention item(s) due (decide 1, act 1, look 1, unmarked 1) and 1 watch item(s) to check" <<< "$out" \
    && ok "SessionStart line: to-dos counted per kind — a look among them (TD-082) — watch counted apart" || bad "due-only header: $out"
! grep -q "heads-up\|upper-case kind" <<< "$out" && ok "SessionStart line: an fyi never appears, even with a Due: of today" || bad "fyi surfaced: $out"
w=$(grep -n "did the backfill" <<< "$out" | cut -d: -f1); a=$(grep -n "rotate the key" <<< "$out" | cut -d: -f1)
[ -n "$w" ] && [ -n "$a" ] && [ "$w" -gt "$a" ] && grep -q "(watch · check today)" <<< "$out" \
    && ok "watch item listed after the to-dos, tagged as a check" || bad "watch placement/tag: $out"
full=$(rep)
grep -q "8 open item(s) (decide 1, act 1, look 1, watch 1, fyi 2, unmarked 2), 4 due/overdue, 1 watch item(s) to check" <<< "$full" \
    && ok "full report header: kinds counted; a look is due like a to-do; fyi and watch not in due/overdue" || bad "full header: $(head -1 <<< "$full")"
grep -qF "(fyi · ⚠ an fyi carries no Due: — drop it) fyi $RAISED (n/a) — heads-up" <<< "$full" \
    && grep -qF "(fyi) FYI $RAISED" <<< "$full" \
    && ok "an fyi with a Due: is flagged; one without is tagged fyi" || bad "fyi tags: $full"
f=$(grep -n "heads-up" <<< "$full" | cut -d: -f1); u=$(grep -n "not a kind word" <<< "$full" | cut -d: -f1)
fl=$(grep -n "did the backfill" <<< "$full" | cut -d: -f1)
[ -n "$f" ] && [ -n "$u" ] && [ "$fl" -gt "$u" ] && [ "$f" -gt "$fl" ] \
    && ok "full report: to-dos, then watch, then fyi" || bad "full order: $full"

# --- 2) escalation: overdue 14d+ says ledger it (not 13d, not a decided item, not fyi)
board <<EOF
- [ ] $RAISED (n/a) — long overdue. Due: $(d '20 days ago').
- [ ] $RAISED (n/a) — nearly. Due: $(d '13 days ago').
- [ ] $RAISED (n/a) — decided long ago. Due: $(d '30 days ago'). Decided: yes ($(d '3 days ago')).
- [ ] watch $RAISED (n/a) — a check long missed. Due: $(d '15 days ago').
EOF
full=$(rep)
grep -qF "(20d overdue · ⚠ overdue 20d — ledger it and close it here) $RAISED (n/a) — long overdue" <<< "$full" \
    && grep -qF "(13d overdue) $RAISED (n/a) — nearly" <<< "$full" \
    && ok "escalation: overdue 20d flagged, 13d not" || bad "escalation tags: $full"
grep "decided long ago" <<< "$full" | grep -q "ledger it" && bad "a decided item was escalated: $full" \
    || ok "escalation: a decided item (a session's work order) is not escalated"
grep "check long missed" <<< "$full" | grep -qF "(watch · check 15d overdue · ⚠ overdue 15d" \
    && ok "escalation: a watch item long past its check-by date is flagged too" || bad "watch escalation: $(grep 'check long' <<< "$full")"
out=$(rep --due-only)
grep -q "^⚠ 2 item(s) overdue past their repo's escalate-overdue-days across these boards — ledger each as a TD and close it on the board" <<< "$out" \
    && ok "SessionStart line counts the escalations" || bad "due-only escalation line: $out"
[ "$(rep --json | python3 -c 'import json,sys; print([i["escalate"] for i in json.load(sys.stdin)["boards"][0]["items"]])')" \
  = "['overdue 20d', None, None, 'overdue 15d']" ] && ok "--json carries escalate" || bad "json escalate: $(rep --json | head -40)"

# --- 3) board size: over 15 open items warns (report, SessionStart line, --json); 15 does not
{ for n in $(seq 1 15); do echo "- [ ] fyi $RAISED (n/a) — note $n."; done; } | board
full=$(rep); out=$(rep --due-only)
! grep -q "open items on this board" <<< "$full" && [ -z "$out" ] \
    && ok "15 open items: no size warning; the SessionStart line stays silent" || bad "15 items: '$out' / $(grep open <<< "$full")"
{ for n in $(seq 1 16); do echo "- [ ] fyi $RAISED (n/a) — note $n."; done; } | board
full=$(rep); out=$(rep --due-only)
grep -q "⚠ 16 open items on this board (over 15) — triage or ledger them" <<< "$full" \
    && grep -q "^⚠ board(s) over their repo's board-size-warn — triage or ledger them: r 16$" <<< "$out" \
    && [ "$(rep --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["boards"][0]["size"].startswith("⚠ 16 open items on this board"))')" = True ] \
    && ok "16 open items: warned in the report, the SessionStart line and --json" || bad "16 items: '$out' / $(grep open <<< "$full")"

# --- 4) the SessionStart list is capped at 12, then says how many more
{ for n in $(seq 1 14); do echo "- [ ] act $RAISED (n/a) — task $n. Due: $T0."; done; } | board
out=$(rep --due-only)
[ "$(grep -c '^  • ' <<< "$out")" = 12 ] && grep -q "^  … and 2 more — run /attention$" <<< "$out" \
    && grep -q "^⚠ 14 attention item(s) due (act 14)" <<< "$out" \
    && ok "SessionStart list: 12 lines, then '… and 2 more'; the count is all 14" || bad "cap: $out"

# the escalation count covers items past the cap too, and says so rather than "of them"
{ for n in $(seq 1 13); do echo "- [ ] act $RAISED (n/a) — late $n. Due: $(d '20 days ago')."; done
  echo "- [ ] act $RAISED (n/a) — recent. Due: $(d '5 days ago')."; } | board
out=$(rep --due-only)
grep -q "^⚠ 13 item(s) overdue past their repo's escalate-overdue-days across these boards" <<< "$out" && ! grep -q "of them" <<< "$out" \
    && ok "capped list: the escalation count is all 13, worded as a total" || bad "capped escalation: $out"

# --- TD-074: which items carry Answers: — the live look's fixed pair, and a default as one press
EDIT="$DC/files/scripts/board_edit.py"
board <<EOF
## Needs the user

- [ ] look $RAISED (session abcdef12 on h) — the new report merged; look at it. Context: TD-900. Due: $T0. Answers: Works | Not right: <what>.
- [ ] look $RAISED (session abcdef12 on h) — soaked 3 days, a second session checked it. Context: TD-901. Due: $T0. Answers: Works (default) | Not right: <what>.
- [ ] watch $RAISED (n/a) — did the backfill drain. Due: $T0.
- [ ] act $RAISED (n/a) — run the rollout. Due: $T0.
EOF
got=$(rep --json | python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
it = json.load(sys.stdin)["boards"][0]["items"]
pair = list(N.LIVE_LOOK_ANSWERS)
assert it[0]["kind"] == "look" and it[0]["answers"] == pair and it[0]["default"] is None, it[0]
assert it[1]["answers"] == pair and it[1]["default"] == "Works", it[1]
assert it[2]["answers"] == [] and it[3]["answers"] == [] and it[2]["default"] is None, (it[2], it[3])
print("ok")' "$DC/files/scripts" 2>&1)
[ "$got" = ok ] && ok "a look's pair parses to LIVE_LOOK_ANSWERS with no default; a marked one carries it; a watch and an act carry none" || bad "live look json: $got"
out=$(rep --due-only)
grep "soaked 3 days" <<< "$out" | grep -qF "(due today · default: Works)" && grep "new report merged" <<< "$out" | grep -qF "(due today)" \
  && ok "the due line's tag shows a live look's default, and none where there is none" || bad "live look tag: $out"
# the words are written in three places and read by tools: cadence.md §3.5's table, the seed board, the constant
got=$(python3 - "$DC" <<'PY' 2>&1
import re, sys
from pathlib import Path
dc = Path(sys.argv[1]); sys.path.insert(0, str(dc / "files/scripts")); import nudge_user_attention as N
want = list(N.LIVE_LOOK_ANSWERS)
for rel, unescape in (("files/docs/cadence.md", True), ("files/docs/user_attention.md", False), ("files/docs/cadence-changes.md", False)):
    text = (dc / rel).read_text()
    lits = [m for m in re.findall(r"`(Answers: Works[^`]*)`", text)]
    assert lits, f"{rel}: no `Answers: Works …` literal"
    for lit in lits:
        if unescape:
            lit = lit.replace("\\|", "|")  # a markdown table cell escapes the bar
        got = N.parse_answers("x. Due: 2099-01-01. " + lit)
        assert got == want, (rel, lit, got)
print("ok")
PY
)
[ "$got" = ok ] && ok "parity: §3.5's table, the seed board and cadence-changes.md write the live look's pair as LIVE_LOOK_ANSWERS" || bad "live look parity: $got"
# the default as one press: board_edit.py decide with the default's text writes Decided: as any answer,
# and the item becomes its session's work order — on a look as on a decide
G="$TMP/g"; git init -q -b main "$G"; mkdir -p "$G/docs"; cp "$B" "$G/docs/user_attention.md"
gg() { git -C "$G" -c user.email=t@t -c user.name=t "$@"; }
gg add -A; gg commit -qm board
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" decide --board "$G/docs/user_attention.md" --line 8 --expect "look $RAISED (session abcdef12" --answer "Works" --tool shiftlead >/dev/null 2>&1; rc=$?
l=$(sed -n 8p "$G/docs/user_attention.md")
[ $rc -eq 0 ] && [[ "$l" == *"Answers: Works (default) | Not right: <what>. Decided: Works ($T0)." ]] && ok "one press on the default: decide --answer <the default's text> writes Decided: on a look" || bad "decide default: rc=$rc $l"
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" decide --board "$G/docs/user_attention.md" --line 7 --expect "look $RAISED (session abcdef12" --answer "Not right: the totals are off" >/dev/null 2>&1
w=$(python3 "$N" --report --board "$G/docs/user_attention.md" --json | python3 -c 'import json,sys; it=json.load(sys.stdin)["boards"][0]["items"]; print(it[0]["decided"]["text"], "|", it[0]["waiting_on"], "|", it[1]["waiting_on"])')
[ "$w" = "Not right: the totals are off | session | session" ] && ok "a decided live look — Works or Not right: <text> — waits on a session" || bad "decided live look: $w"

# --- TD-134: the thresholds are the board's repo's keys (docs/cadence.toml, the machine's file, env)
C="$TMP/r/docs/cadence.toml"
{ for n in $(seq 1 4); do echo "- [ ] fyi $RAISED (n/a) — note $n."; done
  echo "- [ ] act $RAISED (n/a) — late. Due: $(d '20 days ago')."; } | board
printf 'board-size-warn = 4\nescalate-overdue-days = "30"\n' > "$C"
full=$(rep)
grep -q "⚠ 5 open items on this board (over 4)" <<< "$full" && ! grep -q "ledger it and close it here" <<< "$full" \
    && ok "TD-134 the repo's board-size-warn (an integer) and escalate-overdue-days (a string) are read" || bad "repo keys: $full"
j=$(rep --json | python3 -c 'import json,sys; b=json.load(sys.stdin)["boards"][0]; print(b["limits"]["board-size-warn"], b["limits"]["escalate-overdue-days"], b["size"][:22], b["items"][-1]["escalate"])')
[ "$j" = "4 30 ⚠ 5 open items on this None" ] && ok "TD-134 --json: the board's limits, and its size and escalation read with them" || bad "json limits: $j"
rm "$C"; printf 'board-size-warn = "4"\n' > "$DEV_CADENCE_REG_DIR/cadence.toml"
full=$(rep); grep -q "(over 4)" <<< "$full" && grep -q "ledger it and close it here" <<< "$full" \
    && ok "TD-134 the machine's value, and the default (14) for the key it leaves out" || bad "machine key: $full"
rm "$DEV_CADENCE_REG_DIR/cadence.toml"
full=$(CADENCE_ESCALATE_OVERDUE_DAYS=25 rep); ! grep -q "ledger it and close it here" <<< "$full" && ok "TD-134 env CADENCE_ESCALATE_OVERDUE_DAYS wins" || bad "env key: $full"
printf 'board-size-warn = 0\n' > "$C"; full=$(rep)
grep -q "⚠ a threshold setting cannot be read: .*board-size-warn must be a whole number of 1 or more, not 0 — using 15" <<< "$full" \
    && ! grep -q "open items on this board" <<< "$full" && ok "TD-134 an invalid value is said, and its default used" || bad "invalid key: $full"
printf '# board\n\nSwept: %s (h, quick)\nSwept-deep: %s (h, deep)\n\n- [ ] fyi %s (n/a) — x.\n' "$(d '3 days ago')" "$(d '20 days ago')" "$RAISED" > "$B"
printf 'sweep-every = 2\ndeep-sweep-every = 15\n' > "$C"; full=$(rep)
grep -q "last sweep 3d ago" <<< "$full" && ok "TD-134 sweep-every" || bad "sweep-every: $full"
printf 'deep-sweep-every = 15\n' > "$C"; full=$(rep)
grep -q "last deep sweep 20d ago" <<< "$full" && ok "TD-134 deep-sweep-every" || bad "deep-sweep-every: $full"
rm "$C"; full=$(rep); ! grep -q "last.*sweep" <<< "$full" && ok "TD-134 the sweep defaults (10, 30)" || bad "sweep defaults: $full"
# the SessionStart line judges each roster board by its own repo's values
for x in A B; do
  mkdir -p "$TMP/$x/docs"; git init -q "$TMP/$x"
  { printf '# board\n\nSwept: %s (h, deep)\n\n' "$T0"; for n in $(seq 1 4); do echo "- [ ] act $RAISED (n/a) — $x task $n. Due: $(d '20 days ago')."; done; } > "$TMP/$x/docs/user_attention.md"
done
printf 'board-size-warn = 3\nescalate-overdue-days = 30\n' > "$TMP/A/docs/cadence.toml"
printf '%s\n%s\n' "$TMP/A" "$TMP/B" > "$DEV_CADENCE_REG_DIR/repos.txt"
out=$(cd "$TMP/B" && python3 "$N" --report --due-only 2>&1)
grep -q "^⚠ board(s) over their repo's board-size-warn — triage or ledger them: A 4$" <<< "$out" \
    && grep -q "^⚠ 4 item(s) overdue past their repo's escalate-overdue-days" <<< "$out" \
    && ok "TD-134 --due-only: each roster board by its own repo's values (A's size and escalation, B's defaults)" || bad "due-only per repo: $out"
rm "$DEV_CADENCE_REG_DIR/repos.txt"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
