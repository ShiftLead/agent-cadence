#!/usr/bin/env bash
# vendor_ledgerboard.sh <tag> — take a ledgerboard release into this repo (ShiftLead ADR 2026-10-12).
#
# Copies, from ShiftLead/ledgerboard at <tag> (e.g. v1.0):
#   ledgerboard.py -> files/scripts/ledgerboard.py   (a SYNC file: consumers get it by sync.sh)
#   fixtures/      -> tests/ledgerboard/             (tooling: never synced)
# and writes tests/ledgerboard/MANIFEST (the tag, its commit, a sha256 per file). Refuses a
# module whose release header is not <tag>'s or not intact. Commit the result and PR it; a
# consumer then takes it by sync. Tooling at the repo root, beside sync.sh; never synced.
#
# LEDGERBOARD_SRC=<path to a ledgerboard clone> reads the tag from that clone instead of a
# fresh shallow clone of https://github.com/ShiftLead/ledgerboard.
set -euo pipefail
tag="${1:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+$ ]] || { echo "usage: vendor_ledgerboard.sh v<major>.<minor>" >&2; exit 2; }
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ -n "${LEDGERBOARD_SRC:-}" ]; then
    git -C "$LEDGERBOARD_SRC" rev-parse -q --verify "refs/tags/$tag" >/dev/null \
        || { echo "no tag $tag in $LEDGERBOARD_SRC" >&2; exit 2; }
    git -C "$LEDGERBOARD_SRC" archive "$tag" | tar -x -C "$TMP"
    commit=$(git -C "$LEDGERBOARD_SRC" rev-parse "$tag^{commit}")
else
    git clone -q --depth 1 --branch "$tag" https://github.com/ShiftLead/ledgerboard.git "$TMP/src"
    commit=$(git -C "$TMP/src" rev-parse HEAD)
    mv "$TMP/src"/* "$TMP/" && rm -rf "$TMP/src"
fi
head -1 "$TMP/ledgerboard.py" | grep -q "^# ledgerboard $tag sha256:" \
    || { echo "ledgerboard.py at $tag does not carry the $tag release header" >&2; exit 1; }
python3 "$TMP/fixtures/run.py" --check-header --module "$TMP/ledgerboard.py"
install -m 644 "$TMP/ledgerboard.py" "$DC/files/scripts/ledgerboard.py"
rm -rf "$DC/tests/ledgerboard"
cp -R "$TMP/fixtures" "$DC/tests/ledgerboard"
{
    echo "# Written by vendor_ledgerboard.sh — do not edit by hand."
    echo "tag: $tag"
    echo "commit: $commit"
    (cd "$DC" && find files/scripts/ledgerboard.py tests/ledgerboard -type f ! -name MANIFEST | LC_ALL=C sort \
        | while read -r f; do echo "file: $f $(sha256sum "$f" | cut -d' ' -f1)"; done)
} > "$DC/tests/ledgerboard/MANIFEST"
python3 "$DC/tests/ledgerboard/run.py" --module "$DC/files/scripts/ledgerboard.py"
echo "vendored ledgerboard $tag ($commit) — commit it, PR it, then sync the consumers"
