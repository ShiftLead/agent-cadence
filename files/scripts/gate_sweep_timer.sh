#!/usr/bin/env bash
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/gate_sweep_timer.sh
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
#
# gate_sweep_timer.sh [--write] [REPO]  the systemd user units that run REPO's gate sweep daily: printed, or written
# gate_sweep_timer.sh --run REPO        what the timer runs: fetch REPO's origin, then gate_sweep.py --apply in it
#
# What runs a repo's gate sweep is the person's choice (cadence.md §2.14). Where they choose *daily, from
# a timer* (agent-cadence's own board, 2026-11-04), this makes the timer: a systemd user service and timer,
# agent-cadence-gate-sweep-<REPO's basename>.{service,timer}, OnCalendar=daily, Persistent (a day the
# machine was off runs at the next boot). REPO defaults to the clone of the current directory; a
# worktree's path is replaced by its main checkout's, since a worktree is reaped and the main checkout is not.
#
# - **Without --write** it prints the two units and writes nothing.
# - **With --write** it writes them under ${XDG_CONFIG_HOME:-~/.config}/systemd/user/ and prints the line
#   that enables the timer. **It never runs systemctl**: enabling a timer on the machine is the person's
#   step, run by hand. It refuses (exit 2) to replace a unit of that name that runs another repo's sweep.
#   The units bake in PATH as it is now, so the timer finds the same git, gh, python3 and launcher —
#   not credentials: a user service has no ssh agent or unlocked keyring, so an ssh origin needing an
#   agent, or a gh token kept only in a keyring, fails there (the journal says so on the first run).
#   A failed run (exit 1: the fetch before the network is up at boot, a forge error) is retried every
#   10 minutes, at most 4 starts in 2 hours; exit 2 (nothing to sweep) is not retried.
# - **--run REPO** is the service's command: `git fetch origin` in REPO (gate_sweep.py reads origin and
#   fetches nothing), then the sweep with --apply, which opens its PRs from temporary worktrees and never
#   touches REPO's checkout. A repo whose docs/cadence.toml pins agent-cadence (`[agent-cadence]`) runs
#   the pinned tree's gate_sweep.py through the launcher; agent-cadence's own clone, which has no pin, runs
#   its checkout's files/scripts/gate_sweep.py. A fetch that fails sweeps nothing (exit 1): a stale read
#   would file what is already closed. Items it files land under the session `gate-sweep`; its PRs are
#   reviewed and merged by sessions like any (cadence.md §4). Output goes to the journal
#   (`journalctl --user -u <unit>`). Its lifts sign with the machine's `host-alias` (cadence_config.py, TD-240),
#   which --write carries into the service as `CADENCE_HOST`; with none set the service has no such line, and
#   the sweep signs `gate-sweep` — never the machine's own name, which a lift branch publishes on its push.
#
# Exit 0 printed, written or swept; 1 the fetch or the sweep failed; 2 a usage error, REPO not a clone
# with a gate sweep, a path a unit cannot hold, or a unit of that name for another repo. Plain bash.
set -u

usage() { sed -n '5,6p' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2; exit 2; }

main_checkout() {  # the main checkout of the clone at $1, or nothing
    local c
    c="$(cd "$1" 2>/dev/null && d="$(git rev-parse --git-common-dir 2>/dev/null)" && cd "$d" && pwd -P)" || return 1
    [ "${c##*/}" = ".git" ] || return 1
    printf '%s\n' "${c%/*}"
}

pinned() { grep -qx '\[agent-cadence\]' "$1/docs/cadence.toml" 2>/dev/null; }

run() {
    local repo="$1"
    cd "$repo" 2>/dev/null || { echo "gate_sweep_timer: $repo: no such directory" >&2; exit 2; }
    if ! git fetch -q origin; then
        echo "gate_sweep_timer: git fetch origin failed in $repo — nothing swept (a stale read would file what is closed)" >&2
        exit 1
    fi
    if pinned "$repo"; then
        agent-cadence -C "$repo" run gate_sweep.py --apply
    elif [ -f "$repo/files/scripts/gate_sweep.py" ]; then
        python3 "$repo/files/scripts/gate_sweep.py" --apply
    else
        echo "gate_sweep_timer: $repo neither pins agent-cadence nor is its clone — no gate sweep to run" >&2
        exit 2
    fi
    local rc=$?
    [ "$rc" = 0 ] || exit 1
    exit 0
}

WRITE=0
REPO=""
case "${1:-}" in
    --run) [ $# = 2 ] || usage; run "$2" ;;
    -h|--help) usage ;;
esac
while [ $# -gt 0 ]; do
    case "$1" in
        --write) WRITE=1 ;;
        -*) usage ;;
        *) [ -z "$REPO" ] || usage; REPO="$1" ;;
    esac
    shift
done

repo="$(main_checkout "${REPO:-.}")" || { echo "gate_sweep_timer: ${REPO:-.} is not a checkout of a git clone" >&2; exit 2; }
case "$repo$PATH" in
    *%*|*\"*|*\\*|*\$*|*$'\n'*) echo "gate_sweep_timer: $repo or PATH holds a character a unit line cannot carry (% \" \\ \$ or a newline)" >&2; exit 2 ;;
esac
if pinned "$repo"; then
    launcher="$(command -v agent-cadence)" || { echo "gate_sweep_timer: $repo pins agent-cadence and no launcher is on PATH — install it first" >&2; exit 2; }
    exec_start="\"$launcher\" -C \"$repo\" run gate_sweep_timer.sh --run \"$repo\""
elif [ -f "$repo/files/scripts/gate_sweep_timer.sh" ] && [ -f "$repo/files/scripts/gate_sweep.py" ]; then
    exec_start="/usr/bin/env bash \"$repo/files/scripts/gate_sweep_timer.sh\" --run \"$repo\""
else
    echo "gate_sweep_timer: $repo neither pins agent-cadence nor is its clone — no gate sweep to run" >&2
    exit 2
fi

# The name the sweep signs its lifts with (TD-240): the machine's host-alias, carried into the unit as CADENCE_HOST;
# unset (or unreadable), no line, and gate_sweep.py signs `gate-sweep` — never the machine's own name.
alias="$(python3 "$(dirname "${BASH_SOURCE[0]}")/cadence_config.py" get host-alias 2>/dev/null)" || alias=""
env_host=""
[ -n "$alias" ] && env_host="Environment=\"CADENCE_HOST=$alias\"
"
name="agent-cadence-gate-sweep-$(basename "$repo" | tr -c 'A-Za-z0-9_.\n-' '_')"
service="[Unit]
Description=agent-cadence gate sweep of $repo (gate_sweep.py --apply)
# Written by gate_sweep_timer.sh (agent-cadence, TD-219's board line); rewrite it with that script.
StartLimitIntervalSec=2h
StartLimitBurst=4

[Service]
Type=oneshot
WorkingDirectory=$repo
Environment=\"PATH=$PATH\"
${env_host}ExecStart=$exec_start
TimeoutStartSec=30min
Restart=on-failure
RestartSec=10min
RestartPreventExitStatus=2
"
timer="[Unit]
Description=agent-cadence gate sweep of $repo, daily
# Written by gate_sweep_timer.sh (agent-cadence, TD-219's board line); rewrite it with that script.

[Timer]
OnCalendar=daily
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
"

if [ "$WRITE" = 0 ]; then
    printf '# %s.service\n%s\n# %s.timer\n%s' "$name" "$service" "$name" "$timer"
    echo "# nothing written: --write puts them under ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/"
    exit 0
fi

dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [ -f "$dir/$name.service" ] && ! grep -qxF "WorkingDirectory=$repo" "$dir/$name.service"; then
    echo "gate_sweep_timer: $dir/$name.service runs another repo's sweep ($(sed -n 's/^WorkingDirectory=//p' "$dir/$name.service")) — not replaced" >&2
    exit 2
fi
mkdir -p "$dir" || exit 2
printf '%s' "$service" > "$dir/$name.service" || exit 2
printf '%s' "$timer" > "$dir/$name.timer" || exit 2
echo "wrote $dir/$name.service and $dir/$name.timer"
echo "enable it (by hand — this script never runs systemctl):"
echo "  systemctl --user daemon-reload && systemctl --user enable --now $name.timer"
echo "check it: systemctl --user list-timers $name.timer; its runs: journalctl --user -u $name.service"
