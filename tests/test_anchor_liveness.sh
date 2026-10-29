#!/usr/bin/env bash
# Liveness-corroboration tests for scripts/check_anchor.py (cadence.md §1).
#
# The registry is a directory of pid-named files, and a pid only means something
# inside the namespace that issued it. Where ~/.claude is shared across
# namespaces (the host bind the cadence.md appendix describes carries sessions/ too),
# a dead entry's pid gets resolved against a DIFFERENT /proc, where low pids are
# readily in use by unrelated processes. These tests pin both directions:
# a recycled pid must not manufacture a conflict, and a genuinely live session
# must never be judged dead — the silent-permissive direction, which is the
# dangerous one, because a guard that stops warning looks exactly like health.
#
# Self-contained and machine-agnostic: HOME is overridden so the real registry
# is never read or written, and the "live process" stand-ins are spawned here.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$DC/files/scripts/check_anchor.py"
[ -f "$GUARD" ] || GUARD="$DC/scripts/check_anchor.py"   # consumer layout
TMP=$(mktemp -d)
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

cleanup() { [ -n "${PIDS:-}" ] && kill $PIDS 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
PIDS=""

export HOME="$TMP/home"
REG="$HOME/.claude/sessions"
mkdir -p "$REG"

REPO="$TMP/repo"
git init -q -b main "$REPO"
# HOME is overridden above, so git cannot read a global identity — pass one
# explicitly rather than depending on the runner's environment.
git -C "$REPO" -c user.email=test@example.invalid -c user.name=test \
    commit -q --allow-empty -m init

# A live process whose comm is NOT in the guard's allowlist...
sleep 300 & SLEEP_PID=$!; PIDS="$SLEEP_PID"
# ...and one whose comm IS ("node"), a symlink named `node` to python3 so the test
# needs no node install: comm follows the name exec'd (the link's basename), and
# python3 is already a test dependency. Not a copy of `sleep`: a multicall coreutils
# (uutils, Ubuntu 26.04's) picks its program by the name it was run as and refuses
# `node`. The link and the launch are separate statements on purpose: `ln ... && cmd &`
# backgrounds the whole compound, so $! would name the wrapping subshell — cleanup
# would kill that and orphan the sleeper, which then holds this script's stdout pipe
# open for the rest of its 300s under any output-capturing runner.
ln -s "$(command -v python3)" "$TMP/node"
"$TMP/node" -c 'import time; time.sleep(300)' & NODE_PID=$!
PIDS="$PIDS $NODE_PID"
sleep 1

ticks() { # $1=pid -> /proc/<pid>/stat field 22; split after the LAST ')' because
          # comm is parenthesized and may itself contain spaces or parens.
  local s; s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  printf '%s\n' "${s##*) }" | awk '{print $20}'
}

entry() { # $1=file $2=pid $3=cwd $4=startedAt-ms|null $5=procStart|null
  python3 - "$REG/$1.json" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
f, pid, cwd, started, ps = sys.argv[1:6]
o = {"sessionId": f"test{pid}", "pid": int(pid), "cwd": cwd}
if started != "null": o["startedAt"] = int(started)
if ps != "null":      o["procStart"] = ps
json.dump(o, open(f, "w"))
PY
}

run() { (cd "$REPO" && python3 "$GUARD" 2>&1); }
conflicts() { run | grep -q "ANCHOR CONFLICT"; }
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# --- 1) Recycled pid: live process, but procStart disagrees with the entry.
#        The exact-match primary must disprove it. Pre-fix this was a false conflict.
rm -f "$REG"/*.json
entry a "$SLEEP_PID" "$REPO" 1700000000000 12345
if conflicts; then bad "recycled pid (procStart mismatch) should NOT conflict"; else ok "recycled pid (procStart mismatch) dropped"; fi

# --- 2) THE SILENT-PERMISSIVE GUARD: live session whose comm is not in the
#        allowlist, but whose procStart matches exactly. Must still be reported.
#        A regression here makes the guard stop warning about real conflicts.
rm -f "$REG"/*.json
entry b "$SLEEP_PID" "$REPO" "$(now_ms)" "$(ticks "$SLEEP_PID")"
if conflicts; then ok "live session with non-allowlisted comm still conflicts (procStart exact match wins)"; else bad "live session judged dead — comm allowlist overrode an exact procStart match"; fi

# --- 3) Legacy entry (no procStart): start-time ordering decides. A session
#        writes its own entry, so a process that started long after it is a
#        recycled pid.
rm -f "$REG"/*.json
entry c "$SLEEP_PID" "$REPO" 1700000000000 null
if conflicts; then bad "legacy entry with ancient startedAt should NOT conflict"; else ok "legacy entry, process started long after entry -> dropped"; fi

# --- 4) Legacy entry, plausible start time, allowlisted comm -> kept.
rm -f "$REG"/*.json
entry d "$NODE_PID" "$REPO" "$(now_ms)" null
if conflicts; then ok "legacy entry with plausible startedAt kept"; else bad "legacy entry with plausible startedAt should conflict"; fi

# --- 5) Genuinely dead pid -> dropped by the existence check.
rm -f "$REG"/*.json
DEAD=$(python3 -c 'print(4194304)')   # above default pid_max; never live
entry e "$DEAD" "$REPO" "$(now_ms)" 999
if conflicts; then bad "nonexistent pid should NOT conflict"; else ok "nonexistent pid dropped"; fi

# --- 6) Malformed procStart must not crash and must fall through to the
#        start-time fallback rather than being treated as a match.
rm -f "$REG"/*.json
entry f "$SLEEP_PID" "$REPO" 1700000000000 "not-a-number"
if conflicts; then bad "malformed procStart + ancient startedAt should NOT conflict"; else ok "malformed procStart falls through to start-time fallback"; fi

# --- 7) The hook must never fail a session start, whatever the registry holds.
rm -f "$REG"/*.json
printf 'not json at all' > "$REG/garbage.json"
entry g "$SLEEP_PID" "$REPO" null null
(cd "$REPO" && python3 "$GUARD" >/dev/null 2>&1)
if [ $? -eq 0 ]; then ok "exits 0 with a corrupt registry present"; else bad "non-zero exit would break SessionStart"; fi

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
