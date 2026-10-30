#!/usr/bin/env bash
# `agent-cadence adopt` (TD-129, launcher/words.py w_adopt): run from an agent-cadence clone against a NEW
# repo, it seeds what is missing, appends the [agent-cadence] pin (origin's URL, the clone's HEAD, the
# tag as a comment only at a tag), installs the git hook shims and registers the repo — committing
# nothing — and refuses a repo carrying synced copies, a dirty clone, a HEAD origin does not have.
# Offline and fixture-driven: the "agent-cadence clone" is a clone of a temp bare origin built from
# this checkout's launcher/, files/ and sync.sh; HOME, XDG and the roster are temp.
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
rm -rf "$TMP/build/launcher/__pycache__"
git -C "$TMP/build" add -A && git -C "$TMP/build" commit -qm c1 && git -C "$TMP/build" tag v9
git clone -q --bare "$TMP/build" "$ORIGIN"
git clone -q "$ORIGIN" "$CL"
HEAD1=$(git -C "$CL" rev-parse HEAD)
adopt() { (cd "$CL" && python3 "$DC/launcher/agent_cadence.py" -C "$CL" adopt "$@" 2>&1); }
newrepo() { git init -q -b main "$1" && git -C "$1" commit -q --allow-empty -m init; }
pinval() { python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["agent-cadence"][sys.argv[2]])' "$1/docs/cadence.toml" "$2"; }
mapfile -t SEEDS < <(bash -c 'eval "$(sed -n "/^SEED_FILES=(/,/^)/p" "$1")"; printf "%s\n" "${SEED_FILES[@]}"' _ "$DC/sync.sh")

# --- 1) a new repo: seeds, the pin at origin's URL and HEAD with its tag, shims, the roster, no commit
T="$TMP/t1"; newrepo "$T"
out=$(adopt "$T"); rc=$?
missing=""; for f in "${SEEDS[@]}"; do [ -e "$T/$f" ] || missing+=" $f"; done
[ $rc -eq 0 ] && [ -z "$missing" ] && [ ${#SEEDS[@]} -ge 5 ] && ok "every SEED file is created (${#SEEDS[@]})" || bad "seeds rc=$rc missing:$missing / $out"
python3 -c 'import json, sys; f = json.load(open(sys.argv[1]))["context"]["fileName"]; sys.exit(0 if "AGENTS.md" in (f if isinstance(f, list) else [f]) else 1)' "$T/.gemini/settings.json" 2>/dev/null \
    && ok "the seeded .gemini/settings.json makes Gemini CLI read AGENTS.md (TD-111)" || bad "gemini seed: $(cat "$T/.gemini/settings.json" 2>&1)"
[ "$(pinval "$T" source)" = "$ORIGIN" ] && [ "$(pinval "$T" ref)" = "$HEAD1" ] \
    && ok "the pin: source is origin's URL, ref the clone's HEAD" || bad "pin: $(cat "$T/docs/cadence.toml" | tail -4)"
grep -qx "ref = \"$HEAD1\"   # v9" "$T/docs/cadence.toml" && grep -qx '\[agent-cadence\]' "$T/docs/cadence.toml" \
    && ok "HEAD at a tag: the tag is the ref line's comment; the header is written exactly [agent-cadence]" || bad "tag/header: $(tail -3 "$T/docs/cadence.toml")"
grep -qsE '^[[:space:]]*\[agent-cadence\][[:space:]]*(#.*)?$' "$T/docs/cadence.toml" && grep -qF 'agent-cadence hook' "$T/.git/hooks/pre-push" \
    && grep -qF "agent-cadence hook shim (TD-055)" "$T/.git/hooks/pre-push" \
    && ok "the shims are installed, and their pin test finds the pin adopt wrote" || bad "shims: $(ls "$T/.git/hooks") / $out"
[ "$(cat "$AGENT_CADENCE_REG_DIR/repos.txt")" = "$(realpath "$T")" ] && ok "the repo is on the roster" || bad "roster: $(cat "$AGENT_CADENCE_REG_DIR/repos.txt" 2>&1)"
[ "$(git -C "$T" rev-list --count HEAD)" = 1 ] && [ -n "$(git -C "$T" status --porcelain)" ] \
    && ok "nothing committed: the seeds and the pin are left for a PR" || bad "commits: $(git -C "$T" log --oneline)"
python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$T/docs/cadence.toml" && grep -q '^# review-model' "$T/docs/cadence.toml" \
    && ok "the seeded cadence.toml is kept whole, the pin appended" || bad "cadence.toml: $(head -3 "$T/docs/cadence.toml")"

# --- 2) again: idempotent — the pin kept, seeds kept, one roster line
before=$(cat "$T/docs/cadence.toml")
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ "$(cat "$T/docs/cadence.toml")" = "$before" ] && grep -q "already has a \[agent-cadence\] pin" <<< "$out" \
    && grep -q "keep  AGENTS.md" <<< "$out" && [ "$(wc -l < "$AGENT_CADENCE_REG_DIR/repos.txt")" = 1 ] \
    && ok "a second run changes nothing and adds no roster line" || bad "rerun rc=$rc: $out"

# --- 3) a repo's own cadence.toml (no final newline) and its opt-outs: [skip-seed], §4 not adopted
T="$TMP/t3"; newrepo "$T"; mkdir -p "$T/docs"
printf 'review-model = "haiku"\n[skip-seed]\n"AGENTS.md" = "docs/plans/own-map.md"\n[not-adopted]\n"§4" = "docs/plans/no-guard.md"' > "$T/docs/cadence.toml"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ ! -e "$T/AGENTS.md" ] && grep -q "skip  AGENTS.md" <<< "$out" && [ -e "$T/docs/user_attention.md" ] \
    && ok "[skip-seed]: that SEED is never created, the rest are" || bad "skip-seed rc=$rc: $out"
[ ! -e "$T/.git/hooks/pre-push" ] && [ -e "$T/.git/hooks/post-merge" ] && ok "§4 not adopted: no pre-push shim, the other hooks shimmed" || bad "not-adopted: $(ls "$T/.git/hooks")"
[ "$(pinval "$T" ref)" = "$HEAD1" ] && [ "$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["review-model"])' "$T/docs/cadence.toml")" = haiku ] \
    && ok "the pin is appended to the repo's own file after a missing final newline; its keys kept" || bad "own toml: $(cat "$T/docs/cadence.toml")"

# --- 3b) a repo whose ledger is a directory (docs/ledger/, TD-160): no v1 ledger or archive seeded beside it
T="$TMP/t3b"; newrepo "$T"; mkdir -p "$T/docs/ledger"; printf '# Technical Debt\n\nLedgerboard: 2\n' > "$T/docs/ledger/README.md"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ ! -e "$T/docs/technical_debt.md" ] && [ ! -e "$T/docs/technical_debt_archive.md" ] && [ -e "$T/docs/user_attention.md" ] \
    && grep -q "skip  docs/technical_debt.md (the ledger is docs/ledger/, a directory: never created)" <<< "$out" \
    && ok "a v2 ledger: adopt seeds no v1 ledger or archive beside it, the rest as usual" || bad "v2 adopt rc=$rc: $out"

# --- 3c) TD-168 (TD-133, as the retired copy's first sync): the repo's own ledger and board are read by the
# pinned readers first; one they cannot read is refused with the list, and nothing is written
untouched() { [ ! -e "$1/docs/cadence.toml" ] && [ ! -e "$1/AGENTS.md" ] && ! grep -qs "agent-cadence" "$1/.git/hooks/pre-push"; }
refuse() {  # refuse <dir> <what the output names> <label>
  local out rc; out=$(adopt "$1"); rc=$?
  [ $rc -eq 2 ] && [[ "$out" == *"adopt refuses"*"$2"*"nothing was written"* ]] && untouched "$1" && ok "$3" || bad "$3: rc=$rc $out"
}
T="$TMP/t3c1"; newrepo "$T"; mkdir -p "$T/docs"
printf '# Technical Debt\n\n## TD-001: a thing\n\n**Priority:** low\n**Type:** banana\n**Status:** Open\n\n**Why:** x\n' > "$T/docs/technical_debt.md"
refuse "$T" "docs/technical_debt.md: ledger.py --check: ⚠ TD-001: unknown Type 'banana'" "a ledger failing ledger.py --check: refused, the flag named, nothing written"
T="$TMP/t3c2"; newrepo "$T"; mkdir -p "$T/docs"; printf '# Technical Debt\n\n### TD-7: their own shape\n\nx\n' > "$T/docs/technical_debt.md"
refuse "$T" "docs/technical_debt.md:3: a heading the readers skip" "a ledger entry in a shape the readers skip: refused at its line"
T="$TMP/t3c3"; newrepo "$T"; mkdir -p "$T/docs"; printf '# Board\n\n## Needs the user\n\n- decide X\n' > "$T/docs/user_attention.md"
refuse "$T" "docs/user_attention.md:5: a list line the readers skip" "a board line that is not a - [ ] item: refused at its line"
T="$TMP/t3c4"; newrepo "$T"; mkdir -p "$T/docs"; printf '# Technical Debt\n\nLedgerboard: 99\n' > "$T/docs/technical_debt.md"
refuse "$T" "docs/technical_debt.md: " "a ledger declaring a newer format major: refused"
T="$TMP/t3c5"; newrepo "$T"; mkdir -p "$T/docs/ledger"; printf '# Technical Debt\n\nLedgerboard: 2\n' > "$T/docs/ledger/README.md"
printf '## TD-002: wrong file\n\n**Priority:** low\n**Type:** debt\n**Status:** Open\n\n**Why:** x\n' > "$T/docs/ledger/TD-001.md"
refuse "$T" "docs/ledger/: ledger.py --check" "a v2 ledger failing ledger.py --check: refused"

# --- 4) refusals, each exit 2 with its reason, nothing written
refuse() {  # refuse <label> <expected text> <target>
    local out rc; out=$(adopt "$3"); rc=$?
    [ $rc -eq 2 ] && grep -q -- "$2" <<< "$out" && [ ! -e "$3/AGENTS.md" ] && ok "refused: $1" || bad "$1: rc=$rc $out"
}
T="$TMP/t4"; newrepo "$T"; mkdir -p "$T/scripts"; echo x > "$T/scripts/cadence_hooks.sh"
refuse "a repo carrying a synced copy (the migration is sync.sh's)" "carries synced copies (scripts/cadence_hooks.sh" "$T"
T="$TMP/t5"; newrepo "$T"; mkdir -p "$T/docs"; echo x > "$T/docs/cadence-sync.lock"
refuse "a repo with a sync lock" "carries synced copies (docs/cadence-sync.lock" "$T"
refuse "agent-cadence's own clone" "is an agent-cadence clone" "$CL"
mkdir -p "$TMP/plain"; refuse "not a git checkout" "is not a git checkout" "$TMP/plain"
T="$TMP/t8"; newrepo "$T"; mkdir -p "$T/docs"; printf 'agent-cadence.source = "x"\nagent-cadence.ref = "y"\n' > "$T/docs/cadence.toml"
refuse "a pin in a form the hooks cannot detect (a dotted key)" "pins agent-cadence in another TOML form" "$T"
T="$TMP/t9"; newrepo "$T"; git -C "$CL" remote set-url origin "https://u:s3cret@example.com/dc.git"
refuse "an origin URL carrying a credential" "carries a credential" "$T"
git -C "$CL" remote set-url origin "https://ghp_t0ken@example.com/dc.git"
refuse "an https origin URL carrying a bare token" "carries a credential" "$T"
git -C "$CL" remote set-url origin "$ORIGIN"
T="$TMP/t6"; newrepo "$T"
echo dirty >> "$CL/sync.sh"
refuse "a clone with uncommitted changes" "has uncommitted changes" "$T"
git -C "$CL" checkout -q sync.sh
git -C "$CL" commit -q --allow-empty -m local-only
refuse "a HEAD origin does not have" "is not on origin's default branch" "$T"
git -C "$CL" push -q origin HEAD:side
refuse "a HEAD only on another of origin's branches" "is not on origin's default branch (main" "$T"
out=$(adopt); rc=$?
[ $rc -eq 2 ] && grep -q "adopt takes the repo" <<< "$out" && ok "refused: no repo named" || bad "no arg: rc=$rc $out"

# --- 5) a pushed HEAD that is not at a tag: no tag comment
git -C "$CL" push -q origin HEAD:main
HEAD2=$(git -C "$CL" rev-parse HEAD)
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qx "ref = \"$HEAD2\"" "$T/docs/cadence.toml" && ok "HEAD not at a tag: the ref line carries no comment" || bad "no tag rc=$rc: $(grep ref "$T/docs/cadence.toml") / $out"

# --- 5b) seeds come from the pinned commit, never the clone's work tree; a linked worktree target
# adopts its main checkout
echo "# untracked, not pinned" > "$CL/files/README-local.md"; cp "$CL/files/AGENTS.md" "$TMP/agents.orig"
T="$TMP/t10"; newrepo "$T"; git -C "$T" worktree add -q "$TMP/t10-wt" -b wt
printf 'local edit\n' >> "$CL/files/AGENTS.md"; git -C "$CL" update-index --assume-unchanged files/AGENTS.md
out=$(adopt "$TMP/t10-wt"); rc=$?
git -C "$CL" update-index --no-assume-unchanged files/AGENTS.md; cp "$TMP/agents.orig" "$CL/files/AGENTS.md"
[ $rc -eq 0 ] && cmp -s "$T/AGENTS.md" "$TMP/agents.orig" && ok "a seed is the pinned commit's file, not the clone's edited copy" || bad "seed source rc=$rc: $out"
[ -e "$T/docs/cadence.toml" ] && [ ! -e "$TMP/t10-wt/docs/cadence.toml" ] && ok "a linked worktree named: its main checkout is adopted" || bad "worktree target: $out"

# --- 6) a temp-dir repo is never written to a roster outside the temp roots (TD-068)
T="$TMP/fx/t7"; mkdir -p "$TMP/fx"; newrepo "$T"
out=$( cd "$CL" && CADENCE_TEMP_ROOTS="$TMP/fx" python3 "$DC/launcher/agent_cadence.py" -C "$CL" adopt "$T" 2>&1 ); rc=$?
[ $rc -eq 0 ] && grep -q "registration skipped" <<< "$out" && ! grep -qxF "$(realpath "$T")" "$AGENT_CADENCE_REG_DIR/repos.txt" \
    && ok "a temp-dir repo and a roster outside the temp roots: registration skipped, said" || bad "temp roster rc=$rc: $out"

# --- 6b) TD-187 (cadence.md §7.14): the .gitattributes seed makes text LF; adopt converts nothing but says
# what the repo does once — a CRLF index, an own .gitattributes with no LF line
T="$TMP/t1"
grep -qx '\* text=auto eol=lf' "$T/.gitattributes" && [ "$(git -C "$T" check-attr eol -- x.md)" = "x.md: eol: lf" ] \
    && ok "the seeded .gitattributes makes text LF" || bad "gitattributes seed: $(cat "$T/.gitattributes" 2>&1)"
[ "$(sed 3d "$DC/.gitattributes")" = "$(sed 3d "$DC/files/.gitattributes")" ] \
    && ok "this repo's own .gitattributes is its seed's (but the line naming which it is)" || bad "own .gitattributes differs from the seed"
T="$TMP/t6b"; newrepo "$T"; printf 'a\r\nb\r\n' > "$T/w.md"; printf 'c\n' > "$T/u.md"; git -C "$T" add w.md u.md; git -C "$T" commit -qm crlf
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qF "1 file(s) are CRLF in the index" <<< "$out" && grep -qF 'add --renormalize .' <<< "$out" \
    && [ "$(git -C "$T" show HEAD:w.md | od -An -c | tr -d ' \n')" = 'a\r\nb\r\n' ] && ! grep -q "has no \`\* text=auto eol=lf\` line" <<< "$out" \
    && ok "a CRLF index: counted and the one-time renormalize named; nothing converted" || bad "crlf rc=$rc: $out"
T="$TMP/t6c"; newrepo "$T"; printf '*.sh text eol=lf\n' > "$T/.gitattributes"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -q "keep  .gitattributes" <<< "$out" && grep -qF "has no \`* text=auto eol=lf\` line: add it by hand" <<< "$out" \
    && [ "$(cat "$T/.gitattributes")" = '*.sh text eol=lf' ] && ! grep -q "CRLF in the index" <<< "$out" \
    && ok "an own .gitattributes with no LF rule: kept as it is, the line to add named" || bad "own attrs rc=$rc: $out"

# --- 6c) TD-168: the retired copy's two detectors, for a SEED the repo already had — warn, never rewrite
T="$TMP/t1"; out=$(adopt "$T")
! grep -q "SessionStart\|context.fileName" <<< "$out" && ok "the seeds as adopt wrote them: no SessionStart or Gemini warning" || bad "seeded warns: $out"
T="$TMP/t6d"; newrepo "$T"; mkdir -p "$T/.claude" "$T/.gemini"
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "scripts/old_hook.sh"}]}]}}\n' > "$T/.claude/settings.json"
printf '{"context": {"fileName": "GEMINI.md"}}\n' > "$T/.gemini/settings.json"
cp "$T/.claude/settings.json" "$TMP/s.before"; cp "$T/.gemini/settings.json" "$TMP/g.before"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qF ".claude/settings.json: SessionStart lacks the cadence line" <<< "$out" \
    && grep -qF ".gemini/settings.json: context.fileName does not name AGENTS.md" <<< "$out" \
    && cmp -s "$T/.claude/settings.json" "$TMP/s.before" && cmp -s "$T/.gemini/settings.json" "$TMP/g.before" \
    && ok "own settings with no cadence line and a Gemini map without AGENTS.md: both warned, neither rewritten" || bad "warns rc=$rc: $out"
T="$TMP/t6e"; newrepo "$T"; mkdir -p "$T/.claude" "$T/.gemini"
printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "scripts/cadence_hooks.sh --session-start"}]}]}}\n' > "$T/.claude/settings.json"
printf '{"context": {"fileName": ["AGENTS.md"]}}\n' > "$T/.gemini/settings.json"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qF ".claude/settings.json: the cadence SessionStart line differs from the seed" <<< "$out" \
    && ! grep -q "context.fileName" <<< "$out" \
    && ok "an older cadence line: 'differs' warned; a Gemini map naming AGENTS.md: silent" || bad "differs rc=$rc: $out"
T="$TMP/t6f"; newrepo "$T"; mkdir -p "$T/.claude" "$T/.gemini" "$T/docs"
printf '{not json\n' > "$T/.claude/settings.json"; python3 -c 'print("[" * 100000)' > "$T/.gemini/settings.json"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qF ".claude/settings.json: not readable as settings JSON" <<< "$out" \
    && grep -qF ".gemini/settings.json: not readable as settings JSON" <<< "$out" && grep -q "^Next, in" <<< "$out" \
    && ok "unreadable settings (bad JSON, nesting deep enough to raise RecursionError): said, adopt runs to its end" || bad "unreadable rc=$rc: $out"
# a migration: a cadence line that differs is _session_line's (no second WARN), a missing one is warned
W=$(cd "$DC/launcher" && python3 - "$TMP/t6e" "$TMP/t6d" "$DC/files/.claude/settings.json" <<'PY'
import sys, words
seed = {".claude/settings.json": open(sys.argv[3], "rb").read()}
for d in sys.argv[1:3]:
    print(len(words._seed_warnings(d, seed, {}, True)), *[w.split(":")[1].strip()[:14] for w in words._seed_warnings(d, seed, {}, True)])
PY
)
[ "$W" = $'0\n2 SessionStart l context.fileNa' ] && ok "--migrate: a differing line left to _session_line, a missing one still warned" || bad "migrate warns: [$W]"
T="$TMP/t6g"; newrepo "$T"; mkdir -p "$T/.gemini" "$T/docs"
printf '{}\n' > "$T/.gemini/settings.json"; printf '[skip-seed]\n".gemini/settings.json" = "docs/plans/no-gemini.md"\n' > "$T/docs/cadence.toml"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && ! grep -q "context.fileName" <<< "$out" && ok "a skipped Gemini seed is not checked" || bad "skip gemini rc=$rc: $out"

# --- 6h) TD-168: the retired copy's .gitignore step — the literal lines a new repo's own .gitignore needs,
# appended after a missing final newline, a worktree-root other than the default added; a rerun adds nothing
T="$TMP/t1"
[ "$(cat "$T/.gitignore")" = $'docs/session_index.md\n.claude/settings.local.json\n.claude/worktrees/\n*.code-workspace' ] \
    && git -C "$T" check-ignore -q .claude/worktrees/x && ok "a new repo: the four .gitignore lines" || bad "gitignore: $(cat "$T/.gitignore" 2>&1)"
T="$TMP/t6h"; newrepo "$T"; mkdir -p "$T/docs"; printf 'node_modules/\n*.code-workspace' > "$T/.gitignore"
printf 'worktree-root = "wt"\n' > "$T/docs/cadence.toml"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ "$(cat "$T/.gitignore")" = $'node_modules/\n*.code-workspace\ndocs/session_index.md\n.claude/settings.local.json\n.claude/worktrees/\nwt/' ] \
    && grep -qF "conf  *.code-workspace already in .gitignore" <<< "$out" && grep -qF "conf  wt/ added to .gitignore" <<< "$out" \
    && ok "an own .gitignore with no final newline: kept, the missing lines appended, worktree-root's directory too" || bad "own gitignore rc=$rc: $out / $(cat "$T/.gitignore")"
cp "$T/.gitignore" "$TMP/gi.before"; out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && cmp -s "$T/.gitignore" "$TMP/gi.before" && ! grep -q "added to .gitignore" <<< "$out" \
    && ok "a rerun adds no .gitignore line" || bad "gitignore rerun rc=$rc: $out"
T="$TMP/t6i"; newrepo "$T"; printf 'x/\n' > "$TMP/gi.target"; ln -s "$TMP/gi.target" "$T/.gitignore"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ "$(cat "$TMP/gi.target")" = "x/" ] && grep -qF ".gitignore is a symlink — not written through" <<< "$out" \
    && ok "a symlinked .gitignore: warned, never written through" || bad "symlink gitignore rc=$rc: $out"
T="$TMP/t6j"; newrepo "$T"; mkdir "$T/.gitignore"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qF ".gitignore not written" <<< "$out" && grep -qF "agent-cadence hook" "$T/.git/hooks/pre-push" \
    && grep -qxF "$(realpath "$T")" "$AGENT_CADENCE_REG_DIR/repos.txt" \
    && ok "a .gitignore that cannot be read (a directory): warned, and adopt still installs the shims and registers" || bad "dir gitignore rc=$rc: $out"

# --- 6k) TD-168: the retired copy's memory-path step — the clone root's absolute docs/claude-memory merged into
# its .claude/settings.local.json; a value there, a file that does not parse and a symlink are said and left alone
amd() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("autoMemoryDirectory"))' "$1/.claude/settings.local.json"; }
T="$TMP/t1"
[ "$(amd "$T")" = "$(realpath "$T")/docs/claude-memory" ] && ! git -C "$T" status --porcelain | grep -q settings.local \
    && ok "a new repo: autoMemoryDirectory is the clone root's absolute docs/claude-memory, in an ignored file" || bad "memdir: $(cat "$T/.claude/settings.local.json" 2>&1)"
out=$(adopt "$T")
grep -qF "conf  autoMemoryDirectory already set" <<< "$out" && ok "a rerun: already set" || bad "memdir rerun: $out"
T="$TMP/t6k"; newrepo "$T"; mkdir -p "$T/.claude"; printf '{"permissions": {"allow": ["Bash(ls)"]}}\n' > "$T/.claude/settings.local.json"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ "$(amd "$T")" = "$(realpath "$T")/docs/claude-memory" ] \
    && [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["allow"][0])' "$T/.claude/settings.local.json")" = "Bash(ls)" ] \
    && ok "an own settings.local.json: the key merged, the rest kept" || bad "merge rc=$rc: $out / $(cat "$T/.claude/settings.local.json")"
T="$TMP/t6l"; newrepo "$T"; mkdir -p "$T/.claude"; printf '{"autoMemoryDirectory": "/elsewhere"}\n' > "$T/.claude/settings.local.json"
cp "$T/.claude/settings.local.json" "$TMP/sl.before"; out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && cmp -s "$T/.claude/settings.local.json" "$TMP/sl.before" && grep -qF 'autoMemoryDirectory is "/elsewhere"' <<< "$out" \
    && ok "another value already set: warned, left alone" || bad "other value rc=$rc: $out"
T="$TMP/t6m"; newrepo "$T"; mkdir -p "$T/.claude"; printf '{nope\n' > "$T/.claude/settings.local.json"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ "$(cat "$T/.claude/settings.local.json")" = "{nope" ] && grep -qF "could not be parsed" <<< "$out" && grep -q "^Next, in" <<< "$out" \
    && ok "a settings.local.json that does not parse: warned, untouched, adopt runs to its end" || bad "bad json rc=$rc: $out"
T="$TMP/t6n"; newrepo "$T"; mkdir -p "$T/.claude"; printf '{}\n' > "$TMP/sl.target"; ln -s "$TMP/sl.target" "$T/.claude/settings.local.json"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && [ "$(cat "$TMP/sl.target")" = "{}" ] && [ -L "$T/.claude/settings.local.json" ] && grep -qF "is a symlink — left untouched" <<< "$out" \
    && ok "a symlinked settings.local.json: warned, the link and its target untouched" || bad "symlink rc=$rc: $out"

# --- 6o) TD-168: the opt-out WARNs test_sync_optout.sh 4–5b held through sync.sh — a declaration adopt cannot
# read opts nothing out, says so, and adopt seeds the whole payload rather than guess (Adoption checklist step 9)
T="$TMP/t6o"; newrepo "$T"; mkdir -p "$T/docs"; printf 'skip-seed: AGENTS.md — docs/plans/x.md\n' > "$TMP/local.target"
ln -s "$TMP/local.target" "$T/docs/cadence-local.conf"
out=$(adopt "$T"); rc=$?
[ $rc -eq 0 ] && grep -qF "WARN  docs/cadence-local.conf: is a symlink — not read; nothing is opted out" <<< "$out" && [ -e "$T/AGENTS.md" ] \
    && ok "a symlinked legacy declaration: warned, nothing opted out, every SEED created" || bad "symlink optout rc=$rc: $out"
T="$TMP/t6p"; newrepo "$T"; mkdir -p "$T/docs"; printf 'skip-seed: AGENTS.md — docs/plans/x.md\n' > "$T/docs/cadence-local.conf"
chmod 000 "$T/docs/cadence-local.conf"
if [ -r "$T/docs/cadence-local.conf" ]; then
    ok "an unreadable legacy declaration: skipped (running as root, chmod does not bite)"
else
    out=$(adopt "$T"); rc=$?
    [ $rc -eq 0 ] && grep -qF "WARN  docs/cadence-local.conf: cannot read (Permission denied) — nothing is opted out from it" <<< "$out" \
        && [ -e "$T/AGENTS.md" ] && ok "an unreadable legacy declaration: warned, nothing opted out, every SEED created" || bad "unreadable optout rc=$rc: $out"
fi
chmod 644 "$T/docs/cadence-local.conf"

# --- 7) parity: adopt's reading of sync.sh's arrays is bash's own
for a in SYNC_FILES SEED_FILES; do
    want=$(bash -c 'eval "$(sed -n "/^$2=(/,/^)/p" "$1")"; eval "printf \"%s\n\" \"\${$2[@]}\""' _ "$DC/sync.sh" "$a")
    got=$(cd "$DC/launcher" && python3 -c 'import sys, words; print("\n".join(words._sh_array(sys.argv[1])))' "$a")
    [ -n "$want" ] && [ "$got" = "$want" ] && ok "words._sh_array($a) reads sync.sh as bash does" || bad "$a: got [$got] want [$want]"
done

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
