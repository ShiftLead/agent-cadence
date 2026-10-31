#!/usr/bin/env bash
# TD-197: `ledger.py fmt` writes a v2 ledger's entries in ledgerboard's canonical form (canonical()).
# Asserts: every entry in this repo's ledger and archive goes through canonical() or is named as
# refused; fmt puts a hand-edited entry (fields out of order, CRLF, stray blank lines) in canonical
# form and is idempotent; --check names what would change, exits 1 and writes nothing; a refused
# entry is named with its hand fix, left alone, and fails the run; named ids format only those; a v1
# ledger and an unknown id exit 2 with nothing written.
# Offline, fixture-driven: a temp ledger, HOME/XDG and the roster in a temp dir.
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
fmt() { python3 "$LEDGER_PY" fmt --ledger "$L" "$@"; }
sums() { (cd "$L" && find . -type f | LC_ALL=C sort | xargs sha256sum); }

# --- 1) This repo's own ledger and archive: each entry is canonical() or named as refused.
out=$(python3 - "$DC/files/scripts" "$DC/docs/ledger" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import ledgerboard as LB
root, n, bad = Path(sys.argv[2]), 0, []
for d in (root, root / LB.LEDGER_ARCHIVE):
    for p in sorted(d.glob("TD-*.md")):
        n += 1
        try:
            once = LB.canonical(p.read_text(encoding="utf-8"))
            if LB.canonical(once) != once:
                bad.append(f"{p.name}: not idempotent")
        except LB.Refused as e:
            print(f"refused: {p.name}: {e}")
print(f"entries {n}")
for b in bad:
    print(f"BAD {b}")
PY
)
n=$(printf '%s\n' "$out" | sed -n 's/^entries //p')
if [ "${n:-0}" -gt 0 ] && ! printf '%s\n' "$out" | grep -q '^BAD'; then
  ok "this repo's $n entries each round-trip through canonical() or are named ($(printf '%s\n' "$out" | grep -c '^refused') refused)"
else
  bad "this repo's ledger through canonical(): $out"
fi

# --- A fixture ledger: one entry canonical already, one hand-edited, one refused, one archived.
L="$TMP/ledger"; mkdir -p "$L/archive"
printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
cat > "$L/TD-001.md" <<EOF
## TD-001: already canonical

**Priority:** High
**Type:** debt
**Added:** $TODAY
**Status:** Open

**Why:** it is.
EOF
printf '## TD-002: hand edited\r\n\r\n**Status:** Open\r\n**Location:** x.py\r\n**Priority:** Low\r\n**Added:** %s\r\n\r\n\r\n**Why:** reordered.\r\n\r\n**Fix:** fmt.\r\n\r\n\r\n' "$TODAY" > "$L/TD-002.md"
cat > "$L/TD-003.md" <<EOF
## TD-003: refused

**Priority:** Low
**Priority:** High

**Why:** a field twice.
EOF
printf '## TD-004: archived\n**Status:** Done\n**Priority:** Low\n\n**Why:** no blank after the heading.\n' > "$L/archive/TD-004.md"
printf '## TD-005: CRLF only\r\n\r\n**Priority:** Low\r\n\r\n**Why:** line endings.\r\n' > "$L/TD-005.md"
cp "$L/TD-003.md" "$TMP/td3.before"
cp "$L/TD-001.md" "$TMP/td1.before"

# --- 2) --check names what would change, exits 1, writes nothing.
before=$(sums)
out=$(fmt --check 2>"$TMP/err"); rc=$?
if [ $rc -eq 1 ] && [ "$(sums)" = "$before" ] \
   && printf '%s\n' "$out" | grep -q 'would change: .*TD-002.md' \
   && printf '%s\n' "$out" | grep -q 'would change: .*archive/TD-004.md' \
   && printf '%s\n' "$out" | grep -q 'would change: .*TD-005.md' \
   && ! printf '%s\n' "$out" | grep -q 'TD-001.md'; then
  ok "fmt --check names the three entries (CRLF alone among them) that would change, exits 1, writes nothing"
else
  bad "fmt --check (rc=$rc): $out"
fi

# --- 3) fmt formats, names the refused entry with its hand fix and leaves it alone.
out=$(fmt 2>"$TMP/err"); rc=$?
want="## TD-002: hand edited

**Priority:** Low
**Added:** $TODAY
**Status:** Open
**Location:** x.py

**Why:** reordered.

**Fix:** fmt."
if [ $rc -eq 1 ] && [ "$(cat "$L/TD-002.md")" = "$want" ] && ! grep -q $'\r' "$L/TD-002.md" "$L/TD-005.md" \
   && [ "$(tail -c1 "$L/TD-002.md" | od -An -c | tr -d ' ')" = '\n' ]; then
  ok "fmt puts a hand-edited entry in canonical form: field order, LF, one trailing newline"
else
  bad "fmt TD-002 (rc=$rc): $(cat -A "$L/TD-002.md")"
fi
if grep -q 'TD-003.md: refused, left alone — .*twice' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3.before" \
   && cmp -s "$L/TD-001.md" "$TMP/td1.before"; then
  ok "a refused entry is named with its hand fix and left alone; a canonical one is untouched"
else
  bad "refused TD-003: $(cat "$TMP/err")"
fi
if printf '%s\n' "$(cat "$L/archive/TD-004.md")" | sed -n 2p | grep -qx ''; then
  ok "fmt reaches the archive"
else
  bad "archive/TD-004.md: $(cat "$L/archive/TD-004.md")"
fi

# --- 4) Idempotent: a second run changes no byte.
before=$(sums)
out=$(fmt 2>/dev/null)
if [ "$(sums)" = "$before" ] && printf '%s\n' "$out" | grep -q ', 0 formatted, 1 refused'; then
  ok "fmt is idempotent"
else
  bad "second fmt: $out"
fi

# --- 5) Named ids format only those; with the refused one fixed, the run exits 0.
printf '## TD-003: refused\n\n**Priority:** Low\n\n**Why:** fixed.\n' > "$L/TD-003.md"
printf '## TD-001: already canonical\n**Priority:** High\n' > "$L/TD-001.md"
out=$(fmt TD-3 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '1 entry, 0 formatted, 0 refused' \
   && [ "$(sed -n 2p "$L/TD-001.md")" = '**Priority:** High' ]; then
  ok "fmt TD-n formats only the named entry"
else
  bad "fmt TD-3 (rc=$rc): $out"
fi

# --- 6) Unknown id, a bad id, and a v1 ledger: exit 2, nothing written.
before=$(sums)
fmt TD-99 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'TD-99 is in neither' "$TMP/err" && [ "$(sums)" = "$before" ] \
  && ok "an id in neither directory exits 2" || bad "fmt TD-99 (rc=$rc): $(cat "$TMP/err")"
fmt nope >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok "a malformed id is a usage error" || bad "fmt nope (rc=$rc)"
printf '# Ledger\n\n## TD-001: x\n\n**Priority:** Low\n' > "$TMP/technical_debt.md"
python3 "$LEDGER_PY" fmt --ledger "$TMP/technical_debt.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q -- '--split` first' "$TMP/err" \
  && ok "a v1 ledger is refused: split first" || bad "fmt on v1 (rc=$rc): $(cat "$TMP/err")"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
