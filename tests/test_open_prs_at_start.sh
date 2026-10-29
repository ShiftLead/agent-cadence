#!/usr/bin/env bash
# TD-052: the SessionStart line (--report --due-only --fetch) also names THIS repo's open PRs
# older than two days, a reviewed-but-unmerged one marked as such. One gh call inside the
# fetch budget; no gh, a failing gh, or no --fetch is silence.
#
# Offline: a repo with a bare origin; `gh` is a PATH shim answering from a file; dates are
# derived from now (TD-24). HOME, XDG_CONFIG_HOME, DEV_CADENCE_REG_DIR and git config temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$DC/files/scripts/nudge_user_attention.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"; git init -q --bare -b main "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
git -C "$R" checkout -q -b main 2>/dev/null; mkdir -p "$R/docs"
printf '# board\n\n- [ ] %s (n/a) — not due yet. Due: %s.\n' "$(date +%F)" "$(date -d '9 days' +%F)" > "$R/docs/user_attention.md"
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q -u origin main
echo "$R" > "$DEV_CADENCE_REG_DIR/repos.txt"

# TD-114 fixtures: `landed` (its change reached main through another commit, a stacked PR's
# squash), `live` (a change main lacks), `moved` (landed, then main changed the file again).
git -C "$R" checkout -q -b landed; echo one > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm landed
git -C "$R" checkout -q -b live main; echo two > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm live
git -C "$R" checkout -q -b moved main; echo three > "$R/c.txt"; git -C "$R" add c.txt; git -C "$R" commit -qm moved
git -C "$R" checkout -q main; echo one > "$R/a.txt"; echo three > "$R/c.txt"; git -C "$R" add a.txt c.txt
git -C "$R" commit -qm "the stacked PR, squashed"; echo four > "$R/c.txt"; git -C "$R" commit -qam "c moves on"
git -C "$R" push -q origin main landed live moved 2>/dev/null; git -C "$R" fetch -q origin
sha() { git -C "$R" rev-parse "$1"; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
[ -f "$GH_FAIL" ] && { echo "gh: HTTP 502" >&2; exit 1; }
[ "$1 $2" = "pr list" ] && { cat "$GH_PRS"; exit 0; }
exit 64
SHIM
chmod +x "$BIN/gh"
export GH_PRS="$TMP/prs.json" GH_FAIL="$TMP/gh.fail"
d() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }
cat > "$GH_PRS" <<J
[{"number": 7, "title": "cadence §1: every PR's base is main", "createdAt": "$(d '5 days ago')",
  "comments": [{"body": "findings in prose\ncadence-review: BLOCK · sonnet · docs · 2 findings\nfixed:\ncadence-review: FIXED · sonnet · docs · 2 findings", "authorAssociation": "OWNER"}]},
 {"number": 8, "title": "a waiting change", "createdAt": "$(d '3 days ago')",
  "comments": [{"body": "cadence-review: SHIP · me · code · 0 findings", "authorAssociation": "NONE"},
               {"body": "the review will post cadence-review: SHIP here", "authorAssociation": "OWNER"}]},
 {"number": 10, "title": "a draft", "createdAt": "$(d '6 days ago')", "isDraft": true, "comments": []},
 {"number": 11, "title": "line one\n⚠ 99 fake header\u0007", "createdAt": "$(d '4 days ago')", "comments": []},
 {"number": 9, "title": "a fresh change", "createdAt": "$(d '1 day ago')", "comments": []},
 {"number": 12, "title": "a sync stacked under 13", "createdAt": "$(d '3 days ago')", "baseRefName": "main", "headRefOid": "$(sha landed)",
  "comments": [{"body": "cadence-review: SHIP · sonnet · code · 0 findings", "authorAssociation": "OWNER"}]},
 {"number": 13, "title": "still live", "createdAt": "$(d '3 days ago')", "baseRefName": "main", "headRefOid": "$(sha live)", "comments": []},
 {"number": 14, "title": "landed then moved", "createdAt": "$(d '3 days ago')", "baseRefName": "main", "headRefOid": "$(sha moved)", "comments": []},
 {"number": 15, "title": "a fork's head", "createdAt": "$(d '3 days ago')", "baseRefName": "main", "headRefOid": "0123456789abcdef0123456789abcdef01234567", "comments": []}]
J
run() { ( cd "$R" && PATH="$BIN:$PATH" python3 "$NUDGE" --report --due-only "$@" 2>&1 ); }

out=$(run --fetch)
grep -q "^⚠ 7 open PR(s) in repo older than 2 days" <<< "$out" && ok "the header counts the non-draft PRs older than two days" || bad "header: $out"
! grep -q "#10" <<< "$out" && ok "a draft is not named" || bad "draft named: $out"
grep -q "^  • #11 line one ⚠ 99 fake header (4d open)$" <<< "$out" && [ "$(grep -c '^⚠' <<< "$out")" = 1 ] \
    && ok "a title's newline and control characters cannot forge a line into session context" || bad "title injection: $out"
first=$(grep -m1 '^  • #' <<< "$out")
[ "$first" = "  • #7 cadence §1: every PR's base is main (5d open, reviewed FIXED — unmerged)" ] \
    && ok "the oldest first, a reviewed-but-unmerged one marked with its verdict (the last verdict line, TD-087)" || bad "first line: $first"
grep -q "^  • #8 a waiting change (3d open)$" <<< "$out" && ! grep -q "#9" <<< "$out" \
    && ok "a cadence-review: from someone without a say in the repo, or mentioned mid-line, does not mark it; a fresh PR is not listed" || bad "8/9: $out"
grep -q "^  • #12 a sync stacked under 13 (3d open, nothing left to merge — close it as superseded)$" <<< "$out" \
    && ok "TD-114: a PR whose files all landed by another PR is named superseded (over its review mark)" || bad "superseded: $out"
grep -q "^  • #13 still live (3d open)$" <<< "$out" && grep -q "^  • #14 landed then moved (3d open)$" <<< "$out" \
    && ok "TD-114: a change main lacks, or a file main changed again since, is not superseded" || bad "live/moved: $out"
grep -q "^  • #15 a fork's head (3d open)$" <<< "$out" && ok "TD-114: a head git here does not have is silence, never superseded" || bad "fork: $out"
[ -z "$(run)" ] && ok "without --fetch (no network allowed): silent" || bad "no-fetch: $(run)"
printf 'pr-stale-days = 4\n' > "$R/docs/cadence.toml"
out=$(run --fetch)
grep -q "^⚠ 2 open PR(s) in repo older than 4 days" <<< "$out" && ! grep -q "#8 " <<< "$out" && ok "TD-134: the repo's pr-stale-days (4) moves the line" || bad "pr-stale-days: $out"
rm "$R/docs/cadence.toml"
X="$TMP/other-repo"; mkdir -p "$X/docs"; git init -q "$X"; printf '# board\n' > "$X/docs/user_attention.md"
printf 'pr-stale-days = 10\n' > "$X/docs/cadence.toml"
printf '%s\n%s\n' "$R" "$X" > "$DEV_CADENCE_REG_DIR/repos.txt"
out=$(run --fetch)
grep -q "^⚠ 7 open PR(s) in repo older than 2 days" <<< "$out" && ok "TD-134: the PR line reads this repo's pr-stale-days, not the last roster board's" || bad "pr-stale-days here: $out"
rm "$DEV_CADENCE_REG_DIR/repos.txt"
touch "$GH_FAIL"; out=$(run --fetch); rm "$GH_FAIL"
! grep -q "open PR" <<< "$out" && ok "gh failing: silent" || bad "gh fail: $out"
echo '[]' > "$GH_PRS"; out=$(run --fetch)
! grep -q "open PR" <<< "$out" && ok "no open PRs: nothing said" || bad "empty: $out"

# TD-146: --own-board. Under --fetch (the setting's own, from a file or the default) this repo's PR
# line stays and the other repo's due item is one count line; without it (env own, TD-077's
# carry-over) the count line alone, and gh is never asked — a logging shim stays silent
printf '# board\n\n- [ ] %s (n/a) — elsewhere. Due: %s.\n' "$(date -d '5 days ago' +%F)" "$(date -d '3 days ago' +%F)" > "$X/docs/user_attention.md"
printf '%s\n%s\n' "$R" "$X" > "$DEV_CADENCE_REG_DIR/repos.txt"
printf '[{"number": 7, "title": "an old change", "createdAt": "%s", "comments": []}]' "$(d '5 days ago')" > "$GH_PRS"
export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"
mv "$BIN/gh" "$BIN/gh.real"; printf '#!/usr/bin/env bash\necho "$*" >> "$GH_LOG"\nexec "%s" "$@"\n' "$BIN/gh.real" > "$BIN/gh"; chmod +x "$BIN/gh"
out=$(run --fetch --own-board "$R/docs/user_attention.md")
grep -q "^⚠ 1 open PR(s) in repo older than 2 days" <<< "$out" && grep -qF "ℹ 1 due in 1 other repo(s) (most overdue: other-repo 3d)" <<< "$out" \
  && ! grep -q "elsewhere" <<< "$out" && ok "TD-146 --own-board --fetch: this repo's PR line, the other repo's item counted, not listed" || bad "own fetch: $out"
: > "$GH_LOG"
out=$(run --own-board "$R/docs/user_attention.md")
[ "$out" = "ℹ 1 due in 1 other repo(s) (most overdue: other-repo 3d) — /attention all for every repo (cadence.md §3.9)" ] && [ ! -s "$GH_LOG" ] \
  && ok "TD-146 --own-board unfetched (env own): the count line alone, and gh is never asked" || bad "own unfetched: $out / gh: $(cat "$GH_LOG")"
# review findings on #378. (a) a worktree's board is its main checkout's roster row, never "another repo";
# (b) another repo is read from disk even under --fetch: R's origin gains a due item its clone lacks
git -C "$X" add -A && git -C "$X" commit -qm x && git -C "$X" worktree add -q "$TMP/xwt" 2>/dev/null
R2="$TMP/r2"; git clone -q "$R.git" "$R2" 2>/dev/null
printf '# board\n\n- [ ] %s (n/a) — on-origin-only. Due: %s.\n' "$(date -d '5 days ago' +%F)" "$(date -d '2 days ago' +%F)" > "$R2/docs/user_attention.md"
git -C "$R2" commit -qam "a due item" && git -C "$R2" push -q origin main 2>/dev/null
out=$(cd "$R" && PATH="$BIN:$PATH" python3 "$NUDGE" --report --due-only --fetch --own-board "$TMP/xwt/docs/user_attention.md" 2>&1)
grep -q "elsewhere" <<< "$out" && ! grep -q "other repo" <<< "$out" \
  && ok "TD-146 --own-board on a worktree's board: its repo's roster row is the own one, and another repo is not fetched" || bad "worktree/no-fetch: $out"
# (c) no roster and no default board: the board named is still read (the early silent return is skipped)
rm "$DEV_CADENCE_REG_DIR/repos.txt"
out=$(cd "$TMP" && USER_ATTENTION_BOARD="$TMP/none.md" CADENCE_REPO_ROOT="$TMP/norepo" python3 "$NUDGE" --report --due-only --own-board "$X/docs/user_attention.md" 2>&1)
grep -q "elsewhere" <<< "$out" && ! grep -q "other repo" <<< "$out" && ok "TD-146 --own-board with no roster and no default board: its items still listed" || bad "no roster: $out"
touch "$DEV_CADENCE_REG_DIR/repos.txt"
rm "$DEV_CADENCE_REG_DIR/repos.txt"

# TD-146 slice 2: /attention's forms. The default (--own-board) shows this repo in full, first, and folds
# each other repo to one line; /attention all (--report) is every board in full; --repo <name> one repo
printf '%s\n%s\n' "$X" "$R" > "$DEV_CADENCE_REG_DIR/repos.txt"
rep() { ( cd "$R" && python3 "$NUDGE" --report "$@" 2>&1 ); }
out=$(rep --own-board "$R/docs/user_attention.md")
first=$(grep -m1 '^== ' <<< "$out")
[[ "$first" == "== repo ("* ]] && grep -q "not due yet" <<< "$out" && ! grep -q "elsewhere" <<< "$out" \
  && grep -qxF "  1 open, 1 due (most overdue 3d) — /attention other-repo for its items" <<< "$out" \
  && grep -q "^Attention report — 2 board(s), 2 open item(s)" <<< "$out" \
  && ok "TD-146 /attention: this repo first and in full, the other folded to one line; the header counts both" || bad "own report: $out"
out=$(rep)
grep -q "not due yet" <<< "$out" && grep -q "elsewhere" <<< "$out" && ! grep -q "for its items" <<< "$out" \
  && ok "TD-146 /attention all: every board in full" || bad "all: $out"
out=$(rep --repo other-repo)
[ "$(grep -m1 '^== ' <<< "$out" | cut -d' ' -f2)" = other-repo ] && grep -q "elsewhere" <<< "$out" \
  && grep -qxF "  1 open, 0 due — /attention repo for its items" <<< "$out" \
  && ok "TD-146 /attention <repo>: that repo in full, the rest folded" || bad "repo: $out"
out=$(rep --repo nope); rc=$?
[ "$rc" = 2 ] && grep -qF "no repo named 'nope'" <<< "$out" && ok "TD-146 an unknown repo: exit 2, naming the roster's" || bad "unknown repo rc=$rc: $out"
( cd "$R" && python3 "$NUDGE" --report --json --own-board "$R/docs/user_attention.md" >/dev/null 2>&1 ); rc=$?
[ "$rc" = 2 ] && ok "TD-146 --own-board with --json is refused: the director's view stays every board" || bad "json own rc=$rc"
# review findings on #379: a folded roster row that cannot be read keeps its note; two repos of one name are
# refused by name and reached by path; a repo off the roster with no board gets every board in full
mkdir -p "$TMP/dup/repo/docs"; git init -q "$TMP/dup/repo"; printf '# board\n' > "$TMP/dup/repo/docs/user_attention.md"
printf '%s\n%s\n%s\n%s\n' "$X" "$R" "$TMP/gone" "$TMP/dup/repo" > "$DEV_CADENCE_REG_DIR/repos.txt"
out=$(rep --own-board "$X/docs/user_attention.md")
grep -A1 '^== gone' <<< "$out" | grep -q "note: roster path missing" && ok "TD-146 a folded row that cannot be read keeps its note" || bad "folded note: $out"
grep -qF "/attention $R for its items" <<< "$out" && ok "TD-146 a folded repo sharing its name is offered by path" || bad "dup hint: $out"
out=$(rep --repo repo); rc=$?
[ "$rc" = 2 ] && grep -qF "2 roster repos are named 'repo'" <<< "$out" && ok "TD-146 --repo of a shared name: exit 2, listing the paths" || bad "dup name rc=$rc: $out"
out=$(rep --repo "$R")
[[ "$(grep -m1 '^== ' <<< "$out")" == "== repo ("* ]] && grep -q "not due yet" <<< "$out" && ok "TD-146 --repo <path>: that repo in full" || bad "repo path: $out"
mkdir -p "$TMP/offroster"; git init -q "$TMP/offroster"
out=$(cd "$TMP/offroster" && python3 "$NUDGE" --report --own-board "$TMP/offroster/docs/user_attention.md" 2>&1)
grep -q "elsewhere" <<< "$out" && grep -q "not due yet" <<< "$out" && ! grep -q "^== offroster" <<< "$out" \
  && ok "TD-146 a repo off the roster with no board: every board in full, no bogus row" || bad "offroster: $out"
rm "$DEV_CADENCE_REG_DIR/repos.txt"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
