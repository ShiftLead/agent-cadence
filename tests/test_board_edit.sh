#!/usr/bin/env bash
# TD-036: board_edit.py (add|snooze|due|done|decide|reply|fmt|list), the one script every tool writes the board
# through — from TD-213 a wrapper over the vendored ledgerboard's board writer (ledgerboard/board.py), from TD-263
# over v3.0: the board is a directory of item files, an item is named by --id, and done archives the item's file.
# What the wrapper adds is git (the clean-files check, one commit of the files the write changed, the fixed
# message), the People: default for a reply's --by, and the refusals of what v3.0 retired.
# Offline: a throwaway git repo per case; HOME/XDG_CONFIG_HOME are temp dirs, so the real
# roster is never read. Dates derive from the run date (TD-24).
set -u
export TZ=UTC  # TD-209: `date -d 'N days'` from now is N×24h, an hour short across DST; UTC has none, and the scripts under test inherit it
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDIT="$DC/files/scripts/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset SHIFTLEAD_SESSION
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F); PAST=$(date -d "3 days ago" +%F); MONTH=$(date +%Y-%m)
FUT=$(date -d "10 days" +%F); FUT2=$(date -d "20 days" +%F)
Q="$PAST-0000000a"; P="$PAST-0000000b"; U="$PAST-0000000c"

# mkboard <repo> [People: line]: a v3 board (the directory and its stub) holding a question with answers and a
# due date (Q), a plain item (P) and an undated one (U), committed.
mkboard() {
  rm -rf "$1"; git init -q -b main "$1"; local d="$1/docs/user_attention"; mkdir -p "$d"
  { printf '# board\n\nLedgerboard: 3\nSwept: %s (testhost, quick)\n' "$TODAY"; [ -n "${2:-}" ] && printf '\n%s\n' "$2"; } > "$d/README.md"
  printf '# board\n\nLedgerboard: 3\n\nThis board is the directory [user_attention/](user_attention/), one file per item (ledgerboard v3.0).\n' > "$1/docs/user_attention.md"
  printf '## merge PR #7 or hold it?\n\n**Kind:** decide\n**Added:** %s\n**Session:** abcdef12 on testhost\n**Context:** PR #7\n**Due:** %s\n**Answers:** merge (default) | hold\n\n- **Context:** c.\n- **Question:** q.\n- **Recommended:** merge — r.\n' "$PAST" "$PAST" > "$d/$Q.md"
  printf '## plain item\n\n**Added:** %s\n**Context:** TD-1\n**Due:** %s\n' "$PAST" "$PAST" > "$d/$P.md"
  printf '## undated and unpunctuated\n\n**Added:** %s\n' "$PAST" > "$d/$U.md"
  git -C "$1" add -A; git -C "$1" commit -qm base
}
field() { grep -m1 "^\*\*$2:\*\*" "$1" 2>/dev/null; }   # <item file> <field>: its header line
R="$TMP/r"; mkboard "$R" "People: Pat"; D="$R/docs/user_attention"; S="$R/docs/user_attention.md"

# --- 1) decide: Decided: on that item, one commit of that file alone, the fixed message carrying the id
echo scratch > "$R/other.txt"; git -C "$R" add other.txt   # staged elsewhere: must stay out of the commit
out=$("$EDIT" decide --board "$S" --id "$Q" --answer "merge" --by Pat --tool shiftlead 2>&1); rc=$?
[ $rc = 0 ] && ok "decide exits 0 (the board named by its stub)" || bad "decide rc=$rc: $out"
[ "$(field "$D/$Q.md" Decided)" = "**Decided:** $TODAY by Pat — merge" ] && ok "decide: Decided: today by who answered (--by)" || bad "decide: $(cat "$D/$Q.md")"
msg=$(git -C "$R" log -1 --format=%s); files=$(git -C "$R" show --name-only --format= HEAD)
[ "$msg" = "shiftlead: decide $Q merge PR #7 or hold it?: merge (session abcdef12)" ] \
  && ok "decide: the carve-out's fixed commit message, the id after the action" || bad "commit message: $msg"
[ "$files" = "docs/user_attention/$Q.md" ] && ok "decide: the commit carries the item file only (a staged file stays staged)" || bad "commit files: $files"
git -C "$R" diff --cached --name-only | grep -qx other.txt && ok "the staged file is still staged" || bad "the staged file was lost"
git -C "$R" reset -q other.txt; rm "$R/other.txt"
grep -q "^- \*\*Recommended:\*\* merge — r\.$" "$D/$Q.md" && ok "decide keeps the detail block as it was" || bad "detail block changed: $(cat "$D/$Q.md")"

# --- 2) refusals: an id no open item has, an answer the writer refuses, a dirty item file — nothing written
head=$(git -C "$R" rev-parse HEAD); snap() { (cd "$D" && find . -type f | sort | xargs sha256sum); }; before=$(snap)
"$EDIT" decide --board "$D" --id "$PAST-deadbeef" --answer merge --by Pat >/dev/null 2>"$TMP/err"; rc=$?
[ $rc = 1 ] && grep -q "no open item has the id" "$TMP/err" && [ "$(snap)" = "$before" ] \
  && ok "an id no open item has is refused, exit 1, board untouched" || bad "unknown id rc=$rc: $(cat "$TMP/err")"
"$EDIT" decide --board "$D" --id "nope" --answer merge --by Pat >/dev/null 2>&1; rc=$?
[ $rc = 1 ] && [ "$(snap)" = "$before" ] && ok "a malformed id is refused" || bad "malformed id rc=$rc"
"$EDIT" reply --board "$D" --id "$P" --text "" --by Pat >/dev/null 2>&1; rc=$?
[ $rc = 1 ] && [ "$(snap)" = "$before" ] && ok "a reply with empty words is refused" || bad "empty reply rc=$rc"
echo "hand edit" >> "$D/$P.md"; cp "$D/$P.md" "$TMP/dirty"
"$EDIT" done --board "$D" --id "$P" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc = 1 ] && cmp -s "$D/$P.md" "$TMP/dirty" && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && grep -q "uncommitted" "$TMP/err" \
  && ok "an item file with uncommitted changes is refused before any write" || bad "dirty item rc=$rc: $(cat "$TMP/err")"
git -C "$R" checkout -q -- "docs/user_attention/$P.md"

# --- 3) snooze hides the item until a date (Hide until:) and leaves Due: alone; due moves Due: and adds one
"$EDIT" snooze --board "$D" --id "$P" --to "$FUT2" >/dev/null 2>&1
[ "$(field "$D/$P.md" "Hide until")" = "**Hide until:** $FUT2" ] && [ "$(field "$D/$P.md" Due)" = "**Due:** $PAST" ] \
  && ok "snooze writes Hide until: and keeps the Due: date" || bad "snooze: $(cat "$D/$P.md")"
[ "$(git -C "$R" log -1 --format=%s)" = "board_edit: snooze $P plain item to $FUT2 (session n/a)" ] \
  && ok "snooze commits under the fixed message" || bad "snooze message: $(git -C "$R" log -1 --format=%s)"
"$EDIT" due --board "$D" --id "$U" --to "$FUT" >/dev/null 2>&1
[ "$(field "$D/$U.md" Due)" = "**Due:** $FUT" ] && ok "due on an undated item adds Due:" || bad "due undated: $(cat "$D/$U.md")"
[ "$(git -C "$R" log -1 --format=%s)" = "board_edit: due $U undated and unpunctuated to $FUT (session n/a)" ] \
  && ok "due commits under the fixed message" || bad "due message: $(git -C "$R" log -1 --format=%s)"
"$EDIT" snooze --board "$D" --id "$P" --to 2026-02-30 >/dev/null 2>&1; [ $? = 2 ] && ok "snooze --to a non-date is a usage error (exit 2)" || bad "bad --to accepted"
"$EDIT" due --board "$D" --id "$P" >/dev/null 2>&1; [ $? = 2 ] && ok "due without --to is a usage error" || bad "due without --to accepted"
"$EDIT" snooze --board "$D" --id "$P" --to "$FUT" --why x >/dev/null 2>&1; [ $? = 2 ] && ok "--why on snooze is a usage error" || bad "--why accepted on snooze"
"$EDIT" snooze --board "$D" --id "$P" --to "$FUT" --by Pat >/dev/null 2>&1; [ $? = 2 ] && ok "--by on snooze is a usage error" || bad "--by accepted on snooze"

# --- 4) done: the item's file moves to archive/<YYYY-MM>/ with Closed: today — why, in one commit
"$EDIT" done --board "$D" --id "$P" --why "merged in
PR #9." >/dev/null 2>&1; rc=$?
A="$D/archive/$MONTH/$P.md"
[ $rc = 0 ] && [ ! -e "$D/$P.md" ] && [ "$(field "$A" Closed)" = "**Closed:** $TODAY — merged in PR #9" ] \
  && ok "done --why: the file moves to archive/, Closed: today — why (whitespace collapsed)" || bad "done rc=$rc: $(cat "$A" 2>&1)"
[ "$(git -C "$R" show --name-status --format= HEAD | awk '{print $1}' | cut -c1)" = "R" ] \
  && ok "done: one commit, the item's move" || bad "done commit: $(git -C "$R" show --name-status --format= HEAD)"
"$EDIT" list --board "$D" | grep -q "plain item" && bad "list still shows a closed item" || ok "list drops the closed item"
"$EDIT" done --board "$D" --id "$P" >/dev/null 2>&1; [ $? = 1 ] && ok "done on an archived item: no open item has the id" || bad "done twice accepted"

# --- 5) reply: the person's words in the item's Log; --by defaults to the board's one People: name
"$EDIT" reply --board "$D" --id "$U" --text "do it
on Monday" --by Pat >/dev/null 2>&1; [ $? = 1 ] && [ -z "$(grep '^- ' "$D/$U.md")" ] \
  && ok "reply: words holding a line break are refused (v3.0: one line)" || bad "a multi-line reply was written: $(cat "$D/$U.md")"
out=$("$EDIT" reply --board "$D" --id "$U" --text "do  it on Monday" --tool shiftlead 2>&1); rc=$?
[ $rc = 0 ] && grep -qx -- "- $TODAY: Pat: do it on Monday" "$D/$U.md" \
  && ok "reply: a Log line, --by defaulting to the one People: name (whitespace folded)" || bad "reply rc=$rc: $out / $(cat "$D/$U.md")"
[ "$(git -C "$R" log -1 --format=%s)" = "shiftlead: reply $U undated and unpunctuated (session n/a)" ] \
  && ok "reply: one commit, the fixed message (the words stay on the board)" || bad "reply commit: $(git -C "$R" log -1 --format=%s)"
"$EDIT" reply --board "$D" --id "$U" --text "next week" --by "Alex W." >/dev/null 2>&1
[ "$(grep -c "^- $TODAY: " "$D/$U.md")" = 2 ] && grep -qx -- "- $TODAY: Alex W.: next week" "$D/$U.md" \
  && ok "a second reply follows the first" || bad "second reply: $(cat "$D/$U.md")"
"$EDIT" reply --board "$D" --id "$U" --text x --by Pat --answer y >/dev/null 2>&1; r1=$?
"$EDIT" reply --board "$D" --id "$U" >/dev/null 2>&1; r2=$?
"$EDIT" done --board "$D" --id "$U" --text x >/dev/null 2>&1; r3=$?
[ "$r1$r2$r3" = 222 ] && ok "reply usage: --answer refused, --text required, --text on another action refused" || bad "reply usage: $r1 $r2 $r3"

# --- 6) who answered: decide's --by is never git's user.name; one People: name is the default, a name off it refused
git -C "$R" config user.name "Robin Q"; before=$(cat "$D/$Q.md")
"$EDIT" decide --board "$D" --id "$Q" --answer hold --by Robin >/dev/null 2>&1; rc=$?
[ $rc = 1 ] && [ "$(cat "$D/$Q.md")" = "$before" ] && ok "decide --by a name off the board's People: line is refused" || bad "decide off People: rc=$rc"
"$EDIT" decide --board "$D" --id "$Q" --answer hold >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(field "$D/$Q.md" Decided)" = "**Decided:** $TODAY by Pat — hold" ] \
  && ok "re-decide on a one-person People: board: --by defaults to that person, the answer replaced" || bad "decide People: default rc=$rc: $(cat "$D/$Q.md")"
git -C "$R" config --unset user.name
R2="$TMP/r2"; mkboard "$R2"; D2="$R2/docs/user_attention"; before=$(cat "$D2/$Q.md" "$D2/$P.md")
"$EDIT" decide --board "$D2" --id "$Q" --answer merge >/dev/null 2>&1; r1=$?
"$EDIT" reply --board "$D2" --id "$P" --text "named" >/dev/null 2>&1; r2=$?
[ "$r1$r2" = 11 ] && [ "$(cat "$D2/$Q.md" "$D2/$P.md")" = "$before" ] \
  && ok "no People: line: decide and reply with no --by are refused" || bad "no People: rc=$r1 $r2"
R3="$TMP/r3"; mkboard "$R3" "People: Pat, Sam"; D3="$R3/docs/user_attention"
"$EDIT" reply --board "$D3" --id "$P" --text "x" >/dev/null 2>&1; rc=$?
[ $rc = 1 ] && ok "reply with no --by on a two-person People: board is refused" || bad "reply two-people rc=$rc"

# --- 7) add: an item file, its id printed, committed alone under the append subject
out=$("$EDIT" add --board "$S" --kind act --text "Rotate the key." --context TD-4 --due "$FUT" --session s-1 2>&1); rc=$?
id=$(grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9a-f]{8}" <<<"$out" | head -1)
[ $rc = 0 ] && [ -f "$D/$id.md" ] && [ "$(field "$D/$id.md" Kind)" = "**Kind:** act" ] \
  && ok "add: a new item file, its id printed" || bad "add rc=$rc: $out"
[ "$(git -C "$R" log -1 --format=%s)" = "board_edit: append $id Rotate the key. (session s-1)" ] \
  && [ "$(git -C "$R" show --name-only --format= HEAD)" = "docs/user_attention/$id.md" ] \
  && ok "add: committed alone under the append subject" || bad "add commit: $(git -C "$R" log -1 --format=%s)"
"$EDIT" list --board "$S" | grep -q "^$id	" && ok "list: the new item by its id" || bad "list: $("$EDIT" list --board "$S")"

# --- 8) --no-commit writes a board outside git; a commit outside git is refused
mkdir -p "$TMP/nogit/b"; printf '# b\n\nLedgerboard: 3\n\nPeople: Alex\n' > "$TMP/nogit/b/README.md"
printf '## outside git\n\n**Added:** %s\n**Due:** %s\n**Answers:** hold | go\n' "$PAST" "$FUT" > "$TMP/nogit/b/$Q.md"
"$EDIT" decide --board "$TMP/nogit/b" --id "$Q" --answer hold >/dev/null 2>&1; rc=$?
[ $rc = 1 ] && ! grep -q Decided "$TMP/nogit/b/$Q.md" && ok "outside git without --no-commit: refused, untouched" || bad "nogit commit rc=$rc"
"$EDIT" decide --board "$TMP/nogit/b" --id "$Q" --answer hold --no-commit >/dev/null 2>&1
[ "$(field "$TMP/nogit/b/$Q.md" Decided)" = "**Decided:** $TODAY by Alex — hold" ] && ok "--no-commit writes the file only" || bad "--no-commit: $(cat "$TMP/nogit/b/$Q.md")"
"$EDIT" decide --board "$TMP/nogit/b" --id "$Q" --answer go --plan >/dev/null 2>&1 && cmp -s <(field "$TMP/nogit/b/$Q.md" Decided) <(echo "**Decided:** $TODAY by Alex — hold") \
  && ok "--plan writes nothing" || bad "--plan wrote: $(cat "$TMP/nogit/b/$Q.md")"

# --- 9) what ledgerboard v3.0 retired is refused by name, exit 2; a v2 board file is refused for writes
"$EDIT" done --board "$D" --line 7 --expect x >/dev/null 2>"$TMP/err"; rc=$?
[ $rc = 2 ] && grep -q -- "--id" "$TMP/err" && ok "--line/--expect: exit 2, naming --id" || bad "--line rc=$rc: $(cat "$TMP/err")"
"$EDIT" archive --board "$D" >/dev/null 2>"$TMP/err"; r1=$?
"$EDIT" replay --board "$D" >/dev/null 2>"$TMP/err2"; r2=$?
[ "$r1$r2" = 22 ] && grep -q "retired" "$TMP/err" && grep -q "retired" "$TMP/err2" \
  && ok "archive and replay: retired, exit 2" || bad "archive/replay rc=$r1 $r2"
"$EDIT" split --board "$D" >/dev/null 2>&1; [ $? = 2 ] && ok "split is board.py's, not board_edit.py's" || bad "split accepted"
V2="$TMP/v2"; rm -rf "$V2"; git init -q -b main "$V2"; mkdir -p "$V2/docs"
printf '# board\n\n## Needs the user\n\n- [ ] %s (n/a) — a v2 item. Due: %s.\n' "$PAST" "$FUT" > "$V2/docs/user_attention.md"
git -C "$V2" add -A; git -C "$V2" commit -qm v2; cp "$V2/docs/user_attention.md" "$TMP/v2before"
"$EDIT" add --board "$V2/docs/user_attention.md" --text "new." --due "$FUT" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc = 1 ] && grep -q "split first: board.py split" "$TMP/err" && cmp -s "$V2/docs/user_attention.md" "$TMP/v2before" \
  && ok "a write to a v2 board: refused, split first" || bad "v2 write rc=$rc: $(cat "$TMP/err")"
"$EDIT" list --board "$V2/docs/user_attention.md" | grep -q "a v2 item" && ok "list still reads a v2 board" || bad "list v2: $("$EDIT" list --board "$V2/docs/user_attention.md" 2>&1)"

# --- 10) the SYNC contract: shipped executable, and sync.sh lists it
[ -x "$EDIT" ] && ok "board_edit.py is executable" || bad "board_edit.py not executable"
grep -q '"scripts/board_edit.py"' "$DC/sync.sh" && ok "sync.sh ships board_edit.py" || bad "board_edit.py missing from SYNC_FILES"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
