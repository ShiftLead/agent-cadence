#!/usr/bin/env bash
# The launcher (TD-129 slice 1, docs/plans/2026-10-25-pinned-not-synced.md): launcher/agent_cadence.py
# resolves a repo's [agent-cadence] pin, makes the cached read-only tree of that commit, and execs the
# tree's launcher/words.py with CADENCE_REPO_ROOT set. Offline and fixture-driven: the "source" is a
# temp repo reached by file://, the cache is under XDG_CACHE_HOME in the temp dir.
# Asserts: run and path from the pinned tree, with the root handed over; the tree read-only and
# reused without the source; a worktree runs its own pin, a hook the main checkout's; each refusal
# (no pin, a tag or short ref, a commit not in the source, an interface too new, a commit with no
# launcher) exits 2 with its reason; a stale temp tree is cleared; two first runs at once both
# succeed; agent-cadence's own repo runs from its own tree; cadence_config.py --check reads the pin.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
L="$DC/launcher/agent_cadence.py"
TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" XDG_CACHE_HOME="$TMP/cache" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SHIFTLEAD_SESSION CADENCE_REPO_ROOT
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
dc() { local d=$1; shift; (cd "$d" && python3 "$L" "$@" 2>&1); }
TREES="$XDG_CACHE_HOME/agent-cadence/trees"

# the source: an agent-cadence with the real words.py, a script that reports what it was given, and docs
SRC="$TMP/src"; git init -q -b main "$SRC"
mkdir -p "$SRC/launcher" "$SRC/files/scripts" "$SRC/files/docs"
cp "$DC/launcher/words.py" "$SRC/launcher/"; echo 1 > "$SRC/launcher/INTERFACE"
cat > "$SRC/files/scripts/hello.py" <<'EOF'
import os, sys
print("v1 root=" + os.environ.get("CADENCE_REPO_ROOT", "") + " cwd=" + os.getcwd() + " args=" + " ".join(sys.argv[1:]))
EOF
echo "# the rules" > "$SRC/files/docs/cadence.md"
mkdir -p "$SRC/files/scripts/git-hooks"
printf '%s\n' 'echo "hooks $* cwd=$PWD tree=$(cd "$(dirname "$0")/../.." && pwd) stdin=$(cat)"' > "$SRC/files/scripts/cadence_hooks.sh"
printf '#!/bin/sh\necho "pre-push $* cwd=$PWD"\nexit 3\n' > "$SRC/files/scripts/git-hooks/pre-push"
chmod +x "$SRC/files/scripts/cadence_hooks.sh" "$SRC/files/scripts/git-hooks/pre-push" "$SRC/files/scripts/hello.py"   # hello.py executable: hook ../hello.py is refused by name, not by mode
mkdir -m 700 "$TMP/victim"; echo s > "$TMP/victim/secret"
ln -s "$TMP/victim" "$SRC/files/link"   # a symlink out of the tree: never chmod'ed through
printf 'files/docs/cadence.md export-ignore\n' > "$SRC/.gitattributes"   # the tree is the commit, not an archive
git -C "$SRC" add -A && git -C "$SRC" commit -qm c1 && git -C "$SRC" tag v1
C1=$(git -C "$SRC" rev-parse HEAD)
sed -i 's/"v1 /"v3 /' "$SRC/files/scripts/hello.py"; git -C "$SRC" commit -qam c3
C3=$(git -C "$SRC" rev-parse HEAD)
echo 2 > "$SRC/launcher/INTERFACE"; git -C "$SRC" commit -qam c-iface2
C2=$(git -C "$SRC" rev-parse HEAD)
git -C "$SRC" rm -q launcher/INTERFACE; git -C "$SRC" commit -qm c-noiface
C0=$(git -C "$SRC" rev-parse HEAD)
git -C "$SRC" checkout -q "$C1"   # the source's own work tree is never read

pin() {  # pin <repo> <ref> [source]
  mkdir -p "$1/docs"
  printf '# settings\n[agent-cadence]\nsource = "%s"\nref = "%s"   # v1\n' "${3:-file://$SRC}" "$2" > "$1/docs/cadence.toml"
}
R="$TMP/consumer"; git init -q -b main "$R"; pin "$R" "$C1"
git -C "$R" add -A && git -C "$R" commit -qm init

out=$(dc "$R" run hello.py a b); rc=$?
[ $rc -eq 0 ] && [ "$out" = "v1 root=$R cwd=$R args=a b" ] && ok "run: the pinned script runs with the root and its args" || bad "run: rc=$rc out=$out"
[ -d "$TREES/$C1" ] && ok "the tree is cached under trees/<commit>" || bad "no tree at $TREES/$C1"
[ -f "$TREES/$C1/files/docs/cadence.md" ] && ok "the tree is the commit: an export-ignore'd file is there" || bad "export-ignore dropped a file"
[ -x "$TREES/$C1/launcher/words.py" ] && [ -L "$TREES/$C1/files/link" ] && ok "modes and symlinks kept" || bad "modes/symlinks: $(ls -l "$TREES/$C1/launcher" "$TREES/$C1/files")"
f="$TREES/$C1/files/scripts/hello.py"
[ ! -w "$f" ] && [ ! -w "$TREES/$C1/files" ] && [ ! -w "$TREES/$C1" ] && ok "the tree is read-only" || bad "the tree is writable: $(ls -ld "$f" "$TREES/$C1")"
mkdir -p "$R/sub"; out=$(dc "$R/sub" run hello.py)
[ "$out" = "v1 root=$R cwd=$R/sub args=" ] && ok "run from a subdirectory: the root is the checkout's, the cwd kept" || bad "subdir: $out"
out=$(dc "$R" path cadence.md)
[ "$out" = "$TREES/$C1/files/docs/cadence.md" ] && ok "path cadence.md: the pinned rules" || bad "path: $out"
out=$(dc "$R" path); [ "$out" = "$TREES/$C1/files" ] && ok "path: the pinned payload" || bad "path alone: $out"
out=$(dc "$R" path nope.md); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"no nope.md"* ]] && ok "path of a missing file: exit 2, named" || bad "path missing: rc=$rc $out"
out=$(dc "$R" run ../hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"not a path"* ]] && ok "run refuses a path" || bad "run path: rc=$rc $out"
out=$(dc "$R" frobnicate); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"unknown word 'frobnicate'"* ]] && ok "an unknown word: exit 2, the words listed" || bad "unknown word: rc=$rc $out"
out=$(dc "$R" words); [[ "$out" == *"agent-cadence run <script>"* ]] && ok "words lists the words" || bad "words: $out"

mv "$SRC" "$SRC.away"
out=$(dc "$R" run hello.py); [[ "$out" == "v1 "* ]] && ok "a cached tree runs without the source" || bad "no source: $out"
mv "$SRC.away" "$SRC"

# a worktree runs its own pin; a hook resolves the main checkout's
git -C "$R" worktree add -q -b bump "$TMP/wt" 2>/dev/null; pin "$TMP/wt" "$C3"
out=$(dc "$TMP/wt" run hello.py); [ "$out" = "v3 root=$TMP/wt cwd=$TMP/wt args=" ] && ok "a worktree runs its own pin (a bump branch tests its new pin)" || bad "worktree: $out"
hr=$(cd "$TMP/wt" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import agent_cadence as d; print(d.find_root("hook", "."), d.find_root("run", "."))' "$DC/launcher")
[ "$hr" = "$R $TMP/wt" ] && ok "hook resolves the main checkout, run the worktree" || bad "find_root: $hr"
chmod -R u+w "$TREES" && rm -rf "${TREES:?}"/*
out=$(echo '{"p":1}' | dc "$TMP/wt" hook session-start)
[ "$out" = "hooks --session-start cwd=$TMP/wt tree=$TREES/$C1 stdin={\"p\":1}" ] && [ -d "$TREES/$C1" ] && [ ! -e "$TREES/$C3" ] && ok "hook session-start from a worktree: the main checkout's pinned runner, in the worktree, stdin passed" || bad "hook: $out; $(ls "$TREES")"
out=$(dc "$TMP/wt" hook pre-push origin url); rc=$?
[ $rc -eq 3 ] && [ "$out" = "pre-push origin url cwd=$TMP/wt" ] && ok "hook <git-hook>: the shipped hook, its args and its exit code" || bad "hook pre-push: rc=$rc $out"
for h in post-checkout ../hello.py; do
  out=$(dc "$TMP/wt" hook "$h"); rc=$?
  [ $rc -eq 0 ] && [[ "$out" == *"no hook '$h'"*"did not run"* ]] && ok "hook '$h' not shipped: said, and exit 0 (a hook fails open)" || bad "hook $h: rc=$rc $out"
done
# TD-147: a constellation's sibling — the home's pin by -C, the runner in the sibling (--serve), CADENCE_HOME the home
SIB="$R/sib"; mkdir -p "$SIB"; git init -q -b main "$SIB"
out=$(cd "$TMP" && echo '{"p":1}' | python3 "$L" -C "$R" hook session-start --serve "$SIB" 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$out" = "hooks --session-start cwd=$SIB tree=$TREES/$C1 stdin={\"p\":1}" ] \
  && ok "hook session-start --serve: the home's pinned runner, run in the sibling, --serve consumed" || bad "serve: rc=$rc $out"
out=$(cd "$R" && python3 - "$DC/launcher/words.py" "$R" "$SIB" <<'PY'
import os, sys
sys.argv[0:1] = []
words, home, sib = sys.argv
os.environ["CADENCE_REPO_ROOT"] = home
sys.path.insert(0, os.path.dirname(words))
import words as W
W.os.execvp = lambda f, argv: print(os.environ["CADENCE_HOME"], os.getcwd(), " ".join(argv[2:]))
W.w_hook(["session-start", "--serve", sib])
PY
); [ "$out" = "$R $SIB --session-start" ] && ok "  ... with CADENCE_HOME naming the home" || bad "serve env: $out"
out=$(cd "$TMP" && python3 "$L" -C "$R" hook session-start --serve "$TMP/no-such" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "needs the sibling's directory" <<< "$out" && ! grep -q "^hooks " <<< "$out" \
  && ok "hook session-start --serve with no such directory: said, nothing run, exit 0 (a hook fails open)" || bad "serve missing: rc=$rc $out"
out=$(cd "$TMP" && python3 "$L" -C "$R/sub" run hello.py 2>&1)
[ "$out" = "v1 root=$R cwd=$R/sub args=" ] && ok "-C as git's: resolved and run in the directory" || bad "-C: $out"
out=$(python3 "$L" -C "$TMP/nope" run hello.py 2>&1); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"-C $TMP/nope"* ]] && ok "-C a missing directory: exit 2, named" || bad "-C missing: rc=$rc $out"

# refusals
N="$TMP/plain"; git init -q -b main "$N"
out=$(dc "$N" run hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"not a cadence repo"* ]] && ok "no pin: not a cadence repo, exit 2" || bad "no pin: rc=$rc $out"
out=$(dc "$TMP" run hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"not in a git checkout"* ]] && ok "outside a checkout: exit 2" || bad "no checkout: rc=$rc $out"
for ref in v1 main "${C1:0:12}"; do
  pin "$N" "$ref"; out=$(dc "$N" run hello.py); rc=$?
  [ $rc -eq 2 ] && [[ "$out" == *"full 40-hex commit"* ]] && ok "ref '$ref' refused: a full commit only" || bad "ref $ref: rc=$rc $out"
done
for src in "-uupload-pack=x" "rel/path" " "; do
  pin "$N" "$C1" "$src"; out=$(dc "$N" run hello.py); rc=$?
  [ $rc -eq 2 ] && [[ "$out" == *"source must be a git URL or an absolute path"* ]] && ok "source '$src' refused" || bad "source $src: rc=$rc $out"
done
pin "$N" "$(printf 'a%.0s' {1..40})"; out=$(dc "$N" run hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"is not in file://$SRC"* ]] && ok "a commit not in the source: exit 2, named" || bad "missing commit: rc=$rc $out"
pin "$N" "$C2"; out=$(dc "$N" run hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"needs launcher interface 2; this launcher is 1"* ]] && [[ "$out" == *"install"* ]] && ok "an interface too new: refused with the install line" || bad "iface: rc=$rc $out"
pin "$N" "$C0"; out=$(dc "$N" run hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"predates the launcher"* ]] && ok "a commit with no launcher: refused" || bad "no iface: rc=$rc $out"
printf '[agent-cadence\n' > "$N/docs/cadence.toml"; out=$(dc "$N" run hello.py); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"cadence.toml"* ]] && ok "an unreadable cadence.toml: exit 2, the file named" || bad "bad toml: rc=$rc $out"

# a stale temp tree (a run that died) is cleared by the next tree made; two first runs at once both work
rm -rf "$XDG_CACHE_HOME/agent-cadence"/sources; chmod -R u+w "$TREES" && rm -rf "$TREES/$C1"
mkdir -p "$TREES/.tmp-dead-1/x"; chmod 555 "$TREES/.tmp-dead-1/x" "$TREES/.tmp-dead-1"
R2="$TMP/consumer2"; git init -q -b main "$R2"; pin "$R2" "$C1"
dc "$R" run hello.py > "$TMP/p1" & p1=$!
dc "$R2" run hello.py > "$TMP/p2" & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && grep -q "root=$R " "$TMP/p1" && grep -q "root=$R2 " "$TMP/p2" && ok "two first runs at once: both work" || bad "parallel: $r1 $r2 $(cat "$TMP/p1" "$TMP/p2")"
[ ! -e "$TREES/.tmp-dead-1" ] && ok "a stale temp tree is cleared" || bad "stale tmp left"
mkdir -p "$TREES/.tmp-dead-2"; ln -s "$TMP/victim" "$TREES/.tmp-dead-2/out"; chmod 555 "$TREES/.tmp-dead-2"
git -C "$SRC" checkout -q -b b4 "$C1"; echo "# new" >> "$SRC/files/docs/cadence.md"; git -C "$SRC" commit -qam c4
C4=$(git -C "$SRC" rev-parse HEAD); git -C "$SRC" checkout -q "$C1"
pin "$R2" "$C4"; out=$(dc "$R2" path cadence.md)
[ "$out" = "$TREES/$C4/files/docs/cadence.md" ] && ok "a commit the cached clone lacks is fetched (a bump)" || bad "fetch: $out"
[ ! -e "$TREES/.tmp-dead-2" ] && [ "$(stat -c %a "$TMP/victim")" = 700 ] && [ -f "$TMP/victim/secret" ] && ok "clearing a stale tree never follows its symlinks" || bad "victim: $(stat -c %a "$TMP/victim"); $(ls "$TMP/victim")"
left=$(find "$TREES" "$XDG_CACHE_HOME/agent-cadence/sources" -maxdepth 1 -name '*.tmp*' | wc -l)
[ "$left" -eq 0 ] && ok "no temp tree left behind" || bad "$left temp trees left"

# agent-cadence's own repo: no pin, it runs from its own tree (and writes no cache)
rm -rf "$TMP/cache2"; out=$(cd "$DC" && XDG_CACHE_HOME="$TMP/cache2" python3 "$L" path cadence.md 2>&1)
[ "$out" = "$DC/files/docs/cadence.md" ] && [ ! -e "$TMP/cache2" ] && ok "agent-cadence's own repo runs from its own tree" || bad "own repo: $out"
out=$(python3 "$L" --interface); [ "$out" = "$(cat "$DC/launcher/INTERFACE")" ] && ok "--interface: the launcher's number, the tree's INTERFACE" || bad "--interface: $out vs $(cat "$DC/launcher/INTERFACE")"
out=$(python3 "$L" 2>&1); rc=$?; [ $rc -eq 2 ] && [[ "$out" == usage:* ]] && ok "no word: usage, exit 2" || bad "no word: rc=$rc $out"

# the real scripts from a pinned tree find the repo the launcher names, not the tree (CADENCE_REPO_ROOT)
SRC3="$TMP/src3"; mkdir -p "$SRC3/files"; git init -q -b main "$SRC3"
cp -r "$DC/launcher" "$SRC3/"; cp -r "$DC/files/scripts" "$SRC3/files/"; mkdir -p "$SRC3/files/docs"
cp "$DC/files/docs/user_attention.md" "$SRC3/files/docs/"   # the template a real tree carries, never the one read
find "$SRC3" -name __pycache__ -prune -exec rm -rf {} +
git -C "$SRC3" add -A && git -C "$SRC3" commit -qm real; C5=$(git -C "$SRC3" rev-parse HEAD)
R3="$TMP/consumer3"; git init -q -b main "$R3"; pin "$R3" "$C5" "file://$SRC3"
printf -- '- [ ] act %s (person) — the consumer'"'"'s own item. Due: %s.\n' "$(date +%F)" "$(date +%F)" > "$R3/docs/user_attention.md"
out=$(dc "$R3" run nudge_user_attention.py --report)
[[ "$out" == *"== consumer3 ($R3/docs/user_attention.md)"* ]] && [[ "$out" == *"the consumer's own item"* ]] && ok "a pinned nudge_user_attention.py reads the repo's board, not the tree's" || bad "nudge from the tree: $out"

# cadence_config.py --check reads the pin with the launcher's rules
CC="$DC/files/scripts/cadence_config.py"
pin "$R2" "$C1"; out=$(cd "$R2" && python3 "$CC" --check 2>&1); rc=$?
[ $rc -eq 0 ] && ok "--check: a good pin passes" || bad "--check good: rc=$rc $out"
pin "$R2" v1; out=$(cd "$R2" && python3 "$CC" --check 2>&1); rc=$?
[ $rc -eq 1 ] && [[ "$out" == *"[agent-cadence] ref must be a full 40-hex commit"* ]] && ok "--check: a tag pin flagged" || bad "--check tag: rc=$rc $out"
pin "$R2" "$C1" "rel/path"; out=$(cd "$R2" && python3 "$CC" --check 2>&1); rc=$?
[ $rc -eq 1 ] && [[ "$out" == *"source must be a git URL or an absolute path"* ]] && ok "--check: a relative source flagged" || bad "--check source: rc=$rc $out"
printf '[agent-cadence]\nsource = "x"\nref = "%s"\nrev = "y"\n' "$C1" > "$R2/docs/cadence.toml"; out=$(cd "$R2" && python3 "$CC" --check 2>&1); rc=$?
[ $rc -eq 1 ] && [[ "$out" == *"unknown field 'rev'"* ]] && ok "--check: an unknown pin field flagged" || bad "--check field: rc=$rc $out"
rm "$R2/docs/cadence.toml"; printf '[agent-cadence]\nsource = "x"\nref = "%s"\n' "$C1" > "$AGENT_CADENCE_REG_DIR/cadence.toml"
out=$(cd "$R2" && python3 "$CC" --check 2>&1); rc=$?
[ $rc -eq 1 ] && [[ "$out" == *"is the repo's pin"* ]] && ok "--check: a pin in the machine file flagged" || bad "--check machine: rc=$rc $out"
rm "$AGENT_CADENCE_REG_DIR/cadence.toml"

# gc: a tree no roster repo or worktree pins is listed, and removed only with --apply
pin "$R2" "$C4"
out=$(dc "$R" gc); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"no roster"* ]] && ok "gc with no roster: refuses, removes nothing" || bad "gc no roster: rc=$rc $out"
printf '# only a comment\n\n' > "$AGENT_CADENCE_REG_DIR/repos.txt"
out=$(dc "$R" gc --apply); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"an empty one"* ]] && ok "gc with an empty roster: refuses, removes nothing" || bad "gc empty roster: rc=$rc $out"
pin "$TMP/wt" "$C3"; dc "$TMP/wt" run hello.py >/dev/null   # the branch's tree is cached too
before=$(ls "$TREES" | sort)
printf '%s\n# a comment\n%s  # trailing\n' "$R" "$TMP/gone" > "$AGENT_CADENCE_REG_DIR/repos.txt"
out=$(dc "$R" gc --apply); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"$TMP/gone: on the roster but not here"* ]] && [ "$(ls "$TREES" | sort)" = "$before" ] && ok "gc --apply with a roster repo not here: refuses, removes nothing" || bad "gc gone: rc=$rc $out"
printf '%s\n' "$R" > "$AGENT_CADENCE_REG_DIR/repos.txt"
cp "$TMP/wt/docs/cadence.toml" "$TMP/wt.toml"; printf '[agent-cadence\n' > "$TMP/wt/docs/cadence.toml"
out=$(dc "$R" gc); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"cannot read  $TMP/wt/docs/cadence.toml"* ]] && [[ "$out" == *"--apply refuses"* ]] && ok "gc lists a pin it cannot read" || bad "gc bad toml list: rc=$rc $out"
out=$(dc "$R" gc --apply); rc=$?
[ $rc -eq 2 ] && [ "$(ls "$TREES" | sort)" = "$before" ] && ok "gc --apply with a pin it cannot read: refuses, removes nothing" || bad "gc bad toml: rc=$rc $out"
cp "$TMP/wt.toml" "$TMP/wt/docs/cadence.toml"
out=$(dc "$R" gc); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"unpinned  $TREES/$C4"* ]] && [[ "$out" == *"unpinned  $TREES/$C5"* ]] && [[ "$out" != *"$C1"* ]] && [[ "$out" != *"$C3"* ]] && [ "$(ls "$TREES" | sort)" = "$before" ] \
  && ok "gc: lists the unpinned trees (not the main checkout's, not a worktree's), removes nothing" || bad "gc list: rc=$rc $out"
python3 -c 'import fcntl, sys, time; f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); print("held", flush=True); time.sleep(2)' "$XDG_CACHE_HOME/agent-cadence/lock" > "$TMP/held" & holder=$!
for _ in $(seq 50); do [ -s "$TMP/held" ] && break; sleep 0.1; done
t0=$(date +%s%N); out=$(dc "$R" gc --apply); rc=$?; t1=$(date +%s%N); wait $holder
[ $(( (t1 - t0) / 1000000 )) -ge 1000 ] && ok "gc --apply waits for a launcher holding the cache's lock" || bad "gc did not wait: $(( (t1 - t0) / 1000000 ))ms"
[ $rc -eq 0 ] && [ ! -e "$TREES/$C4" ] && [ ! -e "$TREES/$C5" ] && [ -d "$TREES/$C1" ] && [ -d "$TREES/$C3" ] && ok "gc --apply: removes exactly those" || bad "gc apply: rc=$rc $out; $(ls "$TREES")"
out=$(dc "$R2" path cadence.md); [ "$out" = "$TREES/$C4/files/docs/cadence.md" ] && ok "a removed tree is made again on next use" || bad "remake: $out"
out=$(dc "$R2" gc); [[ "$out" == *"nothing to remove"* ]] && ok "gc keeps the tree of the repo it runs from, on the roster or not" || bad "gc self: $out"
rm "$AGENT_CADENCE_REG_DIR/repos.txt"

# bump: the newer tags; a move of the ref line alone, checked first; what the PR body carries
SB="$TMP/srcb"; git init -q -b main "$SB"; mkdir -p "$SB/launcher" "$SB/files/docs"
cp "$DC/launcher/words.py" "$DC/launcher/agent_cadence.py" "$SB/launcher/"; echo 1 > "$SB/launcher/INTERFACE"
printf '# changes\n\n## A — the first\nDo: a.\n' > "$SB/files/docs/cadence-changes.md"
git -C "$SB" add -A && git -C "$SB" commit -qm b1 && git -C "$SB" tag b1; B1=$(git -C "$SB" rev-parse HEAD)
git -C "$SB" checkout -q -b side; echo x > "$SB/x"; git -C "$SB" add x && git -C "$SB" commit -qm side; BX=$(git -C "$SB" rev-parse HEAD)
git -C "$SB" checkout -q main
printf '# changes\n\n## B — the second\nDo: b.\n\n## A — the first\nDo: a.\n' > "$SB/files/docs/cadence-changes.md"
git -C "$SB" commit -qam b2 && git -C "$SB" tag b2; B2=$(git -C "$SB" rev-parse HEAD)
RB="$TMP/bumped"; git init -q -b main "$RB"; mkdir -p "$RB/docs"
printf '# keep this comment\nreview-model = "sonnet"\n\n[agent-cadence]\nsource = "file://%s"   # where\nref = "%s"   # b1\n\n[not-adopted]\n' "$SB" "$B1" > "$RB/docs/cadence.toml"
cp "$RB/docs/cadence.toml" "$TMP/rb.before"
out=$(dc "$RB" bump); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"pinned at $B1; 1 commit(s) on file://$SB main since; newer tags: b2"* ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump alone: the newer tags and commits, nothing written" || bad "bump list: rc=$rc $out"
out=$(dc "$RB" bump b2); rc=$?
d=$(diff "$TMP/rb.before" "$RB/docs/cadence.toml" | grep '^[<>]' | tr '\n' '|')
[ $rc -eq 0 ] && [ "$d" = "< ref = \"$B1\"   # b1|> ref = \"$B2\"   # b2|" ] && ok "bump <tag>: the ref line and its tag comment alone" || bad "bump b2: rc=$rc $out; diff=$d"
[[ "$out" == *"compare: git log $B1..$B2 in file://$SB"* ]] && [[ "$out" == *"- B — the second"* ]] && [[ "$out" != *"- A — the first"* ]] && ok "bump prints the compare and the cadence-changes since the old pin" || bad "bump body: $out"
echo y > "$SB/y"; git -C "$SB" add y && git -C "$SB" commit -qm b3; B3=$(git -C "$SB" rev-parse HEAD)
git -C "$SB" rm -q launcher/INTERFACE && git -C "$SB" commit -qm b4; B4=$(git -C "$SB" rev-parse HEAD)
out=$(dc "$RB" bump "$B3"); rc=$?
[ $rc -eq 0 ] && grep -qx "ref = \"$B3\"" "$RB/docs/cadence.toml" && [[ "$out" == *"cadence-changes since the old pin: none"* ]] && ok "bump <commit>: fetched, no tag comment" || bad "bump B3: rc=$rc $out; $(grep ref "$RB/docs/cadence.toml")"
cp "$RB/docs/cadence.toml" "$TMP/rb.before"
for c in "b1:does not descend from the pin" "$BX:is not on file://$SB's default branch main" "$B4:has no launcher/INTERFACE" "nope:is not a commit or tag"; do
  out=$(dc "$RB" bump "${c%%:*}"); rc=$?
  [ $rc -eq 2 ] && [[ "$out" == *"${c#*:}"* ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump refuses: ${c#*:}" || bad "bump ${c%%:*}: rc=$rc $out"
done
out=$(dc "$RB" bump "$B3"); [[ "$out" == "already pinned at $B3" ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump to the pin: already pinned, nothing written" || bad "bump same: $out"
# the default branch is the source's now, not the cached clone's HEAD from when it was made
git -C "$SB" checkout -q -b dev "$B3"; echo d > "$SB/d"; git -C "$SB" add d && git -C "$SB" commit -qm bd; BD=$(git -C "$SB" rev-parse HEAD)
git -C "$SB" symbolic-ref HEAD refs/heads/dev
out=$(dc "$RB" bump "$BD"); rc=$?
[ $rc -eq 0 ] && grep -qx "ref = \"$BD\"" "$RB/docs/cadence.toml" && ok "bump follows a source whose default branch moved (main -> dev)" || bad "bump new default: rc=$rc $out"
cp "$RB/docs/cadence.toml" "$TMP/rb.before"
echo e > "$SB/e"; git -C "$SB" add e && git -C "$SB" commit -qm be; BE=$(git -C "$SB" rev-parse HEAD)
git -C "$SB" checkout -q main; git -C "$SB" symbolic-ref HEAD refs/heads/main
out=$(dc "$RB" bump "$BE"); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"is not on file://$SB's default branch main"* ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump refuses a commit off the default branch the source names now" || bad "bump old default: rc=$rc $out"
mv "$SB" "$SB.away"
out=$(dc "$RB" bump b2); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"failed"*"nothing is written"* ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump with an unreachable source: refused, nothing written" || bad "bump unreachable: rc=$rc $out"
out=$(dc "$RB" bump 2>&1); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"warning: fetching"*"listing what the cache has"* ]] && [[ "$out" == *"pinned at $BD"* ]] && ok "bump alone with an unreachable source: lists the cache, warned" || bad "bump list unreachable: rc=$rc $out"
mv "$SB.away" "$SB"
chmod -R u+w "$XDG_CACHE_HOME/agent-cadence/sources" && rm -rf "$XDG_CACHE_HOME/agent-cadence/sources"
out=$(dc "$RB" bump); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"pinned at $BD"* ]] && ok "bump makes the source's clone again when the cache lost it" || bad "bump no clone: rc=$rc $out"
# the read-back: an edit that would change anything but ref is never written
printf '[agent-cadence] # the pin\nsource = "file://%s"\n"ref" = "%s"\nnotes = """\nref = "%s"\n"""\n' "$SB" "$BD" "$BD" > "$RB/docs/cadence.toml"; cp "$RB/docs/cadence.toml" "$TMP/rb.before"
git -C "$SB" checkout -q dev; git -C "$SB" symbolic-ref HEAD refs/heads/dev
out=$(dc "$RB" bump "$BE" 2>&1); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"would not read as the same file with the new ref"* ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump reads its edit back: a ref line inside a string is never the pin" || bad "bump read-back: rc=$rc $out"
printf '[agent-cadence]   # the pin\nsource = "file://%s"\nref = "%s"\n' "$SB" "$BD" > "$RB/docs/cadence.toml"
out=$(dc "$RB" bump "$BE"); rc=$?
[ $rc -eq 0 ] && grep -qx "ref = \"$BE\"" "$RB/docs/cadence.toml" && ok "bump: a [agent-cadence] header with a comment" || bad "bump header comment: rc=$rc $out"
printf 'agent-cadence = { source = "file://%s", ref = "%s" }\n' "$SB" "$BD" > "$RB/docs/cadence.toml"; cp "$RB/docs/cadence.toml" "$TMP/rb.before"
out=$(dc "$RB" bump "$BE"); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"by hand"* ]] && cmp -s "$RB/docs/cadence.toml" "$TMP/rb.before" && ok "bump of a pin in a form it does not edit: refused, by hand" || bad "bump inline: rc=$rc $out"

# TD-158: bump refreshes a skill pointer the repo never edited (any version in the new pin's history,
# with or without its synced-file header, as shiftlead's predates its own pin), seeds a missing one,
# keeps an edited one with a WARN, and names each in the body
SP="$TMP/srcp"; git init -q -b main "$SP"; mkdir -p "$SP/launcher" "$SP/files/.claude/skills"
cp "$DC/launcher/words.py" "$DC/launcher/agent_cadence.py" "$SP/launcher/"; echo 1 > "$SP/launcher/INTERFACE"
ptr() {  # ptr <skill> <text>: the canonical pointer, with the header a synced copy carries
  mkdir -p "$SP/files/.claude/skills/$1"
  printf -- '---\nname: %s\ndescription: "%s"\n---\n\n<!-- SYNCED FILE — edit upstream -->\n\nRead the procedure (%s).\n' "$1" "$2" "$2" > "$SP/files/.claude/skills/$1/SKILL.md"
}
for s in attention hdr edited current; do ptr "$s" v1; done
git -C "$SP" add -A && git -C "$SP" commit -qm p1; P1=$(git -C "$SP" rev-parse HEAD)
for s in attention hdr edited current; do ptr "$s" v2; done; git -C "$SP" commit -qam p2; P2=$(git -C "$SP" rev-parse HEAD)
for s in attention hdr edited current; do ptr "$s" v3; done
mkdir -p "$SP/files/.agents/skills/attention"; cp "$SP/files/.claude/skills/attention/SKILL.md" "$SP/files/.agents/skills/attention/"
git -C "$SP" add -A && git -C "$SP" commit -qm p3; P3=$(git -C "$SP" rev-parse HEAD)
RP="$TMP/pointed"; git init -q -b main "$RP"; mkdir -p "$RP/docs" "$RP/.claude/skills"
printf '[agent-cadence]\nsource = "file://%s"\nref = "%s"\n' "$SP" "$P2" > "$RP/docs/cadence.toml"
unhead() { python3 -c 'import re,sys; sys.stdout.write(re.sub(r"\n<!-- SYNCED FILE.*?-->\n\n", "\n", sys.stdin.read(), count=1, flags=re.S))'; }
for s in attention hdr edited current; do mkdir -p "$RP/.claude/skills/$s"; done
git -C "$SP" show "$P1:files/.claude/skills/attention/SKILL.md" | unhead > "$RP/.claude/skills/attention/SKILL.md"   # older than the pin, header gone
git -C "$SP" show "$P1:files/.claude/skills/hdr/SKILL.md" > "$RP/.claude/skills/hdr/SKILL.md"                       # with its header
git -C "$SP" show "$P2:files/.claude/skills/edited/SKILL.md" | unhead > "$RP/.claude/skills/edited/SKILL.md"; echo "a local line" >> "$RP/.claude/skills/edited/SKILL.md"
git -C "$SP" show "$P3:files/.claude/skills/current/SKILL.md" | unhead > "$RP/.claude/skills/current/SKILL.md"
cp "$RP/.claude/skills/edited/SKILL.md" "$TMP/edited.before"
out=$(dc "$RP" bump "$P3"); rc=$?
want=$(git -C "$SP" show "$P3:files/.claude/skills/attention/SKILL.md" | unhead)
[ $rc -eq 0 ] && [ "$(cat "$RP/.claude/skills/attention/SKILL.md")" = "$want" ] \
  && [[ "$out" == *"  refresh .claude/skills/attention/SKILL.md (an unedited copy of ${P1:0:12})"* ]] \
  && ok "bump refreshes an unedited pointer older than the old pin, header stripped" || bad "pointer refresh: rc=$rc $out"
[ "$(cat "$RP/.claude/skills/hdr/SKILL.md")" = "$(git -C "$SP" show "$P3:files/.claude/skills/hdr/SKILL.md" | unhead)" ] \
  && ! grep -q "SYNCED FILE" "$RP/.claude/skills/hdr/SKILL.md" && [[ "$out" == *"refresh .claude/skills/hdr/SKILL.md"* ]] \
  && ok "bump refreshes an unedited pointer that still carries its synced-file header" || bad "pointer hdr: $out"
cmp -s "$RP/.claude/skills/edited/SKILL.md" "$TMP/edited.before" && [[ "$out" == *"warning: .claude/skills/edited/SKILL.md is edited here"* ]] \
  && [[ "$out" == *"- keep \`.claude/skills/edited/SKILL.md\`: edited here"* ]] \
  && ok "bump keeps an edited pointer, warned, and names it in the body" || bad "pointer edited: $out"
[ "$(cat "$RP/.agents/skills/attention/SKILL.md")" = "$want" ] && [[ "$out" == *"- seed \`.agents/skills/attention/SKILL.md\`: missing"* ]] \
  && [[ "$out" == *"- keep \`.claude/skills/current/SKILL.md\`: already the new pin's text"* ]] \
  && ok "bump seeds a pointer new at the pin, keeps a current one; the body names every pointer" || bad "pointer seed: $out"

# a pointer that is a link is never written through; a write that fails leaves the pin where it was
RQ="$TMP/pointed2"; git init -q -b main "$RQ"; mkdir -p "$RQ/docs" "$RQ/.claude/skills/attention"
printf '[agent-cadence]\nsource = "file://%s"\nref = "%s"\n' "$SP" "$P2" > "$RQ/docs/cadence.toml"; cp "$RQ/docs/cadence.toml" "$TMP/rq.before"
git -C "$SP" show "$P1:files/.claude/skills/attention/SKILL.md" | unhead > "$TMP/outside.md"; cp "$TMP/outside.md" "$TMP/outside.before"
ln -s "$TMP/outside.md" "$RQ/.claude/skills/attention/SKILL.md"
echo "not a directory" > "$RQ/.agents"
out=$(dc "$RQ" bump "$P3"); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"cannot write .agents/skills/attention/SKILL.md"*"the pin is not moved"* ]] && cmp -s "$RQ/docs/cadence.toml" "$TMP/rq.before" \
  && ok "bump: a pointer it cannot write stops it before the pin moves" || bad "pointer write fails: rc=$rc $out"
rm "$RQ/.agents"
out=$(dc "$RQ" bump "$P3"); rc=$?
[ $rc -eq 0 ] && cmp -s "$TMP/outside.md" "$TMP/outside.before" && [ -L "$RQ/.claude/skills/attention/SKILL.md" ] \
  && [[ "$out" == *"keep    .claude/skills/attention/SKILL.md (a symlink, or under one: not touched)"* ]] && grep -qx "ref = \"$P3\"" "$RQ/docs/cadence.toml" \
  && ok "bump never writes through a symlinked pointer; run again, it moves the pin" || bad "pointer symlink: rc=$rc $out"

# TD-174: bump runs the NEW pin's bump. H2's words.py says so in its bump; pinned at H1, a bump to H2
# prints it once (the hand-off, and no second one), and moves the pin
SH="$TMP/srch"; git init -q -b main "$SH"; mkdir -p "$SH/launcher" "$SH/files/docs"
cp "$DC/launcher/words.py" "$DC/launcher/agent_cadence.py" "$SH/launcher/"; echo 1 > "$SH/launcher/INTERFACE"
git -C "$SH" add -A && git -C "$SH" commit -qm h1; H1=$(git -C "$SH" rev-parse HEAD)
python3 - "$SH/launcher/words.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("def w_bump(args):\n", "def w_bump(args):\n    print('the bump of h2')\n", 1)
open(p, "w").write(s)
PY
git -C "$SH" commit -qam h2; H2=$(git -C "$SH" rev-parse HEAD)
RH="$TMP/handed"; git init -q -b main "$RH"; mkdir -p "$RH/docs"
printf '[agent-cadence]\nsource = "file://%s"\nref = "%s"\n' "$SH" "$H1" > "$RH/docs/cadence.toml"
out=$(cd "$RH" && timeout 60 python3 "$L" bump "$H2" 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(grep -c '^the bump of h2$' <<< "$out")" = 1 ] && [[ "$out" == *"running ${H2:0:12}'s bump"* ]] \
  && grep -qx "ref = \"$H2\"" "$RH/docs/cadence.toml" && [ -d "$TREES/$H2" ] \
  && ok "bump from an older pin runs the new pin's bump, once (TD-174)" || bad "bump hand-off: rc=$rc $out"
# a tree with no launcher to make the target's tree: bump says the old code runs, and still moves the pin
git -C "$SH" rm -q launcher/agent_cadence.py; git -C "$SH" commit -qm h3; H3=$(git -C "$SH" rev-parse HEAD)
git -C "$SH" commit -q --allow-empty -m h4; H4=$(git -C "$SH" rev-parse HEAD)
printf '[agent-cadence]\nsource = "file://%s"\nref = "%s"\n' "$SH" "$H3" > "$RH/docs/cadence.toml"
out=$(cd "$RH" && timeout 60 python3 "$L" bump "$H4" 2>&1); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"warning: "*"no launcher/agent_cadence.py"*"runs the old pin's code"* ]] && grep -qx "ref = \"$H4\"" "$RH/docs/cadence.toml" \
  && ok "bump from a tree with no launcher copy warns that the old pin's bump runs, and moves the pin" || bad "bump no launcher: rc=$rc $out"
# a target needing a newer launcher than the running tree's copy: refused at the hand-off, nothing written
echo 2 > "$SH/launcher/INTERFACE"; git -C "$SH" commit -qam h5; H5=$(git -C "$SH" rev-parse HEAD)
printf '[agent-cadence]\nsource = "file://%s"\nref = "%s"\n' "$SH" "$H2" > "$RH/docs/cadence.toml"; cp "$RH/docs/cadence.toml" "$TMP/rh.before"
out=$(cd "$RH" && timeout 60 python3 "$L" bump "$H5" 2>&1); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"cannot make ${H5:0:12}'s tree to run its bump"*"interface 2"*"nothing written"* ]] && cmp -s "$RH/docs/cadence.toml" "$TMP/rh.before" \
  && ok "bump to a target needing a newer launcher: refused at the hand-off, nothing written" || bad "bump hand-off interface: rc=$rc $out"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
