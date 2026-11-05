#!/usr/bin/env bash
# gate_sweep_timer.sh: the systemd user units that run a repo's gate sweep daily (the board line decided
# "Daily, from a timer", 2026-11-04, TD-219). It prints them, writes them with --write and never runs
# systemctl, and --run (the service's command) fetches origin, then runs the sweep with --apply.
#
# Offline: origins are local bare repos; gate_sweep.py, agent-cadence and systemctl are PATH shims or stubs
# that log what they were asked. HOME, XDG_CONFIG_HOME and git config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$DC/files/scripts/gate_sweep_timer.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
UNITS="$XDG_CONFIG_HOME/systemd/user"

BIN="$TMP/bin"; mkdir -p "$BIN"
export LOG="$TMP/calls.log"; : > "$LOG"
cat > "$BIN/systemctl" <<'SHIM'
#!/usr/bin/env bash
echo "systemctl $*" >> "$LOG"
SHIM
cat > "$BIN/agent-cadence" <<'SHIM'
#!/usr/bin/env bash
echo "agent-cadence $* (cwd $(pwd -P))" >> "$LOG"
exit "${LAUNCHER_RC:-0}"
SHIM
chmod +x "$BIN/systemctl" "$BIN/agent-cadence"
NOLAUNCHER="/usr/bin:/bin"
export PATH="$BIN:$PATH"

# repo NAME [pinned]: a clone with a bare origin. Unpinned ones carry agent-cadence's files/scripts (a stub
# gate_sweep.py that logs its args and cwd); a pinned one carries `[agent-cadence]` in docs/cadence.toml.
repo() {
    local r="$TMP/$1"
    git init -q --bare -b main "$TMP/$1.git"
    git init -q -b main "$r"
    if [ "${2:-}" = pinned ]; then
        mkdir -p "$r/docs"; printf '[agent-cadence]\nref = "abc"\n' > "$r/docs/cadence.toml"
    else
        mkdir -p "$r/files/scripts"; cp "$T" "$r/files/scripts/gate_sweep_timer.sh"
        printf '#!/usr/bin/env python3\nimport os, sys\nopen(os.environ["LOG"], "a").write("gate_sweep.py %%s (cwd %%s)\\n" %% (" ".join(sys.argv[1:]), os.getcwd()))\nsys.exit(int(os.environ.get("SWEEP_RC", "0")))\n' > "$r/files/scripts/gate_sweep.py"
    fi
    git -C "$r" add -A && git -C "$r" commit -qm init
    git -C "$r" remote add origin "$TMP/$1.git" && git -C "$r" push -q origin main
}
repo canon
repo cons pinned
mkdir -p "$TMP/plain" && git init -q "$TMP/plain"

# --- print: the units, nothing written --------------------------------------------------------------
out=$(cd "$TMP/canon" && bash "$T"); rc=$?
[ "$rc" = 0 ] && ok "print exits 0" || bad "print rc=$rc: $out"
[ ! -e "$UNITS" ] && ok "print writes nothing" || bad "print wrote $UNITS"
grep -q '^# agent-cadence-gate-sweep-canon.service$' <<<"$out" && grep -q '^# agent-cadence-gate-sweep-canon.timer$' <<<"$out" \
    && ok "print names both units by the repo's basename" || bad "unit names: $out"
grep -qx 'OnCalendar=daily' <<<"$out" && grep -qx 'Persistent=true' <<<"$out" && grep -qx 'WantedBy=timers.target' <<<"$out" \
    && ok "the timer is daily and persistent" || bad "timer: $out"
grep -qxF "ExecStart=/usr/bin/env bash \"$TMP/canon/files/scripts/gate_sweep_timer.sh\" --run \"$TMP/canon\"" <<<"$out" \
    && ok "agent-cadence's own clone runs its checkout's script" || bad "canon ExecStart: $(grep ExecStart <<<"$out")"
grep -qxF "Environment=\"PATH=$PATH\"" <<<"$out" && ok "the unit carries PATH as it is now" || bad "PATH line: $(grep Environment <<<"$out")"

# from a worktree, the unit names the main checkout
git -C "$TMP/canon" worktree add -q "$TMP/canon-wt" -b wt
out=$(cd "$TMP/canon-wt" && bash "$T")
grep -qxF "WorkingDirectory=$TMP/canon" <<<"$out" && ! grep -q canon-wt <<<"$out" \
    && ok "a worktree's path is replaced by its main checkout's" || bad "worktree: $(grep -E 'WorkingDirectory|ExecStart' <<<"$out")"

# a pinned consumer runs through the launcher
out=$(bash "$T" "$TMP/cons"); rc=$?
grep -qxF "ExecStart=\"$BIN/agent-cadence\" -C \"$TMP/cons\" run gate_sweep_timer.sh --run \"$TMP/cons\"" <<<"$out" \
    && ok "a pinned repo runs the pinned tree's script through the launcher" || bad "cons rc=$rc ExecStart: $(grep ExecStart <<<"$out")"
out=$(PATH="$NOLAUNCHER" bash "$T" "$TMP/cons" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'no launcher' <<<"$out" && ok "a pinned repo with no launcher on PATH is refused" || bad "no launcher rc=$rc: $out"

# no gate sweep, no clone, a path a unit cannot carry
out=$(bash "$T" "$TMP/plain" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'no gate sweep' <<<"$out" && ok "a repo with no gate sweep is refused" || bad "plain rc=$rc: $out"
out=$(bash "$T" "$TMP/nowhere" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "a path that is no clone is refused" || bad "nowhere rc=$rc: $out"
mkdir -p "$TMP/pct%x" && git init -q "$TMP/pct%x"
out=$(bash "$T" "$TMP/pct%x" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'cannot carry' <<<"$out" && ok "a path with % is refused" || bad "pct rc=$rc: $out"
out=$(bash "$T" --bogus 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q -- '--run REPO' <<<"$out" && ok "an unknown flag prints usage, exit 2" || bad "usage rc=$rc: $out"

# --- --write: the files, the enable line, never systemctl ---------------------------------------------
out=$(bash "$T" --write "$TMP/canon"); rc=$?
[ "$rc" = 0 ] && [ -f "$UNITS/agent-cadence-gate-sweep-canon.service" ] && [ -f "$UNITS/agent-cadence-gate-sweep-canon.timer" ] \
    && ok "--write writes both units under XDG_CONFIG_HOME" || bad "--write rc=$rc: $out"
grep -qF "systemctl --user daemon-reload && systemctl --user enable --now agent-cadence-gate-sweep-canon.timer" <<<"$out" \
    && ok "--write prints the enable line" || bad "enable line: $out"
[ ! -s "$LOG" ] && ok "--write never runs systemctl" || bad "calls: $(cat "$LOG")"
diff <(bash "$T" "$TMP/canon" | sed -n '/^# agent-cadence-gate-sweep-canon.service$/,/^# agent-cadence-gate-sweep-canon.timer$/p' | sed '1d;$d') \
     <(cat "$UNITS/agent-cadence-gate-sweep-canon.service"; echo) >/dev/null \
    && ok "the written service is what print shows" || bad "written service differs from print"
out=$(bash "$T" --write "$TMP/canon"); rc=$?
[ "$rc" = 0 ] && ok "--write again over its own units is fine" || bad "rewrite rc=$rc: $out"

# another repo of the same basename is not allowed to take the unit over
git init -q -b main "$TMP/other/canon" && mkdir -p "$TMP/other/canon/files/scripts" \
    && cp "$T" "$TMP/canon/files/scripts/gate_sweep.py" "$TMP/other/canon/files/scripts/"
before=$(cat "$UNITS/agent-cadence-gate-sweep-canon.service")
out=$(bash "$T" --write "$TMP/other/canon" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "another repo's sweep" <<<"$out" && [ "$before" = "$(cat "$UNITS/agent-cadence-gate-sweep-canon.service")" ] \
    && ok "a unit for another repo of the same name is not replaced" || bad "collision rc=$rc: $out"

# --- --run: fetch, then the sweep with --apply ----------------------------------------------------------
# a commit lands on origin from elsewhere; --run must fetch it before sweeping
git clone -q -b main "$TMP/canon.git" "$TMP/pusher" && git -C "$TMP/pusher" commit -q --allow-empty -m later && git -C "$TMP/pusher" push -q origin main
new=$(git -C "$TMP/pusher" rev-parse HEAD)
: > "$LOG"
out=$(cd / && bash "$T" --run "$TMP/canon" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "--run exits 0 when the sweep does" || bad "--run rc=$rc: $out"
[ "$(git -C "$TMP/canon" rev-parse origin/main)" = "$new" ] && ok "--run fetches origin first" || bad "origin/main not fetched"
grep -qxF "gate_sweep.py --apply (cwd $TMP/canon)" "$LOG" && ok "--run runs the clone's gate_sweep.py --apply in the repo" || bad "calls: $(cat "$LOG")"

: > "$LOG"
out=$(SWEEP_RC=1 bash "$T" --run "$TMP/canon" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "a sweep that fails is exit 1" || bad "sweep fail rc=$rc: $out"

: > "$LOG"
out=$(bash "$T" --run "$TMP/cons" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qxF "agent-cadence -C $TMP/cons run gate_sweep.py --apply (cwd $TMP/cons)" "$LOG" \
    && ok "a pinned repo's --run sweeps through the launcher" || bad "cons --run rc=$rc: $(cat "$LOG") $out"
: > "$LOG"
out=$(LAUNCHER_RC=2 bash "$T" --run "$TMP/cons" 2>&1); rc=$?
[ "$rc" = 1 ] && ok "a launcher failure is exit 1" || bad "launcher fail rc=$rc: $out"

# a fetch that fails sweeps nothing
git -C "$TMP/canon" remote set-url origin "$TMP/gone.git"
: > "$LOG"
out=$(bash "$T" --run "$TMP/canon" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'nothing swept' <<<"$out" && [ ! -s "$LOG" ] && ok "a failed fetch sweeps nothing, exit 1" || bad "fetch fail rc=$rc: $out / $(cat "$LOG")"
out=$(bash "$T" --run "$TMP/plain" 2>&1); rc=$?
[ "$rc" = 1 ] || [ "$rc" = 2 ] && ok "--run on a repo with no origin or sweep is not exit 0" || bad "plain --run rc=$rc: $out"
out=$(bash "$T" --run 2>&1); rc=$?
[ "$rc" = 2 ] && ok "--run with no repo is a usage error" || bad "--run alone rc=$rc"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
