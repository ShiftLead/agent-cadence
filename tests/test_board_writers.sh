#!/usr/bin/env bash
# TD-206 §1–§2: board_edit.py's pass-through commands (add, archive, fmt, list — ledgerboard/board.py's own,
# its flags unchanged), `done` archiving in the same write at ARCHIVE_AT, and the `board-archive` class
# check_cadence.py's classify_direct and row_board_edit_pr give that commit; TD-237, an append landed by PR.
# Offline: a throwaway git repo (and a bare origin) per case; HOME/XDG_CONFIG_HOME are temp dirs, so the
# real roster is never read. Dates derive from the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDIT="$DC/files/scripts/board_edit.py"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F); PAST=$(date -d "3 days ago" +%F); YDAY=$(date -d "1 day ago" +%F); FUT=$(date -d "10 days" +%F)

# A repo with a bare origin; its board has People: Pat, $1 closed items and three open ones.
mkrepo() {  # $1 = dir, $2 = closed items on the board
  rm -rf "$1" "$1.git"; git init -q --bare -b main "$1.git"; git init -q -b main "$1"; mkdir -p "$1/docs"
  git -C "$1" remote add origin "$1.git"
  {
    printf '# board\n\nPeople: Pat\n\nSwept: %s (h, quick)\n\n## Needs the user\n\n' "$TODAY"
    printf -- '- [ ] act %s (session abcdef12 on h) — rotate the key. Context: TD-1. Due: %s.\n' "$PAST" "$FUT"
    printf -- '  - **Context:** the old key leaked into a log.\n'
    printf -- '- [ ] %s (n/a) — plain item. Due: %s.\n' "$PAST" "$FUT"
    printf -- '- [ ] %s (n/a) — undated and unpunctuated\n' "$PAST"
    printf '\n## Closed\n\n'
    for i in $(seq 1 "$2"); do printf -- '- [x] %s (n/a) — old thing %s. Due: %s. Closed: %s — done.\n' "$PAST" "$i" "$PAST" "$PAST"; done
  } > "$1/docs/user_attention.md"
  git -C "$1" add -A; git -C "$1" commit -qm base; git -C "$1" push -q origin main 2>/dev/null
}
# classify a commit, by the direct path and by the PR path (row_board_edit_pr): prints "<class> <review-row status|none>"
cls() {  # $1 = repo, $2 = sha (default HEAD)
  python3 - "$1" "${2:-HEAD}" "$S" <<'EOF'
import sys
root, ref, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", ref], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s", sha], cwd=root).strip()
files = [f for f in C.git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd=root).split() if f]
cls_, _ = C.classify_direct(root, sha, subj, files)
pr = {"state": "open", "head_sha": sha, "title": subj, "files": files, "ref": "#9"}
r = C.row_board_edit_pr(pr, root)
print(cls_, r["status"] if r else "none")
EOF
}

# --- 1) add: every kind, through item_line(), round-tripping item_problem(); prints the line it wrote
R="$TMP/a"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
out=$("$EDIT" add --board "$B" --kind decide --text "Back up the share?" --context TD-7 --due "$FUT" \
  --answer Nightly --answer Weekly --default 0 --session abcdef12 --host h \
  --detail '{"context": "the share holds the notices.", "question": "Back it up?", "recommended": "cheap."}' 2>&1); rc=$?
L=$(sed -n 9p "$B")
chk=$(python3 - "$B" "$S" <<'EOF'
import sys
sys.path.insert(0, sys.argv[2])
import ledgerboard as lb
lines = open(sys.argv[1]).read().splitlines()
ln = lines[8]
assert lb.item_problem(ln) is None, lb.item_problem(ln)
assert lb.canonical_item(ln + "\n") == ln + "\n"
blk = lb.detail_block(lines, 9)
assert any(b.startswith("- **Context:** ") for b in blk) and any(b.startswith("- **Recommended:** ") for b in blk), blk
print("ok")
EOF
)
[ $rc = 0 ] && [ "$chk" = ok ] && echo "$L" | grep -q "^- \[ \] decide $TODAY (session \`abcdef12\` on h) — Back up the share? Context: TD-7. Due: $FUT. Answers: Nightly (default) | Weekly\.$" \
  && [ "$(git -C "$R" log -1 --format=%s)" = "board_edit: append Back up the share? (session \`abcdef12\`)" ] \
  && echo "$out" | grep -q "add line 9" \
  && ok "add decide: the writer's line and detail block, top of Needs, one commit under the append subject" \
  || bad "add decide rc=$rc: $out / $L / $(git -C "$R" log -1 --format=%s) / $chk"
for k in act look watch fyi; do
  extra=(); [ $k = fyi ] || extra=(--due "$FUT");   "$EDIT" add --board "$B" --kind $k --text "a $k item." "${extra[@]}" >/dev/null 2>&1 || bad "add $k refused"
done
chk=$(python3 - "$B" "$S" <<'EOF'
import sys
sys.path.insert(0, sys.argv[2])
import ledgerboard as lb
kinds = [lb.parse_board(ln, warn=False)[0].kind for ln in open(sys.argv[1]).read().splitlines() if lb.is_open_item(ln)]
assert all(lb.item_problem(ln) is None for ln in open(sys.argv[1]).read().splitlines() if lb.is_open_item(ln) and " a " in ln)
print(" ".join(k or "-" for k in kinds[:5]))
EOF
)
[ "$chk" = "fyi watch look act decide" ] && ok "add act, look, watch and fyi: each the writer's line, newest on top" || bad "add kinds: $chk"
"$EDIT" add --board "$B" --text "decided already." --decided "Go" --context TD-8 >/dev/null 2>&1 \
  && sed -n 9p "$B" | grep -q "Decided: Go (by Pat) ($TODAY)\.$" && ok "add --decided: by the board's one People: name" || bad "add --decided: $(sed -n 9p "$B")"
cp "$B" "$TMP/before"
"$EDIT" add --board "$B" --text "x." --line 3 >/dev/null 2>&1; r1=$?
"$EDIT" add --board "$B" --text "bad." --due "not-a-date" >/dev/null 2>&1; r2=$?
"$EDIT" fmt --board "$B" --tool x >/dev/null 2>&1; r3=$?
"$EDIT" list --board "$B" --no-commit >/dev/null 2>&1; r4=$?
[ "$r1$r3$r4" = 222 ] && [ $r2 = 1 ] && cmp -s "$B" "$TMP/before" \
  && ok "pass-through usage: an option the command does not take is exit 2, a line the writer refuses exit 1 (v2.4's table), board untouched" \
  || bad "usage: $r1 $r2 $r3 $r4"
chk=$(python3 - "$S" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import board_edit as E
from ledgerboard import board as LBB
mine = {o for a in LBB.parser()._actions for o in a.option_strings}
assert set(E.PASSTHROUGH) <= set(LBB.ACTIONS) and set(E.PASSTHROUGH) | set(LBB.EDITS) | {"rank"} == set(LBB.ACTIONS)
print("ok" if mine else "none")
EOF
)
[ "$chk" = ok ] && ok "the wrapper's commands are board.py's (its parser, so its flags)" || bad "flags: $chk"
"$EDIT" add --board "$B" --text "not committed." --due "$FUT" --no-commit >/dev/null 2>&1 \
  && [ -n "$(git -C "$R" status --porcelain)" ] && ok "add --no-commit writes the file only" || bad "add --no-commit"
git -C "$R" checkout -q -- docs

# --- 2) list and fmt
n=$("$EDIT" list --board "$B" --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["items"]))')
[ "$n" = 9 ] && ok "list --json: the open items" || bad "list --json: $n"
printf -- '- [ ] %s (n/a) — needs a period Due: %s\n- [ ] %s (session x on host) — an old head. Due: %s.\n' "$PAST" "$FUT" "$PAST" "$FUT" >> "$B"
git -C "$R" commit -qam "two old lines"
out=$("$EDIT" fmt --board "$B" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -q "kept as it is" && echo "$out" | grep -q "not committed" \
  && ok "fmt rewrites what keeps its key, lists what it keeps, commits nothing" || bad "fmt rc=$rc: $out"
git -C "$R" checkout -q -- docs

# --- 3) done below the threshold: a plain one-file close, class board-edit
R="$TMP/b"; mkrepo "$R" 8; B="$R/docs/user_attention.md"
"$EDIT" done --board "$B" --line 11 --expect "$PAST (n/a) — plain" --why handled >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && [ "$(git -C "$R" show --name-only --format= HEAD)" = docs/user_attention.md ] && [ "$(cls "$R")" = "board-edit pass" ] \
  && ok "done at nine closed: board only, class board-edit, the PR path passes" || bad "done at nine rc=$rc: $(cls "$R")"

# --- 4) done reaching ARCHIVE_AT: one commit of the board and the archive, class board-archive
git -C "$R" push -q origin main 2>/dev/null
"$EDIT" done --board "$B" --line 9 --expect "act $PAST (session abcdef12" --why "rotated" >/dev/null 2>&1; rc=$?
subj=$(git -C "$R" log -1 --format=%s)
files=$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')
A="$R/docs/user_attention_archive.md"
[ $rc = 0 ] && [ "$subj" = "board_edit: done rotate the key.; archived 10 (session abcdef12)" ] \
  && [ "$files" = "docs/user_attention.md docs/user_attention_archive.md " ] \
  && [ "$(grep -c '^- \[x\]' "$A")" = 10 ] && ! grep -q '^- \[x\]' "$B" && grep -q "^  - \*\*Context:\*\* the old key" "$A" \
  && ok "done on the tenth: archives in the same write, detail block moved, '; archived 10' before (session" \
  || bad "done at ten rc=$rc: $subj / $files"
[ "$(cls "$R")" = "board-archive pass" ] && ok "the threshold done is class board-archive, by the direct path and the PR path" || bad "class: $(cls "$R")"
chk=$(python3 - "$S" "$subj" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import ledgerboard as lb
print(lb.subject_kind(sys.argv[2]), lb.edit_action(sys.argv[2]))
EOF
)
[ "$chk" = "edit done" ] && ok "the subject still reads as an edit subject (EDIT_SUBJECT_RE)" || bad "subject kind: $chk"

# the same commit with anything else changed fails the class
git -C "$R" reset -q --soft HEAD^; echo "x" >> "$A"; git -C "$R" add -A
git -C "$R" commit -qm "$subj"
[ "$(cls "$R" | cut -d' ' -f1)" = fail ] && ok "a threshold done whose archive is altered fails the class" || bad "altered: $(cls "$R")"
git -C "$R" reset -q --soft HEAD^; git -C "$R" checkout -q HEAD -- docs 2>/dev/null; git -C "$R" clean -qfd docs
git -C "$R" reset -q --hard origin/main

# a wrong count in the subject fails; a hand move under a done subject below the threshold fails
"$EDIT" done --board "$B" --line 9 --expect "act $PAST" --why rotated --no-commit >/dev/null 2>&1
git -C "$R" add -A; git -C "$R" commit -qm "board_edit: done act $PAST (session abcdef12 on h) — rotate the key; archived 9 (session abcdef12)"
[ "$(cls "$R" | cut -d' ' -f1)" = fail ] && ok "a subject whose <n> differs from the count fails the class" || bad "count: $(cls "$R")"
git -C "$R" reset -q --hard origin/main

# --- 5) standalone archive: passes at the threshold, fails below it; the archive refusing leaves a plain done
R="$TMP/c"; mkrepo "$R" 10; B="$R/docs/user_attention.md"
out=$("$EDIT" archive --board "$B" 2>&1); rc=$?
[ $rc = 0 ] && [ "$(git -C "$R" log -1 --format=%s)" = "board_edit: archive 10 closed items (session n/a)" ] && [ "$(cls "$R")" = "board-archive pass" ] \
  && ok "archive at ten: one commit of two files, class board-archive" || bad "archive rc=$rc: $out / $(cls "$R")"
# a relative --archive from below the root names the same file for the write and for git
R="$TMP/c2"; mkrepo "$R" 10
(cd "$R/docs" && "$EDIT" archive --board user_attention.md --archive other.md >/dev/null 2>&1); rc=$?
[ $rc = 0 ] && [ "$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')" = "docs/other.md docs/user_attention.md " ] \
  && ok "archive --archive relative to the cwd, run from docs/: written and committed" || bad "relative --archive rc=$rc"
R="$TMP/d"; mkrepo "$R" 3; B="$R/docs/user_attention.md"
"$EDIT" archive --board "$B" >/dev/null 2>&1
[ "$(cls "$R")" = "fail none" ] && ok "archive below ARCHIVE_AT: fails the class, no carve-out" || bad "below: $(cls "$R")"
# a done whose Closed: is dated a day before the check still recomputes
R="$TMP/e"; mkrepo "$R" 9; B="$R/docs/user_attention.md"
PYTHONPATH="$S" python3 -m ledgerboard.board done --board "$B" --line 11 --expect "$PAST (n/a) — plain" --why ok --today "$YDAY" >/dev/null
PYTHONPATH="$S" python3 -m ledgerboard.board archive --board "$B" --archive "$R/docs/user_attention_archive.md" >/dev/null
git -C "$R" add -A; git -C "$R" commit -qm "board_edit: done $PAST (n/a) — plain item.; archived 10 (session n/a)"
[ "$(cls "$R" | cut -d' ' -f1)" = board-archive ] && ok "a done dated the day before still recomputes (date read back from Closed:)" || bad "yesterday: $(cls "$R")"
# archive_closed refusing: a blank line inside a closed item's detail block
R="$TMP/f"; mkrepo "$R" 9; B="$R/docs/user_attention.md"
printf -- '  - **Context:** first part.\n\n  - **More:** after a blank.\n' >> "$B"; git -C "$R" commit -qam broken
out=$("$EDIT" done --board "$B" --line 11 --expect "$PAST (n/a) — plain" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -q "warning" && [ "$(git -C "$R" show --name-only --format= HEAD)" = docs/user_attention.md ] \
  && ok "done when the archive refuses: a plain close, and a warning" || bad "refusing archive rc=$rc: $out"

# --- 6) a direct add with a detail block, and an fyi: fail (they land by PR)
R="$TMP/g"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --kind decide --text "q?" --due "$FUT" --answer a --answer b \
  --detail '{"context": "c.", "question": "q?", "recommended": "a — x."}' >/dev/null 2>&1
[ "$(cls "$R" | cut -d' ' -f1)" = fail ] && ok "classify_direct: a direct add with a detail block fails" || bad "detail add: $(cls "$R")"
"$EDIT" add --board "$B" --kind fyi --text "heads up." >/dev/null 2>&1
[ "$(cls "$R" | cut -d' ' -f1)" = fail ] && ok "classify_direct: a direct fyi add fails" || bad "fyi add: $(cls "$R")"
"$EDIT" add --board "$B" --text "a dated act." --due "$FUT" >/dev/null 2>&1
[ "$(cls "$R" | cut -d' ' -f1)" = board-append ] && ok "classify_direct: a direct dated one-line add is board-append, as before" || bad "append: $(cls "$R")"

# --- 6b) TD-237, cadence §4.4: a tool's append landed by a PR of its own passes the review row as board-append;
#         anything outside the direct audit's append rules, or a gate's answer, takes ordinary review
apr() {  # $1 = repo, $2 = PR title (default: the commit's subject): prints "<class> <row status|none> <carve_out|-> <lift row|none>"
  python3 - "$1" "${2:-}" "$S" <<'EOF2'
import sys
root, title, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s", sha], cwd=root).strip()
files = [f for f in C.git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd=root).split() if f]
cls_, _ = C.classify_direct(root, sha, subj, files)
pr = {"state": "open", "head_sha": sha, "title": title or subj, "files": files, "ref": "#9",
      "created_at": "2026-01-01T00:00:00Z"}
r = C.row_board_edit_pr(pr, root)
lift = C.row_lift_pr(pr, root)
print(cls_, r["status"] if r else "none", (r or {}).get("carve_out", "-"), lift["status"] if lift else "none")
EOF2
}
R="$TMP/ap1"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "Put on the board: renew the cert." --due "$FUT" --session abcdef12 >/dev/null 2>&1
[ "$(apr "$R")" = "board-append pass board-append none" ] && ok "append PR (a Put on the board line): review passes, carve_out board-append" || bad "append PR: $(apr "$R")"
R="$TMP/ap2"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "Back up nightly?" --answer Go --answer No --decided Go --by Pat --context TD-5 >/dev/null 2>&1
[ "$(apr "$R")" = "board-append pass board-append none" ] && ok "append PR (a decided line): review passes, carve_out board-append" || bad "decided append PR: $(apr "$R")"
R="$TMP/ap3"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "renew the cert." --due "$FUT" --no-commit >/dev/null 2>&1
echo x > "$R/other.txt"; git -C "$R" add -A; git -C "$R" commit -qm "board_edit: append renew the cert. (session n/a)"
[ "$(apr "$R" | cut -d' ' -f2)" = none ] && ok "append PR with a second file: ordinary review" || bad "two files: $(apr "$R")"
R="$TMP/ap4"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "renew the cert." --due "$FUT" --no-commit >/dev/null 2>&1
sed -i '/plain item/d' "$B"; git -C "$R" commit -qam "board_edit: append renew the cert. (session n/a)"
[ "$(apr "$R" | cut -d' ' -f2)" = none ] && ok "append PR that also removes a line: ordinary review" || bad "removed line: $(apr "$R")"
R="$TMP/ap5"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "renew the cert." --due "$FUT" --under "## Closed" >/dev/null 2>&1
[ "$(apr "$R" | cut -d' ' -f2)" = none ] && ok "append PR outside ## Needs…: ordinary review" || bad "outside Needs: $(apr "$R")"
R="$TMP/ap6"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "renew the cert." --due "$FUT" >/dev/null 2>&1
[ "$(apr "$R" "Add a board line by hand" | cut -d' ' -f1-2)" = "board-append none" ] && ok "a board append under a title that is not the append subject: ordinary review" || bad "title: $(apr "$R" "Add a board line by hand")"
R="$TMP/ap7"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "Go to the builds?" --answer Go --answer Hold --decided Go --by Pat --context "TD-5 decision (Pat)" >/dev/null 2>&1
[ "$(apr "$R")" = "board-append none - none" ] && ok "a decided append whose Context names a gate: neither carve-out passes it (ordinary review)" || bad "gate append: $(apr "$R")"
R="$TMP/ap8"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "first." --due "$FUT" >/dev/null 2>&1
"$EDIT" add --board "$B" --text "second." --due "$FUT" >/dev/null 2>&1
[ "$(apr "$R" | cut -d' ' -f2)" = none ] && ok "append PR of two commits: ordinary review (TD-224)" || bad "two commits: $(apr "$R")"

# --- 6c) TD-238: a board line starting with `--` or `++` is content inside a hunk, never a file header, so an
#         append beside its removal (or beside an added `++` line) is not an append, on either route
R="$TMP/ap9"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
sed -i 's/^## Needs the user$/---\n\n&/' "$B"; git -C "$R" commit -qam "a rule line"
"$EDIT" add --board "$B" --text "renew the cert." --due "$FUT" --no-commit >/dev/null 2>&1
sed -i '/^---$/d' "$B"; git -C "$R" commit -qam "board_edit: append renew the cert. (session n/a)"
[ "$(cls "$R")" = "fail none" ] && ok "TD-238: an append that also removes a --- line fails directly and takes ordinary review by PR" || bad "--- removed: $(cls "$R")"
R="$TMP/ap10"; mkrepo "$R" 0; B="$R/docs/user_attention.md"
"$EDIT" add --board "$B" --text "renew the cert." --due "$FUT" --no-commit >/dev/null 2>&1
printf '++ stray\n' >> "$B"; git -C "$R" commit -qam "board_edit: append renew the cert. (session n/a)"
[ "$(cls "$R")" = "fail none" ] && ok "TD-238: an append beside an added ++ line fails directly and takes ordinary review by PR" || bad "++ added: $(cls "$R")"

# --- 6d) TD-221, cadence §4.8: the end-of-rounds item is written with its gate and `Parts:` (ledgerboard v2.6's
#         add --parts, carried by the passthrough), and v2.6's covers() reads each held build's gate as covered
R="$TMP/parts"; rm -rf "$R"; mkdir -p "$R/docs"
cp -R "$DC/tests/ledgerboard/board_writer/add_parts/before/ledger" "$R/docs/ledger"
printf '# board\n\nPeople: robin\n\n## Needs the user\n\n- [ ] act %s (n/a) — tag it. Context: none. Due: %s.\n' "$PAST" "$FUT" > "$R/docs/user_attention.md"
git -C "$R" init -q -b main; git -C "$R" add -A; git -C "$R" commit -qm base
B="$R/docs/user_attention.md"
out=$("$EDIT" add --board "$B" --kind decide --text "Go on the report builds?" --context "TD-4 decision (robin)" \
  --due "$FUT" --answer Go --answer "Not yet" --parts TD-10,TD-9 \
  --detail '{"context": "its rounds ended.", "question": "Go on its builds?", "recommended": "Go."}' 2>&1); rc=$?
L=$(grep -F -- '- [ ] decide ' "$B")
[ $rc = 0 ] && grep -qF "Context: TD-4 decision (robin). Parts: TD-9, TD-10. Due: $FUT." <<< "$L" \
  && [ "$(git -C "$R" show --name-only --format= HEAD)" = docs/user_attention.md ] \
  && ok "add --parts: one commit, Parts: after the Context, in number order" || bad "add --parts rc=$rc: $out / $L"
res=$(python3 - "$S" "$R" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path
import ledgerboard as LB
r = Path(sys.argv[2]); board = (r / "docs/user_attention.md").read_text()   # a board is (origin url, repo name, text, archive)
print(" ".join(f"{t}:{[s for _, _, s in LB.covers((r / f'docs/ledger/{t}.md').read_text(), 'decision (robin)', [('', 'r', board, '')], 'r')]}"
               for t in ("TD-009", "TD-010")))
EOF
)
[ "$res" = "TD-009:['open'] TD-010:['open']" ] \
  && ok "covers(): the one end-of-rounds item covers each held build's decision gate" || bad "covers: $res"
out=$("$EDIT" add --board "$B" --kind decide --text "Go?" --context "TD-4" --due "$FUT" --answer Go --answer No \
  --parts TD-9 --detail '{"context": "c.", "question": "q?", "recommended": "Go."}' --no-commit 2>&1); rc=$?
[ $rc != 0 ] && grep -q refused <<< "$out" && ok "add --parts with no gate in the Context: refused" || bad "no gate rc=$rc: $out"
out=$("$EDIT" add --board "$B" --kind decide --text "Go?" --context "TD-4 decision (robin)" --due "$FUT" --answer Go --answer No \
  --parts TD-9,TD-99 --detail '{"context": "c.", "question": "q?", "recommended": "Go."}' --no-commit 2>&1); rc=$?
[ $rc != 0 ] && grep -q 'TD-99' <<< "$out" && ok "add --parts naming an entry the ledger beside the board lacks: refused, naming it" || bad "missing part rc=$rc: $out"

# --- 7) the nudge's item advice names a writer command on every line (design §4's general rule): a fixture board
#        with a twin, ARCHIVE_AT closed items, an oversized board, an escalated item, an unparseable Due: and an fyi
#        carrying a Due:, through the full report and the session-start text; stamp advice and the summary header (it names /attention) are exempt
NB="$TMP/n/docs/user_attention.md"; mkdir -p "$(dirname "$NB")"; OLDD=$(date -d "40 days ago" +%F)
{
  printf '# board\n\nPeople: Pat\n\nSwept: %s (h, deep)\nSwept-deep: %s\n\n## Needs the user\n\n' "$TODAY" "$TODAY"
  printf -- '- [ ] %s (n/a) — a twin. Context: TD-1. Due: %s.\n- [ ] %s (n/a) — a twin. Context: TD-1. Due: %s.\n' "$PAST" "$FUT" "$PAST" "$PAST"
  printf -- '- [ ] %s (n/a) — long overdue. Context: TD-2. Due: %s.\n' "$OLDD" "$OLDD"
  printf -- '- [ ] %s (n/a) — a typo date. Context: TD-3. Due: 2026-9-5.\n' "$PAST"
  printf -- '- [ ] fyi %s (n/a) — heads-up. Context: TD-4. Due: %s.\n' "$PAST" "$PAST"
  for i in $(seq 1 14); do printf -- '- [ ] %s (n/a) — filler %s. Context: TD-5. Due: %s.\n' "$PAST" "$i" "$PAST"; done
  for i in $(seq 1 10); do printf -- '- [x] %s (n/a) — closed %s. Context: TD-6. Due: %s. Closed: %s — done.\n' "$PAST" "$i" "$PAST" "$PAST"; done
} > "$NB"
full=$(python3 "$S/nudge_user_attention.py" --report --board "$NB" 2>&1)
due=$(python3 "$S/nudge_user_attention.py" --report --due-only --board "$NB" 2>&1)
miss=$(printf '%s\n%s\n' "$full" "$due" | grep '⚠' | grep -v 'Swept' | grep -v 'run /attention for the full report' | grep -v 'board_edit.py\|ledger.py')
conds=0
for want in "appear twice" "closed item(s) on the board" "open items on this board" "overdue 40d" "unparseable due date" "an fyi carries no Due:" "escalate-overdue-days"; do
  printf '%s\n%s\n' "$full" "$due" | grep -qF "$want" && conds=$((conds+1)) || echo "  (condition not triggered: $want)"
done
[ -z "$miss" ] && [ $conds -eq 7 ] && ok "the nudge's item advice names board_edit.py or ledger.py on every line, all seven conditions triggered" \
  || bad "advice without a command ($conds/7 conditions): $miss"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
