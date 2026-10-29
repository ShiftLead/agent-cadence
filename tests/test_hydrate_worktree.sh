#!/usr/bin/env bash
# hydrate_worktree.sh — completes a worktree, and (the half that can destroy
# things) empties it again before it is removed.
#
# The asymmetry is the same one test_reap_worktrees.sh states: a worktree left
# un-hydrated costs a confusing session, while a worktree dehydrated too
# eagerly costs a SIBLING REPO's uncommitted work — in a repo the reaper was
# never even looking at. So every --dehydrate case here asserts the refusal AND
# that the content is still on disk afterwards.
#
# Isolation: everything lives in a tmpdir with real bare origins, because both
# load-bearing predicates (is this sibling saved? where does it branch from?)
# are defined against a remote, and a fixture without one tests a different
# function.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/hydrate_worktree.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Isolation (TD-046): never read the real ~/.gitconfig or ~/.config — a global
# init.templateDir or core.hooksPath would otherwise leak into every fixture.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# $1 = name -> a repo at $TMP/$1 on main, pushed to its own bare origin
mkrepo() {
    local r="$TMP/$1"
    git init -q --bare -b main "$r.git"
    git clone -q "$r.git" "$r" 2>/dev/null
    (
        cd "$r" || exit 1
        git config user.email t@t; git config user.name t
        git checkout -q -b main 2>/dev/null
        echo base > base.txt
        git add -A; git commit -qm base; git push -q -u origin main
    )
}

# Builds a constellation: home/ with docs-repo (worktree), app-repo (link) and
# skipped/ (skip) nested inside it. $1 = home name.
mkconstellation() {
    local h="$1"
    mkrepo "$h"; mkrepo "$h-docs"; mkrepo "$h-app"
    (
        cd "$TMP/$h" || exit 1
        mkdir -p scripts docs .claude
        cp "$SCRIPT" scripts/
        # Slashless entries on purpose: a trailing slash is directory-only and
        # would not match the `link` symlink. Case 9 pins that distinction.
        printf '/docs-repo\n/app-repo\n.claude/worktrees/\n.claude/settings.local.json\n' > .gitignore
        printf '# path mode\ndocs-repo  worktree\napp-repo   link\nabsent     skip\n' > docs/nested-repos.txt
        git add -A; git commit -qm setup; git push -q origin main
        echo '{"autoMemoryDirectory":"/mem"}' > .claude/settings.local.json
    )
    mv "$TMP/$h-docs" "$TMP/$h/docs-repo"
    mv "$TMP/$h-app"  "$TMP/$h/app-repo"
}

# $1 = home, $2 = topic
mkwt() { git -C "$TMP/$1" worktree add -q -b "$2" "$TMP/$1/.claude/worktrees/$2"; }
wt()   { echo "$TMP/$1/.claude/worktrees/$2"; }
run()  { "$TMP/$1/scripts/hydrate_worktree.sh" "${@:2}" 2>&1; }

# --- 1. hydrate honours all three modes ---------------------------------------
mkconstellation h1
mkwt h1 t1
out=$(run h1 "$(wt h1 t1)"); rc=$?
if [ $rc -eq 0 ] \
   && [ -d "$(wt h1 t1)/docs-repo/.git" -o -f "$(wt h1 t1)/docs-repo/.git" ] \
   && [ -L "$(wt h1 t1)/app-repo" ] \
   && [ ! -e "$(wt h1 t1)/absent" ]; then
    ok "hydrate: worktree mode materialises, link mode symlinks, skip mode stays absent"
else
    bad "hydrate did not produce the three modes (rc=$rc): $out"
fi

# The nested worktree carries the TOPIC name, not the sibling default — one
# branch name spanning the project is the whole point of borrowing it.
if [ "$(git -C "$(wt h1 t1)/docs-repo" rev-parse --abbrev-ref HEAD)" = t1 ]; then
    ok "hydrate: nested worktree is on a branch named for the topic"
else
    bad "nested worktree branch is $(git -C "$(wt h1 t1)/docs-repo" rev-parse --abbrev-ref HEAD), want t1"
fi

# --- 2. settings.local.json is the worktree's OWN COPY (TD-080) ----------------
# A symlink made every worktree session write its memory into the main checkout
# (autoMemoryDirectory is absolute). The copy carries everything else as it is.
# The fixture's path (/mem) is OUTSIDE the checkout — a shared memory directory,
# cadence.md §9.16 — so it is carried unchanged; cases 24+ cover the rewrite.
S="$(wt h1 t1)/.claude/settings.local.json"
if [ -f "$S" ] && [ ! -L "$S" ] && grep -q '"/mem"' "$S"; then
    ok "settings.local.json is a real file; a memory path outside the checkout is carried as it is"
else
    bad "settings.local.json is not the worktree's own copy: $(ls -l "$S" 2>&1)"
fi

# --- 3. the worktree is CLEAN afterwards --------------------------------------
# Anything hydration leaves untracked makes the worktree permanently unreapable,
# because reap counts untracked files.
if [ -z "$(git -C "$(wt h1 t1)" status --porcelain -uall)" ]; then
    ok "hydration leaves no untracked noise"
else
    bad "hydration dirtied the worktree: $(git -C "$(wt h1 t1)" status --porcelain -uall)"
fi

# --- 4. idempotent ------------------------------------------------------------
out=$(run h1 "$(wt h1 t1)"); rc=$?
if [ $rc -eq 0 ] && grep -q "already present" <<< "$out" && grep -qc "ok " <<< "$out"; then
    ok "re-running hydrate is a no-op that reports what is already there"
else
    bad "second hydrate run was not a clean no-op (rc=$rc): $out"
fi

# --- 5. the main checkout is refused ------------------------------------------
# Reachable by accident (no argument, run from the main checkout). Hydrating it
# means linking it to itself; dehydrating it means deleting the originals.
out=$(run h1 "$TMP/h1"); rc=$?
if [ $rc -eq 2 ] && grep -q "main checkout" <<< "$out"; then
    ok "refuses to operate on the main checkout"
else
    bad "main checkout was not refused (rc=$rc): $out"
fi
out=$(run h1 --dehydrate "$TMP/h1"); rc=$?
if [ $rc -eq 2 ]; then
    ok "refuses to DEHYDRATE the main checkout (this one would delete the siblings)"
else
    bad "dehydrating the main checkout was not refused (rc=$rc): $out"
fi

# --- 6. a malformed config fails loudly ---------------------------------------
# A typo'd mode must never degrade to "skip": the result is a worktree that
# looks hydrated and silently is not.
mkconstellation h6
mkwt h6 t6
printf 'docs-repo wrktree\nsinglefield\n/absolute link\n../escape link\n' > "$TMP/h6/docs/nested-repos.txt"
out=$(run h6 "$(wt h6 t6)"); rc=$?
if [ $rc -eq 1 ] \
   && grep -q "unknown mode 'wrktree'" <<< "$out" \
   && grep -q "got 'singlefield'" <<< "$out" \
   && [ "$(grep -c 'must not escape it' <<< "$out")" -eq 2 ]; then
    ok "malformed config: every bad line is named and the run fails"
else
    bad "malformed config was not fully reported (rc=$rc): $out"
fi

# --- 7. dehydrate REFUSES on uncommitted work in a sibling --------------------
# The case that motivated the whole script: this work is invisible to `git
# status` in the home repo and `git worktree remove` deletes it without a word.
mkconstellation h7
mkwt h7 t7
run h7 "$(wt h7 t7)" >/dev/null
echo precious > "$(wt h7 t7)/docs-repo/precious.txt"
out=$(run h7 --dehydrate "$(wt h7 t7)"); rc=$?
if [ $rc -eq 1 ] && grep -q "REFUSE" <<< "$out" && [ -f "$(wt h7 t7)/docs-repo/precious.txt" ]; then
    ok "dehydrate refuses on an uncommitted sibling file, and the file survives"
else
    bad "dehydrate did not protect uncommitted sibling work (rc=$rc): $out"
fi

# --- 8. dehydrate refuses on committed-but-unlanded sibling work --------------
# Committing is not saving: a branch nobody merges is stranded work, which is
# the failure class this whole system exists for.
( cd "$(wt h7 t7)/docs-repo" && git add -A && git commit -qm work )
out=$(run h7 --dehydrate "$(wt h7 t7)"); rc=$?
if [ $rc -eq 1 ] && grep -q "not on origin/main" <<< "$out" && [ -d "$(wt h7 t7)/docs-repo" ]; then
    ok "dehydrate refuses on sibling commits whose content is not on the base"
else
    bad "dehydrate did not protect unlanded sibling commits (rc=$rc): $out"
fi

# --- 9. …and ACCEPTS once that work is squash-merged --------------------------
# THE REGRESSION. Written first with `rev-list --count base..branch`, which
# squash merges (cadence §4) make permanently non-zero — so a sibling whose work
# had landed still read as unsaved and the parent worktree could never be
# reaped. Content comparison scoped to the touched files is the only test that
# survives a squash merge. Same reasoning, same trap, as reap_worktrees.sh.
( cd "$TMP/h7/docs-repo" && git fetch -q origin && git merge -q --squash t7 \
  && git commit -qm "t7 (#1)" && git push -q origin main && git fetch -q origin )
out=$(run h7 --dehydrate "$(wt h7 t7)"); rc=$?
if [ $rc -eq 0 ] && [ ! -e "$(wt h7 t7)/docs-repo" ] && [ ! -L "$(wt h7 t7)/app-repo" ]; then
    ok "dehydrate proceeds once the sibling work is squash-merged (ancestry regression)"
else
    bad "squash-merged sibling work still blocks dehydrate (rc=$rc): $out"
fi

# --- 10. removal goes through the OWNING repo ---------------------------------
# Deleting the directory alone leaves the sibling holding a `prunable`
# registration pointing at nothing.
if ! git -C "$TMP/h7/docs-repo" worktree list | grep -q prunable; then
    ok "nested worktree was removed through its own repo — no dangling registration"
else
    bad "sibling left with a prunable worktree registration: $(git -C "$TMP/h7/docs-repo" worktree list)"
fi
if [ -f "$TMP/h7/app-repo/base.txt" ]; then
    ok "unlinking a link mode sibling leaves the target intact"
else
    bad "dehydrate destroyed the link target"
fi

# --- 11. the scan never follows a link mode symlink ---------------------------
# If it did, dehydrating one topic would reach through the symlink into the MAIN
# checkout and start removing worktrees belonging to other topics. The blast
# radius makes this the most important case in the file.
mkconstellation h11
mkwt h11 t11
run h11 "$(wt h11 t11)" >/dev/null
git -C "$TMP/h11/docs-repo" worktree add -q -b decoy "$TMP/h11/app-repo/decoy"
echo danger > "$TMP/h11/app-repo/decoy/danger.txt"
out=$(run h11 --check "$(wt h11 t11)")
if ! grep -q decoy <<< "$out" && [ -f "$TMP/h11/app-repo/decoy/danger.txt" ]; then
    ok "the nested scan does not follow link mode symlinks out of the worktree"
else
    bad "the scan reached through a symlink into the main checkout: $out"
fi

# --- 12. --check mutates nothing ----------------------------------------------
# reap calls it on worktrees it has decided to KEEP, so a --check with a side
# effect would mutate worktrees nobody asked it to touch.
before=$(find "$(wt h11 t11)" -maxdepth 2 | sort)
run h11 --check "$(wt h11 t11)" >/dev/null
after=$(find "$(wt h11 t11)" -maxdepth 2 | sort)
if [ "$before" = "$after" ]; then
    ok "--check leaves the worktree byte-identical"
else
    bad "--check mutated the worktree: $(diff <(echo "$before") <(echo "$after"))"
fi

# --- 13. a trailing-slash ignore rule is diagnosed, not papered over ----------
# A gitignore pattern written directory-only does not match a symlink, so the
# link shows as untracked forever and the worktree can never be reaped. The fix
# belongs in the repo's .gitignore, so the script reports it rather than editing
# .gitignore or the shared .git/info/exclude behind the user's back.
mkconstellation h13
mkwt h13 t13
sed -i 's:^/app-repo$:/app-repo/:' "$(wt h13 t13)/.gitignore"
out=$(run h13 "$(wt h13 t13)"); rc=$?
if [ $rc -eq 1 ] && grep -q "not gitignored" <<< "$out" \
   && grep -q "^?? app-repo" <<< "$(git -C "$(wt h13 t13)" status --porcelain -uall)"; then
    ok "directory-only ignore rule vs symlink: warned, with the untracked result it predicted"
else
    bad "trailing-slash ignore mismatch was not diagnosed (rc=$rc): $out"
fi

# --- 14. no config at all = single-repo layout, nothing to do -----------------
mkrepo h14
mkdir -p "$TMP/h14/scripts"; cp "$SCRIPT" "$TMP/h14/scripts/"
printf '.claude/worktrees/\n' > "$TMP/h14/.gitignore"
( cd "$TMP/h14" && git add -A && git commit -qm setup && git push -q origin main )
mkwt h14 t14
out=$(run h14 "$(wt h14 t14)"); rc=$?
if [ $rc -eq 0 ] && grep -q "single-repo layout" <<< "$out"; then
    ok "no nested-repos.txt: succeeds quietly as a single-repo layout"
else
    bad "single-repo case did not degrade cleanly (rc=$rc): $out"
fi

# --- 15. an unconfigured nested repo is NAMED, not silently omitted ----------
# The failure this prevents is the confusing one: a sibling cloned last week is
# missing from a worktree, which looks identical to the bug this whole script
# exists to fix. Detection also must not GUESS a mode — the note offers the
# three and picks none.
mkconstellation h15
mkwt h15 t15
mkrepo h15-new && mv "$TMP/h15-new" "$TMP/h15/newly-cloned"
out=$(run h15 "$(wt h15 t15)")
if grep -q "newly-cloned" <<< "$out" && grep -q "worktree|link|skip" <<< "$out" \
   && [ ! -e "$(wt h15 t15)/newly-cloned" ]; then
    ok "an unconfigured nested repo is reported with the line to add, and not guessed at"
else
    bad "unconfigured nested repo was not surfaced: $out"
fi

# …and a repo that IS configured must not also be reported as unconfigured.
if [ "$(grep -c 'docs-repo — add' <<< "$out")" -eq 0 ]; then
    ok "configured repos are not re-reported as unconfigured"
else
    bad "a configured repo was listed as unconfigured: $out"
fi

# --- 16. detection ignores node_modules -------------------------------------
# Packages ship their own .git often enough that an unpruned scan would bury the
# real siblings under hundreds of lines — and walk a dependency tree on every
# reap while doing it.
mkdir -p "$TMP/h15/node_modules/somedep/.git"
out=$(run h15 "$(wt h15 t15)")
if ! grep -q node_modules <<< "$out"; then
    ok "detection prunes node_modules"
else
    bad "detection walked into node_modules: $out"
fi

# --- 17. a DETACHED nested worktree is not automatically "saved" -------------
# THE WORST BUG THIS FILE HAS CAUGHT. nested_unsaved() gated its whole content
# comparison on the HEAD resolving to a branch name, so a detached nested
# worktree with a clean tree skipped the comparison and reported safe. Review
# reproduced the end of that: --reap removed it and the commit survived only as
# an unreachable object waiting for gc, with nothing printed at any stage.
# Detached is exactly the state a hand-made `git worktree add --detach` leaves,
# which this script advertises that it repairs.
mkconstellation h17
mkwt h17 t17
run h17 "$(wt h17 t17)" >/dev/null
rm -rf "$(wt h17 t17)/docs-repo"
git -C "$TMP/h17/docs-repo" worktree prune
git -C "$TMP/h17/docs-repo" worktree add -q --detach "$(wt h17 t17)/docs-repo" origin/main
( cd "$(wt h17 t17)/docs-repo" && echo unpushed > unpushed.txt && git add -A && git commit -qm "detached work" )
sha=$(git -C "$(wt h17 t17)/docs-repo" rev-parse HEAD)
out=$(run h17 --dehydrate "$(wt h17 t17)"); rc=$?
if [ $rc -eq 1 ] && grep -q "REFUSE" <<< "$out" && [ -d "$(wt h17 t17)/docs-repo" ]; then
    ok "a detached nested worktree with an unreachable commit is refused, not removed"
else
    bad "DETACHED nested worktree was treated as saved (rc=$rc): $out"
fi
# …and the commit is still reachable, i.e. nothing was orphaned.
if git -C "$TMP/h17/docs-repo" cat-file -e "$sha" 2>/dev/null && [ -d "$(wt h17 t17)/docs-repo" ]; then
    ok "the detached commit survives with its worktree"
else
    bad "the detached commit was orphaned"
fi

# A detached worktree sitting exactly ON the base holds nothing, so it must NOT
# block forever — otherwise the fix trades data loss for an unreapable worktree.
mkconstellation h17b
mkwt h17b t17b
run h17b "$(wt h17b t17b)" >/dev/null
rm -rf "$(wt h17b t17b)/docs-repo"
git -C "$TMP/h17b/docs-repo" worktree prune
git -C "$TMP/h17b/docs-repo" worktree add -q --detach "$(wt h17b t17b)/docs-repo" origin/main
out=$(run h17b --dehydrate "$(wt h17b t17b)"); rc=$?
if [ $rc -eq 0 ] && [ ! -e "$(wt h17b t17b)/docs-repo" ]; then
    ok "a detached nested worktree with nothing of its own is still removable"
else
    bad "detached-but-empty nested worktree wrongly blocks dehydrate (rc=$rc): $out"
fi

# --- 18. find_nested_worktrees prunes a top-level node_modules ----------------
# The -mindepth/-prune bug again, in the second of the two find calls — fixed in
# detect_nested and missed here. It matters more here than in detection: this
# list feeds `git worktree remove`, and a package that is itself a worktree of
# an unrelated repo has a `.git` FILE, so an unpruned walk could delete a
# worktree belonging to a different project entirely.
mkconstellation h18
mkwt h18 t18
run h18 "$(wt h18 t18)" >/dev/null
mkrepo h18-stray
git -C "$TMP/h18-stray" worktree add -q -b stray "$(wt h18 t18)/node_modules/somepkg"
echo mine > "$(wt h18 t18)/node_modules/somepkg/theirs.txt"
out=$(run h18 --check "$(wt h18 t18)")
if ! grep -q somepkg <<< "$out" && [ -f "$(wt h18 t18)/node_modules/somepkg/theirs.txt" ]; then
    ok "the removal scan prunes node_modules, so an unrelated repo's worktree is untouched"
else
    bad "the removal scan reached into node_modules: $out"
fi

# --- 19. a path with a space parses ------------------------------------------
# The mode is the LAST field and the path is everything before it, so the one
# hand-typed file in this feature does not have a footgun that only fires on
# machines whose directory names contain spaces.
mkconstellation h19
mkrepo h19-sp && mv "$TMP/h19-sp" "$TMP/h19/my docs"
printf '/docs-repo\n/app-repo\n/my docs\n.claude/worktrees/\n.claude/settings.local.json\n' > "$TMP/h19/.gitignore"
printf 'my docs  link\n' > "$TMP/h19/docs/nested-repos.txt"
( cd "$TMP/h19" && git add -A && git commit -qm ign && git push -q origin main )
mkwt h19 t19          # created AFTER the ignore rules, so the worktree has them
out=$(run h19 "$(wt h19 t19)"); rc=$?
if [ $rc -eq 0 ] && [ -L "$(wt h19 t19)/my docs" ]; then
    ok "a nested path containing a space parses and links correctly"
else
    bad "a path with a space was mishandled (rc=$rc): $out"
fi

# --- 20-23. --hook: the SessionStart path -------------------------------------
# The one mode that runs in EVERY consumer session, unattended, and the only one
# with a hard contract: advisory output, never a nonzero exit. A SessionStart
# hook that fails is worse than the problem it reports (cadence.md appendix), so
# each case asserts the exit status as well as the text.
mkconstellation h20
mkwt h20 t20
out=$(cd "$(wt h20 t20)" && "$TMP/h20/scripts/hydrate_worktree.sh" --hook 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "missing" <<< "$out" && grep -q "docs-repo" <<< "$out"; then
    ok "--hook in an un-hydrated worktree warns and exits 0"
else
    bad "--hook did not warn (rc=$rc): $out"
fi

out=$(run h20 --hook "$TMP/h20"); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then
    ok "--hook in the main checkout is silent and exits 0"
else
    bad "--hook in the main checkout should say nothing (rc=$rc): $out"
fi

# Hydrated worktrees are the steady state — a hook that nags after the fix is a
# hook people disable.
run h20 "$(wt h20 t20)" >/dev/null 2>&1
out=$(cd "$(wt h20 t20)" && "$TMP/h20/scripts/hydrate_worktree.sh" --hook 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then
    ok "--hook is silent once the worktree is hydrated"
else
    bad "--hook still complains after hydration (rc=$rc): $out"
fi

# The fail-open path: cwd outside any repo. Reaches the resolution error that
# sits ABOVE the hook block, which used to exit 2 from a SessionStart hook.
out=$(cd "$TMP" && "$TMP/h20/scripts/hydrate_worktree.sh" --hook 2>&1); rc=$?
if [ $rc -eq 0 ]; then
    ok "--hook outside a git repo still exits 0 (fail-open contract)"
else
    bad "--hook exited $rc outside a repo — a SessionStart hook must never fail: $out"
fi

# --- 24-30. the memory path is per checkout (TD-080) --------------------------
# $1 = home -> main checkout's settings: an in-checkout memory path + a permission
mksettings() {
    printf '{"autoMemoryDirectory": "%s/docs/claude-memory", "permissions": {"allow": ["Bash(ls:*)"]}}\n' \
        "$TMP/$1" > "$TMP/$1/.claude/settings.local.json"
}
# $1 = settings file -> its autoMemoryDirectory
memdir() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("autoMemoryDirectory"))' "$1"; }
allow()  { python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$1"; }

mkconstellation h24; mksettings h24; mkwt h24 t24
W24="$(wt h24 t24)"; S24="$W24/.claude/settings.local.json"
out=$(run h24 "$W24"); rc=$?
if [ $rc -eq 0 ] && [ -f "$S24" ] && [ ! -L "$S24" ] \
   && [ "$(memdir "$S24")" = "$W24/docs/claude-memory" ] && [ "$(allow "$S24")" = "Bash(ls:*)" ] \
   && [ "$(memdir "$TMP/h24/.claude/settings.local.json")" = "$TMP/h24/docs/claude-memory" ]; then
    ok "the copy names the WORKTREE's memory directory and carries the main checkout's permissions"
else
    bad "copy is wrong (rc=$rc): $out / $(cat "$S24" 2>&1)"
fi

# The Done-when, on the fixture: a note written where the copy points is in the
# worktree's status and not the main checkout's.
mkdir -p "$(memdir "$S24")"; echo note > "$(memdir "$S24")/note.md"
if git -C "$W24" status --porcelain -uall | grep -q 'docs/claude-memory/note.md' \
   && ! git -C "$TMP/h24" status --porcelain -uall | grep -q 'note.md'; then
    ok "a memory note lands in the worktree's git status, and the main checkout stays clean of it"
else
    bad "note landed in the wrong checkout: wt=[$(git -C "$W24" status --porcelain -uall)] main=[$(git -C "$TMP/h24" status --porcelain -uall)]"
fi
rm -rf "$W24/docs/claude-memory"

# A re-run refreshes: a permission granted in the main checkout reaches the worktree.
printf '{"autoMemoryDirectory": "%s/docs/claude-memory", "permissions": {"allow": ["Bash(ls:*)", "Bash(cat:*)"]}}\n' \
    "$TMP/h24" > "$TMP/h24/.claude/settings.local.json"
out=$(run h24 "$W24"); rc=$?
if [ $rc -eq 0 ] && grep -q "refreshed" <<< "$out" && [ "$(allow "$S24")" = "Bash(ls:*),Bash(cat:*)" ] \
   && [ "$(memdir "$S24")" = "$W24/docs/claude-memory" ]; then
    ok "a re-run refreshes the copy from the main checkout's file, keeping the worktree's memory path"
else
    bad "refresh failed (rc=$rc): $out / $(cat "$S24")"
fi
out=$(run h24 "$W24")
grep -q "ok        .claude/settings.local.json" <<< "$out" \
    && ok "an up-to-date copy is left alone" || bad "second run did not read as ok: $out"

# A permission granted INSIDE the worktree is dropped by the refresh — and said,
# even under --quiet.
python3 - "$S24" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["permissions"]["allow"].append("Bash(rm:*)")
json.dump(d, open(sys.argv[1], "w"))
PY
"$TMP/h24/scripts/hydrate_worktree.sh" --settings-disposable "$W24"; drc=$?
out=$(run h24 --quiet "$W24"); rc=$?
if [ $drc -ne 0 ] && [ $rc -eq 0 ] && grep -q "what only this" <<< "$out" && [ "$(allow "$S24")" = "Bash(ls:*),Bash(cat:*)" ]; then
    ok "a copy holding its own permission is not disposable, and a refresh that drops it says so"
else
    bad "own-permission copy mishandled (disposable rc=$drc, hydrate rc=$rc): $out"
fi

# A worktree still carrying the OLD symlink is migrated, and the main checkout's
# file is not written through the link.
mkwt h24 t25; W25="$(wt h24 t25)"
mkdir -p "$W25/.claude"; ln -s "$TMP/h24/.claude/settings.local.json" "$W25/.claude/settings.local.json"
before=$(cat "$TMP/h24/.claude/settings.local.json")
hook=$(cd "$W25" && "$TMP/h24/scripts/hydrate_worktree.sh" --hook 2>&1); hrc=$?
if [ $hrc -eq 0 ] && grep -q "is a symlink to the main checkout's" <<< "$hook" && grep -q "Run: " <<< "$hook" && [ -L "$W25/.claude/settings.local.json" ]; then
    ok "--hook reports an old-symlink worktree, with the command, and changes nothing"
else
    bad "--hook on a symlinked settings file (rc=$hrc): $hook"
fi
pinned=$(cd "$W25" && CADENCE_REPO_ROOT="$TMP/h24" "$TMP/h24/scripts/hydrate_worktree.sh" --hook 2>&1)
if grep -qF "  Run: dev-cadence run hydrate_worktree.sh '$W25'" <<< "$pinned" && grep -qF "  Run: $TMP/h24/scripts/hydrate_worktree.sh '$W25'" <<< "$hook"; then
    ok "--hook's Run: hint is the launcher's word from a pin (TD-164), the script's own path in a copy"
else
    bad "--hook Run: hint: copy='$(grep Run: <<< "$hook")' pinned='$(grep Run: <<< "$pinned")'"
fi
out=$(run h24 "$W25"); rc=$?
if [ $rc -eq 0 ] && grep -q "migrated" <<< "$out" && [ ! -L "$W25/.claude/settings.local.json" ] \
   && [ "$(memdir "$W25/.claude/settings.local.json")" = "$W25/docs/claude-memory" ] \
   && [ "$(cat "$TMP/h24/.claude/settings.local.json")" = "$before" ]; then
    ok "an old symlink is migrated to a copy; the main checkout's file is untouched"
else
    bad "migration failed (rc=$rc): $out"
fi
hook=$(cd "$W25" && "$TMP/h24/scripts/hydrate_worktree.sh" --hook 2>&1)
[ -z "$hook" ] && ok "--hook is silent after the migration" || bad "--hook still complains: $hook"

# --hook: a real file whose memory path is another checkout's is reported.
cp "$TMP/h24/.claude/settings.local.json" "$W25/.claude/settings.local.json"
hook=$(cd "$W25" && "$TMP/h24/scripts/hydrate_worktree.sh" --hook 2>&1); hrc=$?
if [ $hrc -eq 0 ] && grep -q "names a memory directory that is not this worktree's" <<< "$hook"; then
    ok "--hook reports a settings file whose autoMemoryDirectory is not this worktree's"
else
    bad "--hook missed a wrong memory path (rc=$hrc): $hook"
fi
run h24 "$W25" >/dev/null 2>&1

# Dehydrate removes the derived copy (so the reaper can remove the worktree) and
# keeps one that holds something of its own. --check mutates nothing.
out=$(run h24 --check "$W25")
if grep -q "would remove  .claude/settings.local.json" <<< "$out" && [ -f "$W25/.claude/settings.local.json" ]; then
    ok "--check: would remove the derived copy, and leaves it"
else
    bad "--check on a derived copy: $out"
fi
"$TMP/h24/scripts/hydrate_worktree.sh" --settings-disposable "$W25"; drc=$?
out=$(run h24 --dehydrate "$W25")
if [ $drc -eq 0 ] && [ ! -e "$W25/.claude/settings.local.json" ] && [ -f "$TMP/h24/.claude/settings.local.json" ]; then
    ok "--dehydrate removes the derived copy; the main checkout's file survives"
else
    bad "--dehydrate left the derived copy (disposable rc=$drc): $out"
fi
echo '{"permissions": {"allow": ["Bash(mine:*)"]}}' > "$W25/.claude/settings.local.json"
out=$(run h24 --dehydrate "$W25")
if grep -q "kept      .claude/settings.local.json" <<< "$out" && [ -f "$W25/.claude/settings.local.json" ]; then
    ok "--dehydrate keeps a settings file that holds something the main checkout's does not"
else
    bad "--dehydrate removed a settings file with its own content: $out"
fi

# A main-checkout file that is not JSON: nothing is written, and the run fails.
mkwt h24 t26; W26="$(wt h24 t26)"
echo '{not json' > "$TMP/h24/.claude/settings.local.json"
out=$(run h24 "$W26"); rc=$?
if [ $rc -ne 0 ] && grep -q "is not a JSON object" <<< "$out" && [ ! -e "$W26/.claude/settings.local.json" ] \
   && [ -z "$(ls -A "$W26/.claude" 2>/dev/null | grep -v '^worktrees$')" ]; then
    ok "an unparsable main-checkout settings file: nothing written, no temp file left, exit 1"
else
    bad "unparsable source mishandled (rc=$rc): $out / $(ls -A "$W26/.claude" 2>&1)"
fi

# --- 27. TD-101: the nested scan prunes the worktree root the setting names. With
#     worktree-root = "wt", a worktree at wt/<topic> carries a .git at depth 3; unpruned it
#     reads as an unconfigured nested repo. Claude Code's .claude/worktrees stays pruned too.
mkconstellation h27
cp "$DC/files/scripts/cadence_config.py" "$TMP/h27/scripts/"
printf 'worktree-root = "wt"\n' > "$TMP/h27/docs/cadence.toml"; printf '/wt/\n' >> "$TMP/h27/.gitignore"
( cd "$TMP/h27" && git add -A && git commit -qm wt && git push -q origin main )
git -C "$TMP/h27" worktree add -q -b other "$TMP/h27/wt/other"
git -C "$TMP/h27" worktree add -q -b t27 "$TMP/h27/wt/t27"
git -C "$TMP/h27" worktree add -q -b cl "$TMP/h27/.claude/worktrees/cl"
out=$(run h27 "$TMP/h27/wt/t27"); rc=$?
if [ $rc -eq 0 ] && ! grep -q "wt/other\|worktrees/cl" <<< "$out" && [ -e "$TMP/h27/wt/t27/docs-repo/.git" ]; then
    ok "TD-101: the scan prunes the worktree-root setting's directory, and Claude Code's"
else
    bad "worktree-root not pruned (rc=$rc): $out"
fi
rm "$TMP/h27/scripts/cadence_config.py"
out=$(run h27 "$TMP/h27/wt/t27" 2>&1)
grep -q "wt/other" <<< "$out" \
    && ok "TD-101: without the setting's reader the default is pruned, and wt/ shows (the test above is not vacuous)" \
    || bad "control: wt/other not reported without cadence_config.py: $out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
