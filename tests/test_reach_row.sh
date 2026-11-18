#!/usr/bin/env bash
# TD-290 (TD-281 rule 7): the cadence check's `reach` row (check_cadence.py row_reach). A PR whose title
# names a build — an entry **Part of:** a design whose review record has a Reach: line — that changes a
# file a base-tree [far-reaching] glob matches fails while open unless the record's Go by: names a person
# (on the base board's People:); merged, a ⚠. Globs, record and board are read from the base, never the PR.
# Offline: temp git repos with a bare origin; HOME/XDG_CONFIG_HOME are temp; no dates are judged (TD-24).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
python3 -c 'import tomllib' 2>/dev/null || { echo "SKIP: no tomllib (Python < 3.11): the reach row reads na"; echo "0 passed, 0 failed"; exit 0; }

R="$TMP/widgets"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"
mkdir -p "$R/docs/ledger/archive" "$R/docs/reviews" "$R/docs/user_attention" "$R/rules" "$R/src"
printf '# Ledger\n' > "$R/docs/ledger/README.md"; echo a > "$R/rules/core.md"; echo b > "$R/src/app.py"
printf '[far-reaching]\npaths = ["rules/**"]\n' > "$R/docs/cadence.toml"
printf '# Attention\n\nPeople: Alex\n' > "$R/docs/user_attention/README.md"
entry() {   # entry <n> [part of]
  { printf '## TD-%03d: entry %s\n\n**Priority:** Medium\n**Added:** 2026-01-01\n**Status:** Open\n' "$1" "$1"
    [ -n "${2:-}" ] && printf '**Part of:** TD-%03d\n' "$2"
    printf '**Location:** x\n\n**Why:** y\n'
  } > "$R/docs/ledger/TD-$(printf %03d "$1").md"
}
record() {  # record <n> <header lines...>
  local n=$1; shift
  { printf '# Review record: TD-%03d\n\n**Design:** docs/plans/x.md\n**Class:** in-repo\n**Decided:** 2026-01-01\n**Source:** rounds\n' "$n"
    for l in "$@"; do printf '%s\n' "$l"; done
  } > "$R/docs/reviews/TD-$(printf %03d "$n").md"
}
entry 1; entry 2 1; entry 3 4; entry 5 6; entry 7 8; entry 9; entry 10 11
record 1 "**Reach:** routine — r" "**Go by:** judge"
record 6 "**Reach:** far-reaching — r" "**Go by:** Alex"
record 8 "**Reach:** routine — r" "**Go by:** Bob"
record 11 "**Go by:** judge"
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null

row() {  # $1 = state (open|merged), $2 = the PR title: the reach row on HEAD
  python3 - "$R" "$1" "$2" "$S" <<'EOF'
import sys
root, state, title, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
base = C.git(["rev-parse", "origin/main"], cwd=root).strip()
rng = f"{sha}^..{sha}" if state == "merged" else f"{base}..{sha}"
files = sorted(set(C.git(["diff", "--name-only", rng], cwd=root).split()))
pr = {"state": state, "head_sha": sha, "merge_sha": sha, "files": files, "title": title}
r = C.row_reach(pr, root)
print(r["status"], r["detail"])
EOF
}
topic() { git -C "$R" switch -q -C topic origin/main; }
commit() { git -C "$R" add -A; git -C "$R" commit -qm "${1:-change}"; }
st_is() { [ "${2%% *}" = "$1" ]; }

topic; echo x >> "$R/rules/core.md"; commit
st=$(row open "a change with no entry"); st_is na "$st" && ok "1 a title naming no entry: na" || bad "1: $st"
st=$(row open "TD-002: x"); st_is fail "$st" && grep -q "rules/core.md far-reaching" <<< "$st" && grep -q "design TD-001's Go is by judge" <<< "$st" \
  && ok "2 a build of a design whose Go was the judge's, changing a far-reaching path, open: fail" || bad "2: $st"
st=$(row open "TD-009: x"); st_is na "$st" && grep -q "TD-009 is part of no design" <<< "$st" && ok "3 an entry that is part of no design: na" || bad "3: $st"
st=$(row open "TD-003: x"); st_is na "$st" && grep -q "design TD-004 has no review record" <<< "$st" && ok "4 a design with no record: na" || bad "4: $st"
st=$(row open "TD-010: x"); st_is na "$st" && grep -q "no Reach: line (it predates TD-281)" <<< "$st" && ok "5 a record with no Reach: line is not checked: na" || bad "5: $st"
st=$(row open "TD-005: x"); st_is pass "$st" && grep -q "Go is by Alex" <<< "$st" && ok "6 Go by a person on People:: pass" || bad "6: $st"
st=$(row open "TD-007: x"); st_is fail "$st" && grep -q "Bob, who is not on the board's People: (Alex)" <<< "$st" && ok "7 Go by a name not on People:: fail" || bad "7: $st"
st=$(row open "TD-005, TD-002: x"); st_is fail "$st" && ok "8 two builds named, one with the judge's Go: fail" || bad "8: $st"

topic; echo y >> "$R/src/app.py"; commit
st=$(row open "TD-002: x"); st_is na "$st" && grep -q "changes no far-reaching path" <<< "$st" && ok "9 a build changing no far-reaching path: na" || bad "9: $st"

# the base, never the PR: a PR dropping the table, or rewriting its design's Go by:, is still judged by the base
topic; echo x >> "$R/rules/core.md"; printf '' > "$R/docs/cadence.toml"; sed -i 's/^\*\*Go by:\*\* judge$/**Go by:** Alex/' "$R/docs/reviews/TD-001.md"; commit
st=$(row open "TD-002: x"); st_is fail "$st" && grep -q "Go is by judge" <<< "$st" && ok "10 the globs and the record are read from the base, not the PR's edit of them" || bad "10: $st"
topic; printf '[far-reaching]\npaths = ["src/**"]\n' > "$R/docs/cadence.toml"; echo z >> "$R/src/app.py"; commit
st=$(row open "TD-002: x"); st_is na "$st" && ok "11 a PR adding a glob that matches its own file is not judged by it" || bad "11: $st"

# the build's entry as the PR leaves it: archived by the PR, still found
topic; echo x >> "$R/rules/core.md"; git -C "$R" mv docs/ledger/TD-002.md docs/ledger/archive/TD-002.md; commit
st=$(row open "TD-002: x"); st_is fail "$st" && ok "12 a build the PR archives is still read (its archive copy)" || bad "12: $st"

# merged: a ⚠, never a fail
topic; echo x >> "$R/rules/core.md"; commit
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic >/dev/null 2>&1; git -C "$R" commit -qm "TD-002 (#3)"
st=$(row merged "TD-002: x"); st_is pass "$st" && grep -q "⚠" <<< "$st" && grep -q "merged" <<< "$st" && ok "13 merged: a pass with a ⚠" || bad "13: $st"
git -C "$R" reset -q --hard origin/main

# Go by pending, or no Go by: line, is not a person's
sed -i 's/^\*\*Go by:\*\* Bob$/**Go by:** pending/' "$R/docs/reviews/TD-008.md"; sed -i '/^\*\*Go by:\*\*/d' "$R/docs/reviews/TD-006.md"; commit; git -C "$R" push -q origin main 2>/dev/null
topic; echo x >> "$R/rules/core.md"; commit
st=$(row open "TD-007: x"); st_is fail "$st" && grep -q "Go is by pending" <<< "$st" && ok "14 Go by: pending: fail" || bad "14: $st"
st=$(row open "TD-005: x"); st_is fail "$st" && grep -q "no Go by: line" <<< "$st" && ok "15 no Go by: line: fail" || bad "15: $st"

# no board People: line at the base: a person's name passes with a ⚠
git -C "$R" switch -q main; sed -i 's/^\*\*Go by:\*\* pending$/**Go by:** Bob/' "$R/docs/reviews/TD-008.md"; printf '# Attention\n' > "$R/docs/user_attention/README.md"; commit; git -C "$R" push -q origin main 2>/dev/null
topic; echo x >> "$R/rules/core.md"; commit
st=$(row open "TD-007: x"); st_is pass "$st" && grep -q "no board People: line" <<< "$st" && ok "16 no People: line at the base: Go by a name passes, with a ⚠" || bad "16: $st"

# no [far-reaching] at the base: na
git -C "$R" switch -q main; git -C "$R" rm -q docs/cadence.toml; commit; git -C "$R" push -q origin main 2>/dev/null
topic; echo x >> "$R/rules/core.md"; commit
st=$(row open "TD-002: x"); st_is na "$st" && grep -q "nothing is far-reaching here" <<< "$st" && ok "17 no docs/cadence.toml at the base: na" || bad "17: $st"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
