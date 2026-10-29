#!/usr/bin/env bash
# TD-060: the TD archive only grows, and no id ever leaves the ledger ∪ archive (cadence §2:
# a resolved entry MOVES). Twice an archiving script opened the archive for writing before
# reading it and truncated it to one entry (PR #106, PR #112's first draft); both times
# only a lucky citation in another suite noticed. This is that check, on purpose.
#
# A gate on the index (§7): it compares committed state at the merge-base with origin's
# default branch against this checkout's files — the merge-base, not origin's tip, so an
# entry archived on main after this branch was cut is not a false failure here.
# Offline: `git show` reads local objects only. HOME is a temp dir.
#
# A deliberate RENUMBER (an entry that took a colliding id is given the next free one) reads
# here as that id leaving the ledger — expected, and the PR says so; nothing else should.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
LEDGER=docs/technical_debt.md; ARCHIVE=docs/technical_debt_archive.md; LEDGER_DIR=docs/ledger
# flatten <out ledger> <out archive> [<commit>]: either layout — the v1 pair, or the v2 directory (TD-160:
# one TD-NNN.md per entry, archived ones under archive/) — as v1-shaped text, so the checks below read
# both and a split is judged like any other change. A v2 ledger stores no table, so its flat text gets
# one generated from its entries (the table check then holds trivially there, as it should).
flatten() {
    local out_l=$1 out_a=$2 at=${3:-} f
    : > "$out_l"; : > "$out_a"
    if [ -n "$at" ]; then
        if git -C "$DC" cat-file -e "$at:$LEDGER_DIR" 2>/dev/null; then
            for f in $(git -C "$DC" ls-tree --name-only "$at" "$LEDGER_DIR/" | grep -E '/TD-[0-9]+\.md$'); do git -C "$DC" show "$at:$f"; echo; done > "$out_l"
            for f in $(git -C "$DC" ls-tree --name-only "$at" "$LEDGER_DIR/archive/" | grep -E '/TD-[0-9]+\.md$'); do git -C "$DC" show "$at:$f"; echo; done > "$out_a"
        else
            git -C "$DC" show "$at:$LEDGER" > "$out_l" 2>/dev/null; git -C "$DC" show "$at:$ARCHIVE" > "$out_a" 2>/dev/null
            return 0
        fi
    elif [ -d "$DC/$LEDGER_DIR" ]; then
        for f in "$DC/$LEDGER_DIR"/TD-*.md; do [ -e "$f" ] && { cat "$f"; echo; }; done > "$out_l"
        for f in "$DC/$LEDGER_DIR"/archive/TD-*.md; do [ -e "$f" ] && { cat "$f"; echo; }; done > "$out_a"
    else
        cp "$DC/$LEDGER" "$out_l" 2>/dev/null; cp "$DC/$ARCHIVE" "$out_a" 2>/dev/null
        return 0
    fi
    { grep -oE '^## TD-[0-9]+' "$out_l" | sed 's/^## \(.*\)/| \1 | (v2) | - | - |/'; echo; cat "$out_l"; } > "$out_l.t" && mv "$out_l.t" "$out_l"
}

# check <base ledger> <base archive> <ledger> <archive>: prints PASS/FAIL lines
check() {
    python3 - "$@" <<'PY'
import re, sys
def read(p):
    try:
        return open(p, encoding="utf-8").read()
    except OSError:
        return ""
def heads(text):   # every `## TD-N:` heading, as ints (TD-36 and TD-036 are one id)
    return {int(n) for n in re.findall(r"^## TD-0*(\d+):", text, re.M)}
def bodies(text):  # id -> the entry's text, heading to the next `## ` heading
    parts = re.split(r"^(?=## )", text, flags=re.M)
    return {int(m.group(1)): p for p in parts if (m := re.match(r"## TD-0*(\d+):", p))}
def rows(text):    # the summary table's ids
    return {int(n) for n in re.findall(r"^\| TD-0*(\d+) \|", text, re.M)}
bl, ba, l, a = (read(p) for p in sys.argv[1:5])
out = []
lost = sorted(heads(ba) - heads(a))
out.append(("PASS: every archived entry at the base is still in the archive" if not lost else
            f"FAIL: the archive lost {len(lost)} entr{'y' if len(lost) == 1 else 'ies'}: "
            + ", ".join(f"TD-{n}" for n in lost[:12]) + (" …" if len(lost) > 12 else "")))
gone = sorted((heads(bl) | heads(ba)) - (heads(l) | heads(a)))
out.append(("PASS: no id left ledger ∪ archive" if not gone else
            "FAIL: ids gone from both ledger and archive: " + ", ".join(f"TD-{n}" for n in gone)))
# an archived entry may be corrected, never gutted: under half its text at the base fails
# (a truncation that kept the headings and lost the bodies passed the heading check)
was, now = bodies(ba), bodies(a)
shrunk = sorted(n for n in was if n in now and len(now[n].strip()) < len(was[n].strip()) / 2)
out.append(("PASS: no archived entry lost more than half its text" if not shrunk else
            "FAIL: archived entries gutted (under half their text at the base): " + ", ".join(f"TD-{n}" for n in shrunk)))
both = sorted(heads(l) & heads(a))
out.append(("PASS: no entry is in both the ledger and the archive" if not both else
            "FAIL: in both ledger and archive (half a move): " + ", ".join(f"TD-{n}" for n in both)))
body, table = heads(l), rows(l)
out.append(("PASS: the ledger's table lists exactly the entries with a body (§2)" if body == table else
            "FAIL: ledger table vs bodies — rows without a body: "
            + (", ".join(f"TD-{n}" for n in sorted(table - body)) or "none")
            + "; bodies without a row: " + (", ".join(f"TD-{n}" for n in sorted(body - table)) or "none")))
print("\n".join(out))
PY
}
tally() { while IFS= read -r l; do case "$l" in PASS:*) ok "${l#PASS: }";; FAIL:*) bad "${l#FAIL: }";; esac; done; }

# --- 1) this checkout against its merge-base with origin's default branch
ref=$(git -C "$DC" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
base=$(git -C "$DC" merge-base HEAD "$ref" 2>/dev/null)
if [ -z "$base" ]; then
    echo "SKIP: no merge-base with $ref here (no origin, or a shallow clone) — the archive check did not run"
    [ -n "${CI:-}" ] && FAIL=$((FAIL+1))
else
    flatten "$TMP/bl" "$TMP/ba" "$base"; flatten "$TMP/cl" "$TMP/ca"
    # a v2 archive may hold no entry yet (a repo seeded at a cut-over, TD-190): its directory is read
    { [ -s "$TMP/ba" ] || git -C "$DC" cat-file -e "$base:$LEDGER_DIR/archive" 2>/dev/null; } \
        && ok "read the base's archive ($(grep -c '^## TD-' "$TMP/ba") entries at ${base:0:7})" || bad "could not read the archive at the base"
    tally < <(check "$TMP/bl" "$TMP/ba" "$TMP/cl" "$TMP/ca")
fi

# --- 2) the check itself catches the failures it exists for (fixtures from this checkout)
flatten "$TMP/l" "$TMP/a"
if [ "$(grep -c '^## TD-' "$TMP/a")" -lt 2 ]; then   # an archive with under two entries: two of the test's own
    for n in 9001 9002; do printf '## TD-%s: a fixture entry\n\n**Status:** Resolved\n\n**Why:** text enough that gutting it shows, as an archived entry'"'"'s Why does.\n\n' "$n"; done >> "$TMP/a"
fi
awk '/^## TD-/{n++} n<=1' "$TMP/a" > "$TMP/a.trunc"                  # truncated to one entry
check "$TMP/l" "$TMP/a" "$TMP/l" "$TMP/a.trunc" | grep -q "^FAIL: the archive lost" && ok "a truncated archive fails" || bad "truncation not caught"
first=$(grep -m1 -o '^## TD-[0-9]*' "$TMP/l" | cut -c4-)            # a live entry deleted, not moved
firstn="TD-$((10#${first#TD-}))"   # as the check prints it: TD-065 is TD-65 (TD-36 and TD-036 are one id)
python3 - "$TMP/l" "$first" <<'PY' > "$TMP/l.del"
import re, sys
t = open(sys.argv[1]).read(); tid = sys.argv[2]
t = re.sub(rf"^## {tid}:.*?(?=^## |\Z)", "", t, flags=re.S | re.M)
print(re.sub(rf"^\| {tid} \|.*\n", "", t, flags=re.M), end="")
PY
check "$TMP/l" "$TMP/a" "$TMP/l.del" "$TMP/a" | grep -q "^FAIL: ids gone from both ledger and archive: $firstn" \
    && ok "a live entry deleted instead of moved fails ($first)" || bad "deleted entry not caught ($first)"
grep -E '^#{1,2} ' "$TMP/a" > "$TMP/a.gutted"                     # every heading kept, every body gone
check "$TMP/l" "$TMP/a" "$TMP/l" "$TMP/a.gutted" > "$TMP/g.out"
grep -q "^FAIL: archived entries gutted" "$TMP/g.out" && ! grep -q "^FAIL: the archive lost" "$TMP/g.out" \
    && ok "headings kept, bodies gone: fails on the body check (the heading check alone passed it)" || bad "gutted archive not caught: $(cat "$TMP/g.out")"
grep -v "^| $first |" "$TMP/l" > "$TMP/l.norow"                    # a body with no table row
check "$TMP/l" "$TMP/a" "$TMP/l.norow" "$TMP/a" | grep -q "^FAIL: ledger table vs bodies .*bodies without a row: $firstn" \
    && ok "a body without a table row fails" || bad "missing row not caught"
{ cat "$TMP/a"; echo; sed -n "/^## $first:/,/^## /p" "$TMP/l" | sed '$d'; } > "$TMP/a.both"   # copied, not moved
check "$TMP/l" "$TMP/a" "$TMP/l" "$TMP/a.both" | grep -q "^FAIL: in both ledger and archive (half a move): $firstn" \
    && ok "an entry copied to the archive but left in the ledger fails" || bad "half a move not caught"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
