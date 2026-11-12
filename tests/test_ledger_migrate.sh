#!/usr/bin/env bash
# TD-256: `ledger.py migrate` runs ledgerboard's v2.7 migrate over this repo's docs/ledger/ and its archive.
# Asserts: this repo's own ledger passes `--check` (no Status outside the closed set, no header Location);
# on a fixture git repo, --plan and --dry-run write nothing; the run maps an open entry's noted Status to
# Open (its words in the Log) and moves a header Location into the body; an archived Status with no date
# of its own takes git's (the UTC day its archive file was added), while one with a date in its text keeps
# it, not git's; a Status the rules stop on stops the run with nothing written, and `--as` answers it;
# `--check` passes on the result. Dates derive from the run date (TD-24).
# Offline, fixture-driven: a temp git repo, HOME/XDG and the roster in temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/roster" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export TZ=UTC   # TD-209: date -d arithmetic in calendar days
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)
D10=$(date -d "$TODAY -10 days" +%F)   # the dates the entries' own texts carry
D5=$(date -d "$TODAY -5 days" +%F)     # git's archiving day
mig() { (cd "$W" && python3 "$LEDGER_PY" migrate "$@"); }
sums() { (cd "$W" && find docs -type f | LC_ALL=C sort | xargs sha256sum); }

# --- 1) this repo's own ledger is migrated: no Status outside the closed set, no header Location or Waits
# (judged by kind, since a cross-repo Blocked by cannot resolve against the isolated roster)
out=$(cd "$DC" && python3 "$LEDGER_PY" --check --ledger "$DC/docs/ledger" --json 2>&1 | python3 -c '
import json, sys
d = json.load(sys.stdin)
for f in d["flags"]:
    if f["kind"] == "status" or (f["kind"] == "retired" and f["field"] in ("location", "waits")):
        print(f["id"], f["kind"], f["field"])')
[ -z "$out" ] && ok "this repo's ledger: every Status in the closed set, no header Location or Waits" \
  || bad "this repo's ledger: $(printf '%s\n' "$out" | head -5)"

# --- a fixture repo: two open entries, three archived
W="$TMP/w"; L="$W/docs/ledger"; mkdir -p "$L/archive"
git init -q -b main "$W"
printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
printf '# Archive\n' > "$L/archive/README.md"
cat > "$L/TD-001.md" <<EOF
## TD-001: An open entry with a noted Status

**Priority:** High
**Type:** debt
**Added:** $D10
**Status:** Open — slice 1 built $D10, slice 2 left
**Location:** \`src/a.py\`

**Why:** a reason.

**Fix:** a fix.
EOF
cat > "$L/TD-002.md" <<EOF
## TD-002: An open entry already in form

**Priority:** Low
**Type:** debt
**Added:** $D10
**Status:** Open

**Why:** a reason.
EOF
cat > "$L/archive/TD-003.md" <<EOF
## TD-003: Archived with no date of its own

**Priority:** Low
**Type:** debt
**Added:** $D10
**Status:** Resolved

**Why:** a reason.
EOF
cat > "$L/archive/TD-004.md" <<EOF
## TD-004: Archived with its date in its text

**Priority:** Low
**Type:** debt
**Added:** $D10
**Status:** Resolved $D10. Verified and archived.

**Why:** a reason.
EOF
git -C "$W" add -A
GIT_COMMITTER_DATE="${D5}T12:00:00Z" GIT_AUTHOR_DATE="${D5}T12:00:00Z" git -C "$W" commit -qm seed
before=$(sums)

# --- 2) --plan and --dry-run write nothing
mig --release 2.7 --plan >"$TMP/plan" 2>"$TMP/err"; rc=$?
mig --release 2.7 --dry-run >"$TMP/dry" 2>>"$TMP/err"; rc2=$?
[ $rc -eq 0 ] && [ $rc2 -eq 0 ] && [ "$(sums)" = "$before" ] && grep -q '"subject": "ledger: migrate v2.7' "$TMP/plan" \
  && grep -q '^TD-001' "$TMP/dry" \
  && ok "--plan and --dry-run print the changes and write nothing" || bad "plan (rc=$rc/$rc2): $(cat "$TMP/err")"

# --- 3) the run: Status mapped, words to the Log, Location to the body; git's date only where the text has none
mig --release 2.7 >"$TMP/out" 2>"$TMP/err"; rc=$?
loc_body=$(awk '/^$/{b=1} b && /^\*\*Location:\*\* `src\/a.py`/' "$L/TD-001.md")
[ $rc -eq 0 ] && grep -qx '\*\*Status:\*\* Open' "$L/TD-001.md" && [ -n "$loc_body" ] \
  && grep -q "was: Open — slice 1 built $D10, slice 2 left" "$L/TD-001.md" \
  && ok "an open entry's noted Status becomes Open, its words in the Log, its Location in the body" \
  || bad "open entry (rc=$rc): $(cat "$TMP/err") | $(cat "$L/TD-001.md")"
grep -qx "\*\*Status:\*\* Resolved $D5" "$L/archive/TD-003.md" \
  && ok "an archived Status with no date takes git's archiving day" || bad "git date: $(grep Status "$L/archive/TD-003.md")"
grep -qx "\*\*Status:\*\* Resolved $D10" "$L/archive/TD-004.md" \
  && ok "an archived Status dated in its text keeps that date, not git's" || bad "text date: $(grep Status "$L/archive/TD-004.md")"
! grep -q 'TD-002' "$TMP/out" && ok "an entry already in form is not written" || bad "TD-002 written: $(cat "$TMP/out")"
out=$(python3 "$LEDGER_PY" --check --ledger "$L" 2>&1) && ok "--check passes on the result" || bad "check: $out"
git -C "$W" checkout -q -- docs

# --- 3b) archived twice (reopened, then archived again): git's newest add is the date
D3=$(date -d "$TODAY -3 days" +%F)
cp "$L/archive/TD-003.md" "$TMP/td3"; git -C "$W" rm -q docs/ledger/archive/TD-003.md
GIT_COMMITTER_DATE="${D5}T13:00:00Z" git -C "$W" commit -qm reopen
cp "$TMP/td3" "$L/archive/TD-003.md"; git -C "$W" add -A
GIT_COMMITTER_DATE="${D3}T12:00:00Z" git -C "$W" commit -qm rearchive
mig --release 2.7 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx "\*\*Status:\*\* Resolved $D3" "$L/archive/TD-003.md" \
  && ok "an entry archived twice takes git's newest archiving day" || bad "newest (rc=$rc): $(cat "$TMP/err") $(grep Status "$L/archive/TD-003.md")"
git -C "$W" checkout -q -- docs

# --- 4) a stop writes nothing; --as answers it
sed -i 's/^\*\*Status:\*\* Resolved$/**Status:** Parked/' "$L/archive/TD-003.md"
git -C "$W" commit -qam park; before=$(sums)
mig --release 2.7 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && [ "$(sums)" = "$before" ] && grep -q '^TD-003:' "$TMP/err" \
  && ok "a Status the rules stop on stops the run, naming it, nothing written" || bad "stop (rc=$rc): $(cat "$TMP/err")"
mig --release 2.7 --as TD-003=dropped >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx "\*\*Status:\*\* Dropped $D3" "$L/archive/TD-003.md" \
  && ok "--as answers the stop, the date git's newest" || bad "--as (rc=$rc): $(cat "$TMP/err") | $(grep Status "$L/archive/TD-003.md")"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
