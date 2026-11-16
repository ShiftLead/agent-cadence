#!/usr/bin/env bash
# TD-206 §1–§2 on ledgerboard v3.0 (TD-263): board_edit.py's commands are board.py's own (its parser, so its flags),
# add writes one item file of any kind, list and fmt read and rewrite the directory, and add --parts (TD-221) writes
# the end-of-rounds item that covers() reads as covering each held build. The cadence check's classes for these
# commits are check_cadence.py's (tests/test_check_cadence.sh, tests/test_board_row.sh).
# Offline: a throwaway git repo per case; HOME/XDG_CONFIG_HOME are temp dirs, so the real roster is never read.
# Dates derive from the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDIT="$DC/files/scripts/board_edit.py"
S="$DC/files/scripts"
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

# mkrepo <dir> <People>: a v3 board with an act (a detail block under it), a plain item and an undated one.
mkrepo() {
  rm -rf "$1"; git init -q -b main "$1"; local d="$1/docs/user_attention"; mkdir -p "$d"
  printf '# board\n\nLedgerboard: 3\nSwept: %s (h, quick)\n\nPeople: %s\n' "$TODAY" "$2" > "$d/README.md"
  printf '# board\n\nLedgerboard: 3\n\nThis board is the directory [user_attention/](user_attention/), one file per item (ledgerboard v3.0).\n' > "$1/docs/user_attention.md"
  printf '## rotate the key\n\n**Kind:** act\n**Added:** %s\n**Session:** abcdef12 on h\n**Context:** TD-1\n**Due:** %s\n\n- **Context:** the old key leaked into a log.\n' "$PAST" "$FUT" > "$d/$PAST-000000a1.md"
  printf '## plain item\n\n**Added:** %s\n**Due:** %s\n' "$PAST" "$FUT" > "$d/$PAST-000000a2.md"
  printf '## undated and unpunctuated\n\n**Added:** %s\n' "$PAST" > "$d/$PAST-000000a3.md"
  git -C "$1" add -A; git -C "$1" commit -qm base
}
newid() { python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }

# --- 1) add: every kind, as item_file() writes it, round-tripping the module's reader and canonical form
R="$TMP/a"; mkrepo "$R" Pat; B="$R/docs/user_attention"
id=$("$EDIT" add --board "$B" --kind decide --text "Back up the share?" --context TD-7 --due "$FUT" \
  --answer "Nightly — a session sets it up" --answer "Weekly — a session sets it up" --default 0 --session abcdef12 --host h --json \
  --detail '{"context": "the share holds the notices.", "question": "Back it up?", "recommended": "cheap."}' 2>/dev/null | newid)
chk=$(python3 - "$B/$id.md" "$S" <<'EOF'
import sys
sys.path.insert(0, sys.argv[2])
import ledgerboard as lb
text = open(sys.argv[1]).read()
it = lb.parse_item(text, sys.argv[1])
assert it is not None and it.kind == "decide" and it.words == "Back up the share?", it
assert it.answers == ["Nightly", "Weekly"] and it.default == "Nightly" and it.context == "TD-7", it
assert it.session == "abcdef12" and it.host == "h", (it.session, it.host)
assert lb.canonical_item_file(text) == text
assert "- **Context:** the share holds the notices." in text and "- **Recommended:** Nightly — cheap." in text, text
print("ok")
EOF
)
[ "$chk" = ok ] && [ "$(git -C "$R" log -1 --format=%s)" = "board_edit: append $id Back up the share? (session abcdef12)" ] \
  && [ "$(git -C "$R" show --name-only --format= HEAD)" = "docs/user_attention/$id.md" ] \
  && ok "add decide: the writer's item file and detail block, one commit of that file under the append subject" \
  || bad "add decide: $chk / $(git -C "$R" log -1 --format=%s)"
for k in act look watch fyi; do
  extra=(); [ $k = fyi ] || extra=(--due "$FUT")
  t="a $k item."; [ $k = act ] && t="**Rotate the key.** a $k item."
  "$EDIT" add --board "$B" --kind $k --text "$t" "${extra[@]}" >/dev/null 2>&1 || bad "add $k refused"
done
chk=$(python3 - "$R/docs/user_attention.md" "$B" "$S" <<'EOF'
import sys
sys.path.insert(0, sys.argv[3])
import ledgerboard as lb
from ledgerboard import board as LBB
for path in sys.argv[1:3]:   # the stub and the directory name one board
    b = LBB.read_board(path)
    assert b.form == "dir" and not b.problems, (path, b.problems)
got = sorted(it.kind for it in b.items if it.words.startswith(("a ", "**Rotate")))
print(" ".join(got))
EOF
)
[ "$chk" = "act fyi look watch" ] && ok "add act, look, watch and fyi: each an item file the reader reads, by stub or directory" || bad "add kinds: $chk"
id=$("$EDIT" add --board "$B" --text "decided already." --decided "Go" --context TD-8 --json 2>/dev/null | newid)
grep -qx "\*\*Decided:\*\* $TODAY by Pat — Go" "$B/$id.md" && ok "add --decided: by the board's one People: name" || bad "add --decided: $(cat "$B/$id.md" 2>&1)"
snap() { (cd "$B" && find . -type f | sort | xargs sha256sum); }; before=$(snap)
"$EDIT" add --board "$B" --text "x." --line 3 >/dev/null 2>&1; r1=$?
"$EDIT" add --board "$B" --text "bad." --due "not-a-date" >/dev/null 2>&1; r2=$?
"$EDIT" fmt --board "$B" --tool x >/dev/null 2>&1; r3=$?
"$EDIT" list --board "$B" --no-commit >/dev/null 2>&1; r4=$?
"$EDIT" add --board "$B" --text "x." --id "$PAST-000000a1" >/dev/null 2>&1; r5=$?
[ "$r1$r3$r4" = 222 ] && [ "$r2$r5" = 11 ] && [ "$(snap)" = "$before" ] \
  && ok "usage: a retired or untaken option is exit 2, a write the writer refuses (a bad date, a taken id) exit 1, board untouched" \
  || bad "usage: $r1 $r2 $r3 $r4 $r5"
chk=$(python3 - "$S" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import board_edit as E
from ledgerboard import board as LBB
assert set(E.ACTIONS) <= set(LBB.ACTIONS), set(E.ACTIONS) - set(LBB.ACTIONS)
assert set(LBB.EDITS) <= set(E.WRITES) and "add" in E.WRITES
assert set(LBB.ACTIONS) - set(E.ACTIONS) == {"split", "rank"}, set(LBB.ACTIONS) - set(E.ACTIONS)
print("ok")
EOF
)
[ "$chk" = ok ] && ok "the wrapper's commands are board.py's (its parser, so its flags), split and rank aside" || bad "commands: $chk"
"$EDIT" add --board "$B" --text "not committed." --due "$FUT" --no-commit >/dev/null 2>&1 \
  && [ -n "$(git -C "$R" status --porcelain)" ] && ok "add --no-commit writes the file only" || bad "add --no-commit"
git -C "$R" clean -qfd docs

# --- 2) list and fmt
n=$("$EDIT" list --board "$B" --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["items"]))')
[ "$n" = 9 ] && ok "list --json: the open items (a decided item is still open)" || bad "list --json: $n"
"$EDIT" list --board "$B" --json | python3 -c '
import json,sys; r=json.load(sys.stdin)["items"]; assert all(x["id"] and "line" not in x for x in r), r' 2>/dev/null \
  && ok "list --json: each item by its id, no line" || bad "list --json ids"
printf '## needs a tidy\n\n**Due:** %s\n**Added:** %s\n' "$FUT" "$PAST" > "$B/$PAST-000000b1.md"
printf 'no heading at all\n' > "$B/$PAST-000000b2.md"
git -C "$R" add -A; git -C "$R" commit -qm "two hand-written files"
out=$("$EDIT" fmt --board "$B" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -q "$PAST-000000b2 kept as it is" && echo "$out" | grep -q "not committed" \
  && [ "$(sed -n 3p "$B/$PAST-000000b1.md")" = "**Added:** $PAST" ] \
  && ok "fmt rewrites what it can into the writers' form, lists what it keeps, commits nothing" || bad "fmt rc=$rc: $out / $(cat "$B/$PAST-000000b1.md")"
git -C "$R" checkout -q -- docs

# --- 3) TD-221, cadence §4.8: the end-of-rounds item is written with its gate and `Parts:` (add --parts, carried
#        through), checked against ledger/ beside the board, and covers() reads each held build's gate as covered
R="$TMP/parts"; rm -rf "$R"; mkdir -p "$R/docs/user_attention"
cp -R "$DC/tests/ledgerboard/board_writer/add_parts/before/ledger" "$R/docs/ledger"
printf '# board\n\nLedgerboard: 3\n\nPeople: robin\n' > "$R/docs/user_attention/README.md"
git -C "$R" init -q -b main; git -C "$R" add -A; git -C "$R" commit -qm base
B="$R/docs/user_attention"
out=$("$EDIT" add --board "$B" --kind decide --text "Go on the report builds?" --context "TD-4 decision (robin)" \
  --due "$FUT" --answer "Go — the grinders build it" --answer "Not yet — nobody picks the entries until you say" --parts TD-10,TD-9 --json \
  --detail '{"context": "its rounds ended.", "question": "Go on its builds?", "recommended": "Go."}' 2>&1); rc=$?
id=$(newid <<<"$out" 2>/dev/null)
[ $rc = 0 ] && grep -qx "\*\*Parts:\*\* TD-9, TD-10" "$B/$id.md" && grep -qx "\*\*Context:\*\* TD-4 decision (robin)" "$B/$id.md" \
  && [ "$(git -C "$R" show --name-only --format= HEAD)" = "docs/user_attention/$id.md" ] \
  && ok "add --parts: one commit, Parts: in number order" || bad "add --parts rc=$rc: $out"
res=$(python3 - "$S" "$R" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path
import ledgerboard as LB
from ledgerboard import board as LBB
r = Path(sys.argv[2]); board = LBB.read_board(str(r / "docs/user_attention"))   # a board is (origin url, repo name, Board)
print(" ".join(f"{t}:{[s for _, _, s in LB.covers((r / f'docs/ledger/{t}.md').read_text(), 'decision (robin)', [('', 'r', board)], 'r')]}"
               for t in ("TD-009", "TD-010")))
EOF
)
[ "$res" = "TD-009:['open'] TD-010:['open']" ] \
  && ok "covers(): the one end-of-rounds item covers each held build's decision gate" || bad "covers: $res"
out=$("$EDIT" add --board "$B" --kind decide --text "Go?" --context "TD-4" --due "$FUT" --answer "Go — the grinders build it" --answer "No — nobody builds it" \
  --parts TD-9 --detail '{"context": "c.", "question": "q?", "recommended": "Go."}' --no-commit 2>&1); rc=$?
[ $rc != 0 ] && grep -q refused <<< "$out" && ok "add --parts with no gate in the Context: refused" || bad "no gate rc=$rc: $out"
out=$("$EDIT" add --board "$B" --kind decide --text "Go?" --context "TD-4 decision (robin)" --due "$FUT" --answer "Go — the grinders build it" --answer "No — nobody builds it" \
  --parts TD-9,TD-99 --detail '{"context": "c.", "question": "q?", "recommended": "Go."}' --no-commit 2>&1); rc=$?
[ $rc != 0 ] && grep -q 'TD-99' <<< "$out" && ok "add --parts naming an entry the ledger beside the board lacks: refused, naming it" || bad "missing part rc=$rc: $out"

# --- TD-268: a decide or act line is text a person reads, checked at its writer (person_text.py)
before=$(ls "$B" | sha256sum)
padd() { "$EDIT" add --board "$B" --due "$FUT" --no-commit "$@" >/dev/null 2>"$TMP/err"; }
padd --kind decide --text "**Backup** — should the share be backed up?" --answer "Yes — a session sets it up" --answer "No — nobody does"; r1=$?
grep -q 'rule 1: .*does not end in ?' "$TMP/err" && [ $r1 = 1 ] && ok "a decide's bold opening is its whole question: **Title** — question? refused" || bad "bold title rc=$r1: $(cat "$TMP/err")"
padd --kind decide --text "Should we back up **now**?" --answer "Yes — a session sets it up"; r1=$?
grep -q 'bold run mid-text is refused' "$TMP/err" && [ $r1 = 1 ] && ok "a decide with a bold run mid-text is refused" || bad "bold mid rc=$r1: $(cat "$TMP/err")"
padd --kind decide --text "Back up the share nightly." --answer "Yes" --answer "No — nobody does"; r1=$?
[ $r1 = 1 ] && grep -q 'rule 1' "$TMP/err" && grep -q 'rule 2: answer 1 names nobody' "$TMP/err" && ! grep -q 'answer 2' "$TMP/err" \
  && ok "a decide listing every problem at once: a statement (rule 1), an answer naming nobody (rule 2)" || bad "all at once rc=$r1: $(cat "$TMP/err")"
padd --kind act --text "Merge the cleanup; only you can do this"; r1=$?
[ $r1 = 1 ] && grep -q 'an act opens with its task in bold' "$TMP/err" && ok "an act with no bold opening is refused" || bad "act no bold rc=$r1: $(cat "$TMP/err")"
[ "$(ls "$B" | sha256sum)" = "$before" ] && ok "the refused lines wrote nothing" || bad "a refused line wrote the board"
padd --kind decide --text "Should the share be backed up nightly?" --answer "Nightly — a session sets it up" --answer "No — nothing is backed up, as you prefer" \
  --detail '{"context": "the job is `backup.sh`.", "question": "Back it up?", "recommended": "cheap."}'; r1=$?
[ $r1 = 0 ] && grep -q 'warning — the decide line: rule 4: .*backup.sh' "$TMP/err" && ok "a decide that passes is written; code in its detail context warns (rule 4)" || bad "decide ok rc=$r1: $(cat "$TMP/err")"
padd --kind act --text "**Merge the cleanup change** — it alters the gate; only you can do this"; r1=$?
[ $r1 = 0 ] && ok "an act opening with its task in bold is written" || bad "act ok rc=$r1: $(cat "$TMP/err")"
out=$("$EDIT" add --board "$B" --kind act --text "no bold here" --due "$FUT" --no-commit --json 2>/dev/null); r1=$?
[ $r1 = 1 ] && grep -q '"refused"' <<< "$out" && ok "--json: a person-text refusal prints the refused line" || bad "json refusal rc=$r1: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
