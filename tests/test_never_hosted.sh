#!/usr/bin/env bash
# TD-28: "no deep sweep on record" is a real gap for a repo whose sessions nobody swept, and
# nothing to do for one where no session has ever run on this machine. The
# report says which. Offline: HOME is a temp dir holding (or not) a transcript fixture.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"; git init -q "$R"; mkdir -p "$R/docs"
printf '# board\n\nSwept: %s (testhost, quick)\n\n- [ ] %s (n/a) — item.\n' "$(date +%F)" "$(date +%F)" > "$R/docs/user_attention.md"
echo "$R" > "$AGENT_CADENCE_REG_DIR/repos.txt"
rep() { python3 "$S/nudge_user_attention.py" --report 2>&1; }

# TD-100: with the default agents (claude) and no ~/.claude/projects at all, the adapter
# cannot look — that is "cannot tell", so the warning stands
out=$(rep)
grep -q "⚠ no deep sweep on record (quick sweeps only)" <<< "$out" \
    && ok "no Claude transcript store at all: cannot tell, the warning stands (TD-100)" || bad "no store: $out"
mkdir -p "$HOME/.claude/projects"
out=$(rep)
grep -q "ℹ no deep sweep on record — and no session has run in this repo on this machine" <<< "$out" && ! grep -q "⚠ no deep sweep" <<< "$out" \
    && ok "no session ever ran here: an information line, not a warning" || bad "never hosted: $out"
j=$(python3 "$S/nudge_user_attention.py" --report --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["boards"][0]["sweep"][:1])')
[ "$j" = "ℹ" ] && ok "--json carries the same distinction" || bad "json: $j"

M="$HOME/.claude/projects/$(PYTHONPATH="$S" python3 -c 'import sys,list_sessions as L; from pathlib import Path; print(L.munge(Path(sys.argv[1]).resolve()))' "$R")"
for where in "--claude-worktrees-topic" "-some-subdir"; do
    rm -rf "$HOME/.claude/projects"; mkdir -p "$M$where"; echo '{"type":"user","message":{"content":"x"}}' > "$M$where/s.jsonl"
    out=$(rep)
    grep -q "⚠ no deep sweep on record (quick sweeps only)" <<< "$out" \
        && ok "a session ran here (${where#-}) and nobody deep-swept: the warning stands" || bad "hosted ($where): $out"
done
# a tool listed in `agents` with no backend: cannot tell, even with a Claude store that says never
rm -rf "$HOME/.claude/projects"; mkdir -p "$HOME/.claude/projects"
out=$(CADENCE_AGENTS="claude, othertool" rep)
grep -q "⚠ no deep sweep on record (quick sweeps only)" <<< "$out" \
    && ok "agents names a tool with no backend: the warning stands (TD-100)" || bad "unknown tool: $out"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
