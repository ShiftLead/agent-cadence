#!/usr/bin/env bash
# run_tests.sh [--strict] [DIR] — the whole suite, as one pass/fail (TD-047).
#
# Runs every DIR/*.sh (default: tests/) in its own bash, one after another, and reads each
# suite's own tally — its last "N passed, M failed" line. A suite FAILS the run when it
# exits nonzero, reports M > 0, or prints no tally at all (a suite that died before its
# summary is not a pass). `bash tests/*.sh` runs only the first file, and the hand loop
# `for t in tests/*.sh; do bash "$t"; done` exits with the LAST suite's status — neither
# can gate CI; this can.
#
# SKIPs read green in a suite's own tally (TD-046), so they are counted here: every line
# starting "SKIP:" is listed in the summary, and with --strict — or CI set, as GitHub
# Actions sets it — any skip fails the run, because in CI a skipped check is a check that
# did not run. Exit 0 all green, 1 any failure (or strict skip), 2 bad usage / no suites.
#
# Lives at the repo root, not in tests/, so the suite loop never runs it. Tooling; never
# synced.
set -u
strict=0
[ -n "${CI:-}" ] && strict=1
if [ "${1:-}" = "--strict" ]; then strict=1; shift; fi
DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests}"
[ -d "$DIR" ] || { echo "run_tests: no such directory: $DIR" >&2; exit 2; }
shopt -s nullglob
suites=("$DIR"/*.sh)
[ ${#suites[@]} -gt 0 ] || { echo "run_tests: no *.sh suites in $DIR" >&2; exit 2; }

TALLY_RE='([0-9]+) passed, ([0-9]+) failed'
failed=(); skipped=(); total_pass=0; total_fail=0
start=$SECONDS
for t in "${suites[@]}"; do
    name="${t##*/}"
    out=$(bash "$t" 2>&1); rc=$?
    tally=$(grep -Eo "$TALLY_RE" <<< "$out" | tail -1)
    skips=$(grep -E '^SKIP:' <<< "$out")
    if [[ "$tally" =~ $TALLY_RE ]]; then
        p=${BASH_REMATCH[1]}; f=${BASH_REMATCH[2]}
        total_pass=$((total_pass + p)); total_fail=$((total_fail + f))
    else
        p="?"; f="?"
    fi
    verdict=ok
    if [ "$f" = "?" ]; then verdict="FAIL (no tally)"
    elif [ "$f" != 0 ]; then verdict="FAIL"
    elif [ "$rc" != 0 ]; then verdict="FAIL (exit $rc)"
    fi
    printf '%-40s %s passed, %s failed  %s\n' "$name" "$p" "$f" "$verdict"
    if [ "$verdict" != ok ]; then
        failed+=("$name")
        # the suite's own FAIL lines, or its tail when it printed none
        { grep -E '^FAIL' <<< "$out" || tail -15 <<< "$out"; } | sed 's/^/    /'
    fi
    if [ -n "$skips" ]; then
        while IFS= read -r s; do skipped+=("$name: ${s#SKIP: }"); done <<< "$skips"
    fi
done

echo
echo "${#suites[@]} suites, $total_pass passed, $total_fail failed, ${#skipped[@]} skipped — $((SECONDS - start))s"
for s in "${skipped[@]}"; do echo "  SKIP $s"; done
rc=0
if [ ${#failed[@]} -gt 0 ]; then echo "FAILED: ${failed[*]}"; rc=1; fi
if [ ${#skipped[@]} -gt 0 ] && [ "$strict" = 1 ]; then
    echo "FAILED: ${#skipped[@]} skip(s) under --strict/CI — a skipped check did not run"; rc=1
fi
exit $rc
