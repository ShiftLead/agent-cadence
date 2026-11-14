#!/usr/bin/env bash
# TD-039: board item kinds (decide | act | look | watch | fyi — look is TD-082; on ledgerboard v3.0, TD-263, an item
# file's `Kind:` header), the board-size warning, the overdue escalation, and the SessionStart line's per-kind
# counts and cap — through nudge_user_attention.py --report [--due-only] [--json] --board, over a v3 board
# directory. An item with no Kind: is unmarked.
#
# Offline: HOME/XDG_CONFIG_HOME/AGENT_CADENCE_REG_DIR are temp; dates derive from the run date.
set -u
export TZ=UTC  # TD-209: `date -d 'N days'` from now is N×24h, an hour short across DST; UTC has none, and the scripts under test inherit it
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$DC/files/scripts/nudge_user_attention.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
unset SHIFTLEAD_SESSION
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
d() { date -d "$1" +%F; }
T0=$(d today); RAISED=$(d '2 days ago')

# A v3 board at $B (the directory; its stub beside it). `board` empties it and writes README.md with today's
# deep sweep stamp; `it <kind|-> <words> [header line…]` adds one open item, Added $RAISED, its id numbered in
# the order written (so the board's id order is the order of the calls).
B="$TMP/r/docs/user_attention"; mkdir -p "$B"
STUB='# board\n\nLedgerboard: 3\n\nThis board is the directory [user_attention/](user_attention/), one file per item (ledgerboard v3.0).\n'
SEQ=0
board() { rm -rf "$B"; mkdir -p "$B"; printf "$STUB" > "$B.md"; printf '# board\n\nLedgerboard: 3\nSwept: %s (h, deep)\n' "$T0" > "$B/README.md"; SEQ=0; }
it() {  # $1 kind or -, $2 words, then header lines (e.g. "**Due:** …")
  local kind=$1 words=$2; shift 2; SEQ=$((SEQ+1))
  { printf '## %s\n\n' "$words"; [ "$kind" = - ] || printf '**Kind:** %s\n' "$kind"
    printf '**Added:** %s\n' "$RAISED"; for x in "$@"; do printf '%s\n' "$x"; done; } > "$B/$RAISED-$(printf '%08x' "$SEQ").md"
}
due() { printf '**Due:** %s' "$1"; }
rep() { python3 "$N" --report --board "$B.md" "$@" 2>&1; }  # the stub, as the hook passes it

# --- 1) kinds: the Kind: header; an item without one is unmarked; fyi ignores Due:, watch apart
board
it decide "pick a name" "$(due "$T0")"
it act "rotate the key" "$(due "$T0")"
it look "the page merged; look at it" "**Session:** abcdef12 on h" "$(due "$T0")" "**Answers:** Works | Not right: <what>"
it - "an unmarked item, act on it" "$(due "$T0")"
it - "another unmarked item, not due yet" "$(due "$(d '+5 days')")"
it watch "did the backfill drain" "$(due "$T0")"
it fyi "heads-up, the API moved" "$(due "$T0")"
it fyi "an fyi with no Due"
js=$(rep --json)
kinds=$(python3 -c 'import json,sys; print(" ".join(sorted(str(i["kind"]) for i in json.load(sys.stdin)["boards"][0]["items"])))' <<< "$js")
[ "$kinds" = "None None act decide fyi fyi look watch" ] && ok "kind: decide/act/look/watch/fyi from the Kind: header; none is unmarked" \
    || bad "kinds parsed: '$kinds'"
out=$(rep --due-only)
grep -q "^⚠ 4 attention item(s) due (decide 1, act 1, look 1, unmarked 1) and 1 watch item(s) to check" <<< "$out" \
    && ok "SessionStart line: to-dos counted per kind — a look among them (TD-082) — watch counted apart" || bad "due-only header: $out"
! grep -q "heads-up\|an fyi with no Due" <<< "$out" && ok "SessionStart line: an fyi never appears, even with a Due: of today" || bad "fyi surfaced: $out"
w=$(grep -n "did the backfill" <<< "$out" | cut -d: -f1); a=$(grep -n "rotate the key" <<< "$out" | cut -d: -f1)
[ -n "$w" ] && [ -n "$a" ] && [ "$w" -gt "$a" ] && grep -q "(watch · check today)" <<< "$out" \
    && ok "watch item listed after the to-dos, tagged as a check" || bad "watch placement/tag: $out"
full=$(rep)
grep -q "8 open item(s) (decide 1, act 1, look 1, watch 1, fyi 2, unmarked 2), 4 due/overdue, 1 watch item(s) to check" <<< "$full" \
    && ok "full report header: kinds counted; a look is due like a to-do; fyi and watch not in due/overdue" || bad "full header: $(head -1 <<< "$full")"
grep "heads-up" <<< "$full" | grep -qF "(fyi · ⚠ an fyi carries no Due: — \`board_edit.py done\` it and \`board_edit.py add\` it again without --due)" \
    && grep "an fyi with no Due" <<< "$full" | grep -qF "(fyi)" \
    && ok "an fyi with a Due: is flagged; one without is tagged fyi" || bad "fyi tags: $full"
f=$(grep -n "heads-up" <<< "$full" | cut -d: -f1); u=$(grep -n "not due yet" <<< "$full" | cut -d: -f1)
fl=$(grep -n "did the backfill" <<< "$full" | cut -d: -f1)
[ -n "$f" ] && [ -n "$u" ] && [ "$fl" -gt "$u" ] && [ "$f" -gt "$fl" ] \
    && ok "full report: to-dos, then watch, then fyi" || bad "full order: $full"

# --- 2) escalation: overdue 14d+ says ledger it (not 13d, not a decided item, not fyi)
board
it - "long overdue" "$(due "$(d '20 days ago')")"
it - "nearly" "$(due "$(d '13 days ago')")"
it decide "decided long ago" "$(due "$(d '30 days ago')")" "**Answers:** yes | no" "**Decided:** $(d '3 days ago') by Pat — yes"
it watch "a check long missed" "$(due "$(d '15 days ago')")"
full=$(rep)
grep "long overdue" <<< "$full" | grep -qF "(20d overdue · ⚠ overdue 20d — \`ledger.py new\` it, then \`board_edit.py done\` it here)" \
    && grep "nearly" <<< "$full" | grep -qF "(13d overdue)" \
    && ok "escalation: overdue 20d flagged, 13d not" || bad "escalation tags: $full"
grep "decided long ago" <<< "$full" | grep -q "ledger it\|ledger.py new" && bad "a decided item was escalated: $full" \
    || ok "escalation: a decided item (a session's work order) is not escalated"
grep "check long missed" <<< "$full" | grep -qF "(watch · check 15d overdue · ⚠ overdue 15d" \
    && ok "escalation: a watch item long past its check-by date is flagged too" || bad "watch escalation: $(grep 'check long' <<< "$full")"
out=$(rep --due-only)
grep -q "^⚠ 2 item(s) overdue past their repo's escalate-overdue-days across these boards — \`ledger.py new\` each as a TD, then \`board_edit.py done\` it on the board" <<< "$out" \
    && ok "SessionStart line counts the escalations" || bad "due-only escalation line: $out"
esc=$(rep --json | python3 -c 'import json,sys; print(sorted(str(i["escalate"]) for i in json.load(sys.stdin)["boards"][0]["items"]))')
[ "$esc" = "['None', 'None', 'overdue 15d', 'overdue 20d']" ] && ok "--json carries escalate" || bad "json escalate: $esc"

# --- 3) board size: over 15 open items warns (report, SessionStart line, --json); 15 does not
board; for n in $(seq 1 15); do it fyi "note $n"; done
full=$(rep); out=$(rep --due-only)
! grep -q "open items on this board" <<< "$full" && [ -z "$out" ] \
    && ok "15 open items: no size warning; the SessionStart line stays silent" || bad "15 items: '$out' / $(grep open <<< "$full")"
it fyi "note 16"
full=$(rep); out=$(rep --due-only)
grep -q "⚠ 16 open items on this board (over 15) — triage them" <<< "$full" \
    && grep -q "^⚠ board(s) over their repo's board-size-warn — triage them (\`board_edit.py done\`; durable debt \`ledger.py new\` first): r 16$" <<< "$out" \
    && [ "$(rep --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["boards"][0]["size"].startswith("⚠ 16 open items on this board"))')" = True ] \
    && ok "16 open items: warned in the report, the SessionStart line and --json" || bad "16 items: '$out' / $(grep open <<< "$full")"

# --- 4) the SessionStart list is capped at 12, then says how many more
board; for n in $(seq 1 14); do it act "task $n" "$(due "$T0")"; done
out=$(rep --due-only)
[ "$(grep -c '^  • ' <<< "$out")" = 12 ] && grep -q "^  … and 2 more — run /attention$" <<< "$out" \
    && grep -q "^⚠ 14 attention item(s) due (act 14)" <<< "$out" \
    && ok "SessionStart list: 12 lines, then '… and 2 more'; the count is all 14" || bad "cap: $out"

# the escalation count covers items past the cap too, and says so rather than "of them"
board; for n in $(seq 1 13); do it act "late $n" "$(due "$(d '20 days ago')")"; done; it act "recent" "$(due "$(d '5 days ago')")"
out=$(rep --due-only)
grep -q "^⚠ 13 item(s) overdue past their repo's escalate-overdue-days across these boards" <<< "$out" && ! grep -q "of them" <<< "$out" \
    && ok "capped list: the escalation count is all 13, worded as a total" || bad "capped escalation: $out"

# --- TD-074: which items carry Answers: — the live look's fixed pair, and a default as one press
EDIT="$DC/files/scripts/board_edit.py"
board
it look "the new report merged; look at it" "**Session:** abcdef12 on h" "**Context:** TD-900" "$(due "$T0")" "**Answers:** Works | Not right: <what>"
it look "soaked 3 days, a second session checked it" "**Session:** abcdef12 on h" "**Context:** TD-901" "$(due "$T0")" "**Answers:** Works (default) | Not right: <what>"
it watch "did the backfill drain" "$(due "$T0")"
it act "run the rollout" "$(due "$T0")"
LOOK1="$RAISED-00000001"; LOOK2="$RAISED-00000002"
got=$(rep --json | python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1]); import ledgerboard as LB
it = {i["id"]: i for i in json.load(sys.stdin)["boards"][0]["items"]}
pair = list(LB.LIVE_LOOK_ANSWERS)
a, b, w, x = (it[sys.argv[2] + "-" + n] for n in ("00000001", "00000002", "00000003", "00000004"))
assert a["kind"] == "look" and a["answers"] == pair and a["default"] is None, a
assert b["answers"] == pair and b["default"] == "Works", b
assert w["answers"] == [] and x["answers"] == [] and w["default"] is None, (w, x)
print("ok")' "$DC/files/scripts" "$RAISED" 2>&1)
[ "$got" = ok ] && ok "a look's pair parses to LIVE_LOOK_ANSWERS with no default; a marked one carries it; a watch and an act carry none" || bad "live look json: $got"
out=$(rep --due-only)
grep "soaked 3 days" <<< "$out" | grep -qF "(due today · default: Works)" && grep "new report merged" <<< "$out" | grep -qF "(due today)" \
  && ok "the due line's tag shows a live look's default, and none where there is none" || bad "live look tag: $out"
# the words are written in three places and read by tools: cadence.md §3.5's table, the seed board, the change log
got=$(python3 - "$DC" <<'PY' 2>&1
import re, sys
from pathlib import Path
dc = Path(sys.argv[1]); sys.path.insert(0, str(dc / "files/scripts")); import ledgerboard as LB
want = list(LB.LIVE_LOOK_ANSWERS)
seed = "files/docs/user_attention/README.md" if (dc / "files/docs/user_attention/README.md").exists() else "files/docs/user_attention.md"
for rel, unescape in (("files/docs/cadence.md", True), (seed, False), ("files/docs/cadence-changes.md", False)):
    text = (dc / rel).read_text()
    lits = re.findall(r"`(?:\*\*)?Answers:(?:\*\*)? (Works[^`]*)`", text)
    assert lits, f"{rel}: no `Answers: Works …` literal"
    for lit in lits:
        if unescape:
            lit = lit.replace("\\|", "|")  # a markdown table cell escapes the bar
        got = LB.parse_answers_value(lit.rstrip("."))
        assert got == want, (rel, lit, got)
print("ok")
PY
)
[ "$got" = ok ] && ok "parity: §3.5's table, the seed board and cadence-changes.md write the live look's pair as LIVE_LOOK_ANSWERS" || bad "live look parity: $got"
# the default as one press: board_edit.py decide with the default's text writes Decided: as any answer,
# and the item becomes its session's work order — on a look as on a decide
G="$TMP/g"; git init -q -b main "$G"; mkdir -p "$G/docs"; cp -R "$B" "$G/docs/user_attention"; cp "$B.md" "$G/docs/user_attention.md"
GB="$G/docs/user_attention"
gg() { git -C "$G" -c user.email=t@t -c user.name=t "$@"; }
gg add -A; gg commit -qm board
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" decide --board "$GB" --id "$LOOK2" --answer "Works" --by Alex --tool shiftlead >/dev/null 2>&1; rc=$?
l=$(grep -m1 '^\*\*Decided:\*\*' "$GB/$LOOK2.md")
[ $rc -eq 0 ] && [ "$l" = "**Decided:** $T0 by Alex — Works" ] && grep -qx '\*\*Answers:\*\* Works (default) | Not right: <what>' "$GB/$LOOK2.md" \
  && ok "one press on the default: decide --answer <the default's text> writes Decided: on a look" || bad "decide default: rc=$rc $l"
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  "$EDIT" decide --board "$GB" --id "$LOOK1" --answer "Not right: the totals are off" --by Alex >/dev/null 2>&1
w=$(python3 "$N" --report --board "$GB.md" --json | python3 -c '
import json,sys; it={i["id"]: i for i in json.load(sys.stdin)["boards"][0]["items"]}
a, b = it[sys.argv[1]], it[sys.argv[2]]
print(a["decided"]["text"], "|", a["waiting_on"], "|", b["waiting_on"])' "$LOOK1" "$LOOK2")
[ "$w" = "Not right: the totals are off | session | session" ] && ok "a decided live look — Works or Not right: <text> — waits on a session" || bad "decided live look: $w"

# --- TD-134: the thresholds are the board's repo's keys (docs/cadence.toml, the machine's file, env)
C="$TMP/r/docs/cadence.toml"
board; for n in $(seq 1 4); do it fyi "note $n"; done; it act "late" "$(due "$(d '20 days ago')")"
printf 'board-size-warn = 4\nescalate-overdue-days = "30"\n' > "$C"
full=$(rep)
grep -q "⚠ 5 open items on this board (over 4)" <<< "$full" && ! grep -q "\`ledger.py new\` it, then \`board_edit.py done\` it here" <<< "$full" \
    && ok "TD-134 the repo's board-size-warn (an integer) and escalate-overdue-days (a string) are read" || bad "repo keys: $full"
j=$(rep --json | python3 -c '
import json,sys; b=json.load(sys.stdin)["boards"][0]; late=[i for i in b["items"] if i["text"] == "late"][0]
print(b["limits"]["board-size-warn"], b["limits"]["escalate-overdue-days"], b["size"][:22], late["escalate"])')
[ "$j" = "4 30 ⚠ 5 open items on this None" ] && ok "TD-134 --json: the board's limits, and its size and escalation read with them" || bad "json limits: $j"
rm "$C"; printf 'board-size-warn = "4"\n' > "$AGENT_CADENCE_REG_DIR/cadence.toml"
full=$(rep); grep -q "(over 4)" <<< "$full" && grep -q "\`ledger.py new\` it, then \`board_edit.py done\` it here" <<< "$full" \
    && ok "TD-134 the machine's value, and the default (14) for the key it leaves out" || bad "machine key: $full"
rm "$AGENT_CADENCE_REG_DIR/cadence.toml"
full=$(CADENCE_ESCALATE_OVERDUE_DAYS=25 rep); ! grep -q "\`ledger.py new\` it, then \`board_edit.py done\` it here" <<< "$full" && ok "TD-134 env CADENCE_ESCALATE_OVERDUE_DAYS wins" || bad "env key: $full"
printf 'board-size-warn = 0\n' > "$C"; full=$(rep)
grep -q "⚠ a threshold setting cannot be read: .*board-size-warn must be a whole number of 1 or more, not 0 — using 15" <<< "$full" \
    && ! grep -q "open items on this board" <<< "$full" && ok "TD-134 an invalid value is said, and its default used" || bad "invalid key: $full"
board; it fyi "x"
printf '# board\n\nLedgerboard: 3\nSwept: %s (h, quick)\nSwept-deep: %s (h, deep)\n' "$(d '3 days ago')" "$(d '20 days ago')" > "$B/README.md"
printf 'sweep-every = 2\ndeep-sweep-every = 15\n' > "$C"; full=$(rep)
grep -q "last sweep 3d ago" <<< "$full" && ok "TD-134 sweep-every (the stamp read from README.md)" || bad "sweep-every: $full"
printf 'deep-sweep-every = 15\n' > "$C"; full=$(rep)
grep -q "last deep sweep 20d ago" <<< "$full" && ok "TD-134 deep-sweep-every" || bad "deep-sweep-every: $full"
rm "$C"; full=$(rep); ! grep -q "last.*sweep" <<< "$full" && ok "TD-134 the sweep defaults (10, 30)" || bad "sweep defaults: $full"
# the SessionStart line judges each roster board by its own repo's values
for x in A B; do
  XB="$TMP/$x/docs/user_attention"; mkdir -p "$XB"; git init -q "$TMP/$x"; printf "$STUB" > "$XB.md"
  printf '# board\n\nLedgerboard: 3\nSwept: %s (h, deep)\n' "$T0" > "$XB/README.md"
  for n in $(seq 1 4); do printf '## %s task %s\n\n**Kind:** act\n**Added:** %s\n**Due:** %s\n' "$x" "$n" "$RAISED" "$(d '20 days ago')" > "$XB/$RAISED-0000000$n.md"; done
done
printf 'board-size-warn = 3\nescalate-overdue-days = 30\n' > "$TMP/A/docs/cadence.toml"
printf '%s\n%s\n' "$TMP/A" "$TMP/B" > "$AGENT_CADENCE_REG_DIR/repos.txt"
out=$(cd "$TMP/B" && python3 "$N" --report --due-only 2>&1)
grep -q "^⚠ board(s) over their repo's board-size-warn — triage them (\`board_edit.py done\`; durable debt \`ledger.py new\` first): A 4$" <<< "$out" \
    && grep -q "^⚠ 4 item(s) overdue past their repo's escalate-overdue-days" <<< "$out" \
    && ok "TD-134 --due-only: each roster board by its own repo's values (A's size and escalation, B's defaults)" || bad "due-only per repo: $out"
rm "$AGENT_CADENCE_REG_DIR/repos.txt"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
