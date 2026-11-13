#!/usr/bin/env bash
# TD-259/TD-254: ledgerboard v2.8 through board_edit.py — `add --doer` writes an act's Doer:, `decide` fills a
# form answer (`Hold: <note>`) and refuses an unfilled one, and a `reply` whose words begin with a form's head
# on an open decide or look line is that form's press (ShiftLead TD-1557 §4.4).
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

# Line 9: a decide with a form; 10: a look with the live pair; 11: an act with a form among its answers (not a
# press); 12: a decide already decided; 13: a watch with the live pair.
mkrepo() {  # $1 = dir
  rm -rf "$1"; git init -q -b main "$1"; mkdir -p "$1/docs"
  {
    printf '# board\n\nPeople: Pat\n\nSwept: %s (h, quick)\n\n## Needs the user\n\n' "$TODAY"
    printf -- '- [ ] decide %s (n/a) — end the rounds? Due: %s. Answers: Go | One more round | Hold: <note>.\n' "$PAST" "$FUT"
    printf -- '- [ ] look %s (n/a) — look at #5. Due: %s. Answers: Works | Not right: <what>.\n' "$PAST" "$FUT"
    printf -- '- [ ] act %s (n/a) — rotate the key. Due: %s. Answers: Done | Hold: <note>.\n' "$PAST" "$FUT"
    printf -- '- [ ] decide %s (n/a) — keep it? Due: %s. Answers: Yes | Hold: <note>. Decided: Yes (by Pat) (%s).\n' "$PAST" "$FUT" "$PAST"
    printf -- '- [ ] watch %s (n/a) — watch #6. Due: %s. Answers: Works | Not right: <what>.\n' "$PAST" "$FUT"
  } > "$1/docs/user_attention.md"
  git -C "$1" add -A; git -C "$1" commit -qm base
}
R="$TMP/r"; B="$R/docs/user_attention.md"

# --- 1) add --doer: a repo and a team, after the Context on an act
mkrepo "$R"
"$EDIT" add --board "$B" --kind act --text "Bump the pin." --context TD-9 --due "$FUT" --doer shiftlead --no-commit >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "Context: TD-9\. Doer: shiftlead\." && ok "add --doer <repo>: Doer: after the Context" \
  || bad "add --doer <repo>: $(sed -n 9p "$B")"
"$EDIT" add --board "$B" --kind act --text "Run the sweep." --context TD-9 --due "$FUT" --doer "team ac-grind" --no-commit >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "Context: TD-9\. Doer: team ac-grind\." && ok "add --doer 'team <name>'" \
  || bad "add --doer team: $(sed -n 9p "$B")"

# --- 2) add --doer refused: on decide, look and fyi; a bad value; with --decided — nothing written
mkrepo "$R"; before=$(sha256sum "$B")
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
[ "$(sha256sum "$B")" = "$before" ] && ok "refused --doer adds wrote nothing" || bad "a refused --doer add wrote the board"

# --- 3) decide fills a form; a form as written, its head alone, or a bare placeholder is refused
mkrepo "$R"
"$EDIT" decide --board "$B" --line 9 --expect "decide" --answer "hold: until the bump lands" --no-commit >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "Decided: Hold: until the bump lands (by Pat) ($TODAY)\.$" && ok "decide: a form filled, head as offered" \
  || bad "decide fill: $(sed -n 9p "$B")"
for said in "Hold: <note>" "Hold:" "HOLD:   <words>"; do
  mkrepo "$R"
  out=$("$EDIT" decide --board "$B" --line 9 --expect "decide" --answer "$said" --no-commit 2>&1); rc=$?
  [ $rc = 1 ] && grep -q "Hold needs its words" <<<"$out" && ! sed -n 9p "$B" | grep -q "Decided:" \
    && ok "decide '$said': refused, Hold needs its words" || bad "decide '$said': rc=$rc $out"
done
mkrepo "$R"
"$EDIT" decide --board "$B" --line 9 --expect "decide" --answer "Go" --no-commit >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "Decided: Go (by Pat)" && ok "decide: a complete answer as before" || bad "decide Go: $(sed -n 9p "$B")"

# --- 4) reply: a form's head on an open decide or look (or a watch with the pair) decides; else a reply
mkrepo "$R"
"$EDIT" reply --board "$B" --line 9 --expect "decide" --text "Hold: wait for the bump" --no-commit >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "Decided: Hold: wait for the bump (by Pat) ($TODAY)\.$" \
  && ! sed -n 9p "$B" | grep -q "— Pat, $TODAY:" && ok "reply 'Hold: …' on a decide: the form's press, no reply tail" \
  || bad "reply press on decide: $(sed -n 9p "$B")"
mkrepo "$R"
"$EDIT" reply --board "$B" --line 10 --expect "look" --text "not right: the toast never shows" --no-commit >/dev/null 2>&1 \
  && sed -n 10p "$B" | grep -q "Decided: Not right: the toast never shows (by Pat)" && ok "reply 'not right: …' on a look decides" \
  || bad "reply press on look: $(sed -n 10p "$B")"
mkrepo "$R"
"$EDIT" reply --board "$B" --line 13 --expect "watch" --text "Not right: flaky" --no-commit >/dev/null 2>&1 \
  && sed -n 13p "$B" | grep -q "Decided: Not right: flaky (by Pat)" && ok "reply on a watch with the look's pair decides" \
  || bad "reply press on watch: $(sed -n 13p "$B")"
mkrepo "$R"
out=$("$EDIT" reply --board "$B" --line 9 --expect "decide" --text "Hold: <note>" --no-commit 2>&1); rc=$?
[ $rc = 1 ] && grep -q "Hold needs its words" <<<"$out" && ! sed -n 9p "$B" | grep -q " — Pat, \|Decided:" \
  && ok "reply 'Hold: <note>': refused, never a reply" || bad "reply unfilled: rc=$rc $out / $(sed -n 9p "$B")"
mkrepo "$R"
"$EDIT" reply --board "$B" --line 9 --expect "decide" --text "hold off until Monday" --no-commit >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "— Pat, $TODAY: hold off until Monday" && ! sed -n 9p "$B" | grep -q "Decided:" \
  && ok "reply without a form's head and colon: a reply" || bad "plain reply: $(sed -n 9p "$B")"
mkrepo "$R"
"$EDIT" reply --board "$B" --line 11 --expect "act" --text "Hold: later" --no-commit >/dev/null 2>&1 \
  && sed -n 11p "$B" | grep -q "— Pat, $TODAY: Hold: later" && ! sed -n 11p "$B" | grep -q "Decided:" \
  && ok "reply 'Hold: …' on an act: a reply" || bad "reply on act: $(sed -n 11p "$B")"
mkrepo "$R"
"$EDIT" reply --board "$B" --line 12 --expect "decide" --text "Hold: actually wait" --no-commit >/dev/null 2>&1 \
  && sed -n 12p "$B" | grep -q "— Pat, $TODAY: Hold: actually wait" && sed -n 12p "$B" | grep -q "Decided: Yes (by Pat) ($PAST)" \
  && ok "reply 'Hold: …' on a decided line: a reply" || bad "reply on decided: $(sed -n 12p "$B")"

# --- 5) a raw label with a consequence; a committed press's subject; a press on a gated item keeps decide's lift refusal
mkrepo "$R"
sed -i "13s/Answers: Works | Not right: <what>\./Answers: Works — fine | Not right: <what> — say what./" "$B"; git -C "$R" commit -qam consequence
"$EDIT" reply --board "$B" --line 13 --expect "watch" --text "not right: slow" --no-commit >/dev/null 2>&1 \
  && sed -n 13p "$B" | grep -q "Decided: Not right: slow (by Pat)" && ok "reply press: answers with consequences" \
  || bad "reply press with consequences: $(sed -n 13p "$B")"
mkrepo "$R"
out=$("$EDIT" reply --board "$B" --line 9 --expect "decide" --text "Hold: wait" 2>&1); rc=$?
[ $rc = 0 ] && [ "$(git -C "$R" log -1 --format=%s)" = "board_edit: decide end the rounds?: Hold: wait (session n/a)" ] \
  && ok "a committed press commits as a decide" || bad "press commit (rc=$rc): $(git -C "$R" log -1 --format=%s) $out"
mkdir -p "$TMP/bin"; printf '#!/usr/bin/env bash\necho %s\n' "'[{\"id\":\"s-me\",\"by_person\":false,\"unattended\":true,\"seat\":null,\"controllers\":[\"mgr\"]}]'" > "$TMP/bin/ao"; chmod +x "$TMP/bin/ao"
rm -rf "$R"; git init -q -b main "$R"; mkdir -p "$R/docs/ledger"
printf '# board\n\nPeople: Pat\n\n## Needs the user\n\n- [ ] decide %s (n/a) — end the rounds? Context: TD-001 decision (Pat). Due: %s. Answers: Go | Hold: <note>. Lifts: Go.\n' "$PAST" "$FUT" > "$B"
printf '## TD-001: a plan\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n**Blocked by:** decision (Pat)\n\n**Why:** x.\n\n**Ask:** go?\n\n**Fix:** y.\n' "$PAST" > "$R/docs/ledger/TD-001.md"
git -C "$R" add -A; git -C "$R" commit -qm gated; before=$(cat "$B" "$R/docs/ledger/TD-001.md" | sha256sum)
out=$(PATH="$TMP/bin:$PATH" SHIFTLEAD_SESSION=s-me "$EDIT" reply --board "$B" --line 7 --expect "decide" --text "Hold: later" --no-commit 2>&1); rc=$?
[ $rc = 1 ] && grep -q "the answer lifts TD-001: " <<<"$out" && [ "$(cat "$B" "$R/docs/ledger/TD-001.md" | sha256sum)" = "$before" ] \
  && ok "a press on a gated item from an unattended session: decide's refusal, nothing written" || bad "gated press (rc=$rc): $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
