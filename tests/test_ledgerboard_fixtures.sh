#!/usr/bin/env bash
# The vendored ledgerboard (ShiftLead ADR 2026-10-12): the package files/scripts/ledgerboard/ (v2.3,
# TD-213) is an intact release, every file of it the one tests/ledgerboard/MANIFEST names, every vendored file is as vendored, and the
# release's own fixtures pass against this repo's copy. vendor_ledgerboard.sh writes all three.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="$DC/files/scripts/ledgerboard"
MAN="$DC/tests/ledgerboard/MANIFEST"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

out=$(python3 "$DC/tests/ledgerboard/run.py" --check-header --module "$MOD" 2>&1) \
    && ok "the package's release headers are intact ($out)" || bad "release header: $out"
tag=$(sed -n 's/^tag: //p' "$MAN" 2>/dev/null)
off=""
for f in "$MOD"/*.py; do head -1 "$f" | grep -q "^# ledgerboard $tag sha256:" || off="$off $(basename "$f")"; done
[ -n "$tag" ] && [ -f "$MOD/__init__.py" ] && [ -z "$off" ] \
    && ok "every package file's header names the MANIFEST's release ($tag)" \
    || bad "header and MANIFEST disagree (MANIFEST: ${tag:-none}):${off:- no package}"
unlisted=""
for f in "$MOD"/*.py; do grep -q "^file: files/scripts/ledgerboard/$(basename "$f") " "$MAN" || unlisted="$unlisted $(basename "$f")"; done
[ -z "$unlisted" ] && ok "every package file is in the MANIFEST" || bad "package files the MANIFEST does not name:$unlisted"
drift=""
while read -r line; do  # `file: <path> <sha256>`; v2.4's fixture paths hold spaces, so the hash is the last word
    h=${line##* }; f=${line#file: }; f=${f% *}
    [ "$(cd "$DC" && sha256sum "$f" 2>/dev/null | cut -d' ' -f1)" = "$h" ] || drift="$drift '$f'"
done < <(grep '^file: ' "$MAN" 2>/dev/null)
[ -n "$(grep -c '^file: ' "$MAN" 2>/dev/null)" ] && [ -z "$drift" ] \
    && ok "every vendored file is as vendored" || bad "edited since vendored (vendor_ledgerboard.sh owns them):$drift"
out=$(python3 "$DC/tests/ledgerboard/run.py" --module "$MOD" 2>&1) \
    && ok "ledgerboard's fixtures pass against this copy ($out)" || bad "fixtures: $out"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
