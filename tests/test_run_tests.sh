#!/usr/bin/env bash
# run_tests.sh (TD-047): the suite as one pass/fail, for CI. Every case runs the wrapper on a
# directory of fake suites, never on tests/ itself (that would recurse into this file).
# Offline; HOME is a temp dir; CI is unset except where a case sets it.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$DC/run_tests.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CI
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

mk() {  # $1 dir, $2 name, $3 body
    mkdir -p "$1"; printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/$2"
}
run() { out=$(bash "$W" "$@" 2>&1); rc=$?; }

G="$TMP/green"
mk "$G" a.sh 'echo "PASS: x"; echo "3 passed, 0 failed"'
mk "$G" b.sh 'echo "---- 2 passed, 0 failed"'
run "$G"
[ $rc -eq 0 ] && grep -q "^2 suites, 5 passed, 0 failed, 0 skipped" <<< "$out" \
    && ok "all green: exit 0, totals summed across both tally shapes" || bad "green rc=$rc: $out"

F="$TMP/fail"; cp -r "$G" "$F"
mk "$F" c.sh 'echo "FAIL: broke it"; echo "1 passed, 1 failed"; exit 1'
run "$F"
[ $rc -eq 1 ] && grep -q "FAILED: c.sh" <<< "$out" && grep -q "^    FAIL: broke it" <<< "$out" \
    && ok "a suite with failures fails the run and shows its FAIL lines" || bad "fail rc=$rc: $out"

E="$TMP/exit"; mk "$E" d.sh 'echo "4 passed, 0 failed"; exit 3'
run "$E"
[ $rc -eq 1 ] && grep -q "d.sh .*FAIL (exit 3)" <<< "$out" \
    && ok "a nonzero exit fails the run even with a clean tally" || bad "exit rc=$rc: $out"

N="$TMP/notally"; mk "$N" e.sh 'echo "PASS: one"; echo "died here" >&2; exit 0'
run "$N"
[ $rc -eq 1 ] && grep -q "e.sh .*FAIL (no tally)" <<< "$out" && grep -q "died here" <<< "$out" \
    && ok "no tally (a suite that died before its summary) fails the run, tail shown" || bad "no tally rc=$rc: $out"

L="$TMP/last"; mk "$L" f.sh 'echo "9 passed, 0 failed"; echo "0 passed, 2 failed"'
run "$L"
[ $rc -eq 1 ] && ok "the LAST tally line is the suite's verdict" || bad "last tally rc=$rc: $out"

S="$TMP/skip"; mk "$S" g.sh 'echo "SKIP: ruff not installed"; echo "PASS: a SKIP: in a label is not a skip"; echo "1 passed, 0 failed"'
run "$S"
[ $rc -eq 0 ] && grep -q "1 skipped" <<< "$out" && grep -q "  SKIP g.sh: ruff not installed" <<< "$out" \
    && ok "a SKIP is counted and named, and passes without --strict/CI" || bad "skip rc=$rc: $out"
run --strict "$S"
[ $rc -eq 1 ] && grep -q "1 skip(s) under --strict/CI" <<< "$out" && ok "--strict: a skip fails the run" || bad "strict rc=$rc: $out"
out=$(CI=true bash "$W" "$S" 2>&1); rc=$?
[ $rc -eq 1 ] && ok "CI set: a skip fails the run" || bad "CI rc=$rc: $out"

run "$TMP/nope"; [ $rc -eq 2 ] && ok "no such directory: exit 2" || bad "missing dir rc=$rc"
mkdir -p "$TMP/empty"; run "$TMP/empty"; [ $rc -eq 2 ] && ok "no suites: exit 2, never a silent pass" || bad "empty rc=$rc"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
