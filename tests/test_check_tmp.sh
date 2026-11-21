#!/usr/bin/env bash
# check_tmp.py (TD-154): one line at session start when the shared temp filesystem is past 80% of
# its inodes or space, and /attention's report naming the largest directories with the cleanups
# for the person. Offline: os.statvfs is stubbed in-process; the walk runs over a temp directory.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/check_tmp.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" USER=tester
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# run MODE FILES FFREE BLOCKS BFREE BAVAIL [budget]: check_tmp.py MODE with statvfs answering
# those figures (4096-byte blocks) for the temp directory, which is $T
T="$TMP/t"; mkdir -p "$T"
run() {
  CLAUDE_CODE_TMPDIR="$T" python3 - "$@" <<'PY'
import os, sys
sys.path.insert(0, os.path.dirname(os.environ["SCRIPT"]))
import check_tmp as c
mode, files, ffree, blocks, bfree, bavail = sys.argv[1], *map(int, sys.argv[2:7])
if len(sys.argv) > 7:
    c.WALK_BUDGET = float(sys.argv[7])
class S:
    f_files, f_ffree, f_blocks, f_bfree, f_bavail, f_frsize = files, ffree, blocks, bfree, bavail, 4096
os.statvfs = lambda p: S
sys.exit(c.main([mode]))
PY
}
export SCRIPT

# 1. under the threshold: --hook says nothing; --report says it is fine
out=$(run --hook 1000 900 1000 900 900); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "1 under 80%: --hook prints nothing" || bad "1 rc=$rc '$out'"
out=$(run --report 1000 900 1000000 900000 900000)
grep -q "^$T: 10% of its inodes (100 of 1,000) and 10% of its space (0.4 GB of 4.1 GB) — fine (warns at 80%)$" <<< "$out" \
  && [ "$(wc -l <<< "$out")" = 1 ] && ok "1b under 80%: --report is one line saying fine, no walk" || bad "1b '$out'"

# 2. inodes past 80% with space nearly free (the 2026-10-26 outage's shape): one warning line naming both
out=$(run --hook 1048576 104857 4000000 3000000 3000000); rc=$?
[ $rc -eq 0 ] && [ "$(wc -l <<< "$out")" = 1 ] \
  && grep -q "^⚠ $T is past 80% — 91% of its inodes (943,719 of 1,048,576) and 25% of its space (4.1 GB of 16.4 GB)\. Every session on this machine shares it; tell the person — \`/attention\` names what fills it (TD-154)$" <<< "$out" \
  && ok "2 inodes at 90.0%, rounded up as df does, space at 25%: one ⚠ line naming both figures" || bad "2 rc=$rc '$out'"

# 3. space past 80% alone warns too
out=$(run --hook 1000 900 1000 150 150)
grep -q "^⚠ $T is past 80% — 10% of its inodes .* and 85% of its space" <<< "$out" && ok "3 space at 85%, inodes low: warns" || bad "3 '$out'"

# 4. past 95%: sessions are about to fail
out=$(run --hook 1048576 2 4000000 2000000 2000000)
grep -q "^✖ $T is past 95% — 100% of its inodes (1,048,574 of 1,048,576) .*: sessions on this machine are about to fail" <<< "$out" \
  && ok "4 inodes at 100%: ✖ sessions are about to fail" || bad "4 '$out'"

# 5. a filesystem with no inode limit (f_files 0) is judged by space alone
out=$(run --hook 0 0 1000 100 100)
grep -q "90% of its space .*; no inode limit" <<< "$out" && ok "5 no inode count: space alone, said so" || bad "5 '$out'"

# 6. --report past the threshold: the largest top-level directories by entries, most first, and the
# cleanups as commands for the person — nothing is removed
mkdir -p "$T/pytest-of-tester/a" "$T/small" "$T/tmpleak"
for i in $(seq 1 30); do : > "$T/pytest-of-tester/a/f$i"; done
for i in $(seq 1 5); do : > "$T/tmpleak/f$i"; done
: > "$T/small/one"; : > "$T/loose-file"
before=$(find "$T" | wc -l)
out=$(run --report 1048576 104857 4000000 3000000 3000000)
first=$(grep -A1 "the largest directories in $T, by entries:" <<< "$out" | tail -1)
grep -q "^⚠ $T is past 80%" <<< "$out" && grep -qE "^ +32  $T/pytest-of-tester$" <<< "$first" \
  && grep -qE "^ +6  $T/tmpleak$" <<< "$out" && grep -qE "^ +2  $T/small$" <<< "$out" && ! grep -q "loose-file" <<< "$out" \
  && grep -q "rm -rf $T/pytest-of-tester" <<< "$out" \
  && grep -q "find $T -mindepth 1 -maxdepth 1 -type d -user tester -name 'tmp\*' -mmin +1440 -exec rm -rf {} +" <<< "$out" \
  && [ "$(find "$T" | wc -l)" = "$before" ] \
  && ok "6 --report names the directories by entries, most first, and prints the cleanups without running them" || bad "6 '$out'"

# 6b. the find never names the temp directory itself, even one called tmp* and owned by the user;
# a path with a space is quoted
mkdir -p "$TMP/tmp x/tmpold"; touch -d '3 days ago' "$TMP/tmp x/tmpold" "$TMP/tmp x"
out=$(USER=$(id -un) CLAUDE_CODE_TMPDIR="$TMP/tmp x" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.dirname(os.environ["SCRIPT"]))
import check_tmp as c
print(c.cleanups(c.tmp_dir())[1].split(":  ", 1)[1])
PY
)
cmd=${out/-exec rm -rf \{\} +/-print}
got=$(bash -c "$cmd")
[ "$got" = "$TMP/tmp x/tmpold" ] && grep -q "find '$TMP/tmp x' " <<< "$out" \
  && ok "6b the printed find, run with -print, names only the stale tmp* directory inside — never the temp dir, though it is one" || bad "6b '$out' -> '$got'"

# 7. the walk is bounded: a zero budget stops it and says the counts are partial
out=$(run --report 1048576 104857 4000000 3000000 3000000 0)
grep -q "the walk stopped at 0s: counts are at least these" <<< "$out" && ok "7 a walk past its budget stops and says so" || bad "7 '$out'"

# 8. the directory Claude Code uses: CLAUDE_CODE_TMPDIR, else TMPDIR, else /tmp; unreadable: --hook silent, exit 0
d=$(cd "$DC/files/scripts" && env -u CLAUDE_CODE_TMPDIR TMPDIR=/x python3 -c 'import check_tmp; print(check_tmp.tmp_dir())')
e=$(cd "$DC/files/scripts" && env -u CLAUDE_CODE_TMPDIR -u TMPDIR python3 -c 'import check_tmp; print(check_tmp.tmp_dir())')
[ "$d" = /x ] && [ "$e" = /tmp ] && ok "8 TMPDIR without CLAUDE_CODE_TMPDIR, else /tmp" || bad "8 '$d' '$e'"
out=$(CLAUDE_CODE_TMPDIR="$TMP/nowhere" python3 "$SCRIPT" --hook); rc=$?
out2=$(CLAUDE_CODE_TMPDIR="$TMP/nowhere" python3 "$SCRIPT" --report)
[ $rc -eq 0 ] && [ -z "$out" ] && grep -q "cannot read its filesystem's use — not checked" <<< "$out2" \
  && ok "8b a directory that cannot be read: --hook silent, exit 0; --report says not checked" || bad "8b rc=$rc '$out' '$out2'"

# 9. the real filesystem, unstubbed: exit 0 and at most one line — in a directory of this run's own, so a
# real temp dir past the threshold is never reaped by a test (TD-223)
mkdir -p "$TMP/t9"
out=$(CLAUDE_CODE_TMPDIR="$TMP/t9" python3 "$SCRIPT" --hook); rc=$?
[ $rc -eq 0 ] && [ "$(printf '%s' "$out" | grep -c '')" -le 1 ] && ok "9 the real temp filesystem: exit 0, at most one line" || bad "9 rc=$rc '$out'"

# 10. TD-223: past the threshold the user's own leftovers a day old are reaped — top-level tmp* and
# precheck-*, pytest-* under pytest-of-<user>/, a read-only tree among them — and nothing else
T="$TMP/t10"; mkdir -p "$T"
old() { mkdir -p "$1" && age "$1"; }
age() { find "$1" -depth -exec touch -h -d '2 days ago' {} +; }   # every entry of the tree, deepest first
old "$T/tmp.AbCdE12345"; mkdir -p "$T/precheck-7-x/head/cache/m"; touch "$T/precheck-7-x/head/cache/m/f"
chmod -R a-w "$T/precheck-7-x/head/cache"; age "$T/precheck-7-x"
mkdir -p "$T/tmpab12cd34/deep"; age "$T/tmpab12cd34"; touch "$T/tmpab12cd34/deep/live"   # a live tree, written at depth
old "$T/tmpnotes"   # a day old, named tmp* but not as tempfile or mktemp name a directory
mkdir -p "$T/pytest-of-tester"; old "$T/pytest-of-tester/pytest-3"; old "$T/pytest-of-tester/other-old"
mkdir -p "$T/tmp.fresh"; old "$T/claude-1000"; old "$T/keep-tmp.old"
ln -s "$T/tmp.fresh" "$T/tmp.link"; touch -h -d '2 days ago' "$T/tmp.link"
out=$(run --report 1000 900 1000 900 900); rc=$?   # under the threshold: nothing touched
[ $rc -eq 0 ] && [ -d "$T/tmp.AbCdE12345" ] && [ -d "$T/precheck-7-x" ] && ! grep -q reaped <<< "$out" \
  && ok "10 under the threshold: nothing is reaped" || bad "10 rc=$rc $out $(ls "$T")"
out=$(run --hook 1000 100 1000 900 900); rc=$?
[ $rc -eq 0 ] && [ ! -e "$T/tmp.AbCdE12345" ] && [ ! -e "$T/precheck-7-x" ] && [ ! -e "$T/pytest-of-tester/pytest-3" ] \
  && grep -q "reaped 3 of your own leftovers unchanged for a day, session folders 3" <<< "$out" \
  && ok "10b past the threshold --hook reaps aged tmp*, precheck-* (read-only inside) and pytest-*, saying so" || bad "10b rc=$rc $out $(ls -R "$T")"
[ -d "$T/tmp.fresh" ] && [ -d "$T/claude-1000" ] && [ -d "$T/keep-tmp.old" ] && [ -d "$T/pytest-of-tester/other-old" ] \
  && [ -L "$T/tmp.link" ] && [ -d "$T" ] && [ -e "$T/tmpab12cd34/deep/live" ] && [ -d "$T/tmpnotes" ] \
  && ok "10c a fresh one, a live tree with an old top, tmp* not named as tempfile names it, other names, a symlink and the directory itself are kept" || bad "10c $(ls -la "$T")"
other=$(python3 -c 'import os; print(os.getuid() + 1)')
python3 - "$T" "$other" <<'PY' && ok "10d another user's entry, and a temp dir that is / or above home, are never reaped" || bad "10d"
import os, sys
sys.path.insert(0, os.path.dirname(os.environ["SCRIPT"]))
import check_tmp as c
d = sys.argv[1]; os.makedirs(f"{d}/tmpzz99zz99", exist_ok=True); os.utime(f"{d}/tmpzz99zz99", (0, 0))
assert f"{d}/tmpzz99zz99" in c.reapable(d)
real = os.getuid
os.getuid = lambda: int(sys.argv[2])
assert c.reapable(d) == [], c.reapable(d)
os.getuid = real
os.environ["HOME"] = d + "/inside"          # the temp dir is above home: no temp dir at all
assert c.reapable(d) == [], "home"
assert c.reapable("/") == [], "root"
PY
mkdir -p "$TMP/t10e/other"; old "$TMP/t10e/other/pytest-1"; ln -s "$TMP/t10e/other" "$TMP/t10e/pytest-of-tester"
python3 - "$TMP/t10e" <<'PY' && ok "10e a pytest-of-<user> that is a symlink is not read" || bad "10e"
import os, sys
sys.path.insert(0, os.path.dirname(os.environ["SCRIPT"]))
import check_tmp as c
assert c.reapable(sys.argv[1]) == [], c.reapable(sys.argv[1])
PY

# 11. TD-296: Claude Code session folders, claude-<uid>/<project>/<uuid>/, idle 3 days, and in each seat dir
# <name>-<uid>/<seat>/ its pytest-of-<user>/pytest-* and session folders; restraint: a 2-day one, one with a
# file written today, a non-uuid name, a group not named -<uid>, a symlinked seat, and precheck.py's narrow reap
T="$TMP/t11"; U=$(id -u); mkdir -p "$T"
aged() { mkdir -p "$1" && : > "$1/f" && find "$1" -depth -exec touch -h -d "$2 days ago" {} +; }
S1=0a1b2c3d-0000-4000-8000-00000000000a S2=0a1b2c3d-0000-4000-8000-00000000000b
S3=0a1b2c3d-0000-4000-8000-00000000000c S4=0a1b2c3d-0000-4000-8000-00000000000d
aged "$T/claude-$U/-home-x-proj/$S1" 4                     # sentinel: must go
aged "$T/claude-$U/-home-x-proj/$S2" 2                     # two days: kept (a resumed session expects it)
aged "$T/claude-$U/-home-x-proj/$S3" 4; touch "$T/claude-$U/-home-x-proj/$S3/today"   # written today: kept
aged "$T/claude-$U/-home-x-proj/not-a-session" 4           # not a session id: kept
aged "$T/shiftlead-$U/seat1/pytest-of-tester/pytest-5" 2   # a seat's pytest run dir: must go
aged "$T/shiftlead-$U/seat1/claude-$U/-home-x-proj/$S4" 4  # a seat's session folder: must go
aged "$T/shiftlead-$U/seat1/keep-me" 4                     # anything else in a seat: kept
aged "$T/shiftlead-x/seat2/pytest-of-tester/pytest-6" 2    # a group not named -<uid>: not read
aged "$TMP/t11-elsewhere/pytest-of-tester/pytest-7" 2; ln -s "$TMP/t11-elsewhere" "$T/shiftlead-$U/seat3"   # a symlinked seat: not read
python3 - "$T" <<'PY2' && ok "11 precheck.py's narrow reap (its one name) leaves session folders and seat dirs alone" || bad "11"
import os, sys
sys.path.insert(0, os.path.dirname(os.environ["SCRIPT"]))
import check_tmp as c
assert c.reapable(sys.argv[1], ("precheck-*",)) == [], c.reapable(sys.argv[1], ("precheck-*",))
PY2
out=$(run --hook 1000 100 1000 900 900); rc=$?
[ $rc -eq 0 ] && [ ! -e "$T/claude-$U/-home-x-proj/$S1" ] && [ ! -e "$T/shiftlead-$U/seat1/pytest-of-tester/pytest-5" ] \
  && [ ! -e "$T/shiftlead-$U/seat1/claude-$U/-home-x-proj/$S4" ] \
  && grep -q "reaped 3 of your own leftovers unchanged for a day, session folders 3 (.* entries): $S1, $S4, pytest-5" <<< "$out" \
  && ok "11b past the threshold: a session folder idle 3 days, a seat's pytest run dir and a seat's session folder are reaped, named" || bad "11b rc=$rc $out $(find "$T")"
[ -d "$T/claude-$U/-home-x-proj/$S2" ] && [ -e "$T/claude-$U/-home-x-proj/$S3/today" ] && [ -d "$T/claude-$U/-home-x-proj/not-a-session" ] \
  && [ -d "$T/shiftlead-$U/seat1/keep-me" ] && [ -d "$T/shiftlead-x/seat2/pytest-of-tester/pytest-6" ] \
  && [ -d "$TMP/t11-elsewhere/pytest-of-tester/pytest-7" ] && [ -d "$T/claude-$U/-home-x-proj" ] \
  && ok "11c a 2-day session folder, one written today, a non-uuid name, other seat files, an other-named group and a symlinked seat are kept" || bad "11c $(find "$T")"
python3 - "$T" <<'PY2' && ok "11d the claude-<uid> folder read is the running user's own uid alone" || bad "11d"
import os, sys, time
sys.path.insert(0, os.path.dirname(os.environ["SCRIPT"]))
import check_tmp as c
d = sys.argv[1]; s = f"{d}/claude-{os.getuid()}/-home-x-proj/0a1b2c3d-0000-4000-8000-00000000000e"
os.makedirs(s); os.utime(s, (0, 0))
assert s in c.reapable(d), c.reapable(d)
real = os.getuid; uid = real()
os.getuid = lambda: uid + 1
assert c.reapable(d) == [], c.reapable(d)
os.getuid = real
PY2

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
