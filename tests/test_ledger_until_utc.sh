#!/usr/bin/env bash
# TD-253: ledger.py's readers (--pickable, --list, --check) judge an `until` gate against the UTC day, as
# the writers and cadence.md §2.4 do, whatever TZ is. Asserts: under a TZ whose local date differs from the
# UTC date right now (UTC+14 or UTC-12; at every instant one of them does), --pickable, --list and --check
# print what they print under TZ=UTC, for entries gated until UTC yesterday, today and tomorrow; and the
# gate until the UTC day lifts while the one until UTC tomorrow holds.
# Offline: the ledger is a temp git repo; HOME/XDG are temp dirs. Dates derive from the run date (TD-24).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export TZ=UTC   # TD-209; each date and ledger.py run below names its own TZ
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# One clock read for every date, so a run straddling midnight cannot mix days.
NOW=$(date -u +%s)
day() { TZ="$1" date -d "@$((NOW + $2 * 86400))" +%F 2>/dev/null || TZ="$1" date -r "$((NOW + $2 * 86400))" +%F; }
UTC_TODAY=$(day UTC 0); UTC_YDAY=$(day UTC -1); UTC_TMRW=$(day UTC 1)
FAR=Etc/GMT-14                                        # UTC+14 (POSIX signs are reversed)
[ "$(day "$FAR" 0)" != "$UTC_TODAY" ] || FAR=Etc/GMT+12   # else UTC-12
[ "$(day "$FAR" 0)" != "$UTC_TODAY" ] && ok "TZ $FAR's date ($(day "$FAR" 0)) differs from the UTC date ($UTC_TODAY)" \
  || bad "no TZ found whose date differs from the UTC date ($UTC_TODAY)"

W="$TMP/w"; mkdir -p "$W/docs/ledger/archive"; git init -q -b main "$W"
printf '# Ledger\n\nLedgerboard: 2\n' > "$W/docs/ledger/README.md"
entry() {  # $1 id, $2 until date, $3 title
  printf '## %s: %s\n\n**Priority:** Medium\n**Type:** debt\n**Added:** %s\n**Blocked by:** until %s\n**Status:** Open\n\n**Why:** a fixture.\n' \
    "$1" "$3" "$UTC_YDAY" "$2" "$3" > "$W/docs/ledger/$1.md"
}
entry TD-001 "$UTC_YDAY" "gated until UTC yesterday"
entry TD-002 "$UTC_TODAY" "gated until the UTC day"
entry TD-003 "$UTC_TMRW" "gated until UTC tomorrow"
git -C "$W" add -A; git -C "$W" commit -qm seed
lp() { (cd "$W" && TZ="$1" python3 "$LEDGER_PY" "${@:2}" 2>&1); }

for flag in --pickable --list --check; do
  u=$(lp UTC "$flag"); f=$(lp "$FAR" "$flag")
  [ "$u" = "$f" ] && ok "$flag under TZ=$FAR prints what it prints under TZ=UTC" \
    || bad "$flag differs between TZ=UTC and TZ=$FAR: $(diff <(echo "$u") <(echo "$f") | head -6)"
done

out=$(lp "$FAR" --pickable)
pick=$(printf '%s\n' "$out" | sed -n '/^Pickable/,/^Blocked/p')
case "$pick" in *TD-002*) ok "until the UTC day has lifted under TZ=$FAR" ;; *) bad "TD-002 not pickable under TZ=$FAR: $out" ;; esac
case "$pick" in *TD-003*) bad "until UTC tomorrow lifted under TZ=$FAR: $out" ;; *) ok "until UTC tomorrow holds under TZ=$FAR" ;; esac

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
