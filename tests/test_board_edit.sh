#!/usr/bin/env bash
# TD-036: a board item's Answers:/Decided: fields — read by nudge_user_attention.py, written
# by board_edit.py (snooze|done|decide|reply), the one script every tool edits the board through.
# Offline: a throwaway git repo per case; HOME/XDG_CONFIG_HOME are temp dirs, so the real
# roster is never read. Dates derive from the run date (TD-24).
set -u
export TZ=UTC  # TD-209: `date -d 'N days'` from now is N×24h, an hour short across DST; UTC has none, and the scripts under test inherit it
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$DC/files/scripts/nudge_user_attention.py"
EDIT="$DC/files/scripts/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F); PAST=$(date -d "3 days ago" +%F); DPAST=$(date -d "2 days ago" +%F)
FUT=$(date -d "10 days" +%F); FUT2=$(date -d "20 days" +%F)

# A board with: a question (answers, due), a plain item (neither field), an undated question
# whose answers carry a literal bar, an item whose PROSE says "Answers:" before its Due:, and a
# decided item not yet due. Line numbers are fixed by this layout (the stamp is line 3).
mkboard() {  # $1 = repo dir
  rm -rf "$1"; git init -q -b main "$1"; mkdir -p "$1/docs"
  cat > "$1/docs/user_attention.md" <<EOF
# board

Swept: $TODAY (testhost, quick)

## Needs the user

- [ ] $PAST (session abcdef12 on testhost) — **merge PR #7 or hold it?** Context: PR #7. Due: $PAST. Answers: merge | hold | ask me Monday.
- [ ] $PAST (session n/a) — plain item. Context: TD-1. Due: $PAST.
- [ ] $PAST (session 0badf00d on testhost) — pick a shape. Answers: a \| b | c.
- [ ] $PAST (n/a) — the Answers: are in the TD. Due: $FUT.
- [ ] $PAST (session 1234abcd on testhost) — keep the purge? Due: $FUT. Answers: keep | stop. Decided: stop it (then tell me) ($DPAST).
- [ ] $PAST (n/a) — undated, we should check Answers: yes this is prose, and Decided: no (2026-01-01).
- [ ] $PAST (n/a) — undated and unpunctuated
EOF
  git -C "$1" add -A; git -C "$1" commit -qm base
}
R="$TMP/r"; mkboard "$R"; B="$R/docs/user_attention.md"

# --- 1) parse: fields round-trip through --report --json; an entry with neither is unchanged
chk=$(python3 "$NUDGE" --report --json --board "$B" 2>&1 | python3 -c '
import json, sys
it = {i["line"]: i for i in json.load(sys.stdin)["boards"][0]["items"]}
past, dpast = sys.argv[1], sys.argv[2]
assert it[7]["answers"] == ["merge", "hold", "ask me Monday"], it[7]
assert it[7]["decided"] is None and it[7]["waiting_on"] == "person", it[7]
assert it[8]["answers"] == [] and it[8]["decided"] is None and it[8]["due"] == past, it[8]
assert it[9]["answers"] == ["a | b", "c"], it[9]
assert it[10]["answers"] == [], ("prose Answers: before Due: parsed as the field", it[10])
assert it[11]["decided"] == {"text": "stop it (then tell me)", "date": dpast}, it[11]
assert it[11]["waiting_on"] == "session" and it[11]["answers"] == ["keep", "stop"], it[11]
assert it[12]["answers"] == [] and it[12]["decided"] is None, ("undated prose parsed as a field", it[12])
print("ok")' "$PAST" "$DPAST" 2>&1)
[ "$chk" = ok ] && ok "--json: answers (with an escaped bar), decided, waiting_on; plain and prose items unchanged" || bad "--json fields: $chk"

# --- 2) the text reports: a decided item waits on a session, sorts first, is not "due"
out=$(python3 "$NUDGE" --report --board "$B" 2>&1)
first=$(echo "$out" | grep -m1 '^  • ')
echo "$first" | grep -q "decided: stop it (then tell me) on $DPAST, 2d ago — waiting on a session" \
  && ok "full report: the decided item is listed first, marked waiting on a session" || bad "full report first line: $first"
echo "$out" | grep -q "2 due/overdue, 1 decided (waiting on a session)" \
  && ok "full report: the header counts decided apart from due" || bad "full header: $(echo "$out" | head -1)"
out=$(python3 "$NUDGE" --report --due-only --board "$B" 2>&1)
echo "$out" | head -1 | grep -q "2 attention item(s) due and 1 decided item(s) waiting on a session" \
  && echo "$out" | sed -n 2p | grep -q "keep the purge" && ! echo "$out" | grep -q "pick a shape" \
  && ok "--due-only: a decided item surfaces though not due, first; undated items stay out" \
  || bad "--due-only: $out"
n=$(python3 "$NUDGE" --report --json --due-only --board "$B" 2>&1 | python3 -c 'import json,sys; print(sorted(i["line"] for i in json.load(sys.stdin)["boards"][0]["items"]))')
[ "$n" = "[7, 8, 11]" ] && ok "--json --due-only keeps the decided item" || bad "--json --due-only lines: $n"

# --- 3) decide: records Decided: on exactly that line, one commit, board only, fixed message
cp "$B" "$TMP/before"
echo scratch > "$R/other.txt"; git -C "$R" add other.txt   # staged elsewhere: must stay out of the commit
out=$("$EDIT" decide --board "$B" --line 7 --expect "$PAST (session abcdef12" --answer "merge" --tool shiftlead 2>&1); rc=$?
[ $rc = 0 ] && ok "decide exits 0" || bad "decide rc=$rc: $out"
diff <(sed 7d "$TMP/before") <(sed 7d "$B") >/dev/null && ok "decide: every other line (stamp included) byte-identical" || bad "decide touched other lines"
[ "$(sed -n 7p "$B")" = "$(sed -n 7p "$TMP/before") Decided: merge ($TODAY)." ] && ok "decide: Decided: appended after Answers:" || bad "decide line: $(sed -n 7p "$B")"
msg=$(git -C "$R" log -1 --format=%s); files=$(git -C "$R" show --name-only --format= HEAD)
[ "$msg" = "shiftlead: decide merge PR #7 or hold it?: merge (session abcdef12)" ] \
  && ok "decide: the carve-out's fixed commit message" || bad "commit message: $msg"
[ "$files" = "docs/user_attention.md" ] && ok "decide: the commit carries the board only (a staged file stays staged)" || bad "commit files: $files"
git -C "$R" reset -q other.txt; rm "$R/other.txt"
w=$(python3 "$NUDGE" --report --json --board "$B" 2>&1 | python3 -c 'import json,sys; i=[x for x in json.load(sys.stdin)["boards"][0]["items"] if x["line"]==7][0]; print(i["waiting_on"], i["answers"], i["due"])')
[ "$w" = "session ['merge', 'hold', 'ask me Monday'] $PAST" ] && ok "decide: the reader now reads it as waiting on a session, answers and due intact" || bad "after decide: $w"

# re-deciding replaces the field, never stacks a second one
"$EDIT" decide --board "$B" --line 7 --expect "$PAST (session abcdef12" --answer "hold  it" >/dev/null 2>&1
l=$(sed -n 7p "$B")
[ "$(grep -o 'Decided:' <<< "$l" | wc -l)" = 1 ] && [[ "$l" == *"Decided: hold it ($TODAY)." ]] && ok "re-decide replaces the Decided: field (whitespace folded)" || bad "re-decide: $l"

# --- 4) refusals: moved line, not an item, dirty board, an answer the reader cannot read back
cp "$B" "$TMP/before"; head=$(git -C "$R" rev-parse HEAD)
"$EDIT" decide --board "$B" --line 8 --expect "$PAST (session abcdef12" --answer merge >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && cmp -s "$B" "$TMP/before" && ok "a moved line (head mismatch) is refused, exit 3, board untouched" || bad "moved line rc=$rc"
"$EDIT" done --board "$B" --line 3 --expect "Swept:" >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && cmp -s "$B" "$TMP/before" && ok "the Swept: stamp line is not an item: refused" || bad "stamp line rc=$rc"
"$EDIT" decide --board "$B" --line 9 --expect "$PAST" --answer "yes. Decided: no" >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && cmp -s "$B" "$TMP/before" && ok "an answer the reader would not read back is refused" || bad "unreadable answer rc=$rc"
echo "- [ ] $PAST (n/a) — hand-typed, uncommitted." >> "$B"; cp "$B" "$TMP/dirty"
"$EDIT" done --board "$B" --line 8 --expect "$PAST (session n/a" >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && cmp -s "$B" "$TMP/dirty" && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] \
  && ok "a board with uncommitted changes is refused before any write" || bad "dirty board rc=$rc"
git -C "$R" checkout -q docs/user_attention.md

# --- 5) snooze: an existing Due: moves; an undated item gets one before its Answers:
"$EDIT" snooze --board "$B" --line 8 --expect "$PAST (session n/a" --to "$FUT2" >/dev/null 2>&1
[ "$(sed -n 8p "$B")" = "- [ ] $PAST (session n/a) — plain item. Context: TD-1. Due: $FUT2." ] && ok "snooze rewrites the Due: date" || bad "snooze: $(sed -n 8p "$B")"
"$EDIT" snooze --board "$B" --line 9 --expect "$PAST (session 0badf00d" --to "$FUT" >/dev/null 2>&1
chk=$(python3 "$NUDGE" --report --json --board "$B" 2>&1 | python3 -c '
import json,sys; i=[x for x in json.load(sys.stdin)["boards"][0]["items"] if x["line"]==9][0]
print(i["due"], i["answers"])')
[ "$chk" = "$FUT ['a | b', 'c']" ] && sed -n 9p "$B" | grep -q "Due: $FUT. Answers:" && ok "snooze on an undated question inserts Due: before Answers:" || bad "snooze undated: $chk / $(sed -n 9p "$B")"
"$EDIT" snooze --board "$B" --line 8 --expect x --to 2026-02-30 >/dev/null 2>&1; [ $? = 2 ] && ok "snooze --to a non-date is a usage error" || bad "bad --to accepted"
git -C "$R" log --format=%s -2 | grep -q "^board_edit: snooze plain item. to $FUT2 (session n/a)$" \
  && ok "snooze commits under the fixed message" || bad "snooze message: $(git -C "$R" log --format=%s -2)"

# --- 6) done: the item is ticked and the readers stop listing it
"$EDIT" done --board "$B" --line 10 --expect "$PAST (n/a) — the Answers:" >/dev/null 2>&1
sed -n 10p "$B" | grep -q '^- \[x\] ' && ! python3 "$NUDGE" --report --board "$B" 2>&1 | grep -q "the Answers: are in the TD" \
  && ok "done ticks the item and the report drops it" || bad "done: $(sed -n 10p "$B")"

# --- 6a) TD-062: done closes, never deletes — Closed: today (with --why) at the line's end
L=$(wc -l < "$B")
[ "$(sed -n 10p "$B")" = "- [x] $PAST (n/a) — the Answers: are in the TD. Due: $FUT. Closed: $TODAY." ] \
  && [ "$(wc -l < "$B")" = "$L" ] && ok "done without --why appends Closed: today and keeps the line" || bad "done Closed: $(sed -n 10p "$B")"
"$EDIT" done --board "$B" --line 8 --expect "$PAST (session n/a) — plain" --why "merged in
PR #9." >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && sed -n 8p "$B" | grep -q "^- \[x\] .*Due: $FUT2\. Closed: $TODAY — merged in PR #9\.$" \
  && ok "done --why: Closed: today — why (whitespace collapsed)" || bad "done --why rc=$rc: $(sed -n 8p "$B")"
"$EDIT" snooze --board "$B" --line 7 --expect x --to "$FUT" --why x >/dev/null 2>&1; [ $? = 2 ] \
  && ok "--why on snooze is a usage error" || bad "--why accepted on snooze"

# --- 6b) a merge that kept both sides of a close: the closed twin wins, even snoozed/decided
TW="$TMP/twin.md"
{ cat "$B"; echo "- [ ] $PAST (session n/a) — plain item. Context: TD-1. Due: $TODAY. Decided: x ($TODAY)."; } > "$TW"
python3 "$NUDGE" --report --board "$TW" 2>&1 | grep -q "plain item" \
  && bad "an open item with a closed twin still listed" || ok "an open item whose closed twin is on the board is not listed"
{ cat "$B"; echo "- [ ] $PAST (session n/a) — plain item, reworded. Context: TD-1. Due: $TODAY."; } > "$TW"
python3 "$NUDGE" --report --board "$TW" 2>&1 | grep -q "plain item, reworded" \
  && ok "a different item is not taken for a twin" || bad "a non-twin was hidden"
{ cat "$B"; sed -n 7p "$B" | sed "s/Due: $PAST/Due: $FUT2/"; } > "$TW"
python3 "$NUDGE" --report --board "$TW" 2>&1 | grep -q "1 open item(s) appear twice" \
  && ok "two open copies of one item (a merged snooze) are named" || bad "open twins not flagged"
python3 "$NUDGE" --report --board "$B" 2>&1 | grep -q "appear twice" && bad "twin note on a clean board" || ok "no twin note on a clean board"

# --- 6c) ARCHIVE_AT closed items: the report says to archive them; one fewer, silent
AB="$TMP/arch.md"; printf '# b\n\nSwept: %s (testhost, deep)\n\n## Needs the user\n\n' "$TODAY" > "$AB"
for n in 1 2 3 4 5 6 7 8 9; do echo "- [x] $PAST (n/a) — closed $n. Closed: $TODAY." >> "$AB"; done
python3 "$NUDGE" --report --board "$AB" 2>&1 | grep -q "closed item(s) on the board" \
  && bad "archive prompt at 9 closed items" || ok "9 closed items: no archive prompt"
echo "- [x] $PAST (n/a) — closed 10. Closed: $TODAY." >> "$AB"
python3 "$NUDGE" --report --board "$AB" 2>&1 | grep -q "10 closed item(s) on the board — move them to docs/user_attention_archive.md" \
  && ok "10 closed items: the report says to archive them" || bad "no archive prompt: $(python3 "$NUDGE" --report --board "$AB" 2>&1)"
python3 "$NUDGE" --report --json --board "$AB" 2>&1 | python3 -c 'import json,sys; b=json.load(sys.stdin)["boards"][0]; assert b["archive"] and not b["items"], b' 2>/dev/null \
  && ok "--json carries the archive note; closed items are not items" || bad "--json archive slot"

# decide on an unpunctuated undated item ends its sentence first, so the reader reads it back
"$EDIT" decide --board "$B" --line 13 --expect "$PAST (n/a) — undated and" --answer go >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(sed -n 13p "$B")" = "- [ ] $PAST (n/a) — undated and unpunctuated. Decided: go ($TODAY)." ] \
  && ok "decide on an unpunctuated item: '. Decided:' (the field starts a sentence)" || bad "unpunctuated decide rc=$rc: $(sed -n 13p "$B")"

# --- 7) --no-commit edits a board outside git; a commit outside git is refused
mkdir -p "$TMP/nogit"; printf '# b\n\n- [ ] %s (n/a) — outside git. Due: %s.\n' "$PAST" "$FUT" > "$TMP/nogit/b.md"
"$EDIT" decide --board "$TMP/nogit/b.md" --line 3 --expect "$PAST" --answer hold >/dev/null 2>&1; rc=$?
[ $rc = 3 ] && ! grep -q Decided "$TMP/nogit/b.md" && ok "outside git without --no-commit: refused, untouched" || bad "nogit commit rc=$rc"
"$EDIT" decide --board "$TMP/nogit/b.md" --line 3 --expect "$PAST" --answer hold --no-commit >/dev/null 2>&1
sed -n 3p "$TMP/nogit/b.md" | grep -q "Due: $FUT. Decided: hold ($TODAY)\.$" && ok "--no-commit edits the file only" || bad "--no-commit: $(sed -n 3p "$TMP/nogit/b.md")"

# --- 7a) TD-066: one answer marked (default) — stripped from answers, carried as default
DB="$TMP/def"; rm -rf "$DB"; git init -q -b main "$DB"; mkdir -p "$DB/docs"
cat > "$DB/docs/user_attention.md" <<EOF
# board

## Needs the user

- [ ] $PAST (session abcdef12 on testhost) — merge or hold? Context: PR #7. Due: $PAST. Answers: merge (default) | hold.
- [ ] $PAST (n/a) — two marked. Due: $FUT. Answers: a (default) | b (Default).
- [ ] $PAST (n/a) — none marked. Due: $FUT. Answers: a | b.
EOF
git -C "$DB" add -A; git -C "$DB" commit -qm base
chk=$(python3 "$NUDGE" --report --json --board "$DB/docs/user_attention.md" 2>&1 | python3 -c '
import json, sys
it = {i["line"]: i for i in json.load(sys.stdin)["boards"][0]["items"]}
assert it[5]["answers"] == ["merge", "hold"] and it[5]["default"] == "merge", it[5]
assert it[6]["answers"] == ["a", "b"] and it[6]["default"] is None, it[6]
assert it[7]["default"] is None, it[7]
print("ok")' 2>&1)
[ "$chk" = ok ] && ok "(default): stripped from answers, carried as default; two marked or none = null" || bad "(default) json: $chk"
python3 "$NUDGE" --report --board "$DB/docs/user_attention.md" 2>&1 | grep -q "overdue · default: merge) " \
  && ok "the report's tag shows the default" || bad "no default in the report tag"
"$EDIT" decide --board "$DB/docs/user_attention.md" --line 5 --expect "$PAST (session abcdef12" --answer hold >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && sed -n 5p "$DB/docs/user_attention.md" | grep -q "Answers: merge (default) | hold. Decided: hold ($TODAY)\.$" \
  && ok "decide on a marked question keeps the mark; the person's answer need not be the default" || bad "decide with (default) rc=$rc: $(sed -n 5p "$DB/docs/user_attention.md")"
python3 "$NUDGE" --report --board "$DB/docs/user_attention.md" 2>&1 | grep -q "default: merge" \
  && bad "a decided item still shows the default" || ok "a decided item shows the decision, not the default"

# --- 7b) TD-075: reply — the person's words on the item's own line, read back by the reader
RB="$TMP/reply"; rm -rf "$RB"; git init -q -b main "$RB"; mkdir -p "$RB/docs"; RBB="$RB/docs/user_attention.md"
cat > "$RBB" <<EOF
# board

## Needs the user

- [ ] $PAST (session abcdef12 on testhost) — **merge or hold?** Context: PR #7. Due: $PAST. Answers: merge (default) | hold.
- [ ] $PAST (session n/a) — plain item. Context: TD-1. Due: $PAST.
- [ ] $PAST (n/a) — undated and unpunctuated
- [ ] $PAST (session 1234abcd on testhost) — keep the purge? Due: $FUT. Answers: keep | stop. Decided: stop ($DPAST).
- [x] $PAST (session n/a) — twin item. Context: TD-2. Due: $PAST. Closed: $TODAY.
- [ ] $PAST (session n/a) — twin item. Context: TD-2. Due: $PAST. — Alex, $TODAY: a reply the merge kept.
- [ ] $PAST (n/a) — read the list. Answers: are in the TD. Due: $FUT.
EOF
git -C "$RB" add -A; git -C "$RB" commit -qm base
rjson() { python3 "$NUDGE" --report --json --board "$RBB" 2>&1; }
out=$(GIT_CONFIG_GLOBAL=/dev/null "$EDIT" reply --board "$RBB" --line 6 --expect "$PAST (session n/a" --text "do  it
on Monday" --by Alex --tool shiftlead 2>&1); rc=$?
[ $rc = 0 ] && [ "$(sed -n 6p "$RBB")" = "- [ ] $PAST (session n/a) — plain item. Context: TD-1. Due: $PAST. — Alex, $TODAY: do it on Monday" ] \
  && ok "reply: ' — <by>, today: <words>' appended to the line (whitespace folded)" || bad "reply rc=$rc: $out / $(sed -n 6p "$RBB")"
[ "$(git -C "$RB" log -1 --format=%s)" = "shiftlead: reply plain item. (session n/a)" ] \
  && [ "$(git -C "$RB" show --name-only --format= HEAD)" = "docs/user_attention.md" ] \
  && ok "reply: one commit, board only, the fixed message (the words stay on the board)" || bad "reply commit: $(git -C "$RB" log -1 --format=%s)"
"$EDIT" reply --board "$RBB" --line 5 --expect "$PAST (session abcdef12" --text "wait for CI." --by "the person" >/dev/null 2>&1
"$EDIT" reply --board "$RBB" --line 5 --expect "$PAST (session abcdef12" --text "CI is green now" --by "Alex W." >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(sed -n 5p "$RBB")" = "- [ ] $PAST (session abcdef12 on testhost) — **merge or hold?** Context: PR #7. Due: $PAST. — the person, $TODAY: wait for CI. — Alex W., $TODAY: CI is green now. Answers: merge (default) | hold." ] \
  && ok "reply on a question: ahead of Answers:, a second one after the first" || bad "reply before Answers rc=$rc: $(sed -n 5p "$RBB")"
"$EDIT" reply --board "$RBB" --line 8 --expect "$PAST (session 1234abcd" --text "and tell me when" --by Alex >/dev/null 2>&1
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST (n/a) — undated" --text "next week" --by Alex >/dev/null 2>&1
chk=$(rjson | python3 -c '
import json, sys
today, past, dpast, fut = sys.argv[1:]
it = {i["line"]: i for i in json.load(sys.stdin)["boards"][0]["items"]}
r = lambda by, text: {"by": by, "date": today, "text": text}
assert it[5]["replies"] == [r("the person", "wait for CI."), r("Alex W.", "CI is green now.")], it[5]
assert it[5]["answers"] == ["merge", "hold"] and it[5]["default"] == "merge" and it[5]["due"] == past, it[5]
assert it[5]["refs"] == ["PR #7"] and it[5]["waiting_on"] == "person", it[5]
assert it[6]["replies"] == [r("Alex", "do it on Monday")] and it[6]["due"] == past and it[6]["refs"] == ["TD-1"], it[6]
assert it[7]["replies"] == [r("Alex", "next week")] and it[7]["due"] is None, it[7]
assert it[8]["replies"] == [r("Alex", "and tell me when.")], it[8]
assert it[8]["decided"] == {"text": "stop", "date": dpast} and it[8]["answers"] == ["keep", "stop"] and it[8]["due"] == fut, it[8]
assert 10 not in it, "a replied-to open copy of a closed item is still listed"
print("ok")' "$TODAY" "$PAST" "$DPAST" "$FUT" 2>&1)
[ "$chk" = ok ] && ok "reply: --json carries replies (by, date, text); due, answers, default, decided, refs unchanged; a replied-to twin of a closed item stays hidden" || bad "reply json: $chk"
cp "$RBB" "$TMP/before"; rbad=0
for bad_text in "yes. Decided: no" "see Answers: above" "Closed: it" "Context: PR #77" ""; do
  "$EDIT" reply --board "$RBB" --line 6 --expect "$PAST" --text "$bad_text" --by Alex >/dev/null 2>&1; rc=$?
  [ $rc = 3 ] && cmp -s "$RBB" "$TMP/before" || rbad="'$bad_text' rc=$rc"
done
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST" --text "push it, Due: $FUT" --by Alex >/dev/null 2>&1; r1=$?
"$EDIT" reply --board "$RBB" --line 6 --expect "$PAST" --text "fine" --by "Alex, or Sam" >/dev/null 2>&1; r2=$?
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST" --text "push it, Due 2026-9-5" --by Alex >/dev/null 2>&1; r3=$?
[ $r1 = 3 ] && [ $r2 = 3 ] && [ $r3 = 3 ] && cmp -s "$RBB" "$TMP/before" && [ "$rbad" = 0 ] \
  && ok "reply refused, board untouched: a field's name in the words, empty words, a Due: on an undated item, a name the reader cannot read back" || bad "reply refusals: due=$r1 by=$r2 text=$rbad"
"$EDIT" reply --board "$RBB" --line 6 --expect "$PAST" --text "push it, Due: $FUT is fine" --by Alex >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(rjson | python3 -c 'import json,sys; print([i["due"] for i in json.load(sys.stdin)["boards"][0]["items"] if i["line"]==6][0])')" = "$PAST" ] \
  && ok "a reply naming a Due: on a dated item leaves the item's own date" || bad "reply with Due: on a dated item rc=$rc"
# prose that says Answers: BEFORE the Due: is the item's own: the reply still goes after the Due:
"$EDIT" reply --board "$RBB" --line 11 --expect "$PAST (n/a) — read the list" --text "which TD?" --by Alex >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(sed -n 11p "$RBB")" = "- [ ] $PAST (n/a) — read the list. Answers: are in the TD. Due: $FUT. — Alex, $TODAY: which TD?" ] \
  && [ "$(rjson | python3 -c 'import json,sys; i=[x for x in json.load(sys.stdin)["boards"][0]["items"] if x["line"]==11][0]; print(i["answers"], len(i["replies"]))')" = "[] 1" ] \
  && ok "reply on an item whose prose says Answers: before its Due: lands after the Due:" || bad "reply after prose Answers: rc=$rc: $(sed -n 11p "$RBB")"
# the other actions on a replied-to line: snooze dates an undated one AHEAD of its reply; decide and done keep it
"$EDIT" snooze --board "$RBB" --line 7 --expect "$PAST (n/a) — undated" --to "$FUT2" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(sed -n 7p "$RBB")" = "- [ ] $PAST (n/a) — undated and unpunctuated. Due: $FUT2. — Alex, $TODAY: next week" ] \
  && ok "snooze on an undated replied-to item puts Due: ahead of the reply" || bad "snooze replied rc=$rc: $(sed -n 7p "$RBB")"
"$EDIT" decide --board "$RBB" --line 5 --expect "$PAST (session abcdef12" --answer hold >/dev/null 2>&1
"$EDIT" reply --board "$RBB" --line 5 --expect "$PAST (session abcdef12" --text "until Friday" --by Alex >/dev/null 2>&1
chk=$(rjson | python3 -c '
import json, sys
i = [x for x in json.load(sys.stdin)["boards"][0]["items"] if x["line"] == 5][0]
assert [r["text"] for r in i["replies"]] == ["wait for CI.", "CI is green now.", "until Friday."], i["replies"]
assert i["decided"]["text"] == "hold" and i["waiting_on"] == "session" and i["answers"] == ["merge", "hold"], i
print("ok")' 2>&1)
[ "$chk" = ok ] && ok "decide after replies, and a reply after a decide: the decision stands, the replies in order" || bad "reply/decide: $chk"
"$EDIT" done --board "$RBB" --line 6 --expect "$PAST (session n/a) — plain" --why handled >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && sed -n 6p "$RBB" | grep -q "^- \[x\] .* — Alex, $TODAY: do it on Monday — Alex, $TODAY: push it, Due: $FUT is fine\. Closed: $TODAY — handled\.$" \
  && ok "done on a replied-to item closes it, replies kept" || bad "done replied rc=$rc: $(sed -n 6p "$RBB")"
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST" --text x --by Alex --answer y >/dev/null 2>&1; r1=$?
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST" >/dev/null 2>&1; r2=$?
"$EDIT" done --board "$RBB" --line 7 --expect "$PAST" --text x >/dev/null 2>&1; r3=$?
[ "$r1$r2$r3" = 222 ] && ok "reply usage: --answer refused, --text required, --text on another action refused" || bad "reply usage: $r1 $r2 $r3"
# --by defaults to the checkout's git user.name, else 'the person'
git -C "$RB" config user.name "Robin Q"
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST" --text "named" >/dev/null 2>&1
git -C "$RB" config --unset user.name
"$EDIT" reply --board "$RBB" --line 7 --expect "$PAST" --text "unnamed" >/dev/null 2>&1
sed -n 7p "$RBB" | grep -q " — Robin Q, $TODAY: named — the person, $TODAY: unnamed$" \
  && [ "$(git -C "$RB" log -1 --format=%s)" = "board_edit: reply undated and unpunctuated. (session n/a)" ] \
  && ok "reply --by defaults to git user.name, else 'the person'; an earlier reply's words stay out of the commit head" || bad "reply --by default: $(sed -n 7p "$RBB") / $(git -C "$RB" log -1 --format=%s)"

# --- 8) the SYNC contract: shipped executable, and sync.sh lists it
[ -x "$EDIT" ] && ok "board_edit.py is executable" || bad "board_edit.py not executable"
grep -q '"scripts/board_edit.py"' "$DC/sync.sh" && ok "sync.sh ships board_edit.py" || bad "board_edit.py missing from SYNC_FILES"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
