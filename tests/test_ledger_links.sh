#!/usr/bin/env bash
# Every relative link in this repo's own ledger (docs/ledger/, TD-160's split) resolves.
#
# WHY THIS IS A TEST
# ------------------
# `ledger.py --split` moved each entry byte for byte, so the links written relative to docs/
# (`](plans/…)`, `](../files/…)`) resolved one level short from docs/ledger/ and two from
# docs/ledger/archive/, and nothing noticed until a review did (TD-170). An entry filed in the
# old habit breaks the same way. Gates judge the index (cadence.md §7): the files read are the
# tracked ones; a link inside a code span is prose about a link, not one, and is skipped.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

dead() {  # dead <file>…: "<file>:<line>: <target>" for each relative link that resolves nowhere
  python3 - "$@" <<'PY'
import os, re, sys
LINK = re.compile(r"\]\(([^)\s]+)\)")
for f in sys.argv[1:]:
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        for m in LINK.finditer(re.sub(r"`[^`]*`", "", line)):
            path = m.group(1).split("#")[0]
            if not path or re.match(r"[a-z][a-z0-9+.-]*:", path):
                continue
            if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(f), path))):
                print(f"{f}:{i}: {m.group(1)}")
PY
}

mapfile -t files < <(git ls-files 'docs/ledger/*.md')
if [ ${#files[@]} -eq 0 ]; then
  bad "no tracked docs/ledger/*.md files — the ledger moved, so this test reads nothing"
else
  out=$(dead "${files[@]}")
  [ -z "$out" ] && ok "every relative link in the ${#files[@]} ledger files resolves" || bad "dead links:
$out"
fi

# The checker itself: a docs/-relative link in an entry file is dead, the same link one level up
# is not, a URL and an anchor are not links to check, and a code span is skipped.
mkdir -p "$TMP/r/docs/plans" "$TMP/r/docs/ledger/archive"
: > "$TMP/r/docs/plans/p.md"
printf '[a](plans/p.md) [b](../plans/p.md) [c](https://x/y) [d](#h) `[e](plans/q.md)`\n' > "$TMP/r/docs/ledger/TD-001.md"
printf '[a](../plans/p.md) [b](../../plans/p.md#s)\n' > "$TMP/r/docs/ledger/archive/TD-002.md"
out=$(cd "$TMP/r" && dead docs/ledger/TD-001.md docs/ledger/archive/TD-002.md)
[ "$out" = "docs/ledger/TD-001.md:1: plans/p.md
docs/ledger/archive/TD-002.md:1: ../plans/p.md" ] && ok "the checker names exactly the two links one level short" || bad "checker: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
