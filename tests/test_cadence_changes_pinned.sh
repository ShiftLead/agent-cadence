#!/usr/bin/env bash
# cadence_changes.py in a pinned repo (cadence.md §9.19, TD-250): run from the launcher's tree
# (outside the repo), it reads the source's files/docs/cadence-changes.md at origin's pin from the
# launcher's cache, never the repo. Offline: the source, the consumer and its origin are local
# repos; the cache is a scratch XDG_CACHE_HOME. Dates derive from the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME"
unset SHIFTLEAD_SESSION CADENCE_ATTENTION_SCOPE GIT_DIR GIT_WORK_TREE
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
OLD=$(date -u -d "40 days ago" +%F); OLDER=$(date -u -d "60 days ago" +%F)
at() { date -u -d "$1" +%FT%TZ; }

# the script as the launcher runs it: from a tree outside the repo
T="$TMP/tree/files/scripts"; mkdir -p "$T"; cp "$DC/files/scripts/cadence_changes.py" "$T/"
SCRIPT="$T/cadence_changes.py"

# --- the source: commit A has one entry, B adds a second (dated long ago: only the bump brings it)
S="$TMP/source"; git init -q -b main "$S"; mkdir -p "$S/files/docs"
printf '# Cadence changes\n## %s — rule from A\nDo: the A thing.\n' "$OLDER" > "$S/files/docs/cadence-changes.md"
git -C "$S" add . && git -C "$S" commit -qm A; A=$(git -C "$S" rev-parse HEAD)
printf '# Cadence changes\n## %s — rule brought by B\nDo: the B thing.\n## %s — rule from A\nDo: the A thing.\n' "$OLD" "$OLDER" > "$S/files/docs/cadence-changes.md"
git -C "$S" commit -qam B; B=$(git -C "$S" rev-parse HEAD)
git clone -q --bare "$S" "$TMP/source.git"; SRC="$TMP/source.git"

# --- the consumer: adopt at A (10d ago), bump to B (8d), roll back to A (6d), bump again to B (4d)
R="$TMP/repo"; git init -q --bare -b main "$R.git"; git clone -q "$R.git" "$R" 2>/dev/null
git -C "$R" checkout -q -b main 2>/dev/null; mkdir -p "$R/docs"
pin() { printf '[agent-cadence]\nsource = "%s"\nref = "%s"\n' "$SRC" "$1" > "$R/docs/cadence.toml"; git -C "$R" add docs/cadence.toml
        GIT_COMMITTER_DATE=$(at "$2") GIT_AUTHOR_DATE=$(at "$2") git -C "$R" commit -qm "$3"; }
pin "$A" "10 days ago" adopt;    C1=$(git -C "$R" rev-parse HEAD)
pin "$B" "8 days ago" bump
pin "$A" "6 days ago" rollback
pin "$B" "4 days ago" rebump;    C4=$(git -C "$R" rev-parse HEAD)
git -C "$R" push -q -u origin main 2>/dev/null; git -C "$R" fetch -q origin
git -C "$R" worktree add -q -b old "$R/wt-old" "$C1"
hook() { ( cd "$1" && python3 "$SCRIPT" --hook 2>&1 ); }
A7=${A:0:7}; B7=${B:0:7}

# --- 1) no clone in the cache: --hook fetches no source and makes no clone
out=$(hook "$R"); rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok "no clone: a worktree on origin's pin hears nothing" || bad "no clone, main: rc=$rc $out"
out=$(hook "$R/wt-old")
[ "$out" = "📣 (this worktree pins $A7, origin/main pins $B7 — rebase; \`agent-cadence path cadence.md\` prints the path of the rules it runs now)" ] \
  && ok "no clone: a worktree on an older pin gets the behind line alone" || bad "no clone, old: $out"
[ ! -e "$XDG_CACHE_HOME/agent-cadence/sources" ] && ok "--hook made no clone and took no lock" || bad "hook touched the cache: $(ls -R "$XDG_CACHE_HOME" | head)"
out=$(hook "$R/wt-old"); [ -z "$out" ] && ok "the behind line is once per origin pin" || bad "behind repeated: $out"

# --- 2) --json clones once and lands each heading at the commit whose pin last brought it
j=$(cd "$R" && python3 "$SCRIPT" --json); rc=$?
c1t=$(git -C "$R" log -1 --format=%cI "$C1"); c4t=$(git -C "$R" log -1 --format=%cI "$C4")
got=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["ref"]); [print(e["title"], e["landed"]) for e in d["entries"]]' "$j" 2>&1)
want=$(printf 'origin/main\nrule brought by B %s\nrule from A %s' "$c4t" "$c1t")
[ $rc -eq 0 ] && [ "$got" = "$want" ] && ok "--json: origin's pin's entries; landed at the rebump and the adopt" || bad "--json rc=$rc
got:  $got
want: $want"
ls "$XDG_CACHE_HOME"/agent-cadence/sources/*.git >/dev/null 2>&1 && ok "--json made the cache's clone" || bad "no clone made"
out=$(cd "$R" && python3 "$SCRIPT" --list)
echo "$out" | grep -q "rule brought by B" && echo "$out" | grep -q "rule from A" && ok "--list reads as --json" || bad "--list: $out"

# --- 3) with the clone: a bump's entry reaches a worktree on origin's pin (the bump rule), once
rm -f "$R/.git/cadence-changes-seen"
out=$(hook "$R")
echo "$out" | grep -q "1 cadence change this worktree" && echo "$out" | grep -q "rule brought by B" \
  && ! echo "$out" | grep -q "rule from A" && ! echo "$out" | grep -q rebase && ok "bump rule: the bump's old-dated entry is printed, no behind line" || bad "bump rule: $out"
out=$(hook "$R"); [ -z "$out" ] && ok "then silent" || bad "repeat: $out"

# --- 4) a worktree on the older pin: the new entry and the behind line
rm -f "$R/.git/worktrees/wt-old/cadence-changes-seen"
out=$(hook "$R/wt-old")
echo "$out" | grep -q "rule brought by B" && ! echo "$out" | grep -q "rule from A" && echo "$out" | grep -q "pins $A7, origin/main pins $B7" \
  && ok "older pin: the entry its pin lacks, with the behind line" || bad "older pin: $out"

# --- 5) the trees on disk serve without a clone
mv "$XDG_CACHE_HOME/agent-cadence/sources" "$TMP/sources.away"
for c in "$A" "$B"; do mkdir -p "$XDG_CACHE_HOME/agent-cadence/trees/$c/files/docs"
  git -C "$S" show "$c:files/docs/cadence-changes.md" > "$XDG_CACHE_HOME/agent-cadence/trees/$c/files/docs/cadence-changes.md"; done
rm -f "$R/.git/worktrees/wt-old/cadence-changes-seen"
out=$(hook "$R/wt-old")
echo "$out" | grep -q "rule brought by B" && ok "trees on disk: read with no clone" || bad "trees: $out"
[ ! -e "$XDG_CACHE_HOME/agent-cadence/sources" ] && ok "  ... and no clone made" || bad "trees: a clone appeared"

# --- 6) a worktree branched before the migration: its retired copy is its own file
git -C "$R" worktree add -q -b pre "$R/wt-pre" "$C1"
git -C "$R/wt-pre" rm -q docs/cadence.toml
out=$(hook "$R/wt-pre")
[ "$out" = "📣 (this worktree runs no agent-cadence; origin/main pins $B7 — rebase)" ] && ok "a worktree with neither pin nor copy: the behind line alone" || bad "no pin, no copy: $out"
rm -f "$R/.git/worktrees/wt-pre/cadence-changes-seen"; mkdir -p "$R/wt-pre/docs"
printf '# Cadence changes\n## %s — rule from A\nDo: the A thing.\n' "$OLDER" > "$R/wt-pre/docs/cadence-changes.md"
out=$(hook "$R/wt-pre")
echo "$out" | grep -q "rule brought by B" && ! echo "$out" | grep -q "rule from A" && echo "$out" | grep -q "carries its own copy; origin/main pins $B7 — rebase" \
  && ok "pre-migration worktree: what its copy lacks, and its behind line" || bad "pre-migration: $out"
rm -rf "$XDG_CACHE_HOME/agent-cadence/trees"; mv "$TMP/sources.away" "$XDG_CACHE_HOME/agent-cadence/sources"

# --- 6b) the source moves on after the clone: --json fetches the commit the clone lacks, once;
#         and a commit pinning another source is skipped by the walk (it neither lands nor ends a run)
printf '# Cadence changes\n## %s — rule brought by D\nDo: the D thing.\n' "$OLD" > "$TMP/d.md"
cat "$S/files/docs/cadence-changes.md" >> "$TMP/d.md"; tail -n +2 "$TMP/d.md" | sed '1i # Cadence changes' > "$S/files/docs/cadence-changes.md"
git -C "$S" commit -qam D; D=$(git -C "$S" rev-parse HEAD); git -C "$S" push -q "$SRC" main 2>/dev/null
OTHER="$TMP/other.git"; git clone -q --bare "$S" "$OTHER"
printf '[agent-cadence]\nsource = "%s"\nref = "%s"\n' "$OTHER" "$D" > "$R/docs/cadence.toml"; git -C "$R" add docs/cadence.toml
GIT_COMMITTER_DATE=$(at "3 days ago") git -C "$R" commit -qm "pin another source"
pin "$D" "2 days ago" "bump to D"; C6=$(git -C "$R" rev-parse HEAD)
git -C "$R" push -q origin main 2>/dev/null; git -C "$R" fetch -q origin
j=$(cd "$R" && python3 "$SCRIPT" --json); rc=$?
c6t=$(git -C "$R" log -1 --format=%cI "$C6")
got=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); [print(e["title"], e["landed"]) for e in d["entries"]]' "$j" 2>&1)
want=$(printf 'rule brought by D %s\nrule brought by B %s\nrule from A %s' "$c6t" "$c4t" "$c1t")
[ $rc -eq 0 ] && [ "$got" = "$want" ] && ok "fetch: the commit the clone lacked is fetched; the other source's commit is skipped" || bad "fetch/skip rc=$rc
got:  $got
want: $want"
[ ! -e "$XDG_CACHE_HOME/agent-cadence/sources/$(printf %s "$OTHER" | sha256sum | cut -c1-16).git" ] && ok "  ... and the other source is never cloned" || bad "other source cloned"

# --- 7) an unreachable source with no clone: --json exits 2, the reason last on stderr
R2="$TMP/repo2"; git init -q --bare -b main "$R2.git"; git clone -q "$R2.git" "$R2" 2>/dev/null; git -C "$R2" checkout -q -b main 2>/dev/null
mkdir -p "$R2/docs"; printf '[agent-cadence]\nsource = "%s"\nref = "%s"\n' "$TMP/nowhere.git" "$B" > "$R2/docs/cadence.toml"
git -C "$R2" add . && git -C "$R2" commit -qm adopt && git -C "$R2" push -q -u origin main 2>/dev/null; git -C "$R2" fetch -q origin
err=$(cd "$R2" && python3 "$SCRIPT" --json 2>&1 >/dev/null); rc=$?
[ $rc -eq 2 ] && echo "$err" | tail -1 | grep -q "cannot read origin's pin $B7 .*cloning $TMP/nowhere.git failed" && ok "unreachable source: exit 2 with the reason" || bad "unreachable: rc=$rc $err"
out=$(hook "$R2"); [ $? -eq 0 ] && [ -z "$out" ] && ok "  ... and --hook says nothing, exit 0" || bad "unreachable hook: $out"

# --- 8) no pin on origin: the repo reads as before (no file, no changes), and no cache is touched
R3="$TMP/repo3"; git init -q --bare -b main "$R3.git"; git clone -q "$R3.git" "$R3" 2>/dev/null; git -C "$R3" checkout -q -b main 2>/dev/null
echo x > "$R3/f"; git -C "$R3" add . && git -C "$R3" commit -qm base && git -C "$R3" push -q -u origin main 2>/dev/null; git -C "$R3" fetch -q origin
out=$( cd "$R3" && XDG_CACHE_HOME="$TMP/cache3" python3 "$SCRIPT" --list ); rc=$?
[ $rc -eq 0 ] && [ "$out" = "no cadence changes" ] && [ ! -e "$TMP/cache3" ] && ok "no pin on origin: reads as before" || bad "no pin: rc=$rc $out"

# --- 9) a copy inside the repo (a synced copy, or this repo) never reads the pin
mkdir -p "$R/scripts"; cp "$SCRIPT" "$R/scripts/"
out=$( cd "$R" && XDG_CACHE_HOME="$TMP/cache4" python3 scripts/cadence_changes.py --list ); rc=$?
[ $rc -eq 0 ] && [ "$out" = "no cadence changes" ] && [ ! -e "$TMP/cache4" ] && ok "a copy inside the repo reads the repo's own file" || bad "in-repo copy: rc=$rc $out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
