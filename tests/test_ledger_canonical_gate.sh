#!/usr/bin/env bash
# TD-201: an entry a PR changes is held to canonical form. Asserts, for `ledger.py --check --since`
# and for the cadence check's ledger row (ledger_edit_check) alike: a hand edit out of canonical form
# fails, naming `ledger.py fmt TD-n`; the same edit after `fmt` passes; an untouched non-canonical
# entry is never flagged; a body-only edit is judged; a file new in archive/ is judged; an entry
# canonical() refuses fails naming the hand fix; a branch whose main moved on judges only its own
# changes (from the merge-base); the row does not judge a merged PR's form.
# Offline: origin is a local bare repo; HOME/XDG and the roster are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CADENCE_FORGE
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# TD-001 canonical; TD-002 and TD-004 not (Status above Priority), never touched by hand; TD-003 canonical.
O="$TMP/o"; W="$TMP/w"; git init -q --bare -b main "$O"; git init -q -b main "$TMP/seed"
L="$TMP/seed/docs/ledger"; mkdir -p "$L"
printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
printf '## TD-001: one\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** a fixture.\n' > "$L/TD-001.md"
printf '## TD-002: two\n\n**Status:** Open\n**Priority:** Low\n\n**Why:** out of order, untouched.\n' > "$L/TD-002.md"
printf '## TD-003: three\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** a fixture.\n' > "$L/TD-003.md"
printf '## TD-004: four\n\n**Status:** Open\n**Priority:** Low\n\n**Why:** out of order; main formats it later.\n' > "$L/TD-004.md"
git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed; git -C "$TMP/seed" push -q "$O" main; rm -rf "$TMP/seed"
git clone -q "$O" "$W"; L="$W/docs/ledger"
lp() { (cd "$W" && python3 "$LEDGER_PY" "$@"); }
row() { (cd "$DC/files/scripts" && python3 -c "
import json, sys; import check_cadence as K
errs, note = K.ledger_edit_check({'state': 'open', 'head_sha': sys.argv[2], 'files': sys.argv[3:]}, sys.argv[1])
print('\n'.join(errs))" "$W" "$(git -C "$W" rev-parse HEAD)" "$@"); }
commit() { git -C "$W" add -A; git -C "$W" commit -qm "$1"; }

c=$(lp --check --since origin/main 2>&1) && ! grep -q 'canonical' <<<"$c" \
  && ok "an untouched entry out of canonical form is not flagged" || bad "untouched: $c"

# --- a hand edit out of canonical form (a field below Status) fails, naming fmt.
git -C "$W" checkout -q -b hand
printf '## TD-001: one\n\n**Status:** Open\n**Priority:** High\n\n**Why:** a fixture.\n' > "$L/TD-001.md"; commit hand
c=$(lp --check --since origin/main 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q 'TD-001: .*not in canonical form — `ledger.py fmt TD-001`' <<<"$c" && ! grep -q 'TD-002' <<<"$c" \
  && ok "--check --since fails a hand edit out of canonical form, naming fmt, and only that entry" || bad "hand (rc=$rc): $c"
r=$(row docs/ledger/TD-001.md)
grep -q 'TD-001: .*ledger.py fmt TD-001' <<<"$r" && ! grep -q TD-002 <<<"$r" \
  && ok "the cadence check's ledger row fails it too" || bad "row hand: $r"
m=$(cd "$DC/files/scripts" && python3 -c "
import sys; import check_cadence as K
errs, note = K.ledger_edit_check({'state': 'merged', 'merge_sha': sys.argv[2], 'files': ['docs/ledger/TD-001.md']}, sys.argv[1])
print('\n'.join(errs))" "$W" "$(git -C "$W" rev-parse HEAD)")
[ -z "$m" ] && ok "a merged PR is not judged on form (the sweep never fails one merged before the rule)" || bad "merged: $m"

# --- the same edit after fmt passes.
lp fmt TD-001 >/dev/null; commit fmt
c=$(lp --check --since origin/main 2>&1) && [ -z "$(row docs/ledger/TD-001.md)" ] \
  && ok "the same edit after fmt passes both" || bad "after fmt: $c / $(row docs/ledger/TD-001.md)"

# --- a body-only edit of a non-canonical entry is judged (its header block is unchanged).
printf '## TD-002: two\n\n**Status:** Open\n**Priority:** Low\n\n**Why:** out of order, and its body edited.\n' > "$L/TD-002.md"; commit body
c=$(lp --check --since origin/main 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q 'TD-002: .*fmt TD-002' <<<"$c" && grep -q 'TD-002' <<<"$(row docs/ledger/TD-002.md)" \
  && ok "a body-only edit is judged by the file, not the header block" || bad "body (rc=$rc): $c"
lp fmt TD-002 >/dev/null; commit fmt2

# --- a file new in archive/ is judged; an entry canonical() refuses names the hand fix.
mkdir -p "$L/archive"; git -C "$W" mv docs/ledger/TD-003.md docs/ledger/archive/TD-003.md
printf '## TD-003: three\n\n**Status:** Resolved 2026-01-01: done\n**Priority:** Low\n\n**Why:** a fixture.\n\n**Resolved:** 2026-01-01\n' > "$L/archive/TD-003.md"
commit archived
c=$(lp --check --since origin/main 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q 'TD-003: .*archive/TD-003.md is not in canonical form' <<<"$c" \
  && ok "a file new in archive/ is judged" || bad "archive (rc=$rc): $c"
lp fmt TD-003 >/dev/null; commit fmt3
printf '## TD-001: one\n\n**Priority:** Low\n**Priority:** High\n**Status:** Open\n\n**Why:** a fixture.\n' > "$L/TD-001.md"; commit twice
c=$(lp --check --since origin/main 2>&1); rc=$?
[ $rc -eq 1 ] && grep -q 'TD-001: .*fix it by hand, then `ledger.py fmt TD-001`' <<<"$c" \
  && ok "an entry canonical() refuses fails naming the hand fix" || bad "refused (rc=$rc): $c"
git -C "$W" reset -q --hard HEAD~1

# --- main moves on (it formats TD-004): the branch, behind it with TD-004 as it was, is not judged on it.
git -C "$W" checkout -q main; lp fmt TD-004 >/dev/null; commit main-fmt; git -C "$W" push -q origin main; git -C "$W" checkout -q hand
c=$(lp --check --since origin/main 2>&1) && ! grep -q 'TD-004' <<<"$c" \
  && ok "an entry main changed after the branch left it is not the branch's to fix" || bad "fork: $c"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
