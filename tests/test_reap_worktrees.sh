#!/usr/bin/env bash
# reap_worktrees.sh — the most destructive script this repo ships.
#
# Every case here exists because something failed toward DELETION during review,
# or because a reviewer had to re-derive that it doesn't. The asymmetry is the
# whole point: a false "keep" costs disk, a false "REAPABLE" costs work that was
# never pushed. So each case asserts the verdict AND, for the reap path, that
# the worktree and branch still exist afterwards.
#
# Isolation: HOME points into the tmpdir so the session-registry probe can be
# driven deterministically and never reads the real one. Repos are built with a
# real bare origin, because `landed` is defined against origin/main and a
# fixture without a remote would test a different function.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/reap_worktrees.sh"
ANCHOR="$DC/files/scripts/check_anchor.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/sessions" "$TMP/emptybin"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- fixture ------------------------------------------------------------------
# $1 = repo name. Leaves a repo at $TMP/$1 on main, pushed to its own origin.
mkrepo() {
    local r="$TMP/$1"
    git init -q --bare -b main "$r.git"
    git clone -q "$r.git" "$r" 2>/dev/null
    (
        cd "$r" || exit 1
        git config user.email t@t; git config user.name t
        git checkout -q -b main 2>/dev/null
        mkdir -p scripts
        cp "$ANCHOR" "$DC/files/scripts/agent_sessions.py" "$DC/files/scripts/cadence_config.py" scripts/
        cp "$SCRIPT" reap_worktrees.sh
        echo base > base.txt
        git add .; git commit -qm base; git push -q -u origin main
    )
}

# $1 = repo, $2 = topic, $3.. = shell run inside the worktree
mkwt() {
    local r="$TMP/$1" t="$2"; shift 2
    git -C "$r" worktree add -q -b "$t" "$r/.claude/worktrees/$t" origin/main
    if [ $# -gt 0 ]; then ( cd "$r/.claude/worktrees/$t" && eval "$@" ); fi
}

# $1 = repo, $2 = topic -> squash-merges the topic and pushes, as gh does
squash() {
    local r="$TMP/$1" t="$2"
    ( cd "$r" && git merge -q --squash "$t" && git commit -qm "$t (#1)" && git push -q origin main && git fetch -q origin )
}

# $1 = repo, extra args -> the report line for each worktree
report() { ( cd "$TMP/$1" && shift && ./reap_worktrees.sh "$@" 2>&1 ); }

verdict_for() { grep -E "^  $2 " <<< "$1" | head -1; }

# --- 1. unlanded work is never reaped ----------------------------------------
mkrepo r1
mkwt r1 unlanded 'echo work >> base.txt; git commit -qam "real work"'
out=$(report r1 --reap)
if grep -q "landed=no" <<< "$(verdict_for "$out" unlanded)" && [ -d "$TMP/r1/.claude/worktrees/unlanded" ]; then
    ok "unlanded branch: landed=no and survives --reap"
else
    bad "unlanded branch was misjudged: $(verdict_for "$out" unlanded)"
fi

# --- 2. squash-merged work IS reaped (ancestry would say unmerged) -----------
mkrepo r2
mkwt r2 landed 'echo work >> base.txt; git commit -qam "real work"'
squash r2 landed
out=$(report r2)
if grep -q "landed=yes" <<< "$(verdict_for "$out" landed)"; then
    ok "squash-merged branch: landed=yes despite ancestry saying otherwise"
else
    bad "squash-merged branch not detected as landed: $(verdict_for "$out" landed)"
fi
out=$(report r2 --reap)
if [ ! -d "$TMP/r2/.claude/worktrees/landed" ] && ! git -C "$TMP/r2" show-ref --verify --quiet refs/heads/landed; then
    ok "--reap removes the worktree and deletes the branch"
else
    bad "--reap did not clean up a landed worktree"
fi

# --- 2b. the per-topic workspace file goes with the worktree ------------------
# It lives at the CLONE ROOT, not inside the tree, so `git worktree remove` does
# not take it. Left behind it is a workspace whose every root is a dead path,
# and it is gitignored, so nothing else would ever report it.
mkrepo r2b
mkwt r2b landed2 'echo work >> base.txt; git commit -qam work; git push -q -u origin landed2'
squash r2b landed2
: > "$TMP/r2b/landed2.code-workspace"
: > "$TMP/r2b/unrelated.code-workspace"
report r2b --reap >/dev/null
if [ ! -e "$TMP/r2b/landed2.code-workspace" ]; then
    ok "--reap deletes the reaped topic's workspace file"
else
    bad "--reap left a workspace file pointing at a removed worktree"
fi
# Scoped to the topic it removed: the overview file and other topics' files are
# not this loop iteration's business.
if [ -e "$TMP/r2b/unrelated.code-workspace" ]; then
    ok "--reap leaves other topics' workspace files alone"
else
    bad "--reap deleted a workspace file belonging to another topic"
fi

# --- 3. a branch with no commits is 'empty', never 'landed' ------------------
# Regression: an early build marked freshly-created worktrees REAPABLE, because
# a branch that touches nothing has an empty diff from its merge-base.
mkrepo r3
mkwt r3 fresh
out=$(report r3 --reap)
if grep -q "landed=empty" <<< "$(verdict_for "$out" fresh)" && [ -d "$TMP/r3/.claude/worktrees/fresh" ]; then
    ok "brand-new branch: landed=empty and survives --reap"
else
    bad "brand-new branch misjudged: $(verdict_for "$out" fresh)"
fi

# --- 4. spaced filenames must not word-split into a false 'landed' -----------
# Regression, HIGH: unquoted $files split on the space, the fragments matched no
# paths, and `git diff --quiet` exits 0 for a pathspec matching nothing — so
# unlanded work reported LANDED and was reaped.
mkrepo r4
mkwt r4 spaced 'mkdir -p "dir with space"; echo secret > "dir with space/my file.txt"; git add .; git commit -qm "spaced work"'
out=$(report r4 --reap)
if grep -q "landed=no" <<< "$(verdict_for "$out" spaced)" && [ -f "$TMP/r4/.claude/worktrees/spaced/dir with space/my file.txt" ]; then
    ok "spaced filename, work absent from origin/main: landed=no and file survives"
else
    bad "spaced-filename branch misjudged: $(verdict_for "$out" spaced)"
fi

# --- 5. untracked scratch blocks reaping even when landed -------------------
mkrepo r5
mkwt r5 scratch 'echo work >> base.txt; git commit -qam "real work"'
squash r5 scratch
echo "unsaved notes" > "$TMP/r5/.claude/worktrees/scratch/NOTES.txt"
out=$(report r5 --reap)
if grep -qE "landed=yes clean=no" <<< "$(verdict_for "$out" scratch)" && [ -f "$TMP/r5/.claude/worktrees/scratch/NOTES.txt" ]; then
    ok "landed + untracked scratch: clean=no, scratch survives --reap"
else
    bad "untracked scratch did not block reaping: $(verdict_for "$out" scratch)"
fi

# --- 6. uncommitted edits block reaping -------------------------------------
mkrepo r6
mkwt r6 dirty 'echo work >> base.txt; git commit -qam "real work"'
squash r6 dirty
echo "edit" >> "$TMP/r6/.claude/worktrees/dirty/base.txt"
out=$(report r6 --reap)
if grep -q "clean=no" <<< "$(verdict_for "$out" dirty)" && [ -d "$TMP/r6/.claude/worktrees/dirty" ]; then
    ok "landed + uncommitted edit: clean=no, worktree survives --reap"
else
    bad "uncommitted edit did not block reaping: $(verdict_for "$out" dirty)"
fi

# --- 7. a live session inside the worktree blocks reaping -------------------
# Registry entry must corroborate: pid alive AND procStart matching /proc, or
# check_anchor drops it as a fossil. Use this shell, whose pid is certainly live.
mkrepo r7
mkwt r7 busy 'echo work >> base.txt; git commit -qam "real work"'
squash r7 busy
ps_start=$(awk '{print $22}' "/proc/$$/stat")
cat > "$HOME/.claude/sessions/$$.json" <<EOF
{"sessionId":"test-session","pid":$$,"cwd":"$TMP/r7/.claude/worktrees/busy","procStart":$ps_start}
EOF
out=$(report r7 --reap)
if grep -q "idle=no" <<< "$(verdict_for "$out" busy)" && [ -d "$TMP/r7/.claude/worktrees/busy" ]; then
    ok "live session cwd inside: idle=no, worktree survives --reap"
else
    bad "live session did not block reaping: $(verdict_for "$out" busy)"
fi

# --- 8. sibling topics whose names prefix each other -------------------------
# The idle check compares realpath'd paths; without trailing-slash anchoring a
# glob would match by prefix alone.
#
# DIRECTION MATTERS. An earlier version of this case put the session in the
# SHORTER name and checked the LONGER one, which cannot collide even with the
# anchor removed (`busy` can never satisfy a pattern demanding the extra `-2`),
# so it stayed green under the very mutation it claimed to pin — a vacuous test
# that manufactured confidence in the fix. The live session must sit in the
# LONGER sibling, so the shorter one's pattern is the one at risk of matching it.
mkwt r7 busy-2 'echo other >> base.txt; git commit -qam "other work"'
rm -f "$HOME/.claude/sessions/$$.json"
cat > "$HOME/.claude/sessions/$$.json" <<EOF
{"sessionId":"test-session","pid":$$,"cwd":"$TMP/r7/.claude/worktrees/busy-2","procStart":$ps_start}
EOF
out=$(report r7)
if grep -q "idle=no" <<< "$(verdict_for "$out" busy-2)" && grep -q "idle=yes" <<< "$(verdict_for "$out" busy)"; then
    ok "prefix-sibling topics: a session in busy-2 does not mark busy non-idle"
else
    bad "prefix collision in idle check: busy=$(verdict_for "$out" busy)"
fi
rm -f "$HOME/.claude/sessions/$$.json"

# --- 9. a locked worktree is never reaped -----------------------------------
mkrepo r9
mkwt r9 locked 'echo work >> base.txt; git commit -qam "real work"'
squash r9 locked
git -C "$TMP/r9" worktree lock --reason "claude session foo (pid 1 start 1)" "$TMP/r9/.claude/worktrees/locked"
out=$(report r9 --reap)
if grep -q "unlocked=no" <<< "$(verdict_for "$out" locked)" && [ -d "$TMP/r9/.claude/worktrees/locked" ]; then
    ok "locked worktree: unlocked=no, survives --reap"
else
    bad "lock did not block reaping: $(verdict_for "$out" locked)"
fi
git -C "$TMP/r9" worktree unlock "$TMP/r9/.claude/worktrees/locked"

# --- 10. an unreadable session registry disables reaping, loudly ------------
# live_sessions() returns [] for a MISSING registry exactly as for an empty one,
# so without this the sole liveness signal vanishes silently.
mkrepo r10
mkwt r10 noreg 'echo work >> base.txt; git commit -qam "real work"'
squash r10 noreg
out=$(HOME="$TMP/nonexistent-home" report r10 --reap)
if grep -q "warn: could not read the live-session registry" <<< "$out" && [ -d "$TMP/r10/.claude/worktrees/noreg" ]; then
    ok "missing session registry: warns and refuses to reap"
else
    bad "missing registry did not disable reaping"
fi

# --- 11. python3 present but failing disables reaping -----------------------
# The heredoc's try/except cannot catch the interpreter itself failing, so this
# pins the `|| LIVE_CWDS=__UNKNOWN__` fallback around the substitution.
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nexit 127\n' > "$TMP/fakebin/python3"; chmod +x "$TMP/fakebin/python3"
out=$( cd "$TMP/r10" && PATH="$TMP/fakebin:$PATH" ./reap_worktrees.sh --reap 2>&1 )
if grep -q "warn: could not read the live-session registry" <<< "$out" && [ -d "$TMP/r10/.claude/worktrees/noreg" ]; then
    ok "python3 fails at runtime: warns and refuses to reap"
else
    bad "python3 runtime failure did not disable reaping"
fi

# --- 11b. python3 absent from PATH entirely --------------------------------
# Distinct branch from 11: this one pins the `command -v python3` guard. Case 11
# leaves a stub ON the PATH, so it never exercises that branch at all.
#
# The PATH must still carry everything else the script shells out to — an empty
# PATH removes `git` too, CLONE_ROOT resolution fails, and the script exits 0
# silently having tested nothing. (It did exactly that on first run here.)
# `env` and `bash` included because the script's own `#!/usr/bin/env bash`
# shebang needs them — without those it never starts, and the case passes or
# fails for reasons having nothing to do with python3.
for c in env bash git realpath grep awk sed basename dirname cat rm; do
    src="$(command -v "$c" 2>/dev/null)" && ln -sf "$src" "$TMP/emptybin/$c"
done
out=$( cd "$TMP/r10" && PATH="$TMP/emptybin" ./reap_worktrees.sh --reap 2>&1 )
if grep -q "warn: could not read the live-session registry" <<< "$out" && [ -d "$TMP/r10/.claude/worktrees/noreg" ]; then
    ok "python3 absent from PATH: warns and refuses to reap"
else
    bad "python3 absence did not disable reaping"
fi

# --- 11c. registry PRESENT but UNREADABLE ----------------------------------
# The nastiest of the three, and the one that reaped a live worktree in review:
# is_dir() only needs the parent searchable, so an unreadable sessions dir
# returns True, and pathlib's glob() swallows the PermissionError and yields
# nothing — live_sessions() then reports an empty registry with no exception.
# Indistinguishable from "nobody is live" unless the probe actually reads it.
mkrepo r11
mkwt r11 unreadable 'echo work >> base.txt; git commit -qam "real work"'
squash r11 unreadable
UNREAD_HOME="$TMP/unreadable-home"
mkdir -p "$UNREAD_HOME/.claude/sessions"
echo '{}' > "$UNREAD_HOME/.claude/sessions/x.json"
chmod 000 "$UNREAD_HOME/.claude/sessions"
out=$(HOME="$UNREAD_HOME" report r11 --reap)
chmod 755 "$UNREAD_HOME/.claude/sessions"
if grep -q "warn: could not read the live-session registry" <<< "$out" && [ -d "$TMP/r11/.claude/worktrees/unreadable" ]; then
    ok "unreadable session registry: warns and refuses to reap"
else
    bad "unreadable registry did not disable reaping: $(verdict_for "$out" unreadable)"
fi

# --- 12. report-only mode never removes anything ----------------------------
mkrepo r12
mkwt r12 reportonly 'echo work >> base.txt; git commit -qam "real work"'
squash r12 reportonly
out=$(report r12)
if grep -q "REAPABLE" <<< "$out" && [ -d "$TMP/r12/.claude/worktrees/reportonly" ]; then
    ok "no --reap: reports REAPABLE but removes nothing"
else
    bad "report-only mode removed something or failed to report"
fi

# --- 12b. moved-away directory reads clean=gone, and is never reaped --------
# TD-27: the only state in the PR #64 review matrix without a regression test.
# `git status` on a moved-out directory FAILS with empty output, which an
# earlier build read as clean=yes; the gone state pins the distinction. The
# branch also degrades to '?' (rev-parse needs the dir), so landed=no gates
# first — the assertion is on the clean field itself, so a landed-gating
# refactor cannot silently lose it.
mkrepo r14
mkwt r14 gone 'echo work >> base.txt; git commit -qam "real work"'
squash r14 gone
mv "$TMP/r14/.claude/worktrees/gone" "$TMP/r14-gone-aside"
out=$(report r14 --reap)
line=$(verdict_for "$out" gone)
if grep -q "clean=gone" <<< "$line" && ! grep -q "REAPABLE" <<< "$line" \
    && git -C "$TMP/r14" show-ref --verify --quiet refs/heads/gone \
    && [ -f "$TMP/r14-gone-aside/base.txt" ]; then
    ok "moved-away dir: clean=gone, kept, branch and moved files survive --reap"
else
    bad "moved-away dir misjudged: $line"
fi

# --- 12c. unknown registry renders idle=?, not a confident idle=yes ---------
# TD-27: reaping is already disabled (case 10 pins that), but the report field
# claimed knowledge the script does not have — the sentinel never matches any
# realpath, so every row read idle=yes.
out=$(HOME="$TMP/nonexistent-home" report r10)
if grep -q "idle=?" <<< "$(verdict_for "$out" noreg)"; then
    ok "unknown registry: report shows idle=? per worktree"
else
    bad "unknown registry still prints a confident idle field: $(verdict_for "$out" noreg)"
fi

# --- 12b. TD-164: the closing line names the command a reader can run ---------
mkrepo r12b
mkwt r12b landed 'echo work >> base.txt; git commit -qam "real work"'
squash r12b landed
out=$(report r12b); pinned=$(CADENCE_REPO_ROOT="$TMP/r12b" report r12b)
if grep -q "— run scripts/reap_worktrees.sh --reap to remove$" <<< "$out" \
   && grep -q "— run dev-cadence run reap_worktrees.sh --reap to remove$" <<< "$pinned"; then
    ok "the closing line: scripts/reap_worktrees.sh in a copy, dev-cadence run reap_worktrees.sh from a pin"
else
    bad "closing line: copy='$(tail -1 <<< "$out")' pinned='$(tail -1 <<< "$pinned")'"
fi

# --- 13. --quiet is silent when nothing is reapable (hook mode) -------------
mkrepo r13
mkwt r13 quiet1 'echo work >> base.txt; git commit -qam "real work"'
out=$(report r13 --quiet)
if [ -z "$out" ]; then
    ok "--quiet with nothing reapable: no output"
else
    bad "--quiet printed when it should be silent: $out"
fi

# --- 14. a nested sibling repo holding unsaved work blocks the reap ----------
# THE REGRESSION THIS COLUMN EXISTS FOR. Every other check votes to reap:
# landed=yes because the home branch did land, clean=yes because the nested
# directory is GITIGNORED in the home repo and `git status` therefore cannot see
# it, idle=yes, unlocked=yes. And `git worktree remove` does not refuse either —
# measured on git 2.39.5, it succeeds and takes the sibling's uncommitted work
# with it, leaving a `prunable` registration behind. Unattended, from the
# post-merge hook. So this case asserts the verdict AND that the file is still
# on disk after a real --reap run.
mkrepo r15
mkrepo r15nested
cp "$DC/files/scripts/hydrate_worktree.sh" "$TMP/r15/scripts/"
(
    cd "$TMP/r15" || exit 1
    printf '/nested\n.claude/worktrees/\n' > .gitignore
    mkdir -p docs && printf 'nested worktree\n' > docs/nested-repos.txt
    git add -A; git commit -qm nestedcfg; git push -q origin main
)
mv "$TMP/r15nested" "$TMP/r15/nested"
mkwt r15 hasnested 'echo work > f.txt; git add f.txt; git commit -qm work'
git -C "$TMP/r15/nested" worktree add -q -b hasnested "$TMP/r15/.claude/worktrees/hasnested/nested"
echo precious > "$TMP/r15/.claude/worktrees/hasnested/nested/precious.txt"
squash r15 hasnested
out=$(report r15 --reap)
line=$(verdict_for "$out" hasnested)
if grep -q "clean=yes" <<< "$line" && grep -q "nested=no" <<< "$line" && grep -q "keep" <<< "$line"; then
    ok "nested unsaved work: clean=yes but nested=no, verdict keep"
else
    bad "nested unsaved work misjudged: $line"
fi
if [ -f "$TMP/r15/.claude/worktrees/hasnested/nested/precious.txt" ]; then
    ok "nested unsaved work survives a real --reap"
else
    bad "--reap DESTROYED uncommitted work in a nested sibling repo"
fi

# --- 15. once the sibling has nothing to lose, the reap proceeds and cleans up -
# The other direction has to work too, or the column is just a permanent block:
# a constellation worktree would never be reapable and the reaper would quietly
# stop doing its job.
rm "$TMP/r15/.claude/worktrees/hasnested/nested/precious.txt"
out=$(report r15 --reap)
if [ ! -d "$TMP/r15/.claude/worktrees/hasnested" ]; then
    ok "nested sibling with nothing unsaved: parent worktree is reaped"
else
    bad "reap did not proceed after the nested sibling was clean: $out"
fi
if ! git -C "$TMP/r15/nested" worktree list | grep -q prunable; then
    ok "reap dehydrated first, so the sibling has no dangling registration"
else
    bad "reap left the sibling with a prunable registration: $(git -C "$TMP/r15/nested" worktree list)"
fi

# --- 16. ignored scratch blocks the reap (TD-054) ---------------------------
# `git status --untracked-files=all` never lists IGNORED paths and `git worktree
# remove` deletes them without --force: reproduced, a worktree whose only
# unsaved file sat under an ignored dir read clean=yes and the file was gone.
# $1 = repo -> a repo whose main ignores the paths the cases below leave behind.
mkrepo_ignoring() {
    mkrepo "$1"
    ( cd "$TMP/$1" && printf 'scratch/\nclone/\n__pycache__/\n.claude/settings.local.json\n.claude/worktrees/\n*.log\n' > .gitignore \
        && git add .gitignore && git commit -qm ignore && git push -q origin main )
}
mkrepo_ignoring r16
mkwt r16 ignscratch 'echo work >> base.txt; git commit -qam "real work"'
squash r16 ignscratch
W="$TMP/r16/.claude/worktrees/ignscratch"
mkdir -p "$W/scratch/deep"; echo "unsaved notes" > "$W/scratch/deep/my notes.txt"
out=$(report r16 --reap)
line=$(verdict_for "$out" ignscratch)
if grep -q "landed=yes clean=no" <<< "$line" && grep -q "keep" <<< "$line" \
    && grep -qF "ignored, would be destroyed: scratch/deep/my notes.txt" <<< "$out" \
    && [ -f "$W/scratch/deep/my notes.txt" ]; then
    ok "ignored scratch: clean=no, the path is named, the file survives --reap"
else
    bad "ignored scratch did not block reaping: $out"
fi

# --- 17. a nested FULL clone blocks the reap, hydrate or not -----------------
# hydrate's nested scan prunes .git directories, so `nested` passes a full
# clone; only `clean` can stop it, and its unpushed commits are the loss.
mkrepo_ignoring r17
cp "$DC/files/scripts/hydrate_worktree.sh" "$TMP/r17/scripts/"
mkwt r17 hasclone 'echo work >> base.txt; git commit -qam "real work"'
squash r17 hasclone
W="$TMP/r17/.claude/worktrees/hasclone"
git init -q "$W/clone"
( cd "$W/clone" && git config user.email t@t && git config user.name t && echo c > c.txt && git add . && git commit -qm unpushed )
out=$(report r17 --reap)
line=$(verdict_for "$out" hasclone)
if grep -q "clean=no" <<< "$line" && grep -q "keep" <<< "$line" \
    && grep -qF "ignored, would be destroyed: clone/" <<< "$out" && [ -d "$W/clone/.git" ]; then
    ok "nested full clone: clean=no, the clone survives --reap"
else
    bad "nested full clone did not block reaping: $out"
fi

# --- 18. a real (divergent) settings.local.json blocks; derived paths do not --
# hydrate refuses to touch a real one because it may be the newer copy, so the
# reaper must not delete it either. A hydrate symlink, __pycache__ and a
# nested worktree (case 15) are derived and must NOT block, or no worktree
# would ever be reapable.
mkrepo_ignoring r18
mkwt r18 settings 'echo work >> base.txt; git commit -qam "real work"'
squash r18 settings
W="$TMP/r18/.claude/worktrees/settings"
mkdir -p "$W/.claude" "$W/src/__pycache__"
echo '{"mine": true}' > "$W/.claude/settings.local.json"
touch "$W/src/__pycache__/m.cpython-311.pyc"
out=$(report r18 --reap)
line=$(verdict_for "$out" settings)
if grep -q "clean=no" <<< "$line" && grep -qF "ignored, would be destroyed: .claude/settings.local.json" <<< "$out" \
    && ! grep -q "__pycache__" <<< "$out" && [ -f "$W/.claude/settings.local.json" ]; then
    ok "real settings.local.json: clean=no and survives; __pycache__ not listed"
else
    bad "real settings.local.json misjudged: $out"
fi
echo '{}' > "$TMP/r18/settings.local.json"
rm "$W/.claude/settings.local.json"; ln -s "$TMP/r18/settings.local.json" "$W/.claude/settings.local.json"
out=$(report r18 --reap)
if [ ! -d "$W" ] && [ -f "$TMP/r18/settings.local.json" ]; then
    ok "symlinked settings + __pycache__ only: reaped, the link's target survives"
else
    bad "derived ignored paths blocked the reap: $out"
fi

# --- 18b. the copy hydrate writes does not block; one with its own content does (TD-080)
# Every hydrated worktree carries a real settings.local.json now, so a copy that
# blocked would make every worktree unreapable. The reaper asks hydrate.
mkrepo_ignoring r18b
cp "$DC/files/scripts/hydrate_worktree.sh" "$TMP/r18b/scripts/"
mkdir -p "$TMP/r18b/.claude"
printf '{"autoMemoryDirectory": "%s/docs/claude-memory", "permissions": {"allow": ["Bash(ls:*)"]}}\n' "$TMP/r18b" > "$TMP/r18b/.claude/settings.local.json"
mkwt r18b own 'echo work >> base.txt; git commit -qam "real work"'
squash r18b own
W="$TMP/r18b/.claude/worktrees/own"
"$TMP/r18b/scripts/hydrate_worktree.sh" "$W" >/dev/null 2>&1
python3 - "$W/.claude/settings.local.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["permissions"]["allow"].append("Bash(rm:*)")
json.dump(d, open(sys.argv[1], "w"))
PY
out=$(report r18b --reap)
if grep -q "clean=no" <<< "$(verdict_for "$out" own)" && grep -qF "ignored, would be destroyed: .claude/settings.local.json" <<< "$out" && [ -f "$W/.claude/settings.local.json" ]; then
    ok "a settings copy holding its own permission: clean=no and survives"
else
    bad "a settings copy with its own content did not block: $out"
fi
"$TMP/r18b/scripts/hydrate_worktree.sh" "$W" >/dev/null 2>&1
[ -f "$W/.claude/settings.local.json" ] && [ ! -L "$W/.claude/settings.local.json" ] || bad "fixture: no copy to reap"
out=$(report r18b --reap)
if [ ! -d "$W" ] && [ -f "$TMP/r18b/.claude/settings.local.json" ]; then
    ok "hydrate's own settings copy does not block: reaped, the main checkout's file survives"
else
    bad "hydrate's settings copy blocked the reap: $out"
fi

# --- 19. more than five blockers: five named, the rest counted ---------------
mkrepo_ignoring r19
mkwt r19 many 'echo work >> base.txt; git commit -qam "real work"'
squash r19 many
for i in 1 2 3 4 5 6 7; do echo x > "$TMP/r19/.claude/worktrees/many/f$i.log"; done
out=$(report r19)
if [ "$(grep -c "ignored, would be destroyed" <<< "$out")" -eq 5 ] && grep -q "and 2 more" <<< "$out"; then
    ok "seven ignored blockers: five named, 'and 2 more'"
else
    bad "blocker list not capped: $out"
fi

# --- 20a. the depth rule is ONE function, verbatim in both scripts (TD-058 parity)
fn() { sed -n '/^nested_depth() {$/,/^}$/p' "$DC/files/scripts/$1"; }
[ -n "$(fn reap_worktrees.sh)" ] && [ "$(fn reap_worktrees.sh)" = "$(fn hydrate_worktree.sh)" ] \
    && ok "nested_depth() is identical in reap_worktrees.sh and hydrate_worktree.sh" || bad "nested_depth() drifted between the two scripts"
cfg="$TMP/nr.txt"
printf '# path mode\nshallow worktree\n' > "$cfg"
[ "$(bash -c "$(fn reap_worktrees.sh)"$'\n'"nested_depth \"\$1\"" _ "$cfg")" = 3 ] && ok "nested_depth: shallow config -> 3 (today's reach)" || bad "depth shallow"
printf 'x worktree\n./a/b/c/d/ worktree  # deep\n' > "$cfg"
[ "$(bash -c "$(fn reap_worktrees.sh)"$'\n'"nested_depth \"\$1\"" _ "$cfg")" = 4 ] && ok "nested_depth: the deepest configured path (./ and trailing / tolerated)" || bad "depth deep"
[ "$(bash -c "$(fn reap_worktrees.sh)"$'\n'"nested_depth \"\$1\"" _ "$TMP/none.txt")" = 3 ] && ok "nested_depth: no config -> 3" || bad "depth none"
printf 'my deep path/a/b/c/d worktree\n' > "$cfg"
[ "$(bash -c "$(fn reap_worktrees.sh)"$'\n'"nested_depth \"\$1\"" _ "$cfg")" = 5 ] && ok "nested_depth: a path with a space counts at its real depth" || bad "depth spaced"

# --- 20. nested-worktree exemption ends exactly where hydrate's scan does ----
# hydrate's find_nested_worktrees is `-maxdepth 4` over `.git` files, i.e. a
# worktree at most 3 directories deep; the reaper exempts the same depth
# (`${#depth} -le 2` slashes). A parity pair: pin both sides of the boundary.
# Deeper than hydrate can see, `nested` reads ok (hydrate never found it), so
# only `clean` stands between the sibling and `git worktree remove`.
for d in "a/b/c" "a/b/c/d"; do
    r="r20$(tr -cd / <<< "$d" | wc -c)"
    mkrepo_ignoring "$r"; mkrepo "${r}sib"
    cp "$DC/files/scripts/hydrate_worktree.sh" "$TMP/$r/scripts/"
    ( cd "$TMP/$r" && printf '/a/\n' >> .gitignore && git commit -qam ign && git push -q origin main )
    mkwt "$r" deep 'echo work >> base.txt; git commit -qam "real work"'
    squash "$r" deep
    git -C "$TMP/${r}sib" worktree add -q -b deep "$TMP/$r/.claude/worktrees/deep/$d"
    out=$(report "$r" --reap)
    if [ "$d" = "a/b/c" ]; then
        if [ ! -d "$TMP/$r/.claude/worktrees/deep" ]; then
            ok "nested worktree 3 deep (hydrate's reach): exempt, dehydrated and reaped"
        else
            bad "nested worktree at hydrate's depth blocked the reap: $out"
        fi
    else
        if grep -qF "ignored, would be destroyed: a/b/c/d/" <<< "$out" && [ -d "$TMP/$r/.claude/worktrees/deep/$d" ]; then
            ok "nested worktree 4 deep (beyond hydrate): blocks, survives --reap"
        else
            bad "nested worktree beyond hydrate's depth was not blocked: $out"
        fi
    fi
done

# --- 20b. configured deeper, both sides reach it: hydrate dehydrates it, the reaper exempts it
r="r20cfg"; d="a/b/c/d"
mkrepo_ignoring "$r"; mkrepo "${r}sib"
cp "$DC/files/scripts/hydrate_worktree.sh" "$TMP/$r/scripts/"
( cd "$TMP/$r" && mkdir -p docs && printf '/a/\n' >> .gitignore && printf '%s worktree\n' "$d" > docs/nested-repos.txt && git add -A && git commit -qm cfg && git push -q origin main )
mkwt "$r" deep 'echo work >> base.txt; git commit -qam "real work"'
squash "$r" deep
git -C "$TMP/${r}sib" worktree add -q -b deep "$TMP/$r/.claude/worktrees/deep/$d"
# unsaved work in it: hydrate must SEE it and refuse, so the reaper keeps the parent — the
# case a one-sided depth drift would destroy (a clean sibling proves nothing)
echo "unsaved" > "$TMP/$r/.claude/worktrees/deep/$d/wip.txt"
out=$(report "$r" --reap)
[ -f "$TMP/$r/.claude/worktrees/deep/$d/wip.txt" ] && grep -q "nested=no" <<< "$out" \
    && ok "a 4-deep configured sibling with unsaved work: hydrate refuses, the reaper keeps it" || bad "unsaved deep: $out"
rm "$TMP/$r/.claude/worktrees/deep/$d/wip.txt"
out=$(report "$r" --reap)
[ ! -d "$TMP/$r/.claude/worktrees/deep" ] && ok "…and once saved: hydrate reaches it, the reaper exempts it, reaped" || bad "configured deep: $out"

# --- 21. a newline in an ignored name stays one report line ------------------
mkrepo_ignoring r21
mkwt r21 nl 'echo work >> base.txt; git commit -qam "real work"'
squash r21 nl
mkdir -p "$TMP/r21/.claude/worktrees/nl/scratch"; echo x > "$TMP/r21/.claude/worktrees/nl/scratch/two"$'\n'"lines"
out=$(report r21)
if grep -qF 'ignored, would be destroyed: scratch/two\nlines' <<< "$out"; then
    ok "newline in an ignored name: one report line, escaped"
else
    bad "newline in an ignored name split the report: $out"
fi


# --- 22. TD-038: dev-cadence's own layout (payload under files/scripts/) --------------
# The reaper finds check_anchor.py and hydrate beside itself; with scripts/ hardcoded
# the registry probe failed here, every row read idle=? and nothing was ever reapable.
# post-merge finds the reaper beside its own git-hooks/ directory the same way.
mkrepo r22
( cd "$TMP/r22" && mkdir -p files/scripts/git-hooks && git mv scripts/check_anchor.py scripts/agent_sessions.py scripts/cadence_config.py files/scripts/ \
    && git mv reap_worktrees.sh files/scripts/ && cp "$DC/files/scripts/git-hooks/post-merge" files/scripts/git-hooks/ \
    && git add -A && git commit -qm layout && git push -q origin main )
mkwt r22 dclayout 'echo work >> base.txt; git commit -qam "real work"'
squash r22 dclayout
out=$(cd "$TMP/r22" && files/scripts/reap_worktrees.sh 2>&1)
if grep -q "idle=yes" <<< "$(verdict_for "$out" dclayout)" && grep -q "REAPABLE" <<< "$out"; then
    ok "files/scripts layout: registry probe works, landed worktree reported REAPABLE"
else
    bad "files/scripts layout: $out"
fi
( cd "$TMP/r22" && git config core.hooksPath files/scripts/git-hooks )
out=$(cd "$TMP/r22" && files/scripts/git-hooks/post-merge 2>&1)
if grep -q "dclayout" <<< "$out"; then
    ok "files/scripts layout: post-merge finds the reaper beside git-hooks/ and reports"
else
    bad "post-merge found no reaper in the files/scripts layout: '$out'"
fi

# --- 23. run from a worktree, the reaper still uses the MAIN checkout's hydrate ------
# (PR #102 review) hydrate's --check gates the destructive path; a worktree whose branch
# carries a different hydrate (mid-edit, or old) must not swap its logic in. The stub
# here records that it ran; the main checkout's real hydrate must be the one used.
mkrepo r23
cp "$DC/files/scripts/hydrate_worktree.sh" "$TMP/r23/scripts/"
( cd "$TMP/r23" && git add scripts && git commit -qm hydrate && git push -q origin main )
mkwt r23 divergent 'printf "#!/usr/bin/env bash\ntouch \"$TMP/r23-stub-ran\"\nexit 0\n" > scripts/hydrate_worktree.sh; cp scripts/hydrate_worktree.sh hydrate_worktree.sh; chmod +x scripts/hydrate_worktree.sh hydrate_worktree.sh; git add -A; git commit -qm stub'
out=$(cd "$TMP/r23/.claude/worktrees/divergent" && ./reap_worktrees.sh 2>&1)
if [ ! -e "$TMP/r23-stub-ran" ] && grep -q "divergent" <<< "$out"; then
    ok "reaper run from a worktree uses the main checkout's hydrate, not the worktree's"
else
    bad "reaper used the worktree's own hydrate copy: $out"
fi
# --- 24. orphan branches (no worktree): deleted only when contained or landed (TD-032) ----
# Branch refs are one namespace across worktrees and workers reuse names, so a branch
# whose worktree moved on can carry new unpushed commits. Every keep below is a branch a
# bare "[gone]"-style rule would have deleted.
mkrepo r24; R="$TMP/r24"
mkwt r24 w-landed 'echo a > a.txt; git add a.txt; git commit -qm a'; squash r24 w-landed
git -C "$R/.claude/worktrees/w-landed" checkout -q --detach origin/main          # moved on: w-landed is orphaned, landed
mkwt r24 w-reused 'echo b > b.txt; git add b.txt; git commit -qm b'; squash r24 w-reused
( cd "$R/.claude/worktrees/w-reused" && echo more >> b.txt && git commit -qam "new, unpushed" && git checkout -q --detach origin/main )
git -C "$R" branch --no-track done origin/main                                               # a save-point name: contained
( cd "$R" && git branch --no-track netzero origin/main && git worktree add -q "$TMP/r24-nz" netzero \
  && cd "$TMP/r24-nz" && echo z > z.txt && git add z.txt && git commit -qm z && git rm -q z.txt && git commit -qm unz \
  && git checkout -q --detach && cd "$R" && git worktree remove "$TMP/r24-nz" )    # commits that net to nothing
git -C "$R" branch --no-track rb origin/main                                                 # contained, but a rebase is rewriting it:
gd=$(git -C "$R/.claude/worktrees/w-landed" rev-parse --absolute-git-dir); mkdir -p "$gd/rebase-merge"
echo refs/heads/rb > "$gd/rebase-merge/head-name"
git -C "$R" branch --no-track bis origin/main                                     # contained, but a bisect started from it:
echo bis > "$gd/BISECT_START"                                                     # (bisect writes the bare name)
git -C "$R" checkout -q -b parked                                                 # the anchor parked off main
out=$(report r24)
ln() { sed -n '/^branches without a worktree:/,$p' <<< "$out" | grep -E "^  $1 " | head -1; }
grep -q "branches without a worktree:" <<< "$out" && ok "orphan section is reported" || bad "no orphan section: $out"
grep -q "landed=yes .*DELETABLE" <<< "$(ln w-landed)" && ok "orphan landed by content: DELETABLE" || bad "w-landed: $(ln w-landed)"
grep -q "landed=contained .*DELETABLE" <<< "$(ln done)" && ok "orphan with no commits past origin/main: contained, DELETABLE" || bad "done: $(ln done)"
grep -q "landed=no .*keep" <<< "$(ln w-reused)" && ok "a reused name with a new unpushed commit: keep" || bad "w-reused: $(ln w-reused)"
grep -q "landed=net-empty .*keep" <<< "$(ln netzero)" && ok "commits that net to no change: net-empty, keep" || bad "netzero: $(ln netzero)"
[ -z "$(ln rb)" ] && ok "a branch a rebase is rewriting is never a candidate" || bad "rb listed: $(ln rb)"
[ -z "$(ln bis)" ] && ok "a branch a bisect started from is never a candidate" || bad "bis listed: $(ln bis)"
[ -z "$(ln main)" ] && ok "the default branch is never a candidate, even with the anchor parked off it" || bad "main listed: $(ln main)"
[ -z "$(ln parked)" ] && ok "a branch checked out in the anchor is not an orphan" || bad "parked listed: $(ln parked)"
for b in w-landed done w-reused netzero rb main; do git -C "$R" show-ref -q --verify "refs/heads/$b" || bad "report mode deleted $b"; done
out=$(report r24 --reap)
gone=""; for b in w-landed done; do git -C "$R" show-ref -q --verify "refs/heads/$b" && gone="$gone $b-kept"; done
kept=""; for b in w-reused netzero rb bis main parked; do git -C "$R" show-ref -q --verify "refs/heads/$b" || kept="$kept $b-deleted"; done
[ -z "$gone$kept" ] && grep -q "deleted branch done" <<< "$out" && ok "--reap deletes exactly the DELETABLE orphans" || bad "--reap orphans:$gone$kept — $out"
rm -rf "$gd/rebase-merge" "$gd/BISECT_START"
# the compare-and-delete: a branch that moved after the report is not deleted
git -C "$R" branch --no-track late origin/main; old=$(git -C "$R" rev-parse late)
( cd "$R" && git worktree add -q "$TMP/r24-late" late && cd "$TMP/r24-late" && echo l > l.txt && git add l.txt && git commit -qm l && git checkout -q --detach && cd "$R" && git worktree remove "$TMP/r24-late" )
git -C "$R" update-ref -d refs/heads/late "$old" 2>/dev/null
git -C "$R" show-ref -q --verify refs/heads/late && ok "update-ref -d <ref> <old sha> refuses a branch that moved (the delete the reaper uses)" || bad "compare-and-delete removed a moved branch"

# --- 25. TD-059: landed, then main edited its files — reaped by the same predicate as
# check_cadence.py's (landed_since_edited, imported from the main checkout's copy)
mkrepo_ignoring r25; R="$TMP/r25"
cp "$DC/files/scripts/check_cadence.py" "$R/scripts/"
( cd "$R" && git add scripts/check_cadence.py && git commit -qm "the predicate" && git push -q origin main )
main_edit() { ( cd "$TMP/$1" && git checkout -q main && git pull -q --ff-only origin main && eval "$2" && git commit -qam "$3" && git push -q origin main && git fetch -q origin ); }
mkwt r25 since 'echo mine > s.txt; git add s.txt; git commit -qm s'; squash r25 since
main_edit r25 'echo later >> s.txt' "main edits s again"
mkwt r25 rev 'echo r > r.txt; git add r.txt; git commit -qm r'; squash r25 rev
main_edit r25 'git rm -q r.txt' "main reverts r"
mkwt r25 sincescratch 'echo m2 > t.txt; git add t.txt; git commit -qm t'; squash r25 sincescratch
main_edit r25 'echo later >> t.txt' "main edits t again"
mkdir -p "$R/.claude/worktrees/sincescratch/scratch"; echo unsaved > "$R/.claude/worktrees/sincescratch/scratch/n.txt"
git -C "$R" branch --no-track orph-since origin/main
( cd "$R" && git worktree add -q "$TMP/r25-o" orph-since && cd "$TMP/r25-o" && echo o > o.txt && git add o.txt && git commit -qm o \
  && git checkout -q --detach && cd "$R" && git worktree remove "$TMP/r25-o" )
squash r25 orph-since
main_edit r25 'echo later >> o.txt' "main edits o again"
out=$(report r25)
grep -q "landed=since .*REAPABLE" <<< "$(verdict_for "$out" since)" && ok "landed, then edited on main: landed=since, REAPABLE" || bad "since: $(verdict_for "$out" since) / $out"
grep -q "landed=no .*keep" <<< "$(verdict_for "$out" rev)" && ok "landed, then reverted on main: landed=no, kept" || bad "rev: $(verdict_for "$out" rev)"
grep -q "landed=since clean=no" <<< "$(verdict_for "$out" sincescratch)" && grep -qF "ignored, would be destroyed: scratch/n.txt" <<< "$out" \
  && ok "a since worktree still gets the ignored-scratch scan: clean=no, kept" || bad "sincescratch: $(verdict_for "$out" sincescratch)"
grep -q "orph-since .*landed=since .*DELETABLE" <<< "$out" && ok "an orphan branch landed-since-edited: DELETABLE" || bad "orph-since: $out"
out=$(report r25 --reap)
[ ! -d "$R/.claude/worktrees/since" ] && [ -d "$R/.claude/worktrees/rev" ] && [ -f "$R/.claude/worktrees/sincescratch/scratch/n.txt" ] \
  && ! git -C "$R" show-ref -q --verify refs/heads/since && git -C "$R" show-ref -q --verify refs/heads/rev \
  && ok "--reap removes the since worktree and branch; the reverted one and the scratch survive" || bad "reap since: $out"
# TD-078: the predicate asks main in one `git log -p | git patch-id` over the commits that touch
# every file of the branch, not one `git show` per commit — same answers as the per-commit way
mkwt r25 two 'echo a > a2.txt; echo b > b2.txt; git add a2.txt b2.txt; git commit -qm two'; squash r25 two
main_edit r25 'echo later >> a2.txt' "main edits a2 again"
mkwt r25 part 'echo p > p2.txt; echo q > q2.txt; git add p2.txt q2.txt; git commit -qm part'
main_edit r25 'echo p > p2.txt; git add p2.txt' "main gets half of part"
mkwt r25 decoy 'echo mine > d1.txt; echo mine > d2.txt; git add d1.txt d2.txt; git commit -qm decoy'
main_edit r25 'echo theirs > d1.txt; echo theirs > d2.txt; git add d1.txt d2.txt' "main writes the decoy's two files differently"
chk=$(cd "$R" && python3 - "$DC/files/scripts" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import check_cadence as C
fast = {b: C.landed_since_edited(".", b) for b in ("two", "part", "decoy", "rev")}
ref = C.default_ref(".")
for b in ("two", "part"):
    base = C.git(["merge-base", ref, b], cwd=".").strip()
    names = [f for f in C.git(["diff", "--name-only", "-z", base, b], cwd=".").split("\0") if f]
    assert C._main_patch_ids(".", base, ref, names) is not None, "the one-pipeline path did not run"
calls = []
C._main_patch_ids = lambda *a: calls.append(a)  # returns None: the per-commit fallback answers
slow = {b: C.landed_since_edited(".", b) for b in fast}
assert calls and fast == slow == {"two": "yes", "part": False, "decoy": False, "rev": "reverted"}, (fast, slow)
print("ok")
PY
)
[ "$chk" = ok ] && ok "landed_since_edited: a two-file squash edited since = yes, half a branch on main = no, the same files written differently = no, a reverted one = reverted — the same from one pipeline and from the per-commit fallback" || bad "TD-078 predicate: $chk"
# without the predicate beside the reaper, the second question is not asked: kept
mkwt r25 since2 'echo m3 > u.txt; git add u.txt; git commit -qm u'; squash r25 since2
main_edit r25 'echo later >> u.txt' "main edits u again"
git -C "$R" rm -q scripts/check_cadence.py; git -C "$R" commit -qm "drop the predicate"
out=$(report r25)
grep -q "landed=no .*keep" <<< "$(verdict_for "$out" since2)" && ok "no check_cadence.py to ask: landed=no, kept (the safe direction)" || bad "no predicate: $(verdict_for "$out" since2)"

# --- 26. TD-142: a checked-out submodule — reaped (with --force) only when it holds nothing
# `git worktree remove` refuses a tree with a checked-out submodule, so before TD-142 such a
# tree read REAPABLE and failed on every reap. And --force drops the submodule's git dir, so
# its dirty files, its ignored scratch and its unpushed commits are each a reason to keep.
mkrepo r26
R="$TMP/r26"
G=(-c protocol.file.allow=always)
git init -q --bare -b main "$TMP/sub26.git"
git clone -q "$TMP/sub26.git" "$TMP/sub26" 2>/dev/null
( cd "$TMP/sub26" && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt && git commit -qm s && git push -q origin HEAD:main )
( cd "$R" && git "${G[@]}" submodule -q add "$TMP/sub26.git" sub && git commit -qm "add sub" && git push -q origin main && git fetch -q origin )
subwt() {  # $1 = topic, $2 = shell run in its submodule after init; work lands on main
    mkwt r26 "$1" "git ${G[*]} submodule -q update --init; echo $1 > $1.txt; git add $1.txt; git commit -qm $1"
    squash r26 "$1"
    if [ -n "$2" ]; then ( cd "$R/.claude/worktrees/$1/sub" && git config user.email t@t && git config user.name t && eval "$2" ); fi
}
subwt subclean ''
subwt subdirty 'echo x > untracked.txt'
subwt subignored 'echo junk.log >> "$(git rev-parse --git-path info/exclude)"; echo j > junk.log'
subwt subunpushed 'git commit -q --allow-empty -m "only here"'
# the dangerous one: the parent recorded a submodule commit never pushed, and that landed —
# the parent reads clean, so only the submodule's own refs say anything is at stake
mkwt r26 subrecorded "git ${G[*]} submodule -q update --init; (cd sub && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m rec); git add sub; git commit -qm rec"
squash r26 subrecorded
mkwt r26 subinit 'echo i > i.txt; git add i.txt; git commit -qm i'; squash r26 subinit
out=$(report r26)
grep -q "landed=yes clean=yes .*REAPABLE" <<< "$(verdict_for "$out" subclean)" && ok "clean, pushed submodule: REAPABLE" || bad "subclean: $(verdict_for "$out" subclean) / $out"
grep -q "clean=no .*keep" <<< "$(verdict_for "$out" subdirty)" && grep -qF "submodule, would be destroyed: sub: modified or untracked files" <<< "$out" \
  && ok "untracked file in the submodule: kept, and the report names it" || bad "subdirty: $out"
grep -q "clean=no .*keep" <<< "$(verdict_for "$out" subignored)" && grep -qF "submodule, would be destroyed: sub: ignored files (junk.log)" <<< "$out" \
  && ok "ignored scratch in the submodule (the parent cannot see it): kept, named" || bad "subignored: $out"
grep -q "clean=no .*keep" <<< "$(verdict_for "$out" subunpushed)" && grep -qF "submodule, would be destroyed: sub: commits on no remote" <<< "$out" \
  && ok "an unpushed commit in the submodule: kept, named" || bad "subunpushed: $out"
grep -q "landed=yes clean=no .*keep" <<< "$(verdict_for "$out" subrecorded)" && [ -z "$(git -C "$R/.claude/worktrees/subrecorded" status --porcelain)" ] \
  && ok "a recorded, landed, never-pushed submodule commit (parent status clean): kept" || bad "subrecorded: $(verdict_for "$out" subrecorded)"
grep -q "landed=yes clean=yes .*REAPABLE" <<< "$(verdict_for "$out" subinit)" && ok "submodule never initialised: REAPABLE as before" || bad "subinit: $(verdict_for "$out" subinit)"
out=$(report r26 --reap)
[ ! -d "$R/.claude/worktrees/subclean" ] && [ ! -d "$R/.claude/worktrees/subinit" ] && ! git -C "$R" show-ref -q --verify refs/heads/subclean \
  && ok "--reap removes the clean-submodule tree (with --force) and the uninitialised one" || bad "reap subclean: $out"
[ -f "$R/.claude/worktrees/subdirty/sub/untracked.txt" ] && [ -f "$R/.claude/worktrees/subignored/sub/junk.log" ] \
  && [ -n "$(git -C "$R/.claude/worktrees/subunpushed/sub" rev-list --all --not --remotes)" ] \
  && [ -n "$(git -C "$R/.claude/worktrees/subrecorded/sub" rev-list --all --not --remotes)" ] \
  && ok "--reap leaves the dirty, the ignored and both unpushed submodule trees, their work intact" || bad "reap kept: $out"
! grep -q "could not remove" <<< "$out" && ok "no 'could not remove' on a submodule tree any more" || bad "reap error: $out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
