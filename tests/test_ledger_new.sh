#!/usr/bin/env bash
# TD-198: `ledger.py new` files one entry in a v2 ledger from flags, its id from the counter.
# Asserts: an entry from flags is written in canonical form, passes `--check --since` and
# `fmt --check`, and carries the take's `Taken by`; two news take two ids; a body from stdin works;
# what the gate would fail is refused before any take (an unknown Type, a prose wait), and so is a
# cross-repo blocker its roster repo does not have; --id files under a taken id and refuses an
# untaken one; a v1 ledger, two stdin sections and missing --priority/--why are usage errors.
# Offline: origin is a local bare repo, the roster a temp dir; HOME/XDG are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
NEXT="$DC/files/scripts/ledger_next_id.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_CODE_REMOTE CADENCE_FORGE
export CLAUDE_CODE_SESSION_ID=fixture-session LEDGER_IDS_RACE_SECONDS=20
BY=$(printf %s fixture-session | sha256sum | cut -c1-12)
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)

# origin (bare) seeded with a v2 ledger: TD-001 open, TD-002 archived; then a clone of it at $2.
mkrepo() {  # $1 origin dir, $2 clone dir
  rm -rf "$1" "$2" "$TMP/seed"; git init -q --bare -b main "$1"
  git init -q -b main "$TMP/seed"; mkdir -p "$TMP/seed/docs/ledger/archive"
  printf '# Ledger\n\nLedgerboard: 2\n' > "$TMP/seed/docs/ledger/README.md"
  printf '## TD-001: open one\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n\n**Why:** a fixture.\n' "$TODAY" \
    > "$TMP/seed/docs/ledger/TD-001.md"
  printf '## TD-002: archived one\n\n**Priority:** Low\n**Status:** Resolved %s: done\n\n**Why:** a fixture.\n\n**Resolved:** %s\n' \
    "$TODAY" "$TODAY" > "$TMP/seed/docs/ledger/archive/TD-002.md"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed
  git -C "$TMP/seed" push -q "$1" main; rm -rf "$TMP/seed"
  git clone -q "$1" "$2"; git -C "$2" config user.email t@t
}
last() { git -C "$1" show refs/heads/cadence/ledger-ids:LAST 2>/dev/null; }   # $1 origin
lp()   { (cd "$W" && python3 "$LEDGER_PY" "$@"); }
O="$TMP/o"; W="$TMP/w"; mkrepo "$O" "$W"
printf 'Filing goes wrong by hand.\n\nA second paragraph.\n' > "$TMP/why.md"
printf -- '- one step\n- another\n' > "$TMP/fix.md"

# --- 1) A full entry from flags: written in canonical form, with the take's Taken by.
out=$(lp new --title "a filed entry" --priority Medium --type debt --owner grinder --kind build \
      --location "x.py" --field "Area=ledger" --why "$TMP/why.md" --fix "$TMP/fix.md" 2>"$TMP/err"); rc=$?
f="$W/docs/ledger/TD-003.md"
want="## TD-003: a filed entry

**Priority:** Medium
**Type:** debt
**Added:** $TODAY
**Owner:** grinder
**Kind:** build
**Status:** Open
**Taken by:** $BY
**Location:** x.py
**Area:** ledger

**Why:** Filing goes wrong by hand.

A second paragraph.

**Fix:** - one step
- another"
if [ $rc -eq 0 ] && [ "$out" = "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "$want" ] && [ "$(last "$O")" = 3 ]; then
  ok "new writes the entry in canonical form under the taken id, with the take's Taken by, and prints its path"
else
  bad "new (rc=$rc) out=$out: $(cat "$TMP/err") --- $(cat "$f" 2>/dev/null)"
fi
c=$(lp --check --since origin/main 2>&1); rc1=$?
lp fmt --check >/dev/null 2>&1; rc2=$?
[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && ok "the new entry passes --check --since (ids judged) and fmt --check with no hand edit" \
  || bad "check rc=$rc1 fmt rc=$rc2: $c"
[ -z "$(git -C "$W" log origin/main..HEAD --oneline)" ] && [ "$(git -C "$W" status --porcelain)" = "?? docs/ledger/TD-003.md" ] \
  && ok "new commits nothing" || bad "git state: $(git -C "$W" status --porcelain)"

# --- 2) A second new takes the next id; its Why from stdin.
out=$(printf 'From stdin.\n' | lp new --title second --priority low --why - 2>"$TMP/err"); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$W/docs/ledger/TD-004.md" ] && grep -qx '\*\*Why:\*\* From stdin.' "$W/docs/ledger/TD-004.md" \
   && grep -qx '\*\*Status:\*\* Open' "$W/docs/ledger/TD-004.md" && [ "$(last "$O")" = 4 ]; then
  ok "two news take two ids; --why - reads stdin; Status defaults to Open"
else
  bad "second new (rc=$rc) out=$out: $(cat "$TMP/err")"
fi

# --- 3) What the gate fails is refused before any take: nothing written, the counter unmoved.
n_before=$(ls "$W/docs/ledger" | wc -l)
lp new --title bad --priority Low --type nonsense --why "$TMP/why.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused' "$TMP/err" && [ "$(last "$O")" = 4 ] && [ "$(ls "$W/docs/ledger" | wc -l)" = "$n_before" ] \
  && ok "an unknown Type is refused before the take: nothing written, no id spent" \
  || bad "bad Type (rc=$rc): $(cat "$TMP/err")"
lp new --title waits --priority Low --status "Open — waits on TD-001" --why "$TMP/why.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — .*waits on TD-001' "$TMP/err" && [ "$(last "$O")" = 4 ] \
  && ok "a wait written in prose is refused (name it in Blocked by), before the take" \
  || bad "prose wait (rc=$rc): $(cat "$TMP/err")"
printf '**Bold** opens a section.\n\n**Another:** lead\n' > "$TMP/boldy.md"
lp new --title bold --priority Low --why "$TMP/boldy.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused' "$TMP/err" && [ "$(last "$O")" = 4 ] \
  && ok "a section ledgerboard would not read back as given is refused" || bad "bold section (rc=$rc): $(cat "$TMP/err")"

# --- 4) A cross-repo blocker its roster repo does not have is refused; one it has is written.
O2="$TMP/o2"; R2="$TMP/other"; mkrepo "$O2" "$R2"
echo "$R2" > "$AGENT_CADENCE_REG_DIR/repos.txt"
lp new --title xrepo --priority Low --blocked-by "other#TD-099" --why "$TMP/why.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'Blocked by other#TD-099: other has no TD-099' "$TMP/err" && grep -q 'fetch' "$TMP/err" \
  && [ "$(last "$O")" = 4 ] && ok "a cross-repo blocker missing from its roster repo is refused, saying to fetch there" \
  || bad "xrepo missing (rc=$rc): $(cat "$TMP/err")"
out=$(lp new --title xrepo --priority Low --blocked-by "other#TD-001" --why "$TMP/why.md" 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && grep -qx '\*\*Blocked by:\*\* other#TD-001' "$out" \
  && ok "a cross-repo blocker its repo holds is written" || bad "xrepo present (rc=$rc): $(cat "$TMP/err")"
: > "$AGENT_CADENCE_REG_DIR/repos.txt"

# --- 5) --id: a taken id is filed with its take's by; an untaken one is refused.
t=$(cd "$W" && python3 "$NEXT" --by someone-else 2>/dev/null)
out=$(lp new --id "$t" --title "by id" --priority Low --why "$TMP/why.md" 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && grep -qx '\*\*Taken by:\*\* someone-else' "$out" && grep -q "^## $t: by id" "$out" \
  && ok "--id files under an id already taken, its Taken by the take's by" || bad "--id taken (rc=$rc): $(cat "$TMP/err")"
t2=$(cd "$W" && python3 "$NEXT" 2>/dev/null)
out=$(lp new --id "TD-$((10#${t2#TD-}))" --title unpadded --priority Low --why "$TMP/why.md" 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && [ "$out" = "$W/docs/ledger/$t2.md" ] && grep -q "^## $t2: unpadded" "$out" \
  && ok "--id TD-n is written at §2.2's width, as the counter gave it" || bad "--id unpadded (rc=$rc) out=$out: $(cat "$TMP/err")"
lp new --id TD-90 --title untaken --priority Low --why "$TMP/why.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused' "$TMP/err" && [ ! -e "$W/docs/ledger/TD-90.md" ] \
  && ok "--id with an id no take gave is refused (the gate's id check)" || bad "--id untaken (rc=$rc): $(cat "$TMP/err")"
lp new --id TD-001 --title dup --priority Low --why "$TMP/why.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'already' "$TMP/err" && ok "--id of an id the ledger holds is refused" || bad "--id dup (rc=$rc)"

# --- 6) Usage: v1 ledger, two stdin sections, no --priority, no --why.
printf '# L\n' > "$TMP/technical_debt.md"
python3 "$LEDGER_PY" new --ledger "$TMP/technical_debt.md" --title x --priority Low --why "$TMP/why.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q -- '--split` first' "$TMP/err" && ok "a v1 ledger is refused: split first" || bad "v1 (rc=$rc): $(cat "$TMP/err")"
lp new --title x --priority Low --why - --fix - </dev/null >/dev/null 2>&1; r1=$?
lp new --title x --why "$TMP/why.md" >/dev/null 2>&1; r2=$?
lp new --title x --priority Low >/dev/null 2>&1; r3=$?
lp new --title x --priority Low --why - </dev/null >/dev/null 2>&1; r4=$?
[ $r1 -eq 2 ] && [ $r2 -eq 2 ] && [ $r3 -eq 2 ] && [ $r4 -eq 2 ] && [ "$(last "$O")" = "$((10#${t2#TD-}))" ] \
  && ok "two stdin sections, no --priority, no --why and an empty Why are usage errors, before any take" || bad "usage: $r1 $r2 $r3 $r4"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
