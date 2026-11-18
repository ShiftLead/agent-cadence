#!/usr/bin/env bash
# TD-292: delegated answers (ledgerboard v3.4) as this repo takes them.
#   board_edit.py passes board.py's --scope (add) and --delegate (decide) through, refusals and all;
#   the person row (check_cadence.py row_person) fails an open PR that changes the board's Delegates: grants or
#   its People:, and never a Swept: stamp or a reorder;
#   no carve-out (classify_direct) admits an appended item with a Scope:, or an item that gains one;
#   the board row's rules (board_change_problems) refuse a delegated Decided: no grant covers.
# Offline: a throwaway git repo with a bare origin; HOME/XDG_CONFIG_HOME are temp dirs. Dates derive from the
# run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"; EDIT="$S/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset SHIFTLEAD_SESSION
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F); FUT=$(date -d "10 days" +%F)

R="$TMP/r"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"
D="$R/docs/user_attention"; B="$R/docs/user_attention.md"; mkdir -p "$D"
readme() {  # readme [Delegates: line]: the board's README.md, People: Pat
  { printf '# board\n\nLedgerboard: 3\nSwept: %s (testhost, quick)\n\nPeople: Pat\n' "${SWEPT:-$TODAY}"
    [ -n "${1:-}" ] && printf '%s\n' "$1"; } > "$D/README.md"
}
GRANT="Delegates: director for Pat (merge-line)"
readme "$GRANT"
printf '# board\n\nLedgerboard: 3\n\nThis board is the directory [user_attention/](user_attention/), one file per item (ledgerboard v3.0).\n' > "$B"
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null
DETAIL='{"context": "c", "question": "q", "recommended": "Merge — a session merges it"}'
add() {  # add [--scope NAME]: a decide item, committed by board_edit.py under its append message; prints its id
  "$EDIT" add --board "$B" --kind decide --text "Merge the change now?" --answer "Merge — a session merges it" \
    --answer "Hold — nobody merges it" --due "$FUT" --detail "$DETAIL" "$@" 2>/dev/null | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[0-9a-f]\{8\}' | head -1
}

# --- 1) board_edit.py: --scope on add, --delegate on decide, passed through to board.py
id=$(add --scope merge-line)
[ -n "$id" ] && grep -qx '\*\*Scope:\*\* merge-line' "$D/$id.md" && ok "1a add --scope writes the item's Scope:" || bad "1a add --scope: $id $(cat "$D/$id.md" 2>&1)"
git -C "$R" push -q origin main 2>/dev/null
"$EDIT" decide --board "$B" --id "$id" --answer Hold --by Pat --delegate other --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc = 1 ] && grep -q "no faultless Delegates: grant covers other for Pat (merge-line)" "$TMP/err" && git -C "$R" diff --quiet \
  && ok "1b decide --delegate with no grant covering it: refused, exit 1, nothing written" || bad "1b rc=$rc: $(cat "$TMP/err")"
"$EDIT" decide --board "$B" --id "$id" --answer Hold --by Pat --delegate director --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc = 0 ] && grep -qx "\*\*Decided:\*\* $TODAY by director for Pat (merge-line) — Hold" "$D/$id.md" \
  && ok "1c decide --delegate under a covering grant: the delegated Decided: form" || bad "1c rc=$rc: $(cat "$TMP/err") $(cat "$D/$id.md")"
git -C "$R" checkout -q -- docs
"$EDIT" done --board "$B" --id "$id" --delegate director --no-commit >/dev/null 2>&1; [ $? = 2 ] \
  && ok "1d --delegate on done is a usage error" || bad "1d --delegate accepted on done"
"$EDIT" add --help 2>&1 | grep -q -- "--delegate" && "$EDIT" add --help 2>&1 | grep -q -- "--scope" \
  && ok "1e the usage names --scope and --delegate" || bad "1e usage"

PY() {  # PY <python body>: check_cadence imported as C, root = $R
  python3 - "$R" "$S" "$1" <<'EOF'
import sys
root, s, body = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
exec(body)
EOF
}
person() {  # person <open|merged> [noroot]: the person row on HEAD against origin/main
  PY "
sha = C.git(['rev-parse', 'HEAD'], cwd=root).strip()
base = C.git(['rev-parse', 'origin/main'], cwd=root).strip()
rng = f'{sha}^..{sha}' if '$1' == 'merged' else f'{base}..{sha}'
files = sorted(set(C.git(['diff', '--name-only', rng], cwd=root).split()))
pr = {'state': '$1', 'head_sha': sha, 'merge_sha': sha, 'files': files}
r = C.row_person(pr, None if '${2:-}' == 'noroot' else root)
print(r['status'], r['detail'])"
}
topic() { git -C "$R" switch -q -C topic origin/main; }
commit() { git -C "$R" add -A; git -C "$R" commit -qm "${1:-change}"; }

# --- 2) the person row: the board's grants and People: are the person's
topic; readme "Delegates: director for Pat (merge-line, other-line)"; commit
st=$(person open); [ "${st%% *}" = fail ] && grep -q "Delegates: grants" <<< "$st" \
  && ok "2a a PR widening a Delegates: grant: the person row fails" || bad "2a: $st"
topic; readme; commit
st=$(person open); [ "${st%% *}" = fail ] && grep -q "Delegates: grants" <<< "$st" \
  && ok "2b a PR removing the Delegates: line: fails" || bad "2b: $st"
topic; readme "Delegates: DIRECTOR  for  pat (merge-line)"; commit
st=$(person open); [ "${st%% *}" = na ] && ok "2c a grant rewritten in case and whitespace alone: na" || bad "2c: $st"
topic; SWEPT=$(date -d "1 day ago" +%F) readme "$GRANT"; commit
st=$(person open); [ "${st%% *}" = na ] && ok "2d a Swept: stamp change alone: na" || bad "2d: $st"
topic; readme "$GRANT"; sed -i 's/^People: Pat$/People: Pat, Sam/' "$D/README.md"; commit
st=$(person open); [ "${st%% *}" = fail ] && grep -q "People:" <<< "$st" \
  && ok "2e a PR changing People:: the person row fails" || bad "2e: $st"
st=$(person open noroot); [ "${st%% *}" = unknown ] && ok "2f no clone to read the preamble's change from: unknown" || bad "2f: $st"
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic >/dev/null 2>&1; git -C "$R" commit -qm "people (#2)"
st=$(person merged); [ "${st%% *}" = pass ] && grep -q "⚠" <<< "$st" && ok "2g merged: a ⚠, never a fail" || bad "2g: $st"
git -C "$R" reset -q --hard origin/main
topic; add >/dev/null
st=$(person open); [ "${st%% *}" = na ] && ok "2h a PR adding an item alone: na" || bad "2h: $st"

classify() {  # classify: classify_direct of HEAD
  PY "
sha = C.git(['rev-parse', 'HEAD'], cwd=root).strip()
subject = C.git(['log', '-1', '--format=%s', sha], cwd=root).strip()
files = sorted(set(C.git(['diff', '--name-only', f'{sha}^', sha], cwd=root).split()))
print(*C.classify_direct(root, sha, subject, files))"
}
# --- 3) the carve-outs: an item with a Scope: lands by a reviewed PR
topic; "$EDIT" add --board "$B" --text "A plain item." --due "$FUT" >/dev/null 2>&1
st=$(classify); [ "${st%% *}" = board-append ] && ok "3a an unscoped append (Due:, no detail block): still board-append" || bad "3a: $st"
# a scoped decide with a Due: and no detail block, the one shape the append carve-out could otherwise take
topic; sid="$TODAY-0000abcd"
printf '## Merge the change now?\n\n**Kind:** decide\n**Added:** %s\n**Context:** none\n**Scope:** merge-line\n**Due:** %s\n**Answers:** Merge — a session merges it | Hold — nobody merges it\n' "$TODAY" "$FUT" > "$D/$sid.md"
git -C "$R" add -A; git -C "$R" commit -qm "board_edit: append $sid Merge the change now? (session n/a)"
st=$(classify); [ "${st%% *}" = fail ] && grep -q "appended item with a Scope:" <<< "$st" \
  && ok "3b an appended item with a Scope:: no carve-out" || bad "3b: $st"
topic; git -C "$R" switch -q main; git -C "$R" reset -q --hard origin/main
pid=$(add); git -C "$R" push -q origin main 2>/dev/null
sed -i "s/^\*\*Context:\*\* none$/**Context:** none\n**Scope:** merge-line/" "$D/$pid.md"
git -C "$R" add -A; git -C "$R" commit -qm "board_edit: due $pid Merge the change now? to $FUT (session n/a)"
st=$(classify); [ "${st%% *}" = fail ] && grep -q "gains a Scope:" <<< "$st" \
  && ok "3c a one-item edit that gives the item a Scope:: no carve-out" || bad "3c: $st"
git -C "$R" reset -q --hard origin/main

# --- 4) the board row's rules: a delegated Decided: stands only under a grant that covers it
board() {  # board: board_change_problems from origin/main to HEAD, the fails
  PY "
base_t = C._board_tree(root, 'origin/main'); head_t = C._board_tree(root, 'HEAD')
print('; '.join(m for st, m in C.board_change_problems(C.board_of(base_t), C.board_of(head_t)) if st == 'fail') or 'ok')"
}
topic; "$EDIT" decide --board "$B" --id "$id" --answer Hold --by Pat --delegate director >/dev/null 2>&1
st=$(board); [ "$st" = ok ] && ok "4a a delegated answer under a covering grant: no fail" || bad "4a: $st"
st=$(classify); [ "${st%% *}" = board-edit ] && ok "4b ... and its one-item edit is the board-edit carve-out's" || bad "4b: $st"
topic; "$EDIT" decide --board "$B" --id "$id" --answer Hold --by Pat --no-commit >/dev/null 2>&1
sed -i "s/^\*\*Decided:\*\* $TODAY by Pat — Hold$/**Decided:** $TODAY by intruder for Pat (merge-line) — Hold/" "$D/$id.md"
grep -q "by intruder for Pat" "$D/$id.md" || bad "4c fixture: $(cat "$D/$id.md")"
git -C "$R" add -A; git -C "$R" commit -qm "board_edit: decide $id Merge the change now?: Hold (session n/a)"
st=$(board); grep -q "delegated Decided: by intruder for Pat does not stand" <<< "$st" \
  && ok "4c a delegated answer no grant covers: the board row's rules fail it" || bad "4c: $st"
st=$(classify); [ "${st%% *}" = fail ] && ok "4d ... and no carve-out admits it" || bad "4d: $st"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
