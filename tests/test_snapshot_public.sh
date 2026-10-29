#!/usr/bin/env bash
# snapshot_public.sh (TD-090): the public tree is HEAD minus the private paths, with the README's
# note, and the scrub gate over it — the machine's publish-names, dead links, the accept list; an
# out-dir that is not empty, is dirty, or shares history with the repo is refused. Offline: a
# fixture repo carrying this checkout's script and files/scripts/, a fixture machine file.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.test
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
printf 'publish-names = ["Zelda"]\n' > "$DEV_CADENCE_REG_DIR/cadence.toml"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"; mkdir -p "$R/files/docs" "$R/docs" "$R/tests" "$R/.claude"
cp "$DC/snapshot_public.sh" "$R/"
(cd "$DC" && git ls-files -z files/scripts | xargs -0 cp --parents -t "$R")   # tracked files only: no __pycache__
printf '# fx\n\nSee [the plan](docs/plan.md) and [ok](files/docs/ok.md).\n' > "$R/README.md"
printf 'fine\n' > "$R/files/docs/ok.md"
printf 'Zelda decided this\n' > "$R/docs/plan.md"
printf 'Zelda only\n' > "$R/CLAUDE.md"; printf '{}\n' > "$R/.claude/settings.json"
printf '# asked Zelda\ncd /home/realname/x\n' > "$R/tests/a.sh"
git -C "$R" init -q -b main && git -C "$R" add -A && git -C "$R" commit -qm fx
printf 'Zelda, uncommitted\n' > "$R/tests/new.sh"; printf 'Zelda\n' >> "$R/files/docs/ok.md"
SNAP="$R/snapshot_public.sh"

# 1. a new directory: HEAD's tree minus the private paths, the note, the findings
A="$TMP/accept.txt"; printf 'files/scripts/cadence_layer.py a machine path (*)\n' > "$A"   # the check's own patterns
O="$TMP/o1"; out=$(SNAPSHOT_ACCEPT="$A" "$SNAP" "$O" 2>&1); rc=$?
[ $rc = 1 ] && [ -f "$O/files/scripts/cadence_layer.py" ] && [ -f "$O/snapshot_public.sh" ] \
  && [ ! -e "$O/docs" ] && [ ! -e "$O/CLAUDE.md" ] && [ ! -e "$O/.claude" ] \
  && ok "1 written, minus docs/, CLAUDE.md, .claude/; exit 1 on findings" || bad "1 rc=$rc $(ls -A "$O" 2>&1) $out"
[ "$(sed -n 3p "$O/README.md")" = '> *dev-cadence, published as agent-cadence.* Each release here is one snapshot commit of the canonical tree, which is kept elsewhere; the tool, its commands and its docs keep the name dev-cadence.' ] \
  && [ "$(sed -n 1p "$O/README.md")" = "# fx" ] && ok "1b the note under the README's title" || bad "1b $(head -3 "$O/README.md")"
# the dogfood suites know a published tree by this note: each one's pattern is the same, and matches it
MARK="snapshot() { grep -q '^> \\*dev-cadence, published as agent-cadence\\.\\*' \"\$1/README.md\"; }"
n=0; for f in test_briefs_primer test_cadence_hooks test_ledger test_ledger_archive test_ledger_links test_parity; do grep -qxF "$MARK" "$DC/tests/$f.sh" && n=$((n+1)); done
[ $n = 6 ] && grep -q '^> \*dev-cadence, published as agent-cadence\.\*' "$O/README.md" \
  && ok "1e the six dogfood suites' snapshot() pattern is one, and matches the note" || bad "1e $n of 6 carry the pattern"
grep -qxF "tests/a.sh:1: a name your publish-names lists (Zelda)" <<< "$out" \
  && grep -qxF "tests/a.sh:2: a machine path (/home/realname)" <<< "$out" \
  && grep -qxF "README.md:5: a link to a file the tree lacks (docs/plan.md)" <<< "$out" \
  && grep -q "^gate: 3 findings to judge, [0-9]* accepted$" <<< "$out" \
  && ok "1c the machine's name, a machine path and a dead link into docs/ are findings" || bad "1c $out"
[ ! -e "$O/tests/new.sh" ] && [ -z "$(find "$O" -name __pycache__)" ] && ! grep -q Zelda "$O/files/docs/ok.md" && ! grep -q "ok.md" <<< "$out" \
  && ok "1d only what is committed (no untracked file, no working-tree edit), and the gate leaves no bytecode" || bad "1d $out"

# 2. the accept list: matched findings drop, an unused line is named, exit 0 on none left
printf '# c\ntests/a.sh a name your publish-names lists (Zelda)\ntests/* a machine path (*)\nREADME.md a link to a file the tree lacks (docs/*)\nnowhere/* *\nfiles/scripts/cadence_layer.py a machine path (*)\n' > "$A"
O="$TMP/o2"; out=$(SNAPSHOT_ACCEPT="$A" "$SNAP" "$O" 2>&1); rc=$?
[ $rc = 0 ] && grep -q "^gate: 0 findings to judge, [0-9]* accepted — clean$" <<< "$out" \
  && grep -qF "accept line 5 (nowhere/* *) matched nothing" <<< "$out" \
  && ok "2 accepted findings drop; a stale accept line is named; exit 0" || bad "2 rc=$rc $out"
printf 'tests/a.sh a machine path (*)\n' > "$A"
out=$(SNAPSHOT_ACCEPT="$A" "$SNAP" "$TMP/o2b" 2>&1); rc=$?
[ $rc = 1 ] && grep -qxF "tests/a.sh:1: a name your publish-names lists (Zelda)" <<< "$out" \
  && ok "2b accepting one finding of a file keeps its others" || bad "2b rc=$rc $out"

# 3. refusals, each before anything is written or removed
O="$TMP/o3"; mkdir -p "$O"; echo keep > "$O/x"
out=$("$SNAP" "$O" 2>&1); rc=$?
[ $rc = 2 ] && [ "$(ls -A "$O")" = x ] && grep -q "neither empty nor a git repo" <<< "$out" \
  && ok "3 a non-empty directory that is no repo: refused, untouched" || bad "3 rc=$rc $out"
O="$TMP/o4"; git clone -q "$R" "$O"
out=$("$SNAP" "$O" 2>&1); rc=$?
[ $rc = 2 ] && [ -f "$O/docs/plan.md" ] && grep -q "shares commit .* with this repo" <<< "$out" \
  && ok "3b a clone sharing history with the repo: refused, untouched" || bad "3b rc=$rc $out"
O="$TMP/o5"; git init -q -b main "$O"; echo old > "$O/old.txt"; git -C "$O" add -A; git -C "$O" commit -qm pub; echo dirty >> "$O/old.txt"
out=$("$SNAP" "$O" 2>&1); rc=$?
[ $rc = 2 ] && [ "$(cat "$O/old.txt")" = "$(printf 'old\ndirty')" ] && grep -q "uncommitted or untracked" <<< "$out" \
  && ok "3c a dirty clone of the public repo: refused, untouched" || bad "3c rc=$rc $out"
out=$("$SNAP" "$R/tests/inside" 2>&1); rc=$?
[ $rc = 2 ] && grep -q "is inside this repo" <<< "$out" && [ ! -e "$R/tests/inside" ] \
  && ok "3d an out-dir inside the repo: refused, nothing created" || bad "3d rc=$rc $out"
out=$("$SNAP" "$TMP" 2>&1); rc=$?
[ $rc = 2 ] && grep -q "holds this repo" <<< "$out" && [ -f "$R/README.md" ] \
  && ok "3e an out-dir holding the repo: refused" || bad "3e rc=$rc $out"
git -C "$O" checkout -q -- old.txt; echo stray > "$O/stray.txt"; git -C "$O" config status.showUntrackedFiles no
out=$("$SNAP" "$O" 2>&1); rc=$?
[ $rc = 2 ] && [ -f "$O/stray.txt" ] && [ -f "$O/old.txt" ] && grep -q "untracked" <<< "$out" \
  && ok "3f an untracked file, even hidden from status by config: refused, untouched" || bad "3f rc=$rc $out"
rm "$O/stray.txt"

# 4. a clean clone of the public repo: every tracked file replaced, an ignored one kept, the release a diff to commit
printf '.env\n' > "$O/.gitignore"; git -C "$O" add .gitignore; git -C "$O" commit -qm ignore; echo SECRET=1 > "$O/.env"
printf '* *\n' > "$A"
out=$(SNAPSHOT_ACCEPT="$A" "$SNAP" "$O" 2>&1); rc=$?
[ $rc = 0 ] && [ ! -e "$O/old.txt" ] && [ -f "$O/README.md" ] && [ "$(git -C "$O" rev-list --count HEAD)" = 2 ] \
  && git -C "$O" status --porcelain | grep -q "^ D old.txt$" && [ "$(cat "$O/.env")" = SECRET=1 ] \
  && ok "4 a clean public clone: tracked files replaced, an ignored .env kept, nothing committed" || bad "4 rc=$rc $out $(git -C "$O" status --porcelain)"

# 4b. the public tree names its own repo, and drops what is true only of the private one
U="$TMP/url"; git clone -q "$R" "$U"; P="ShiftLead/dev""-cadence"   # in pieces: the published copy of this test is rewritten too
printf 'clone https://github.com/%s or git@github.com:%s.git; %s-x stays\nInstall it. <!-- private: -->Needs a token.<!-- :private --> Then run.\n' "$P" "$P" "$P" > "$U/files/docs/url.md"
printf '# %s <!-- private: --> kept in a script\n' "$P" > "$U/tests/b.sh"
git -C "$U" add -A; git -C "$U" commit -qm url
out=$(SNAPSHOT_ACCEPT="$A" "$U/snapshot_public.sh" "$TMP/o4b" 2>&1); rc=$?
[ $rc = 0 ] && [ "$(sed -n 1p "$TMP/o4b/files/docs/url.md")" = "clone https://github.com/ShiftLead/agent-cadence or git@github.com:ShiftLead/agent-cadence.git; $P-x stays" ] \
  && [ "$(sed -n 2p "$TMP/o4b/files/docs/url.md")" = 'Install it. Then run.' ] && grep -qF "$P or" "$U/files/docs/url.md" \
  && [ "$(cat "$TMP/o4b/tests/b.sh")" = '# ShiftLead/agent-cadence <!-- private: --> kept in a script' ] \
  && ok "4b the repo's address is the public one's, a .md private span is dropped (a script's is kept), the source is untouched" || bad "4b rc=$rc $out $(cat "$TMP/o4b/files/docs/url.md")"
printf 'open <!-- private: -->never closed\n' > "$U/files/docs/url.md"; git -C "$U" commit -qam open
out=$(SNAPSHOT_ACCEPT="$A" "$U/snapshot_public.sh" "$TMP/o4c" 2>&1); rc=$?
[ $rc = 2 ] && grep -q "url.md has a private span that does not close" <<< "$out" && ! grep -q "clean" <<< "$out" \
  && ok "4c a private span left open: exit 2, never clean" || bad "4c rc=$rc $out"

# 5. a gate that crashes, or prints what the filter cannot read, never reads as clean
C="$TMP/crash"; git clone -q "$R" "$C"; printf 'raise RuntimeError("boom")\n' > "$C/files/scripts/cadence_layer.py"
git -C "$C" commit -qam crash
out=$(SNAPSHOT_ACCEPT="$A" "$C/snapshot_public.sh" "$TMP/o6" 2>&1); rc=$?
[ $rc = 2 ] && grep -q "unchecked" <<< "$out" && ! grep -q "clean" <<< "$out" \
  && ok "5 a crashing gate: exit 2, unchecked, never clean" || bad "5 rc=$rc $out"
printf 'import sys\nprint("all good")\nsys.exit(0)\n' > "$C/files/scripts/cadence_layer.py"; git -C "$C" commit -qam quiet
out=$(SNAPSHOT_ACCEPT="$A" "$C/snapshot_public.sh" "$TMP/o7" 2>&1); rc=$?
[ $rc = 2 ] && grep -q "cannot read (all good)" <<< "$out" \
  && ok "5b a gate whose output the filter cannot read: exit 2" || bad "5b rc=$rc $out"

# 6. --seed (TD-190): the cut-over's first commit — docs/ and the rest carried, minus the plans, the
# archive and the private accept list; docs/seed/ laid over; the board's open items only; a link into
# docs/plans/ named, not dead; the archive's README naming the last private id; the public accept list
Q="$TMP/seedrepo"; git clone -q "$R" "$Q"; mkdir -p "$Q/docs/ledger/archive" "$Q/docs/seed/docs/ledger/archive" "$Q/docs/plans"
printf '# fx\n\nSee [ok](files/docs/ok.md).\n' > "$Q/README.md"
printf 'Zelda decided this\n' > "$Q/docs/plans/plan.md"; git -C "$Q" rm -q docs/plan.md
printf '# ledger\n\nLedgerboard: 2\n' > "$Q/docs/ledger/README.md"
printf '## TD-007: open\n\n**Status:** Open — see [the plan](../plans/plan.md#why)\n**Blocked by:** TD-003, TD-005, decision (Zelda) — once TD-003 lands\n' > "$Q/docs/ledger/TD-007.md"
printf '## TD-005: open\n\n**Status:** Open — [docs/plans/plan.md](../plans/plan.md), not `[x](../plans/plan.md)`\n**Blocked by:** TD-003 (landed), decision (Zelda, x) — once TD-003 lands\n' > "$Q/docs/ledger/TD-005.md"
printf '## TD-003: done\n\n**Status:** Resolved — Zelda\n' > "$Q/docs/ledger/archive/TD-003.md"
printf '# board\n\n- [x] 2026-01-01 done, by Zelda\n  more of the done item\n- [ ] 2026-01-02 still open\n' > "$Q/docs/user_attention.md"
printf 'docs/* a name your publish-names lists (Zelda)\n' > "$Q/docs/publish-accept.txt"
printf '# archive\n\n**Private through:** TD-@LAST@\n' > "$Q/docs/seed/docs/ledger/archive/README.md"
printf 'publish-gate = "required"\n' > "$Q/docs/seed/docs/cadence.toml"
printf 'files/scripts/cadence_layer.py a machine path (*)\ntests/* *\nCLAUDE.md *\ndocs/* * :: *decision (Zelda*\n' > "$Q/docs/seed/docs/publish-accept.txt"
git -C "$Q" add -A; git -C "$Q" commit -qm seed-fixture
O="$TMP/o8"; out=$("$Q/snapshot_public.sh" --seed "$O" 2>&1); rc=$?
[ -f "$O/docs/ledger/TD-007.md" ] && [ -f "$O/CLAUDE.md" ] && [ -f "$O/.claude/settings.json" ] \
  && [ ! -e "$O/docs/plans/plan.md" ] && [ ! -e "$O/docs/ledger/archive/TD-003.md" ] && [ ! -e "$O/docs/seed" ] \
  && [ "$(cat "$O/docs/cadence.toml")" = 'publish-gate = "required"' ] && ! grep -qxF "docs/* a name your publish-names lists (Zelda)" "$O/docs/publish-accept.txt" \
  && ok "6 --seed: docs/ carried, minus the plans, the archive and the private accept list; docs/seed/ laid over" || bad "6 rc=$rc $(find "$O/docs" | sort) $out"
[ "$(sed -n 3p "$O/docs/ledger/archive/README.md")" = "**Private through:** TD-7" ] \
  && ok "6b the archive's README names the last private id (no counter here: the highest filed)" || bad "6b $(cat "$O/docs/ledger/archive/README.md")"
grep -qxF -- "- [ ] 2026-01-02 still open" "$O/docs/user_attention.md" && ! grep -q "done" "$O/docs/user_attention.md" \
  && ok "6c the board keeps its open items; a done one goes, with its continuation line" || bad "6c $(cat "$O/docs/user_attention.md")"
grep -qF "**Status:** Open — see the plan (dev-cadence's private plan *plan*)" "$O/docs/ledger/TD-007.md" && ! grep -q "lacks" <<< "$out" \
  && ok "6d a link into docs/plans/ keeps its text and names the plan; no dead link" || bad "6d $(cat "$O/docs/ledger/TD-007.md") $out"
grep -qxF "**Blocked by:** TD-005, decision (Zelda) — once TD-003 lands" "$O/docs/ledger/TD-007.md" \
  && grep -qxF "**Blocked by:** decision (Zelda, x) — once TD-003 lands" "$O/docs/ledger/TD-005.md" \
  && ok "6f a Blocked by loses the ids the seed does not carry (archived privately), a note with its id, a comma in (…) kept" || bad "6f $(cat "$O/docs/ledger/TD-007.md" "$O/docs/ledger/TD-005.md")"
grep -qxF "**Status:** Open — dev-cadence's private plan *plan*, not \`[x](../plans/plan.md)\`" "$O/docs/ledger/TD-005.md" \
  && ok "6g link text that is the path is replaced by the plan's name; a link in a code span is left" || bad "6g $(cat "$O/docs/ledger/TD-005.md")"
[ $rc = 0 ] && grep -q "^gate: 0 findings to judge, [0-9]* accepted — clean$" <<< "$out" \
  && ok "6e the gate runs with the seed's public accept list" || bad "6e rc=$rc $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
