#!/usr/bin/env bash
# TD-248: `board_edit.py replay` settles a board conflict in a stopped rebase or merge by making the
# replayed side's item writes again on the other side's board (cadence.md §3.4's *take both sides*).
# Asserts: two branches that each add an item under one section, rebased, end with both items and a
# board the gate passes; an add, then a done of that item in a later commit, against an add on main;
# a merge (not a rebase) is settled the same way; a done that archives, against main's due on the item beside it, is replayed as its close and the
# archive runs again; a write that no longer applies (both sides closed one item) is refused by name,
# writing nothing; replay outside a rebase or merge is refused; an --archive outside the repo refuses with no
# traceback; a CRLF board stays CRLF; an archive twin refuses nothing; a section move and an add under a
# section the other side lacks refuse by name.
# Offline: throwaway git repos; HOME/XDG are temp dirs. Dates derive from the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDIT="$DC/files/scripts/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_EDITOR=true
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F); PAST=$(date -d "3 days ago" +%F); FUT=$(date -d "10 days" +%F)

mkrepo() {  # $1 repo dir, $2 how many closed items the board starts with
  rm -rf "$1"; git init -q -b main "$1"; mkdir -p "$1/docs"
  { printf '# board\n\nPeople: paul\n\n## Needs the user\n\n'
    printf -- '- [ ] %s (session `aaaa1111`) — the first item. Context: none. Due: %s.\n' "$PAST" "$FUT"
    printf -- '- [ ] %s (session `bbbb2222`) — the second item. Context: none. Due: %s.\n' "$PAST" "$FUT"
    for i in $(seq 1 "$2"); do printf -- '- [x] %s (n/a) — closed %s. Context: none. Due: %s. Closed: %s.\n' "$PAST" "$i" "$PAST" "$PAST"; done
    printf '\n## Later\n\n- [ ] %s (n/a) — a later item. Context: none. Due: %s.\n' "$PAST" "$FUT"; } > "$1/docs/user_attention.md"
  git -C "$1" add -A; git -C "$1" commit -qm base
}
be() { (cd "$R" && python3 "$EDIT" "$@" --board docs/user_attention.md); }
add() { be add --text "$1" --due "$FUT" --session "$2" >/dev/null 2>"$TMP/err" || echo "add failed: $(cat "$TMP/err")"; }
line_of() { grep -n -- "$1" "$R/docs/user_attention.md" | head -1 | cut -d: -f1; }
gate() {  # the board as the writers' gate reads it: no fault but notes
  python3 - "$R/docs/user_attention.md" "$DC/files/scripts" <<'EOF'
import sys; sys.path.insert(0, sys.argv[2]); import ledgerboard as LB
t = open(sys.argv[1]).read()
bad = [w for _, w in LB.board_problems(t) if not w.startswith("ℹ")]
print("; ".join(bad) or "clean")
EOF
}

# --- 1) two branches each add an item under the same section: the rebase stops, replay settles it.
R="$TMP/r1"; mkrepo "$R" 0
git -C "$R" switch -qc feat; add "the branch's item" feat0001
git -C "$R" switch -q main; add "main's item" main0001
git -C "$R" switch -q feat
git -C "$R" rebase -q main >/dev/null 2>&1 && bad "1: the rebase did not stop (no conflict to settle)"
out=$(be replay 2>&1); rc=$?
B="$R/docs/user_attention.md"
f=$(line_of "the branch's item"); m=$(line_of "main's item"); a=$(line_of "the first item")
[ $rc -eq 0 ] && [ -n "$f" ] && [ -n "$m" ] && [ "$f" -lt "$m" ] && [ "$m" -lt "$a" ] && ! grep -q '^<<<<<<<\|^>>>>>>>' "$B" \
  && grep -q "add: the branch's item" <<< "$out" && [ "$(gate)" = clean ] \
  && git -C "$R" rebase --continue >/dev/null 2>&1 && [ -z "$(git -C "$R" status --porcelain)" ] \
  && [ "$(git -C "$R" log --format=%s main..feat)" != "" ] \
  && ok "two adds under one section: replay keeps both, the replayed one on top as add puts it, and the rebase continues" \
  || bad "1 (rc=$rc): $out $(cat "$B")"
[ "$(sed -n "$f,$((a+1))p" "$B" | grep -c '^- \[ \]')" = 4 ] && [ "$(grep -c '^- \[ \]' "$B")" = 5 ] \
  && ok "nothing else on the board moved: five open items, no blank line inside the section" || bad "1 shape: $(cat "$B")"

# --- 2) an add, then a done of that item in a later commit, against an add on main.
R="$TMP/r2"; mkrepo "$R" 0
git -C "$R" switch -qc feat; add "added then closed" feat0002
be done --line "$(line_of 'added then closed')" --expect "$TODAY" --why "did it" >/dev/null 2>"$TMP/err" || echo "done failed: $(cat "$TMP/err")"
git -C "$R" switch -q main; add "main's other item" main0002
git -C "$R" switch -q feat
git -C "$R" rebase -q main >/dev/null 2>&1
n=0; out=""
while [ -n "$(git -C "$R" diff --name-only --diff-filter=U)" ] && [ $n -lt 3 ]; do
  out+=$(be replay 2>&1); out+=$'\n'; git -C "$R" rebase --continue >/dev/null 2>&1; n=$((n+1))
done
B="$R/docs/user_attention.md"
[ $n -ge 1 ] && [ ! -d "$R/.git/rebase-merge" ] && grep -q "^- \[x\] .*added then closed.*Closed: $TODAY — did it\." "$B" \
  && grep -q "^- \[ \] .*main's other item" "$B" && [ "$(gate)" = clean ] && [ -z "$(git -C "$R" status --porcelain)" ] \
  && ok "an add and a later done of the same item replay onto main's add, commit by commit ($n stop(s))" \
  || bad "2 (n=$n): $out $(cat "$B")"

# --- 3) a merge, not a rebase: MERGE_HEAD is the other side.
R="$TMP/r3"; mkrepo "$R" 0
git -C "$R" switch -qc feat; add "merge side item" feat0003
git -C "$R" switch -q main; add "main side item" main0003
git -C "$R" switch -q feat
git -C "$R" merge -q main >/dev/null 2>&1
out=$(be replay 2>&1); rc=$?
B="$R/docs/user_attention.md"
[ $rc -eq 0 ] && grep -q "merge side item" "$B" && grep -q "main side item" "$B" && [ "$(gate)" = clean ] \
  && grep -q "then git commit" <<< "$out" && git -C "$R" commit -q --no-edit 2>/dev/null \
  && ok "a stopped merge is settled the same way (HEAD replayed onto MERGE_HEAD)" || bad "3 (rc=$rc): $out $(cat "$B")"

# --- 4) a done that archives (ARCHIVE_AT): replayed as its close, the archive run again on the result.
R="$TMP/r4"; mkrepo "$R" 9
git -C "$R" switch -qc feat
be done --line "$(line_of 'the second item')" --expect "$PAST" --why "closed here" >/dev/null 2>"$TMP/err" || echo "done failed: $(cat "$TMP/err")"
A="$R/docs/user_attention_archive.md"
[ -f "$A" ] && [ "$(grep -c '^- \[x\]' "$A")" = 10 ] || echo "fixture: the done did not archive: $(cat "$TMP/err")"
git -C "$R" switch -q main
be due --line "$(line_of 'the first item')" --expect "$PAST" --to "$TODAY" >/dev/null 2>"$TMP/err" || echo "due failed: $(cat "$TMP/err")"
git -C "$R" switch -q feat
git -C "$R" rebase -q main >/dev/null 2>&1
out=$(be replay 2>&1); rc=$?
B="$R/docs/user_attention.md"
[ $rc -eq 0 ] && ! grep -q '^- \[x\]' "$B" && ! grep -q "the second item" "$B" && grep -q "the first item. Context: none. Due: $TODAY" "$B" \
  && [ "$(grep -c '^- \[x\]' "$A")" = 10 ] && grep -q "^- \[x\] .*the second item.*Closed: $TODAY — closed here\." "$A" \
  && grep -q "archive: run again" <<< "$out" && [ "$(gate)" = clean ] && git -C "$R" rebase --continue >/dev/null 2>&1 \
  && ok "a done that archived replays as its close, and the archive runs again (10 closed items moved)" \
  || bad "4 (rc=$rc): $out $(cat "$B") ARCH: $(cat "$A" 2>/dev/null)"

# --- 5) a write that no longer applies: both sides closed the same item. Refused by name; nothing written.
R="$TMP/r5"; mkrepo "$R" 0
git -C "$R" switch -qc feat
be done --line "$(line_of 'the first item')" --expect "$PAST" --why "here" >/dev/null 2>&1
git -C "$R" switch -q main
be done --line "$(line_of 'the first item')" --expect "$PAST" --why "there" >/dev/null 2>&1
git -C "$R" switch -q feat
git -C "$R" rebase -q main >/dev/null 2>&1
cp "$R/docs/user_attention.md" "$TMP/conflicted"
out=$(be replay 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "no longer applies — the other side changed the item too: the first item" <<< "$out" \
  && cmp -s "$R/docs/user_attention.md" "$TMP/conflicted" \
  && ok "both sides closed one item: refused by name, the conflicted file left as it was" || bad "5 (rc=$rc): $out"
git -C "$R" rebase --abort

# --- 6) replay with no rebase or merge stopped is refused.
out=$(be replay 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "no rebase or merge has stopped here" <<< "$out" \
  && ok "replay outside a stopped rebase or merge is refused" || bad "6 (rc=$rc): $out"

# --- 7) review cases: an --archive outside the repo, a CRLF board, an untouched twin in the archive, a
# move between sections, an add under a section the other side lacks.
R="$TMP/r7"; mkrepo "$R" 0
git -C "$R" switch -qc feat; add "seven" feat0007
git -C "$R" switch -q main; add "main seven" main0007
git -C "$R" switch -q feat; git -C "$R" rebase -q main >/dev/null 2>&1
out=$(be replay --archive "$TMP/elsewhere.md" 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "is outside the board's repo" <<< "$out" && ! grep -q Traceback <<< "$out" \
  && ok "an --archive outside the repo is refused, no traceback" || bad "7a (rc=$rc): $out"
git -C "$R" rebase --abort
R="$TMP/r8"; mkrepo "$R" 0
sed -i 's/$/\r/' "$R/docs/user_attention.md"; git -C "$R" commit -qam crlf
git -C "$R" switch -qc feat; add "crlf branch" feat0008
git -C "$R" switch -q main; add "crlf main" main0008
git -C "$R" switch -q feat; git -C "$R" rebase -q main >/dev/null 2>&1
out=$(be replay 2>&1); rc=$?
B="$R/docs/user_attention.md"
[ $rc -eq 0 ] && [ "$(grep -c $'\r$' "$B")" = "$(wc -l < "$B")" ] && grep -q "crlf branch" "$B" && grep -q "crlf main" "$B" \
  && ok "a CRLF board keeps CRLF on every line" || bad "7b (rc=$rc): $out $(grep -c $'\r$' "$B")/$(wc -l < "$B")"
git -C "$R" rebase --abort
R="$TMP/r9"; mkrepo "$R" 0
printf -- '- [ ] %s (n/a) — a twin. Context: none. Due: %s.\n- [x] %s (n/a) — a twin. Context: none. Due: %s. Closed: %s.\n' \
  "$PAST" "$PAST" "$PAST" "$PAST" "$PAST" > "$R/docs/user_attention_archive.md"; git -C "$R" add -A; git -C "$R" commit -qm twin
git -C "$R" switch -qc feat; add "beside a twin" feat0009
git -C "$R" switch -q main; add "main beside a twin" main0009
git -C "$R" switch -q feat; git -C "$R" rebase -q main >/dev/null 2>&1
out=$(be replay 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "beside a twin" "$R/docs/user_attention.md" \
  && ok "an open twin in the archive does not refuse a write to another item" || bad "7c (rc=$rc): $out"
git -C "$R" rebase --abort
R="$TMP/r10"; mkrepo "$R" 0
git -C "$R" switch -qc feat
python3 -c '
import sys; p = sys.argv[1]; t = open(p).read().split("\n")
i = next(k for k, ln in enumerate(t) if "the second item" in ln); ln = t.pop(i); t.append(ln)
open(p, "w").write("\n".join(t).rstrip("\n") + "\n")' "$R/docs/user_attention.md"
git -C "$R" commit -qam move
git -C "$R" switch -q main; be due --line "$(line_of 'the second item')" --expect "$PAST" --to "$TODAY" >/dev/null 2>&1
git -C "$R" switch -q feat; git -C "$R" rebase -q main >/dev/null 2>&1
out=$(be replay 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "moved an item to another section" <<< "$out" \
  && ok "an item moved between sections is refused, not dropped" || bad "7d (rc=$rc): $out"
git -C "$R" rebase --abort
R="$TMP/r11"; mkrepo "$R" 0
git -C "$R" switch -qc feat; be add --text "a later add" --due "$FUT" --session feat0011 --under "## Later" >/dev/null 2>&1
git -C "$R" switch -q main
python3 -c '
import sys; p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("## Later\n\n", "## Afterwards\n\n").replace("— a later item.", "— a later item, renamed."))' "$R/docs/user_attention.md"
git -C "$R" commit -qam "rename the section"
git -C "$R" switch -q feat; git -C "$R" rebase -q main >/dev/null 2>&1
out=$(be replay 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q "has no '## Later' section for the item: a later add" <<< "$out" \
  && ok "an add under a section the other side lacks is refused by name, not put in another" || bad "7e (rc=$rc): $out"
git -C "$R" rebase --abort 2>/dev/null

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
