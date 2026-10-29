#!/usr/bin/env bash
# The README's SYNC and SEED rows must list exactly the files sync.sh installs.
#
# WHY THIS IS A TEST AND NOT A CONVENTION
# ---------------------------------------
# It had already drifted by five entries before anyone noticed — generate_workspace.sh,
# open_worktree.sh, reap_worktrees.sh, git-hooks/post-merge and the attention skill
# were all in SYNC_FILES and absent from the table — and it was found by a reviewer
# reading the table against sync.sh by hand, not by anything that runs. A table
# that lists what a tool installs is a claim about that tool, and cadence.md §7
# says a claim nothing checks is a claim that rots. Adding a SYNC file is exactly
# the moment the table goes stale, and exactly the moment nobody is thinking
# about the README.
#
# Deliberately basename-only: the table is prose for humans, so it writes
# `git-hooks/pre-push` and `check_anchor.py` rather than full `scripts/` paths,
# and pinning the exact rendering would make the test a formatting police
# officer instead of a completeness check.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Isolation (TD-046): never read the real ~/.gitconfig or ~/.config — a global
# init.templateDir or core.hooksPath would otherwise leak into every fixture.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# The SYNC_FILES array as sync.sh actually defines it, read from the source of
# truth rather than restated here — a second hand-maintained list would have the
# same rot problem this test exists to catch.
mapfile -t sync_files < <(
    awk '/^SYNC_FILES=\(/{f=1; next} f && /^\)/{exit} f {gsub(/[" \t]/,""); if ($0 != "") print}' sync.sh
)

if [ "${#sync_files[@]}" -eq 0 ]; then
    bad "could not parse SYNC_FILES out of sync.sh — this test is not checking anything"
else
    ok "parsed ${#sync_files[@]} SYNC files from sync.sh"
fi

# Both rows, both directions, exact tokens (TD-046). The old check was a substring
# match of each SYNC basename against the SYNC row: it could not see a retired file
# still listed, the SEED row at all, or `cadence.md` satisfied by `docs/cadence.md`
# when only `cadence-changes.md` was meant. A row's files are its backticked tokens;
# a token may drop a leading `scripts/` or `docs/` (the table is prose). Skills are
# named in "a + b + c skills" (one name covers its .claude and .agents pointers), and
# "<x>.md + archive" names <x>_archive.md.
check_row() { # $1 class (SYNC|SEED), $2 array name in sync.sh
    local out
    out=$(python3 - "$1" "$2" <<'PY2'
import re, sys
cls, arr = sys.argv[1], sys.argv[2]
src = open("sync.sh").read()
m = re.search(rf"^{arr}=\((.*?)^\)", src, re.S | re.M)
files = re.findall(r'"([^"]+)"', m.group(1)) if m else []
row = next((l for l in open("README.md") if l.startswith(f"| {cls} |")), None)
if not files or row is None:
    print(f"ERR could not read {arr} from sync.sh or the | {cls} | row"); sys.exit()
cells = row.split("|")
listed = cells[3] if len(cells) > 3 else ""
tokens = re.findall(r"`([^`]+)`", listed)
sk = re.search(r"([\w-]+(?:\s*\+\s*[\w-]+)*)\s+skills?\b", re.sub(r"`[^`]*`", "", listed))
skills = set(re.split(r"\s*\+\s*", sk.group(1))) if sk else set()
archived = {t[:-3] + "_archive.md" for t in re.findall(r"`([^`]+\.md)`\s*\+\s*archive", listed)}
def forms(f):
    out = {f}
    for pre in ("scripts/", "docs/"):
        if f.startswith(pre):
            out.add(f[len(pre):])
    return out
missing, used = [], set()
for f in files:
    sm = re.match(r"\.(claude|agents)/skills/([^/]+)/SKILL\.md$", f)
    if sm:   # an .agents pointer (TD-127) also needs the row to say the set exists
        ok = sm.group(2) in skills and (sm.group(1) == "claude" or ".agents/skills" in listed)
        (used.add("skill:" + sm.group(2)) if ok else missing.append(f))
        continue
    hit = [t for t in tokens if t in forms(f)]
    if hit:
        used.update(hit)
    elif any(forms(f) & {a, "docs/" + a} for a in archived):
        pass
    else:
        missing.append(f)
extra = [t for t in tokens if t not in used] + [s for s in skills if "skill:" + s not in used]
print("MISSING " + " ".join(missing) if missing else "OK-FWD")
print("EXTRA " + " ".join(extra) if extra else "OK-REV")
PY2
)
    case "$out" in ERR*) bad "$out"; return ;; esac
    grep -qx "OK-FWD" <<< "$out" && ok "README $1 row lists every file in sync.sh's $2" \
        || bad "README $1 row is missing: $(grep ^MISSING <<< "$out" | cut -d' ' -f2-)"
    grep -qx "OK-REV" <<< "$out" && ok "README $1 row lists nothing that is not in $2" \
        || bad "README $1 row lists files not in $2 (retired, or the wrong class): $(grep ^EXTRA <<< "$out" | cut -d' ' -f2-)"
}
check_row SYNC SYNC_FILES
# RETIRED (TD-057): the row lists exactly RETIRED_FILES; while that array is empty the row
# lists no file at all.
ret=$(python3 - <<'PY3'
import re
src = open("sync.sh").read()
m = re.search(r"^RETIRED_FILES=\((.*?)^\)", src, re.S | re.M)
row = next((l for l in open("README.md") if l.startswith("| RETIRED |")), None)
if m is None or row is None:
    print("ERR"); raise SystemExit
files = sorted(re.findall(r'"([^"]+)"', m.group(1)))
listed = sorted(re.findall(r"`([^`]+)`", row.split("|")[3]))
short = sorted(f.split("/", 1)[1] if f.startswith(("scripts/", "docs/")) else f for f in files)
print("OK" if listed in (files, short) else f"DIFF files={files} row={listed}")
PY3
)
[ "$ret" = OK ] && ok "README RETIRED row lists exactly sync.sh's RETIRED_FILES" || bad "README RETIRED row: $ret"
check_row SEED SEED_FILES

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
