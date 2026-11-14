#!/usr/bin/env bash
# TD-084: a board item's detail block — on ledgerboard v3.0 (TD-263) the item file's body below its header,
# before its Log (context, bullets, the question, caveats, the recommendation). nudge_user_attention.py carries
# it as `detail` in --json and prints it in the full report, never on the SessionStart line; board_edit.py's
# edits change the header and the Log and leave the block as it was.
#
# Offline: HOME/XDG_CONFIG_HOME/AGENT_CADENCE_REG_DIR are temp; dates derive from the run date.
set -u
export TZ=UTC  # TD-209: `date -d 'N days'` from now is N×24h, an hour short across DST; UTC has none, and the scripts under test inherit it
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$DC/files/scripts/nudge_user_attention.py"
EDIT="$DC/files/scripts/board_edit.py"
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

B="$TMP/r/docs/user_attention"
STUB='# board\n\nLedgerboard: 3\n\nThis board is the directory [user_attention/](user_attention/), one file per item (ledgerboard v3.0).\n'
board() { rm -rf "$B"; mkdir -p "$B"; printf "$STUB" > "$B.md"; printf '# board\n\nLedgerboard: 3\nSwept: %s (h, deep)\n\nPeople: Alex\n' "$T0" > "$B/README.md"; }
rep() { python3 "$N" --report --board "$B.md" "$@" 2>&1; }  # the stub, as the hook passes it
ID1="$RAISED-00000001"; ID2="$RAISED-00000002"; ID3="$RAISED-00000003"
detail() { python3 -c '
import json,sys; it={i["id"]: i for i in json.load(sys.stdin)["boards"][0]["items"]}
print(json.dumps([it[k]["detail"] for k in sys.argv[1:]], ensure_ascii=False))' "$@"; }

# --- 1) the block: the body under the header, nesting kept; the Log is not detail
board
cat > "$B/$ID1.md" <<EOF
## Back up the uploads bucket?

**Kind:** decide
**Added:** $RAISED
**Due:** $T0
**Answers:** Nightly (default) | Weekly | No backup

- **Context:** The bucket holds every user upload. The database is backed up; this is not.
  - losing it means asking users to upload again
- **Question:** Should we back it up, and how often?
- **Recommended:** Nightly — cheap, and the loss is unrecoverable.

**Log:**
- $RAISED: Alex: thinking about it
EOF
printf '## rotate the key\n\n**Kind:** act\n**Added:** %s\n**Due:** %s\n\n- **Context:** it expires Friday.\n' "$RAISED" "$T0" > "$B/$ID2.md"
printf '## no block\n\n**Kind:** act\n**Added:** %s\n**Due:** %s\n' "$RAISED" "$T0" > "$B/$ID3.md"
got=$(rep --json | detail "$ID1" "$ID2" "$ID3")
want='[["- **Context:** The bucket holds every user upload. The database is backed up; this is not.", "  - losing it means asking users to upload again", "- **Question:** Should we back it up, and how often?", "- **Recommended:** Nightly — cheap, and the loss is unrecoverable."], ["- **Context:** it expires Friday."], []]'
[ "$got" = "$want" ] && ok "--json detail: the body per item, nesting kept, the Log not in it; none when there is none" \
    || bad "detail: $got"
a=$(rep --json | python3 -c 'import json,sys; i=[x for x in json.load(sys.stdin)["boards"][0]["items"] if x["id"] == sys.argv[1]][0]; print(i["answers"], i["default"], [r["text"] for r in i["replies"]])' "$ID1")
[ "$a" = "['Nightly', 'Weekly', 'No backup'] Nightly ['thinking about it']" ] && ok "Answers:, (default) and the Log's replies read beside the block" || bad "answers: $a"

full=$(rep)
grep -qF '      - **Question:** Should we back it up, and how often?' <<< "$full" \
    && grep -qF '        - losing it means asking users to upload again' <<< "$full" \
    && ok "full report: the block printed under its item, indented, nesting kept" || bad "full report: $full"
due=$(rep --due-only)
grep -q "Back up the uploads bucket" <<< "$due" && ! grep -q "Question:\|Context:" <<< "$due" \
    && ok "SessionStart line: the item's words only, never the block" || bad "due-only: $due"

# --- 2) the reports bound the block: each line clipped like the head, at most 20 lines
board
{ printf '## long\n\n**Kind:** act\n**Added:** %s\n**Due:** %s\n\n' "$RAISED" "$T0"
  for i in $(seq 1 25); do echo "- line $i $(printf 'x%.0s' $(seq 1 250))"; done; } > "$B/$ID1.md"
full=$(rep)
n=$(grep -c "^      - line" <<< "$full"); w=$(grep "^      - line 1 " <<< "$full" | wc -c)
grep -qF "… 5 more line(s) — --json has them all" <<< "$full" && [ "$n" = 20 ] && [ "$w" -le 220 ] \
    && [ "$(rep --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["boards"][0]["items"][0]["detail"]))')" = 25 ] \
    && ok "full report: 20 detail lines, each clipped, then how many more; --json keeps all 25" || bad "cap: n=$n w=$w"

# --- 3) board_edit's decide and done change the header; the block stays byte-identical, in the archived file too
mkdir -p "$TMP/nogit/b"; NB="$TMP/nogit/b"
printf '# board\n\nLedgerboard: 3\n\nPeople: Alex\n' > "$NB/README.md"
cat > "$NB/$ID1.md" <<EOF
## pick one?

**Kind:** decide
**Added:** $RAISED
**Due:** $T0
**Answers:** A (default) | B

- **Context:** two lines
  - nested
EOF
block() { sed -n '/^- \*\*Context/,$p' "$1"; }
before=$(block "$NB/$ID1.md")
"$EDIT" decide --board "$NB" --id "$ID1" --answer A --no-commit >/dev/null 2>&1; r1=$?
"$EDIT" done --board "$NB" --id "$ID1" --why "did A" --no-commit >/dev/null 2>&1; r2=$?
A="$NB/archive/$(date +%Y-%m)/$ID1.md"
[ $r1 = 0 ] && [ $r2 = 0 ] && [ "$(block "$A")" = "$before" ] && grep -qx "\*\*Decided:\*\* $T0 by Alex — A" "$A" \
    && grep -qx "\*\*Closed:\*\* $T0 — did A" "$A" && [ ! -e "$NB/$ID1.md" ] \
    && ok "decide then done: the header edited, the file archived, the block untouched" || bad "board_edit: r1=$r1 r2=$r2 $(cat "$A" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
