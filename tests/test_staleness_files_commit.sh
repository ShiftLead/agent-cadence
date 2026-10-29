#!/usr/bin/env bash
# TD-035, for a pin (TD-169): the "cadence pin behind" line must not fire on an upstream commit
# that changes nothing a pinned repo runs. A dev-cadence clone on the roster, fetched to the
# remote's tip, answers whether upstream's last commit touching files/, launcher/ or sync.sh is
# in the pin; without one the fallback is the remote HEAD, worded as uncertain. A repo that still
# carries docs/cadence-sync.lock and no pin is told to move to a pin.
#
# Offline: the "upstream" is a local repo whose origin URL is only a string (its
# refs/remotes/origin/main is set by hand); the fallback's ls-remote is intercepted in
# process. HOME, XDG_CONFIG_HOME, DEV_CADENCE_REG_DIR and git's global config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
URL="https://example.invalid/o/dev-cadence"

# the local dev-cadence clone
U="$TMP/dc"; git init -q -b main "$U"; mkdir -p "$U/files/docs" "$U/docs"
echo a > "$U/files/docs/cadence.md"; echo s > "$U/sync.sh"; echo l > "$U/docs/technical_debt.md"
git -C "$U" add -A; git -C "$U" commit -qm c1; git -C "$U" remote add origin "$URL"
C1=$(git -C "$U" rev-parse HEAD); git -C "$U" update-ref refs/remotes/origin/main HEAD
echo "$U" > "$DEV_CADENCE_REG_DIR/repos.txt"
# a consumer pinned at C1
B="$TMP/consumer/docs"; mkdir -p "$B"; echo "# board" > "$B/user_attention.md"
pin() { printf '# why: the settings\n[dev-cadence]\nsource = "%s"\nref = "%s"\n' "$URL" "$1" > "$B/cadence.toml"; }
pin "$C1"

line() {  # line [fake ls-remote tip]: staleness_line() for the consumer's board; by default
          # the remote's tip IS the clone's origin/main (the clone is up to date)
    python3 - "$DC/files/scripts/nudge_user_attention.py" "$B/user_attention.md" "${1:-$(git -C "$U" rev-parse refs/remotes/origin/main)}" <<'PY'
import importlib.util, pathlib, subprocess, sys
spec = importlib.util.spec_from_file_location("nudge", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
fake = sys.argv[3]
real = subprocess.run
def run(cmd, *a, **k):
    if "ls-remote" in cmd:          # never the network: the fallback's answer, by hand
        return subprocess.CompletedProcess(cmd, 0 if fake else 2, (fake + "\tHEAD\n").encode() if fake else b"", b"")
    return real(cmd, *a, **k)
mod.subprocess.run = run
print(mod.staleness_line(pathlib.Path(sys.argv[2])) or "NONE")
PY
}

[ "$(line)" = NONE ] && ok "in step: no line" || bad "in step: $(line)"
echo more >> "$U/docs/technical_debt.md"; git -C "$U" commit -qam "ledger only"; git -C "$U" update-ref refs/remotes/origin/main HEAD
[ "$(line)" = NONE ] && ok "an upstream commit touching only the ledger: still no line" || bad "ledger-only fired: $(line)"
mkdir -p "$U/launcher"; echo w > "$U/launcher/words.py"; git -C "$U" add -A; git -C "$U" commit -qm "a launcher change"
echo b >> "$U/files/docs/cadence.md"; git -C "$U" commit -qam "a payload change"; git -C "$U" update-ref refs/remotes/origin/main HEAD
C4=$(git -C "$U" rev-parse HEAD)
out=$(line); grep -q "cadence pin behind (2 payload commit(s) since the pin ${C1:0:8} → upstream ${C4:0:8}): move it with a .dev-cadence bump. PR" <<< "$out" \
    && ok "upstream commits touching files/ and launcher/: the line fires, counting both, naming the bump" || bad "payload change: $out"
pin "$C4"
[ "$(line)" = NONE ] && ok "pinned at the latest payload commit: no line" || bad "bumped: $(line)"
echo more >> "$U/docs/technical_debt.md"; git -C "$U" commit -qam "ledger after"; git -C "$U" update-ref refs/remotes/origin/main HEAD
[ "$(line)" = NONE ] && ok "a pin behind upstream's tip by a ledger commit only: no line" || bad "ledger after pin: $(line)"
pin "$C1"
# the clone was never re-fetched: the remote is ahead of its origin/main — it must not answer
T=$(git -C "$U" rev-parse HEAD); git -C "$U" update-ref refs/remotes/origin/main "$C1"
out=$(line "$T"); grep -q "cadence upstream moved" <<< "$out" \
    && ok "a stale (unfetched) clone is not trusted: the uncertain fallback, never a false 'in step'" || bad "stale clone: $out"
git -C "$U" update-ref refs/remotes/origin/main "$T"
# a pin the clone does not hold: the fallback, never a false answer
pin 0123456789abcdef0123456789abcdef01234567
out=$(line); grep -q "cadence upstream moved (pin 01234567" <<< "$out" && ok "a pin the clone lacks: the fallback" || bad "unknown pin: $out"
pin "$C1"

# no clone on the roster: the remote-HEAD fallback, worded as uncertain
: > "$DEV_CADENCE_REG_DIR/repos.txt"
out=$(line 0123456789abcdef0123456789abcdef01234567)
grep -q "cadence upstream moved (pin ${C1:0:8} → upstream 01234567) — possibly only files outside the payload; .dev-cadence bump. with no argument lists what is new" <<< "$out" \
    && ok "no clone: the HEAD fallback says it cannot tell and points at bump" || bad "fallback: $out"
[ "$(line "$C1")" = NONE ] && ok "no clone, the remote's HEAD is the pin: no line" || bad "fallback at pin: $(line "$C1")"
echo "$U" > "$DEV_CADENCE_REG_DIR/repos.txt"

# a synced repo (a lock, no pin): nothing syncs it any more, whatever upstream holds
rm "$B/cadence.toml"; printf 'source: %s\ncommit: %s\nfiles_commit: %s\n' "$URL" "$C1" "$C1" > "$B/cadence-sync.lock"
out=$(line); grep -q "still carries synced cadence copies (docs/cadence-sync.lock).*sync.sh --pin <repo>. moves it to a pin" <<< "$out" \
    && ok "a lock and no pin: the line says move it to a pin" || bad "lock: $out"
rm "$B/cadence-sync.lock"
[ "$(line)" = NONE ] && ok "neither a pin nor a lock (dev-cadence's own repo): no line" || bad "neither: $(line)"
printf '[dev-cadence\n' > "$B/cadence.toml"
[ "$(line)" = NONE ] && ok "an unreadable cadence.toml: no line, no traceback" || bad "bad toml: $(line)"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
