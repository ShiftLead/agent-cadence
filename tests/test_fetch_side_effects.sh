#!/usr/bin/env bash
# TD-044: the SessionStart --fetch is a READER — it must not leave locks, prune refs, or
# starve the repo the session runs in. Offline: bare origins under a temp dir, and a
# PATH-shim `git` whose `fetch` hangs while holding a lock file it removes only on SIGTERM
# (git's own lockfile handlers do the same; SIGKILL runs no handler). HOME and
# XDG_CONFIG_HOME are temp dirs, so the real roster is never read.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NUDGE="$DC/files/scripts/nudge_user_attention.py"
CHANGES="$DC/files/scripts/cadence_changes.py"
TMP=$(mktemp -d)

# No real `gh` from this suite (TD-052): --due-only --fetch asks gh for this repo's open PRs,
# and a run from inside a real clone would ask GitHub. A stub that always fails = offline.
mkdir -p "$TMP/nogh"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nogh/gh"; chmod +x "$TMP/nogh/gh"
export PATH="$TMP/nogh:$PATH"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$XDG_CONFIG_HOME/dev-cadence"
REG="$XDG_CONFIG_HOME/dev-cadence/repos.txt"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)

mkrepo() {  # mkrepo <dir>: a clone of a bare origin, with a board
    git init -q --bare -b main "$1.git"; git clone -q "$1.git" "$1" 2>/dev/null
    git -C "$1" checkout -q -b main 2>/dev/null; mkdir -p "$1/docs"
    printf '# board\n\n- [ ] %s (n/a) — item. Due: %s.\n' "$TODAY" "$TODAY" > "$1/docs/user_attention.md"
    git -C "$1" add -A; git -C "$1" commit -qm base; git -C "$1" push -q origin main
    git -C "$1" remote set-head origin -a >/dev/null 2>&1
}
advance() {  # advance <dir> [branch]: origin gains a commit this clone has not fetched
    local w="$TMP/w$RANDOM"; git clone -q "$1.git" "$w" 2>/dev/null
    git -C "$w" commit -q --allow-empty -m moved; git -C "$w" push -q origin "HEAD:${2:-main}"
    git -C "$1.git" rev-parse "refs/heads/${2:-main}"
}

# The shim: `git … fetch …` in a repo marked HANG takes a lock, then sleeps; SIGTERM
# removes the lock and exits. Everything else is the real git.
REAL=$(command -v git); BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/git" <<SHIM
#!/usr/bin/env bash
dir=.; prev=""; isfetch=0
for a in "\$@"; do [ "\$prev" = -C ] && dir="\$a"; [ "\$a" = fetch ] && isfetch=1; prev="\$a"; done
if [ \$isfetch = 1 ] && [ -e "\$dir/HANG" ]; then
    lock="\$dir/.git/shim-fetch.lock"; : > "\$lock"
    trap 'rm -f "\$lock"; exit 143' TERM
    sleep 30 & wait \$!
    exit 0
fi
exec "$REAL" "\$@"
SHIM
chmod +x "$BIN/git"

A="$TMP/a"; B="$TMP/b"; mkrepo "$A"; mkrepo "$B"; touch "$A/HANG"
printf '%s\n%s\n' "$A" "$B" > "$REG"          # the hanging repo is FIRST on the roster
want=$(advance "$B")

# --- 1) budget runs out on the hanging repo: exit 0, on time, no lock left, one stderr line
t0=$(date +%s.%N)
out=$(cd "$B" && PATH="$BIN:$PATH" ATTENTION_DUE_FETCH_BUDGET=3 python3 "$NUDGE" --report --due-only --fetch 2>"$TMP/err"); rc=$?
took=$(echo "$(date +%s.%N) - $t0" | bc)
[ $rc -eq 0 ] && ok "--due-only --fetch exits 0 with a hanging remote" || bad "rc=$rc: $out"
awk -v t="$took" 'BEGIN{exit !(t < 4.5)}' && ok "stays inside the budget, SIGTERM grace included (${took}s for a 3s budget)" || bad "took ${took}s for a 3s budget"
[ ! -e "$A/.git/shim-fetch.lock" ] && ok "no .lock survives the stopped fetch (SIGTERM before SIGKILL)" || bad "a .lock survived: $A/.git/shim-fetch.lock"
grep -q "fetch budget (3s) ran out — 1 repo(s) read from their last fetch: a" "$TMP/err" \
    && ok "the budget running out is said once on stderr, naming the repo" || bad "stderr: $(cat "$TMP/err")"

# --- 2) the session's own repo is fetched first, though it is second on the roster
[ "$(git -C "$B" rev-parse refs/remotes/origin/main)" = "$want" ] \
    && ok "the current repo was fetched first (its origin/main advanced despite the starved repo ahead of it)" \
    || bad "current repo not fetched: $(git -C "$B" rev-parse refs/remotes/origin/main) != $want"

# --- 3) a reader: default branch only, never --prune
rm "$A/HANG"
git -C "$B" update-ref refs/remotes/origin/gone "$(git -C "$B" rev-parse HEAD)"   # a ref origin no longer has
advance "$B" feature >/dev/null                                                  # a branch origin gained
want=$(advance "$B")
(cd "$B" && python3 "$NUDGE" --report --due-only --fetch >/dev/null 2>&1)
[ "$(git -C "$B" rev-parse refs/remotes/origin/main)" = "$want" ] && ok "the default branch is fetched" || bad "origin/main not fetched"
git -C "$B" rev-parse -q --verify refs/remotes/origin/gone >/dev/null && ok "no --prune: a remote-tracking ref origin dropped survives" || bad "origin/gone was pruned"
! git -C "$B" rev-parse -q --verify refs/remotes/origin/feature >/dev/null && ok "only the default branch: origin/feature was not fetched" || bad "origin/feature was fetched"

# --- 4) the changes hook fetches only when nothing did: a repo off the roster, FETCH_HEAD stale
C="$TMP/c"; mkrepo "$C"; mkdir -p "$C/scripts"; : > "$REG"
rm -f "$C/.git/FETCH_HEAD"; want=$(advance "$C")
(cd "$C" && python3 "$CHANGES" --hook >/dev/null 2>&1)
[ "$(git -C "$C" rev-parse refs/remotes/origin/main)" = "$want" ] && ok "changes hook: no recent FETCH_HEAD -> one fetch of its own" || bad "changes hook did not fetch"
before=$(git -C "$C" rev-parse refs/remotes/origin/main); advance "$C" >/dev/null
(cd "$C" && python3 "$CHANGES" --hook >/dev/null 2>&1)
[ "$(git -C "$C" rev-parse refs/remotes/origin/main)" = "$before" ] && ok "changes hook: a fresh FETCH_HEAD -> no second fetch" || bad "changes hook fetched again"
touch -d '1 hour ago' "$C/.git/FETCH_HEAD"; touch "$C/HANG"
t0=$(date +%s); (cd "$C" && PATH="$BIN:$PATH" python3 "$CHANGES" --hook >/dev/null 2>&1); rc=$?; took=$(( $(date +%s) - t0 ))
[ $rc -eq 0 ] && [ $took -le 8 ] && [ ! -e "$C/.git/shim-fetch.lock" ] \
    && ok "changes hook: a hanging fallback fetch is stopped in time and leaves no .lock (${took}s)" || bad "changes hang rc=$rc took=${took}s lock=$(ls "$C/.git/shim-fetch.lock" 2>&1)"

# --- 5) from a linked worktree (the cadence's own workflow): the fallback fetch lands in
#        the COMMON FETCH_HEAD, so the next start sees it fresh and does not fetch again
rm -f "$C/HANG" "$C/.git/FETCH_HEAD"; git -C "$C" worktree add -q "$TMP/c-wt" -b wt-topic origin/main
want=$(advance "$C")
(cd "$TMP/c-wt" && python3 "$CHANGES" --hook >/dev/null 2>&1)
[ "$(git -C "$C" rev-parse refs/remotes/origin/main)" = "$want" ] && [ -e "$C/.git/FETCH_HEAD" ] \
    && ok "changes hook from a worktree: fetched, and FETCH_HEAD is the common one" || bad "worktree fallback: no common FETCH_HEAD"
before=$(git -C "$C" rev-parse refs/remotes/origin/main); advance "$C" >/dev/null
(cd "$TMP/c-wt" && python3 "$CHANGES" --hook >/dev/null 2>&1)
[ "$(git -C "$C" rev-parse refs/remotes/origin/main)" = "$before" ] && ok "changes hook from a worktree: the next start does not refetch" || bad "worktree fallback refetched every start"

# --- 6) a narrowed remote.origin.fetch: the explicit refspec still moves origin/<default>
git -C "$B" config remote.origin.fetch "+refs/heads/nothing:refs/remotes/origin/nothing"
want=$(advance "$B"); printf '%s\n' "$B" > "$REG"
(cd "$B" && python3 "$NUDGE" --report --due-only --fetch >/dev/null 2>&1)
[ "$(git -C "$B" rev-parse refs/remotes/origin/main)" = "$want" ] && ok "narrowed fetch refspec: origin/main still updated (no stale compare)" || bad "narrowed refspec left origin/main stale"
git -C "$C" config remote.origin.fetch "+refs/heads/nothing:refs/remotes/origin/nothing"; rm -f "$C/.git/FETCH_HEAD"
want=$(advance "$C"); (cd "$C" && python3 "$CHANGES" --hook >/dev/null 2>&1)
[ "$(git -C "$C" rev-parse refs/remotes/origin/main)" = "$want" ] && ok "narrowed fetch refspec: the changes hook's fetch updates origin/main too" || bad "changes hook narrowed refspec stale"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
