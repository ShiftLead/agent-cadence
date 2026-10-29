#!/usr/bin/env bash
# The techlead primer (docs/briefs/techlead-context.md) is an index: every path and every
# ledger id it names must exist, or it misdirects a cold reader who has nothing else.
#
# WHY THIS IS A TEST AND NOT A CONVENTION
# ---------------------------------------
# The primer is read on every fill of the techlead seat and is never cited as a source —
# it points, and the pointed-at document is what gets cited. A pointer to a file that was
# renamed or a TD that was archived and renumbered fails silently: the techlead searches,
# finds nothing, and answers from the asker's framing instead, which is the exact failure
# the seat exists to prevent. A consumer guards its primer the same way (its tests/test_briefs_primer.py).
#
# Also checks that every brief docs/briefs/README.md lists is present, so a team definition
# that names one cannot point at nothing.
#
# Held to: backticked tokens that look like repo paths (contain a `/` or end in .md/.sh/.py/.toml),
# and every TD-NNN token. Prose is not checked — that is a person reading it.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# a published snapshot (snapshot_public.sh's README note, TD-090) carries none of this repo's own docs/,
# CLAUDE.md or .claude/: there a dogfood check whose file is absent is not run, said; here it always runs
snapshot() { grep -q '^> \*dev-cadence, published as agent-cadence\.\*' "$1/README.md"; }
PRIMER=docs/briefs/techlead-context.md
if [ ! -e docs ] && snapshot "$ROOT"; then echo "NOTE: a published snapshot has no docs/briefs/ — the primer check is this repo's own, not run"; echo "---- 0 passed, 0 failed"; exit 0; fi
[ -f "$PRIMER" ] || { bad "$PRIMER missing"; echo "---- $PASS passed, $FAIL failed"; exit 1; }

# --- paths -------------------------------------------------------------------
# A path "exists" when the INDEX has it (TD-081): this test fails the suite, so it is a
# gate, and a gate judges the index, not the disk (cadence.md §7.12). With `[ -e ]` a
# path present only as an untracked or gitignored file in the checkout running the suite
# passed locally and failed in CI's fresh clone (PR #202, `.claude/settings.local.json`).
# $1 = repo-relative path (file or directory), $2 = repo (default: here)
in_index() {
    # --literal-pathspecs: a token is a name, never a glob — `docs/br*` must not pass
    # because something matches it.
    git -C "${2:-.}" --literal-pathspecs ls-files --error-unmatch -- "$1" >/dev/null 2>&1 && return 0
    [ -n "$(git -C "${2:-.}" --literal-pathspecs ls-files -- "$1/" 2>/dev/null | head -1)" ]
}
# Backticked tokens; keep those that read as a repo-relative path. Strip a trailing
# `/**`, `/`, or `/*.sh` glob so a directory reference is checked as the directory.
# check_paths <primer> [<repo>] -> sets `missing` and `checked`. A function so the fixture
# case below runs the SAME loop: pinning in_index alone would leave the loop free to go
# back to the disk.
check_paths() {
missing=""; checked=0
local tok p
while IFS= read -r tok; do
    case "$tok" in
        ~*|/*|\$*|*'<'*|*' '*) continue ;;                 # home/absolute/env/placeholder/prose
    esac
    case "$tok" in
        */*|*.md|*.sh|*.py|*.toml) ;;
        *) continue ;;
    esac
    # Named on purpose although absent here: a consumer-side path (where the payload lands),
    # a directory the primer says this repo does NOT have, or a gitignored path.
    case "$tok" in
        docs/cadence-sync.lock|.claude/settings.json|scripts/|'scripts/…'|scripts/reap_worktrees.sh) continue ;;   # consumer-side
        docs/decisions/|.github/) continue ;;                                             # named as absent
        __pycache__/) continue ;;                                                         # gitignored
    esac
    p="${tok%/\*\*}"; p="${p%/\*.sh}"; p="${p%/}"
    checked=$((checked+1))
    in_index "$p" "${2:-.}" || missing+=" $tok"
done < <(grep -o '`[^`]*`' "$1" | tr -d '`' | sort -u)
}
check_paths "$PRIMER"
if [ "$checked" -eq 0 ]; then
    bad "no path tokens found in $PRIMER — the check is not checking anything"
elif [ -z "$missing" ]; then
    ok "every one of $checked path tokens in the primer exists"
else
    bad "primer names paths that do not exist:$missing"
fi

# The index, not the disk, on a fixture: an untracked file and an untracked directory are
# absent however present they are on disk; a tracked file and a directory holding one pass.
FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
git init -q "$FX" && mkdir -p "$FX/tracked_dir" "$FX/loose_dir" \
    && echo t > "$FX/tracked.md" && echo t > "$FX/tracked_dir/a.sh" \
    && echo u > "$FX/untracked.md" && echo u > "$FX/loose_dir/b.sh" \
    && git -C "$FX" add tracked.md tracked_dir
if in_index tracked.md "$FX" && in_index tracked_dir "$FX" \
   && ! in_index untracked.md "$FX" && ! in_index loose_dir "$FX" && ! in_index nowhere.md "$FX" \
   && ! in_index 'tracked*' "$FX" && ! in_index 'tracked_di' "$FX"; then
    ok "a path counts only when the index has it: an untracked file or directory, a glob and a name's prefix do not"
else
    bad "in_index misjudged the fixture (tracked/untracked file or directory, glob, prefix)"
fi
# …and the loop itself, on a primer of the fixture's own: only the untracked names are missing.
printf 'see `tracked.md`, `tracked_dir/`, `tracked_dir/a.sh`, `untracked.md` and `loose_dir/b.sh`\n' > "$FX/primer.txt"
check_paths "$FX/primer.txt" "$FX"
if [ "$checked" -eq 5 ] && [ "$missing" = " loose_dir/b.sh untracked.md" ]; then
    ok "the paths loop reports exactly the untracked names of a fixture primer"
else
    bad "the paths loop misjudged the fixture primer: checked=$checked missing=[$missing]"
fi

# --- ledger ids ----------------------------------------------------------------
# A TD is "known" when its heading exists in the live ledger or the archive, or — for the
# unpadded pre-2026-08 ids (TD-7, TD-16, TD-24) — when either file mentions it at all.
# TD-037 is reserved, not filed (see the note in the ledger's README), so it is accepted
# when that note names it.
# The ledger is the directory docs/ledger/ since TD-160's split (2026-10-28): its entries, its archive/
# and its README (where the retired-number notes now live); before it, the v1 pair.
if [ -d docs/ledger ]; then LEDGERS=(-r docs/ledger); else LEDGERS=(docs/technical_debt.md docs/technical_debt_archive.md); fi
# a repo seeded at a cut-over (TD-190) names, in its archive's README, the last id whose entry is
# kept in the private history it was seeded from: an id up to it is known, its entry there
floor=$(sed -n 's/^\*\*Private through:\*\* TD-\([0-9]*\).*/\1/p' docs/ledger/archive/README.md 2>/dev/null | head -1)
unknown=""; ids=0
while IFS= read -r id; do
    ids=$((ids+1))
    if [ -n "$floor" ] && [ "$((10#${id#TD-}))" -le "$((10#$floor))" ]; then continue; fi
    if grep -qE "^## $id:" "${LEDGERS[@]}"; then continue; fi
    if grep -qE "\b$id\b" "${LEDGERS[@]}"; then continue; fi
    unknown+=" $id"
done < <(grep -oE 'TD-[0-9]+' "$PRIMER" | sort -u)
if [ "$ids" -eq 0 ]; then
    bad "no TD ids found in $PRIMER — the check is not checking anything"
elif [ -z "$unknown" ]; then
    ok "every one of $ids ledger ids in the primer is in the ledger or the archive"
else
    bad "primer cites ids found in neither ledger nor archive:$unknown"
fi

# --- the briefs the README lists -------------------------------------------------
listed=0; absent=""
while IFS= read -r f; do
    listed=$((listed+1))
    [ -f "docs/briefs/$f" ] || absent+=" $f"
done < <(grep -oE '^\| `[^`]+\.md` \|' docs/briefs/README.md | grep -oE '[^`]+\.md')
if [ "$listed" -eq 0 ]; then
    bad "docs/briefs/README.md lists no briefs — the check is not checking anything"
elif [ -z "$absent" ]; then
    ok "every brief the README lists ($listed) is present"
else
    bad "README lists briefs that do not exist:$absent"
fi

# --- placeholders -------------------------------------------------------------
# The launcher fills exactly {lane}, {techlead} and {context}; any other {word} in a brief
# ships literally. A stray one is a typo that reaches a session as-is.
stray=""
for b in docs/briefs/manager-dc-1.md docs/briefs/grinder-dc-1.md; do
    s="$(grep -oE '\{[a-z_]+\}' "$b" | grep -vE '^\{(lane|techlead|context)\}$' | sort -u | tr '\n' ' ')"
    [ -z "$s" ] || stray+=" $b:$s"
done
if [ -z "$stray" ]; then
    ok "briefs use only the three placeholders the launcher fills"
else
    bad "briefs carry placeholders the launcher will not fill:$stray"
fi

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
