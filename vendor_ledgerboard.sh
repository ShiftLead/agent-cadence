#!/usr/bin/env bash
# vendor_ledgerboard.sh <tag> — take a ledgerboard release into this repo (ShiftLead ADR 2026-10-12).
#
# Copies, from ShiftLead/ledgerboard at <tag> (v2.3 or later: the package, TD-213):
#   ledgerboard/*.py -> files/scripts/ledgerboard/   (SYNC files: the module and its board writer, board.py)
#   fixtures/        -> tests/ledgerboard/           (tooling: never synced)
# and writes tests/ledgerboard.MANIFEST (the tag, its commit, a sha256 per file) beside the fixtures, whose own
# MANIFEST (v2.5) is the release's and is kept as shipped. Refuses a
# package file whose release header is not <tag>'s or not intact, and a package file that is not in
# sync.sh's SYNC_FILES (a new one is added there and to the README's table in the same PR). Commit the
# result and PR it; a consumer takes it by its next pin bump. Tooling at the repo root, beside sync.sh.
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
[ -f "$TMP/ledgerboard/__init__.py" ] \
    || { echo "ledgerboard at $tag is not the package (v2.3 or later): no ledgerboard/__init__.py" >&2; exit 1; }
for f in "$TMP"/ledgerboard/*.py; do
    head -1 "$f" | grep -q "^# ledgerboard $tag sha256:" \
        || { echo "ledgerboard/$(basename "$f") at $tag does not carry the $tag release header" >&2; exit 1; }
    grep -qxF "    \"scripts/ledgerboard/$(basename "$f")\"" "$DC/sync.sh" \
        || { echo "ledgerboard/$(basename "$f") is not in sync.sh's SYNC_FILES — add it there and to README's table" >&2; exit 1; }
done
python3 "$TMP/fixtures/run.py" --check-header --module "$TMP/ledgerboard"
rm -rf "$DC/files/scripts/ledgerboard" "$DC/files/scripts/ledgerboard.py"
mkdir -p "$DC/files/scripts/ledgerboard"
install -m 644 "$TMP"/ledgerboard/*.py "$DC/files/scripts/ledgerboard/"
rm -rf "$DC/tests/ledgerboard"
cp -R "$TMP/fixtures" "$DC/tests/ledgerboard"
{
    echo "# Written by vendor_ledgerboard.sh — do not edit by hand."
    echo "tag: $tag"
    echo "commit: $commit"
    (cd "$DC" && find files/scripts/ledgerboard tests/ledgerboard -type f ! -path '*/__pycache__/*' | LC_ALL=C sort \
        | while read -r f; do echo "file: $f $(sha256sum "$f" | cut -d' ' -f1)"; done)
} > "$DC/tests/ledgerboard.MANIFEST"
python3 "$DC/tests/ledgerboard/run.py" --module "$DC/files/scripts/ledgerboard"
echo "vendored ledgerboard $tag ($commit) — commit it and PR it; a consumer takes it by its next pin bump"
