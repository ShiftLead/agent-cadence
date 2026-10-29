#!/usr/bin/env bash
# TD-133: a ledger or board that declares a newer major of the formats (`Ledgerboard: N` on a
# preamble line, ledgerboard SPEC *Versions*) is read by no agent-cadence script — each refuses by
# name rather than misread it. Offline and fixture-driven: HOME, XDG_CONFIG_HOME and the roster
# (AGENT_CADENCE_REG_DIR) point into a temp dir; origins are temp bare repos.
# Asserts, per reader: ledger.py (the ledger, the archive, a cross-repo blocker's ledger),
# ledger_next_id.py (main's ledger), board_edit.py, nudge_user_attention.py (--report text and
# --json, --due-only, nudge mode), check_cadence.py's ledger row; and that `Ledgerboard: 1`,
# declared or not, reads as before.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset USER_ATTENTION_BOARD TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID NUDGE_COMMAND
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)

ledger() {  # $1 major line ("" for none), $2 an id
  printf '# Technical Debt\n\n%s\n\n| ID | Title | Priority | Status |\n|---|---|---|---|\n| %s | x | medium | Open |\n\n## %s: x\n\n**Priority:** medium\n**Added:** %s\n**Status:** Open\n**Location:** x\n\n**Why:** x\n\n**Fix:** x\n' "$1" "$2" "$2" "$TODAY"
}
board() {  # $1 major line
  printf '# User attention\n\n%s\n\n- [ ] act %s (session t) — something due. Due: %s.\n' "$1" "$TODAY" "$TODAY"
}

# --- ledger.py: the ledger, the archive
R="$TMP/r"; mkdir -p "$R/docs"; git init -q -b main "$R"
ledger "Ledgerboard: 3" TD-001 > "$R/docs/technical_debt.md"
out=$(cd "$R" && python3 "$S/ledger.py" --pickable 2>&1); rc=$?
[ "$rc" = 2 ] && grep -qF "ledger: not read — $R/docs/technical_debt.md: this file declares Ledgerboard: 3" <<< "$out" \
  && ok "1 ledger.py --pickable: a newer ledger is refused by name, exit 2" || bad "1 rc=$rc '$out'"
out=$(cd "$R" && python3 "$S/ledger.py" --check 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "not read" <<< "$out" && ok "1b ledger.py --check: the same" || bad "1b rc=$rc '$out'"
ledger "Ledgerboard: 1" TD-001 > "$R/docs/technical_debt.md"
printf '# Archive\n\nLedgerboard: 4\n' > "$R/docs/technical_debt_archive.md"
out=$(cd "$R" && python3 "$S/ledger.py" --pickable 2>&1); rc=$?
[ "$rc" = 2 ] && grep -qF "technical_debt_archive.md: this file declares Ledgerboard: 4" <<< "$out" && ok "2 a newer archive is refused too" || bad "2 rc=$rc '$out'"
rm "$R/docs/technical_debt_archive.md"
out=$(cd "$R" && python3 "$S/ledger.py" --pickable 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "TD-001" <<< "$out" && ok "3 Ledgerboard: 1 declared reads as before" || bad "3 rc=$rc '$out'"
ledger "" TD-001 > "$R/docs/technical_debt.md"
out=$(cd "$R" && python3 "$S/ledger.py" --pickable 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "TD-001" <<< "$out" && ok "3b no version line reads as 1" || bad "3b rc=$rc '$out'"

# --- ledger.py: a cross-repo blocker whose ledger is newer stays blocked, and says why
B="$TMP/other"; mkdir -p "$B/docs"; git init -q -b main "$B"
ledger "Ledgerboard: 3" TD-005 > "$B/docs/technical_debt.md"
echo "$B" > "$AGENT_CADENCE_REG_DIR/repos.txt"
ledger "" TD-002 | sed 's/^\*\*Status:\*\* Open$/**Status:** Open\n**Blocked by:** other#TD-005/' > "$R/docs/technical_debt.md"
grep -q "other#TD-005" "$R/docs/technical_debt.md" || printf 'fixture: no Blocked by line\n'
out=$(cd "$R" && python3 "$S/ledger.py" --pickable --json 2>&1); rc=$?
python3 -c "import json,sys; d=json.loads(sys.argv[1]); s=json.dumps(d); sys.exit(0 if 'TD-002' in s and 'Ledgerboard: 3' in s else 1)" "$out" 2>/dev/null \
  && ! python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if any(e.get('id')=='TD-002' for e in d.get('pickable',[])) else 1)" "$out" 2>/dev/null \
  && ok "4 a blocker in a newer-format ledger keeps the block, and the why names it" || bad "4 rc=$rc '${out:0:600}'"

# --- ledger_next_id.py: main's ledger in a newer format, no id handed out
O="$TMP/origin.git"; git init -q --bare -b main "$O"
C="$TMP/clone"; git clone -q "$O" "$C" 2>/dev/null; mkdir -p "$C/docs"
ledger "Ledgerboard: 3" TD-009 > "$C/docs/technical_debt.md"
git -C "$C" add -A && git -C "$C" commit -qm l && git -C "$C" push -q origin main 2>/dev/null
out=$(cd "$C" && timeout 60 python3 "$S/ledger_next_id.py" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -qF "refused — not read — refs/remotes/origin/main:docs/technical_debt.md: this file declares Ledgerboard: 3" <<< "$out" \
  && ! grep -qE "^TD-" <<< "$out" && ok "5 ledger_next_id.py: main's newer ledger, exit 2, no id" || bad "5 rc=$rc '$out'"

# --- board_edit.py: refused, the board untouched
BD="$TMP/b"; mkdir -p "$BD/docs"; git init -q -b main "$BD"
board "Ledgerboard: 3" > "$BD/docs/user_attention.md"
before=$(cat "$BD/docs/user_attention.md")
out=$(python3 "$S/board_edit.py" done --board "$BD/docs/user_attention.md" --line 5 --expect "act" --why x --no-commit 2>&1); rc=$?
[ "$rc" = 3 ] && grep -qF "this file declares Ledgerboard: 3" <<< "$out" && [ "$before" = "$(cat "$BD/docs/user_attention.md")" ] \
  && ok "6 board_edit.py: refused (exit 3), the board untouched" || bad "6 rc=$rc '$out'"
board "Ledgerboard: 1" > "$BD/docs/user_attention.md"
python3 "$S/board_edit.py" done --board "$BD/docs/user_attention.md" --line 5 --expect "act" --why x --no-commit >/dev/null 2>&1 \
  && grep -q "^- \[x\]" "$BD/docs/user_attention.md" && ok "6b Ledgerboard: 1: edited as before" || bad "6b $(cat "$BD/docs/user_attention.md")"

# --- nudge_user_attention.py: the report (text, --json, --due-only) and nudge mode
board "Ledgerboard: 3" > "$BD/docs/user_attention.md"
NU="$S/nudge_user_attention.py"
out=$(python3 "$NU" --report --board "$BD/docs/user_attention.md" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qF "⚠ not read: $BD/docs/user_attention.md: this file declares Ledgerboard: 3" <<< "$out" && ! grep -q "something due" <<< "$out" \
  && ok "7 --report: the board named in place of its items" || bad "7 rc=$rc '$out'"
out=$(python3 "$NU" --report --json --board "$BD/docs/user_attention.md" 2>&1)
python3 -c "import json,sys; r=json.loads(sys.argv[1])['boards'][0]; sys.exit(0 if r['note'].startswith('not read: ') and 'Ledgerboard: 3' in r['note'] and r['items']==[] else 1)" "$out" \
  && ok "7b --report --json: the row's note, no items" || bad "7b '$out'"
out=$(python3 "$NU" --report --due-only --board "$BD/docs/user_attention.md" 2>&1)
grep -q "1 board(s) in a newer format, not read" <<< "$out" && grep -q "not read — .*Ledgerboard: 3" <<< "$out" \
  && ok "7c --due-only: said at session start, never counted as a due item" || bad "7c '$out'"
out=$(python3 "$NU" --board "$BD/docs/user_attention.md" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "not read: .*Ledgerboard: 3" <<< "$out" && ok "7d nudge mode: exit 1, said" || bad "7d rc=$rc '$out'"
board "" > "$BD/docs/user_attention.md"
out=$(python3 "$NU" --report --board "$BD/docs/user_attention.md" 2>&1)
grep -q "something due" <<< "$out" && ! grep -q "not read" <<< "$out" && ok "7e no version line: the report as before" || bad "7e '$out'"

# --- check_cadence.py: the ledger row's field check says it did not check a newer ledger
out=$(cd "$C" && python3 - "$S" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import subprocess, check_cadence as K
head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
pr = {"files": ["docs/technical_debt.md"], "state": "open", "head_sha": head, "number": 1}
errs, note = K.ledger_edit_check(pr, ".")
print(errs, note)
PY
)
grep -q "^\[\] ledger fields not checked: .*Ledgerboard: 3" <<< "$out" && ok "8 check_cadence.py: the ledger row says the fields were not checked, and why" || bad "8 '$out'"

ledger "" TD-009 > "$C/docs/technical_debt.md"; printf '# Archive\n\nLedgerboard: 3\n' > "$C/docs/technical_debt_archive.md"
git -C "$C" add -A && git -C "$C" commit -qm "v1 ledger, newer archive"
out=$(cd "$C" && python3 - "$S" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import subprocess, check_cadence as K
head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
print(K.ledger_edit_check({"files": ["docs/technical_debt.md"], "state": "open", "head_sha": head, "number": 1}, "."))
PY
)
grep -q "ledger fields not checked: .*technical_debt_archive.md: this file declares Ledgerboard: 3" <<< "$out" \
  && ok "8b check_cadence.py: a newer archive beside a v1 ledger is not read either" || bad "8b '$out'"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
