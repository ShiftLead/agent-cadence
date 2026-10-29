#!/usr/bin/env bash
# cadence_layer.py — the person's own cadence layers, printed at session start (TD-126,
# cadence §9.18). Offline and fixture-driven: the layers are temp git clones, the setting is a
# machine cadence.toml under DEV_CADENCE_REG_DIR, and HOME/XDG_CONFIG_HOME point into the temp dir.
# Asserts: silent when unset; one's own layer from its working tree, with its commit; a pinned
# layer read at its ref and never fetched; the layers in their order; a layer that cannot be
# read is a warning and exit 0 under --hook; one's own layer fetched and said to be behind or ahead,
# within one bounded budget; the repo's own settings file cannot cost the
# person their layer; the size ceiling; the real runner frames it as the person's rules; and
# rules keyed by § — precedence across two layers, an unknown §, show effective (--effective);
# and the attention report's section for an own layer holding unpushed or uncommitted work.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/cadence_layer.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SHIFTLEAD_SESSION CADENCE_ATTENTION_SCOPE
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
CFG="$DEV_CADENCE_REG_DIR/cadence.toml"
hook() { (cd "$TMP" && python3 "$SCRIPT" --hook 2>"$TMP/err"); }

# 1. no setting: the hook prints nothing; the listing says where the setting goes
out=$(hook); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "1 no layers set: the hook is silent, exit 0" || bad "1 rc=$rc '$out'"
out=$(python3 "$SCRIPT"); rc=$?
[ "$rc" = 0 ] && grep -qF "no layers set (the layers key in $CFG" <<< "$out" && ok "1b the listing names the file the setting goes in" || bad "1b rc=$rc '$out'"
printf 'review-model = "haiku"\n' > "$CFG"
[ -z "$(hook)" ] && ok "1c a machine file without layers: silent" || bad "1c '$(hook)'"

# fixtures: one's own layer (under ~), and someone else's with a pin, an origin ahead of the clone
mkdir -p "$HOME/src"
OWN="$HOME/src/mine"; git init -q -b main "$OWN"
printf '# my rules\n§4.8 override: review with the cheapest model\n' > "$OWN/cadence-personal.md"
git -C "$OWN" add -A && git -C "$OWN" commit -qm one
OWN_SHA=$(git -C "$OWN" rev-parse --short HEAD)
UP="$TMP/alice-origin"; git init -q -b main "$UP"
mkdir -p "$UP/rules"; echo "alice v1: §2.4 add: rank by hand" > "$UP/rules/layer.md"
git -C "$UP" add -A && git -C "$UP" commit -qm v1 && git -C "$UP" tag v1
git clone -q "$UP" "$TMP/alice"
V1_SHA=$(git -C "$TMP/alice" rev-parse --short v1)
echo "alice v2: §2.4 override: never rank" > "$TMP/alice/rules/layer.md"
git -C "$TMP/alice" commit -qam "v2, local"
echo "alice v3 upstream" > "$UP/rules/layer.md"; git -C "$UP" commit -qam v3
cat > "$CFG" <<EOF
[[layers]]
path = "$TMP/alice/rules/layer.md"
ref = "v1"
[[layers]]
path = "~/src/mine/cadence-personal.md"
EOF

# 2. both layers, in the setting's order, each with its commit; the pinned one at its ref
before=$(git -C "$TMP/alice" for-each-ref --format='%(objectname)' refs/remotes)
out=$(hook); rc=$?
first=$(grep -n '^--- layer 1 of 2: ' <<< "$out" | cut -d: -f1); second=$(grep -n '^--- layer 2 of 2: ' <<< "$out" | cut -d: -f1)
[ "$rc" = 0 ] && grep -q '^The person.s own cadence rules: 2 layers .*a later one wins over an earlier one), then cadence.md' <<< "$out" \
  && [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ] \
  && ok "2 two layers, in the setting's order, under the precedence line" || bad "2 rc=$rc
$out"
grep -qxF -- "--- layer 1 of 2: $TMP/alice/rules/layer.md @ $V1_SHA (pinned v1)" <<< "$out" \
  && grep -qx 'alice v1: §2.4 add: rank by hand' <<< "$out" && ! grep -q 'alice v[23]' <<< "$out" \
  && ok "2b a pinned layer is read at its ref — not the clone's working tree, not origin's tip" || bad "2b
$out"
[ "$before" = "$(git -C "$TMP/alice" for-each-ref --format='%(objectname)' refs/remotes)" ] && [ ! -e "$TMP/alice/.git/FETCH_HEAD" ] \
  && ok "2c the hook never fetches the pinned clone" || bad "2c the clone's remote refs moved"
grep -qxF -- "--- layer 2 of 2: ~/src/mine/cadence-personal.md @ $OWN_SHA (own)" <<< "$out" \
  && grep -qx '§4.8 override: review with the cheapest model' <<< "$out" && grep -qx -- '--- end of layer 2' <<< "$out" \
  && ok "2d one's own layer, ~ expanded, from its working tree, with its HEAD" || bad "2d
$out"
echo "§1.1 add: an uncommitted thought" >> "$OWN/cadence-personal.md"
out=$(hook)
grep -qxF -- "--- layer 2 of 2: ~/src/mine/cadence-personal.md @ $OWN_SHA (own, with uncommitted edits)" <<< "$out" \
  && grep -qx '§1.1 add: an uncommitted thought' <<< "$out" \
  && ok "2e an uncommitted edit to one's own layer is read, and said" || bad "2e
$out"
git -C "$OWN" commit -qam two
out=$(python3 "$SCRIPT"); rc=$?
[ "$rc" = 0 ] && grep -qF "1. $TMP/alice/rules/layer.md @ $V1_SHA (pinned v1) — read" <<< "$out" \
  && grep -qF "2. ~/src/mine/cadence-personal.md @ $(git -C "$OWN" rev-parse --short HEAD) (own) — read" <<< "$out" \
  && ok "2f the listing names each layer, its commit, and read" || bad "2f rc=$rc
$out"

# 3. a layer that cannot be read: a warning line, the others still read; exit 0 under --hook, 1 listed
cat > "$CFG" <<EOF
[[layers]]
path = "$TMP/alice/rules/layer.md"
ref = "v9"
[[layers]]
path = "$TMP/nowhere/cadence-personal.md"
[[layers]]
path = "~/src/mine/cadence-personal.md"
EOF
out=$(hook); rc=$?
[ "$rc" = 0 ] && grep -qF -- "--- layer 1 of 3: $TMP/alice/rules/layer.md (pinned v9) — not read: ref v9 is not in the clone (a pinned layer is never fetched" <<< "$out" \
  && grep -qF -- "--- layer 2 of 3: $TMP/nowhere/cadence-personal.md (own) — not read: not found; this session runs without it" <<< "$out" \
  && grep -qx '§4.8 override: review with the cheapest model' <<< "$out" \
  && ok "3 a missing ref and a missing file are warnings; the layer after them is still read; exit 0" || bad "3 rc=$rc
$out"
python3 "$SCRIPT" >/dev/null; rc=$?
[ "$rc" = 1 ] && ok "3b the listing exits 1 when a layer could not be read" || bad "3b rc=$rc"
mkdir -p "$TMP/loose"; echo "§3 add: loose" > "$TMP/loose/p.md"
printf '[[layers]]\npath = "%s"\n[[layers]]\npath = "%s"\nref = "v1"\n' "$TMP/loose/p.md" "$TMP/loose/p.md" > "$CFG"
out=$(hook)
grep -qxF -- "--- layer 1 of 2: $TMP/loose/p.md (own, not in a git clone: it is on this machine alone)" <<< "$out" && grep -qx '§3 add: loose' <<< "$out" \
  && grep -qF -- "--- layer 2 of 2: $TMP/loose/p.md (pinned v1) — not read: not in a git clone" <<< "$out" \
  && ok "3c a file outside git: one's own is read with a note; a pinned one cannot be" || bad "3c
$out"
printf '[[layers]]\npath = "%s"\nref = "v1"\n' "$TMP/alice/nofile.md" > "$CFG"
out=$(hook)
grep -qF -- "(pinned v1) — not read: no nofile.md at v1" <<< "$out" && ok "3d a pinned path the ref does not hold: said" || bad "3d
$out"

printf '\xff\xfe bytes that are not UTF-8\n' > "$TMP/alice/rules/raw.md"; git -C "$TMP/alice" add rules/raw.md; git -C "$TMP/alice" commit -qm raw
printf '[[layers]]\npath = "%s"\nref = "HEAD"\n[[layers]]\npath = "%s"\nref = "HEAD"\n[[layers]]\npath = "~/src/mine/cadence-personal.md"\n' \
  "$TMP/alice/rules/raw.md" "$TMP/alice/rules/" > "$CFG"
out=$(hook); rc=$?
[ "$rc" = 0 ] && grep -q 'bytes that are not UTF-8' <<< "$out" && grep -qF -- "--- layer 2 of 3: $TMP/alice/rules/ (pinned HEAD) — not read: not a file" <<< "$out" \
  && grep -qx '§4.8 override: review with the cheapest model' <<< "$out" \
  && ok "3e a pinned layer that is not UTF-8 is read, a path ending in / is not a file, and the next layer still reads" || bad "3e rc=$rc
$out $(cat "$TMP/err")"
echo "§5 add: new" > "$OWN/new.md"
printf '[[layers]]\npath = "~/src/mine/new.md"\n' > "$CFG"
out=$(hook)
grep -qxF -- "--- layer 1 of 1: ~/src/mine/new.md (own, not committed: it is on this machine alone)" <<< "$out" \
  && ok "3f an own layer git has never seen is said to be uncommitted, with no commit named" || bad "3f
$out"
rm -f "$OWN/new.md"

# 4. the setting itself cannot be read: one warning line, exit 0; the listing exits 2
echo 'layers = [' > "$CFG"
out=$(hook); rc=$?
[ "$rc" = 0 ] && grep -q "^cadence layers: not read — $CFG: .*this session runs without them$" <<< "$out" \
  && ok "4 an unreadable machine file: one warning line, exit 0" || bad "4 rc=$rc '$out'"
python3 "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "4b the listing exits 2 on an unreadable machine file" || bad "4b rc=$rc"
echo 'layers = [{path = "relative.md"}]' > "$CFG"
out=$(hook)
grep -q "^cadence layers: not read — .*layers entry 1: path must be absolute or start with ~/" <<< "$out" \
  && ok "4c a malformed layers value is named, not guessed at" || bad "4c '$out'"

# 5. the repo's own settings file, broken, does not cost the person their layer
printf '[[layers]]\npath = "~/src/mine/cadence-personal.md"\n' > "$CFG"
R="$TMP/repo"; mkdir -p "$R/docs"; git init -q -b main "$R"; echo 'precheck = [' > "$R/docs/cadence.toml"
out=$(cd "$R" && python3 "$SCRIPT" --hook)
grep -qx '§4.8 override: review with the cheapest model' <<< "$out" && ok "5 a repo's unreadable docs/cadence.toml: the layer is still read" || bad "5 '$out'"

# 6. the ceiling: a layer past MAX_BYTES is cut, and the cut is said
python3 -c 'print("§9 add: " + "x" * 70000)' > "$OWN/cadence-personal.md"
out=$(hook)
n=$(wc -c <<< "$out")
grep -qx -- '--- layer 1 cut at 64 KiB: read the rest from the file itself' <<< "$out" && [ "$n" -lt 67000 ] \
  && ok "6 a layer past 64 KiB is cut, and says so (${n} bytes printed)" || bad "6 ${n} bytes"
git -C "$OWN" checkout -q -- cadence-personal.md

# 7. the real runner: the layer's frame names it the person's rules, not data
D="$TMP/consumer"; mkdir -p "$D/scripts"; git init -q -b main "$D"
cp "$DC/files/scripts/cadence_hooks.sh" "$SCRIPT" "$DC/files/scripts/cadence_config.py" "$D/scripts/"
out=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" "$D/scripts/cadence_hooks.sh" --session-start </dev/null 2>/dev/null)
grep -A1 -x "\[cadence hook cadence_layer.py — the person's own cadence rules, from the layers their machine's cadence.toml names (cadence.md §9.18)\]" <<< "$out" \
  | tail -1 | grep -q "^The person.s own cadence rules: 1 layer named" \
  && ok "7 the runner prints the layer under its own frame" || bad "7
$out"
rm -f "$CFG"
out=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" "$D/scripts/cadence_hooks.sh" --session-start </dev/null 2>/dev/null)
! grep -q 'cadence_layer' <<< "$out" && ok "7b no layers set: no frame at all" || bad "7b
$out"

# 8. one's own layer against its upstream (TD-126 (3)): fetched, bounded, never pulled
git init -q --bare -b main "$TMP/layer-origin.git"
git clone -q "$TMP/layer-origin.git" "$TMP/l1" 2>/dev/null
echo "§4 add: v1" > "$TMP/l1/p.md"; git -C "$TMP/l1" add -A; git -C "$TMP/l1" commit -qm v1; git -C "$TMP/l1" push -q origin HEAD:main 2>/dev/null
git -C "$TMP/l1" branch -q --set-upstream-to=origin/main
git clone -q "$TMP/layer-origin.git" "$TMP/l2" 2>/dev/null
printf '[[layers]]\npath = "%s"\n' "$TMP/l1/p.md" > "$CFG"
out=$(hook)
! grep -q -- '^--- layer 1: ' <<< "$out" && grep -qx '§4 add: v1' <<< "$out" && ok "8 level with its upstream: nothing said" || bad "8
$out"
echo "§4 add: v2" > "$TMP/l2/p.md"; git -C "$TMP/l2" commit -qam v2; git -C "$TMP/l2" push -q origin HEAD:main 2>/dev/null
out=$(hook)
grep -qx -- '--- layer 1: 1 commit behind origin/main — pull it: this session reads the older rules' <<< "$out" && grep -qx '§4 add: v1' <<< "$out" \
  && [ "$(git -C "$TMP/l1" rev-parse origin/main)" = "$(git -C "$TMP/l2" rev-parse HEAD)" ] && [ "$(cat "$TMP/l1/p.md")" = "§4 add: v1" ] \
  && ok "8b origin moved: fetched, said to be behind, and the working tree never pulled" || bad "8b
$out"
git -C "$TMP/l1" pull -q 2>/dev/null; echo "§4 add: v3" > "$TMP/l1/p.md"; git -C "$TMP/l1" commit -qam v3
out=$(python3 "$SCRIPT")
grep -qF "1. $TMP/l1/p.md @ $(git -C "$TMP/l1" rev-parse --short HEAD) (own) — read; 1 commit not pushed to origin/main — push it: your other machines do not have them" <<< "$out" \
  && ok "8c an unpushed commit is said, in the listing too" || bad "8c
$out"
printf '[[layers]]\npath = "~/src/mine/cadence-personal.md"\n' > "$CFG"
hook | grep -qx -- '--- layer 1: its branch has no upstream: an edit here reaches no other machine' \
  && ok "8d a clone with no upstream is said to reach no other machine" || bad "8d $(hook)"
git -C "$TMP/l1" remote set-url origin "$TMP/gone.git"
printf '[[layers]]\npath = "%s"\n' "$TMP/l1/p.md" > "$CFG"
out=$(hook); rc=$?
[ "$rc" = 0 ] && grep -q -- "^--- layer 1: 1 commit not pushed to origin/main — push it: your other machines do not have them; as of the last fetch (the fetch failed: " <<< "$out" \
  && grep -qx '§4 add: v3' <<< "$out" && ok "8e a remote that is gone: the last fetch's counts, said to be stale; the layer still read" || bad "8e rc=$rc
$out"
# a remote that hangs: an ssh on PATH that never answers; the fetches share one budget under the 10 s bound
mkdir -p "$TMP/hang"; printf '#!/bin/sh\nexec sleep 30\n' > "$TMP/hang/ssh"; chmod +x "$TMP/hang/ssh"
git -C "$TMP/l1" remote set-url origin "ssh://nowhere.invalid/layer.git"
git clone -q "$TMP/layer-origin.git" "$TMP/l3" 2>/dev/null; git -C "$TMP/l3" remote set-url origin "ssh://nowhere.invalid/layer.git"
printf '[[layers]]\npath = "%s"\n[[layers]]\npath = "%s"\n' "$TMP/l1/p.md" "$TMP/l3/p.md" > "$CFG"
start=$(date +%s); out=$(PATH="$TMP/hang:$PATH" hook); rc=$?; took=$(( $(date +%s) - start ))
[ "$rc" = 0 ] && [ "$took" -lt 10 ] && grep -q -- '^--- layer 1: .*(the fetch was stopped after 4s)$' <<< "$out" \
  && grep -q -- '^--- layer 2: level with origin/main as of the last fetch (the fetch was stopped after [0-9]s)$' <<< "$out" \
  && grep -qx '§4 add: v3' <<< "$out" && grep -qx '§4 add: v2' <<< "$out" \
  && ok "8f a hanging remote: each fetch stopped, the two within one budget (${took}s < the runner's 10 s), both layers read" || bad "8f rc=$rc took=${took}s
$out"

# 8g. the upstream as git config names it: a remote whose name has a /, tags left alone,
# a local-branch upstream and a detached HEAD each said for what they are
git clone -q -o my/rem "$TMP/layer-origin.git" "$TMP/l4" 2>/dev/null
git -C "$TMP/l2" commit -q --allow-empty -m v4; git -C "$TMP/l2" push -q origin HEAD:main 2>/dev/null
git -C "$TMP/l2" tag v8; git -C "$TMP/l2" push -q origin v8 2>/dev/null
printf '[[layers]]\npath = "%s"\n' "$TMP/l4/p.md" > "$CFG"
out=$(hook)
grep -qx -- '--- layer 1: 1 commit behind my/rem/main — pull it: this session reads the older rules' <<< "$out" \
  && [ -z "$(git -C "$TMP/l4" tag -l v8)" ] \
  && ok "8g a remote named my/rem is fetched by its name, and no tag is imported" || bad "8g tags=$(git -C "$TMP/l4" tag -l)
$out"
git -C "$TMP/l4" checkout -q -b side; git -C "$TMP/l4" branch -q --set-upstream-to=main
out=$(hook)
grep -qx -- '--- layer 1: its upstream is the local branch main: an edit here reaches no other machine' <<< "$out" \
  && ok "8h a local-branch upstream is said to be one" || bad "8h
$out"
git -C "$TMP/l4" checkout -q --detach
out=$(hook)
grep -qx -- '--- layer 1: a detached HEAD: not compared with any upstream' <<< "$out" && grep -q '§4 add' <<< "$out" \
  && ok "8i a detached HEAD is said, and the layer still read" || bad "8i
$out"

# 9. --publish-check (TD-126 (5)): every tracked file of one's own layer's repo, line by line
P="$HOME/src/pub"; git init -q -b main "$P"
cat > "$P/cadence-personal.md" <<'L'
# rules
§4.8 override: review with the cheapest model
§1.1 add: keep the anchor in /home/jdoe/dev/acme-secret, ask alex@acme-mail.io first
L
printf 'judged: secret-svc memory 3\n' > "$P/memory-harvest.md"
git -C "$P" add -A && git -C "$P" commit -qm one
echo "$TMP/elsewhere/secret-svc" > "$DEV_CADENCE_REG_DIR/repos.txt"
printf '[[layers]]\npath = "%s"\nref = "v1"\n[[layers]]\npath = "~/src/pub/cadence-personal.md"\n' "$TMP/alice/rules/layer.md" > "$CFG"
out=$(python3 "$SCRIPT" --publish-check); rc=$?
[ "$rc" = 1 ] && grep -qF "$P/cadence-personal.md:3: an email address (alex@acme-mail.io)" <<< "$out" \
  && grep -qF "$P/cadence-personal.md:3: a machine path (/home/jdoe)" <<< "$out" \
  && grep -qF "$P/memory-harvest.md:1: a repo on this machine's roster (secret-svc)" <<< "$out" \
  && ! grep -q "alice" <<< "$out" && ! grep -q 'cadence-personal.md:[12]: ' <<< "$out" \
  && ok "9 the publish check names each line, in every tracked file, and skips a layer one does not own" || bad "9 rc=$rc
$out"
echo "§2 add: notes in $HOME/notes" > "$P/cadence-personal.md"
out=$(python3 "$SCRIPT" --publish-check "$P/cadence-personal.md"); rc=$?
[ "$rc" = 1 ] && grep -qF "this machine's home directory ($HOME)" <<< "$out" && ! grep -q memory-harvest <<< "$out" \
  && ok "9b a named file alone; this machine's home directory is named" || bad "9b rc=$rc
$out"
printf '# rules\n§4.8 override: review with the cheapest model\n' > "$P/cadence-personal.md"; git -C "$P" rm -q memory-harvest.md
out=$(python3 "$SCRIPT" --publish-check); rc=$?
[ "$rc" = 0 ] && grep -q '^0 lines to look at in 1 file — the current tree only: git history goes public too, and is not read$' <<< "$out" && ok "9c a clean layer: exit 0" || bad "9c rc=$rc
$out"
out=$(python3 "$SCRIPT" --publish-check "$P/cadence-personal.md" "$P/typo.md"); rc=$?
[ "$rc" = 2 ] && grep -qF "note: $P/typo.md: not read (No such file or directory) — not checked" <<< "$out" && grep -q '^0 lines to look at in 1 file (1 not read)' <<< "$out" \
  && ok "9e a file that cannot be read is said, and nothing found with it unread is exit 2, never clean" || bad "9e rc=$rc
$out"
# 9f (TD-090): the machine's publish-names and short name are flagged; fixtures and the tool's name are not
HOST=$(python3 -c 'import socket; print(socket.gethostname().split(".")[0])'); SHORT=${HOST%%-*}
printf 'publish-names = ["Jordan", "acme-corp"]\n[[layers]]\npath = "~/src/pub/cadence-personal.md"\n' > "$CFG"
echo "$TMP/elsewhere/dev-cadence" >> "$DEV_CADENCE_REG_DIR/repos.txt"
cat > "$P/notes.md" <<L
ask Jordan before acme-corp's release
see someone@example.com, a@b.test, /home/someone/x, /Users/alice/y, C:\\Users\\<user>\\z, /home/\$USER/w
dev-cadence and agent-cadence are the tool
the box: $SHORT
L
out=$(python3 "$SCRIPT" --publish-check "$P/notes.md"); rc=$?
[ "$rc" = 1 ] && grep -qF "notes.md:1: a name your publish-names lists (Jordan)" <<< "$out" \
  && grep -qF "notes.md:1: a name your publish-names lists (acme-corp)" <<< "$out" \
  && ! grep -q "notes.md:[23]:" <<< "$out" \
  && { [ "$SHORT" = "$HOST" ] || [ ${#SHORT} -lt 3 ] || grep -qF "notes.md:4: this machine's short name ($SHORT)" <<< "$out"; } \
  && ok "9f publish-names and the short host name flagged; reserved emails, placeholder homes and the tool's name are not" || bad "9f rc=$rc
$out"
printf 'publish-names = "Jordan"\n' > "$CFG"
out=$(python3 "$SCRIPT" --publish-check "$P/notes.md" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "publish-names.*must be an array of non-empty strings" <<< "$out" && ok "9g a publish-names that is not a list of strings: exit 2, said" || bad "9g rc=$rc
$out"
printf 'publish-names = ["dev-cadence"]\n' > "$CFG"
printf 'mail x@example.com.evil.io, y@notexample.com\nkeys in /home/user/.ssh\n' > "$P/near.md"
out=$(HOME=/home/user python3 "$SCRIPT" --publish-check "$P/near.md" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "near.md:1: an email address (x@example.com.evil.io)" <<< "$out" && grep -qF "near.md:1: an email address (y@notexample.com)" <<< "$out" \
  && grep -qF "near.md:2: a machine path (/home/user)" <<< "$out" && grep -q "note: publish-names lists dev-cadence, the tool's own name" <<< "$out" \
  && ok "9h a lookalike of a reserved domain is flagged; a stand-in home that is this machine's own is flagged; a tool name listed is said" || bad "9h rc=$rc
$out"
rm -f "$CFG"; python3 "$SCRIPT" --publish-check >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "9d nothing set and nothing named: exit 2" || bad "9d rc=$rc"

# 9i (TD-189): --accept makes it a gate — an accept line drops a finding (its third field matched
# against the line's own text), an unused line is named, a dead relative link is a finding, and the
# run ends with the gate's line
G="$TMP/gate"; mkdir -p "$G/docs/docs"; git init -q -b main "$G"; : > "$G/docs/docs/here.md"
printf 'publish-names = ["Jordan"]\n' > "$CFG"
printf '**Blocked by:** decision (Jordan)\nJordan wrote this\nsee [x](missing.md) and [y](docs/here.md)\n' > "$G/docs/e.md";
printf '# the hold marker only\ndocs/*.md a name your publish-names lists (Jordan) :: *decision (Jordan)*\nnowhere/* *\n' > "$G/accept.txt"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept accept.txt docs/e.md docs/docs/here.md); rc=$?
[ "$rc" = 1 ] && ! grep -q "docs/e.md:1:" <<< "$out" && grep -qxF "docs/e.md:2: a name your publish-names lists (Jordan)" <<< "$out" \
  && grep -qxF "docs/e.md:3: a link to a file the tree lacks (missing.md)" <<< "$out" && ! grep -q "docs/here.md" <<< "$out" \
  && grep -qF "accept line 3 (nowhere/* *) matched nothing" <<< "$out" && grep -qx "gate: 2 findings to judge, 1 accepted" <<< "$out" \
  && ok "9i --accept: the line-text field accepts the hold marker alone; a dead link is a finding; an unused line is named" || bad "9i rc=$rc
$out"
printf 'docs/*.md a name your publish-names lists (Jordan)\ndocs/*.md a link to a file the tree lacks (*)\n' > "$G/accept.txt"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept accept.txt docs/e.md docs/docs/here.md); rc=$?
[ "$rc" = 0 ] && grep -qx "gate: 0 findings to judge, 3 accepted — clean" <<< "$out" \
  && ok "9j --accept: every finding accepted is exit 0, clean" || bad "9j rc=$rc
$out"
# a `#` inside a glob is the glob's, never a comment that cuts the rule wider; an absolute path is
# matched as the path from where the check runs; a link to a file on disk but not named is dead
printf 'docs/*.md * :: *#*\n' > "$G/accept.txt"; printf 'Jordan #1\n' > "$G/docs/f.md"; : > "$G/docs/untracked.md"
printf 'Jordan\nsee [u](untracked.md), not `](example.md)` or ``a `](x.md)` b``\n' > "$G/docs/g.md"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept accept.txt "$G/docs/f.md" docs/g.md); rc=$?
[ "$rc" = 1 ] && ! grep -q "f.md:1:" <<< "$out" && grep -qxF "docs/g.md:1: a name your publish-names lists (Jordan)" <<< "$out" \
  && grep -qxF "docs/g.md:2: a link to a file the tree lacks (untracked.md)" <<< "$out" && ! grep -q "example.md\|x.md" <<< "$out" \
  && ok "9j2 a # in a line glob stays the glob's; a link in a code span is an example, no link; an absolute path matches a relative glob; an unnamed file is no link target" || bad "9j2 rc=$rc
$out"
printf 'docs/*.md * ::   # cut\n' > "$G/accept.txt"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept accept.txt docs/g.md 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "with no line glob" <<< "$out" && ok "9j3 a :: with no line glob is refused, never read as no third field" || bad "9j3 rc=$rc
$out"
printf 'docs/*.md a name your publish-names lists (Jordan)\ndocs/*.md a link to a file the tree lacks (*)\n' > "$G/accept.txt"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept nope.txt docs/e.md 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "the accept list nope.txt cannot be read" <<< "$out" && ok "9k an accept list that cannot be read: exit 2" || bad "9k rc=$rc
$out"
# the repo key: a public repo's gate refuses to run on a machine that has no names to flag
printf 'publish-gate = "required"\n' > "$G/docs/cadence.toml"; rm -f "$CFG"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept accept.txt docs/e.md 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'publish-gate = "required", and this machine has no publish-names' <<< "$out" \
  && ok "9l publish-gate required with no publish-names: exit 2, said" || bad "9l rc=$rc
$out"
printf 'publish-names = ["Jordan"]\n' > "$CFG"; printf 'docs/*.md a name your publish-names lists (Jordan)\n' > "$G/accept.txt"
out=$(cd "$G" && python3 "$SCRIPT" --publish-check --accept accept.txt docs/e.md docs/g.md 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qxF "docs/g.md:2: a link to a file the tree lacks (untracked.md)" <<< "$out" && ok "9m publish-gate required, publish-names set: the gate runs and still finds" || bad "9m rc=$rc
$out"
rm -f "$CFG"

# 10. rules keyed by § (TD-126 (4a)/(4b)): precedence across two layers, found mechanically
K="$TMP/keys"; mkdir -p "$K/a" "$K/b"; git init -q -b main "$K/b"
cat > "$K/a/l.md" <<'EOF2'
# a's rules
- §2.4 add: rank by hand
- **§4.8 override:** review with haiku
- §1.1 add: stays

an unkeyed paragraph
that runs on
<!-- §7.2 override: commented out
-->
EOF2
cat > "$K/b/l.md" <<'EOF2'
§4 override: the whole review loop is mine

§2.4 override: never rank
§9.99 add: names nothing
```
§1.1 override: inside a fence, not a rule
```
§3.3 override: one
§3.3 override: two
EOF2
git -C "$K/b" add -A && git -C "$K/b" commit -qm k && KB=$(git -C "$K/b" rev-parse --short HEAD)
git init -q --bare "$K/up.git" && git -C "$K/b" remote add origin "$K/up.git" && git -C "$K/b" push -qu origin main 2>/dev/null
printf '[[layers]]\npath = "%s"\n[[layers]]\npath = "%s"\n' "$K/a/l.md" "$K/b/l.md" > "$CFG"
out=$(python3 "$SCRIPT" --effective); rc=$?
[ "$rc" = 1 ] && grep -qxF "layer 2: $K/b/l.md @ $KB (own)" <<< "$out" \
  && grep -qxF '  layer 1 line 2 add: rank by hand — superseded by layer 2'"'"'s §2.4 override (line 3)' <<< "$out" \
  && grep -qxF '  layer 2 line 3 override: never rank — holds' <<< "$out" \
  && ok "10 a later layer's override supersedes an earlier layer's rule for that §, with layer, commit and line" || bad "10 rc=$rc
$out"
grep -qxF '  layer 1 line 3 override: review with haiku — superseded by layer 2'"'"'s §4 override (line 1)' <<< "$out" \
  && grep -qxF '  layer 1 line 4 add: stays — holds' <<< "$out" \
  && ok "10b an override of §4 supersedes §4.8 beneath it, and leaves §1.1 alone" || bad "10b
$out"
grep -qxF 'warning: layer 2 line 4: §9.99 names no rule in cadence.md, so what it changes is unknown' <<< "$out" \
  && grep -qF 'warning: layer 2 overrides §3.3 at line 8 and again at line 9' <<< "$out" \
  && ok "10c a § cadence.md lacks, and one layer overriding a § twice, are warnings (exit 1)" || bad "10c
$out"
grep -qxF 'unkeyed (1): layer 1 line 6 — they hold beside cadence.md, but no tool can say what they change' <<< "$out" \
  && ! grep -q 'inside a fence\|§7.2' <<< "$out" \
  && ok "10d a paragraph is one unkeyed rule; a fence and an HTML comment are no rules" || bad "10d
$out"
[ ! -e "$K/b/.git/FETCH_HEAD" ] && ok "10e --effective never fetches" || bad "10e it fetched"
out=$(hook); rc=$?
[ "$rc" = 0 ] && grep -qF -- "--- the layers' rules by § (cadence_layer.py --effective shows each): §1.1: layer 1 adds; §2.4: layer 2 overrides (superseded: layer 1's add by layer 2's §2.4 override (line 3))" <<< "$out" \
  && grep -qF '§4.8: nothing holds (superseded: layer 1'"'"'s override by layer 2'"'"'s §4 override (line 1))' <<< "$out" \
  && grep -qF '; 1 unkeyed rule beside cadence.md' <<< "$out" && grep -qxF -- '--- warning: layer 2 line 4: §9.99 names no rule in cadence.md, so what it changes is unknown' <<< "$out" \
  && ok "10f the hook ends with the by-§ view and its warnings, exit 0" || bad "10f rc=$rc
$out"
printf '[[layers]]\npath = "%s"\n' "$K/a/l.md" > "$CFG"
cat > "$K/a/l.md" <<'EOF2'
````
~~~
§4.2 override: inside the four-backtick fence
```
§4.3 override: still inside
````
**§4.7** OVERRIDE: bold key, the verb outside it
§4.1 override: one
§4.10 add: not beneath §4.1
§4 override: covers §4.1
~~~
§4.4 override: inside a tilde fence
~~~
EOF2
out=$(python3 "$SCRIPT" --effective); rc=$?
[ "$rc" = 0 ] && ! grep -q 'inside\|warning' <<< "$out" \
  && grep -qxF '  layer 1 line 7 override: bold key, the verb outside it — superseded by layer 1'"'"'s §4 override (line 10)' <<< "$out" \
  && grep -qxF '  layer 1 line 9 add: not beneath §4.1 — superseded by layer 1'"'"'s §4 override (line 10)' <<< "$out" \
  && grep -qxF '  layer 1 line 8 override: one — superseded by layer 1'"'"'s §4 override (line 10)' <<< "$out" \
  && ok "10i fences close on their own marker; **§N** override: is a key; a §4 override over §4.1 is no double override" || bad "10i rc=$rc
$out"
printf '§4.1 override: a\n§4.10 add: b\n' > "$K/a/l.md"
out=$(python3 "$SCRIPT" --effective)
grep -qxF '  layer 1 line 2 add: b — holds' <<< "$out" && ok "10j an override of §4.1 leaves §4.10 alone" || bad "10j
$out"
{ printf '§%s add: a key too long to be one\n' "$(printf '9%.0s' $(seq 5000))"; printf '§4 override'; printf ' %.0s' $(seq 60000); printf 'x\n'; } > "$K/a/l.md"
start=$(date +%s); out=$(hook); rc=$?; took=$(( $(date +%s) - start ))
[ "$rc" = 0 ] && [ "$took" -le 3 ] && ! grep -q Traceback "$TMP/err" && ok "10k a 5000-digit key and a line of 60000 spaces: the hook exits 0, quickly (${took}s)" || bad "10k rc=$rc took=${took}s $(cat "$TMP/err")"
{ for n in $(seq 1 8); do echo "§9$n.1 add: unknown $n"; done; for n in $(seq 1 40); do echo "§99.$n add: x"; done; } > "$K/a/l.md"
out=$(hook)
grep -qE '^--- the layers.* §99\.22: layer 1 adds; 18 more §s \(--effective lists them\)$' <<< "$out" \
  && ok "10m the hook's by-§ line names at most 30 §s" || bad "10m
$out"
[ "$(grep -c '^--- warning: ' <<< "$out")" = 5 ] && grep -qxF -- '--- and 43 more warnings: cadence_layer.py --effective lists them' <<< "$out" \
  && ok "10l the hook prints at most five warnings, and says how many more" || bad "10l
$out"
printf '§4.8 add: fine\n' > "$K/b/l.md"; printf '[[layers]]\npath = "%s"\n' "$K/b/l.md" > "$CFG"
out=$(python3 "$SCRIPT" --effective); rc=$?
[ "$rc" = 0 ] && ! grep -q '^warning' <<< "$out" && ok "10g one valid add: exit 0" || bad "10g rc=$rc
$out"
printf 'just prose\n' > "$K/b/l.md"
[ -z "$(hook | grep "rules by §")" ] && ok "10h a layer with no keyed rule: no by-§ line at session start" || bad "10h"

# 11. the attention report (TD-126 (3)): an own layer's clone with work no other machine has is
# a section of --report, read from the setting — the roster is never written and a pin never named
NUA="$DC/files/scripts/nudge_user_attention.py"
A="$TMP/att"; git init -q --bare "$A/up.git"; git clone -q "$A/up.git" "$A/mine" 2>/dev/null
echo "§4 add: x" > "$A/mine/p.md"; git -C "$A/mine" add -A; git -C "$A/mine" commit -qm one; git -C "$A/mine" push -qu origin HEAD:main 2>/dev/null
git -C "$A/mine" branch -q --set-upstream-to=origin/main 2>/dev/null
printf '[[layers]]\npath = "%s"\nref = "HEAD"\n[[layers]]\npath = "%s"\n' "$A/mine/p.md" "$A/mine/p.md" > "$CFG"
rm -f "$DEV_CADENCE_REG_DIR/repos.txt"
out=$(cd "$TMP" && python3 "$NUA" --report 2>&1); rc=$?
[ "$rc" = 0 ] && ! grep -q 'cadence layers' <<< "$out" && ok "11 a level own layer: no layers section" || bad "11 rc=$rc
$out"
echo "§4 add: y" >> "$A/mine/p.md"; git -C "$A/mine" commit -qam two
out=$(cd "$TMP" && python3 "$NUA" --report 2>&1)
grep -qF "== your cadence layers (the machine's cadence.toml, cadence.md §9.18 — not on the roster)" <<< "$out" \
  && grep -qE "^  • layer 2: $A/mine/p.md @ [0-9a-f]+ \(own\) — 1 commit not pushed to origin/main — push it" <<< "$out" \
  && ! grep -q '• layer 1' <<< "$out" && [ ! -e "$DEV_CADENCE_REG_DIR/repos.txt" ] \
  && ok "11b an unpushed commit in one's own layer is in the report; the pinned one is not; the roster is untouched" || bad "11b
$out"
echo "draft" >> "$A/mine/p.md"
out=$(cd "$TMP" && python3 "$NUA" --report --json 2>&1)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); l=d["layers"]; assert len(l)==1 and "with uncommitted edits" in l[0] and "not pushed" in l[0], l' "$out" \
  && ok "11c --json carries the same lines as layers; an uncommitted edit is said" || bad "11c
$out"
out=$(cd "$TMP" && python3 "$NUA" --report --due-only 2>&1)
! grep -q 'layer' <<< "$out" && ok "11d --due-only (the session start) leaves it to the layer hook" || bad "11d
$out"
git -C "$A/mine" checkout -q -- p.md; git -C "$A/mine" push -q origin HEAD:main 2>/dev/null
out=$(cd "$TMP" && python3 "$NUA" --report 2>&1)
! grep -q 'cadence layers' <<< "$out" && ok "11e pushed again: the section is gone" || bad "11e
$out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
