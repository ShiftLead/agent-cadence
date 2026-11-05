#!/usr/bin/env bash
# TD-218: `ledger.py set TD-n --blocked-by … --by <person> [--answer <label>]` is the person's lift of a
# `decision (<person>)` (ledgerboard's target design §1.1, §3.1). Asserts: dropping a decision without --by is
# refused; the session attestation (agent_sessions.person_session_refusal) refuses an unattended session, a
# session with controllers, one holding a seat, an `ao` that cannot answer and a session `ao` does not list, and passes a person's
# own session and a terminal with no SHIFTLEAD_SESSION; the covering item on this repo's board is answered by
# the board writer's --board-only half (Decided, closed — lifted) and the Log carries no suffix; a label not in
# the item's Lifts: is refused, an either/or item's non-default lifting label lifts; a parent snapshot whose
# other part still carries the gate is answered and left open (`shared board item left open`); an item only on
# another roster repo's board logs `board <repo>` and writes no board; no item logs `no board item`; a reassign
# (--why) is refused when the new person has no board, and otherwise closes a's item as moved, files b's decide
# item and a's fyi, leaving a shared parent snapshot open; an override (--override) is refused when a has no board, and otherwise closes a's item and
# files a's fyi; a two-decision drop is refused; ledgerboard's tripwire() (and uncovered_decisions() for the
# reassign) passes each route as the PR would carry it; and
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
export TZ=UTC   # TD-209: date -d arithmetic in calendar days; the board and ledger dates agree
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
  seat) echo '[{"id":"s-me","by_person":true,"unattended":false,"seat":{"trigger":"asks"},"controllers":[]}]' ;;
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
  entry "$L/TD-001.md" TD-001 "no item" '**Blocked by:** decision (Robin)\n'
  entry "$L/TD-002.md" TD-002 "own item" '**Blocked by:** decision (Robin)\n'
  entry "$L/TD-003.md" TD-003 "either or" '**Blocked by:** decision (Robin)\n'
  entry "$L/TD-010.md" TD-010 "parent" ''
  entry "$L/TD-011.md" TD-011 "part one" '**Blocked by:** decision (Robin)\n**Part of:** TD-010\n'
  entry "$L/TD-012.md" TD-012 "part two" '**Blocked by:** decision (Robin)\n**Part of:** TD-010\n'
  entry "$L/TD-020.md" TD-020 "elsewhere" '**Blocked by:** decision (Robin)\n'
  entry "$L/TD-021.md" TD-021 "two people" '**Blocked by:** decision (Robin), decision (Sam)\n'
  entry "$L/TD-031.md" TD-031 "nobody's board" '**Blocked by:** decision (Kim)\n'
  entry "$L/TD-030.md" TD-030 "named as another's" '**Blocked by:** decision (Robin)\n'
  { printf '# Board\n\nPeople: Robin, Sam\n\n## Needs the user\n\n'
    item "TD-002 decision (Robin)" "" "Go (default) | Not yet"
    item "TD-003 decision (Robin)" "" "CSV (default) | JSON | Not yet" " Lifts: CSV | JSON."
    item "TD-010 decision (Robin)" ". Parts: TD-011, TD-012" "Go (default) | Not yet"
    item "w#TD-030 decision (Robin)" "" "Go (default) | Not yet"
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
{ printf '# Board\n\nPeople: Robin\n\n## Needs the user\n\n'; item "w#TD-020 decision (Robin)" "" "Go (default) | Not yet"; } \
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
for mode in grinder driven seat other down; do
  AO_MODE=$mode SHIFTLEAD_SESSION=s-me lp set TD-001 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
  [ $rc -eq 1 ] && same docs && grep -q 'refused' "$TMP/err" \
    && ok "an attested lift is refused for a session that is $mode, writing nothing" || bad "attest $mode (rc=$rc): $(cat "$TMP/err")"
done
AO_MODE=person SHIFTLEAD_SESSION=s-me lp set TD-001 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ok "a person's own session lifts" || bad "person session (rc=$rc): $(cat "$TMP/err")"
reset

# --- 3) no item covers the gate: `no board item`, the board untouched
out=$(lp set TD-001 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && [ "$out" = "$L/TD-001.md" ] && ! grep -q 'Blocked by' "$L/TD-001.md" \
  && logline TD-001 | grep -q 'decision (Robin) — by Robin; answer "Go"; no board item' && same docs/user_attention.md \
  && ok "no covering item: the lift logs 'no board item' and leaves the board alone" || bad "no item (rc=$rc): $(cat "$TMP/err") $(cat "$L/TD-001.md")"

# --- 4) the item on this board: answered by the board-only half, closed — lifted
n=$(line_of "TD-002 decision"); before=$(sed -n "${n}p" "$B")
out=$(lp set TD-002 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
got=$(sed -n "${n}p" "$B")
[ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "$B" ] && logline TD-002 | grep -q 'by Robin; answer "Go"$' \
  && printf '%s' "$got" | grep -q "^- \[x\] .*Decided: Go (by Robin) ($LOCAL)\. Closed: $LOCAL — lifted\.$" \
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
uc() {  # ledgerboard's uncovered_decisions on the same trees: its refusals and flags, one per line
  (cd "$W" && python3 - "$DC/files/scripts" <<'EOF'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import ledgerboard as LB
def tree(ref):
    names = subprocess.run(["git", "ls-tree", "-r", "--name-only", ref, "docs"], capture_output=True, text=True).stdout.split()
    return {p: subprocess.run(["git", "show", f"{ref}:{p}"], capture_output=True, text=True).stdout for p in names}
head = {}
for d, _, fs in os.walk("docs"):
    for f in fs:
        head[os.path.join(d, f)] = open(os.path.join(d, f), encoding="utf-8").read()
refusals, flags = LB.uncovered_decisions(tree("origin/main"), head, [], "w")
for r in [*refusals, *flags]:
    print(r)
EOF
  )
}
t=$(tw); [ -z "$t" ] && ok "tripwire() passes the set lift with its board half" || bad "tripwire on own item: $t"
reset

# --- 4b) --by in another case is written as the gate spells it
lp set TD-001 --blocked-by "" --by robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && logline TD-001 | grep -q 'by Robin;' && ok "--by robin is logged as the gate spells it (Robin)" \
  || bad "by case (rc=$rc): $(cat "$TMP/err") $(logline TD-001)"
reset
# --- 4c) an item on this board naming the entry as <repo>#TD-n: refused before anything is written
out=$(lp set TD-030 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
[ $rc -eq 1 ] && [ -z "$out" ] && same docs && grep -q 'bare TD-030' "$TMP/err" \
  && ok "an own-board item naming the entry as w#TD-030 is refused, nothing written or printed" \
  || bad "own #ref (rc=$rc): out=$out $(cat "$TMP/err")"

# --- 5) Lifts: a label the item does not lift is refused; its non-default lifting label lifts
lp set TD-003 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "does not lift" "$TMP/err" \
  && ok "Go is refused on an item whose Lifts: are CSV | JSON, writing nothing" || bad "lifts refuse (rc=$rc): $(cat "$TMP/err")"
n=$(line_of "TD-003 decision")
lp set TD-003 --blocked-by "" --by Robin --answer JSON >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && logline TD-003 | grep -q 'answer "JSON"$' && sed -n "${n}p" "$B" | grep -q 'Decided: JSON (by Robin)' \
  && [ -z "$(tw)" ] && ok "an either/or item's non-default lifting label lifts, and the tripwire passes it" \
  || bad "either/or (rc=$rc): $(cat "$TMP/err") $(tw)"
reset

# --- 6) a parent snapshot whose other part still carries the gate: answered, left open
n=$(line_of "TD-010 decision")
lp set TD-011 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
got=$(sed -n "${n}p" "$B")
[ $rc -eq 0 ] && logline TD-011 | grep -q 'answer "Go"; shared board item left open$' \
  && printf '%s' "$got" | grep -q '^- \[ \] .*Decided: Go (by Robin)' && grep -q 'decision (Robin)' "$L/TD-012.md" \
  && [ -z "$(tw)" ] && ok "a shared parent snapshot is answered and left open, its other part untouched; tripwire passes" \
  || bad "shared (rc=$rc): $(cat "$TMP/err") | $got | $(logline TD-011) | $(tw)"
reset

# --- 7) the only covering item is another roster repo's: `board <repo>`, no board written
lp set TD-020 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
git -C "$TMP/tools" diff --quiet; rc3=$?
[ $rc -eq 0 ] && [ $rc3 -eq 0 ] && logline TD-020 | grep -q 'board tools$' && same docs/user_attention.md \
  && [ -z "$(tw)" ] && ok "an item on another roster board logs 'board tools' and writes no board; tripwire passes" \
  || bad "elsewhere (rc=$rc): $(cat "$TMP/err") | $(logline TD-020) | $(tw)"
reset

# --- 8) the reassign and the override, with the board notices they owe; a two-decision drop is refused
lp set TD-001 --blocked-by "decision (Kim)" --by Robin --why "Kim owns exports now" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'Kim has no board' "$TMP/err" \
  && ok "a reassign to a person with no board is refused, writing nothing" || bad "reassign no board (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --blocked-by "decision (Sam)" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -qi 'why' "$TMP/err" \
  && ok "a reassign without --why is refused, writing nothing" || bad "reassign no why (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --blocked-by "decision (Sam)" --by Robin --why "Sam owns exports now" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx '\*\*Blocked by:\*\* decision (Sam)' "$L/TD-002.md" \
  && grep -q "^- $TODAY: gate reassigned: decision (Robin) → decision (Sam) — by Robin; Sam owns exports now" "$L/TD-002.md" \
  && grep -q "^- \[x\] .*Context: TD-002 decision (Robin)\..*Closed: $LOCAL — moved to decision (Sam) by Robin\.$" "$B" \
  && grep -q '^- \[ \] decide .*Context: TD-002 decision (Sam)\. Due: ' "$B" \
  && grep -q '^- \[ \] fyi .*TD-002.s decision moved from you to Sam, by Robin: Sam owns exports now.* Context: TD-002\.' "$B" \
  && [ -z "$(tw)" ] && [ -z "$(uc)" ] \
  && ok "a reassign: Log, a's item closed as moved, b's decide item filed, a's fyi; tripwire and coverage pass" \
  || bad "reassign (rc=$rc): $(cat "$TMP/err") | $(grep -n 'TD-002' "$B") | $(tw) | $(uc)"
reset
lp set TD-031 --blocked-by "" --by Robin --override "Kim is away" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'Kim has no board' "$TMP/err" \
  && ok "an override whose person has no board to notify is refused, writing nothing" || bad "override no board (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --blocked-by "" --by Sam --override "Robin is away a month" --answer Go >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && same docs && ok "an override takes no --answer (a usage error), writing nothing" || bad "override answer (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --blocked-by "" --by Sam --override "Robin is away a month" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-002.md" && grep -q "^- $TODAY: .*override: Robin is away a month" "$L/TD-002.md" \
  && grep -q "^- \[x\] .*Context: TD-002 decision (Robin)\..*Closed: $LOCAL — lifted by override by Sam\.$" "$B" \
  && grep -q "^- \[ \] fyi .*TD-002.s decision (Robin) was lifted by override, by Sam: Robin is away a month" "$B" \
  && [ -z "$(tw)" ] && ok "an override: Log, a's item closed, a's fyi; the tripwire passes" \
  || bad "override (rc=$rc): $(cat "$TMP/err") | $(grep -n 'TD-002' "$B" "$L/TD-002.md") | $(tw)"
reset
lp set TD-011 --blocked-by "decision (Sam)" --by Robin --why "Sam owns part one" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -q '^- \[ \] decide .*Context: TD-010 decision (Robin)\. Parts: TD-011, TD-012\.' "$B" \
  && grep -q '^- \[ \] decide .*Context: TD-011 decision (Sam)\.' "$B" && [ -z "$(tw)" ] && [ -z "$(uc)" ] \
  && ok "a reassign leaves a shared parent snapshot open while another part still carries the gate" \
  || bad "reassign shared (rc=$rc): $(cat "$TMP/err") | $(grep -n 'TD-010' "$B") | $(tw) | $(uc)"
reset
lp set TD-002 --blocked-by "decision (Sam)" --by Robin --override "away" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && same docs && ok "--override with a Blocked by that swaps the decision is a usage error" \
  || bad "override+swap (rc=$rc): $(cat "$TMP/err")"
lp set TD-021 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && same docs && grep -q 'one at a time' "$TMP/err" \
  && ok "dropping two decisions at once is refused: one at a time" || bad "two (rc=$rc): $(cat "$TMP/err")"
lp set TD-021 --blocked-by "decision (Sam)" --by Sam >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && ok "a --by who is not the gate's person is refused (lift_gate), writing nothing" \
  || bad "wrong person (rc=$rc): $(cat "$TMP/err")"

# --- 9) board_edit.py decide's two-file lift is attested the same way
EDIT="$DC/files/scripts/board_edit.py"
n=$(line_of "TD-002 decision")
AO_MODE=grinder SHIFTLEAD_SESSION=s-me python3 "$EDIT" decide --board "$B" --line "$n" --expect "decide $LOCAL" \
  --answer Go --by Robin --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'lifts TD-002' "$TMP/err" \
  && ok "board_edit.py decide refuses a lift from an unattended session, writing nothing" || bad "decide attest (rc=$rc): $(cat "$TMP/err")"
AO_MODE=person SHIFTLEAD_SESSION=s-me python3 "$EDIT" decide --board "$B" --line "$n" --expect "decide $LOCAL" \
  --answer Go --by Robin --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-002.md" && sed -n "${n}p" "$B" | grep -q 'Decided: Go (by Robin)' \
  && ok "a person's own session's decide lifts the gate and answers the item" || bad "decide person (rc=$rc): $(cat "$TMP/err")"
reset

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
