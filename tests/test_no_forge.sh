#!/usr/bin/env bash
# TD-105: `forge = "none"` — a repo with no PR API (a bare repo over ssh). The §4.9 review line
# goes in the squash commit's body; check_cadence.py --since reads it from git, passing a commit
# that carries it and failing one without it (or with BLOCK); --pr says there are no PRs; the
# nudge says "no forge" once; nothing reports "PRs not checked", and gh is never asked.
#
# Offline: the origin is a local bare repo; `gh` is a PATH shim that logs every call.
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
printf '#!/usr/bin/env bash\necho "$*" >> "$GH_LOG"\nexit 64\n' > "$BIN/gh"; chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log"; : > "$GH_LOG"

REVIEW='cadence-review: SHIP · sonnet · code · 0 findings'
# mkrepo DIR: a clone of a fresh bare origin, `forge = "none"` committed (with its review line)
mkrepo() {
    git init -q --bare -b main "$1.git"; git clone -q "$1.git" "$1" 2>/dev/null
    git -C "$1" commit -q --allow-empty -m base
    mkdir -p "$1/docs"; printf 'forge = "none"\n' > "$1/docs/cadence.toml"
    git -C "$1" add docs/cadence.toml; git -C "$1" commit -q -m "no forge" -m "$REVIEW"
}
# land DIR FILE BODY: one squash-shaped commit on main, pushed
land() { echo x > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -q -m "add $2" ${3:+-m "$3"}; git -C "$1" push -q origin main 2>/dev/null; }
cc() { (cd "$1" && shift && python3 "$S/check_cadence.py" "$@" 2>&1); }

# 1. a window with a reviewed commit, an unreviewed one and a BLOCK
R="$TMP/r"; mkrepo "$R"
land "$R" a "the change

$REVIEW"
land "$R" b
land "$R" c "cadence-review: BLOCK · sonnet · code · 1 findings"
land "$R" d "cadence-review: CLEAN · sonnet · code"
out=$(cc "$R" --since 1d --json); rc=$?
cls() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(*[c["class"]+":"+c["status"] for c in d["direct"]["commits"] if c["subject"]==sys.argv[1]])' "$1" <<< "$out"; }
[ "$rc" = 1 ] && ok "1a a window with an unreviewed commit fails (exit 1)" || bad "1a rc=$rc: $out"
[ "$(cls 'add a')" = "reviewed:pass" ] && ok "1b the body's cadence-review: line passes the commit" || bad "1b $(cls 'add a')"
[ "$(cls 'add b')" = "fail:fail" ] && ok "1c no review line: fail" || bad "1c $(cls 'add b')"
[ "$(cls 'add c')" = "fail:fail" ] && ok "1d a BLOCK line: fail" || bad "1d $(cls 'add c')"
[ "$(cls 'no forge')" = "reviewed:pass" ] && ok "1e the review line after another paragraph still counts" || bad "1e $(cls 'no forge')"
text=$(cc "$R" --since 1d)
grep -q "no cadence-review: line in its body" <<< "$text" && grep -q "says BLOCK" <<< "$text" \
  && ok "1f the text names what is missing" || bad "1f: $text"
[ "$(cls 'add d')" = "fail:fail" ] && grep -q "its cadence-review: line says CLEAN: the verdict is SHIP, FIXED or BLOCK" <<< "$text" \
  && ok "1h a CLEAN line: fail, naming the word (TD-116)" || bad "1h $(cls 'add d'): $text"
! grep -q "PRs not checked" <<< "$out$text" && ok "1g nothing reports \"PRs not checked\"" || bad "1g: $out$text"

# 2. every commit reviewed: a pass, exit 0
R2="$TMP/r2"; mkrepo "$R2"
land "$R2" a "$REVIEW"
out=$(cc "$R2" --since 1d); rc=$?
[ "$rc" = 0 ] && grep -q "PASS" <<< "$out" && ok "2 every commit carries its line: pass, exit 0" || bad "2 rc=$rc: $out"

# 3. --pr / --branch: no PRs here, exit 2, saying why
out=$(cc "$R" --pr 1); rc=$?
[ "$rc" = 2 ] && grep -q "no forge" <<< "$out" && grep -q -- "--since" <<< "$out" && ! grep -q "PRs not checked" <<< "$out" \
  && ok "3a --pr: exit 2, no forge, points at --since" || bad "3a rc=$rc: $out"
out=$(cc "$R" --branch x); rc=$?
[ "$rc" = 2 ] && grep -q "no forge" <<< "$out" && ok "3b --branch: exit 2, no forge" || bad "3b rc=$rc: $out"

# 4. the nudge: "no forge" once, not a warning; no settings line
nudge=$(python3 - "$S" "$R" <<'PY'
import sys, pathlib, time
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
root = pathlib.Path(sys.argv[2])
print(N.open_pr_lines(root, time.monotonic() + 30))
print(N.settings_line(root, {"t": 0.0, "hit": False}))
PY
)
grep -q "^\['no forge (forge = \"none\"" <<< "$nudge" && grep -q '^None$' <<< "$nudge" \
  && ok "4 the nudge: one 'no forge' line, no ⚠, no settings line" || bad "4: $nudge"

# 5. gh was never asked
[ ! -s "$GH_LOG" ] && ok "5 no gh call" || bad "5 gh was asked: $(cat "$GH_LOG")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
