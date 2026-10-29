#!/usr/bin/env bash
# TD-098: off GitHub the PR detectors say they cannot see, never go quiet. origin_forge()
# classifies origin once (github / other / none); with "other", the SessionStart open-PR line,
# check_cadence.py and the settings row (test_settings_drift.sh) each say "PRs not checked",
# and no gh call is made. A transient gh failure on a GitHub origin stays silent; a local-path
# origin (every fixture's) behaves as before.
#
# Offline: origins are only ever *named* — nothing is fetched; `gh` is a PATH shim that logs.
# HOME, XDG_CONFIG_HOME, AGENT_CADENCE_REG_DIR and git config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ -f "$GH_FAIL" ] && { echo "gh: HTTP 502" >&2; exit 1; }
[ "$1 $2" = "pr list" ] && { echo '[]'; exit 0; }
exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" GH_FAIL="$TMP/gh.fail"
R="$TMP/repo"; git init -q -b main "$R"; git -C "$R" commit -q --allow-empty -m base
seturl() { git -C "$R" remote remove origin 2>/dev/null; [ -n "$1" ] && git -C "$R" remote add origin "$1"; : > "$GH_LOG"; }
py() { python3 - "$S" "$R" "$@" <<'PY'
import sys, pathlib, time
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
root, what = pathlib.Path(sys.argv[2]), sys.argv[3]
if what == "forge":
    print(*N.origin_forge(root))
else:
    print("\n".join(N.open_pr_lines(root, time.monotonic() + 30)) or "NONE")
PY
}

# --- the classifier
while IFS='|' read -r url want; do
    seturl "$url"; got=$(py forge)
    [ "$got" = "$want" ] && ok "origin_forge: '${url:-<no origin>}' → $want" || bad "origin_forge '$url': got '$got', want '$want'"
done <<'T'
git@github.com:Tester/Thing.git|github tester/thing
https://github.com/tester/thing|github tester/thing
https://tok@github.com/tester/thing.git/|github tester/thing
git@gitlab.com:group/sub/thing.git|gitlab gitlab.com/group/sub/thing
https://gitlab.example/tester/thing.git|gitlab gitlab.example/tester/thing
ssh://git@gitea.local:2222/tester/thing.git|other gitea.local
https://github.example.corp/tester/thing|other github.example.corp
ssh://gitlab.com/group/thing|gitlab gitlab.com/group/thing
deploy@git.corp:team/thing.git|other git.corp
git://gitea.local/tester/thing|other gitea.local
HTTPS://GitLab.Example/tester/thing|gitlab gitlab.example/tester/thing
HTTPS://GitHub.com/Tester/Thing.git|github tester/thing
/srv/git/thing.git|none None
file:///srv/git/thing.git|none None
tester/thing|none None
|none None
T

# --- the SessionStart open-PR line
seturl https://gitea.example/tester/thing.git
out=$(py prs)
[ "$out" = "⚠ PRs not checked: origin is gitea.example, which the cadence cannot read yet (TD-097)" ] && [ ! -s "$GH_LOG" ] \
    && ok "open_pr_lines, Gitea origin: one 'not checked' line, no gh call" || bad "open_pr_lines gitea: '$out' / $(cat "$GH_LOG")"
seturl git@github.com:tester/thing.git; touch "$GH_FAIL"
[ "$(py prs)" = NONE ] && grep -q '^pr list' "$GH_LOG" && ok "open_pr_lines, GitHub origin, gh failing: still silence (the network, not the forge)" || bad "gh fail: $(py prs)"
rm -f "$GH_FAIL"
seturl "$TMP/bare.git"
[ "$(py prs)" = NONE ] && grep -q '^pr list' "$GH_LOG" && ok "open_pr_lines, local-path origin: asks gh as before" || bad "local path: $(py prs) / $(cat "$GH_LOG")"

# --- check_cadence.py
seturl git@gitea.example:group/thing.git
err=$(cd "$R" && python3 "$S/check_cadence.py" --pr 1 2>&1 >/dev/null); rc=$?
[ $rc = 2 ] && [ "$err" = "CANNOT CHECK: PRs not checked: origin is gitea.example, which the cadence cannot read yet (TD-097)" ] && [ ! -s "$GH_LOG" ] \
    && ok "check_cadence.py, Gitea origin: exit 2 naming the forge, not 'gh is not installed', no gh call" || bad "check_cadence gitlab: rc=$rc '$err' / $(cat "$GH_LOG")"
# …and with no gh on PATH at all (a PATH of python3 and git alone — a real gh may sit in
# /usr/bin, and this suite must never reach it), the forge is still the reason given
NOGH="$TMP/nogh"; mkdir -p "$NOGH"; ln -s "$(command -v python3)" "$NOGH/python3"; ln -s "$(command -v git)" "$NOGH/git"
err=$(cd "$R" && PATH="$NOGH" python3 "$S/check_cadence.py" --pr 1 2>&1 >/dev/null); rc=$?
[ $rc = 2 ] && echo "$err" | grep -q "origin is gitea.example" && ok "check_cadence.py, Gitea origin and no gh: the forge is named" || bad "no gh: rc=$rc '$err'"
seturl git@github.com:tester/thing.git
err=$(cd "$R" && PATH="$NOGH" python3 "$S/check_cadence.py" --pr 1 2>&1 >/dev/null); rc=$?
[ $rc = 2 ] && [ "$err" = "CANNOT CHECK: gh is not installed" ] && ok "check_cadence.py, GitHub origin and no gh: 'gh is not installed', as before" || bad "github no gh: rc=$rc '$err'"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
