#!/usr/bin/env bash
# TD-209: a test's date fixtures are calendar days. GNU `date -d 'N days'` counted from now adds N×24
# hours, so in the hour before a DST change it lands a day short (2026-10-31 00:06 MDT + '2 days' read
# 2026-11-01), and the suite went red for a reason that says nothing about the code. Every tests/*.sh
# that does `date -d` arithmetic exports TZ=UTC before it (no DST; the scripts it runs inherit it, so
# their today is the test's). Offline; reads only this repo's tests.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. the hazard, and the form that avoids it: from a moment with an offset (as "now" is), 2 days
#    across the fall-back in Denver is one calendar day; in UTC it is two
den=$(TZ=America/Denver date -d '2026-10-31 00:30 -0600 2 days' +%F 2>/dev/null)
utc=$(TZ=UTC date -d '2026-10-31 06:30 +0000 2 days' +%F)
if [ "$den" = 2026-11-01 ]; then
  [ "$utc" = 2026-11-02 ] && ok "1 offset-anchored '2 days' is 48h: a day short across DST in Denver, two calendar days in UTC" || bad "1 utc=$utc"
elif [ ! -e /usr/share/zoneinfo/America/Denver ]; then
  [ "$utc" = 2026-11-02 ] && ok "1 (no Denver zone data here) UTC's '2 days' is two calendar days" || bad "1 utc=$utc"
else
  bad "1 Denver's offset-anchored '2 days' read '$den', not the 48h 2026-11-01 this test pins"
fi

# 2. every test that does date -d arithmetic exports TZ=UTC before its first such line
missing=()
for f in "$DC"/tests/*.sh; do
  first=$(grep -nE "date (-d|--date)[ =]" "$f" | grep -vE '^[0-9]+:([[:space:]]*#|export TZ=)' | head -1 | cut -d: -f1)
  [ -n "$first" ] || continue
  [ "$(basename "$f")" = test_date_fixtures.sh ] && continue
  tz=$(grep -n '^export TZ=UTC\b' "$f" | head -1 | cut -d: -f1)
  { [ -n "$tz" ] && [ "$tz" -lt "$first" ]; } || missing+=("$(basename "$f")")
done
[ "${#missing[@]}" = 0 ] && ok "2 every tests/*.sh with date -d arithmetic exports TZ=UTC before it" || bad "2 no TZ=UTC before date -d in: ${missing[*]}"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
