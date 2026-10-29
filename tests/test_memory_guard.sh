#!/usr/bin/env bash
# Memory-guard MEM_DIR resolution tests (TD-21: parse-based binding; pins the
# PR #42 precedence-walk behaviors too). Every case runs with HOME and
# XDG_CONFIG_HOME pointed at throwaway dirs so the real ~/.claude and machine
# roster are never read or touched.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/files/scripts/check_claude_memory.sh"
INSTALLER="$ROOT/files/scripts/install_git_hooks.sh"
TMP=$(mktemp -d)
FAKEHOME="$TMP/home"; mkdir -p "$FAKEHOME"
PASS=0; FAIL=0; SKIPPED=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

mkrepo() { git init -q -b main "$1"; git -C "$1" commit -q --allow-empty -m init; }
run_guard() {  # run_guard <repo>
  HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$1" bash "$GUARD" 2>&1
}

# --- 1) top-level value binds; the resolved dir is the one the guard watches
R="$TMP/r1"; mkrepo "$R"; mkdir -p "$R/.claude" "$R/memdir"
printf '{"autoMemoryDirectory": "%s"}\n' "$R/memdir" > "$R/.claude/settings.json"
out=$(run_guard "$R")
if echo "$out" | grep -qF "Memory index missing: $R/memdir/MEMORY.md"; then
  ok "top-level value binds (guard watches the named dir)"
else bad "top-level binding: $(echo "$out" | head -3)"; fi

# --- 2) nested lookalike is NOT adopted; walk continues to the lower-precedence
#        file; the decoy file is named loudly. (Pre-TD-21 the textual match
#        adopted the nested value silently.)
R="$TMP/r2"; mkrepo "$R"; mkdir -p "$R/.claude" "$R/realmem"
printf '{"hooks": {"x": {"autoMemoryDirectory": "%s"}}}\n' "$TMP/decoy" > "$R/.claude/settings.local.json"
printf '{"autoMemoryDirectory": "%s"}\n' "$R/realmem" > "$R/.claude/settings.json"
out=$(run_guard "$R")
if echo "$out" | grep -qF "Memory index missing: $R/realmem/MEMORY.md" \
   && echo "$out" | grep -qF "settings.local.json mentions \"autoMemoryDirectory\" but carries no usable top-level string value" \
   && ! echo "$out" | grep -qF "$TMP/decoy"; then
  ok "nested lookalike skipped, lower file binds, decoy named"
else bad "decoy case: $(echo "$out" | head -5)"; fi

# --- 3) null value: ignored like Claude Code does, loudly; falls to default
R="$TMP/r3"; mkrepo "$R"; mkdir -p "$R/.claude"
printf '{"autoMemoryDirectory": null}\n' > "$R/.claude/settings.json"
out=$(run_guard "$R")
if echo "$out" | grep -qF "no usable top-level string value" \
   && echo "$out" | grep -qF "falling back to $R/docs/claude-memory"; then
  ok "null value walks on to the default, loudly"
else bad "null case: $(echo "$out" | head -5)"; fi

# --- 4) duplicate top-level keys resolve to the LAST occurrence (JSON.parse
#        semantics), silently — correct binding needs no ambiguity warning
R="$TMP/r4"; mkrepo "$R"; mkdir -p "$R/.claude" "$R/first" "$R/second"
printf '{"autoMemoryDirectory": "%s", "autoMemoryDirectory": "%s"}\n' "$R/first" "$R/second" > "$R/.claude/settings.json"
out=$(run_guard "$R")
if echo "$out" | grep -qF "Memory index missing: $R/second/MEMORY.md" \
   && ! echo "$out" | grep -q "appears .* times"; then
  ok "duplicate top-level keys: last wins, no ambiguity warning"
else bad "duplicate-keys case: $(echo "$out" | head -5)"; fi

# --- 5) bad JSON in the higher-precedence file: skipped, lower file supplies
#        the value, warning names both (pins PR #42's precedence walk)
R="$TMP/r5"; mkrepo "$R"; mkdir -p "$R/.claude" "$R/lowmem"
printf '{"autoMemoryDirectory": "/nope", }\n' > "$R/.claude/settings.local.json"
printf '{"autoMemoryDirectory": "%s"}\n' "$R/lowmem" > "$R/.claude/settings.json"
out=$(run_guard "$R")
if echo "$out" | grep -qF "is not valid JSON" \
   && echo "$out" | grep -qF "Memory index missing: $R/lowmem/MEMORY.md"; then
  ok "bad JSON skipped; precedence walk continues"
else bad "badjson case: $(echo "$out" | head -5)"; fi

# --- 6) escaped characters decode correctly (the sed path had to reject them)
R="$TMP/r6"; mkrepo "$R"; mkdir -p "$R/.claude"
QDIR="$TMP/we\"ird"; mkdir -p "$QDIR"
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/we\\\"ird" > "$R/.claude/settings.json"
out=$(run_guard "$R")
if echo "$out" | grep -qF "Memory index missing: $QDIR/MEMORY.md"; then
  ok "escaped quote in value decodes and binds"
else bad "escape case: $(echo "$out" | head -5)"; fi

# --- 7) interpreter-absent fallback: textual binding + ambiguity stays loud.
#        Build a PATH with everything except python3* so `command -v python3`
#        genuinely fails while bash/grep/sed/git still resolve.
SHIM="$TMP/shim"; mkdir -p "$SHIM"
for d in /usr/bin /bin; do
  [ -d "$d" ] || continue
  for b in "$d"/*; do
    n=$(basename "$b")
    case "$n" in python3*) continue ;; esac
    [ -e "$SHIM/$n" ] || ln -s "$b" "$SHIM/$n" 2>/dev/null
  done
done
R="$TMP/r7"; mkrepo "$R"; mkdir -p "$R/.claude" "$R/textmem"
printf '{"autoMemoryDirectory": "%s", "other": {"autoMemoryDirectory": "/decoy"}}\n' "$R/textmem" > "$R/.claude/settings.json"
if PATH="$SHIM" "$SHIM/bash" -c 'command -v python3' >/dev/null 2>&1; then
  echo "SKIP: could not build a python3-free PATH; fallback case not run"; SKIPPED=$((SKIPPED+1))
else
  out=$(HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$R" PATH="$SHIM" "$SHIM/bash" "$GUARD" 2>&1)
  if echo "$out" | grep -qF "Memory index missing: $R/textmem/MEMORY.md" \
     && echo "$out" | grep -q "appears 2 times"; then
    ok "no-python3 fallback binds textually and stays loud on ambiguity"
  else bad "fallback case: $(echo "$out" | head -5)"; fi
fi

# --- TD-038: check #4 finds the shipped hook beside the guard when the guard runs from
#     inside the repo (files/scripts/git-hooks in agent-cadence itself); scripts/ was blind
#     there, so an unset core.hooksPath went unreported. TD-055: the fix it names is the
#     installer beside it, and the relative hooksPath this repo used to set is reported.
R="$TMP/dclayout"; mkrepo "$R"; mkdir -p "$R/files/scripts/git-hooks" "$R/docs/claude-memory"
cp "$GUARD" "$INSTALLER" "$R/files/scripts/"; printf '#!/bin/sh\nexit 0\n' > "$R/files/scripts/git-hooks/pre-push"; chmod +x "$R/files/scripts/git-hooks/pre-push"; : > "$R/docs/claude-memory/MEMORY.md"
out=$(HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$R" bash "$R/files/scripts/check_claude_memory.sh" 2>&1)
if echo "$out" | grep -qF "the git hooks are not installed in this clone" && echo "$out" | grep -qF "Fix: files/scripts/install_git_hooks.sh"; then
  ok "files/scripts layout: no hooks reported with the files/ installer"
else bad "files/scripts layout check #4: $(echo "$out" | head -5)"; fi
git -C "$R" config core.hooksPath files/scripts/git-hooks
out=$(HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$R" bash "$R/files/scripts/check_claude_memory.sh" 2>&1)
if echo "$out" | grep -qF "core.hooksPath (files/scripts/git-hooks) is relative" && echo "$out" | grep -qF "TD-055"; then
  ok "files/scripts layout: the relative hooksPath is reported (TD-055)"
else bad "files/scripts layout, relative hooksPath: $(echo "$out" | head -5)"; fi
bash "$R/files/scripts/install_git_hooks.sh" "$R" >/dev/null
out=$(HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$R" bash "$R/files/scripts/check_claude_memory.sh" 2>&1)
if ! echo "$out" | grep -qiE "hooksPath|hooks are not|pre-push"; then
  ok "files/scripts layout: installed shims pass check #4"
else bad "files/scripts layout, installed: $(echo "$out" | head -5)"; fi

# --- checks 1-4 (TD-046: until now only the setting RESOLUTION was tested) -------------
# A consumer-layout repo whose path holds '_' and '.', so check #2's munged fallback
# name is the one Claude Code really uses (every non-alphanumeric -> '-').
C="$TMP/con_sumer.repo"; mkrepo "$C"; mkdir -p "$C/scripts/git-hooks" "$C/docs/claude-memory"
cp "$GUARD" "$INSTALLER" "$C/scripts/"; printf '#!/bin/sh\nexit 0\n' > "$C/scripts/git-hooks/pre-push"; chmod +x "$C/scripts/git-hooks/pre-push"
: > "$C/docs/claude-memory/MEMORY.md"
git -C "$C" add -A; git -C "$C" -c user.email=t@t -c user.name=t commit -qm seed
bash "$C/scripts/install_git_hooks.sh" "$C" >/dev/null
cg() { HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$C" bash "$C/scripts/check_claude_memory.sh" "$@" 2>&1; }
out=$(cg)
echo "$out" | grep -q "^OK: 1 memory files tracked" && [ -z "$(cg --hook)" ] \
  && ok "healthy consumer: OK line standalone, silent as a hook" || bad "healthy baseline: $out"

# 1) index missing
mv "$C/docs/claude-memory/MEMORY.md" "$TMP/MEMORY.md.aside"
cg --hook | grep -qF "Memory index missing: $C/docs/claude-memory/MEMORY.md" \
  && ok "check 1: missing MEMORY.md reported" || bad "check 1: $(cg --hook)"
mv "$TMP/MEMORY.md.aside" "$C/docs/claude-memory/MEMORY.md"

# 2) strays in the fallback, under the fully munged name ('_' and '.' too)
FB="$FAKEHOME/.claude/projects/$(printf '%s' "$C" | sed 's/[^a-zA-Z0-9]/-/g')/memory"
case "$FB" in *con-sumer-repo*) ;; *) bad "fixture: munged name lost the '_'/'.' mapping: $FB" ;; esac
mkdir -p "$FB"; echo x > "$FB/lost.md"
cg --hook | grep -qF "1 memory file(s) in the default fallback $FB" \
  && ok "check 2: a stray in the munged fallback dir reported" || bad "check 2: $(cg --hook)"
rm -rf "$FAKEHOME/.claude/projects"

# 2b) TD-11: a repo path outside printable ASCII. Claude Code counts UTF-16 code units, so an
#     emoji is TWO dashes — sed gets one (UTF-8 locale) or four (C). The expected name is
#     Claude Code's own (its JS under node), so the guard must hand this path to munge().
E="$TMP/r😀"; mkrepo "$E"; mkdir -p "$E/scripts/git-hooks" "$E/docs/claude-memory"
cp "$GUARD" "$INSTALLER" "$ROOT/files/scripts/agent_sessions.py" "$E/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$E/scripts/git-hooks/pre-push"; chmod +x "$E/scripts/git-hooks/pre-push"
: > "$E/docs/claude-memory/MEMORY.md"
git -C "$E" add -A; git -C "$E" -c user.email=t@t -c user.name=t commit -qm seed
bash "$E/scripts/install_git_hooks.sh" "$E" >/dev/null
FB="$FAKEHOME/.claude/projects/$(printf '%s' "$TMP" | sed 's/[^a-zA-Z0-9]/-/g')-r--/memory"
mkdir -p "$FB"; echo x > "$FB/lost.md"
for loc in C.UTF-8 C; do
  out=$(LC_ALL=$loc HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$E" bash "$E/scripts/check_claude_memory.sh" --hook 2>&1)
  grep -qF "1 memory file(s) in the default fallback $FB" <<< "$out" \
    && ok "check 2 (LC_ALL=$loc): an emoji path probes Claude Code's own fallback name" || bad "check 2 emoji, LC_ALL=$loc: $out"
done
rm -rf "$FAKEHOME/.claude/projects"

# 3a) uncommitted memory in this repo
echo m > "$C/docs/claude-memory/new.md"
cg --hook | grep -qF "1 uncommitted change(s) in $C/docs/claude-memory (new.md) — commit & push" \
  && ok "check 3: an uncommitted memory reported, and named, in the main checkout" || bad "check 3a: $(cg --hook)"
rm "$C/docs/claude-memory/new.md"
# 3a') TD-080: whose the uncommitted memory is decides the advice. A worktree whose
#      memory is its own is told to commit on its branch; one whose setting still
#      names the MAIN checkout's directory is told not to commit them from there.
WT="$TMP/con_wt"; git -C "$C" worktree add -q -b topic "$WT"
wg() { HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$WT" bash "$C/scripts/check_claude_memory.sh" "$@" 2>&1; }
mkdir -p "$WT/.claude"; printf '{"autoMemoryDirectory": "%s"}\n' "$WT/docs/claude-memory" > "$WT/.claude/settings.local.json"
echo m > "$WT/docs/claude-memory/mine.md"
out=$(wg --hook)
grep -qF "1 uncommitted change(s) in $WT/docs/claude-memory — commit them on your branch" <<< "$out" \
  && [ -z "$(cg --hook)" ] \
  && ok "check 3: a worktree's own uncommitted memory -> commit it on your branch; the main checkout hears nothing" || bad "check 3 worktree: $out / main: $(cg --hook)"
rm "$WT/docs/claude-memory/mine.md"
printf '{"autoMemoryDirectory": "%s"}\n' "$C/docs/claude-memory" > "$WT/.claude/settings.local.json"
echo m > "$C/docs/claude-memory/theirs.md"
out=$(wg --hook)
grep -qF "the MAIN checkout's memory" <<< "$out" && grep -qF "do not commit them from here" <<< "$out" \
  && ! grep -qF "commit & push" <<< "$out" \
  && ok "check 3: a worktree still naming the main checkout's memory is told not to commit it from there" || bad "check 3 old wiring: $out"
rm "$C/docs/claude-memory/theirs.md"
git -C "$C" worktree remove --force "$WT"; git -C "$C" branch -q -D topic
# 3b) memory dir in ANOTHER repo: asked of that repo, and named as different
O2="$TMP/memrepo"; mkrepo "$O2"; mkdir -p "$O2/mem"; : > "$O2/mem/MEMORY.md"; echo m > "$O2/mem/a.md"
mkdir -p "$C/.claude"; printf '{"autoMemoryDirectory": "%s"}\n' "$O2/mem" > "$C/.claude/settings.local.json"
cg --hook | grep -qF "(in $O2, a different repo than this session's)" \
  && ok "check 3: dirty memory in another repo is asked of THAT repo" || bad "check 3b: $(cg --hook)"
# 3c) memory dir outside any git repo
mkdir -p "$TMP/nogit/mem"; : > "$TMP/nogit/mem/MEMORY.md"
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/nogit/mem" > "$C/.claude/settings.local.json"
cg --hook | grep -qF "$TMP/nogit/mem is not inside a git repo" \
  && ok "check 3: a memory dir outside git reported" || bad "check 3c: $(cg --hook)"
rm "$C/.claude/settings.local.json"

# 4) the pre-push guard: not installed / relative hooksPath / a foreign hooks dir /
#    a hook of the clone's own in .git/hooks / a copy of the guard there / installed
mv "$C/.git/hooks/pre-push" "$TMP/shim.aside"
cg --hook | grep -qF "the git hooks are not installed in this clone" \
  && ok "check 4: no hook installed reported" || bad "check 4a: $(cg --hook)"
git -C "$C" config core.hooksPath scripts/git-hooks
cg --hook | grep -qF "core.hooksPath (scripts/git-hooks) is relative" \
  && ok "check 4: the relative hooksPath reported as per-branch (TD-055)" || bad "check 4r: $(cg --hook)"
mkdir -p "$C/.husky"; git -C "$C" config core.hooksPath .husky
out=$(cg --hook)
echo "$out" | grep -qF "core.hooksPath (.husky) has no pre-push hook" && echo "$out" | grep -qF "do NOT repoint" \
  && ok "check 4: a foreign hooks dir without pre-push reported, never 'repoint'" || bad "check 4b: $out"
git -C "$C" config --unset core.hooksPath
printf '#!/bin/sh\nnpx lint-staged\n' > "$C/.git/hooks/pre-push"; chmod +x "$C/.git/hooks/pre-push"
cg --hook | grep -qF "is a pre-push hook of this clone's own, not the cadence main guard" \
  && ok "check 4: a clone's own pre-push in .git/hooks reported" || bad "check 4o: $(cg --hook)"
cp "$ROOT/files/scripts/git-hooks/pre-push" "$C/.git/hooks/pre-push"
[ -z "$(cg --hook)" ] && ok "check 4: a copy of the guard itself in .git/hooks passes" || bad "check 4g: $(cg --hook)"
mv "$TMP/shim.aside" "$C/.git/hooks/pre-push"
[ -z "$(cg --hook)" ] && ok "check 4: shim restored -> silent again" || bad "check 4c: $(cg --hook)"

# TD-063: a cloud session (CLAUDE_CODE_REMOTE) never hears the hooks warning — the harness clone
# has none and needs none — and hears one line about what differs there instead
mv "$C/.git/hooks/pre-push" "$TMP/shim.aside"
out=$(CLAUDE_CODE_REMOTE=true cg --hook)
! grep -q "hooks are not installed" <<< "$out" && grep -q "^ℹ cloud session (CLAUDE_CODE_REMOTE): the pre-push guard does not apply" <<< "$out" \
  && grep -q "gh may be missing or limited" <<< "$out" && ! grep -q "found issue" <<< "$out" \
  && ok "cloud session: no hooks warning, one note about what differs" || bad "cloud: $out"
cg --hook | grep -q "hooks are not installed" && ok "the same clone off the cloud still warns" || bad "local after cloud: $(cg --hook)"
out=$(CLAUDE_CODE_REMOTE=false cg --hook)
grep -q "hooks are not installed" <<< "$out" && ! grep -q "cloud session" <<< "$out" \
  && ok "CLAUDE_CODE_REMOTE=false is not a cloud session (only the exact value true is)" || bad "remote=false: $out"
mv "$TMP/shim.aside" "$C/.git/hooks/pre-push"

# TD-095: the Claude-only checks run only when Claude Code is in the `agents` setting (TD-100).
# A repo worked by another tool alone gets no setting warnings and no fallback-stray scan; the
# index, uncommitted and git checks still run, and the index message names no Claude setting.
R="$TMP/r95"; mkrepo "$R"; mkdir -p "$R/docs/claude-memory" "$R/.claude"
echo "- [x](x.md)" > "$R/docs/claude-memory/MEMORY.md"
printf '{"autoMemoryDirectory": null}\n' > "$R/.claude/settings.json"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm mem
FB="$FAKEHOME/.claude/projects/$(printf '%s' "$R" | sed 's/[^a-zA-Z0-9]/-/g')/memory"
mkdir -p "$FB"; echo stray > "$FB/lost.md"
out=$(run_guard "$R")
grep -q "memory file(s) in the default fallback" <<< "$out" && grep -q "no usable top-level string value" <<< "$out" \
  && ok "TD-095: default agents (claude): the fallback strays and the setting warning are reported" || bad "td095 default: $out"
printf 'agents = "codex"\n' > "$R/docs/cadence.toml"; echo new > "$R/docs/claude-memory/new.md"
out=$(run_guard "$R"); rm "$R/docs/claude-memory/new.md"
! grep -q "fallback" <<< "$out" && ! grep -q "autoMemoryDirectory" <<< "$out" && grep -q "uncommitted change" <<< "$out" \
  && ok "TD-095: agents = codex: no Claude check runs; the uncommitted check still does" || bad "td095 codex: $out"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm toml
out=$(run_guard "$R")
grep -q "^OK: .*no fallback check (Claude Code is not in agents)" <<< "$out" \
  && ok "TD-095: agents = codex, clean: OK says the fallback was not checked" || bad "td095 ok line: $out"
rm "$R/docs/claude-memory/MEMORY.md"
out=$(run_guard "$R")
grep -qF "Memory index missing: $R/docs/claude-memory/MEMORY.md — the memory directory has no index" <<< "$out" && ! grep -q "autoMemoryDirectory" <<< "$out" \
  && ok "TD-095: agents = codex: a missing index is reported without naming Claude's setting" || bad "td095 index: $out"
git -C "$R" checkout -q -- docs/claude-memory/MEMORY.md
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/elsewhere" > "$R/.claude/settings.json"; git -C "$R" add -A; git -C "$R" -c user.email=t@t -c user.name=t commit -qm stale
out=$(run_guard "$R")
grep -qF "OK: 1 memory files tracked in $R/docs/claude-memory; no fallback" <<< "$out" && ! grep -q "autoMemoryDirectory\|elsewhere" <<< "$out" \
  && ok "TD-095: agents = codex: a stale autoMemoryDirectory is ignored; docs/claude-memory is watched" || bad "td095 stale: $out"
printf 'agents = "codex, claude"\n' > "$R/docs/cadence.toml"
out=$(run_guard "$R")
grep -q "memory file(s) in the default fallback" <<< "$out" \
  && ok "TD-095: agents = codex, claude: the fallback check runs again" || bad "td095 both: $out"
printf 'agents = \n' > "$R/docs/cadence.toml"
out=$(run_guard "$R")
grep -q "memory file(s) in the default fallback" <<< "$out" \
  && ok "TD-095: an unreadable agents setting fails safe (the Claude checks run)" || bad "td095 unreadable: $out"

# --- TD-140: a memory [[link]] names the target's name: slug; check #7 warns (never fails) otherwise
R="$TMP/links"; mkrepo "$R"; M="$R/docs/claude-memory"; mkdir -p "$M"
printf -- '- [A](feedback_alpha_rule.md)\n' > "$M/MEMORY.md"
printf -- '---\nname: alpha-rule\ndescription: a\n---\nSee [[beta-rule]].\n' > "$M/feedback_alpha_rule.md"
printf -- '---\nname: beta-rule\ndescription: b\n---\nSee [[alpha-rule]], and `[[not_a_link]]` in code.\n```\n[[fenced_example]]\n```\n' > "$M/feedback_beta_rule.md"
git -C "$R" add -A && git -C "$R" commit -qm mem
out=$(run_guard "$R"); rc=$?
[ $rc = 0 ] && ! grep -q "memory link" <<< "$out" && ok "TD-140: slug links (and links in code) are quiet" || bad "td140 clean: $out"
printf -- '---\nname: gamma-rule\ndescription: c\n---\nSee [[feedback_alpha_rule]] and [[delta-rule]].\n' > "$M/feedback_gamma_rule.md"
git -C "$R" add -A && git -C "$R" commit -qm mem2
out=$(run_guard "$R"); rc=$?
[ $rc = 0 ] && grep -q "2 memory link(s) match no memory's name:" <<< "$out" \
  && grep -qF "feedback_gamma_rule.md: [[feedback_alpha_rule]] names a file — use its name: [[alpha-rule]]" <<< "$out" \
  && grep -qF "feedback_gamma_rule.md: [[delta-rule]] is no memory's name: (a memory not yet written is fine" <<< "$out" \
  && ok "TD-140: a filename link names its slug; a dangling link is named, never a failure (exit 0)" || bad "td140 bad links rc=$rc: $out"
grep -q "memory link" <<< "$(HOME="$FAKEHOME" XDG_CONFIG_HOME="$TMP/xdg" CLAUDE_PROJECT_DIR="$R" bash "$GUARD" --hook 2>&1)" \
  && ok "TD-140: the warning reaches the SessionStart hook's output" || bad "td140 hook"

rm -rf "$TMP"

# A skip is counted in the tally, and is a failure wherever CI is set (TD-046).
echo; echo "$PASS passed, $FAIL failed${SKIPPED:+ ($SKIPPED skipped)}" | sed 's/ (0 skipped)//'
[ "$FAIL" = 0 ] && { [ "$SKIPPED" = 0 ] || [ -z "${CI:-}" ]; }
