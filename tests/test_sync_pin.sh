#!/usr/bin/env bash
# `sync.sh --pin <repo>` (TD-129, Decision 11 of docs/plans/2026-10-25-pinned-not-synced.md): a synced
# repo's last sync. It pins the repo to the agent-cadence clone's HEAD, retires every synced copy that
# still matches its lock hash and keeps an edited one with a WARN, drops the lock, seeds the skill
# pointers (SEED once pinned, Decision 5) without their synced-file header, reinstalls the shims and
# lists the repo's files that name scripts/ — committing nothing. It is adopt's code (`adopt --migrate`).
# Offline and fixture-driven: the "agent-cadence clone" is a clone of a temp bare origin built from this
# checkout's launcher/, files/ and sync.sh; the consumer is synced from it first, by the copy mode as
# it was before TD-129 retired it (tests/fixtures/legacy_sync.sh). HOME, XDG and the roster are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" XDG_CACHE_HOME="$TMP/cache" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SHIFTLEAD_SESSION CADENCE_REPO_ROOT CADENCE_TEMP_ROOTS
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

ORIGIN="$TMP/origin.git"; CL="$TMP/dc-clone"
git init -q -b main "$TMP/build"
cp -r "$DC/launcher" "$DC/files" "$DC/sync.sh" "$TMP/build/"
cp "$DC/tests/fixtures/legacy_sync.sh" "$TMP/build/legacy_sync.sh"   # makes the synced consumer; sync.sh no longer copies
rm -rf "$TMP/build/launcher/__pycache__" "$TMP/build/files/scripts/__pycache__"
git -C "$TMP/build" add -A && git -C "$TMP/build" commit -qm c1
git clone -q --bare "$TMP/build" "$ORIGIN"
git clone -q "$ORIGIN" "$CL"
HEAD1=$(git -C "$CL" rev-parse HEAD)
pin() { (cd "$CL" && ./sync.sh --pin "$@" 2>&1); }
consumer() {  # consumer <dir>: a repo synced from the clone, committed
    git init -q -b main "$1" && git -C "$1" commit -q --allow-empty -m init
    (cd "$CL" && ./legacy_sync.sh "$1" >/dev/null 2>&1) || { echo "fixture sync failed" >&2; return 1; }
    git -C "$1" add -A && git -C "$1" commit -qm synced
}

R="$TMP/consumer"; consumer "$R"
[ -f "$R/docs/cadence-sync.lock" ] && [ -f "$R/scripts/cadence_hooks.sh" ] && ok "fixture: a synced consumer with its lock" || bad "fixture sync"
mapfile -t LOCKED < <(sed -n 's/^file: \(.*\) [0-9a-f]\{64\}.*/\1/p' "$R/docs/cadence-sync.lock")

# --- 1) refusals: a dirty consumer, a repo never synced, --verify and the copy mode (retired)
echo x >> "$R/AGENTS.md"
out=$(pin "$R"); rc=$?
[ $rc -eq 2 ] && grep -q "has uncommitted changes" <<< "$out" && [ -f "$R/docs/cadence-sync.lock" ] \
    && ok "refused: a consumer with uncommitted changes, nothing touched" || bad "dirty: rc=$rc $out"
git -C "$R" checkout -q AGENTS.md
N="$TMP/new"; git init -q -b main "$N"; git -C "$N" commit -q --allow-empty -m init
out=$(pin "$N"); rc=$?
[ $rc -eq 2 ] && grep -q "no docs/cadence-sync.lock: it is not a synced repo" <<< "$out" && ok "refused: a repo never synced (adopt is for that)" || bad "unsynced: rc=$rc $out"
out=$( cd "$CL" && ./sync.sh --verify --pin "$R" 2>&1 ); rc=$?
[ $rc -eq 1 ] && grep -q "sync.sh --verify is retired" <<< "$out" && [ -f "$R/docs/cadence-sync.lock" ] && ok "refused: --verify, retired (TD-129), even with --pin" || bad "verify+pin: rc=$rc $out"
out=$( cd "$CL" && ./sync.sh "$R" 2>&1 ); rc=$?
[ $rc -eq 1 ] && grep -q "sync.sh no longer copies into a repo" <<< "$out" && [ -z "$(git -C "$R" status --porcelain)" ] \
    && ok "refused: a plain sync — the copy mode is retired (TD-129), nothing touched" || bad "plain sync: rc=$rc $out"

# TD-168: the migration reads the ledger it keeps first; one declaring a newer format major is refused, nothing touched
printf '\nLedgerboard: 99\n' >> "$R/docs/technical_debt.md"; git -C "$R" commit -qam "a newer major"
out=$(pin "$R"); rc=$?
[ $rc -eq 2 ] && grep -q "a ledger or board it keeps declares a format the pinned scripts cannot read" <<< "$out" && [ -f "$R/docs/cadence-sync.lock" ] \
    && [ -f "$R/scripts/cadence_hooks.sh" ] && ok "refused: a kept ledger declaring a newer format major (TD-168), nothing touched" || bad "newer major: rc=$rc $out"
git -C "$R" reset -q --hard HEAD~1
# a pin that would not read back (a `"` in origin's path) is refused before anything is removed
git -C "$CL" remote set-url origin "$TMP/o\"x.git"
out=$(pin "$R"); rc=$?
[ $rc -eq 2 ] && grep -q "would not read back" <<< "$out" && [ -f "$R/docs/cadence-sync.lock" ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    && ok "refused: a pin that would not read back, before any copy is removed" || bad "readback: rc=$rc $out"
git -C "$CL" remote set-url origin "$ORIGIN"

# --- 2) the migration: an edited copy kept, a file naming scripts/ listed, everything else retired
printf '\n# a local edit\n' >> "$R/scripts/reap_worktrees.sh"
printf 'check:\n\tbash scripts/check_cadence.py\n' > "$R/Makefile"
git -C "$R" add -A && git -C "$R" commit -qm "local edit; a Makefile naming scripts/"
out=$(pin "$R"); rc=$?
[ $rc -eq 0 ] && [ ! -e "$R/docs/cadence-sync.lock" ] && ok "the migration exits 0 and drops the lock" || bad "migrate rc=$rc: $out"
left=""; for f in "${LOCKED[@]}"; do
    case "$f" in scripts/reap_worktrees.sh|.claude/skills/*|.agents/skills/*) continue ;; esac
    [ -e "$R/$f" ] && left+=" $f"
done
[ ${#LOCKED[@]} -gt 20 ] && [ -z "$left" ] && ok "every unedited synced copy is retired (${#LOCKED[@]} in the lock)" || bad "left behind:$left"
[ -f "$R/scripts/reap_worktrees.sh" ] && grep -q "scripts/reap_worktrees.sh: edited since it was synced — kept" <<< "$out" \
    && ok "an edited copy is kept, with a WARN" || bad "edited copy: $out"
[ ! -e "$R/scripts/git-hooks" ] && [ ! -e "$R/docs/procedures" ] && ok "directories left empty are removed" || bad "empty dirs: $(ls "$R/scripts" "$R/docs" 2>&1)"
p="$R/.claude/skills/cadence/SKILL.md"
[ -f "$p" ] && ! grep -q "SYNCED FILE" "$p" && grep -qF '`agent-cadence path procedures/cadence.md`' "$p" && [ -f "$R/.agents/skills/attention/SKILL.md" ] \
    && ok "the skill pointers are seeded without the synced-file header, naming the pinned path" || bad "pointers: $(head -8 "$p" 2>&1)"
head -c 200 "$p" | grep -q '^---$' && [ "$(sed -n '/^---$/,/^# /p' "$p" | tail -2 | head -1)" = "" ] && ! grep -Pzq '\n\n\n' "$p" \
    && ok "  ... and keep their frontmatter, with one blank line before the title" || bad "pointer layout: $(head -8 "$p")"
python3 -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb"))["agent-cadence"]; assert d["ref"]==sys.argv[2] and d["source"]==sys.argv[3]' \
    "$R/docs/cadence.toml" "$HEAD1" "$ORIGIN" && grep -qx '\[agent-cadence\]' "$R/docs/cadence.toml" \
    && ok "the pin: origin's URL and the clone's HEAD, under the header the hooks detect" || bad "pin: $(tail -4 "$R/docs/cadence.toml")"
grep -qF 'agent-cadence hook' "$R/.git/hooks/pre-push" && grep -qF '/scripts/git-hooks/' "$R/.git/hooks/pre-push" && ! grep -qF 'files/scripts' "$R/.git/hooks/pre-push" \
    && ok "the shims run the pin, and fall back to the consumer's scripts/git-hooks (not the clone's files/)" || bad "shim: $(grep -n 'hook=' "$R/.git/hooks/pre-push")"
grep -q "these files name scripts/" <<< "$out" && grep -qx "    Makefile" <<< "$out" && ! grep -qx "    scripts/reap_worktrees.sh" <<< "$out" \
    && ok "the repo's own files naming scripts/ are listed for the same change (and not edited)" || bad "named list: $out"
[ "$(git -C "$R" log --oneline | wc -l)" = 3 ] && grep -q "check_cadence" "$R/Makefile" && ok "nothing committed, the listed file untouched" || bad "commits: $(git -C "$R" log --oneline)"
grep -qxF "$(realpath "$R")" "$AGENT_CADENCE_REG_DIR/repos.txt" && [ "$(grep -cxF "$(realpath "$R")" "$AGENT_CADENCE_REG_DIR/repos.txt")" = 1 ] \
    && ok "the roster holds the repo once" || bad "roster: $(cat "$AGENT_CADENCE_REG_DIR/repos.txt")"

# --- 3) from a linked worktree on a branch: the files change there, the main checkout is untouched
R2="$TMP/consumer2"; consumer "$R2"
git -C "$R2" worktree add -q "$TMP/c2-wt" -b migrate
out=$(pin "$TMP/c2-wt"); rc=$?
[ $rc -eq 0 ] && [ ! -e "$TMP/c2-wt/docs/cadence-sync.lock" ] && [ -f "$R2/docs/cadence-sync.lock" ] && [ -f "$R2/scripts/cadence_hooks.sh" ] \
    && ! grep -qx '\[agent-cadence\]' "$R2/docs/cadence.toml" && grep -qx '\[agent-cadence\]' "$TMP/c2-wt/docs/cadence.toml" \
    && ok "a worktree named: it is migrated, the main checkout still synced" || bad "worktree: rc=$rc $out"
grep -qF "agent-cadence hook shim (TD-055)" "$R2/.git/hooks/pre-push" && grep -qF '/scripts/git-hooks/' "$R2/.git/hooks/pre-push" \
    && ok "  ... and the clone's shims, until the PR merges, still run main's scripts/git-hooks copy" || bad "worktree shim"

# --- 3b) the lock is committed, so untrusted: a path out of the checkout (a `..`, a symlinked
# directory) is never removed; an untracked file keeps its directory; a non-ASCII name is listed
R3="$TMP/consumer3"; consumer "$R3"
echo outside > "$TMP/outside.txt"; mkdir -p "$TMP/elsewhere"; echo victim > "$TMP/elsewhere/victim"
ln -s "$TMP/elsewhere" "$R3/linkdir"
{ echo "file: ../outside.txt $(sha256sum < "$TMP/outside.txt" | cut -d' ' -f1)"
  echo "file: linkdir/victim $(sha256sum < "$TMP/elsewhere/victim" | cut -d' ' -f1)"
  echo "file: $TMP/outside.txt $(sha256sum < "$TMP/outside.txt" | cut -d' ' -f1)"
  echo "file: legacy.txt"; } >> "$R3/docs/cadence-sync.lock"
echo old > "$R3/legacy.txt"
printf 'see `scripts/attention.sh`\n' > "$R3/café.md"
git -C "$R3" add -A && git -C "$R3" commit -qm "hostile lock lines; a non-ASCII file"
echo mine > "$R3/scripts/git-hooks/my-notes.txt"   # untracked: the migration may start with it
out=$(pin "$R3"); rc=$?
[ $rc -eq 0 ] && [ -f "$TMP/outside.txt" ] && [ -f "$TMP/elsewhere/victim" ] && [ "$(grep -c "names a path outside the checkout" <<< "$out")" = 3 ] \
    && ok "lock paths out of the checkout (.., a symlinked dir, absolute) are left alone, each said" || bad "hostile lock rc=$rc: $out"
[ -f "$R3/scripts/git-hooks/my-notes.txt" ] && [ ! -e "$R3/scripts/git-hooks/pre-push" ] && ok "an untracked file keeps its directory; the copies beside it go" || bad "untracked: $(ls "$R3/scripts/git-hooks" 2>&1)"
[ -f "$R3/legacy.txt" ] && grep -q "1 lock line(s) carry no sha256" <<< "$out" && ok "a lock line with no hash: its copy kept, with a WARN" || bad "hashless: $out"
grep -qx "    café.md" <<< "$out" && ok "a file with a non-ASCII name that names scripts/ is listed" || bad "non-ascii: $out"
# a run that stopped part-way (the deletions are uncommitted): refused, with the way back named
R4="$TMP/consumer4"; consumer "$R4"; rm "$R4/scripts/check_cadence.py"
out=$(pin "$R4"); rc=$?
[ $rc -eq 2 ] && grep -qF "git -C $(realpath "$R4") checkout -- ." <<< "$out" && ok "a half-done checkout is refused, naming how to undo it" || bad "partial: rc=$rc $out"
# after a migration that kept an edited copy: adopt on the pinned repo warns and carries on (the two
# never refuse each other)
out=$( cd "$CL" && python3 "$DC/launcher/agent_cadence.py" -C "$CL" adopt "$R" 2>&1 ); rc=$?
[ $rc -eq 0 ] && grep -q "edited copies kept by the migration" <<< "$out" && ok "adopt on a migrated repo with a kept copy: a WARN, not a refusal" || bad "adopt after: rc=$rc $out"

# --- 3c) TD-149: the old SessionStart line. A repo synced before the pin's line kept its own (the
# settings file is a SEED); the migration makes each command that ran scripts/cadence_hooks.sh the
# seed's line, keeping every other byte, and lists $VAR/scripts/ references for the same change
SEEDCMD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][0]["command"])' "$DC/files/.claude/settings.json")
cmd() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("\n".join(h["command"] for e in d["hooks"]["SessionStart"] for h in e["hooks"]))' "$1"; }
R5="$TMP/consumer5"; consumer "$R5"
cat > "$R5/.claude/settings.json" <<'J'
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "f=\"$CLAUDE_PROJECT_DIR/scripts/cadence_hooks.sh\"; if [ -x \"$f\" ]; then \"$f\" --session-start; fi", "timeout": 120}]},
      {"hooks": [{"type": "command", "command": "echo repo-own-hook"}]}
    ],
    "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}]
  }
}
J
printf 'r=$(git worktree list); f="${r:-.}/scripts/x.sh"\n' > "$R5/hook.sh"
git -C "$R5" add -A && git -C "$R5" commit -qm "the old SessionStart line; a \${r}/scripts/ caller"
cp "$R5/.claude/settings.json" "$TMP/settings5.before"
out=$(pin "$R5"); rc=$?
[ $rc -eq 0 ] && [ "$(cmd "$R5/.claude/settings.json" | head -1)" = "$SEEDCMD" ] && grep -q "replaced .claude/settings.json: 1 SessionStart command" <<< "$out" \
    && ok "TD-149: the old SessionStart line becomes the seed's, and the run says replaced" || bad "old line rc=$rc: $out / $(cmd "$R5/.claude/settings.json")"
python3 - "$TMP/settings5.before" "$R5/.claude/settings.json" "$SEEDCMD" <<'P' && ok "  ... every other byte kept: the timeout, the repo's own hook, Stop, the permissions" || bad "  other bytes changed: $(diff "$TMP/settings5.before" "$R5/.claude/settings.json")"
import json, sys
a, b, seed = open(sys.argv[1]).read(), open(sys.argv[2]).read(), sys.argv[3]
old = json.loads(a)["hooks"]["SessionStart"][0]["hooks"][0]["command"]
assert b == a.replace(json.dumps(old), json.dumps(seed)), "not a one-literal swap"
assert "echo repo-own-hook" in b and '"timeout": 120' in b and "Bash(ls:*)" in b
P
grep -qx "    hook.sh" <<< "$out" && ! grep -qx "    .claude/settings.json" <<< "$out" \
    && ok "  ... \${r}/scripts/ is listed; the settings file, now on the seed's line, is not" || bad "scan: $out"
R7="$TMP/consumer7"; consumer "$R7"; cp "$R7/.claude/settings.json" "$TMP/settings7.before"
out=$(pin "$R7"); rc=$?
[ $rc -eq 0 ] && cmp -s "$TMP/settings7.before" "$R7/.claude/settings.json" && ! grep -q "replaced .claude/settings.json\|WARN  .claude/settings.json" <<< "$out" \
    && ok "  ... a repo already on the seed's line is untouched, and nothing is said" || bad "seed line rc=$rc: $out"
R6="$TMP/consumer6"; consumer "$R6"
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/scripts/cadence_hooks.sh --session-start"}]}]},}\n' > "$R6/.claude/settings.json"
git -C "$R6" add -A && git -C "$R6" commit -qm "a settings file JSON cannot read"
cp "$R6/.claude/settings.json" "$TMP/settings6.before"
out=$(pin "$R6"); rc=$?
[ $rc -eq 0 ] && cmp -s "$TMP/settings6.before" "$R6/.claude/settings.json" && grep -q "WARN  .claude/settings.json: cannot read it" <<< "$out" \
    && grep -qx "    .claude/settings.json" <<< "$out" \
    && ok "TD-149: a settings file that does not parse is left as it was, with a WARN, and listed (\$CLAUDE_PROJECT_DIR/scripts/)" || bad "unparseable rc=$rc: $out"

R8="$TMP/consumer8"; consumer "$R8"; cp "$TMP/settings5.before" "$TMP/dotfiles-settings.json"
rm "$R8/.claude/settings.json"; ln -s "$TMP/dotfiles-settings.json" "$R8/.claude/settings.json"
git -C "$R8" add -A && git -C "$R8" commit -qm "a symlinked settings file with the old line"
out=$(pin "$R8"); rc=$?
[ $rc -eq 0 ] && cmp -s "$TMP/settings5.before" "$TMP/dotfiles-settings.json" && [ -L "$R8/.claude/settings.json" ] && grep -q "WARN  .claude/settings.json: it is a symlink" <<< "$out" \
    && ok "TD-149: a symlinked settings file with the old line is never rewritten, and a WARN says so" || bad "symlink rc=$rc: $out"

# --- 5) TD-147: a constellation's home. Its siblings' SessionStart hooks run the home's scripts/, which
# the migration removes — refused, nothing changed, until the siblings have moved (--siblings-moved)
H="$TMP/home-repo"; consumer "$H"
printf 'docs-site worktree\nlanding link   # a comment\n' > "$H/docs/nested-repos.txt"
printf '/docs-site/\n/landing/\n' >> "$H/.gitignore"
git -C "$H" add -A && git -C "$H" commit -qm "a constellation home"
mkdir -p "$H/docs-site/.claude" "$H/landing/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR/../scripts/check_anchor.py\\" --hook"},{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR/../scripts/check_claude_memory.sh\\" --hook"}]}]}}\n' \
    > "$H/docs-site/.claude/settings.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"./scripts/own.sh"}]}]}}\n' > "$H/landing/.claude/settings.json"
out=$(pin "$H"); rc=$?
[ $rc -eq 2 ] && grep -q "is a constellation's home" <<< "$out" && grep -q "docs-site/.claude/settings.json (2 call(s) into the home's scripts/)" <<< "$out" \
    && ! grep -q "landing" <<< "$out" && [ -f "$H/docs/cadence-sync.lock" ] && [ -z "$(git -C "$H" status --porcelain)" ] \
    && ok "TD-147: --pin on a home whose sibling calls its scripts/ is refused, naming that sibling alone, nothing changed" || bad "home refused rc=$rc: $out"
out=$( cd "$CL" && ./sync.sh --siblings-moved "$H" 2>&1 ); rc=$?
[ $rc -eq 1 ] && grep -q "goes with --pin" <<< "$out" && ok "TD-147: --siblings-moved without --pin is refused" || bad "moved alone rc=$rc: $out"
mv "$H/landing" "$TMP/landing.away"
out=$(pin "$H"); rc=$?
[ $rc -eq 2 ] && grep -q "landing (not here to read" <<< "$out" && ok "TD-147: a listed sibling not on disk is named, not taken as moved" || bad "absent sibling rc=$rc: $out"
mv "$TMP/landing.away" "$H/landing"
out=$( cd "$CL" && ./sync.sh --pin --siblings-moved "$H" 2>&1 ); rc=$?
[ $rc -eq 0 ] && [ ! -e "$H/docs/cadence-sync.lock" ] && grep -q "WARN  docs-site/.claude/settings.json (2 call(s) into the home's scripts/) — --siblings-moved given" <<< "$out" \
    && ok "TD-147: --siblings-moved migrates the home, with a WARN per sibling still calling its scripts/" || bad "moved rc=$rc: $out"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR\\"/../home-repo/scripts/check_anchor.py --hook"}]}]}}\n' \
    > "$H/landing/.claude/settings.local.json"
git -C "$H" checkout -q -- . && git -C "$H" clean -qfd -e docs-site -e landing && git -C "$H" reset -q --hard HEAD
out=$(pin "$H"); rc=$?
[ $rc -eq 2 ] && grep -q "landing/.claude/settings.local.json (1 call(s) into the home's scripts/)" <<< "$out" \
    && ok "TD-147: a sibling's settings.local.json calling ../<home>/scripts/ is named too (./scripts/ is not)" || bad "local rc=$rc: $out"
H2="$TMP/home-moved"; consumer "$H2"
printf 'docs-site worktree\n' > "$H2/docs/nested-repos.txt"; printf '/docs-site/\n' >> "$H2/.gitignore"
git -C "$H2" add -A && git -C "$H2" commit -qm "a home whose sibling has moved"
mkdir -p "$H2/docs-site/.claude"; printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"agent-cadence -C .. hook session-start"}]}]}}\n' > "$H2/docs-site/.claude/settings.json"
out=$(pin "$H2"); rc=$?
[ $rc -eq 0 ] && ! grep -q "constellation\|docs-site" <<< "$out" && ok "TD-147: a home whose siblings no longer call its scripts/ migrates with no flag" || bad "home moved rc=$rc: $out"

# --- 4) adopt (a new repo) seeds the same pointers, and a rerun of it is not refused for them
A="$TMP/fresh"; git init -q -b main "$A"; git -C "$A" commit -q --allow-empty -m init
out=$( cd "$CL" && python3 "$DC/launcher/agent_cadence.py" -C "$CL" adopt "$A" 2>&1 ); rc=$?
out2=$( cd "$CL" && python3 "$DC/launcher/agent_cadence.py" -C "$CL" adopt "$A" 2>&1 ); rc2=$?
[ $rc -eq 0 ] && [ $rc2 -eq 0 ] && cmp -s "$A/.claude/skills/cadence/SKILL.md" "$R/.claude/skills/cadence/SKILL.md" \
    && ok "adopt seeds the pointers the migration does, and a second adopt is not refused for them" || bad "adopt pointers rc=$rc/$rc2: $out2"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
