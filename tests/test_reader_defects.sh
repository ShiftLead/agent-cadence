#!/usr/bin/env bash
# TD-053: small reader defects in the silent-drop class (§7). A Due: that is written but not a
# date used to demote the item to "undated" with no word, in the mode that decides what a
# person is told at session start; list_sessions with no --repo indexed a worktree's own dir
# (or nothing, from a subdirectory); reads racing a session's exit could traceback.
#
# Offline, fixture-driven; HOME, XDG_CONFIG_HOME and git's global config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- 1) a malformed Due: is said out loud, in every mode
B="$TMP/b/docs"; mkdir -p "$B"
T0=$(date +%F)
cat > "$B/user_attention.md" <<EOF
# board

- [ ] $T0 (n/a) — typo date. Due: 2026-9-5.
- [ ] $T0 (n/a) — impossible date. Due: 2026-02-30.
- [ ] $T0 (n/a) — Due to a bug in prose, no field.
- [ ] $T0 (n/a) — missing colon. Due 2026-09-05.
- [ ] $T0 (n/a) — fix the reader so a malformed Due: is no longer silent.
EOF
out=$(python3 "$S/nudge_user_attention.py" --report --board "$B/user_attention.md" 2>&1)
grep -q "(⚠ unparseable due date 2026-9-5 — write Due: YYYY-MM-DD) .*typo date" <<< "$out" && grep -q "(⚠ unparseable due date 2026-02-30" <<< "$out" \
    && grep -q "(⚠ unparseable due date 2026-09-05 .*missing colon" <<< "$out" \
    && ok "full report: an unparseable Due: is tagged, not silently undated" || bad "report: $out"
grep -q "(no due date) .*Due to a bug in prose" <<< "$out" && grep -q "(no due date) .*a malformed Due: is no longer silent" <<< "$out" \
    && ok "prose that says 'Due to', or talks about the Due: field, is not a date" || bad "prose: $out"
out=$(python3 "$S/nudge_user_attention.py" --report --due-only --board "$B/user_attention.md" 2>&1)
grep -q "typo date" <<< "$out" && grep -q "impossible date" <<< "$out" && ! grep -q "Due to a bug" <<< "$out" \
    && ! grep -q "no longer silent" <<< "$out" && head -1 <<< "$out" | grep -q "3 with a due date that cannot be read" && ! head -1 <<< "$out" | grep -q "item(s) due" \
    && ok "SessionStart line: unreadable due dates shown and counted apart from due items" || bad "due-only: $out"
e=$(python3 "$S/nudge_user_attention.py" --report --json --board "$B/user_attention.md" 2>/dev/null | python3 -c 'import json,sys; print([i["due_error"] for i in json.load(sys.stdin)["boards"][0]["items"]])')
[ "$e" = "['2026-9-5', '2026-02-30', None, '2026-09-05', None]" ] && ok "--json carries due_error" || bad "json: $e"

# --- 2) list_sessions with no --repo, from a worktree subdirectory: the MAIN checkout
R="$TMP/repo"; git init -q -b main "$R"; git -C "$R" commit -q --allow-empty -m i
git -C "$R" worktree add -q "$R/.claude/worktrees/wt" -b wt; mkdir -p "$R/.claude/worktrees/wt/sub"
P="$HOME/.claude/projects/$(PYTHONPATH="$S" python3 -c 'import sys,list_sessions as L; from pathlib import Path; print(L.munge(Path(sys.argv[1])))' "$R")"
mkdir -p "$P"
printf '{"type":"user","timestamp":"%s","message":{"content":"work in the main checkout"}}\n{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n' "$(date -u +%FT%T.000Z)" > "$P/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
out=$(cd "$R/.claude/worktrees/wt/sub" && python3 "$S/list_sessions.py" 2>&1)
grep -q "started: work in the main checkout" <<< "$out" && ok "no --repo from a worktree subdirectory: indexes the main checkout's sessions" || bad "default repo: $out"

# --- 3) reads that race a session's exit degrade, never traceback
chk=$(PYTHONPATH="$S" python3 - "$TMP" <<'PY' 2>&1
import sys, pathlib, list_sessions as L
t = pathlib.Path(sys.argv[1])
assert L.scan_session(t / "gone.jsonl", 80) is None               # removed after the glob
(t / "brd" / "docs" / "user_attention.md").mkdir(parents=True)     # unreadable: a directory
assert L.board_items(t / "brd") == {}
print("OK")
PY
)
[ "$chk" = OK ] && ok "a transcript gone since the glob and an unreadable board: None / {}, no traceback" || bad "races: $chk"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
