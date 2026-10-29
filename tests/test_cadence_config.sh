#!/usr/bin/env bash
# cadence_config.py — the one reader of the cadence's settings (TD-096, cadence §9.18).
# Precedence env > repo > machine > default; a file that cannot be read is an error, never a
# silent default; --check names a key nothing reads. And the parity pair (cadence §7.9): the
# reader's KEYS, the seed docs/cadence.toml and §9.18 name the same keys with the same defaults.
# Offline; HOME, XDG_CONFIG_HOME and AGENT_CADENCE_REG_DIR all point into a temp dir.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/cadence_config.py"
SEED="$DC/files/docs/cadence.toml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
unset CADENCE_REVIEW_MODEL CADENCE_SWEEP_MODEL
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"; mkdir -p "$R/docs/sub"; git init -q "$R"
get() { (cd "$R/docs/sub" && python3 "$SCRIPT" get "$@" 2>"$TMP/err"); }

# 1. no file anywhere: the defaults, from anywhere in the repo
v=$(get review-model); rc=$?
[ "$rc" = 0 ] && [ "$v" = sonnet ] && ok "1 no file: review-model is the default" || bad "1 got rc=$rc '$v'"
python3 "$SCRIPT" --repo "$R" | grep -q '^review-model *sonnet *(default)' \
  && ok "1b the listing names the default as the source" || bad "1b $(python3 "$SCRIPT" --repo "$R")"

# 2. the seed as shipped parses, is clean, and changes nothing
cp "$SEED" "$R/docs/cadence.toml"
v=$(get review-model); rc=$?
[ "$rc" = 0 ] && [ "$v" = sonnet ] && python3 "$SCRIPT" --repo "$R" --check >/dev/null \
  && ok "2 the shipped seed reads clean" || bad "2 rc=$rc '$v' $(cat "$TMP/err")"

# 3. the machine file over the default, the repo file over the machine
printf 'review-model = "machine-model"\nsweep-model = "machine-sweep"\n' > "$AGENT_CADENCE_REG_DIR/cadence.toml"
printf '# why: a test\nreview-model = "repo-model"\n' > "$R/docs/cadence.toml"
[ "$(get review-model)" = repo-model ] && [ "$(get sweep-model)" = machine-sweep ] \
  && ok "3 repo over machine over default" || bad "3 $(get review-model) $(get sweep-model)"
python3 "$SCRIPT" --repo "$R" --json | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["review-model"]["from"]=="docs/cadence.toml", d
assert d["sweep-model"]["from"].endswith("/reg/cadence.toml"), d' \
  && ok "3b --json names each value's source" || bad "3b"

# 4. env over everything; an empty env value is unset
[ "$(CADENCE_REVIEW_MODEL=env-model get review-model)" = env-model ] \
  && [ "$(CADENCE_REVIEW_MODEL= get review-model)" = repo-model ] \
  && ok "4 CADENCE_REVIEW_MODEL wins; empty is unset" || bad "4"

# 5. no AGENT_CADENCE_REG_DIR: the machine file is under XDG_CONFIG_HOME/agent-cadence
mkdir -p "$XDG_CONFIG_HOME/agent-cadence"; printf 'sweep-model = "xdg-sweep"\n' > "$XDG_CONFIG_HOME/agent-cadence/cadence.toml"
[ "$(cd "$R" && env -u AGENT_CADENCE_REG_DIR python3 "$SCRIPT" get sweep-model)" = xdg-sweep ] \
  && ok "5 machine file falls back to XDG_CONFIG_HOME/agent-cadence" || bad "5"
rm -f "$AGENT_CADENCE_REG_DIR/cadence.toml"

# 6. a key nothing reads: get still answers, --check names it and fails
printf 'review-model = "repo-model"\ncolour = "blue"\n' > "$R/docs/cadence.toml"
out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$(get review-model)" = repo-model ] && [ "$rc" = 1 ] && grep -q "unknown key 'colour'" <<< "$out" \
  && ok "6 --check names an unknown key" || bad "6 rc=$rc '$out'"

# 7. a file that is not TOML: an error naming it, never the default
printf 'review-model: sonnet\n' > "$R/docs/cadence.toml"
v=$(get review-model); rc=$?
[ "$rc" = 2 ] && [ -z "$v" ] && grep -q 'docs/cadence.toml' "$TMP/err" \
  && ok "7 bad TOML is exit 2 naming the file" || bad "7 rc=$rc '$v' $(cat "$TMP/err")"

# 8. a value of the wrong type
printf 'review-model = 3\n' > "$R/docs/cadence.toml"
v=$(get review-model); rc=$?; python3 "$SCRIPT" --repo "$R" --check >/dev/null; crc=$?
[ "$rc" = 2 ] && [ "$crc" = 1 ] && grep -q 'non-empty string' "$TMP/err" \
  && ok "8 a non-string value is an error, and --check fails" || bad "8 rc=$rc crc=$crc"

# 9. a key no tool knows, asked for
get no-such-key >/dev/null; rc=$?
[ "$rc" = 2 ] && grep -q "unknown key 'no-such-key'" "$TMP/err" && ok "9 get of an unknown key is exit 2" || bad "9 rc=$rc"

# 11. Python < 3.11 (no tomllib): the SEED as synced (comments only) reads as no settings;
#     a file with a setting in it is exit 2 naming the version — never a silent default
old() { (cd "$R" && python3 -c 'import sys, runpy; sys.modules["tomllib"] = None; sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name="__main__")' "$SCRIPT" get review-model 2>"$TMP/err"); }
cp "$SEED" "$R/docs/cadence.toml"
v=$(old); rc=$?
[ "$rc" = 0 ] && [ "$v" = sonnet ] && ok "11 no tomllib, the comment-only SEED: the defaults answer" || bad "11 rc=$rc '$v' $(cat "$TMP/err")"
printf '# why\nreview-model = "opus"\n' > "$R/docs/cadence.toml"
v=$(old); rc=$?
[ "$rc" = 2 ] && [ -z "$v" ] && grep -q 'Python >= 3.11' "$TMP/err" && ok "11b no tomllib, a file with a setting: exit 2 naming the version" || bad "11b rc=$rc '$v' $(cat "$TMP/err")"
rm "$R/docs/cadence.toml"

# 12. an env value of blanks is unset; an explicit --repo that is not a repo is exit 2
[ "$(CADENCE_REVIEW_MODEL='  ' get review-model)" = sonnet ] && ok "12 a blank CADENCE_REVIEW_MODEL is unset" || bad "12 blank env"
python3 "$SCRIPT" --repo "$TMP/nowhere" get review-model >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'not a git repository' "$TMP/err" && ok "12b --repo naming no repo: exit 2, not the defaults" || bad "12b rc=$rc $(cat "$TMP/err")"

# 13. the opt-out tables (TD-096 slice 2): the repo's file only, each value an ADR string
printf '[not-adopted]\n"§4" = "docs/decisions/0001.md"\n[skip-seed]\n"docs/claude-memory/MEMORY.md" = "docs/decisions/0001.md"\n' > "$R/docs/cadence.toml"
python3 "$SCRIPT" --repo "$R" --check >/dev/null && [ "$(get review-model)" = sonnet ] \
  && ok "13 [not-adopted]/[skip-seed] in the repo's file: no problem, and settings still resolve" || bad "13 $(python3 "$SCRIPT" --repo "$R" --check)"
cp "$R/docs/cadence.toml" "$AGENT_CADENCE_REG_DIR/cadence.toml"; printf '[not-adopted]\n"§4" = 4\n' > "$R/docs/cadence.toml"
out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$rc" = 1 ] && grep -q "is the repo's decision" <<< "$out" && grep -q "must name its ADR as a string" <<< "$out" \
  && ok "13b --check: an opt-out in the machine file, and an ADR that is not a string" || bad "13b rc=$rc $out"
out=$(python3 "$SCRIPT" opt-outs --repo "$R" | tr '\037' '|')
grep -q '^warn|docs/cadence.toml: \[not-adopted\] "§4" must name its ADR as a string' <<< "$out" && ! grep -q '^not-adopted' <<< "$out" \
  && ok "13c opt-outs: the machine file's table is never read, a bad entry is a warn line" || bad "13c $out"
rm -f "$AGENT_CADENCE_REG_DIR/cadence.toml" "$R/docs/cadence.toml"
python3 "$SCRIPT" opt-outs >/dev/null 2>&1; [ $? = 2 ] && ok "13d opt-outs without --repo: exit 2" || bad "13d"

# 14. post-sync (TD-113) is retired (TD-169): --check names it as retired in either file, never as
# an unknown key; get no longer knows it
printf '# why: the wheel copy\npost-sync = "scripts/vendor.sh v1"\n' > "$R/docs/cadence.toml"
out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$rc" = 1 ] && grep -q "docs/cadence.toml: post-sync is retired — .*TD-169.*; delete the line" <<< "$out" && ! grep -q "unknown key 'post-sync'" <<< "$out" \
  && ok "14 --check: post-sync in the repo's file is named as retired" || bad "14 rc=$rc $out"
get post-sync >/dev/null; rc=$?
[ "$rc" = 2 ] && grep -q "unknown key 'post-sync'" "$TMP/err" && ok "14b get post-sync: no longer a key, exit 2" || bad "14b rc=$rc $(cat "$TMP/err")"
[ "$(get review-model)" = sonnet ] && ok "14c a retired key in the file does not stop another key resolving" || bad "14c $(get review-model)"
rm -f "$R/docs/cadence.toml"
printf 'post-sync = "make vendor"\n' > "$AGENT_CADENCE_REG_DIR/cadence.toml"
out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$rc" = 1 ] && grep -q "cadence.toml: post-sync is retired" <<< "$out" && ok "14d --check: post-sync in the machine file is named as retired too" || bad "14d rc=$rc $out"
rm -f "$AGENT_CADENCE_REG_DIR/cadence.toml"
# 14f. ledger-ids-host (TD-124): a repo key with a vocabulary — on or off, anything else flagged
printf 'ledger-ids-host = "off"\n' > "$R/docs/cadence.toml"
[ "$(get ledger-ids-host)" = off ] && python3 "$SCRIPT" --repo "$R" --check >/dev/null \
  && ok "14f ledger-ids-host = off: read and clean" || bad "14f $(python3 "$SCRIPT" --repo "$R" --check)"
printf 'ledger-ids-host = "maybe"\n' > "$R/docs/cadence.toml"
out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$rc" = 1 ] && grep -q "ledger-ids-host must be one of on, off" <<< "$out" \
  && ok "14g --check flags a ledger-ids-host that is neither on nor off" || bad "14g rc=$rc $out"
rm -f "$R/docs/cadence.toml"
# 14h. [precheck-paths] (TD-155): a table of the repo's file, globs -> a non-empty command
printf 'precheck = "make test"\n[precheck-paths]\n"docs/technical_debt*.md docs/user_attention*.md" = "make ledger-check"\n' > "$R/docs/cadence.toml"
python3 "$SCRIPT" --repo "$R" --check >/dev/null \
  && PYTHONPATH="$DC/files/scripts" python3 -c 'import cadence_config as c, sys; e = c.precheck_paths(c.sources(sys.argv[1]))
assert e == [(["docs/technical_debt*.md", "docs/user_attention*.md"], "make ledger-check")], e' "$R" \
  && ok "14h [precheck-paths] in the repo's file: --check clean, read as (globs, command)" || bad "14h $(python3 "$SCRIPT" --repo "$R" --check)"
cp "$R/docs/cadence.toml" "$AGENT_CADENCE_REG_DIR/cadence.toml"
printf '[precheck-paths]\n"docs/*.md" = ""\n" " = "x"\n' > "$R/docs/cadence.toml"
out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$rc" = 1 ] && grep -q "reg/cadence.toml: \[precheck-paths\] is the repo's decision" <<< "$out" \
  && [ "$(grep -c "must name globs and map them to a non-empty command" <<< "$out")" = 2 ] \
  && ok "14i --check: [precheck-paths] in the machine file, an empty command and an empty glob list" || bad "14i rc=$rc $out"
rm -f "$R/docs/cadence.toml" "$AGENT_CADENCE_REG_DIR/cadence.toml"

# 10. parity (cadence §7.9): KEYS ↔ the seed's commented lines ↔ §9.18, key and default
# (the repo's own keys — REPO_KEYS, no default — are shown in the seed as an example, 10c)
keys=$(PYTHONPATH="$DC/files/scripts" python3 -c 'import cadence_config as c; [print(k, d) for k,(d,_) in c.KEYS.items()]')
rkeys=$(PYTHONPATH="$DC/files/scripts" python3 -c 'import cadence_config as c; [print(k) for k in c.REPO_KEYS]')
seed=$(sed -n 's/^# *\([a-z-]*\) = "\(.*\)"$/\1 \2/p' "$SEED" | grep -vF -f <(sed 's/$/ /' <<< "$rkeys"))
[ -n "$keys" ] && [ "$keys" = "$seed" ] && ok "10 the seed lists exactly KEYS with their defaults" || bad "10 KEYS='$keys' seed='$seed'"
rule=$(grep -F -- '- **§9.18**' "$DC/files/docs/cadence.md")
miss=""; while read -r k d; do grep -qF "\`$k\`" <<< "$rule" && grep -qF "default \`$d\`" <<< "$rule" || miss+=" $k"; done <<< "$keys"
[ -z "$miss" ] && ok "10b §9.18 names every key and its default" || bad "10b §9.18 lacks:$miss"
miss=""; while read -r k; do grep -qE "^# *$k = " "$SEED" && grep -qF "\`$k\`" <<< "$rule" || miss+=" $k"; done <<< "$rkeys"
[ -n "$rkeys" ] && [ -z "$miss" ] && ok "10c the seed and §9.18 name every repo key (REPO_KEYS)" || bad "10c lacks:$miss"
mkeys=$(PYTHONPATH="$DC/files/scripts" python3 -c 'import cadence_config as c; [print(k) for k in c.MACHINE_KEYS]')
miss=""; while read -r k; do grep -qF "\`$k\`" <<< "$rule" && ! grep -qE "^$k *=" "$SEED" || miss+=" $k"; done <<< "$mkeys"
[ -n "$mkeys" ] && [ -z "$miss" ] && ok "10d §9.18 names every machine key (MACHINE_KEYS), and the repo seed never sets one" || bad "10d lacks:$miss"

# 11. a machine key (TD-126): the machine's file only — never env, never the repo's file
rm -f "$R/docs/cadence.toml" "$AGENT_CADENCE_REG_DIR/cadence.toml"
get layers; rc=$?
[ "$rc" = 1 ] && ok "11 layers unset: get exits 1, no default" || bad "11 rc=$rc"
printf '[[layers]]\npath = "~/mine/p.md"\n[[layers]]\npath = "/abs/theirs.md"\nref = "v1"\n' > "$AGENT_CADENCE_REG_DIR/cadence.toml"
v=$(get layers); rc=$?
[ "$rc" = 0 ] && [ "$v" = '[{"path": "~/mine/p.md"}, {"path": "/abs/theirs.md", "ref": "v1"}]' ] \
  && ok "11b layers from the machine's file, in order, as JSON" || bad "11b rc=$rc '$v' $(cat "$TMP/err")"
v=$(CADENCE_LAYERS='[{"path": "/x"}]' get layers)
[ "$v" = '[{"path": "~/mine/p.md"}, {"path": "/abs/theirs.md", "ref": "v1"}]' ] && ok "11c CADENCE_LAYERS is not read" || bad "11c '$v'"
printf '[[layers]]\npath = "/repo/says.md"\n' > "$R/docs/cadence.toml"
v=$(get layers); out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$v" = '[{"path": "~/mine/p.md"}, {"path": "/abs/theirs.md", "ref": "v1"}]' ] && [ "$rc" = 1 ] \
  && grep -q "docs/cadence.toml: layers is the person's, not the repo's" <<< "$out" \
  && ok "11d a repo's file naming layers is not read, and --check names it" || bad "11d '$v' rc=$rc $out"
rm -f "$R/docs/cadence.toml"
f11e=0
for bad_value in 'layers = "~/p.md"' 'layers = []' 'layers = [{path = "rel/p.md"}]' 'layers = [{path = "/p.md", ref = ""}]' \
                 'layers = [{path = "/p.md", ref = "--upload-pack=x"}]' 'layers = [{path = "/p.md", branch = "main"}]' 'layers = ["/p.md"]'; do
    echo "$bad_value" > "$AGENT_CADENCE_REG_DIR/cadence.toml"
    out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
    get layers >/dev/null; grc=$?
    [ "$rc" = 1 ] && grep -q ": layers " <<< "$out" && [ "$grc" = 2 ] || { bad "11e $bad_value: check rc=$rc get rc=$grc $out"; f11e=1; }
done
[ "$f11e" = 0 ] && ok "11e a malformed layers value: --check names it, get exits 2"
rm -f "$AGENT_CADENCE_REG_DIR/cadence.toml"
# 11f publish-names (TD-090), the person's too: the machine's file only, a list of names
printf 'publish-names = ["Jordan", "acme-corp"]\n' > "$AGENT_CADENCE_REG_DIR/cadence.toml"
printf 'publish-names = ["repo-says"]\n' > "$R/docs/cadence.toml"
v=$(CADENCE_PUBLISH_NAMES='["env-says"]' get publish-names); out=$(python3 "$SCRIPT" --repo "$R" --check); rc=$?
[ "$v" = '["Jordan", "acme-corp"]' ] && [ "$rc" = 1 ] && grep -q "docs/cadence.toml: publish-names is the person's, not the repo's" <<< "$out" \
  && ok "11f publish-names: the machine's file only — never env, never a repo's file (--check names it)" || bad "11f '$v' rc=$rc $out"
rm -f "$R/docs/cadence.toml" "$AGENT_CADENCE_REG_DIR/cadence.toml"

# 12. TD-134's thresholds: the default, a repo value (integer or string), a machine value, an invalid value
rm -f "$R/docs/cadence.toml" "$AGENT_CADENCE_REG_DIR/cadence.toml"
for kd in sweep-every:10 deep-sweep-every:30 pr-stale-days:2 escalate-overdue-days:14 board-size-warn:15; do
  k=${kd%%:*}; dflt=${kd#*:}
  v=$(get "$k"); [ "$v" = "$dflt" ] || bad "12 $k default: '$v'"
  printf '%s = 7\n' "$k" > "$R/docs/cadence.toml"; v=$(get "$k"); [ "$v" = 7 ] || bad "12 $k repo integer: '$v'"
  printf '%s = "8"\n' "$k" > "$R/docs/cadence.toml"; v=$(get "$k"); [ "$v" = 8 ] || bad "12 $k repo string: '$v'"
  rm "$R/docs/cadence.toml"; printf '%s = 9\n' "$k" > "$AGENT_CADENCE_REG_DIR/cadence.toml"; v=$(get "$k"); [ "$v" = 9 ] || bad "12 $k machine: '$v'"
  rm "$AGENT_CADENCE_REG_DIR/cadence.toml"
  for badv in 0 '"x"' 1.5 true '"-3"'; do
    printf '%s = %s\n' "$k" "$badv" > "$R/docs/cadence.toml"
    out=$(cd "$R" && python3 "$SCRIPT" --check 2>&1); rc=$?
    [ $rc = 1 ] && [[ "$out" == *"$k must be a whole number of 1 or more"* ]] || bad "12 $k --check $badv: rc=$rc $out"
    get "$k" >/dev/null; [ $? = 2 ] || bad "12 $k get of $badv did not exit 2"
  done
  rm "$R/docs/cadence.toml"
done
[ "$FAIL" = 0 ] && ok "12 each threshold: its default, a repo integer and string, a machine value, and five invalid values flagged"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
