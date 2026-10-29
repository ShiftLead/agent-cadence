#!/usr/bin/env bash
# TD-050: runtime canaries for the undocumented Claude Code internals the system reads. A
# changed session-registry or transcript format used to degrade every reader to "nothing
# found" without a word. Offline: HOME is a temp dir holding fixture registries/transcripts.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME/.claude/sessions" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
REG="$HOME/.claude/sessions"
anchor() { (cd "$TMP" && python3 "$S/check_anchor.py" 2>&1); }

# --- 1) the session registry: judged by its newest SETTLED entry (older than 5 s)
old() { touch -d "$1" "$2"; }
[ -z "$(anchor | grep 'registry')" ] && ok "an empty registry: no warning (nothing to judge)" || bad "empty: $(anchor)"
echo '{"sessionId": "11111111-2222", "pid": 999999, "cwd": "/nowhere"}' > "$REG/1.json"; old '10 minutes ago' "$REG/1.json"
[ -z "$(anchor | grep 'registry')" ] && ok "the newest entry in the known format: no warning" || bad "healthy: $(anchor)"
echo '{"id": "abc", "processId": 2}' > "$REG/2.json"; old '1 minute ago' "$REG/2.json"
anchor | grep -q "the newest entry in Claude Code's session registry (.*2.json) does not read as a session" \
    && ok "a newer entry in a changed format: warned — an older healthy entry does not mask it" || bad "masking: $(anchor)"
rm -f "$REG"/*.json
echo '{"sessionId": "11111111-2222", "pid": 999999}' > "$REG/1.json"; old '10 minutes ago' "$REG/1.json"
printf '{"sessionId": "torn' > "$REG/3.json"          # being written right now: too young to judge
[ -z "$(anchor | grep 'registry')" ] && ok "a torn entry younger than 5 s (a session starting now) is not judged" || bad "fresh torn: $(anchor)"
old '1 minute ago' "$REG/3.json"
anchor | grep -q "does not read as a session" && ok "the same torn entry, settled and newest: warned" || bad "settled torn: $(anchor)"
rm -f "$REG"/*.json

# --- 2) transcripts: files present, none readable -> say so
R="$TMP/repo"; mkdir -p "$R"
P="$HOME/.claude/projects/$(PYTHONPATH="$S" python3 -c 'import sys,list_sessions as L; from pathlib import Path; print(L.munge(Path(sys.argv[1])))' "$R")"
mkdir -p "$P"
echo '{"kind": "turn", "role": "human", "text": "a new format"}' > "$P/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
out=$(python3 "$S/list_sessions.py" --repo "$R" 2>&1)
grep -q "note: 1 transcript file(s) found and none had a readable user or assistant message — they hold only commands, or" <<< "$out" \
    && ok "transcripts in an unknown format: the index says so instead of printing nothing" || bad "transcripts: $out"
printf '{"type":"user","message":{"content":"hello"}}\n{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}\n' > "$P/bbbbbbbb-1111-2222-3333-444444444444.jsonl"
out=$(python3 "$S/list_sessions.py" --repo "$R" 2>&1)
! grep -q "none had a readable" <<< "$out" && ok "one readable transcript: no note" || bad "readable: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
