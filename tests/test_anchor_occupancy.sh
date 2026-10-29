#!/usr/bin/env bash
# Occupancy tests for scripts/check_anchor.py's occupies() (cadence.md §1).
#
# The anchor unit is the CHECKOUT, not the directory tree. An independent repo
# nested inside another repo's working dir — a sibling clone under an umbrella
# repo, a submodule, a vendored or gitignored subproject — shares no HEAD,
# index, or working files, so a session there collides with nothing in the outer
# checkout. Path nesting alone reported it as an occupant, and the outer session
# was told to abandon a checkout it exclusively owned.
#
# The other direction is pinned too: when the repo root cannot be determined
# (git failed, or the cwd has since been deleted) the entry stays an occupant.
# This check exists to remove false CONFLICTS; inventing false CLEARANCES would
# trade a visible annoyance for a silent one.
#
# Registry entries carry procStart and a fresh startedAt so the suite behaves
# identically before and after the liveness-corroboration change lands.
#
# Self-contained and machine-agnostic: HOME is overridden so the real registry
# is never read or written, and the live process is spawned here.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$DC/files/scripts/check_anchor.py"
[ -f "$GUARD" ] || GUARD="$DC/scripts/check_anchor.py"   # consumer layout
TMP=$(mktemp -d)
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

cleanup() { [ -n "${HELPER:-}" ] && kill "$HELPER" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
HELPER=""

export HOME="$TMP/home"
REG="$HOME/.claude/sessions"
mkdir -p "$REG"
GIT="git -c user.email=test@example.invalid -c user.name=test -c protocol.file.allow=always"

# Outer checkout, with every nesting shape that matters underneath it.
ROOT="$TMP/outer"
$GIT init -q -b main "$ROOT"
mkdir -p "$ROOT/subdir"
echo x > "$ROOT/subdir/f"; $GIT -C "$ROOT" add -A >/dev/null 2>&1
$GIT -C "$ROOT" commit -q -m init

# an independent repo that merely lives inside the outer working dir
INDEP="$ROOT/nested-independent"
$GIT init -q -b main "$INDEP"; $GIT -C "$INDEP" commit -q --allow-empty -m init

# a real submodule
SUBSRC="$TMP/submodule-src"
$GIT init -q -b main "$SUBSRC"; $GIT -C "$SUBSRC" commit -q --allow-empty -m init
$GIT -C "$ROOT" submodule add -q "$SUBSRC" sub >/dev/null 2>&1
$GIT -C "$ROOT" commit -q -m addsub >/dev/null 2>&1

# a worktree of the OUTER repo, in the location cadence.md reserves for them
$GIT -C "$ROOT" worktree add -q ".claude/worktrees/wt1" -b wt1 >/dev/null 2>&1

# stand-in for a live Claude Code process
sleep 300 >/dev/null 2>&1 & HELPER=$!
sleep 1
STAT=$(cat "/proc/$HELPER/stat"); TICKS=$(printf '%s\n' "${STAT##*) }" | awk '{print $20}')

entry() { # $1=cwd
  python3 - "$REG/e.json" "$HELPER" "$1" "$TICKS" <<'PY'
import json, sys, time
f, pid, cwd, ticks = sys.argv[1:5]
json.dump({"sessionId": "occupancy-test", "pid": int(pid), "cwd": cwd,
           "startedAt": int(time.time() * 1000), "procStart": ticks}, open(f, "w"))
PY
}
conflicts() { (cd "$ROOT" && python3 "$GUARD" 2>&1) | grep -q "ANCHOR CONFLICT"; }

# --- 1) THE HEADLINE FIX: a separate repo nested in the working dir.
entry "$INDEP"
if conflicts; then bad "nested independent repo must NOT occupy the outer checkout"; else ok "nested independent repo is not an occupant"; fi

# --- 2) A submodule is its own checkout for the same reason.
entry "$ROOT/sub"
if conflicts; then bad "submodule must NOT occupy the outer checkout"; else ok "submodule is not an occupant"; fi

# --- 3) An ordinary subdirectory of the SAME repo still shares everything.
entry "$ROOT/subdir"
if conflicts; then ok "same-repo subdirectory still occupies"; else bad "same-repo subdirectory must still conflict"; fi

# --- 4) A second session at the root itself.
entry "$ROOT"
if conflicts; then ok "second session at the checkout root still occupies"; else bad "session at root must still conflict"; fi

# --- 5) Worktrees are the isolation unit, so they are exempt.
entry "$ROOT/.claude/worktrees/wt1"
if conflicts; then bad "worktree under .claude/worktrees must NOT occupy"; else ok "worktree under .claude/worktrees is exempt"; fi

# --- 6) UNDETERMINABLE KEEPS: a cwd that no longer exists must stay an
#        occupant. Clearing it would be a silent false negative.
entry "$ROOT/since-deleted"
if conflicts; then ok "deleted cwd stays an occupant (undeterminable keeps)"; else bad "deleted cwd was silently cleared — false clearance"; fi

# --- 7) Somewhere else entirely on disk.
entry "$TMP/unrelated"
if conflicts; then bad "path outside the checkout must NOT occupy"; else ok "path outside the checkout is not an occupant"; fi

# --- 8) The conflict report names the cwd, so a surprising warning can be
#        diagnosed rather than guessed at.
entry "$ROOT/subdir"
if (cd "$ROOT" && python3 "$GUARD" 2>&1) | grep -q "in $ROOT/subdir"; then ok "conflict report names the occupying cwd"; else bad "conflict report omits the cwd"; fi

# --- 9) Cost is bounded: occupancy lookups are memoized and budgeted, so a large
#        registry cannot turn SessionStart into a serial run of git calls.
rm -f "$REG"/*.json
python3 - "$REG" "$HELPER" "$ROOT/subdir" "$TICKS" <<'PY'
import json, sys, time
reg, pid, cwd, ticks = sys.argv[1:5]
for i in range(200):
    json.dump({"sessionId": f"bulk{i:05d}", "pid": int(pid), "cwd": cwd,
               "startedAt": int(time.time() * 1000), "procStart": ticks},
              open(f"{reg}/b{i}.json", "w"))
PY
t0=$(python3 -c 'import time; print(time.time())')
(cd "$ROOT" && python3 "$GUARD" >/dev/null 2>&1)
t1=$(python3 -c 'import time; print(time.time())')
elapsed=$(python3 -c "print(int(($t1-$t0)*1000))")
if [ "$elapsed" -lt 3000 ]; then ok "200-entry registry resolved in ${elapsed}ms (<3000ms)"; else bad "200-entry registry took ${elapsed}ms — occupancy lookups are not bounded"; fi

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
