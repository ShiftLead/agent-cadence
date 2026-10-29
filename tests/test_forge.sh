#!/usr/bin/env bash
# TD-103: the forge adapter. scripts/forge.py is the one place a script runs the forge's CLI;
# the `forge` setting picks the backend (auto / github / gitlab / none); an unsupported forge
# reads "PRs not checked" from every caller, never an empty answer; a `host/owner/repo` line in
# remote_repos.txt / no_auto_delete.txt equals its `owner/repo` form on github.com; the squash's
# parent count comes from git when the clone holds the merge commit.
#
# Offline: origins are only named, never fetched; `gh` is a PATH shim that logs every call.
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
  "pr list") echo '[]'; exit 0 ;;
  "pr view") cat "$GH_PRVIEW"; exit 0 ;;
  "auth status") exit 0 ;;
esac
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log"
R="$TMP/repo"; git init -q -b main "$R"; git -C "$R" commit -q --allow-empty -m base
seturl() { git -C "$R" remote remove origin 2>/dev/null; [ -n "$1" ] && git -C "$R" remote add origin "$1"; : > "$GH_LOG"; }
classify() { (cd "$R" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import forge; print(*forge.origin_forge("."))' "$S"); }

# 1. the forge key decides, origin's host only under auto
seturl https://ghe.example.com/Org/Thing.git
[ "$(classify)" = "other ghe.example.com" ] && ok "1a auto: an unknown host is other, never GitHub" || bad "1a: $(classify)"
[ "$(CADENCE_FORGE=github classify)" = "github org/thing" ] && ok "1b forge=github: a GitHub under another host reads as GitHub" || bad "1b: $(CADENCE_FORGE=github classify)"
mkdir -p "$R/docs"; printf 'forge = "github"\n' > "$R/docs/cadence.toml"
[ "$(classify)" = "github org/thing" ] && ok "1c forge=github read from docs/cadence.toml" || bad "1c: $(classify)"
rm "$R/docs/cadence.toml"
seturl https://github.com/o/r.git
[ "$(CADENCE_FORGE=gitlab classify)" = "gitlab github.com/o/r" ] && ok "1d forge=gitlab: GitLab, whatever the host (TD-104)" || bad "1d: $(CADENCE_FORGE=gitlab classify)"
[ "$(CADENCE_FORGE=none classify)" = "other none" ] && ok "1e forge=none: other (TD-105)" || bad "1e: $(CADENCE_FORGE=none classify)"
[ "$(CADENCE_FORGE=bitbucket classify)" = "other !bitbucket" ] && ok "1f an unknown forge value is other, naming it" || bad "1f: $(CADENCE_FORGE=bitbucket classify)"
out=$(cd "$R" && CADENCE_FORGE=bitbucket python3 "$S/check_cadence.py" --pr 1 2>&1)
grep -q "the forge setting 'bitbucket' is not one of auto, github, gitlab, none" <<< "$out" && ! grep -q "origin is" <<< "$out" && ok "1h a bad setting is named as the setting, not blamed on origin" || bad "1h: $out"
[ "$(classify)" = "github o/r" ] && ok "1g auto on github.com: github, owner/repo" || bad "1g: $(classify)"

# 2. an unsupported forge says "PRs not checked" from every caller, and asks gh nothing
seturl https://gitea.example/o/r.git
out=$(cd "$R" && python3 "$S/check_cadence.py" --pr 1 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "CANNOT CHECK: PRs not checked: origin is gitea.example" <<< "$out" && ok "2a check_cadence.py: CANNOT CHECK, exit 2" || bad "2a rc=$rc: $out"
out=$(cd "$R" && python3 "$S/forge.py" check 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "PRs not checked" <<< "$out" && ok "2c forge.py check: the line, exit 2" || bad "2c rc=$rc: $out"
out=$(bash "$S/adopt_repo_settings.sh" --check gitea.example/o/r 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "cannot verify: PRs not checked: origin is gitea.example" <<< "$out" && ok "2d adopt_repo_settings.sh host/owner/repo off GitHub: cannot verify, exit 2" || bad "2d rc=$rc: $out"
nudge=$(python3 - "$S" "$R" <<'PY'
import sys, pathlib, time
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
root = pathlib.Path(sys.argv[2])
print(N.open_pr_lines(root, time.monotonic() + 30)[0])
print(N.settings_line(root, {"t": 0.0, "hit": False}))
PY
)
grep -q "^⚠ PRs not checked: origin is gitea.example" <<< "$nudge" && grep -q "^⚙ repo settings not checked: origin is gitea.example" <<< "$nudge" \
  && ok "2e the nudge's open-PR and settings lines: not checked" || bad "2e: $nudge"
[ ! -s "$GH_LOG" ] && ok "2f no gh call for an unsupported forge" || bad "2f gh was asked: $(cat "$GH_LOG")"
seturl https://github.com/o/r.git
out=$(cd "$R" && CADENCE_FORGE=none python3 "$S/check_cadence.py" --pr 1 2>&1)
grep -q 'forge = "none"' <<< "$out" && grep -q TD-105 <<< "$out" && ok "2g forge=none names itself and TD-105" || bad "2g: $out"

# 3. a host/owner/repo line equals its owner/repo form
py3() { python3 - "$S" "$@"; }
[ "$(py3 <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import forge as F
print(F.repo_key("github.com/O/R") == F.repo_key("o/r") == ("github.com", "o/r"), F.repo_key("gitlab.example.com/a/b"), F.repo_key("nope"))
PY
)" = "True ('gitlab.example.com', 'a/b') None" ] && ok "3a repo_key: github.com/O/R == o/r; another host kept; junk None" || bad "3a"
printf 'Alpha/One\ngithub.com/beta/two  # stacked\n' > "$DEV_CADENCE_REG_DIR/no_auto_delete.txt"
got=$(py3 <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print(sorted(N._no_auto_delete()))
PY
)
[ "$got" = "['alpha/one', 'beta/two']" ] && ok "3b no_auto_delete.txt: both forms name the same repo" || bad "3b: $got"
printf 'someowner\ngithub.com/c/d\ne/f\ngitlab.com/g/h\ngitlab.com/grp\ngitlab.com\nexample.org/x/y\n' > "$DEV_CADENCE_REG_DIR/remote_repos.txt"
got=$(py3 <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print(N._read_remote_filter())
PY
)
[ "$got" = "({'github.com': {'discover': False, 'owners': ['someowner'], 'repos': ['c/d', 'e/f']}, 'gitlab.com': {'discover': True, 'owners': ['grp'], 'repos': ['g/h']}}, ['example.org/x/y'])" ] && ok "3c remote_repos.txt: github.com/c/d reads as c/d; a GitLab host's group, project and bare host (TD-110); another host set aside" || bad "3c: $got"

# 4. the squash's parents from git when the clone holds the merge commit; the forge otherwise
git -C "$R" commit -q --allow-empty -m "squash (#1)"
SQ=$(git -C "$R" rev-parse HEAD)
got=$(py3 "$R" "$SQ" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import check_cadence as C
class Forge:
    def commit_parents(self, sha): return f"forge:{sha}"
C.FORGE = Forge(); C._FETCHED.add(sys.argv[2])
print(C.merge_parents(sys.argv[3], sys.argv[2]), C.merge_parents("abc1234", sys.argv[2]))
PY
)
[ "$got" = "1 forge:abc1234" ] && ok "4 merge_parents: git for a commit in the clone, the forge for one that is not" || bad "4: $got"

# 4b. a shallow clone's boundary commit lists no parents: never read as "0 parents, not a squash"
SH="$TMP/shallow"; git clone -q --depth 1 "file://$R" "$SH" 2>/dev/null
got=$(py3 "$SH" "$(git -C "$SH" rev-parse HEAD)" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import check_cadence as C
class Forge:
    def commit_parents(self, sha): return "forge"
C.FORGE = Forge(); C._FETCHED.add(sys.argv[2])
print(C.merge_parents(sys.argv[3], sys.argv[2]))
PY
)
[ "$got" = forge ] && ok "4b merge_parents: a shallow boundary (0 parents from git) asks the forge" || bad "4b: $got"

# 4c. a remote_repos.txt naming only other hosts is still a filter: no discovery of the user's GitHub
printf 'example.org/g/h\n' > "$DEV_CADENCE_REG_DIR/remote_repos.txt"; : > "$GH_LOG"
out=$(py3 <<'PY'
import sys, datetime; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print("\n".join(N.remote_tier([], datetime.date.today())))
PY
)
grep -q "not covered (first: example.org/g/h" <<< "$out" && ! grep -q "user" "$GH_LOG" && ok "4c only other-host lines: reported, and no user/org discovery" || bad "4c: $out / $(cat "$GH_LOG")"

# 5. Done when (TD-103): no script outside forge.py runs gh
hits=$(cd "$DC" && grep -nE '\["gh"|which\("gh"\)|^[^#]*\bgh (pr|api|auth|repo) |^[^#]*command -v gh' files/scripts/*.py files/scripts/*.sh | grep -v '^files/scripts/forge.py:')
[ -z "$hits" ] && ok "5 no gh call outside forge.py (files/scripts)" || bad "5 gh outside forge.py: $hits"

# 6. TD-114: `forge.py nothing-left N` — exit 0 when every file the PR changed is already the
# same on origin/<base> (landed by another PR), 1 when one differs, 2 when git here cannot tell
N="$TMP/nl"; git init -q --bare -b main "$N.git"; git clone -q "$N.git" "$N" 2>/dev/null
git -C "$N" commit -q --allow-empty -m base; git -C "$N" push -q -u origin main 2>/dev/null
git -C "$N" remote set-url origin https://github.com/o/r.git; git -C "$N" remote set-url --push origin "$N.git"
git -C "$N" checkout -q -b landed; echo x > "$N/f"; git -C "$N" add f; git -C "$N" commit -qm landed
git -C "$N" checkout -q -b live main; echo y > "$N/g"; git -C "$N" add g; git -C "$N" commit -qm live
git -C "$N" checkout -q main; echo x > "$N/f"; git -C "$N" add f; git -C "$N" commit -qm "stacked PR, squashed"
git -C "$N" push -q origin main 2>/dev/null; git -C "$N" update-ref refs/remotes/origin/main main
export GH_PRVIEW="$TMP/prview.json"
nl() { printf '{"number":%s,"state":"%s","baseRefName":"main","headRefOid":"%s"}' "$1" "${3:-OPEN}" "$2" > "$GH_PRVIEW"; (cd "$N" && python3 "$S/forge.py" nothing-left "$1" 2>&1); }
out=$(nl 3 "$(git -C "$N" rev-parse landed)"); rc=$?
[ $rc = 0 ] && [ "$out" = "#3 nothing left to merge — close it as superseded" ] && ok "6a landed by another PR: exit 0, superseded" || bad "6a rc=$rc: $out"
out=$(nl 4 "$(git -C "$N" rev-parse live)"); rc=$?
[ $rc = 1 ] && grep -q "#4 has changes left to merge" <<< "$out" && ok "6b a change main lacks: exit 1" || bad "6b rc=$rc: $out"
out=$(nl 3 "$(git -C "$N" rev-parse landed)" MERGED); rc=$?
[ $rc = 1 ] && [ "$out" = "#3 is merged, not open — nothing to close" ] && ok "6d a PR that is not open: exit 1, never superseded" || bad "6d rc=$rc: $out"
out=$(nl 5 0123456789abcdef0123456789abcdef01234567); rc=$?
[ $rc = 2 ] && grep -q "cannot tell" <<< "$out" && ok "6c a head not fetched here: exit 2, cannot tell" || bad "6c rc=$rc: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
