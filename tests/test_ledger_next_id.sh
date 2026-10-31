#!/usr/bin/env bash
# TD-124: ledger_next_id.py hands out ledger ids from a counter branch on origin
# (cadence/ledger-ids, its tip's LAST the last id given). Offline: origin is a local bare repo per
# case; HOME/XDG_CONFIG_HOME are temp dirs, and `gh` is a PATH shim, so nothing real is touched.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXT="$DC/files/scripts/ledger_next_id.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR" "$TMP/bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_CODE_REMOTE CADENCE_FORGE CLAUDE_CODE_SESSION_ID
export PATH="$TMP/bin:$PATH" LEDGER_IDS_RACE_SECONDS=20
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)
# a container's marker files would leave host out of every take; the host cases say so
CONTAINER=0; { [ -e /.dockerenv ] || [ -e /run/.containerenv ]; } && CONTAINER=1

# origin (bare) seeded with a ledger whose ids are unpadded TD-1..TD-28 plus TD-124, and an archive
# holding TD-110 as a heading and TD-118 only as a table row; then a clone of it at $2.
mkrepo() {  # $1 origin dir, $2 clone dir
  rm -rf "$1" "$2" "$TMP/seed"; git init -q --bare -b main "$1"
  git init -q -b main "$TMP/seed"; mkdir -p "$TMP/seed/docs"
  { echo "# ledger"; echo; echo "| ID | Title | Priority | Status |"; echo "|---|---|---|---|"
    for i in $(seq 1 28); do echo "| TD-$i | t | Low | open |"; done
    for i in $(seq 1 28); do printf '\n## TD-%s: t\n\n**Added:** %s\n' "$i" "$TODAY"; done
    printf '\n## TD-124: t\n\n**Added:** %s\n' "$TODAY"; } > "$TMP/seed/docs/technical_debt.md"
  printf '# archive\n\n| TD-118 | t | Low | done |\n\n## TD-110: t\n\n**Resolved:** %s\n' "$TODAY" \
    > "$TMP/seed/docs/technical_debt_archive.md"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed
  git -C "$TMP/seed" push -q "$1" main; rm -rf "$TMP/seed"
  git clone -q "$1" "$2"; git -C "$2" config user.email t@t
}
last()    { git -C "$1" show refs/heads/cadence/ledger-ids:LAST 2>/dev/null; }   # $1 origin
subject() { git -C "$1" log -1 --format=%s refs/heads/cadence/ledger-ids; }
body()    { git -C "$1" log -1 --format=%b refs/heads/cadence/ledger-ids; }
take()    { (cd "$1" && shift && python3 "$NEXT" "$@" 2>"$TMP/err"); }

O="$TMP/o"; W="$TMP/w"; mkrepo "$O" "$W"

# 1. the first take: no counter yet — one above the ledger's highest (unpadded ids read as numbers)
out=$(take "$W"); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-125 ] && [ "$(last "$O")" = 125 ] \
  && [ "$(subject "$O")" = "TD-125 [skip ci]" ] \
  && [ "$(git -C "$O" rev-list --count refs/heads/cadence/ledger-ids)" = 1 ] \
  && [ "$(git -C "$O" log -1 --format='%an <%ae>|%cn' refs/heads/cadence/ledger-ids)" = "cadence <cadence@noreply>|cadence" ] \
  && ok "1 first take: TD-125 reserved, a root commit by the fixed identity, LAST 125" \
  || bad "1 rc=$rc out='$out' last=$(last "$O") $(cat "$TMP/err")"
b=$(body "$O")
h=$(printf %s t@t | sha256sum | cut -c1-12)
grep -qx "by: $h" <<< "$b" && ! grep -q "t@t" <<< "$b" && grep -qx "branch: main" <<< "$b" \
  && { [ "$CONTAINER" = 1 ] || grep -qx "host: $(python3 -c 'import socket; print(socket.gethostname())')" <<< "$b"; } \
  && ok "1b the body names by (user.email's hash, never the address: TD-195), branch and host" || bad "1b body='$b'"
git -C "$W" show-ref --verify -q refs/heads/cadence/ledger-ids \
  && bad "1c a local branch was made" || ok "1c no local branch: the counter is only origin's (and its tracking ref)"

# 2. a later take follows LAST; --count 2 is a range, LAST its end; --by names the taker
out=$(take "$W" --count 2 --by grinder-x); rc=$?
[ "$rc" = 0 ] && [ "$out" = $'TD-126\nTD-127' ] && [ "$(last "$O")" = 127 ] \
  && [ "$(subject "$O")" = "TD-126..TD-127 [skip ci]" ] && grep -qx "by: grinder-x" <<< "$(body "$O")" \
  && [ "$(git -C "$O" rev-list --count refs/heads/cadence/ledger-ids)" = 2 ] \
  && ok "2 --count 2: TD-126..TD-127, a child of the last take" || bad "2 rc=$rc out='$out' $(cat "$TMP/err")"

# 3. --floor: a front end's own last-given id lifts the counter past it
out=$(take "$W" --floor 500); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-501 ] && [ "$(last "$O")" = 501 ] \
  && ok "3 --floor 500: TD-501, and LAST follows" || bad "3 rc=$rc out='$out'"

# 4. LAST wins over the ledger, but a LAST that is not a number is ignored with a warning
mkrepo "$O" "$W"
blob=$(printf 'abc\n' | git -C "$O" hash-object -w --stdin)
tree=$(printf '100644 blob %s\tLAST\n' "$blob" | git -C "$O" mktree)
git -C "$O" update-ref refs/heads/cadence/ledger-ids "$(git -C "$O" commit-tree "$tree" -m bad)"
out=$(take "$W" --json); rc=$?
chk=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["ids"] == ["TD-125"] and d["reserved"] is True and d["why"] == "", d
assert any("not a number" in w for w in d["warnings"]), d
print("ok")' "$out" 2>&1)
[ "$rc" = 0 ] && [ "$chk" = ok ] && [ "$(last "$O")" = 125 ] \
  && ok "4 a non-numeric LAST: ignored with a warning, the ledger decides, LAST rewritten" || bad "4 rc=$rc $chk"
tree=$(printf '' | git -C "$O" mktree)
git -C "$O" update-ref refs/heads/cadence/ledger-ids \
  "$(git -C "$O" commit-tree "$tree" -p refs/heads/cadence/ledger-ids -m empty)"
out=$(take "$W" --json); rc=$?
[ "$rc" = 0 ] && grep -q '"TD-125"' <<< "$out" && grep -q "absent" <<< "$out" \
  && ok "4b a counter tip with no LAST: a warning, the ledger decides" || bad "4b rc=$rc $out"

# 5. host: left out when the repo says off, and in a cloud session
mkrepo "$O" "$W"
printf 'ledger-ids-host = "off"\n' > "$W/docs/cadence.toml"
take "$W" >/dev/null; grep -q "^host:" <<< "$(body "$O")" && bad "5 host written with ledger-ids-host = off" \
  || ok "5 ledger-ids-host = off: no host line"
rm -f "$W/docs/cadence.toml"
CLAUDE_CODE_REMOTE=true take "$W" >/dev/null; grep -q "^host:" <<< "$(body "$O")" \
  && bad "5b host written in a cloud session" || ok "5b CLAUDE_CODE_REMOTE: no host line"
git -C "$W" checkout -q --detach; take "$W" >/dev/null
grep -q "^branch:" <<< "$(body "$O")" && bad "5c branch written while detached" || ok "5c detached: no branch line"

# 6. two takers in the same instant: each clone's pre-push hook waits at a barrier, so both read the
# same tip and push together; the server refuses one, which re-probes, sees the tip moved and retries
mkrepo "$O" "$W"; rm -rf "$TMP/w2" "$TMP/bar"; git clone -q "$O" "$TMP/w2"; mkdir -p "$TMP/bar"
take "$W" >/dev/null   # the counter exists (LAST 125), so the race is on a child commit
for c in "$W" "$TMP/w2"; do
  cat > "$c/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
[ -e "$TMP/bar/done-\$\$-\$(basename "$c")" ] && exit 0
[ -e "$TMP/bar/once-$(basename "$c")" ] && exit 0
touch "$TMP/bar/once-$(basename "$c")" "$TMP/bar/at-$(basename "$c")"
for _ in \$(seq 1 100); do [ "\$(ls "$TMP/bar" | grep -c '^at-')" -ge 2 ] && exit 0; sleep 0.05; done
exit 0
EOF
  chmod +x "$c/.git/hooks/pre-push"
done
(cd "$W" && python3 "$NEXT" > "$TMP/r1" 2>"$TMP/e1"; echo $? > "$TMP/c1") &
(cd "$TMP/w2" && python3 "$NEXT" > "$TMP/r2" 2>"$TMP/e2"; echo $? > "$TMP/c2") &
wait
ids=$(sort "$TMP/r1" "$TMP/r2" | tr '\n' ' ')
[ "$(cat "$TMP/c1")" = 0 ] && [ "$(cat "$TMP/c2")" = 0 ] && [ "$ids" = "TD-126 TD-127 " ] \
  && [ "$(last "$O")" = 127 ] && [ "$(git -C "$O" rev-list --count refs/heads/cadence/ledger-ids)" = 3 ] \
  && ok "6 two takers at once: different ids, both reserved, the loser retried (LAST 127, 3 takes)" \
  || bad "6 rc=$(cat "$TMP/c1")/$(cat "$TMP/c2") ids='$ids' last=$(last "$O") $(cat "$TMP/e1" "$TMP/e2")"
# the same race on the first take: two root commits, one branch
mkrepo "$O" "$W"; rm -rf "$TMP/w2" "$TMP/bar"; git clone -q "$O" "$TMP/w2"; mkdir -p "$TMP/bar"
for c in "$W" "$TMP/w2"; do
  cat > "$c/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
[ -e "$TMP/bar/once-$(basename "$c")" ] && exit 0
touch "$TMP/bar/once-$(basename "$c")" "$TMP/bar/at-$(basename "$c")"
for _ in \$(seq 1 100); do [ "\$(ls "$TMP/bar" | grep -c '^at-')" -ge 2 ] && exit 0; sleep 0.05; done
exit 0
EOF
  chmod +x "$c/.git/hooks/pre-push"
done
(cd "$W" && python3 "$NEXT" > "$TMP/r1" 2>"$TMP/e1"; echo $? > "$TMP/c1") &
(cd "$TMP/w2" && python3 "$NEXT" > "$TMP/r2" 2>"$TMP/e2"; echo $? > "$TMP/c2") &
wait
ids=$(sort "$TMP/r1" "$TMP/r2" | tr '\n' ' ')
[ "$(cat "$TMP/c1")" = 0 ] && [ "$(cat "$TMP/c2")" = 0 ] && [ "$ids" = "TD-125 TD-126 " ] && [ "$(last "$O")" = 126 ] \
  && ok "6b two first takes at once: one root commit wins, the other retries onto it" \
  || bad "6b rc=$(cat "$TMP/c1")/$(cat "$TMP/c2") ids='$ids' $(cat "$TMP/e1" "$TMP/e2")"

# 7. a refusal with the tip unmoved (a pre-receive that declines): the fallback — printed, exit 3
mkrepo "$O" "$W"
printf '#!/bin/sh\necho "branch protected" >&2\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
out=$(take "$W" --json); rc=$?
chk=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["ids"] == ["TD-125"] and d["reserved"] is False, d
assert "unmoved" in d["why"] and "cadence/ledger-ids" in d["why"], d
print("ok")' "$out" 2>&1)
[ "$rc" = 3 ] && [ "$chk" = ok ] && [ -z "$(last "$O")" ] \
  && ok "7 a declined push, tip unmoved: exit 3, the id printed but not reserved, why names the push" \
  || bad "7 rc=$rc $chk"
out=$(take "$W"); rc=$?
[ "$rc" = 3 ] && [ "$out" = TD-125 ] && grep -q "NOT reserved" "$TMP/err" \
  && ok "7b without --json: the id on stdout, NOT reserved on stderr" || bad "7b rc=$rc '$out' $(cat "$TMP/err")"
rm -f "$O/hooks/pre-receive"

# 8. origin unreachable: main cannot be the floor, so refused — exit 2, nothing on stdout
git -C "$W" remote set-url origin "$TMP/nowhere"
out=$(take "$W"); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "refused" "$TMP/err" \
  && ok "8 origin unreachable: exit 2, nothing printed" || bad "8 rc=$rc '$out'"
git -C "$W" remote set-url origin "$O"

# 9. the first take reads the open PRs (a gh shim): an id typed by hand into PR #7 counts; PR #8,
# whose head origin does not serve, is named unread and the take still reserves
mkrepo "$O" "$W"
git clone -q "$O" "$TMP/pr"; printf '\n## TD-300: by hand\n' >> "$TMP/pr/docs/technical_debt.md"
git -C "$TMP/pr" commit -qam pr7; git -C "$TMP/pr" push -q "$O" HEAD:refs/pull/7/head; rm -rf "$TMP/pr"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  "pr list"*) echo '[{"number":7,"title":"a"},{"number":8,"title":"b"}]' ;;
  *) echo "gh shim: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
out=$(CADENCE_FORGE=github take "$W" --json); rc=$?
chk=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["ids"] == ["TD-301"] and d["reserved"] is True, d
assert d["unread"] == ["#8"], d
print("ok")' "$out" 2>&1)
[ "$rc" = 0 ] && [ "$chk" = ok ] && [ -z "$(git -C "$W" for-each-ref refs/cadence/pr)" ] \
  && ok "9 first take reads open PRs: #7's TD-300 counts (TD-301), #8 named unread, private refs gone" \
  || bad "9 rc=$rc $chk"
out=$(CADENCE_FORGE=github take "$W"); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-302 ] && ! grep -q "not read" "$TMP/err" \
  && ok "9b a later take does not read the PRs (LAST decides)" || bad "9b rc=$rc '$out' $(cat "$TMP/err")"
git -C "$W" fetch -q origin main
mkrepo "$O" "$W"
out=$(take "$W" --json); rc=$?
[ "$rc" = 0 ] && grep -q "open PRs not read: origin names no forge" <<< "$out" \
  && ok "9c no forge (a local origin): the PR read is skipped, and says so" || bad "9c rc=$rc $out"

# 11. byte-identical takes: the same tip, the same second (dates pinned), the same by/branch/host.
# B reads the tip, then a git wrapper on its PATH holds its push until A's identical take has landed,
# so B's push starts against a tip already at its own sha — "[up to date]", exit 0. That must not
# read as reserved: B retries and gets TD-126.
mkrepo "$O" "$W"; rm -rf "$TMP/w2" "$TMP/bar" "$TMP/slow"; git clone -q "$O" "$TMP/w2"; git -C "$TMP/w2" config user.email t@t
mkdir -p "$TMP/bar" "$TMP/slow"
cat > "$TMP/slow/git" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" push "* ]] && [ ! -e "$TMP/bar/once" ]; then
  touch "$TMP/bar/once" "$TMP/bar/at-b"
  for _ in \$(seq 1 200); do $(command -v git) -C "$O" rev-parse -q --verify refs/heads/cadence/ledger-ids >/dev/null && break; sleep 0.05; done
fi
exec $(command -v git) "\$@"
EOF
chmod +x "$TMP/slow/git"
export GIT_AUTHOR_DATE="@1700000000 +0000" GIT_COMMITTER_DATE="@1700000000 +0000"
(cd "$TMP/w2" && PATH="$TMP/slow:$PATH" python3 "$NEXT" --by same > "$TMP/r2" 2>"$TMP/e2"; echo $? > "$TMP/c2") &
for _ in $(seq 1 200); do [ -e "$TMP/bar/at-b" ] && break; sleep 0.05; done
(cd "$W" && python3 "$NEXT" --by same > "$TMP/r1" 2>"$TMP/e1"; echo $? > "$TMP/c1")
wait
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
[ "$(cat "$TMP/r1")" = TD-125 ] && [ "$(cat "$TMP/r2")" = TD-126 ] && [ "$(cat "$TMP/c2")" = 0 ] && [ "$(last "$O")" = 126 ] \
  && ok "11 one tip, one second, one by/branch/host: never one id twice (B retried to TD-126)" \
  || bad "11 A='$(cat "$TMP/r1")' B='$(cat "$TMP/r2")' rc=$(cat "$TMP/c1")/$(cat "$TMP/c2") last=$(last "$O") $(cat "$TMP/e2")"

# 12. a tip that moves on every attempt: refused after LEDGER_IDS_RACE_SECONDS — exit 2, no ids
mkrepo "$O" "$W"; take "$W" >/dev/null
cat > "$W/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
t=\$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)
git -C "$O" update-ref refs/heads/cadence/ledger-ids "\$(git -C "$O" commit-tree "\$t^{tree}" -p "\$t" -m other)"
EOF
chmod +x "$W/.git/hooks/pre-push"
out=$(LEDGER_IDS_RACE_SECONDS=1 take "$W"); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "kept moving" "$TMP/err" \
  && ok "12 a counter that never holds still: exit 2 after the race window, nothing printed" || bad "12 rc=$rc '$out' $(cat "$TMP/err")"
rm -f "$W/.git/hooks/pre-push"

# 13. a later take refused with the tip unmoved: the fallback, the counter untouched
printf '#!/bin/sh\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
before=$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)
out=$(take "$W"); rc=$?
[ "$rc" = 3 ] && [ -n "$out" ] && [ "$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)" = "$before" ] \
  && grep -q "unmoved" "$TMP/err" && ok "13 a later take declined, tip unmoved: exit 3, unreserved, counter untouched" \
  || bad "13 rc=$rc '$out' $(cat "$TMP/err")"
rm -f "$O/hooks/pre-receive"

# 14. --prs reads the open PRs on a later take; read_prs(base=True) gives head − base per PR, so an
# archive move is not new
mkrepo "$O" "$W"; take "$W" >/dev/null   # LAST 125
git clone -q "$O" "$TMP/pr"
python3 - "$TMP/pr/docs" <<'PY'
import re, sys
d = sys.argv[1]
led = open(f"{d}/technical_debt.md").read()
body = re.search(r"\n## TD-124: t\n\n\*\*Added:\*\* \S+\n", led).group(0)
open(f"{d}/technical_debt.md", "w").write(led.replace(body, "\n") + "\n## TD-400: by hand\n")
open(f"{d}/technical_debt_archive.md", "a").write(body)
PY
git -C "$TMP/pr" commit -qam "pr9: TD-400 new, TD-124 archived"; git -C "$TMP/pr" push -q "$O" HEAD:refs/pull/9/head; rm -rf "$TMP/pr"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  "pr list"*) echo '[{"number":9,"title":"a"}]' ;;
  *) exit 1 ;;
esac
GH
out=$(CADENCE_FORGE=github take "$W"); out2=$(CADENCE_FORGE=github take "$W" --prs)
[ "$out" = TD-126 ] && [ "$out2" = TD-401 ] && ok "14 a later take skips the PRs; --prs reads them (#9's TD-400 → TD-401)" || bad "14 '$out' '$out2'"
chk=$(cd "$W" && CADENCE_FORGE=github PYTHONPATH="$DC/files/scripts" python3 -c '
from pathlib import Path
import ledger_next_id as X
prs, unread = X.read_prs(Path("."), "docs/technical_debt.md", "docs/technical_debt_archive.md", base=True)
r = prs[9]
assert unread == [], unread
assert 400 in r["head"] and 124 in r["head"] and r["base"] is not None, r
assert r["head"] - r["base"] == {400}, r["head"] - r["base"]
print("ok")' 2>&1)
[ "$chk" = ok ] && ok "14b read_prs(base=True): head − base is the PR's new ids only (an archive move is not new)" || bad "14b $chk"

# 15. nothing that lists branches reports the counter (cadence.md §2.10): the stranded-work sweep's
# own branch command, read from the procedure, and the reaper, in a clone that holds its tracking ref
mkrepo "$O" "$W"; take "$W" >/dev/null
cmd=$(grep -o '`git branch -a[^`]*`' "$DC/files/docs/procedures/stranded-work.md" | head -1 | tr -d '`')
git -C "$W" rev-parse -q --verify refs/remotes/origin/cadence/ledger-ids >/dev/null \
  && listed=$(cd "$W" && bash -c "$cmd") && grep -q "origin/main" <<< "$listed" && ! grep -q "ledger-ids" <<< "$listed" \
  && ok "15 the stranded-work sweep's branch list ($cmd) leaves the counter out" || bad "15 cmd='$cmd' listed='$listed'"
reaped=$(cd "$W" && bash "$DC/files/scripts/reap_worktrees.sh" 2>&1)
! grep -q "ledger-ids" <<< "$reaped" && ok "15b reap_worktrees.sh never reports the counter (it reads local heads only)" || bad "15b $reaped"

# 10. arguments
mkrepo "$O" "$W"
take "$W" --count 11 >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ -z "$(last "$O")" ] && ok "10 --count 11: refused, nothing taken" || bad "10 rc=$rc"
out=$(cd "$TMP" && python3 "$NEXT" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "not inside a git work tree" <<< "$out" && ok "10b outside a work tree: exit 2" || bad "10b rc=$rc $out"

# 16. TD-145: read_takes() maps each id to its take; --claim takes exactly one id while it is free
mkrepo "$O" "$W"
take "$W" --by a >/dev/null 2>&1; take "$W" --count 2 --by b >/dev/null 2>&1    # TD-125 by a; TD-126..127 by b
chk=$(cd "$W" && python3 - "$DC/files/scripts" <<'PY2' 2>&1
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import ledger_next_id as X
t = X.read_takes(Path("."), "refs/remotes/origin/cadence/ledger-ids")
assert sorted(t) == [125, 126, 127], t
assert t[125]["by"] == "a" and t[126]["by"] == t[127]["by"] == "b" and t[126]["sha"] == t[127]["sha"], t
assert t[125]["branch"] == "main" and t[125]["take"] and t[125]["date"], t
assert X.read_takes(Path("."), "refs/remotes/origin/no-such") is None
print("ok")
PY2
)
[ "$chk" = ok ] && ok "16 read_takes: each id to its take (a range is one take), by and branch read; an unreadable log is None" || bad "16 $chk"
out=$(take "$W" --claim TD-130 --by c); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-130 ] && [ "$(subject "$O")" = "TD-130 [skip ci]" ] && [ "$(last "$O")" = 130 ] \
  && grep -qx "by: c" <<< "$(body "$O")" \
  && ok "16b --claim TD-130 above LAST: taken as a one-id take, LAST 130" || bad "16b rc=$rc out='$out' $(cat "$TMP/err")"
out=$(take "$W" --claim 128); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-128 ] && [ "$(last "$O")" = 130 ] \
  && ok "16c --claim below LAST of an id never given: taken, LAST stays 130" || bad "16c rc=$rc out='$out' last=$(last "$O")"
out=$(take "$W"); [ "$out" = TD-131 ] && ok "16d the next take goes above both" || bad "16d out='$out'"
before=$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)
out=$(take "$W" --claim TD-126 --json); rc=$?
[ "$rc" = 2 ] && grep -q '"why": "TD-126 was already handed to b"' <<< "$out" && grep -q '"ids": \[\]' <<< "$out" \
  && [ "$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)" = "$before" ] \
  && ok "16e --claim of an id a take gave: refused (exit 2) naming its taker, the counter untouched" || bad "16e rc=$rc $out"
take "$W" --claim TD-028 >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q "TD-028 is already on origin/main" "$TMP/err" \
  && ok "16f --claim of an id main holds: refused" || bad "16f rc=$rc $(cat "$TMP/err")"
for bad_args in "--claim x" "--claim TD-0" "--claim TD-140 --count 2" "--claim TD-140 --floor 9"; do
  # shellcheck disable=SC2086
  take "$W" $bad_args >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] || bad "16g $bad_args: rc=$rc"
done
[ "$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)" = "$before" ] && ok "16g a malformed --claim, or one with --count/--floor, is a usage error" || bad "16g moved"
# the fallback (counter unreachable) under --claim prints that id, unreserved
git -C "$W" remote set-url origin "$TMP/nowhere"
out=$(take "$W" --claim TD-140); rc=$?
git -C "$W" remote set-url origin "$O"
[ "$rc" = 2 ] && [ -z "$out" ] && ok "16h --claim with origin unreachable: refused like any take (main is not the floor)" || bad "16h rc=$rc out='$out'"
printf '#!/bin/sh\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
out=$(take "$W" --claim TD-140); rc=$?
rm -f "$O/hooks/pre-receive"
[ "$rc" = 3 ] && [ "$out" = TD-140 ] && grep -q "NOT reserved" "$TMP/err" && [ "$(git -C "$O" rev-parse refs/heads/cadence/ledger-ids)" = "$before" ] \
  && ok "16i --claim declined with the tip unmoved: the fallback prints that same id, unreserved" || bad "16i rc=$rc out='$out' $(cat "$TMP/err")"

# 17. TD-145 slice 2: a reserved take prints the Taken by line to write; --branch names the branch it is for
mkrepo "$O" "$W"
out=$(take "$W" --by grinder-y --branch td125-x); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-125 ] && grep -qx "branch: td125-x" <<< "$(body "$O")" \
  && grep -qF 'write `**Taken by:** grinder-y` in each entry'"'"'s header' "$TMP/err" \
  && ok "17 --branch is recorded in place of the current branch; stderr names the Taken by line" || bad "17 rc=$rc out='$out' $(body "$O") $(cat "$TMP/err")"
out=$(take "$W" --by grinder-y --json); rc=$?
[ "$rc" = 0 ] && grep -q '"taken_by": "grinder-y"' <<< "$out" && grep -qx "branch: main" <<< "$(body "$O")" \
  && ok "17b --json carries taken_by; with no --branch the current branch is recorded" || bad "17b rc=$rc $out"
printf '#!/bin/sh\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
out=$(take "$W" --json); rc=$?
rm -f "$O/hooks/pre-receive"
[ "$rc" = 3 ] && grep -q '"taken_by": null' <<< "$out" && ok "17c the fallback reserves nothing, so it names no taker" || bad "17c rc=$rc $out"

# 18. TD-145 slice 3: ledger.py --check --since judges the ids the edit adds against the counter, as the row does
LEDGER="$DC/files/scripts/ledger.py"
mkrepo "$O" "$W"
take "$W" --by a >/dev/null 2>&1                                              # TD-125 by a
entry() { printf '\n## TD-%s: t\n\n**Priority:** Low\n**Status:** Open\n%s\n**Why:** x.\n' "$1" "${2:+**Taken by:** $2}" \
            >> "$W/docs/technical_debt.md"; }
chk()   { (cd "$W" && python3 "$LEDGER" --check --since origin/main "$@"); }
reset() { git -C "$W" checkout -q -- docs; }
git -C "$W" checkout -q -b td125-x
entry 125 a; out=$(chk); rc=$?; reset
[ "$rc" = 0 ] && ! grep -q "TD-125" <<< "$out" && ok "18 an id its Taken by's take gave passes, silent" || bad "18 rc=$rc $out"
entry 125 b; out=$(chk); rc=$?; reset
[ "$rc" = 1 ] && grep -q "⚠ TD-125 was handed to a, not b" <<< "$out" \
  && ok "18b Taken by another than the take's by: an error naming the by (#2370)" || bad "18b rc=$rc $out"
entry 140 a; out=$(chk); rc=$?; reset
[ "$rc" = 1 ] && grep -q "⚠ TD-140 handed out by nobody" <<< "$out" && ok "18c a hand-typed id no take gave: an error" || bad "18c rc=$rc $out"
entry 125; out=$(chk --json); rc=$?; reset
kinds=$(python3 -c 'import json,sys; print(",".join(f["kind"] for f in json.loads(sys.argv[1])["flags"] if f["kind"].startswith("id-")))' "$out")
[ "$rc" = 0 ] && [ "$kinds" = id-no-taken-by ] && grep -q 'Taken by:\*\* a' <<< "$out" \
  && ok "18d no Taken by: an ℹ line naming the take's by, keyed id-no-taken-by" || bad "18d rc=$rc kinds=$kinds $out"
entry 50 a; out=$(chk); rc=$?; reset
[ "$rc" = 0 ] && grep -q "ℹ TD-050 below the counter's first take (TD-125)" <<< "$out" \
  && ok "18e an id older than the counter: ℹ, not judged" || bad "18e rc=$rc $out"
git -C "$W" remote set-url origin "$TMP/nowhere"
entry 140 a; out=$(chk); rc=$?; reset
git -C "$W" remote set-url origin "$O"
[ "$rc" = 0 ] && grep -q "ℹ the ledger-id counter was not read" <<< "$out" \
  && ok "18f origin unreachable: ℹ, the edit not failed on what could not be read" || bad "18f rc=$rc $out"
git -C "$W" remote set-url origin "$TMP/nowhere"
out=$(chk); rc=$?
git -C "$W" remote set-url origin "$O"
[ "$rc" = 0 ] && ! grep -q "counter" <<< "$out" && ok "18g an edit adding no id asks origin nothing" || bad "18g rc=$rc $out"
base=$(git -C "$W" rev-parse origin/main); git -C "$W" remote remove origin
entry 140 a; out=$(cd "$W" && python3 "$LEDGER" --check --since "$base"); rc=$?; reset
git -C "$W" remote add origin "$O"
[ "$rc" = 0 ] && ! grep -q "TD-140\|counter" <<< "$out" && ok "18g2 no origin remote: no counter to ask, silent" || bad "18g2 rc=$rc $out"
mkrepo "$O" "$W"; git -C "$W" checkout -q -b td140
entry 140 a; out=$(chk); rc=$?; reset
[ "$rc" = 0 ] && ! grep -q "TD-140" <<< "$out" && ok "18h a repo with no counter: ids not judged" || bad "18h rc=$rc $out"

# 19. TD-145 (e): with no --by, a Claude Code session's take names the session, not the machine's shared git email;
#     TD-195: by its id's hash (first 12 hex of the sha256), so the public counter never carries the id
mkrepo "$O" "$W"
sid=0f1e2d3c-4b5a-4978-8695-a4b3c2d1e0f9; h=$(printf %s "$sid" | sha256sum | cut -c1-12)
out=$(CLAUDE_CODE_SESSION_ID=$sid take "$W" --json); rc=$?
[ "$rc" = 0 ] && grep -qx "by: $h" <<< "$(body "$O")" && grep -q "\"taken_by\": \"$h\"" <<< "$out" \
  && ! grep -q "$sid" <<< "$(body "$O") $out" \
  && ok "19 no --by in a Claude Code session: by is its session id's hash, never the id (TD-195)" || bad "19 rc=$rc $out $(body "$O")"
CLAUDE_CODE_SESSION_ID=$sid take "$W" --by grinder-z >/dev/null
grep -qx "by: grinder-z" <<< "$(body "$O")" && ok "19b --by still wins over the session id, verbatim" || bad "19b $(body "$O")"
CLAUDE_CODE_SESSION_ID=$sid take "$W" >/dev/null
grep -qF "write \`**Taken by:** $h\`" "$TMP/err" && ok "19c the Taken by line it prints is the hash" || bad "19c $(cat "$TMP/err")"

# 20. TD-195: a take whose by is a bare session id or an address warns (id-by-unhashed); a hash or a name does not
mkrepo "$O" "$W"
take "$W" --by "$sid" >/dev/null 2>&1                                          # TD-125 by a bare UUID
take "$W" --by t@t.example >/dev/null 2>&1                                      # TD-126 by an address
take "$W" --by "$h" >/dev/null 2>&1                                             # TD-127 by a hash
git -C "$W" checkout -q -b td125-x
entry 125 "$sid"; entry 126 t@t.example; entry 127 "$h"; out=$(chk --json); rc=$?; reset
kinds=$(python3 -c 'import json,sys; print(",".join(f["kind"] for f in json.loads(sys.argv[1])["flags"] if f["kind"].startswith("id-")))' "$out")
[ "$rc" = 0 ] && [ "$kinds" = id-by-unhashed ] && grep -q "TD-125, TD-126 taken by a bare session id" <<< "$out" \
  && ! grep -q "TD-127 taken by" <<< "$out" \
  && ok "20 a by that is a UUID or an address: an ℹ line keyed id-by-unhashed, naming those ids alone" || bad "20 rc=$rc kinds=$kinds $out"

# 21. TD-204: review-outcomes on asks the filing question, last on stderr, on every hand-out of ids
# (exit 0 and 3, --json too) and never on --claim or a refusal; stdout stays the ids
Q="ledger_next_id: if this entry is a defect, did a design miss it? then \`**Escaped from:** <design TD>\` (cadence §2.13)"
mkrepo "$O" "$W"
out=$(take "$W"); rc=$?
[ "$rc" = 0 ] && ! grep -qF "did a design miss it" "$TMP/err" && ok "21 review-outcomes unset (off): no question" || bad "21 rc=$rc $(cat "$TMP/err")"
mkdir -p "$W/docs"; printf 'review-outcomes = "on"\n' > "$W/docs/cadence.toml"
out=$(take "$W"); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-126 ] && [ "$(tail -n1 "$TMP/err")" = "$Q" ] && [ "$(grep -cF "did a design miss it" "$TMP/err")" = 1 ] \
  && ok "21b on: the id on stdout, the question once and last on stderr" || bad "21b rc=$rc '$out' $(cat "$TMP/err")"
out=$(take "$W" --json); rc=$?
[ "$rc" = 0 ] && python3 -c 'import json,sys; assert json.loads(sys.argv[1])["ids"] == ["TD-127"]' "$out" && [ "$(tail -n1 "$TMP/err")" = "$Q" ] \
  && ok "21c on, --json: stdout is the object alone, the question last on stderr" || bad "21c rc=$rc '$out' $(cat "$TMP/err")"
printf '#!/bin/sh\necho "branch protected" >&2\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
out=$(take "$W"); rc=$?
[ "$rc" = 3 ] && [ "$out" = TD-128 ] && [ "$(tail -n1 "$TMP/err")" = "$Q" ] && grep -q "NOT reserved" "$TMP/err" \
  && ok "21d on, exit 3 (printed, not reserved): the question still last" || bad "21d rc=$rc '$out' $(cat "$TMP/err")"
rm -f "$O/hooks/pre-receive"
out=$(take "$W" --claim TD-140); rc=$?
[ "$rc" = 0 ] && [ "$out" = TD-140 ] && ! grep -qF "did a design miss it" "$TMP/err" \
  && ok "21e on, --claim: no question (the id was already handed out)" || bad "21e rc=$rc '$out' $(cat "$TMP/err")"
git -C "$W" remote set-url origin "$TMP/nowhere"
out=$(take "$W"); rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] && ! grep -qF "did a design miss it" "$TMP/err" \
  && ok "21f on, refused (exit 2): no question" || bad "21f rc=$rc '$out' $(cat "$TMP/err")"
git -C "$W" remote set-url origin "$O"
printf 'review-outcomes = "maybe"\n' > "$W/docs/cadence.toml"
out=$(take "$W"); rc=$?
[ "$rc" = 0 ] && ! grep -qF "did a design miss it" "$TMP/err" && ok "21g a value that is not on or off: no question" || bad "21g rc=$rc $(cat "$TMP/err")"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
