#!/usr/bin/env bash
# TD-179: an edit that removes an archived entry fails — `ledger.py --check --since REF` exits 1 and
# the cadence check's `ledger` row fails, naming the ids — in both layouts: a `## TD-NNN:` heading cut
# from a v1 archive, an `archive/TD-NNN.md` deleted or emptied in a v2 one. A `--split` between REF
# and the head loses nothing; an id moved from the archive back into the ledger is a reopen, named
# but never failed. (tests/test_ledger_archive.sh is this repo's own archive; this is the check every
# repo runs.) Offline, fixture-driven: temp repos, no origin, HOME/XDG and the roster in a temp dir.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/roster"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)
lp() { (cd "$1" && shift && python3 "$LEDGER_PY" "$@"); }
ent() { printf '## %s: %s\n\n**Priority:** low\n**Added:** %s\n**Status:** %s\n\n**Why:** a reason.\n\n' "$1" "$2" "$TODAY" "$3"; }
# row REPO FILE… — the cadence check's ledger row on HEAD as a merged PR (merge_sha^ is its base,
# so no origin and no forge are asked); prints "<status>|<detail>"
row() { local r=$1; shift; (cd "$DC/files/scripts" && python3 -c "
import json, sys; import check_cadence as K
pr = {'number': 9, 'state': 'merged', 'title': 'TD-002: an edit', 'files': sys.argv[3:],
      'merge_sha': sys.argv[2]}
r = K.row_ledger(pr, sys.argv[1]); print(f\"{r['status']}|{r['detail']}\")" "$r" "$(git -C "$r" rev-parse HEAD)" "$@"); }

V=$TMP/v1; mkdir -p "$V/docs"; git -C "$V" init -q -b main
{ printf '# Technical Debt\n\n## Summary\n\n| ID | Title | Priority | Status |\n|----|-------|----------|--------|\n| TD-002 | open | Low | Open |\n\n'
  ent TD-002 open Open; } > "$V/docs/technical_debt.md"
{ printf '# Archive\n\n'; ent TD-001 one Resolved; ent TD-003 three Resolved; } > "$V/docs/technical_debt_archive.md"
git -C "$V" add -A && git -C "$V" commit -qm base && BASE=$(git -C "$V" rev-parse HEAD)

# 1. v1: the archive truncated to its header (shiftlead #1421's shape)
git -C "$V" checkout -q -b trunc
printf '# Archive\n\n' > "$V/docs/technical_debt_archive.md"; git -C "$V" commit -qam truncate
out=$(lp "$V" --check --since "$BASE" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "⚠ the archive lost TD-001, TD-003" <<<"$out" \
  && ok "v1: --check --since fails a truncated archive, naming every id it lost" || bad "v1 trunc: rc=$rc $out"
out=$(lp "$V" --check --since "$BASE" --json 2>&1)
python3 -c "import json,sys; d=json.loads(sys.argv[1]); k=[f['kind'] for f in d['flags']]; assert d['errors']==1 and k==['archive-loss'], d" "$out" \
  && ok "v1: --json names the kind archive-loss, one error" || bad "v1 json: $out"
out=$(row "$V" docs/technical_debt_archive.md)
[ "${out%%|*}" = fail ] && grep -q "the archive lost TD-001, TD-003" <<<"$out" \
  && ok "v1: the cadence check's ledger row fails a PR that touches the archive alone and loses entries" || bad "v1 row: $out"

# 2. v1: an entry moved from the archive back into the ledger is reopened, not lost
git -C "$V" checkout -q main && git -C "$V" checkout -q -b reopen
{ printf '# Archive\n\n'; ent TD-001 one Resolved; } > "$V/docs/technical_debt_archive.md"
{ cat "$V/docs/technical_debt.md"; ent TD-003 three Open; } > "$TMP/l" && mv "$TMP/l" "$V/docs/technical_debt.md"
sed -i 's/^| TD-002 | open | Low | Open |$/&\n| TD-003 | three | Low | Open |/' "$V/docs/technical_debt.md"
git -C "$V" commit -qam reopen
out=$(lp "$V" --check --since "$BASE" 2>&1); rc=$?
[ $rc = 0 ] && grep -q "ℹ TD-003 left the archive for the ledger" <<<"$out" && ! grep -q "archive lost" <<<"$out" \
  && ok "v1: an id back in the ledger is named as reopened, and passes" || bad "v1 reopen: rc=$rc $out"
out=$(row "$V" docs/technical_debt.md docs/technical_debt_archive.md)
[ "${out%%|*}" = pass ] && grep -q "TD-003 left the archive" <<<"$out" \
  && ok "v1: the ledger row passes a reopen and warns of it" || bad "v1 reopen row: $out"

# 3. v1: an archive that grows passes with nothing said about it
git -C "$V" checkout -q main && git -C "$V" checkout -q -b grow
ent TD-004 four Resolved >> "$V/docs/technical_debt_archive.md"; git -C "$V" commit -qam grow
out=$(lp "$V" --check --since "$BASE" 2>&1); rc=$?
[ $rc = 0 ] && ! grep -q "archive" <<<"$out" && ok "v1: an archive that only grows passes" || bad "v1 grow: rc=$rc $out"

# 3b. REF archived an entry after the branch left it: judged from the merge-base, not REF's tip
git -C "$V" checkout -q main
ent TD-005 five Resolved >> "$V/docs/technical_debt_archive.md"; git -C "$V" commit -qam "main archives TD-005"
git -C "$V" checkout -q grow
out=$(lp "$V" --check --since main 2>&1); rc=$?
[ $rc = 0 ] && ! grep -q "archive lost" <<<"$out" \
  && ok "v1: an entry archived on REF after the branch forked is not this edit's loss" || bad "v1 stale: rc=$rc $out"
git -C "$V" checkout -q main && git -C "$V" reset -q --hard "$BASE"

# 4. the split itself (v1 → v2) loses nothing
git -C "$V" checkout -q main && git -C "$V" checkout -q -b split
lp "$V" --split >/dev/null 2>&1 && git -C "$V" add -A && git -C "$V" commit -qm split
[ -f "$V/docs/ledger/archive/TD-001.md" ] && [ ! -e "$V/docs/technical_debt_archive.md" ] || bad "split fixture: $(ls -R "$V/docs")"
SPLIT=$(git -C "$V" rev-parse HEAD)
out=$(lp "$V" --check --since "$BASE" 2>&1); rc=$?
[ $rc = 0 ] && ! grep -q "archive" <<<"$out" && ok "v2: --check --since across the split loses nothing" || bad "split: rc=$rc $out"
out=$(row "$V" docs/ledger/README.md docs/ledger/TD-002.md docs/ledger/archive/TD-001.md docs/ledger/archive/TD-003.md \
  docs/technical_debt.md docs/technical_debt_archive.md)
[ "${out%%|*}" = pass ] && ok "v2: the ledger row passes the split's own move" || bad "split row: $out"

# 5. v2: an archive file deleted
git -C "$V" checkout -q -b v2rm
git -C "$V" rm -q docs/ledger/archive/TD-001.md && git -C "$V" commit -qm rm
out=$(lp "$V" --check --since "$SPLIT" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "⚠ the archive lost TD-001:" <<<"$out" && ok "v2: a deleted archive file fails --check --since, naming its id" \
  || bad "v2 rm: rc=$rc $out"
out=$(row "$V" docs/ledger/archive/TD-001.md)
[ "${out%%|*}" = fail ] && grep -q "the archive lost TD-001" <<<"$out" && ok "v2: the ledger row fails a deleted archive file" \
  || bad "v2 rm row: $out"

# 6. v2: an archive file emptied — the layout is faulted too, and the row names the lost id beside it
git -C "$V" checkout -q split && git -C "$V" checkout -q -b v2empty
: > "$V/docs/ledger/archive/TD-003.md"; git -C "$V" commit -qam empty
out=$(row "$V" docs/ledger/archive/TD-003.md)
[ "${out%%|*}" = fail ] && grep -q "the archive lost TD-003" <<<"$out" && grep -q "not read" <<<"$out" \
  && ok "v2: an emptied archive file fails the row, naming the lost id and the faulted file" || bad "v2 empty row: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
