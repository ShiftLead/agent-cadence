#!/usr/bin/env bash
# adopt_repo_settings.sh (TD-034): --check is read-only and exits 1 on drift; --apply
# PATCHes only the drifted settings and is a no-op on a clean repo. Fully offline: gh
# is a PATH shim driven by a fixture file, and every call is logged so tests can
# assert that --check never writes.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/files/scripts/adopt_repo_settings.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; export XDG_CONFIG_HOME="$TMP/config"; mkdir -p "$HOME" "$XDG_CONFIG_HOME"
export ADOPT_READ_SLEEP=0   # the re-read loop's pause (TD-107); its count stays the script's default
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

FAKE="$TMP/fake"; mkdir -p "$FAKE"; export FAKE
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls.log"
[ -f "$FAKE/down" ] && { echo "gh: HTTP 401: Bad credentials" >&2; exit 1; }
if [ "$1 $2" = "repo view" ]; then cat "$FAKE/slug" 2>/dev/null || exit 1; exit 0; fi
if [ "$1" = "api" ] && [ "$2" = "-X" ] && [ "$3" = "PATCH" ]; then
  shift 4   # api -X PATCH repos/<r>
  cp "$FAKE/settings" "$FAKE/stale"
  while [ $# -gt 0 ]; do
    [ "$1" = "-F" ] && { k="${2%%=*}"; v="${2#*=}"; sed -i "s/^$k=.*/$k=$v/" "$FAKE/settings"; shift 2; continue; }
    shift
  done
  echo "{}"; exit 0
fi
if [ "$1" = "api" ] && [[ "$2" == repos/* ]]; then
  # TD-107: $FAKE/lag holds how many reads still return the values from before the PATCH
  if [ -s "$FAKE/lag" ] && [ "$(cat "$FAKE/lag")" -gt 0 ] && [ -f "$FAKE/stale" ]; then
    echo $(( $(cat "$FAKE/lag") - 1 )) > "$FAKE/lag"; cat "$FAKE/stale"; exit 0
  fi
  # emulate --jq output from the fixture (name=value per line)
  cat "$FAKE/settings"; exit 0
fi
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

reset_fixture() { printf 'allow_squash_merge=%s\nallow_merge_commit=%s\nallow_rebase_merge=%s\ndelete_branch_on_merge=%s\n' "$@" > "$FAKE/settings"; : > "$FAKE/calls.log"; }
echo "tester/thing" > "$FAKE/slug"

# 1) clean repo: --check exits 0, no PATCH
reset_fixture true false false true
out=$(bash "$S" --check tester/thing 2>&1); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "clean: nothing to change" && ! grep -q PATCH "$FAKE/calls.log"; then
  ok "--check on a clean repo exits 0 and writes nothing"; else bad "clean --check (rc=$rc): $out"; fi

# 2) drift: default mode is --check, exits 1, names the drifted settings, no PATCH
reset_fixture true true false false
out=$(bash "$S" tester/thing 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q "DRIFT  allow_merge_commit" && echo "$out" | grep -q "DRIFT  delete_branch_on_merge" \
   && echo "$out" | grep -q "ok     allow_squash_merge" && ! grep -q PATCH "$FAKE/calls.log"; then
  ok "default (--check) exits 1 on drift, names each drifted setting, writes nothing"
else bad "drift --check (rc=$rc): $out"; fi

# 3a) --apply with no terminal to ask and no --yes: refused, exit 2, naming the flag (TD-058)
out=$(bash "$S" --apply tester/thing 2>&1 </dev/null); rc=$?
if [ "$rc" = 2 ] && echo "$out" | grep -q "re-run with --yes" && ! grep -q PATCH "$FAKE/calls.log"; then
  ok "--apply without a terminal or --yes: refused, exit 2, nothing written"; else bad "unattended apply (rc=$rc): $out"; fi
# 3b) at a terminal it asks, naming the repo; anything but yes writes nothing
if command -v script >/dev/null 2>&1; then
  out=$(printf 'n\n' | script -qec "bash '$S' --apply tester/thing" /dev/null 2>&1); rc=$?
  if echo "$out" | grep -q "apply these to tester/thing? \[y/N\]" && echo "$out" | grep -q "not applied: nothing changed" && ! grep -q PATCH "$FAKE/calls.log"; then
    ok "--apply at a terminal asks, naming the repo; 'n' writes nothing"; else bad "prompt n (rc=$rc): $out"; fi
  out=$(printf 'y\n' | script -qec "bash '$S' --apply tester/thing" /dev/null 2>&1)
  if echo "$out" | grep -q "^applied" && [ "$(grep -c PATCH "$FAKE/calls.log")" = 1 ]; then
    ok "--apply at a terminal: 'y' applies"; else bad "prompt y: $out"; fi
  reset_fixture true true false false
else
  echo "SKIP: no script(1) — the terminal prompt is not exercised"
fi
# 3) --apply --yes PATCHes only the drifted settings, re-reads, exits 0
out=$(bash "$S" --apply --yes tester/thing 2>&1); rc=$?
patch=$(grep PATCH "$FAKE/calls.log")
if [ "$rc" = 0 ] && echo "$out" | grep -q "^applied" && [ "$(grep -c PATCH "$FAKE/calls.log")" = 1 ] \
   && echo "$patch" | grep -q -- "-F allow_merge_commit=false" && echo "$patch" | grep -q -- "-F delete_branch_on_merge=true" \
   && ! echo "$patch" | grep -q "allow_squash_merge"; then
  ok "--apply PATCHes exactly the drifted settings and confirms"; else bad "--apply (rc=$rc): $out / $patch"; fi

# 4) --apply on a now-clean repo is a no-op
: > "$FAKE/calls.log"
out=$(bash "$S" --apply tester/thing 2>&1); rc=$?
if [ "$rc" = 0 ] && ! grep -q PATCH "$FAKE/calls.log"; then ok "--apply is idempotent (no write on a clean repo)"
else bad "idempotent apply (rc=$rc): $out"; fi

# 5) repo resolved from the checkout's ORIGIN when omitted — never gh repo view, which in a
#    fork clone prefers `upstream` and names the parent (TD-058)
reset_fixture true false false true
F="$TMP/forkclone"; git init -q "$F"
git -C "$F" remote add origin git@github.com:tester/thing.git
git -C "$F" remote add upstream https://github.com/parent/thing.git
echo "parent/thing" > "$FAKE/slug"
out=$(cd "$F" && bash "$S" 2>&1); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "^tester/thing — merge settings" && ! grep -q "repo view" "$FAKE/calls.log" \
   && ! grep -q "parent/thing" "$FAKE/calls.log"; then
  ok "omitting owner/repo takes it from origin (a fork clone's upstream is never used)"; else bad "slug resolution (rc=$rc): $out / $(cat "$FAKE/calls.log")"; fi
echo "tester/thing" > "$FAKE/slug"
out=$(cd "$TMP" && bash "$S" 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "origin is not a GitHub repo" && ok "no GitHub origin: cannot verify, exit 2" || bad "no origin (rc=$rc): $out"
G="$TMP/tokclone"; git init -q "$G"; git -C "$G" remote add origin "https://user:s3cr3t@github.com/tester/thing/"
out=$(cd "$G" && bash "$S" 2>&1); rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "^tester/thing — merge settings" && ok "a trailing slash (and credentials) in origin still resolve the repo" || bad "slash (rc=$rc): $out"
git -C "$G" remote set-url origin "https://user:s3cr3t@gitea.example/tester/thing.git"
out=$(cd "$G" && bash "$S" 2>&1); rc=$?
[ "$rc" = 2 ] && ! echo "$out" | grep -q s3cr3t && echo "$out" | grep -q "https://gitea.example/tester/thing.git" \
    && ok "an unparseable credentialed origin: exit 2, and the token is never printed" || bad "leak (rc=$rc): $out"

# 5b) a setting gh reads back as null (a non-admin) is cannot-verify, never drift
reset_fixture true null false true
out=$(bash "$S" --check tester/thing 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "allow_merge_commit as null" && ok "a null setting: exit 2 (cannot verify), not drift" || bad "null (rc=$rc): $out"

# 5c) --no-auto-delete leaves auto-delete out of the check and the apply
reset_fixture true false false false
out=$(bash "$S" --apply --yes --no-auto-delete tester/thing 2>&1); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "clean: nothing to change" && ! grep -q PATCH "$FAKE/calls.log" && ! echo "$out" | grep -q delete_branch_on_merge; then
  ok "--no-auto-delete: auto-delete neither checked nor applied"; else bad "--no-auto-delete (rc=$rc): $out"; fi

# 6) gh cannot answer -> exit 2, distinct from drift
touch "$FAKE/down"
out=$(bash "$S" --check tester/thing 2>&1); rc=$?
if [ "$rc" = 2 ] && echo "$out" | grep -q "cannot verify"; then ok "gh failure exits 2 (cannot verify), not 1"
else bad "gh down (rc=$rc): $out"; fi
rm -f "$FAKE/down"

# 7) PATCH refused (no admin) -> exit 2, reported
reset_fixture true false false false
sed -i 's|if \[ "$1" = "api" \] && \[ "$2" = "-X" \] && \[ "$3" = "PATCH" \]; then|if [ "$1" = "api" ] \&\& [ "$2" = "-X" ] \&\& [ "$3" = "PATCH" ]; then\n  [ -f "$FAKE/deny" ] \&\& { echo "gh: HTTP 403: Must have admin rights" >\&2; exit 1; }|' "$BIN/gh"
touch "$FAKE/deny"
out=$(bash "$S" --apply --yes tester/thing 2>&1); rc=$?
if [ "$rc" = 2 ] && echo "$out" | grep -q "apply failed"; then ok "refused PATCH exits 2 and says so"
else bad "denied apply (rc=$rc): $out"; fi

# 8) PATCH accepted but the read-back still drifts -> exit 1 (drift), reported as not sticking
rm -f "$FAKE/deny"; reset_fixture true false false false
sed -i 's|  shift 4   # api -X PATCH repos/<r>|  [ -f "$FAKE/noop" ] \&\& { echo "{}"; exit 0; }\n  shift 4   # api -X PATCH repos/<r>|' "$BIN/gh"
touch "$FAKE/noop"
out=$(bash "$S" --apply --yes tester/thing 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q "apply did not stick"; then ok "a PATCH that does not change the read-back exits 1 and says so"
else bad "did-not-stick (rc=$rc): $out"; fi
rm -f "$FAKE/noop"

# 8b) TD-107: GitHub's read lags the PATCH — the first reads show the old values, then the new.
#     Two stale reads settle on the third: applied, exit 0, saying it settled late.
reset_fixture true false false false; rm -f "$FAKE/stale"; echo 2 > "$FAKE/lag"
out=$(bash "$S" --apply --yes tester/thing 2>&1); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q "applied (after 3 reads" && ! echo "$out" | grep -q "did not stick" \
   && [ "$(grep -c '^api repos/' "$FAKE/calls.log")" = 4 ]; then ok "a lagging read settles: applied after 3 reads, exit 0"
else bad "lagging read (rc=$rc): $out"; fi
# …and a lag longer than the reads allowed is still reported, naming how many reads it made
reset_fixture true false false false; rm -f "$FAKE/stale"; echo 9 > "$FAKE/lag"
out=$(ADOPT_READ_TRIES=3 bash "$S" --apply --yes tester/thing 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q "did not stick: settings still drift after the write (3 reads"; then ok "a lag past the read limit still reports did-not-stick, with the read count"
else bad "long lag (rc=$rc): $out"; fi
# …and a non-numeric read limit falls back to the default, never an endless loop
reset_fixture true false false false; rm -f "$FAKE/stale"; echo 99 > "$FAKE/lag"
out=$(ADOPT_READ_TRIES=abc timeout 20 bash "$S" --apply --yes tester/thing 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q "(5 reads"; then ok "a non-numeric ADOPT_READ_TRIES uses the default 5"
else bad "non-numeric tries (rc=$rc): $out"; fi
rm -f "$FAKE/lag" "$FAKE/stale"

# 9) unknown option -> exit 2, no gh call
: > "$FAKE/calls.log"
bash "$S" --bogus >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ] && [ ! -s "$FAKE/calls.log" ]; then ok "unknown option exits 2 before touching gh"; else bad "bogus option rc=$rc"; fi

# 9) TD-117: the workflows that run on every PR are named from the checkout's .github/workflows —
#    information only (exit code unchanged), and never for a repo given by name
reset_fixture true false false true
W="$TMP/wfclone"; git init -q "$W"; git -C "$W" remote add origin git@github.com:tester/thing.git
mkdir -p "$W/.github/workflows" "$W/docs"
printf 'name: ci\non:\n  push:\n    branches: [main]\n  pull_request:\njobs: {}\n' > "$W/.github/workflows/ci.yml"
printf 'on: [push, pull_request_target]\njobs: {}\n' > "$W/.github/workflows/inline.yaml"
printf 'on:\n  workflow_dispatch:\njobs:\n  t:\n    if: github.event_name == '"'"'pull_request'"'"'\n' > "$W/.github/workflows/matrix.yml"
printf '"on": push\n# pull_request\n' > "$W/.github/workflows/push.yml"
out=$(cd "$W" && bash "$S" 2>&1); rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "workflows that run on every PR (each run costs CI minutes; cadence.md §4.12): ci.yml inline.yaml$" \
  && echo "$out" | grep -q "no precheck set: what a session can run" \
  && ok "PR workflows named from on: (block and inline, _target too), not from a job's if: or a comment; exit unchanged" || bad "pr workflows (rc=$rc): $out"
printf 'precheck = "make check"\n' > "$W/docs/cadence.toml"
out=$(cd "$W" && bash "$S" 2>&1)
echo "$out" | grep -q "precheck is set: keep in CI only what a session cannot easily run" && ok "…with precheck set, CI keeps what a session cannot run" || bad "pr workflows precheck: $out"
rm "$W/.github/workflows/ci.yml" "$W/.github/workflows/inline.yaml"
out=$(cd "$W" && bash "$S" 2>&1)
echo "$out" | grep -q "workflows that run on every PR: none" && ok "no PR workflow: says none" || bad "pr workflows none: $out"
out=$(cd "$W" && bash "$S" tester/thing 2>&1)
! echo "$out" | grep -q "workflows that run on every PR" && ok "a repo given by name: its workflows are not read from this checkout" || bad "pr workflows by name: $out"

echo; echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
