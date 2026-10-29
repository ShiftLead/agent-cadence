#!/usr/bin/env bash
# TD-137: `forge.py in-flight TD-NNN` — is an entry already being worked (cadence.md §2.9).
# PRs naming the id in any state (the PR that filed the entry and a closed-unmerged one do not
# count), origin's branches naming it, the entry's Status on origin/<default> (fetched), an
# archived entry; exit 1 / 0 / 2 (a lookup that could not be made is never "none").
# Offline: origin is a temp bare repo; `gh` is a PATH shim answering `pr list` from a fixture.
# HOME, XDG_CONFIG_HOME, DEV_CADENCE_REG_DIR and git config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CADENCE_FORGE
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list") [ -f "$GH_FAIL" ] && { echo "gh: could not connect" >&2; exit 1; }; cat "$GH_PRS"; exit 0 ;;
esac
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" GH_PRS="$TMP/prs.json" GH_FAIL="$TMP/gh-fail"

# origin: a bare repo whose main has a ledger (TD-050 filed by one commit, TD-051 live) and an archive (TD-040)
ORIGIN="$TMP/origin.git"; git init -q --bare -b main "$ORIGIN"
W="$TMP/work"; git clone -q "$ORIGIN" "$W" 2>/dev/null
mkdir -p "$W/docs"
printf '# Ledger\n\n<!-- ## TD-050: the template comment is no entry -->\n' > "$W/docs/technical_debt.md"
printf '# Archive\n\n## TD-040: an old one\n\n**Status:** Resolved\n' > "$W/docs/technical_debt_archive.md"
git -C "$W" add -A && git -C "$W" commit -qm init
printf '\n## TD-050: the entry under test\n\n**Priority:** medium\n**Status:** Open — waiting for a hand\n\n**Why:** x\n' >> "$W/docs/technical_debt.md"
git -C "$W" commit -qam "file TD-050 (#7)"; FILER=$(git -C "$W" rev-parse HEAD)
printf '\n## TD-051: another\n\n**Priority:** low\n**Status:** Open\n' >> "$W/docs/technical_debt.md"
git -C "$W" commit -qam "file TD-051"
git -C "$W" push -q origin main 2>/dev/null
git -C "$W" remote set-head origin -a >/dev/null 2>&1
R="$TMP/repo"; git clone -q "$ORIGIN" "$R" 2>/dev/null
# origin names no host (a local path): read with the GitHub backend, so the gh shim answers
run() { (cd "$R" && python3 "$S/forge.py" in-flight "$@" 2>&1); }

# 1. the PR that filed the entry, a closed-unmerged one, a TD-0500 lookalike: nothing in flight
cat > "$GH_PRS" <<JSON
[{"number":7,"state":"MERGED","title":"Harvest: TD-050 filed","body":"","headRefName":"harvest","url":"u7","mergeCommit":{"oid":"$FILER"}},
 {"number":8,"state":"CLOSED","title":"TD-050: a first try","body":"","headRefName":"x","url":"u8","mergeCommit":null},
 {"number":9,"state":"OPEN","title":"TD-0500 and TD-5000","body":"","headRefName":"td5000-y","url":"u9","mergeCommit":null}]
JSON
out=$(run TD-050); rc=$?
[ $rc = 0 ] && grep -q "TD-050: nothing in flight" <<< "$out" && grep -q "PR #7 merged .*(filed the entry: not in flight)" <<< "$out" \
  && grep -q "PR #8 closed .*(closed unmerged: not in flight)" <<< "$out" && ! grep -q "PR #9" <<< "$out" \
  && grep -q "Status on origin/main: Open — waiting for a hand" <<< "$out" \
  && ok "1 the filing PR, a closed one and a lookalike id are not in flight; the Status is read" || bad "1 rc=$rc: $out"
grep -q -- '--state all' "$GH_LOG" && grep -q '"TD-50" in:title,body' "$GH_LOG" && grep -q '"TD-050" in:title,body' "$GH_LOG" \
  && ok "1b the forge is asked for every state, as TD-50 and TD-050" || bad "1b: $(cat "$GH_LOG")"

# 2. an open PR naming it in the body: in flight, exit 1
cat > "$GH_PRS" <<'JSON'
[{"number":11,"state":"OPEN","title":"a fix","body":"Resolves td-050.","headRefName":"fix","url":"u11","mergeCommit":null}]
JSON
out=$(run td50); rc=$?
[ $rc = 1 ] && grep -q "PR #11 open  fix  a fix$" <<< "$out" && grep -q "TD-050: in flight" <<< "$out" \
  && ok "2 an open PR naming the id in its body: in flight, exit 1 (id given as td50)" || bad "2 rc=$rc: $out"

# 3. a merged PR that worked it: in flight (verify on main)
cat > "$GH_PRS" <<'JSON'
[{"number":12,"state":"MERGED","title":"TD-050 slice 1","body":"","headRefName":"s1","url":"u12","mergeCommit":{"oid":"0000000000000000000000000000000000000001"}}]
JSON
out=$(run TD-050); rc=$?
[ $rc = 1 ] && grep -q "PR #12 merged" <<< "$out" && grep -q "verify on main" <<< "$out" && ok "3 a merged PR that worked it: in flight" || bad "3 rc=$rc: $out"

# 4. a branch on origin naming it, no PR: in flight
echo '[]' > "$GH_PRS"
git -C "$W" push -q origin main:td050-started 2>/dev/null
out=$(run TD-050); rc=$?
[ $rc = 1 ] && grep -qx "branch origin/td050-started" <<< "$out" && ok "4 a branch on origin naming it (no PR yet): in flight" || bad "4 rc=$rc: $out"
git -C "$W" push -q origin --delete td050-started 2>/dev/null

# 5. the Status is read after a fetch: origin moved since the clone
sed -i 's/Open — waiting for a hand/Built — PR #12/' "$W/docs/technical_debt.md"
git -C "$W" commit -qam "TD-050 built" && git -C "$W" push -q origin main 2>/dev/null
out=$(run TD-050); rc=$?
[ $rc = 0 ] && grep -q "Status on origin/main: Built — PR #12" <<< "$out" && ok "5 the Status is origin's after a fetch, not the clone's stale copy" || bad "5 rc=$rc: $out"

# 6. archived: in flight (resolved); in neither file: cannot tell
out=$(run TD-040); rc=$?
[ $rc = 1 ] && grep -q "TD-040 is archived on origin/main" <<< "$out" && ok "6a an archived entry: exit 1, said" || bad "6a rc=$rc: $out"
out=$(run TD-099); rc=$?
[ $rc = 2 ] && grep -q "in neither the ledger nor the archive" <<< "$out" && ok "6b an id in neither file: exit 2" || bad "6b rc=$rc: $out"
out=$(run banana); rc=$?
[ $rc = 2 ] && grep -q "is not a ledger id" <<< "$out" && ok "6c not an id: exit 2" || bad "6c rc=$rc: $out"

# 7. the forge unreadable: cannot tell (exit 2), never "nothing in flight"; a branch still says in flight
touch "$GH_FAIL"
out=$(run TD-050); rc=$?
[ $rc = 2 ] && grep -q "PRs: cannot see — gh: could not connect" <<< "$out" && ! grep -q "nothing in flight" <<< "$out" \
  && ok "7a the forge unreadable: exit 2, never none" || bad "7a rc=$rc: $out"
git -C "$W" push -q origin main:TD-050-other 2>/dev/null
out=$(run TD-050); rc=$?
[ $rc = 1 ] && grep -qx "branch origin/TD-050-other" <<< "$out" && ok "7b ... but a branch found still reads in flight" || bad "7b rc=$rc: $out"
rm -f "$GH_FAIL"
out=$(cd "$R" && CADENCE_FORGE=none python3 "$S/forge.py" in-flight TD-051 2>&1); rc=$?
[ $rc = 2 ] && grep -q "PRs: cannot see" <<< "$out" && ok "7c forge = none: PRs cannot be seen, exit 2" || bad "7c rc=$rc: $out"

# 7d. the fetch alone fails (origin/HEAD names a branch origin no longer has), ls-remote answers:
# the Status is as last fetched, so nothing is "none"
git -C "$R" update-ref refs/remotes/origin/gone refs/remotes/origin/main
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
echo '[]' > "$GH_PRS"
out=$(run TD-051); rc=$?
[ $rc = 2 ] && grep -q "Status on origin/gone (not fetched: as last fetched): Open" <<< "$out" && ! grep -q "nothing in flight" <<< "$out" \
  && ok "7d a failed fetch alone: exit 2, never none" || bad "7d rc=$rc: $out"
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# 7e. a full page of search results may have dropped the one: cannot see all
python3 -c 'import json; print(json.dumps([{"number": i, "state": "OPEN", "title": "unrelated", "body": "", "headRefName": "b", "url": "u", "mergeCommit": None} for i in range(100, 200)]))' > "$GH_PRS"
out=$(run TD-051); rc=$?
[ $rc = 2 ] && grep -q "cannot see all — the search filled its page of 100" <<< "$out" && ok "7e a full search page: exit 2" || bad "7e rc=$rc: $out"

# 7f. another repo's id (<repo>#TD-051) is not this entry; a crash is "cannot tell", never "in flight"
cat > "$GH_PRS" <<'JSON'
[{"number":21,"state":"OPEN","title":"see shiftlead#TD-051","body":"","headRefName":"z","url":"u21","mergeCommit":null}]
JSON
out=$(run TD-051); rc=$?
[ $rc = 0 ] && ! grep -q "PR #21" <<< "$out" && ok "7f a cross-repo id (<repo>#TD-NNN) does not name this entry" || bad "7f rc=$rc: $out"
echo '{"not": "a list"}' > "$GH_PRS"
out=$(run TD-051); rc=$?
[ $rc = 2 ] && grep -q "cannot tell — in-flight failed" <<< "$out" && ok "7g a crash exits 2 (cannot tell), not 1" || bad "7g rc=$rc: $out"

# 7h. a ledger in a newer format major is not read
echo '[]' > "$GH_PRS"
sed -i '1a Ledgerboard: 99' "$W/docs/technical_debt.md"
git -C "$W" commit -qam "a newer major" && git -C "$W" push -q origin main 2>/dev/null
out=$(run TD-051); rc=$?
[ $rc = 2 ] && grep -q "cannot read docs/technical_debt.md on origin/main — this file declares Ledgerboard: 99" <<< "$out" \
  && ok "7h a ledger in a newer format major: not read, exit 2" || bad "7h rc=$rc: $out"
git -C "$W" revert --no-edit HEAD >/dev/null && git -C "$W" push -q origin main 2>/dev/null && git -C "$R" fetch -q origin

# 7i. ls-remote alone fails (a git shim): the branches unseen, exit 2
REALGIT=$(command -v git); GB="$TMP/gitbin"; mkdir -p "$GB"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = ls-remote ] && { echo "ls-remote: refused" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REALGIT" > "$GB/git"
chmod +x "$GB/git"
echo '[]' > "$GH_PRS"
out=$(cd "$R" && PATH="$GB:$PATH" python3 "$S/forge.py" in-flight TD-051 2>&1); rc=$?
[ $rc = 2 ] && grep -q "branches: cannot see" <<< "$out" && ! grep -q "not fetched" <<< "$out" \
  && ok "7i ls-remote alone fails: exit 2, never none" || bad "7i rc=$rc: $out"

# 7j. origin's default branch has no ledger: exit 2
git -C "$W" checkout -q -b noledger && git -C "$W" rm -q docs/technical_debt.md && git -C "$W" commit -qm "no ledger" \
  && git -C "$W" push -q origin noledger 2>/dev/null && git -C "$W" checkout -q main
git -C "$R" fetch -q origin && git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/noledger
out=$(run TD-051); rc=$?
[ $rc = 2 ] && grep -q "no docs/technical_debt.md on origin/noledger" <<< "$out" && ok "7j no ledger on origin: exit 2" || bad "7j rc=$rc: $out"
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# 7k. a v2 ledger on origin (docs/ledger/, TD-160): the Status read from the entry's file, the
# filing PR found by the commit that added its file, an archived entry found in archive/
git -C "$W" checkout -q -b v2main main
(cd "$W" && python3 "$S/ledger.py" --split >/dev/null) && git -C "$W" add -A && git -C "$W" commit -qm split
printf '## TD-052: filed after the split\n\n**Priority:** low\n**Status:** Open — v2\n' > "$W/docs/ledger/TD-052.md"
git -C "$W" add -A && git -C "$W" commit -qm "file TD-052 (#10)"; FILER2=$(git -C "$W" rev-parse HEAD)
git -C "$W" mv docs/ledger/TD-051.md docs/ledger/archive/TD-051.md && git -C "$W" commit -qm "archive TD-051"
git -C "$W" push -q origin v2main 2>/dev/null && git -C "$W" checkout -q main
git -C "$R" fetch -q origin && git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/v2main
cat > "$GH_PRS" <<JSON
[{"number":10,"state":"MERGED","title":"file TD-052","body":"","headRefName":"f","url":"u10","mergeCommit":{"oid":"$FILER2"}},
 {"number":7,"state":"MERGED","title":"Harvest: TD-050 filed","body":"","headRefName":"harvest","url":"u7","mergeCommit":{"oid":"$FILER"}}]
JSON
out=$(run TD-050)
grep -q "PR #7 merged .*(filed the entry: not in flight)" <<< "$out" \
  && ok "7k' a v2 ledger: an entry filed before the split keeps its filing PR (the v1 file's history)" || bad "7k' $out"
out=$(run TD-052); rc=$?
[ $rc = 0 ] && grep -q "Status on origin/v2main: Open — v2" <<< "$out" && grep -q "PR #10 merged .*(filed the entry: not in flight)" <<< "$out" \
  && ok "7k a v2 ledger: the Status read, the filing PR known by the commit that added the entry's file" || bad "7k rc=$rc: $out"
echo '[]' > "$GH_PRS"
out=$(run TD-051); rc=$?
[ $rc = 1 ] && grep -q "TD-051 is archived on origin/v2main" <<< "$out" && ok "7l a v2 ledger: an entry moved into archive/ is archived" || bad "7l rc=$rc: $out"
git -C "$W" checkout -q v2main && printf '## TD-099: misfiled\n' > "$W/docs/ledger/TD-098.md"
git -C "$W" add -A && git -C "$W" commit -qm damaged && git -C "$W" push -q origin v2main 2>/dev/null && git -C "$W" checkout -q main
git -C "$R" fetch -q origin
out=$(run TD-052); rc=$?
[ $rc = 2 ] && grep -q "Status: cannot read docs/ledger on origin/v2main — .*TD-098.md" <<< "$out" \
  && ok "7m a v2 ledger v2_problems() faults: cannot read, exit 2" || bad "7m rc=$rc: $out"
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# 8. origin unreachable: no fetch, no branches — cannot tell
git -C "$R" remote set-url origin "$TMP/gone.git"
echo '[]' > "$GH_PRS"
out=$(run TD-051); rc=$?
[ $rc = 2 ] && grep -q "branches: cannot see" <<< "$out" && grep -q "(not fetched: as last fetched)" <<< "$out" \
  && ok "8 origin unreachable: the branches unseen and the Status marked stale, exit 2" || bad "8 rc=$rc: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
