#!/usr/bin/env bash
# prepare-commit-msg (TD-067): the working agent is a co-author of its commits, named by
# AGENT_NAME, and the hook never blocks and never touches a commit that is not an agent's
# normal commit. Every case is a real `git commit` through the TD-055 shim, installed by
# install_git_hooks.sh into a worktree-free consumer-layout clone, and asserts what the
# committed message holds.
#
# Isolation: HOME, XDG_CONFIG_HOME and the global/system git config point into the tmpdir,
# so a machine's own core.hooksPath or cadence.agentDomain cannot leak in.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$DC/files/scripts/git-hooks/prepare-commit-msg"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
unset AGENT_NAME AGENT_DOMAIN AGENT_MODEL AGENT_MODEL_FILE
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

C="$TMP/c"
git init -q -b main "$C"
cd "$C" || exit 1
git config user.email t@t; git config user.name t
mkdir -p scripts/git-hooks
cp "$DC/files/scripts/install_git_hooks.sh" scripts/
cp "$HOOK" scripts/git-hooks/
git add -A && git commit -qm hooks
out=$(bash scripts/install_git_hooks.sh . 2>&1)
grep -qF "agent-cadence hook shim" .git/hooks/prepare-commit-msg 2>/dev/null \
  && ok "install: the shim for prepare-commit-msg is in place" || bad "install: $out"

body() { git log -1 --format=%B "${1:-HEAD}"; }
n_trailers() { body "${2:-HEAD}" | grep -cxF "$1"; }
T="Co-Authored-By: grinder-ao-1 <grinder-ao-1@shiftlead.placeholder>"

# --- 1) a person's commit (no AGENT_NAME) is untouched
git commit -q --allow-empty -m "plain"
[ "$(body)" = "plain" ] && ok "no AGENT_NAME: message untouched" || bad "no AGENT_NAME: '$(body)'"

# --- 2) an agent's commit gets the trailer, default domain
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty -m "agent work"
[ "$(n_trailers "$T")" = 1 ] && [ "$(body | head -1)" = "agent work" ] \
  && ok "AGENT_NAME set: one trailer, default domain" || bad "agent commit: '$(body)'"
git interpret-trailers --parse <<< "$(body)" | grep -qxF "$T" \
  && ok "the trailer is a real trailer (interpret-trailers parses it)" || bad "not parsed as a trailer: '$(body)'"

# --- 3) idempotent: amend --no-edit, amend with the same message, cherry-pick
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty --amend --no-edit
[ "$(n_trailers "$T")" = 1 ] && ok "amend --no-edit: one trailer, not two" || bad "amend: '$(body)'"
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty --amend -m "$(body)"
[ "$(n_trailers "$T")" = 1 ] && ok "amend -m <same message>: one trailer" || bad "amend -m: '$(body)'"
git checkout -q -b side
echo x > x && git add x && AGENT_NAME=grinder-ao-1 git commit -qm "side work"
git checkout -q main
AGENT_NAME=grinder-ao-1 git cherry-pick side >/dev/null 2>&1
[ "$(n_trailers "$T")" = 1 ] && [ "$(body | head -1)" = "side work" ] \
  && ok "cherry-pick of an agent commit: one trailer" || bad "cherry-pick: '$(body)'"

# a cherry-pick resumed after a conflict reaches the hook as source `merge` (MERGE_MSG
# exists) — still the agent's commit, so it gets the trailer, once
git checkout -q -b cp && echo theirs > k && git add k && git commit -qm "cp work" && git checkout -q main
echo ours > k && git add k && git commit -qm "main k"
AGENT_NAME=grinder-ao-1 git cherry-pick cp >/dev/null 2>&1
echo resolved > k && git add k
AGENT_NAME=grinder-ao-1 GIT_EDITOR=true git cherry-pick --continue >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && [ "$(n_trailers "$T")" = 1 ] && [ "$(body | head -1)" = "cp work" ] \
  && ok "cherry-pick --continue after a conflict (source merge): one trailer" || bad "cp --continue rc=$rc: '$(body)'"

# --- 4) an existing trailer block (Claude Code's own line) is joined, not duplicated
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty -m "both

Co-Authored-By: Claude <noreply@anthropic.com>"
exp="both

Co-Authored-By: Claude <noreply@anthropic.com>
$T"
[ "$(body)" = "$exp" ] && ok "Claude Code's trailer kept, ours appended to the same block" || bad "block: '$(body)'"

# --- 5) domain: cadence.agentDomain, overridden by AGENT_DOMAIN
git config cadence.agentDomain example.org
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty -m "cfg"
body | grep -qxF "Co-Authored-By: grinder-ao-1 <grinder-ao-1@example.org>" \
  && ok "domain from git config cadence.agentDomain" || bad "config domain: '$(body)'"
AGENT_NAME=grinder-ao-1 AGENT_DOMAIN=on.prem git commit -q --allow-empty -m "env"
body | grep -qxF "Co-Authored-By: grinder-ao-1 <grinder-ao-1@on.prem>" \
  && ok "AGENT_DOMAIN overrides the config key" || bad "env domain: '$(body)'"
git config --unset cadence.agentDomain

# --- 6) someone else's message: merge commit, squash merge, -C <other commit>
git checkout -q -b m1 && echo m > m && git add m && git commit -qm "m1 work" && git checkout -q main
AGENT_NAME=grinder-ao-1 git merge -q --no-ff m1 -m "merge m1" 2>/dev/null
[ "$(git rev-list --count HEAD^@ 2>/dev/null)" -ge 2 ] && [ "$(n_trailers "$T")" = 0 ] \
  && ok "merge commit: untouched" || bad "merge: '$(body)'"
git checkout -q -b s1 && echo s > s && git add s && git commit -qm "s1 work" && git checkout -q main
git merge -q --squash s1 >/dev/null 2>&1
AGENT_NAME=grinder-ao-1 git commit -q --no-edit
[ "$(n_trailers "$T")" = 0 ] && body | grep -q "s1 work" \
  && ok "squash merge (SQUASH_MSG): untouched" || bad "squash: '$(body)'"
other=$(git rev-parse m1)
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty -C "$other"
[ "$(n_trailers "$T")" = 0 ] && [ "$(body)" = "m1 work" ] \
  && ok "-C <another commit>: its message untouched" || bad "-C: '$(body)'"

# --- 7) an empty message still aborts (a trailer must not turn it into a commit)
before=$(git rev-parse HEAD)
AGENT_NAME=grinder-ao-1 GIT_EDITOR=true git commit -q --allow-empty >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ "$(git rev-parse HEAD)" = "$before" ] \
  && ok "empty message: commit still aborts" || bad "empty message committed (rc=$rc): '$(body)'"
echo v >> x && git add x
AGENT_NAME=grinder-ao-1 GIT_EDITOR=true git commit -q -v >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ "$(git rev-parse HEAD)" = "$before" ] \
  && ok "empty message with -v (diff below the scissors): commit still aborts" || bad "-v committed (rc=$rc): '$(body)'"
git reset -q --hard

# --- 8) fails gracefully: bad name, unreadable/missing file — exit 0, nothing added
AGENT_NAME='a b <x>' git commit -q --allow-empty -m "bad name"; rc=$?
[ $rc -eq 0 ] && [ "$(body)" = "bad name" ] && ok "a name an address cannot carry: nothing added, commit made" \
  || bad "bad name rc=$rc: '$(body)'"
AGENT_NAME=grinder-ao-1 "$HOOK" "$TMP/no-such-file" message; rc=$?
[ $rc -eq 0 ] && [ ! -e "$TMP/no-such-file" ] && ok "missing message file: exit 0, nothing created" || bad "missing file rc=$rc"
printf 'x\n' > "$TMP/ro" && chmod 444 "$TMP/ro"
AGENT_NAME=grinder-ao-1 "$HOOK" "$TMP/ro" message; rc=$?
[ $rc -eq 0 ] && [ "$(cat "$TMP/ro")" = "x" ] && ok "unwritable message file: exit 0, untouched" || bad "ro file rc=$rc"
AGENT_NAME=grinder-ao-1 "$HOOK"; rc=$?
[ $rc -eq 0 ] && ok "no arguments: exit 0" || bad "no args rc=$rc"

# --- 9) TD-181: Agent-Model — the model file's first line, else AGENT_MODEL; replaced, never doubled
M="$TMP/model"
model_lines() { body | grep -c '^Agent-Model:'; }
git checkout -q main
AGENT_NAME=grinder-ao-1 AGENT_MODEL=claude-code/opus git commit -q --allow-empty -m "declared"
[ "$(model_lines)" = 1 ] && [ "$(n_trailers "Agent-Model: claude-code/opus")" = 1 ] && [ "$(n_trailers "$T")" = 1 ] \
  && git interpret-trailers --parse <<< "$(body)" | grep -qxF "Agent-Model: claude-code/opus" \
  && ok "AGENT_MODEL alone: one Agent-Model trailer beside the co-author, a real trailer" || bad "AGENT_MODEL: '$(body)'"
printf 'claude-code/claude-opus-5-5\nsecond line\n' > "$M"
AGENT_NAME=grinder-ao-1 AGENT_MODEL=claude-code/opus AGENT_MODEL_FILE="$M" git commit -q --allow-empty -m "running"
[ "$(model_lines)" = 1 ] && [ "$(n_trailers "Agent-Model: claude-code/claude-opus-5-5")" = 1 ] \
  && ok "AGENT_MODEL_FILE wins over AGENT_MODEL, its first line only" || bad "model file: '$(body)'"
printf ' claude-code/opus-crlf  \r\n' > "$M"
AGENT_NAME=grinder-ao-1 AGENT_MODEL_FILE="$M" git commit -q --allow-empty -m "crlf"
[ "$(model_lines)" = 1 ] && [ "$(n_trailers "Agent-Model: claude-code/opus-crlf")" = 1 ] \
  && ok "a model file line with CRLF and blanks around it is trimmed, not dropped" || bad "crlf: '$(body)'"
printf 'claude-code/claude-sonnet-5-5\n' > "$M"
AGENT_NAME=grinder-ao-1 AGENT_MODEL_FILE="$M" git commit -q --allow-empty --amend --no-edit
[ "$(model_lines)" = 1 ] && [ "$(n_trailers "Agent-Model: claude-code/claude-sonnet-5-5")" = 1 ] && [ "$(n_trailers "$T")" = 1 ] \
  && ok "an amend after a model switch names the new model alone" || bad "switch amend: '$(body)'"
AGENT_NAME=grinder-ao-1 AGENT_MODEL=claude-code/opus AGENT_MODEL_FILE="$TMP/no-such-model" git commit -q --allow-empty -m "gone"
[ "$(n_trailers "Agent-Model: claude-code/opus")" = 1 ] && [ "$(model_lines)" = 1 ] \
  && ok "an unreadable model file falls back to AGENT_MODEL" || bad "fallback: '$(body)'"
: > "$M"
AGENT_NAME=grinder-ao-1 AGENT_MODEL_FILE="$M" git commit -q --allow-empty -m "empty file"
[ "$(model_lines)" = 0 ] && [ "$(n_trailers "$T")" = 1 ] && ok "an empty model file and no AGENT_MODEL: no Agent-Model" \
  || bad "empty model file: '$(body)'"
AGENT_NAME=grinder-ao-1 git commit -q --allow-empty -m "no model"
[ "$(model_lines)" = 0 ] && ok "neither variable set: no Agent-Model trailer" || bad "no model: '$(body)'"
AGENT_MODEL=claude-code/opus git commit -q --allow-empty -m "model, no name"
[ "$(model_lines)" = 1 ] && ! body | grep -q '^Co-Authored-By' && ok "a model without AGENT_NAME: Agent-Model, no co-author" \
  || bad "model no name: '$(body)'"
AGENT_NAME=grinder-ao-1 AGENT_MODEL=$'a\tb' git commit -q --allow-empty -m "odd model"; rc=$?
[ $rc -eq 0 ] && [ "$(model_lines)" = 0 ] && [ "$(n_trailers "$T")" = 1 ] \
  && ok "a model value with a control character: no Agent-Model, the co-author still added" || bad "odd model rc=$rc: '$(body)'"
AGENT_MODEL=claude-code/opus git commit -q --allow-empty --cleanup=strip -m "# only a comment" 2>/dev/null; rc=$?
[ $rc -ne 0 ] && [ "$(body | head -1)" = "odd model" ] && ok "an empty message is still aborted with only a model set" \
  || bad "empty msg with model rc=$rc: '$(body)'"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
