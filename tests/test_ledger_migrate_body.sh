#!/usr/bin/env bash
# TD-283: `ledger.py migrate-body` passes through to ledgerboard's plan_migrate_body() (v3.3, its TD-133).
# Asserts: an open and an archived entry each carrying a non-strict lead (`**Done when** …`) and a glued lead
# are rewritten to the strict `**Name:**` form, a multi-line Ask is joined and its context moved under **Context:**, so `--check` shows no lead-form/glued-lead; an entry with
# no fault is left byte for byte; a second run changes nothing; --check names what would change, exits 1 and
# writes nothing; named ids rewrite only those; an entry with an open code fence is refused, named, left
# alone and fails the run; and a v1 ledger exits 2.
# Offline, fixture-driven: a temp ledger, HOME/XDG and the roster in a temp dir; dates from the run date.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/roster"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)
mb() { python3 "$LEDGER_PY" migrate-body --ledger "$L" "$@"; }
sums() { (cd "$L" && find . -type f | LC_ALL=C sort | xargs sha256sum); }
bodyflags() {  # the body kinds --check prints for the fixture ledger (open entries)
  python3 "$LEDGER_PY" --check --ledger "$L" --json 2>/dev/null \
    | python3 -c 'import json,sys; print(" ".join(sorted({f["kind"] for f in json.load(sys.stdin)["flags"] if f["kind"] in ("lead-form","glued-lead","field-lines","fence-open")})))'
}

L="$TMP/ledger"; mkdir -p "$L/archive"
printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
cat > "$L/TD-001.md" <<EOF
## TD-001: a non-strict lead and a glued one

**Priority:** Low
**Added:** $TODAY
**Status:** Open

**Why:** a case.
**Fix:** glued to the Why.

**Done when** it is done.
EOF
cat > "$L/TD-002.md" <<EOF
## TD-002: already strict

**Priority:** Low
**Added:** $TODAY
**Status:** Open

**Why:** a case.

**Done when:** it is done.
EOF
cat > "$L/TD-005.md" <<EOF
## TD-005: an Ask with context paragraphs

**Priority:** Low
**Added:** $TODAY
**Status:** Open

**Why:** a case.

**Ask:** Should the cache live
on disk?

It is read nightly.
EOF
cat > "$L/archive/TD-003.md" <<EOF
## TD-003: archived, a non-strict lead

**Priority:** Low
**Added:** $TODAY
**Status:** Resolved $TODAY

**Why:** a case.

**Done when** it was done.
EOF
cp "$L/TD-002.md" "$TMP/td2.before"

# --- 1) --check sees the flags, names what would change, exits 1, writes nothing.
f=$(bodyflags)
case "$f" in *lead-form*) ok "--check flags the fixture's non-strict lead ($f)";; *) bad "--check flags: '$f'";; esac
before=$(sums)
out=$(mb --check 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'would change: .*TD-001.md' \
   && printf '%s\n' "$out" | grep -q 'would change: .*archive/TD-003.md' \
   && ! printf '%s\n' "$out" | grep -q 'TD-002.md' && [ "$(sums)" = "$before" ]; then
  ok "--check names TD-001 and archived TD-003, not TD-002; exits 1; writes nothing"
else
  bad "--check (rc=$rc): $out"
fi

# --- 2) named ids rewrite only those.
out=$(mb TD-003 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q '^\*\*Done when:\*\* it was done\.$' "$L/archive/TD-003.md" \
   && grep -q '^\*\*Done when\*\* it is done\.$' "$L/TD-001.md"; then
  ok "migrate-body TD-003 rewrites the archived entry alone"
else
  bad "named id (rc=$rc): $out"
fi

# --- 3) the whole ledger: strict leads, a blank above the glued lead, the clean entry byte for byte.
out=$(mb 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q '^\*\*Done when:\*\* it is done\.$' "$L/TD-001.md" \
   && grep -B1 '^\*\*Fix:\*\* glued' "$L/TD-001.md" | head -1 | grep -q '^$' \
   && grep -qx '\*\*Ask:\*\* Should the cache live on disk?' "$L/TD-005.md" \
   && grep -A2 '^\*\*Context:\*\*' "$L/TD-005.md" | grep -q 'It is read nightly\.' \
   && printf '%s\n' "$out" | grep -q '^migrated: .*TD-005.md$' \
   && cmp -s "$L/TD-002.md" "$TMP/td2.before" && printf '%s\n' "$out" | grep -q 'ledger migrate-body: 4 entries, 2 migrated, 0 refused'; then
  ok "migrate-body rewrites TD-001 to strict leads, unglues its Fix, joins TD-005's Ask and moves its context, leaves TD-002"
else
  bad "migrate-body (rc=$rc): $out"; cat "$L/TD-001.md"
fi
f=$(bodyflags)
[ -z "$f" ] && ok "--check flags no body kind after the migration" || bad "--check after migration: '$f'"

# --- 4) idempotent.
before=$(sums)
out=$(mb 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$(sums)" = "$before" ] && printf '%s\n' "$out" | grep -q '0 migrated, 0 refused'; then
  ok "a second run changes nothing"
else
  bad "second run (rc=$rc): $out"
fi

# --- 5) an open fence is refused, named and left alone; the run fails.
printf '## TD-004: an open fence\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n\n**Why:** a case.\n\n```\ncode\n\n**Done when** never.\n' "$TODAY" > "$L/TD-004.md"
cp "$L/TD-004.md" "$TMP/td4.before"
out=$(mb 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'TD-004.md: refused, left alone — .*fence-open' \
   && cmp -s "$L/TD-004.md" "$TMP/td4.before"; then
  ok "an open fence is refused with its hand fix, left alone, exit 1"
else
  bad "open fence (rc=$rc): $out"
fi
rm "$L/TD-004.md"

# --- 6) a v1 ledger exits 2.
printf '# Technical debt\n' > "$TMP/technical_debt.md"
out=$(python3 "$LEDGER_PY" migrate-body --ledger "$TMP/technical_debt.md" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q 'not a v2 directory' && ok "a v1 ledger exits 2" || bad "v1 (rc=$rc): $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
