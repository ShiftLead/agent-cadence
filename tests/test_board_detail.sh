#!/usr/bin/env bash
# TD-084: a board item's detail block — the lines under it indented deeper than its `-`
# (context, bullets, the question, caveats, the recommendation). nudge_user_attention.py
# carries it as `detail` in --json and prints it in the full report, never on the
# SessionStart line; board_edit.py edits only the head line and leaves the block as it was.
#
# Offline: HOME/XDG_CONFIG_HOME/AGENT_CADENCE_REG_DIR are temp; dates derive from the run date.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$DC/files/scripts/nudge_user_attention.py"
EDIT="$DC/files/scripts/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
d() { date -d "$1" +%F; }
T0=$(d today); RAISED=$(d '2 days ago')

B="$TMP/r/docs/user_attention.md"; mkdir -p "$(dirname "$B")"
board() { printf '# board\n\nSwept: %s (h, deep)\n\n' "$T0" > "$B"; cat >> "$B"; }
rep() { python3 "$N" --report --board "$B" "$@" 2>&1; }
detail() { python3 -c 'import json,sys; print(json.dumps([i["detail"] for i in json.load(sys.stdin)["boards"][0]["items"]], ensure_ascii=False))'; }

# --- 1) the block: indented lines under the item, nesting kept, common indent removed;
# it ends at a blank line, a line no deeper than the item, or another item (open or closed)
board <<EOF
- [ ] decide $RAISED (n/a) — Back up the uploads bucket? Due: $T0. Answers: Nightly (default) | Weekly | No backup.
  - **Context:** The bucket holds every user upload. The database is backed up; this is not.
    - losing it means asking users to upload again
  - **Question:** Should we back it up, and how often?
  - **Recommended:** Nightly — cheap, and the loss is unrecoverable.
- [ ] act $RAISED (n/a) — rotate the key. Due: $T0.
  - **Context:** it expires Friday.
- [x] act $RAISED (n/a) — a closed one. Due: $T0. Closed: $T0 — done.
  - closed detail, never read
- [ ] act $RAISED (n/a) — no block. Due: $T0.

  - after a blank line: not a block
- [ ] act $RAISED (n/a) — last. Due: $T0.
not indented: not a block
EOF
got=$(rep --json | detail)
want='[["- **Context:** The bucket holds every user upload. The database is backed up; this is not.", "  - losing it means asking users to upload again", "- **Question:** Should we back it up, and how often?", "- **Recommended:** Nightly — cheap, and the loss is unrecoverable."], ["- **Context:** it expires Friday."], [], []]'
[ "$got" = "$want" ] && ok "--json detail: the block per item, nesting kept; a closed item's block, a blank line and an unindented line end it" \
    || bad "detail: $got"
a=$(rep --json | python3 -c 'import json,sys; i=json.load(sys.stdin)["boards"][0]["items"][0]; print(i["answers"], i["default"])')
[ "$a" = "['Nightly', 'Weekly', 'No backup'] Nightly" ] && ok "Answers: and (default) still read from the head line" || bad "answers: $a"

full=$(rep)
grep -qF '      - **Question:** Should we back it up, and how often?' <<< "$full" \
    && grep -qF '        - losing it means asking users to upload again' <<< "$full" \
    && ok "full report: the block printed under its item, indented, nesting kept" || bad "full report: $full"
! grep -q "closed detail\|after a blank line\|not indented" <<< "$full" && ok "full report: nothing outside a block printed" || bad "stray lines: $full"
due=$(rep --due-only)
grep -q "Back up the uploads bucket" <<< "$due" && ! grep -q "Question:\|Context:" <<< "$due" \
    && ok "SessionStart line: the head line only, never the block" || bad "due-only: $due"

# --- 2) a nested checkbox is an item of its own, not detail
board <<EOF
- [ ] act $RAISED (n/a) — parent. Due: $T0.
  - context line
  - [ ] act $RAISED (n/a) — nested checkbox. Due: $T0.
EOF
n=$(rep --json | python3 -c 'import json,sys; it=json.load(sys.stdin)["boards"][0]["items"]; print(len(it), it[0]["detail"])')
[ "$n" = "2 ['- context line']" ] && ok "a checkbox in the block ends it and is read as an item" || bad "nested checkbox: $n"

# --- 2b) the reports bound the block: each line clipped like the head, at most 20 lines
{ echo "- [ ] act $RAISED (n/a) — long. Due: $T0."
  for i in $(seq 1 25); do echo "  - line $i $(printf 'x%.0s' $(seq 1 250))"; done; } | board
full=$(rep)
n=$(grep -c "^      - line" <<< "$full"); w=$(grep "^      - line 1 " <<< "$full" | wc -c)
grep -qF "… 5 more line(s) — --json has them all" <<< "$full" && [ "$n" = 20 ] && [ "$w" -le 220 ] \
    && [ "$(rep --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["boards"][0]["items"][0]["detail"]))')" = 25 ] \
    && ok "full report: 20 detail lines, each clipped, then how many more; --json keeps all 25" || bad "cap: n=$n w=$w"

# --- 3) board_edit edits the head line only; the block stays byte-identical
mkdir -p "$TMP/nogit"; NB="$TMP/nogit/b.md"
cat > "$NB" <<EOF
# board

- [ ] decide $RAISED (n/a) — pick one? Due: $T0. Answers: A (default) | B.
  - **Context:** two lines
    - nested
- [ ] act $RAISED (n/a) — next. Due: $T0.
EOF
before=$(sed -n '4,5p' "$NB")
"$EDIT" decide --board "$NB" --line 3 --expect "decide $RAISED" --answer A --no-commit >/dev/null 2>&1; r1=$?
"$EDIT" done --board "$NB" --line 3 --expect "decide $RAISED" --why "did A" --no-commit >/dev/null 2>&1; r2=$?
[ $r1 = 0 ] && [ $r2 = 0 ] && [ "$(sed -n '4,5p' "$NB")" = "$before" ] && sed -n 3p "$NB" | grep -q "^- \[x\] .*Decided: A ($T0)\..*Closed: $T0 — did A\.$" \
    && ok "decide then done: the head line edited, the block untouched" || bad "board_edit: r1=$r1 r2=$r2 $(cat "$NB")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
