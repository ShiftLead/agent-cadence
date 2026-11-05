#!/usr/bin/env bash
# TD-218: `ledger.py set TD-n --blocked-by … --by <person> [--answer <label>]` is the person's lift of a
# `decision (<person>)` (ledgerboard's target design §1.1, §3.1). Asserts: dropping a decision without --by is
# refused; the session attestation (agent_sessions.person_session_refusal) refuses an unattended session, a
# session with controllers, an `ao` that cannot answer and a session `ao` does not list, and passes a person's
# own session and a terminal with no SHIFTLEAD_SESSION; the covering item on this repo's board is answered by
# the board writer's --board-only half (Decided, closed — lifted) and the Log carries no suffix; a label not in
# the item's Lifts: is refused, an either/or item's non-default lifting label lifts; a parent snapshot whose
# other part still carries the gate is answered and left open (`shared board item left open`); an item only on
# another roster repo's board logs `board <repo>` and writes no board; no item logs `no board item`; a reassign
# and a two-decision drop are refused; ledgerboard's tripwire() passes each lift as the PR would carry it; and
# board_edit.py decide's two-file lift is attested the same way.
# Offline: origins are local bare repos, `ao` a PATH shim, the roster a temp dir; HOME/XDG are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR" "$TMP/bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SHIFTLEAD_SESSION
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date -u +%F)
LOCAL=$(date +%F)
DUE=$(date -d "+7 days" +%F 2>/dev/null || date -v+7d +%F)

# `ao status --json` as the shim answers it: $AO_MODE picks the record (or a failure).
cat > "$TMP/bin/ao" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2 $3" = "status --json " ] || [ "$1 $2" = "status --json" ] || exit 2
case "${AO_MODE:-person}" in
  person) echo '[{"id":"s-me","by_person":true,"unattended":false,"seat":null,"controllers":[]}]' ;;
  grinder) echo '[{"id":"s-me","by_person":false,"unattended":true,"seat":null,"controllers":["mgr"]}]' ;;
  driven) echo '[{"id":"s-me","by_person":true,"unattended":false,"seat":null,"controllers":["mgr"]}]' ;;
  other) echo '[{"id":"s-else","by_person":true,"unattended":false,"seat":null,"controllers":[]}]' ;;
  down) echo 'host agent is down' >&2; exit 3 ;;
esac
EOF
chmod +x "$TMP/bin/ao"
export PATH="$TMP/bin:$PATH"

entry() {  # $1 file, $2 id, $3 title, $4 extra header lines (each ending \n)
  printf '## %s: %s\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n%b\n**Why:** a fixture.\n\n**Ask:** go?\n' \
    "$2" "$3" "$TODAY" "$4" > "$1"
}
item() {  # $1 Context, $2 its Parts (". Parts: …", with the leading ". ") or "", $3 answers, $4 " Lifts: ….", or ""
  printf -- '- [ ] decide %s (n/a) — Go on this one? Context: %s%s. Due: %s. Answers: %s.%s\n' "$LOCAL" "$1" "$2" "$DUE" "$3" "${4:-}"
}

mkrepo() {  # $1 origin, $2 clone — the ledger and the board below; committed and pushed
  rm -rf "$1" "$2" "$TMP/seed"; git init -q --bare -b main "$1"
  git init -q -b main "$TMP/seed"; local L="$TMP/seed/docs/ledger"; mkdir -p "$L/archive"
  printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
  entry "$L/TD-001.md" TD-001 "no item" '**Blocked by:** decision (Paul)\n'
  entry "$L/TD-002.md" TD-002 "own item" '**Blocked by:** decision (Paul)\n'
  entry "$L/TD-003.md" TD-003 "either or" '**Blocked by:** decision (Paul)\n'
  entry "$L/TD-010.md" TD-010 "parent" ''
  entry "$L/TD-011.md" TD-011 "part one" '**Blocked by:** decision (Paul)\n**Part of:** TD-010\n'
  entry "$L/TD-012.md" TD-012 "part two" '**Blocked by:** decision (Paul)\n**Part of:** TD-010\n'
  entry "$L/TD-020.md" TD-020 "elsewhere" '**Blocked by:** decision (Paul)\n'
  entry "$L/TD-021.md" TD-021 "two people" '**Blocked by:** decision (Paul), decision (Robin)\n'
  { printf '# Board\n\nPeople: Paul\n\n## Needs the user\n\n'
    item "TD-002 decision (Paul)" "" "Go (default) | Not yet"
    item "TD-003 decision (Paul)" "" "CSV (default) | JSON | Not yet" " Lifts: CSV | JSON."
    item "TD-010 decision (Paul)" ". Parts: TD-011, TD-012" "Go (default) | Not yet"
  } > "$TMP/seed/docs/user_attention.md"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed
  git -C "$TMP/seed" push -q "$1" main; rm -rf "$TMP/seed"
  git clone -q "$1" "$2"
}
O="$TMP/o"; W="$TMP/w"; mkrepo "$O" "$W"
L="$W/docs/ledger"; B="$W/docs/user_attention.md"
lp() { (cd "$W" && python3 "$LEDGER_PY" "$@"); }
same() { git -C "$W" diff --quiet -- "$@"; }   # as committed
reset() { git -C "$W" checkout -q -- docs; }
logline() { grep -E "^- $TODAY: gate lifted" "$L/$1.md"; }
line_of() { grep -n -- "Context: $1" "$B" | head -1 | cut -d: -f1; }

# another roster repo whose board (at its origin/main) asks about TD-020 of this one
git init -q --bare -b main "$TMP/o2"; git init -q -b main "$TMP/seed2"; mkdir -p "$TMP/seed2/docs"
{ printf '# Board\n\nPeople: Paul\n\n## Needs the user\n\n'; item "w#TD-020 decision (Paul)" "" "Go (default) | Not yet"; } \
  > "$TMP/seed2/docs/user_attention.md"
git -C "$TMP/seed2" add -A; git -C "$TMP/seed2" commit -qm seed; git -C "$TMP/seed2" push -q "$TMP/o2" main
git clone -q "$TMP/o2" "$TMP/tools"; rm -rf "$TMP/seed2"
printf '%s\n%s\n' "$W" "$TMP/tools" > "$AGENT_CADENCE_REG_DIR/repos.txt"

# --- 1) dropping a decision takes --by; --answer alone is a usage error
lp set TD-001 --blocked-by "" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q -- '--by' "$TMP/err" \
  && ok "set refuses to drop a decision without --by, writing nothing" || bad "no --by (rc=$rc): $(cat "$TMP/err")"
lp set TD-001 --blocked-by "" --answer Go >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && same docs && ok "--answer without --by is a usage error" || bad "--answer alone rc=$rc"

# --- 2) the attestation: only a person's own session lifts
for mode in grinder driven other down; do
  AO_MODE=$mode SHIFTLEAD_SESSION=s-me lp set TD-001 --blocked-by "" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
  [ $rc -eq 1 ] && same docs && grep -q 'refused' "$TMP/err" \
    && ok "an attested lift is refused for a session that is $mode, writing nothing" || bad "attest $mode (rc=$rc): $(cat "$TMP/err")"
done
AO_MODE=person SHIFTLEAD_SESSION=s-me lp set TD-001 --blocked-by "" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ok "a person's own session lifts" || bad "person session (rc=$rc): $(cat "$TMP/err")"
reset

# --- 3) no item covers the gate: `no board item`, the board untouched
out=$(lp set TD-001 --blocked-by "" --by Paul 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && [ "$out" = "$L/TD-001.md" ] && ! grep -q 'Blocked by' "$L/TD-001.md" \
  && logline TD-001 | grep -q 'decision (Paul) — by Paul; answer "Go"; no board item' && same docs/user_attention.md \
  && ok "no covering item: the lift logs 'no board item' and leaves the board alone" || bad "no item (rc=$rc): $(cat "$TMP/err") $(cat "$L/TD-001.md")"

# --- 4) the item on this board: answered by the board-only half, closed — lifted
n=$(line_of "TD-002 decision"); before=$(sed -n "${n}p" "$B")
out=$(lp set TD-002 --blocked-by "" --by Paul 2>"$TMP/err"); rc=$?
got=$(sed -n "${n}p" "$B")
[ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "$B" ] && logline TD-002 | grep -q 'by Paul; answer "Go"$' \
  && printf '%s' "$got" | grep -q "^- \[x\] .*Decided: Go (by Paul) ($LOCAL)\. Closed: $LOCAL — lifted\.$" \
  && ok "the covering item on this board is answered (Decided, by) and closed as lifted; the Log has no suffix" \
  || bad "own item (rc=$rc): $(cat "$TMP/err") | $got | $(logline TD-002)"
tw() {  # ledgerboard's tripwire on origin/main's tree against the working tree: its flags, one per line
  (cd "$W" && python3 - "$DC/files/scripts" <<'EOF'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import ledgerboard as LB
def tree(ref):
    out = {}
    names = subprocess.run(["git", "ls-tree", "-r", "--name-only", ref, "docs"], capture_output=True, text=True).stdout.split()
    for p in names:
        out[p] = subprocess.run(["git", "show", f"{ref}:{p}"], capture_output=True, text=True).stdout
    return out
base = tree("origin/main")
head = {}
for d, _, fs in os.walk("docs"):
    for f in fs:
        head[os.path.join(d, f)] = open(os.path.join(d, f), encoding="utf-8").read()
for k, t in LB.tripwire(base, head, "ledger: set", "w"):
    print(k, t)
EOF
  )
}
t=$(tw); [ -z "$t" ] && ok "tripwire() passes the set lift with its board half" || bad "tripwire on own item: $t"
reset

# --- 5) Lifts: a label the item does not lift is refused; its non-default lifting label lifts
lp set TD-003 --blocked-by "" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "does not lift" "$TMP/err" \
  && ok "Go is refused on an item whose Lifts: are CSV | JSON, writing nothing" || bad "lifts refuse (rc=$rc): $(cat "$TMP/err")"
n=$(line_of "TD-003 decision")
lp set TD-003 --blocked-by "" --by Paul --answer JSON >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && logline TD-003 | grep -q 'answer "JSON"$' && sed -n "${n}p" "$B" | grep -q 'Decided: JSON (by Paul)' \
  && [ -z "$(tw)" ] && ok "an either/or item's non-default lifting label lifts, and the tripwire passes it" \
  || bad "either/or (rc=$rc): $(cat "$TMP/err") $(tw)"
reset

# --- 6) a parent snapshot whose other part still carries the gate: answered, left open
n=$(line_of "TD-010 decision")
lp set TD-011 --blocked-by "" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
got=$(sed -n "${n}p" "$B")
[ $rc -eq 0 ] && logline TD-011 | grep -q 'answer "Go"; shared board item left open$' \
  && printf '%s' "$got" | grep -q '^- \[ \] .*Decided: Go (by Paul)' && grep -q 'decision (Paul)' "$L/TD-012.md" \
  && [ -z "$(tw)" ] && ok "a shared parent snapshot is answered and left open, its other part untouched; tripwire passes" \
  || bad "shared (rc=$rc): $(cat "$TMP/err") | $got | $(logline TD-011) | $(tw)"
reset

# --- 7) the only covering item is another roster repo's: `board <repo>`, no board written
lp set TD-020 --blocked-by "" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
git -C "$TMP/tools" diff --quiet; rc3=$?
[ $rc -eq 0 ] && [ $rc3 -eq 0 ] && logline TD-020 | grep -q 'board tools$' && same docs/user_attention.md \
  && [ -z "$(tw)" ] && ok "an item on another roster board logs 'board tools' and writes no board; tripwire passes" \
  || bad "elsewhere (rc=$rc): $(cat "$TMP/err") | $(logline TD-020) | $(tw)"
reset

# --- 8) a reassign and a two-decision drop are not taken
lp set TD-001 --blocked-by "decision (Robin)" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'reassign' "$TMP/err" \
  && ok "a reassign through set is refused here, writing nothing" || bad "reassign (rc=$rc): $(cat "$TMP/err")"
lp set TD-021 --blocked-by "" --by Paul >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && same docs && grep -q 'one at a time' "$TMP/err" \
  && ok "dropping two decisions at once is refused: one at a time" || bad "two (rc=$rc): $(cat "$TMP/err")"
lp set TD-021 --blocked-by "decision (Robin)" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && ok "a --by who is not the gate's person is refused (lift_gate), writing nothing" \
  || bad "wrong person (rc=$rc): $(cat "$TMP/err")"

# --- 9) board_edit.py decide's two-file lift is attested the same way
EDIT="$DC/files/scripts/board_edit.py"
n=$(line_of "TD-002 decision")
AO_MODE=grinder SHIFTLEAD_SESSION=s-me python3 "$EDIT" decide --board "$B" --line "$n" --expect "decide $LOCAL" \
  --answer Go --by Paul --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'lifts TD-002' "$TMP/err" \
  && ok "board_edit.py decide refuses a lift from an unattended session, writing nothing" || bad "decide attest (rc=$rc): $(cat "$TMP/err")"
AO_MODE=person SHIFTLEAD_SESSION=s-me python3 "$EDIT" decide --board "$B" --line "$n" --expect "decide $LOCAL" \
  --answer Go --by Paul --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-002.md" && sed -n "${n}p" "$B" | grep -q 'Decided: Go (by Paul)' \
  && ok "a person's own session's decide lifts the gate and answers the item" || bad "decide person (rc=$rc): $(cat "$TMP/err")"
reset

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
