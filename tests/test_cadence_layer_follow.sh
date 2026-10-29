#!/usr/bin/env bash
# cadence_layer.py --follow / --update — following someone else's cadence layer with the pin
# checked (TD-130, cadence §9.18, Adoption checklist step 12). Offline and fixture-driven: the
# followed layer's "remote" is a temp repo, the setting is a machine cadence.toml under
# AGENT_CADENCE_REG_DIR, and HOME/XDG_CONFIG_HOME point into the temp dir.
# Asserts: each check refuses with its reason and leaves the setting byte-for-byte (an
# unreachable ref, a branch, a missing file, a duplicate path, a URL whose --dir holds another
# clone); the success path clones, prints the text and the effective view, and inserts the block
# before one's own layer with every comment kept, which the hook then reads at its pin; a file
# with no own layer, and no file at all; a form it does not edit is refused with the block to add
# by hand; --update lists newer tags, moves the ref line alone, warns on a non-descendant and
# refuses a branch; a result that would not read is put back; and --json (TD-132) lists each
# layer's root, kind and ref.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/cadence_layer.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SHIFTLEAD_SESSION
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
CFG="$AGENT_CADENCE_REG_DIR/cadence.toml"
cl() { (cd "$TMP" && python3 "$SCRIPT" "$@" 2>&1); }
same() { cmp -s "$CFG" "$TMP/cfg.before"; }

# fixtures: alice's layer repo (tags v1, v2; a branch dev; a tag and branch both named both), and one's own
UP="$TMP/alice-layer"; git init -q -b main "$UP"
printf '# alice\n§4.8 add: alice reviews twice\n' > "$UP/cadence-personal.md"
git -C "$UP" add -A && git -C "$UP" commit -qm v1 && git -C "$UP" tag v1
V1=$(git -C "$UP" rev-parse HEAD)
printf '# alice\n§4.8 add: alice reviews three times\n' > "$UP/cadence-personal.md"
git -C "$UP" commit -qam v2 && git -C "$UP" tag v2
git -C "$UP" branch dev; git -C "$UP" tag both; git -C "$UP" branch both
URL="file://$UP"
mkdir -p "$HOME/cadence-layer"; git init -q -b main "$HOME/cadence-layer"
printf '# mine\n§4.8 override: one review\n' > "$HOME/cadence-layer/cadence-personal.md"
git -C "$HOME/cadence-layer" add -A && git -C "$HOME/cadence-layer" commit -qm own
cat > "$CFG" <<'TOML'
# machine settings — why each is here
review-model = "sonnet"   # cheapest that catches things

# my own rules, last so they win
[[layers]]
path = "~/cadence-layer/cadence-personal.md"   # the working tree
TOML
cp "$CFG" "$TMP/cfg.before"

# 1. the refusals: each names its reason; the setting is untouched
out=$(cl --follow "$URL" --ref v9); rc=$?
[ $rc = 1 ] && grep -q "refused — ref v9 does not resolve to a commit" <<< "$out" && same && [ -d "$HOME/src/alice-layer" ] \
  && ok "1a an unreachable ref is refused (the clone is made, the setting untouched)" || bad "1a rc=$rc $out"
out=$(cl --follow "$URL" --ref dev); rc=$?
[ $rc = 1 ] && grep -q "refused — ref dev is a branch (refs/remotes/origin/dev)" <<< "$out" && same \
  && ok "1b a branch is refused: a pin must not move" || bad "1b rc=$rc $out"
out=$(cl --follow "$URL" --ref origin/dev); rc=$?
[ $rc = 1 ] && grep -q "refused — ref origin/dev is a branch (refs/remotes/origin/dev)" <<< "$out" && same \
  && ok "1b' a remote-tracking branch is refused the same way" || bad "1b' rc=$rc $out"
out=$(cl --follow "$URL" --ref both); rc=$?
[ $rc = 1 ] && grep -q "refused — ref both names a tag and also refs/remotes/origin/both: ambiguous" <<< "$out" && same \
  && ok "1c a tag that is also a branch is refused as ambiguous" || bad "1c rc=$rc $out"
out=$(cl --follow "$URL" --ref v1 --file rules/none.md); rc=$?
[ $rc = 1 ] && grep -q "refused — no file rules/none.md at v1" <<< "$out" && same \
  && ok "1d a file missing at the ref is refused" || bad "1d rc=$rc $out"
out=$(cl --follow "$HOME/cadence-layer" --ref HEAD); rc=$?
[ $rc = 1 ] && grep -q "refused — ref HEAD is neither a tag nor a commit" <<< "$out" && same \
  && ok "1e a symbolic ref is refused" || bad "1e rc=$rc $out"
git -C "$HOME/cadence-layer" tag own1
out=$(cl --follow "$HOME/cadence-layer" --ref own1); rc=$?
[ $rc = 1 ] && grep -q "refused — layer 1 already names ~/cadence-layer/cadence-personal.md (your own)" <<< "$out" && same \
  && ok "1f a path already in the setting is refused" || bad "1f rc=$rc $out"
git init -q "$TMP/other"; out=$(cl --follow "$URL" --ref v1 --dir "$TMP/other"); rc=$?
[ $rc = 1 ] && grep -q "is a clone of nothing (no origin), not $URL: give another --dir" <<< "$out" && same \
  && ok "1g a --dir holding another clone is refused" || bad "1g rc=$rc $out"
out=$(cl --follow "$URL" --ref v1 --bogus x); rc=$?
[ $rc = 2 ] && grep -q "^usage:" <<< "$out" && same && ok "1h an unknown option is a usage error" || bad "1h rc=$rc $out"

# 2. success: the clone reused, the text printed, the effective view, the block before one's own
out=$(cl --follow "$URL" --ref v1); rc=$?
[ $rc = 0 ] && grep -q "reusing ~/src/alice-layer; fetched its tags" <<< "$out" && grep -q "§4.8 add: alice reviews twice" <<< "$out" \
  && grep -q "layer 1 line 2 add: alice reviews twice — superseded by layer 2's §4.8 override" <<< "$out" \
  && grep -q "added to $CFG as layer 1, before your own layer" <<< "$out" \
  && ok "2a --follow prints the text at the pin and the effective view, then adds it as layer 1" || bad "2a rc=$rc $out"
want=$(printf '%s\n' '# machine settings — why each is here' 'review-model = "sonnet"   # cheapest that catches things' '' \
  '[[layers]]' 'path = "~/src/alice-layer/cadence-personal.md"' 'ref = "v1"' '' \
  '# my own rules, last so they win' '[[layers]]' 'path = "~/cadence-layer/cadence-personal.md"   # the working tree')
[ "$(cat "$CFG")" = "$want" ] && ok "2b the block is inserted above one's own (its comment kept with it); every other byte the same" || bad "2b
$(cat "$CFG")"
out=$(cd "$TMP" && python3 "$SCRIPT" --hook); short=$(git -C "$UP" rev-parse --short v1)
grep -q "layer 1 of 2: ~/src/alice-layer/cadence-personal.md @ $short (pinned v1)" <<< "$out" && grep -q "alice reviews twice" <<< "$out" \
  && ok "2c the hook reads the followed layer at its pin" || bad "2c $out"
out=$(cl --json); rc=$?
python3 - "$out" "$HOME" <<'PY' && ok "2d --json (TD-132): each layer's path, file, root, kind, ref and commit, in order" || bad "2d rc=$rc $out"
import json, sys
d, home = json.loads(sys.argv[1]), sys.argv[2]
f, o = d["layers"]
assert f["path"] == "~/src/alice-layer/cadence-personal.md" and f["file"] == home + "/src/alice-layer/cadence-personal.md", f
assert f["root"] == home + "/src/alice-layer" and f["kind"] == "followed" and f["ref"] == "v1" and f["commit"] and f["error"] is None, f
assert o["root"] == home + "/cadence-layer" and o["kind"] == "own" and o["ref"] is None and o["commit"] and o["error"] is None, o
PY
mkdir -p "$HOME/cadence-layer/sub" "$TMP/loose"; echo "x" > "$HOME/cadence-layer/sub/more.md"; echo "y" > "$TMP/loose/l.md"
cp "$CFG" "$TMP/cfg.keep"
printf '[[layers]]\npath = "~/cadence-layer/sub/more.md"\n[[layers]]\npath = "%s/loose/l.md"\n' "$TMP" > "$CFG"
out=$(cl --json); rc=$?
python3 - "$out" "$HOME" <<'PY' && [ $rc = 0 ] && ok "2e --json: a layer in a subdirectory gives its clone's top; a file in no clone, root null; each with its note" || bad "2e rc=$rc $out"
import json, sys
s, l = json.loads(sys.argv[1])["layers"]
assert s["root"] == sys.argv[2] + "/cadence-layer" and s["commit"] is None and "not committed" in s["note"], s
assert l["root"] is None and "not in a git clone" in l["note"] and l["error"] is None, l
PY
cp "$TMP/cfg.keep" "$CFG"; rm -r "$HOME/cadence-layer/sub"

# 3. --update: newer tags listed; the ref moved, only that line; a branch refused; a non-descendant warned
cp "$CFG" "$TMP/cfg.before"
out=$(cl --update 1); rc=$?
[ $rc = 0 ] && grep -q "pinned at v1; newer tags: .*v2" <<< "$out" && same && ok "3a --update lists the newer tags, changing nothing" || bad "3a rc=$rc $out"
out=$(cl --update 2 --ref v2); rc=$?
[ $rc = 1 ] && grep -q "is your own, read from its working tree: there is no pin to move" <<< "$out" && same && ok "3b one's own layer has no pin to move" || bad "3b rc=$rc $out"
out=$(cl --update 1 --ref dev); rc=$?
[ $rc = 1 ] && grep -q "ref dev is a branch" <<< "$out" && same && ok "3c --update refuses a branch too" || bad "3c rc=$rc $out"
out=$(cl --update 1 --ref v2); rc=$?
[ $rc = 0 ] && grep -q "^-§4.8 add: alice reviews twice" <<< "$out" && grep -q "^+§4.8 add: alice reviews three times" <<< "$out" \
  && grep -q "layer 1: ref v1 -> v2" <<< "$out" && ! grep -q "does not descend" <<< "$out" \
  && [ "$(diff "$TMP/cfg.before" "$CFG" | grep -c '^[<>]')" = 2 ] && grep -qx 'ref = "v2"' "$CFG" \
  && ok "3d --update --ref prints the diff and moves the ref line alone" || bad "3d rc=$rc $out $(diff "$TMP/cfg.before" "$CFG")"
git -C "$UP" checkout -q --orphan side && git -C "$UP" commit -qm side && git -C "$UP" tag v3 && git -C "$UP" checkout -q main
out=$(cl --update 1 --ref v3); rc=$?
[ $rc = 0 ] && grep -q "warning: v3 does not descend from v2" <<< "$out" && grep -qx 'ref = "v3"' "$CFG" \
  && ok "3e a ref that does not descend from the pin is warned about, then moved" || bad "3e rc=$rc $out"
out=$(cl --update 1 --ref "${V1:0:12}"); rc=$?
[ $rc = 0 ] && grep -qx "ref = \"${V1:0:12}\"" "$CFG" && ok "3f a commit is a pin" || bad "3f rc=$rc $out"

# 4. no own layer: appended; no file at all: created
rm "$CFG"
out=$(cl --follow "$URL" --ref v1); rc=$?
[ $rc = 0 ] && [ "$(cat "$CFG")" = "$(printf '[[layers]]\npath = "~/src/alice-layer/cadence-personal.md"\nref = "v1"')" ] \
  && ok "4a no settings file: it is created with the block" || bad "4a rc=$rc $out $(cat "$CFG" 2>&1)"
git -C "$HOME/cadence-layer" tag v1
printf 'review-model = "haiku"' > "$CFG"
out=$(cl --follow "$HOME/cadence-layer" --ref v1); rc=$?
[ $rc = 0 ] && [ "$(cat "$CFG")" = "$(printf 'review-model = "haiku"\n\n[[layers]]\npath = "~/cadence-layer/cadence-personal.md"\nref = "v1"')" ] \
  && grep -q "has no remote: checking what the clone has" <<< "$out" \
  && ok "4b no layers yet: appended after the file's last line; a local clone with no remote is used as it is" || bad "4b rc=$rc $out
$(cat "$CFG")"

printf 'layers = 3\n' > "$CFG"
out=$(cl --json); rc=$?
[ $rc = 2 ] && python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$out" \
  && ok "5c --json on a setting that does not read: {error}, exit 2" || bad "5c rc=$rc $out"

# 5. a form it does not edit, and a result that would not read, leave the file as it was
printf 'layers = [{path = "~/cadence-layer/cadence-personal.md"}]\n' > "$CFG"; cp "$CFG" "$TMP/cfg.before"
out=$(cl --follow "$URL" --ref v2); rc=$?
[ $rc = 1 ] && grep -q "in a form this tool does not edit" <<< "$out" && grep -q 'ref = "v2"' <<< "$out" && same \
  && ok "5a an inline layers array is refused, with the block to add by hand" || bad "5a rc=$rc $out"
printf 'note = """\n[[layers]]\n"""\nlayers = [{path = "~/cadence-layer/cadence-personal.md"}]\n' > "$CFG"; cp "$CFG" "$TMP/cfg.before"
out=$(cl --follow "$URL" --ref v2); rc=$?
[ $rc = 1 ] && grep -q "not changed — the file would not read as the same settings with the new layer at 1" <<< "$out" && same \
  && ok "5b an insert that would change another setting (a [[layers]] line inside a string) is put back" || bad "5b rc=$rc $out"

# 6. a symlinked settings file is written through its link; a CRLF file is edited in its own line endings
mkdir -p "$TMP/dotfiles"; printf '[[layers]]\npath = "~/cadence-layer/cadence-personal.md"\n' > "$TMP/dotfiles/cadence.toml"
rm -f "$CFG"; ln -s "$TMP/dotfiles/cadence.toml" "$CFG"
out=$(cl --follow "$URL" --ref v1); rc=$?
[ $rc = 0 ] && [ -L "$CFG" ] && grep -q 'ref = "v1"' "$TMP/dotfiles/cadence.toml" \
  && ok "6a a symlinked cadence.toml stays a link; the edit lands in its target" || bad "6a rc=$rc $out $(ls -l "$CFG")"
rm -f "$CFG"; printf '[[layers]]\r\npath = "~/src/alice-layer/cadence-personal.md"\r\nref = "v1"\r\n[[layers]]\r\npath = "~/cadence-layer/cadence-personal.md"\r\n' > "$CFG"
out=$(cl --update 1 --ref v2); rc=$?
[ $rc = 0 ] && [ "$(cat "$CFG")" = "$(printf '[[layers]]\r\npath = "~/src/alice-layer/cadence-personal.md"\r\nref = "v2"\r\n[[layers]]\r\npath = "~/cadence-layer/cadence-personal.md"\r')" ] \
  && ok "6b a CRLF file: --update moves the ref and keeps the line ending" || bad "6b rc=$rc $out $(od -c "$CFG" | head)"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
