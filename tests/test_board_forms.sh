#!/usr/bin/env bash
# TD-259/TD-254, on ledgerboard v3.0 (TD-263): through board_edit.py — `add --doer` writes an act's Doer:, `decide`
# fills a form answer (`Hold: <note>`) and refuses an unfilled one, and a `reply` whose words begin with a form's
# head on an open decide or look item is that form's press (ShiftLead TD-1557 §4.4).
# Offline: a throwaway git repo per case; HOME/XDG_CONFIG_HOME are temp dirs. Dates derive from the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDIT="$DC/files/scripts/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset SHIFTLEAD_SESSION
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F); PAST=$(date -d "3 days ago" +%F); FUT=$(date -d "10 days" +%F)
D1="$PAST-000000d1"; L1="$PAST-000000a1"; A1="$PAST-000000c1"; K1="$PAST-000000b1"; W1="$PAST-000000e1"

# item <dir> <id> <kind> <title> <answers> [extra header lines…]: one open item file, Added $PAST, Due $FUT
item() {
  local d=$1 id=$2 kind=$3 title=$4 answers=$5; shift 5
  { printf '## %s\n\n**Kind:** %s\n**Added:** %s\n**Due:** %s\n**Answers:** %s\n' "$title" "$kind" "$PAST" "$FUT" "$answers"
    for x in "$@"; do printf '%s\n' "$x"; done; } > "$d/$id.md"
}
# A v3 board whose People: is Pat: a decide with a form, a look with the live pair, an act with a form among its
# answers (not a press), a decide already decided, a watch with the live pair.
mkrepo() {  # $1 = dir
  rm -rf "$1"; git init -q -b main "$1"; local d="$1/docs/user_attention"; mkdir -p "$d"
  printf '# board\n\nLedgerboard: 3\n\nPeople: Pat\n' > "$d/README.md"
  item "$d" "$D1" decide "end the rounds?" "Go | One more round | Hold: <note>"
  item "$d" "$L1" look "look at #5" "Works | Not right: <what>"
  item "$d" "$A1" act "rotate the key" "Done | Hold: <note>"
  item "$d" "$K1" decide "keep it?" "Yes | Hold: <note>" "**Decided:** $PAST by Pat — Yes"
  item "$d" "$W1" watch "watch #6" "Works | Not right: <what>"
  git -C "$1" add -A; git -C "$1" commit -qm base
}
R="$TMP/r"; B="$R/docs/user_attention"
field() { grep -m1 "^\*\*$2:\*\*" "$B/$1.md" 2>/dev/null; }  # <id> <field>: the item file's header line

# --- 1) add --doer: a repo and a team, on an act
mkrepo "$R"
id=$("$EDIT" add --board "$B" --kind act --text "Bump the pin." --context TD-9 --due "$FUT" --doer shiftlead --no-commit --json 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
[ "$(field "$id" Doer)" = "**Doer:** shiftlead" ] && [ "$(field "$id" Context)" = "**Context:** TD-9" ] \
  && ok "add --doer <repo>: an act's Doer:" || bad "add --doer <repo>: $(cat "$B/$id.md" 2>&1)"
id=$("$EDIT" add --board "$B" --kind act --text "Run the sweep." --context TD-9 --due "$FUT" --doer "team ac-grind" --no-commit --json 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
[ "$(field "$id" Doer)" = "**Doer:** team ac-grind" ] && ok "add --doer 'team <name>'" || bad "add --doer team: $(cat "$B/$id.md" 2>&1)"

# --- 2) add --doer refused: on decide, look and fyi; a bad value; with --decided — nothing written
mkrepo "$R"; before=$(ls "$B" | sha256sum)
for k in decide look fyi; do
  extra=(); [ $k = fyi ] || extra=(--due "$FUT"); [ $k = decide ] && extra+=(--answer a --answer b)
  "$EDIT" add --board "$B" --kind $k --text "a $k." "${extra[@]}" --doer shiftlead --no-commit >/dev/null 2>"$TMP/err" \
    && bad "add --doer on $k: accepted" || { grep -qi "act" "$TMP/err" && ok "add --doer on $k: refused, an act's alone" || bad "add --doer on $k: refused for another reason: $(cat "$TMP/err")"; }
done
"$EDIT" add --board "$B" --kind act --text "x." --due "$FUT" --doer "shiftlead." --no-commit >/dev/null 2>"$TMP/err"
[ $? -ne 0 ] && grep -qi "doer" "$TMP/err" && ok "add --doer: a repo ending in . refused, by the doer rule" \
  || bad "add --doer 'shiftlead.': $(cat "$TMP/err")"
"$EDIT" add --board "$B" --text "x." --context TD-9 --answer Go --answer No --decided Go --by Pat --doer shiftlead --no-commit >/dev/null 2>"$TMP/err"
[ $? -ne 0 ] && grep -qi "doer" "$TMP/err" && ok "add --doer with --decided: refused, by the doer rule" \
  || bad "add --doer --decided: $(cat "$TMP/err")"
[ "$(ls "$B" | sha256sum)" = "$before" ] && ok "refused --doer adds wrote nothing" || bad "a refused --doer add wrote the board"

# --- 3) decide fills a form; a form as written, its head alone, or a bare placeholder is refused
mkrepo "$R"
"$EDIT" decide --board "$B" --id "$D1" --answer "hold: until the bump lands" --no-commit >/dev/null 2>&1 \
  && [ "$(field "$D1" Decided)" = "**Decided:** $TODAY by Pat — Hold: until the bump lands" ] && ok "decide: a form filled, head as offered" \
  || bad "decide fill: $(field "$D1" Decided)"
for said in "Hold: <note>" "Hold:" "HOLD:   <words>"; do
  mkrepo "$R"
  out=$("$EDIT" decide --board "$B" --id "$D1" --answer "$said" --no-commit 2>&1); rc=$?
  [ $rc = 1 ] && grep -q "Hold needs its words" <<<"$out" && [ -z "$(field "$D1" Decided)" ] \
    && ok "decide '$said': refused, Hold needs its words" || bad "decide '$said': rc=$rc $out"
done
mkrepo "$R"
"$EDIT" decide --board "$B" --id "$D1" --answer "Go" --no-commit >/dev/null 2>&1 \
  && [ "$(field "$D1" Decided)" = "**Decided:** $TODAY by Pat — Go" ] && ok "decide: a complete answer as before" || bad "decide Go: $(field "$D1" Decided)"

# --- 4) reply: a form's head on an open decide or look (or a watch with the pair) decides; else a reply
mkrepo "$R"
"$EDIT" reply --board "$B" --id "$D1" --text "Hold: wait for the bump" --no-commit >/dev/null 2>&1 \
  && [ "$(field "$D1" Decided)" = "**Decided:** $TODAY by Pat — Hold: wait for the bump" ] \
  && ! grep -q "^- $TODAY: Pat:" "$B/$D1.md" && ok "reply 'Hold: …' on a decide: the form's press, no reply" \
  || bad "reply press on decide: $(cat "$B/$D1.md")"
mkrepo "$R"
"$EDIT" reply --board "$B" --id "$L1" --text "not right: the toast never shows" --no-commit >/dev/null 2>&1 \
  && [ "$(field "$L1" Decided)" = "**Decided:** $TODAY by Pat — Not right: the toast never shows" ] && ok "reply 'not right: …' on a look decides" \
  || bad "reply press on look: $(field "$L1" Decided)"
mkrepo "$R"
"$EDIT" reply --board "$B" --id "$W1" --text "Not right: flaky" --no-commit >/dev/null 2>&1 \
  && [ "$(field "$W1" Decided)" = "**Decided:** $TODAY by Pat — Not right: flaky" ] && ok "reply on a watch with the look's pair decides" \
  || bad "reply press on watch: $(field "$W1" Decided)"
mkrepo "$R"; before=$(cat "$B/$D1.md")
out=$("$EDIT" reply --board "$B" --id "$D1" --text "Hold: <note>" --no-commit 2>&1); rc=$?
[ $rc = 1 ] && grep -q "Hold needs its words" <<<"$out" && [ "$(cat "$B/$D1.md")" = "$before" ] \
  && ok "reply 'Hold: <note>': refused, never a reply" || bad "reply unfilled: rc=$rc $out"
mkrepo "$R"
"$EDIT" reply --board "$B" --id "$D1" --text "hold off until Monday" --no-commit >/dev/null 2>&1 \
  && grep -qx -- "- $TODAY: Pat: hold off until Monday" "$B/$D1.md" && [ -z "$(field "$D1" Decided)" ] \
  && ok "reply without a form's head and colon: a reply in the Log" || bad "plain reply: $(cat "$B/$D1.md")"
mkrepo "$R"
"$EDIT" reply --board "$B" --id "$A1" --text "Hold: later" --no-commit >/dev/null 2>&1 \
  && grep -qx -- "- $TODAY: Pat: Hold: later" "$B/$A1.md" && [ -z "$(field "$A1" Decided)" ] \
  && ok "reply 'Hold: …' on an act: a reply" || bad "reply on act: $(cat "$B/$A1.md")"
mkrepo "$R"
"$EDIT" reply --board "$B" --id "$K1" --text "Hold: actually wait" --no-commit >/dev/null 2>&1 \
  && grep -qx -- "- $TODAY: Pat: Hold: actually wait" "$B/$K1.md" && [ "$(field "$K1" Decided)" = "**Decided:** $PAST by Pat — Yes" ] \
  && ok "reply 'Hold: …' on a decided item: a reply" || bad "reply on decided: $(cat "$B/$K1.md")"

# --- 5) a raw label with a consequence; a committed press's subject; a press on a gated item keeps decide's lift refusal
mkrepo "$R"
sed -i "s/^\*\*Answers:\*\* Works | Not right: <what>$/**Answers:** Works — fine | Not right: <what> — say what/" "$B/$W1.md"; git -C "$R" commit -qam consequence
"$EDIT" reply --board "$B" --id "$W1" --text "not right: slow" --no-commit >/dev/null 2>&1 \
  && [ "$(field "$W1" Decided)" = "**Decided:** $TODAY by Pat — Not right: slow" ] && ok "reply press: answers with consequences" \
  || bad "reply press with consequences: $(cat "$B/$W1.md")"
mkrepo "$R"
out=$("$EDIT" reply --board "$B" --id "$D1" --text "Hold: wait" 2>&1); rc=$?
[ $rc = 0 ] && [ "$(git -C "$R" log -1 --format=%s)" = "board_edit: decide $D1 end the rounds?: Hold: wait (session n/a)" ] \
  && ok "a committed press commits as a decide" || bad "press commit (rc=$rc): $(git -C "$R" log -1 --format=%s) $out"
mkdir -p "$TMP/bin"; printf '#!/usr/bin/env bash\necho %s\n' "'[{\"id\":\"s-me\",\"by_person\":false,\"unattended\":true,\"seat\":null,\"controllers\":[\"mgr\"]}]'" > "$TMP/bin/ao"; chmod +x "$TMP/bin/ao"
rm -rf "$R"; git init -q -b main "$R"; mkdir -p "$B" "$R/docs/ledger"
printf '# board\n\nLedgerboard: 3\n\nPeople: Pat\n' > "$B/README.md"
item "$B" "$D1" decide "end the rounds?" "Go | Hold: <note>" "**Context:** TD-001 decision (Pat)" "**Lifts:** Go"
printf '## TD-001: a plan\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n**Blocked by:** decision (Pat)\n\n**Why:** x.\n\n**Ask:** go?\n\n**Fix:** y.\n' "$PAST" > "$R/docs/ledger/TD-001.md"
git -C "$R" add -A; git -C "$R" commit -qm gated; before=$(cat "$B/$D1.md" "$R/docs/ledger/TD-001.md" | sha256sum)
out=$(PATH="$TMP/bin:$PATH" SHIFTLEAD_SESSION=s-me "$EDIT" reply --board "$B" --id "$D1" --text "Hold: later" --no-commit 2>&1); rc=$?
[ $rc = 1 ] && grep -q "the answer lifts TD-001: " <<<"$out" && [ "$(cat "$B/$D1.md" "$R/docs/ledger/TD-001.md" | sha256sum)" = "$before" ] \
  && ok "a press on a gated item from an unattended session: decide's refusal, nothing written" || bad "gated press (rc=$rc): $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
