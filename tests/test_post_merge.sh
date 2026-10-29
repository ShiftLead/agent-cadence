#!/usr/bin/env bash
# post-merge (TD-058): on a host without coreutils `timeout` the hook used to do nothing on
# every pull — `timeout 20 … 2>/dev/null` failed with "command not found", hidden. It must
# run the reaper unbounded there instead, and still exit 0.
#
# Offline: a fixture repo with the hook and a stub reaper; the no-`timeout` case runs under
# a minimal PATH of symlinked tools. (The 20 s kill line is not exercised: it needs a 20 s run.)
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"; git init -q -b main "$R"; mkdir -p "$R/scripts/git-hooks"
cp "$DC/files/scripts/git-hooks/post-merge" "$R/scripts/git-hooks/"
printf '#!/usr/bin/env bash\necho "reaper ran: $*"\n' > "$R/scripts/reap_worktrees.sh"
chmod +x "$R/scripts/git-hooks/post-merge" "$R/scripts/reap_worktrees.sh"

out=$(cd "$R" && scripts/git-hooks/post-merge 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "reaper ran: --quiet" <<< "$out" && ok "with timeout: the reaper runs, exit 0" || bad "with timeout (rc=$rc): $out"

MIN="$TMP/min"; mkdir -p "$MIN"
for t in bash env git dirname; do p=$(command -v "$t") && ln -sf "$p" "$MIN/$t"; done
[ ! -e "$MIN/timeout" ] || bad "fixture: timeout leaked into the minimal PATH"
out=$(cd "$R" && PATH="$MIN" scripts/git-hooks/post-merge 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "reaper ran: --quiet" <<< "$out" && ok "no timeout on the host: the reaper still runs (was: nothing, silently), exit 0" || bad "no timeout (rc=$rc): $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
