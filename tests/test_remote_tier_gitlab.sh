#!/usr/bin/env bash
# TD-110: the /attention remote tier on a GitLab host remote_repos.txt names. `glab` is a PATH
# shim answering in the shapes gitlab.com gave glab 1.123.0 on 2026-10-14: `user`, a
# fine-grained token's 403 on `groups`, a group's and a user's projects, a raw file, and the
# three 404s (File / Commit / Project Not Found) told apart. `gh` is a shim too, so a test
# that should not touch GitHub can say it did not.
#
# Offline: HOME, XDG_CONFIG_HOME, DEV_CADENCE_REG_DIR and git config are temp;
# GIT_ALLOW_PROTOCOL=file stops a fetch of a fixture's https origin before it leaves.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_ALLOW_PROTOCOL=file
unset CADENCE_FORGE
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
FILTER="$DEV_CADENCE_REG_DIR/remote_repos.txt"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

FAKE="$TMP/fake"; BIN="$TMP/bin"; mkdir -p "$FAKE" "$BIN"
cat > "$BIN/glab" <<'SHIM'
#!/usr/bin/env python3
import os, re, sys
a = sys.argv[1:]
F = os.environ["FAKE_DIR"]
open(f"{F}/glab.log", "a").write(" ".join(a) + "\n")
def out(name):
    sys.stdout.write(open(f"{F}/{name}").read()); sys.exit(0)
def http404(what):
    sys.stdout.write('{"message":"404 %s Not Found"}' % what)
    print(f"glab: 404 {what} Not Found (HTTP 404)", file=sys.stderr); sys.exit(1)
if a[:1] != ["api"]:
    print(f"glab-shim: unhandled: {a}", file=sys.stderr); sys.exit(64)
ep = [x for x in a[1:] if not x.startswith("--") and x != a[a.index("--hostname") + 1]][0]
path = ep.split("?")[0]
if path == "user":
    if os.path.exists(f"{F}/fail_user"):
        sys.stdout.write('{"message":"401 Unauthorized"}')
        print("glab: 401 Unauthorized (HTTP 401)", file=sys.stderr); sys.exit(1)
    out("user.json")
if path == "groups":
    if os.path.exists(f"{F}/groups.json"):
        out("groups.json")
    sys.stdout.write('{"error":"insufficient_granular_scope","error_description":"Access denied: '
                     'This operation requires a fine-grained personal access token with the '
                     'following user permissions: [Group: Read]."}')
    print("glab: HTTP 403", file=sys.stderr); sys.exit(1)
m = re.fullmatch(r"(groups|users)/([^/]+)/projects", path)
if m:
    f = f"{'g' if m[1] == 'groups' else 'u'}proj_{m[2]}.json"
    if os.path.exists(f"{F}/{f}"):
        out(f)
    http404("Group" if m[1] == "groups" else "User")
m = re.fullmatch(r"projects/([^/]+)/repository/files/docs%2Fuser_attention\.md/raw", path)
if m:
    key = m[1].replace("%2F", "_")
    if os.path.exists(f"{F}/board_{key}.md"):
        out(f"board_{key}.md")
    if os.path.exists(f"{F}/noboard_{key}"):
        http404("File")
    if os.path.exists(f"{F}/empty_{key}"):
        http404("Commit")
    http404("Project")
print(f"glab-shim: unhandled api {ep}", file=sys.stderr); sys.exit(64)
SHIM
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.log"
if [ "$1 $2" = "api user" ]; then echo ghuser; exit 0; fi
if [ "$1 $2" = "api user/orgs" ]; then exit 0; fi
if [ "$1 $2" = "repo list" ]; then echo '[{"nameWithOwner":"ghuser/hub","isArchived":false}]'; exit 0; fi
if [ "$1" = "api" ] && [ "$2" = "repos/ghuser/hub/contents/docs/user_attention.md" ]; then
  printf '# b\n\n- [ ] 2026-10-01 (n/a) — from github.\n'; exit 0
fi
echo "gh: Not Found (HTTP 404)" >&2; exit 1
SHIM
chmod +x "$BIN/glab" "$BIN/gh"
export PATH="$BIN:$PATH" FAKE_DIR="$FAKE"

reset() {
  rm -rf "$FAKE"; mkdir -p "$FAKE"; : > "$FAKE/glab.log"; : > "$FAKE/gh.log"
  echo '{"id":1,"username":"gluser","name":"G"}' > "$FAKE/user.json"
}
proj() { printf '{"id":%d,"path_with_namespace":"%s","archived":%s,"default_branch":"main"}' "$RANDOM" "$1" "${2:-false}"; }
tier() {
  python3 - "$S" "$@" <<'PY'
import sys, datetime; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
from pathlib import Path
print("\n".join(N.remote_tier([Path(p) for p in sys.argv[2:]], datetime.date.today())))
PY
}

# 1. a group line: its projects, subgroups' included, probed on gitlab.com — and GitHub untouched
reset
printf 'gitlab.com/grp\n' > "$FILTER"
echo "[$(proj grp/a),$(proj grp/sub/b),$(proj grp/old true),$(proj grp/empty)]" > "$FAKE/gproj_grp.json"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — from gitlab.\n' > "$FAKE/board_grp_a.md"
touch "$FAKE/noboard_grp_sub_b" "$FAKE/empty_grp_empty"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — ghost.\n' > "$FAKE/board_grp_old.md"
out=$(tier)
grep -q "== gitlab.com/grp/a (remote-only, pushed state)" <<< "$out" && grep -q "from gitlab" <<< "$out" \
  && ok "1a a gitlab.com/<group> line lists a board from a project no clone covers" || bad "1a: $out"
grep -q "^-- Remote tier (gitlab.com, pushed state only) — 1 remote-only board(s) across 3 repo(s) probed --" <<< "$out" \
  && ok "1b header names the host and counts the probes" || bad "1b: $(head -1 <<< "$out")"
grep -q 'include_subgroups=true' "$FAKE/glab.log" && ok "1c the group's listing includes its subgroups" || bad "1c: $(cat "$FAKE/glab.log")"
! grep -q "grp%2Fold" "$FAKE/glab.log" && ! grep -q ghost <<< "$out" && ok "1d an archived project is never probed" || bad "1d"
! grep -q "⚠" <<< "$out" && ok "1e File Not Found and an empty project (Commit Not Found) are silent" || bad "1e: $(grep '⚠' <<< "$out")"
[ ! -s "$FAKE/gh.log" ] && ok "1f a filter naming only GitLab asks gh nothing" || bad "1f: $(cat "$FAKE/gh.log")"
grep -q -- '--hostname gitlab.com' "$FAKE/glab.log" && ok "1g every call names the host" || bad "1g"

# 2. a name that is no group is read as a user's namespace
reset
printf 'gitlab.com/someone\n' > "$FILTER"
echo "[$(proj someone/mine)]" > "$FAKE/uproj_someone.json"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — users.\n' > "$FAKE/board_someone_mine.md"
out=$(tier)
grep -q "== gitlab.com/someone/mine" <<< "$out" && grep -q "groups/someone/projects" "$FAKE/glab.log" \
  && ok "2 group 404 falls back to users/<u>/projects" || bad "2: $out"

# 3. a bare host: the user's projects, and a token that cannot read groups says so as a ⚠
reset
printf 'gitlab.com\n' > "$FILTER"
echo "[$(proj gluser/solo)]" > "$FAKE/uproj_gluser.json"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — solo.\n' > "$FAKE/board_gluser_solo.md"
out=$(tier)
grep -q "== gitlab.com/gluser/solo" <<< "$out" && ok "3a bare gitlab.com: whoami, then the user's projects" || bad "3a: $out"
grep -q "⚠ group discovery failed on gitlab.com (glab: HTTP 403 (Access denied: .*Group: Read.*)) — group repos not covered" <<< "$out" \
  && ok "3b a 403 on groups reads as a ⚠ with GitLab's own reason" || bad "3b: $(grep '⚠' <<< "$out")"
reset
printf 'gitlab.com\n' > "$FILTER"
echo '[{"id":7,"full_path":"top"},{"id":8,"full_path":"top/sub"},{"id":9,"full_path":"other"}]' > "$FAKE/groups.json"
echo '[]' > "$FAKE/uproj_gluser.json"; echo '[]' > "$FAKE/gproj_top.json"; echo '[]' > "$FAKE/gproj_other.json"
out=$(tier)
grep -q "groups/top/projects" "$FAKE/glab.log" && grep -q "groups/other/projects" "$FAKE/glab.log" && ! grep -q "groups/top%2Fsub/projects" "$FAKE/glab.log" \
  && ok "3c a subgroup whose parent is listed is not listed again" || bad "3c: $(cat "$FAKE/glab.log")"

# 4. unauthenticated, and glab missing: each a ⚠, never "no boards"
reset; touch "$FAKE/fail_user"
printf 'gitlab.com\n' > "$FILTER"
out=$(tier)
grep -q "⚠ remote tier unavailable on gitlab.com (glab: 401 Unauthorized (HTTP 401))" <<< "$out" && ok "4a unauthenticated: unavailable on gitlab.com" || bad "4a: $out"
reset
printf 'gitlab.com\ngitlab.com/grp\n' > "$FILTER"
NOGLAB="$TMP/noglab"; mkdir -p "$NOGLAB"; ln -sf "$(command -v python3)" "$NOGLAB/python3"; ln -sf "$(command -v git)" "$NOGLAB/git"
out=$(PATH="$NOGLAB" tier)
grep -q "⚠ remote tier unavailable on gitlab.com (glab not installed)" <<< "$out" \
  && grep -q "⚠ repo list failed for gitlab.com/grp (glab not installed) — that owner not covered" <<< "$out" \
  && ok "4b glab missing: said for discovery and for the group" || bad "4b: $out"

# 5. a project line that does not exist (or this token cannot see) is unprobeable, not silent
reset
printf 'gitlab.com/grp/gone\ngitlab.com/grp/here\n' > "$FILTER"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — here.\n' > "$FAKE/board_grp_here.md"
out=$(tier)
grep -q "⚠ 1 repo(s) unprobeable (first: gitlab.com/grp/gone: glab: 404 Project Not Found (HTTP 404))" <<< "$out" \
  && grep -q "== gitlab.com/grp/here" <<< "$out" && ! grep -q "groups/" "$FAKE/glab.log" \
  && ok "5 Project Not Found is unprobeable; a project line skips discovery" || bad "5: $out"

# 6. a local clone of the project wins: not probed
reset
L="$TMP/local"; git init -q -b main "$L"; git -C "$L" remote add origin git@gitlab.com:grp/a.git
printf 'gitlab.com/grp\n' > "$FILTER"
echo "[$(proj grp/a)]" > "$FAKE/gproj_grp.json"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — dup.\n' > "$FAKE/board_grp_a.md"
out=$(tier "$L")
! grep -q "repository/files" "$FAKE/glab.log" && ! grep -q dup <<< "$out" && ok "6 a project a local row covers is not probed" || bad "6: $out"

# 7. both forges: a bare github.com line keeps GitHub's discovery beside a GitLab group
reset
printf 'github.com\ngitlab.com/grp\n' > "$FILTER"
echo "[$(proj grp/a)]" > "$FAKE/gproj_grp.json"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — from gitlab.\n' > "$FAKE/board_grp_a.md"
out=$(tier)
grep -q "== ghuser/hub (remote-only" <<< "$out" && grep -q "== gitlab.com/grp/a (remote-only" <<< "$out" \
  && grep -q "^-- Remote tier (GitHub, gitlab.com, pushed state only) — 2 remote-only board(s)" <<< "$out" \
  && ok "7 github.com + gitlab.com/grp: both tiers, one header" || bad "7: $out"

# 8. end to end: /attention remote (the report) carries the GitLab board
reset
printf 'gitlab.com/grp\n' > "$FILTER"
echo "[$(proj grp/a)]" > "$FAKE/gproj_grp.json"
printf '# b\n\n- [ ] 2026-10-01 (n/a) — reported.\n' > "$FAKE/board_grp_a.md"
out=$(python3 "$S/nudge_user_attention.py" --report --remote 2>/dev/null)
grep -q "== gitlab.com/grp/a (remote-only, pushed state)" <<< "$out" && grep -q "reported" <<< "$out" \
  && ok "8 nudge_user_attention.py --report --remote lists it" || bad "8: $out"

echo; echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
