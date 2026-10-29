#!/usr/bin/env bash
# TD-160: ledger.py on a v2 ledger — a directory of one TD-NNN.md per entry (docs/ledger/), read
# through ledgerboard's load(). Asserts: --split migrates a v1 ledger (README, entries, archive/,
# the rank file moved, the v1 files removed) and refuses with nothing written; every view reads the
# same before and after; --summary generates the table; the default ledger is docs/ledger/ when it
# exists; a v2 ledger v2_problems() faults is not read; --check --since reads the ref in whichever
# layout it had; a cross-repo blocker resolves into a v2 repo at its origin/main; ledger_next_id.py
# reads ids from a v2 ref's file names; check_cadence's ledger row checks a v2 edit.
# Offline, fixture-driven: temp repos, HOME/XDG and the roster in a temp dir.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/roster"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$DEV_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)
lp() { (cd "$1" && shift && python3 "$LEDGER_PY" "$@"); }

mkv1() {  # mkv1 DIR — a repo with a v1 ledger, archive and rank file, committed
  mkdir -p "$1/docs"; git -C "$1" init -q -b main
  cat > "$1/docs/technical_debt.md" <<EOF2
# Technical Debt — fixture

Opening prose.

---

## Summary

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| TD-003 | medium | Medium | Open |
| TD-004 | blocked on TD-003 | High | Open |
| TD-010 | blocked on an archived one | Low | Open |

## TD-003: medium

**Priority:** Medium
**Added:** $TODAY
**Status:** Open

## TD-004: blocked on TD-003

**Priority:** High
**Status:** Open
**Blocked by:** TD-003

## TD-010: blocked on an archived one

**Priority:** Low
**Status:** Open
**Blocked by:** TD-1
EOF2
  cat > "$1/docs/technical_debt_archive.md" <<EOF2
# Archive

## TD-1: gone

**Resolved:** $TODAY
EOF2
  printf 'TD-010: 0a\n' > "$1/docs/technical_debt_rank.yml"
  git -C "$1" add -A && git -C "$1" commit -qm v1
}

R="$TMP/r"; mkv1 "$R"
before=$(lp "$R" --list --json); before_p=$(lp "$R" --pickable)
out=$(lp "$R" --split 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$R/docs/ledger/README.md" ] && [ -f "$R/docs/ledger/TD-003.md" ] && [ -f "$R/docs/ledger/archive/TD-1.md" ] \
  && [ ! -e "$R/docs/technical_debt.md" ] && [ ! -e "$R/docs/technical_debt_archive.md" ] \
  && [ "$(cat "$R/docs/ledger/rank.yml")" = "TD-010: 0a" ] && [ ! -e "$R/docs/technical_debt_rank.yml" ] \
  && grep -q "3 open, 1 archived, the rank file moved in" <<<"$out" \
  && ok "--split writes docs/ledger/, moves the rank file in, removes the v1 files" || bad "split rc=$rc '$out' $(ls -R "$R/docs")"
grep -qx "Ledgerboard: 2" "$R/docs/ledger/README.md" && ! grep -q "^|" "$R/docs/ledger/README.md" \
  && ok "the README declares Ledgerboard: 2 and holds no table" || bad "README: $(cat "$R/docs/ledger/README.md")"
[ "$(head -1 "$R/docs/ledger/TD-004.md")" = "## TD-004: blocked on TD-003" ] && ok "an entry's file opens with its heading" \
  || bad "TD-004.md: $(cat "$R/docs/ledger/TD-004.md")"
[ "$before" = "$(lp "$R" --list --json)" ] && [ "$before_p" = "$(lp "$R" --pickable)" ] \
  && ok "the default reads docs/ledger/: --list and --pickable are the same before and after (rank file included)" \
  || bad "views differ: $(lp "$R" --pickable)"
sum=$(lp "$R" --summary)
[ "$(sed -n 3p <<<"$sum")" = "| TD-010 | blocked on an archived one | Low | debt | pickable |" ] \
  && grep -qx "| TD-004 | blocked on TD-003 | High | debt | blocked by TD-003 |" <<<"$sum" \
  && ok "--summary: the table generated, in pick order (the ranked entry first), state derived" || bad "summary: $sum"
git -C "$R" add -A && git -C "$R" commit -qm v2

out=$(lp "$R" --split 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "is a v2 directory already" <<<"$out" && ok "--split on a v2 ledger is refused" || bad "re-split rc=$rc '$out'"
out=$(lp "$R" --pickable --archive x.md 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q -- "--archive applies to a v1 ledger" <<<"$out" && ok "--archive with a v2 ledger is a usage error" || bad "archive rc=$rc '$out'"

# --check --since reads the ref in the layout it had: v1 at HEAD~1, v2 at HEAD
out=$(lp "$R" --check --since HEAD~1 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "ledger check: 0 error(s)" <<<"$out" && ok "--check --since a v1 ref: the split changed no entry" || bad "since v1 rc=$rc '$out'"
sed -i 's/^\*\*Priority:\*\* Medium$/**Priority:** Medium\n**Type:** chore/' "$R/docs/ledger/TD-003.md"
out=$(lp "$R" --check --since HEAD 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "TD-003" <<<"$out" && ok "--check --since a v2 ref: an edited entry's bad Type is an error" || bad "since v2 rc=$rc '$out'"
git -C "$R" checkout -q -- docs

# across the split itself: a bad field standing since v1 stays standing, not "new" (the ref read v1)
Q="$TMP/q"; mkv1 "$Q"
sed -i 's/^\*\*Priority:\*\* Low$/**Priority:** Low\n**Type:** chore/' "$Q/docs/technical_debt.md"; git -C "$Q" commit -qam "a bad Type, standing"
lp "$Q" --split >/dev/null; git -C "$Q" add -A; git -C "$Q" commit -qm split
out=$(lp "$Q" --check --since HEAD~1 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qE "0 error\(s\); [0-9]+ standing flag" <<<"$out" \
  && ok "--check --since the commit before a split: v1 at the ref, a standing flag stays standing" || bad "since across split rc=$rc '$out'"
git -C "$Q" revert --no-edit HEAD >/dev/null   # back to v1 in the working tree; HEAD~1 is the v2 directory
out=$(lp "$Q" --check --since HEAD~1 2>&1); rc=$?
[ -f "$Q/docs/technical_debt.md" ] && [ ! -e "$Q/docs/ledger" ] && [ "$rc" = 0 ] && grep -qE "0 error\(s\); [0-9]+ standing flag" <<<"$out" \
  && ok "--check --since a v2 ref from a v1 working tree reads the ref's directory" || bad "since v2 from v1 rc=$rc '$out'"

# a custom --ledger name keeps v1's default archive: technical_debt_archive.md beside it
C="$TMP/c"; mkv1 "$C"; mv "$C/docs/technical_debt.md" "$C/docs/other.md"
out=$(python3 "$LEDGER_PY" --pickable --ledger "$C/docs/other.md" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "^  TD-010 " <<<"$out" && grep -q "every blocker is archived (TD-1)" <<<"$out" && ok "--ledger with another name reads technical_debt_archive.md beside it" \
  || bad "custom ledger rc=$rc '$out'"

# a hand edit v2_problems() faults: not read, the file named
printf '## TD-012: misfiled\n\n**Priority:** Low\n' > "$R/docs/ledger/TD-011.md"
out=$(lp "$R" --pickable 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "not read — .*TD-011.md: must open with its one \`## TD-11:\` heading (found TD-012)" <<<"$out" \
  && ok "a v2 ledger v2_problems() faults is not read, and says which file" || bad "v2_problems rc=$rc '$out'"
rm "$R/docs/ledger/TD-011.md"

# refusals write nothing: an existing docs/ledger/, and a v1 ledger split() refuses
S="$TMP/s"; mkv1 "$S"; mkdir "$S/docs/ledger"
out=$(lp "$S" --split --ledger "$S/docs/technical_debt.md" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "exists — nothing was split" <<<"$out" && [ -f "$S/docs/technical_debt.md" ] && [ -z "$(ls "$S/docs/ledger")" ] \
  && ok "--split refuses when docs/ledger/ exists" || bad "exists rc=$rc '$out'"
rmdir "$S/docs/ledger"; printf '\n## Notes\n\nnot an entry\n' >> "$S/docs/technical_debt_archive.md"
out=$(lp "$S" --split 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "'## Notes' in the archive is not an entry" <<<"$out" && [ ! -e "$S/docs/ledger" ] \
  && [ -f "$S/docs/technical_debt.md" ] && [ -f "$S/docs/technical_debt_rank.yml" ] \
  && ok "a split ledgerboard's split() refuses writes nothing and removes nothing" || bad "refused rc=$rc '$out'"

# TD-176: --split rewrites each relative link it moves to resolve from the entry's new place — once for
# an open entry and the README, twice under archive/, a title kept — and leaves a code span, a dead link, a URL alone;
# a link into the v1 files it removes is pointed at the entry's file when its anchor is an entry's (TD-185)
L="$TMP/links"; mkv1 "$L"; mkdir -p "$L/docs/plans" "$L/files"; : > "$L/docs/plans/p.md"; : > "$L/files/x.py"
python3 - "$L/docs" <<'PY'
import sys
d = sys.argv[1]
t = open(f"{d}/technical_debt.md").read()
t = t.replace("Opening prose.", "Opening prose, [the plan](plans/p.md).")
t = t.replace("## TD-003: medium\n\n**Priority:** Medium\n**Added:**",
              "## TD-003: medium\n\n**Priority:** Medium\n**Location:** [plan](plans/p.md#s), [code](../files/x.py \"the code\"), `[q](plans/p.md)`, "
              "[dead](plans/nope.md), [web](https://x/y), [old](technical_debt_archive.md#td-1)\n**Added:**")
open(f"{d}/technical_debt.md", "w").write(t)
a = open(f"{d}/technical_debt_archive.md").read().replace("**Resolved:**", "**Location:** [plan](plans/p.md)\n**Resolved:**")
open(f"{d}/technical_debt_archive.md", "w").write(a)
PY
git -C "$L" add -A && git -C "$L" commit -qm links
out=$(lp "$L" --split 2>&1); rc=$?
loc=$(grep '^\*\*Location:' "$L/docs/ledger/TD-003.md")
[ "$rc" = 0 ] && [ "$loc" = '**Location:** [plan](../plans/p.md#s), [code](../../files/x.py "the code"), `[q](plans/p.md)`, [dead](plans/nope.md), [web](https://x/y), [old](archive/TD-1.md)' ] \
  && grep -qxF '**Location:** [plan](../../plans/p.md)' "$L/docs/ledger/archive/TD-1.md" && grep -qF '[the plan](../plans/p.md)' "$L/docs/ledger/README.md" \
  && grep -q "relative links rewritten in 3 file(s)" <<<"$out" && ! grep -q "the v1 file this split removes" <<<"$out" \
  && ok "--split rewrites moved links (../ open, ../../ archived), leaves a code span, a dead link and a URL, points an entry anchor into the removed v1 files at its file" \
  || bad "split links rc=$rc '$out' loc=$loc / $(cat "$L/docs/ledger/archive/TD-1.md") / $(head -5 "$L/docs/ledger/README.md")"
# TD-185: an entry-heading anchor into the v1 files (a bare #td-… in the ledger, a path#td-… from anywhere) is pointed
# at the entry's file; a v1 file with no anchor at its directory; any other anchor into them warned; a directory
# link keeps its trailing slash; the archive's ## Summary is kept, frozen, as archive/summary-at-split.md; the
# repo's other tracked Markdown has its links into the v1 files repointed (and nothing else) and is named
A="$TMP/anchors"; mkv1 "$A"; mkdir -p "$A/docs/plans"; : > "$A/docs/plans/p.md"
python3 - "$A/docs" <<'PY'
import sys
d = sys.argv[1]
t = open(f"{d}/technical_debt.md").read()
t = t.replace("**Blocked by:** TD-003\n", "**Blocked by:** TD-003\n**Related:** [self](#td-003-medium), [gone](technical_debt_archive.md#td-1-gone), "
              "[sum](#summary), [arch](technical_debt_archive.md), [dir](plans/)\n")
open(f"{d}/technical_debt.md", "w").write(t)
a = open(f"{d}/technical_debt_archive.md").read().replace(
    "# Archive\n", "# Archive\n\nArchive prose.\n\n## Summary\n\n| ID | Title | Promoted to |\n|----|-------|----|\n| [TD-1](#td-1-gone) | gone | `x.py` |\n\n")
open(f"{d}/technical_debt_archive.md", "w").write(a)
open(f"{d}/other.md", "w").write("[e](technical_debt.md#td-004-blocked-on-td-003) [a](technical_debt_archive.md#td-1-gone) "
                                 "[l](technical_debt.md) [s](technical_debt.md#summary) [p](./plans/p.md) [h](#td-4-x)\n")
PY
git -C "$A" add -A && git -C "$A" commit -qm anchors
out=$(lp "$A" --split 2>&1); rc=$?
rel=$(grep '^\*\*Related:' "$A/docs/ledger/TD-004.md"); oth=$(cat "$A/docs/other.md"); fz="$A/docs/ledger/archive/summary-at-split.md"
[ "$rc" = 0 ] && [ "$rel" = '**Related:** [self](TD-003.md), [gone](archive/TD-1.md), [sum](#summary), [arch](archive/), [dir](../plans/)' ] \
  && [ "$oth" = '[e](ledger/TD-004.md) [a](ledger/archive/TD-1.md) [l](ledger/) [s](technical_debt.md#summary) [p](./plans/p.md) [h](#td-4-x)' ] \
  && grep -qxF '| [TD-1](TD-1.md) | gone | `x.py` |' "$fz" && grep -q "^# technical_debt_archive.md's summary, frozen at the split" "$fz" \
  && grep -q "the archive's summary kept as archive/summary-at-split.md" <<<"$out" && grep -q "docs/other.md: technical_debt.md#summary: the v1 file this split removes" <<<"$out" \
  && grep -q "repointed in 1 other file(s): docs/other.md" <<<"$out" && [ ! -e "$A/docs/technical_debt_archive.md" ] \
  && (cd "$A" && python3 "$LEDGER_PY" --check 2>&1 | grep -q "ledger check: 0 error(s)") \
  && ok "--split points entry anchors at entry files, keeps the archive's summary frozen, repoints other docs' links into the v1 files" \
  || bad "anchors rc=$rc '$out' rel=$rel oth=$oth / $(cat "$fz" 2>&1)"
# TD-185 review: the other files are read before anything is written — an unreadable one is skipped and named,
# the split completes; a CRLF file keeps its line endings; a link in a fenced block is left; a reference
# definition into the v1 files is warned, not rewritten; a symlinked .md is not followed
B="$TMP/anchors2"; mkv1 "$B"; mkdir -p "$B/sub"
printf '\xff\xfe [x](../docs/technical_debt.md#td-003-medium)\n' > "$B/sub/bad.md"
printf '[a](../docs/technical_debt.md#td-003-medium)\r\nline\r\n' > "$B/sub/crlf.md"
printf '````md\n```bash\n[f](../docs/technical_debt.md#td-003-medium)\n```\n````\n```\nx\n```python\n[g](../docs/technical_debt.md#td-003-medium)\n```\n[r]: ../docs/technical_debt.md#td-003-medium\n<a href="../docs/technical_debt.md#td-003-medium">h</a>\n' > "$B/sub/fence.md"
ln -s ../sub/crlf.md "$B/docs/link.md"
git -C "$B" add -A && git -C "$B" commit -qm others
out=$(lp "$B" --split 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$B/docs/ledger/TD-003.md" ] && [ ! -e "$B/docs/technical_debt.md" ] \
  && grep -q "sub/bad.md: not read (UnicodeDecodeError)" <<<"$out" \
  && printf '[a](../docs/ledger/TD-003.md)\r\nline\r\n' | cmp -s - "$B/sub/crlf.md" \
  && grep -qxF '[f](../docs/technical_debt.md#td-003-medium)' "$B/sub/fence.md" && grep -qxF '[g](../docs/technical_debt.md#td-003-medium)' "$B/sub/fence.md" \
  && [ "$(grep -c 'sub/fence.md: ../docs/technical_debt.md#td-003-medium: a reference or HTML link' <<<"$out")" = 2 ] \
  && grep -qxF '[r]: ../docs/technical_debt.md#td-003-medium' "$B/sub/fence.md" && grep -q "sub/fence.md: ../docs/technical_debt.md#td-003-medium: a reference or HTML link" <<<"$out" \
  && ! grep -q "docs/link.md" <<<"$out" \
  && ok "--split reads the other files first (an unreadable one skipped), keeps CRLF, leaves fenced links, warns on a reference definition, skips a symlink" \
  || bad "others rc=$rc '$out' crlf=$(od -An -c "$B/sub/crlf.md" | head -2) fence=$(cat "$B/sub/fence.md")"
# a read-only file among the others is skipped and named before anything is written
if [ "$(id -u)" != 0 ]; then
  C="$TMP/anchors3"; mkv1 "$C"; printf '[a](docs/technical_debt.md#td-003-medium)\n' > "$C/ro.md"; git -C "$C" add -A && git -C "$C" commit -qm ro
  chmod a-w "$C/ro.md"; out=$(lp "$C" --split 2>&1); rc=$?; chmod u+w "$C/ro.md"
  [ "$rc" = 0 ] && [ -f "$C/docs/ledger/TD-003.md" ] && grep -q "ro.md: not writable" <<<"$out" && grep -qxF '[a](docs/technical_debt.md#td-003-medium)' "$C/ro.md" \
    && ok "--split skips and names a read-only file before writing anything" || bad "ro rc=$rc '$out'"
fi
# a cross-repo blocker into a v2 repo, read at its origin/main (not its working tree)
O="$TMP/other"; mkv1 "$O"; lp "$O" --split >/dev/null; git -C "$O" add -A; git -C "$O" commit -qm v2
git init -q --bare -b main "$TMP/other.git"; git -C "$O" remote add origin "$TMP/other.git"
git -C "$O" push -q origin main; git -C "$O" fetch -q origin
git -C "$O" mv docs/ledger/TD-003.md docs/ledger/archive/TD-003.md   # archived locally, not pushed: origin wins
printf '%s\n' "$O" > "$DEV_CADENCE_REG_DIR/repos.txt"
XL="$TMP/xl.md"
printf '## TD-101: on an archived one there\n\n**Priority:** High\n**Blocked by:** other#TD-1\n\n## TD-102: on an open one there\n\n**Priority:** High\n**Blocked by:** other#TD-003\n' > "$XL"
out=$(python3 "$LEDGER_PY" --pickable --ledger "$XL" --archive "$TMP/none.md" --json)
python3 -c "
import json,sys; d=json.loads(sys.argv[1])
assert [r['id'] for r in d['pickable']] == ['TD-101'], d['pickable']
assert [r['id'] for r in d['blocked']] == ['TD-102'], d['blocked']
" "$out" && ok "a cross-repo blocker resolves into a v2 repo at origin/main" || bad "xrepo: $out"

# the other readers (step 3, slice 2): ledger_next_id.py's ids and the cadence check's ledger row
NEXT="$DC/files/scripts/ledger_next_id.py"
I="$TMP/ids"; mkv1 "$I"; lp "$I" --split >/dev/null
printf '## TD-050: the highest open\n\n**Priority:** Low\n' > "$I/docs/ledger/TD-050.md"
git -C "$I" add -A && git -C "$I" commit -qm v2
git init -q --bare -b main "$TMP/ids.git"; git -C "$I" remote add origin "$TMP/ids.git"
git -C "$I" push -q origin main; git -C "$I" fetch -q origin
out=$(cd "$I" && python3 "$NEXT" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-051 ] && ok "ledger_next_id.py on a v2 main: one above its highest entry file, by default" \
  || bad "next id v2 rc=$rc '$out' $(cat "$TMP/err")"
git -C "$I" checkout -q -b misfiled
printf '## TD-070: misfiled\n\n**Priority:** Low\n' > "$I/docs/ledger/TD-060.md"
printf '## TD-080: misfiled\n\n**Resolved:** %s\n' "$TODAY" > "$I/docs/ledger/archive/TD-075.md"
git -C "$I" add -A && git -C "$I" commit -qm misfiled
ids() { (cd "$DC/files/scripts" && python3 -c "
import sys; from pathlib import Path; import ledger_next_id as X
print(sorted(X.ids_at(Path(sys.argv[1]), sys.argv[2], *sys.argv[3:])))" "$@"); }
[ "$(ids "$I" HEAD docs/technical_debt.md docs/technical_debt_archive.md)" = "[1, 3, 4, 10, 50, 60, 70, 75, 80]" ] \
  && [ "$(ids "$I" HEAD docs/ledger docs/unused.md)" = "[1, 3, 4, 10, 50, 60, 70, 75, 80]" ] \
  && [ "$(ids "$I" HEAD~2 docs/ledger docs/unused.md)" = "[1, 3, 4, 10]" ] \
  && ok "ids_at: a v2 ref's file names and headings (archive/ too); either --ledger default reads either layout" \
  || bad "ids_at: $(ids "$I" HEAD docs/technical_debt.md docs/technical_debt_archive.md) / $(ids "$I" HEAD~2 docs/ledger docs/unused.md)"

A="$TMP/apart"; mkdir -p "$A/docs" "$A/arch"; git -C "$A" init -q -b main
printf '## TD-005: open\n' > "$A/docs/led.md"; printf '## TD-009: archived\n' > "$A/arch/old.md"
git -C "$A" add -A && git -C "$A" commit -qm apart
[ "$(ids "$A" HEAD docs/led.md arch/old.md)" = "[5, 9]" ] \
  && ok "ids_at: an archive in another directory than its ledger is read" || bad "apart: $(ids "$A" HEAD docs/led.md arch/old.md)"

cc() { (cd "$DC/files/scripts" && python3 -c "
import json, sys; import check_cadence as K
pr = json.loads(sys.argv[2]); print(json.dumps(K.ledger_edit_check(pr, sys.argv[1])))" "$@"); }
head=$(git -C "$I" rev-parse HEAD)
out=$(cc "$I" "{\"state\": \"open\", \"head_sha\": \"$head\", \"files\": [\"docs/ledger/TD-060.md\"]}")
grep -q "not read: .*TD-060.md: must open with its one" <<<"$out" \
  && ok "check_cadence's ledger row: a v2 head v2_problems() faults is an error, the file named" || bad "row v2_problems: $out"
git -C "$I" checkout -q main
sed -i 's/^\*\*Priority:\*\* Medium$/**Priority:** Medium\n**Type:** chore/' "$I/docs/ledger/TD-003.md"
git -C "$I" checkout -q -b badtype && git -C "$I" commit -qam "a bad Type"
head=$(git -C "$I" rev-parse HEAD)
out=$(cc "$I" "{\"state\": \"open\", \"head_sha\": \"$head\", \"files\": [\"docs/ledger/TD-003.md\"]}")
python3 -c "
import json, sys; errs, note = json.loads(sys.argv[1])
assert len(errs) == 1 and 'TD-003' in errs[0] and note == 'ledger fields checked', (errs, note)" "$out" \
  && ok "check_cadence's ledger row: an edited v2 entry is field-checked against its merge-base" || bad "row v2 edit: $out"
out=$(cc "$I" "{\"state\": \"open\", \"head_sha\": \"$head\", \"files\": [\"docs/ledger/rank.yml\"]}")
[ "$out" = '[[], ""]' ] && ok "check_cadence's ledger row: a v2 rank-file-only PR is not a ledger edit" || bad "row rank: $out"
out=$(cd "$DC/files/scripts" && python3 -c "
import check_cadence as K
print(K.ledger_touched(['docs/ledger/README.md', 'docs/ledger/archive/TD-1.md', 'docs/ledger/rank.yml',
                        'docs/ledger/notes.md', 'docs/technical_debt.md', 'x/docs/ledger/TD-2.md']))")
[ "$out" = "['docs/ledger/README.md', 'docs/ledger/archive/TD-1.md', 'docs/technical_debt.md']" ] \
  && ok "ledger_touched: v1's files and a v2 ledger's README and entry files, nothing else" || bad "ledger_touched: $out"

[ -x "$LEDGER_PY" ] && ok "ledger.py is executable" || bad "ledger.py not executable"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
