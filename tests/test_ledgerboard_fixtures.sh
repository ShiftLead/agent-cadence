#!/usr/bin/env bash
# The vendored ledgerboard (ShiftLead ADR 2026-10-12): files/scripts/ledgerboard.py is an intact
# release, the one tests/ledgerboard/MANIFEST names, every vendored file is as vendored, and the
# release's own fixtures pass against this repo's copy. vendor_ledgerboard.sh writes all three.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="$DC/files/scripts/ledgerboard.py"
MAN="$DC/tests/ledgerboard/MANIFEST"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

out=$(python3 "$DC/tests/ledgerboard/run.py" --check-header --module "$MOD" 2>&1) \
    && ok "the module's release header is intact ($out)" || bad "release header: $out"
tag=$(sed -n 's/^tag: //p' "$MAN" 2>/dev/null)
[ -n "$tag" ] && head -1 "$MOD" | grep -q "^# ledgerboard $tag sha256:" \
    && ok "the header names the MANIFEST's release ($tag)" || bad "header and MANIFEST disagree (MANIFEST: ${tag:-none})"
drift=""
while read -r _ f h; do
    [ "$(cd "$DC" && sha256sum "$f" 2>/dev/null | cut -d' ' -f1)" = "$h" ] || drift="$drift $f"
done < <(grep '^file: ' "$MAN" 2>/dev/null)
[ -n "$(grep -c '^file: ' "$MAN" 2>/dev/null)" ] && [ -z "$drift" ] \
    && ok "every vendored file is as vendored" || bad "edited since vendored (vendor_ledgerboard.sh owns them):$drift"
out=$(python3 "$DC/tests/ledgerboard/run.py" --module "$MOD" 2>&1) \
    && ok "ledgerboard's fixtures pass against this copy ($out)" || bad "fixtures: $out"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
