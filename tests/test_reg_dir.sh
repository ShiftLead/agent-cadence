#!/usr/bin/env bash
# TD-029: AGENT_CADENCE_REG_DIR isolates ONLY the machine roster. An ad-hoc run used to be told
# to point XDG_CONFIG_HOME at a temp dir, which also hid gh's credentials and broke the
# (since retired, TD-129) sync-all.sh at `gh pr create`. Every reader and writer of the roster
# honours the variable (cadence.md §9); without it the XDG path is unchanged. The one writer is
# `agent-cadence adopt`'s _register (launcher/words.py), sync.sh's last step until TD-129.
#
# Offline: a fixture consumer; HOME, XDG_CONFIG_HOME and git's global config are temp; the
# real roster is never read or written.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

T="$TMP/consumer"; git init -q -b main "$T"; git -C "$T" commit -q --allow-empty -m init
T="$(cd "$T" && pwd -P)"
mkdir -p "$T/docs"; cp "$DC/files/docs/user_attention.md" "$T/docs/user_attention.md"
REG="$TMP/reg"
# the writer, run as adopt runs it: $1 the repo; the environment as given
reg() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import words; words._register(sys.argv[2])' "$DC/launcher" "$1" 2>&1; }

# --- 1) the writer registers the target under AGENT_CADENCE_REG_DIR, and nowhere under XDG
CADENCE_TEMP_ROOTS=/nonexistent AGENT_CADENCE_REG_DIR="$REG" reg "$T" > "$TMP/reg.out"
grep -qxF "$T" "$REG/repos.txt" 2>/dev/null && ok "the writer wrote the roster under AGENT_CADENCE_REG_DIR" || bad "roster not in $REG: $(cat "$REG/repos.txt" 2>&1) / $(cat "$TMP/reg.out")"
[ ! -e "$XDG_CONFIG_HOME/agent-cadence/repos.txt" ] && ok "nothing written under XDG_CONFIG_HOME" || bad "XDG roster written: $(cat "$XDG_CONFIG_HOME/agent-cadence/repos.txt")"

# --- 2) the readers take the same file
out=$(AGENT_CADENCE_REG_DIR="$REG" python3 "$DC/files/scripts/nudge_user_attention.py" --report 2>&1)
grep -q "== consumer ($T/docs/user_attention.md)" <<< "$out" && ok "nudge --report reads the roster from AGENT_CADENCE_REG_DIR" || bad "nudge: $(head -3 <<< "$out")"
out=$(AGENT_CADENCE_REG_DIR="$REG" python3 "$DC/files/scripts/list_sessions.py" --roster 2>&1)
grep -q "No session transcripts found for: $T" <<< "$out" \
    && ok "list_sessions --roster reads the roster from AGENT_CADENCE_REG_DIR" || bad "list_sessions: $out"
# the memory guard's check #6, run: an open board item, a roster that lists the repo -> no roster
# warning; one that does not -> a warning naming IT
echo "- [ ] $(date +%F) (n/a) — an open item. Due: $(date +%F)." >> "$T/docs/user_attention.md"
REG2="$TMP/reg2"; mkdir -p "$REG2"; echo "$TMP/elsewhere" > "$REG2/repos.txt"
g1=$(CLAUDE_PROJECT_DIR="$T" AGENT_CADENCE_REG_DIR="$REG" bash "$DC/files/scripts/check_claude_memory.sh" 2>&1)
g2=$(CLAUDE_PROJECT_DIR="$T" AGENT_CADENCE_REG_DIR="$REG2" bash "$DC/files/scripts/check_claude_memory.sh" 2>&1)
! grep -q "roster" <<< "$g1" && grep -q "this machine's roster ($REG2/repos.txt) doesn't list this repo" <<< "$g2" \
    && ok "the memory guard's check #6 reads the roster from AGENT_CADENCE_REG_DIR (run, not grepped)" \
    || bad "memory guard: listed='$(grep roster <<< "$g1")' unlisted='$(grep roster <<< "$g2")'"

# --- 3) without it, the XDG path as before
CADENCE_TEMP_ROOTS=/nonexistent reg "$T" > "$TMP/reg2.out"
grep -qxF "$T" "$XDG_CONFIG_HOME/agent-cadence/repos.txt" 2>/dev/null && ok "unset: the roster is \${XDG_CONFIG_HOME}/agent-cadence/repos.txt, as before" || bad "unset: no XDG roster"

# --- 4) TD-068: a temp-dir repo is never written into a roster outside a temp dir. The suite
#        runs under /tmp, so CADENCE_TEMP_ROOTS names a fake temp root to test both sides.
FT="$TMP/faketmp"; mkdir -p "$FT"
F="$FT/fixture"; git init -q -b main "$F"; git -C "$F" commit -q --allow-empty -m init; F="$(cd "$F" && pwd -P)"
REAL="$TMP/realreg"
out=$(CADENCE_TEMP_ROOTS="$FT" AGENT_CADENCE_REG_DIR="$REAL" reg "$F"); rc=$?
[ $rc -eq 0 ] && ! grep -qxF "$F" "$REAL/repos.txt" 2>/dev/null && grep -q "WARN  $F is in a temp dir and $REAL/repos.txt is not — registration skipped" <<< "$out" \
    && ok "a temp-dir target is not appended to a non-temp roster (WARN, exit 0)" \
    || bad "temp target vs real roster: rc=$rc roster='$(cat "$REAL/repos.txt" 2>&1)' $out"
out=$(CADENCE_TEMP_ROOTS="$FT" AGENT_CADENCE_REG_DIR="$FT/reg" reg "$F")
grep -qxF "$F" "$FT/reg/repos.txt" 2>/dev/null && ok "the same target IS appended to a roster inside a temp dir" \
    || bad "temp target vs temp roster: $out"
out=$(CADENCE_TEMP_ROOTS="$FT" AGENT_CADENCE_REG_DIR="$REAL" reg "$T")
grep -qxF "$T" "$REAL/repos.txt" 2>/dev/null && ok "a target outside every temp root is appended as before" \
    || bad "non-temp target: $out"
# the predicate itself: inside, not yet made, the root itself yes; outside, a same-prefix sibling, a '/' root no
v=$(python3 - "$DC/launcher" "$FT" "$REAL" <<'PY2'
import os, sys
sys.path.insert(0, sys.argv[1]); import words
ft, real = sys.argv[2], sys.argv[3]
os.environ["CADENCE_TEMP_ROOTS"] = ft
r = "".join("T" if words._under_temp(p) else "-" for p in (ft + "/fixture", ft + "/new/not/yet", ft, real, ft + "x"))
os.environ["CADENCE_TEMP_ROOTS"] = "/"; r += "T" if words._under_temp("/etc") else "-"
os.environ["CADENCE_TEMP_ROOTS"] = ":" + ft + ":"; r += "T" if words._under_temp(ft + "/a") else "-"
print(r)
PY2
)
[ "$v" = "TTT---T" ] && ok "_under_temp: inside/missing/root itself yes; outside, a same-prefix sibling, and a '/' root no" \
    || bad "_under_temp verdicts: $v (want TTT---T)"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
