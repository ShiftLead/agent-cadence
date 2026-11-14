#!/usr/bin/env bash
# TD-218: `ledger.py set TD-n --blocked-by … --by <person> [--answer <label>]` is the person's lift of a
# `decision (<person>)` (ledgerboard's target design §1.1, §3.1). Asserts: dropping a decision without --by is
# refused; the session attestation (agent_sessions.person_session_refusal) refuses an unattended session, a
# session with controllers, one holding a seat, an `ao` that cannot answer and a session `ao` does not list, and passes a person's
# own session and a terminal with no SHIFTLEAD_SESSION; the covering item on this repo's board is answered by
# the board writer's --board-only half (Decided, closed — lifted) and the Log carries no suffix; a label not in
# the item's Lifts: is refused, an either/or item's non-default lifting label lifts; a parent snapshot whose
# other part still carries the gate leaves the board unwritten (v2.7 `left_open`, `shared board item left open`); an item only on
# another roster repo's board logs `board <repo>` and writes no board; no item logs `no board item`; a reassign
# (--why) is refused when the new person has no board, and otherwise closes a's item as moved, files b's decide
# item and a's fyi, leaving a shared parent snapshot open (b's item, a's fyi, or the close of a's item, on another
# roster repo's board by a PR opened there and left for its review, TD-226); an override (--override) is refused when a has no board, and otherwise closes a's item and
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
# `gh pr create` for the notices PR in another roster repo (TD-226): logged; $GH_FAIL refuses it.
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"; pwd -P >> "$GH_LOG.pwd"
[ "$1 $2" = "pr create" ] || { echo "gh-shim: unhandled: $*" >&2; exit 64; }
[ -n "${GH_FAIL:-}" ] && { echo "pull request create failed: GraphQL: boom" >&2; exit 1; }
echo "https://github.com/o/tools/pull/$(grep -c '^pr create' "$GH_LOG")"
EOF
chmod +x "$TMP/bin/gh"
export GH_LOG="$TMP/gh.log"
export PATH="$TMP/bin:$PATH"
entry() {  # $1 file, $2 id, $3 title, $4 extra header lines (each ending \n)
  printf '## %s: %s\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n%b\n**Why:** a fixture.\n\n**Ask:** go?\n' \
    "$2" "$3" "$TODAY" "$4" > "$1"
}
# The board is v3 (ledgerboard v3.0, TD-263): docs/user_attention/README.md, the stub at docs/user_attention.md, and
# one file per item. mkb.py writes an item file as the writers do; each fixture item has a fixed id.
cat > "$TMP/mkb.py" <<'PY'
# mkb.py <board dir> <id> <words> <context> <answers> [parts=…] [lifts=…] [due=…] [decided=<ans>:<by>:<day>[:close]]
#   or: mkb.py --decide <item file> <ans> <by> <day> — an open item decided in place
import datetime as d, os, sys
import ledgerboard as LB
if sys.argv[1] == "--decide":
    f, ans, by, day = sys.argv[2:6]
    new = LB.edit_item(open(f).read(), "decide", answer=ans, by=by, today=d.date.fromisoformat(day))
    open(f, "w").write(new)
    sys.exit(0)
board, iid, words, ctx, answers, *opts = sys.argv[1:]
o = dict(x.split("=", 1) for x in opts)
labels = [a.strip() for a in answers.split("|")]
default = next((i for i, a in enumerate(labels) if a.endswith(" (default)")), None)
labels = [a.removesuffix(" (default)") for a in labels]
added = iid[:10]
f = LB.item_file(words, o.get("due"), added, None, None, ctx, kind="decide", answers=labels, default=default,
                 parts=o["parts"].split(", ") if "parts" in o else None,
                 lifts=o["lifts"].split(" | ") if "lifts" in o else None,
                 detail={"context": "a fixture", "question": "go?", "recommended": "go"})
if "decided" in o:
    ans, by, day, *close = o["decided"].split(":")
    f = LB.edit_item(f, "decide", answer=ans, by=by, today=d.date.fromisoformat(day), close=bool(close))
shut = LB.parse_item(f).closed
path = os.path.join(board, LB.item_path(iid, shut[0].isoformat() if shut else None))
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w").write(f)
PY
mkb() { PYTHONPATH="$DC/files/scripts" python3 "$TMP/mkb.py" "$@"; }
vboard() {  # vboard <repo dir> <people>: an empty v3 board
  mkdir -p "$1/docs/user_attention"
  printf '# Board\n\nLedgerboard: 3\n\nPeople: %s\n' "$2" > "$1/docs/user_attention/README.md"
  PYTHONPATH="$DC/files/scripts" python3 -c 'import ledgerboard as LB; print(LB.board_stub("Board", "user_attention"), end="")' \
    > "$1/docs/user_attention.md"
}
I2="$LOCAL-00000002"; I3="$LOCAL-00000003"; I10="$LOCAL-00000010"; I30="$LOCAL-00000030"; I20="$LOCAL-00000020"

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
  entry "$L/TD-040.md" TD-040 "Lee's, on another board" '**Blocked by:** decision (Lee)\n'
  local BD="$TMP/seed/docs/user_attention"; vboard "$TMP/seed" "Robin, Sam"
  mkb "$BD" "$I2" "Go on this one?" "TD-002 decision (Robin)" "Go (default) | Not yet" due="$DUE"
  mkb "$BD" "$I3" "Go on this one?" "TD-003 decision (Robin)" "CSV (default) | JSON | Not yet" due="$DUE" "lifts=CSV | JSON"
  mkb "$BD" "$I10" "Go on this one?" "TD-010 decision (Robin)" "Go (default) | Not yet" due="$DUE" "parts=TD-011, TD-012"
  mkb "$BD" "$I30" "Go on this one?" "w#TD-030 decision (Robin)" "Go (default) | Not yet" due="$DUE"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed
  git -C "$TMP/seed" push -q "$1" main; rm -rf "$TMP/seed"
  git clone -q "$1" "$2"
}
O="$TMP/o"; W="$TMP/w"; mkrepo "$O" "$W"
L="$W/docs/ledger"; B="$W/docs/user_attention.md"; BD="$W/docs/user_attention"; BS="docs/user_attention.md docs/user_attention"
lp() { (cd "$W" && python3 "$LEDGER_PY" "$@"); }
same() { [ -z "$(git -C "$W" status --porcelain -- "$@")" ]; }   # as committed, no file added either
reset() { git -C "$W" checkout -q -- docs; git -C "$W" clean -fdq -- docs; }
logline() { grep -E "^- $TODAY: gate lifted" "$L/$1.md"; }
flat() {  # flat <board dir>: one line per item file, its path in the board first, its lines joined by spaces
  local f; for f in $(cd "$1" && find . -name '*.md' ! -name README.md | sort); do
    printf '%s: %s \n' "${f#./}" "$(tr '\n' ' ' < "$1/$f")"; done; }
at() { ls "$BD/$1.md" "$BD"/archive/*/"$1.md" 2>/dev/null | head -1; }   # an item's file, open or archived

# another roster repo whose board (at its origin/main) asks about TD-020 of this one
git init -q --bare -b main "$TMP/o2"; git init -q -b main "$TMP/seed2"
vboard "$TMP/seed2" "Robin, Lee"
mkb "$TMP/seed2/docs/user_attention" "$I20" "Go on this one?" "w#TD-020 decision (Robin)" "Go (default) | Not yet" due="$DUE"
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
  && logline TD-001 | grep -q 'decision (Robin) — by Robin; answer "Go"; no board item' && same $BS \
  && ok "no covering item: the lift logs 'no board item' and leaves the board alone" || bad "no item (rc=$rc): $(cat "$TMP/err") $(cat "$L/TD-001.md")"

# --- 4) the item on this board: answered by the board-only half, closed — lifted (its file moved into archive/)
out=$(lp set TD-002 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
got=$(at "$I2")
[ $rc -eq 0 ] && grep -q "/archive/.*/$I2.md$" <<< "$out" && logline TD-002 | grep -q 'by Robin; answer "Go"$' \
  && case "$got" in */archive/*) true ;; *) false ;; esac \
  && grep -qx "\*\*Decided:\*\* $LOCAL by Robin — Go" "$got" && grep -qx "\*\*Closed:\*\* $LOCAL — lifted" "$got" \
  && ok "the covering item on this board is answered (Decided, by) and closed as lifted; the Log has no suffix" \
  || bad "own item (rc=$rc): $(cat "$TMP/err") | $out | $got | $(logline TD-002)"
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
[ $rc -eq 1 ] && [ -z "$out" ] && same docs && grep -q 'bare TD-030' "$TMP/err" && grep -q "$I30" "$TMP/err" \
  && ok "an own-board item naming the entry as w#TD-030 is refused, nothing written or printed, the item named by id" \
  || bad "own #ref (rc=$rc): out=$out $(cat "$TMP/err")"

# --- 5) Lifts: a label the item does not lift is refused; its non-default lifting label lifts
lp set TD-003 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "does not lift" "$TMP/err" \
  && ok "Go is refused on an item whose Lifts: are CSV | JSON, writing nothing" || bad "lifts refuse (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --blocked-by "" --by Robin --answer JSON >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && logline TD-003 | grep -q 'answer "JSON"$' && grep -qx "\*\*Decided:\*\* $LOCAL by Robin — JSON" "$(at "$I3")" \
  && [ -z "$(tw)" ] && ok "an either/or item's non-default lifting label lifts, and the tripwire passes it" \
  || bad "either/or (rc=$rc): $(cat "$TMP/err") $(tw)"
reset

# --- 6) a parent snapshot whose other part still carries the gate: the board half writes nothing (ledgerboard
# v2.7, its TD-067 plan *Consumers*: paths [], left_open) and that is a success — the ledger path alone printed,
# the item left open said on stderr (by its id), the board as committed
out=$(lp set TD-011 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && logline TD-011 | grep -q 'answer "Go"; shared board item left open$' \
  && same $BS && grep -q 'decision (Robin)' "$L/TD-012.md" \
  && [ "$out" = "$(cd "$W" && pwd -P)/docs/ledger/TD-011.md" ] \
  && grep -q "item $I10 is left open, unanswered: TD-012 still carry decision (Robin)" "$TMP/err" \
  && [ -z "$(tw)" ] && ok "a shared parent snapshot: board left unwritten and unanswered, only the ledger printed, left_open said; tripwire passes" \
  || bad "shared (rc=$rc): out=$out err=$(cat "$TMP/err") | $(logline TD-011) | $(tw)"
reset

# --- 7) the only covering item is another roster repo's: `board <repo>`, no board written
lp set TD-020 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
git -C "$TMP/tools" diff --quiet; rc3=$?
[ $rc -eq 0 ] && [ $rc3 -eq 0 ] && logline TD-020 | grep -q 'board tools$' && same $BS \
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
f=$(flat "$BD")
[ $rc -eq 0 ] && grep -qx '\*\*Blocked by:\*\* decision (Sam)' "$L/TD-002.md" \
  && grep -q "^- $TODAY: gate reassigned: decision (Robin) → decision (Sam) — by Robin; Sam owns exports now" "$L/TD-002.md" \
  && grep -q "^archive/.*/$I2.md: .*Context:\*\* TD-002 decision (Robin) .*Closed:\*\* $LOCAL — moved to decision (Sam) by Robin " <<< "$f" \
  && grep -q '^[0-9][^/]*: .*Kind:\*\* decide .*Context:\*\* TD-002 decision (Sam) .*Due:\*\* ' <<< "$f" \
  && grep -q '^[0-9][^/]*: ## TD-002.s decision moved from you to Sam, by Robin: Sam owns exports now.*Kind:\*\* fyi .*Context:\*\* TD-002 ' <<< "$f" \
  && [ -z "$(tw)" ] && [ -z "$(uc)" ] \
  && ok "a reassign: Log, a's item closed as moved, b's decide item filed, a's fyi; tripwire and coverage pass" \
  || bad "reassign (rc=$rc): $(cat "$TMP/err") | $(grep 'TD-002' <<< "$f") | $(tw) | $(uc)"
reset
lp set TD-031 --blocked-by "" --by Robin --override "Kim is away" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'Kim has no board' "$TMP/err" \
  && ok "an override whose person has no board to notify is refused, writing nothing" || bad "override no board (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --blocked-by "" --by Sam --override "Robin is away a month" --answer Go >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && same docs && ok "an override takes no --answer (a usage error), writing nothing" || bad "override answer (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --blocked-by "" --by Sam --override "Robin is away a month" >/dev/null 2>"$TMP/err"; rc=$?
f=$(flat "$BD")
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-002.md" && grep -q "^- $TODAY: .*override: Robin is away a month" "$L/TD-002.md" \
  && grep -q "^archive/.*/$I2.md: .*Context:\*\* TD-002 decision (Robin) .*Closed:\*\* $LOCAL — lifted by override by Sam " <<< "$f" \
  && grep -q "^[0-9][^/]*: ## TD-002.s decision (Robin) was lifted by override, by Sam: Robin is away a month.*Kind:\*\* fyi " <<< "$f" \
  && [ -z "$(tw)" ] && ok "an override: Log, a's item closed, a's fyi; the tripwire passes" \
  || bad "override (rc=$rc): $(cat "$TMP/err") | $(grep 'TD-002' <<< "$f") | $(tw)"
reset
lp set TD-011 --blocked-by "decision (Sam)" --by Robin --why "Sam owns part one" >/dev/null 2>"$TMP/err"; rc=$?
f=$(flat "$BD")
[ $rc -eq 0 ] && grep -q "^$I10.md: .*Context:\*\* TD-010 decision (Robin) \*\*Parts:\*\* TD-011, TD-012 " <<< "$f" \
  && grep -q '^[0-9][^/]*: .*Kind:\*\* decide .*Context:\*\* TD-011 decision (Sam) ' <<< "$f" && [ -z "$(tw)" ] && [ -z "$(uc)" ] \
  && ok "a reassign leaves a shared parent snapshot open while another part still carries the gate" \
  || bad "reassign shared (rc=$rc): $(cat "$TMP/err") | $(grep 'TD-01' <<< "$f") | $(tw) | $(uc)"
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

# --- 8b) a notice whose person's board is another roster repo's goes there by a PR, left open (TD-226)
onb() {  # the board on that branch at origin, flattened as flat() does
  local f; for f in $(git -C "$TMP/o2" ls-tree -r --name-only "$1" -- docs/user_attention 2>/dev/null | grep -v '/README.md$'); do
    printf '%s: %s \n' "${f#docs/user_attention/}" "$(git -C "$TMP/o2" show "$1:$f" | tr '\n' ' ')"; done; }
out=$(lp set TD-002 --blocked-by "decision (Lee)" --by Robin --why "Lee owns exports now" 2>"$TMP/err"); rc=$?
f=$(flat "$BD"); n=$(onb notices/w-TD-002-lee)
[ $rc -eq 0 ] && grep -qx '\*\*Blocked by:\*\* decision (Lee)' "$L/TD-002.md" \
  && grep -q "^archive/.*/$I2.md: .*Context:\*\* TD-002 decision (Robin) .*Closed:\*\* $LOCAL — moved to decision (Lee) by Robin " <<< "$f" \
  && grep -q '^[0-9][^/]*: ## TD-002.s decision moved from you to Lee, by Robin' <<< "$f" \
  && ! grep -q 'Context:\*\* TD-002 decision (Lee)' <<< "$f" \
  && grep -q '^[0-9][^/]*: .*Kind:\*\* decide .*Context:\*\* w#TD-002 decision (Lee) .*Due:\*\* ' <<< "$n" \
  && grep -q "w#TD-002.s decision moved from Robin to you" <<< "$n" \
  && ! sed 's/^[^:]*: //' <<< "$n" | grep -q "[^#]TD-002" \
  && [ "$(sort -u "$GH_LOG.pwd")" = "$(cd "$TMP/tools" && pwd -P)" ] \
  && [ "$(grep -vc '^archive/' <<< "$n")" -eq 2 ] \
  && grep -q '^pr create --head notices/w-TD-002-lee --base main --title board: w#TD-002 decision (Robin) moved to decision (Lee)' "$GH_LOG" \
  && [ "$(printf '%s\n' "$out" | tail -1)" = "https://github.com/o/tools/pull/1" ] \
  && [ -z "$(git -C "$TMP/tools" status --porcelain)" ] && ! git -C "$TMP/tools" rev-parse -q --verify notices/w-TD-002-lee >/dev/null \
  && ! uc | grep -q "decision-uncovered" \
  && ok "a reassign to a person on another roster board: a's notices here, b's decide item there by a PR left open" \
  || bad "reassign elsewhere (rc=$rc): $(cat "$TMP/err") | $out | $n | $(cat "$GH_LOG")"
reset
out=$(lp set TD-040 --blocked-by "" --by Robin --override "Lee is away" 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-040.md" && same $BS \
  && onb notices/w-TD-040-override | grep -q "^[0-9][^/]*: ## w#TD-040.s decision (Lee) was lifted by override, by Robin: Lee is away.*Kind:\*\* fyi .*Context:\*\* w#TD-040 " \
  && grep -q '^pr create --head notices/w-TD-040-override ' "$GH_LOG" \
  && ok "an override for a person on another roster board: the fyi there by a PR, this board untouched" \
  || bad "override elsewhere (rc=$rc): $(cat "$TMP/err") | $out | $(onb notices/w-TD-040-override)"
reset
out=$(lp set TD-020 --blocked-by "decision (Sam)" --by Robin --why "Sam owns it now" 2>"$TMP/err"); rc=$?
f=$(flat "$BD"); n=$(onb notices/w-TD-020-sam)
[ $rc -eq 0 ] && grep -q '^[0-9][^/]*: .*Kind:\*\* decide .*Context:\*\* TD-020 decision (Sam) .*Due:\*\* ' <<< "$f" \
  && grep -q '^[0-9][^/]*: ## TD-020.s decision moved from you to Sam' <<< "$f" \
  && grep -q "^archive/.*/$I20.md: .*Context:\*\* w#TD-020 decision (Robin) .*Closed:\*\* $LOCAL — moved to decision (Sam) by Robin " <<< "$n" \
  && [ "$(wc -l <<< "$n")" -eq 1 ] && grep -q '^pr create --head notices/w-TD-020-sam ' "$GH_LOG" \
  && ok "a reassign whose old item is on another roster board: closed there as moved, by a PR left open" \
  || bad "close elsewhere (rc=$rc): $(cat "$TMP/err") | $out | $n"
reset
git -C "$TMP/o2" branch -q -D notices/w-TD-040-override
GH_FAIL=1 lp set TD-040 --blocked-by "" --by Robin --override "Lee is away" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'boom' "$TMP/err" && [ -z "$(onb notices/w-TD-040-override)" ] \
  && ok "a notices PR the forge refuses: both files here put back, the pushed branch deleted again" \
  || bad "notices refused (rc=$rc): $(cat "$TMP/err")"
# a reassign whose notice goes to a board still v2 (TD-263): refused before anything is written, naming its split
git clone -q "$TMP/o2" "$TMP/v2b"; rm -rf "$TMP/v2b/docs/user_attention"
printf '# Board\n\nPeople: Robin, Lee\n\n## Needs the user\n\n- (none)\n' > "$TMP/v2b/docs/user_attention.md"
git -C "$TMP/v2b" add -A; git -C "$TMP/v2b" commit -qm "a v2 board"; git -C "$TMP/v2b" push -q origin HEAD:refs/heads/v2
m=$(git -C "$TMP/tools" rev-parse origin/main)
git -C "$TMP/tools" fetch -q origin; git -C "$TMP/tools" update-ref refs/remotes/origin/main refs/remotes/origin/v2
lp set TD-040 --blocked-by "" --by Robin --override "Lee is away" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "tools's board is still v2 (docs/user_attention.md): tools splits it first (board.py split" "$TMP/err" \
  && ok "a notice for a board still v2: refused, writing nothing, the refusal naming that repo's split" \
  || bad "v2 target (rc=$rc): $(cat "$TMP/err")"
git -C "$TMP/tools" update-ref refs/remotes/origin/main "$m"

# --- 9) board_edit.py decide's two-file lift is attested the same way
EDIT="$DC/files/scripts/board_edit.py"
AO_MODE=grinder SHIFTLEAD_SESSION=s-me python3 "$EDIT" decide --board "$B" --id "$I2" \
  --answer Go --by Robin --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q 'lifts TD-002' "$TMP/err" \
  && ok "board_edit.py decide refuses a lift from an unattended session, writing nothing" || bad "decide attest (rc=$rc): $(cat "$TMP/err")"
AO_MODE=person SHIFTLEAD_SESSION=s-me python3 "$EDIT" decide --board "$B" --id "$I2" \
  --answer Go --by Robin --no-commit >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-002.md" && grep -qx "\*\*Decided:\*\* $LOCAL by Robin — Go" "$(at "$I2")" \
  && ok "a person's own session's decide lifts the gate and answers the item" || bad "decide person (rc=$rc): $(cat "$TMP/err")"
reset

# --- 10) TD-260: a session applies the person's answer already recorded on origin's default branch (a Queue press)
OLD=$(date -d "-10 days" +%F 2>/dev/null || date -v-10d +%F); YEST=$(date -u -d "-1 day" +%F 2>/dev/null || date -u -v-1d +%F)
git clone -q "$O" "$TMP/press"; PB="$TMP/press/docs/user_attention"
mkb --decide "$PB/$I2.md" Go Robin "$LOCAL"; mkb --decide "$PB/$I3.md" CSV Sam "$LOCAL"; mkb --decide "$PB/$I10.md" Go Robin "$LOCAL"
# an earlier round's answer, carried out and closed; and an answer from before the gate was last added
mkb "$PB" "$OLD-000000e1" "an earlier round?" "TD-001 decision (Robin)" "Ship | Not yet" due="$OLD" "lifts=Ship" "decided=Ship:Robin:$OLD:close"
mkb "$PB" "$YEST-000000e2" "before the gate: Go?" "TD-031" "Go | Not yet" due="$DUE" "decided=Go:Kim:$YEST"
printf '\n**Log:**\n- %s: gate added: decision (Kim)\n' "$TODAY" >> "$TMP/press/docs/ledger/TD-031.md"
mkb "$PB" "$LOCAL-000000e3" "no item: Lift it?" "TD-001" "Lift it | Not yet" due="$DUE" "decided=Lift it:Robin:$LOCAL"
git -C "$TMP/press" add -A; git -C "$TMP/press" commit -qm "board: the Queue's presses"; git -C "$TMP/press" push -q origin main
git -C "$W" pull -q --ff-only
g() { AO_MODE=grinder SHIFTLEAD_SESSION=s-me lp "$@"; }
out=$(g set TD-002 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
got=$(at "$I2")
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-002.md" && logline TD-002 | grep -q 'by Robin; answer "Go"$' \
  && grep -qE "^- $TODAY: lifted by a session on Robin's answer 'Go' \($LOCAL\) on the board item $I2 .*at origin/main$" "$L/TD-002.md" \
  && case "$got" in */archive/*) true ;; *) false ;; esac \
  && grep -qx "\*\*Decided:\*\* $LOCAL by Robin — Go" "$got" && grep -qx "\*\*Closed:\*\* $LOCAL — lifted" "$got" \
  && [ -z "$(tw)" ] \
  && ok "an unattended session lifts a gate whose item origin/main holds decided by its person; the Log names the answer" \
  || bad "recorded board answer (rc=$rc): $(cat "$TMP/err") | $got | $(tail -3 "$L/TD-002.md") | $(tw)"
reset
out=$(g set TD-001 --blocked-by "" --by Robin --answer "Lift it" 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && logline TD-001 | grep -q 'answer "Lift it"; no board item' && grep -q "lifted by a session on Robin's answer 'Lift it'" "$L/TD-001.md" \
  && [ -z "$(tw)" ] \
  && ok "the Queue's decided line for an entry (Context: the bare id) is a recorded answer too" \
  || bad "bare-id answer (rc=$rc): $(cat "$TMP/err") | $(tail -3 "$L/TD-001.md") | $(tw)"
reset
g set TD-001 --blocked-by "" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "records no answer 'Go' by Robin" "$TMP/err" \
  && ok "an answer other than the recorded one is refused, writing nothing" || bad "other label (rc=$rc): $(cat "$TMP/err")"
g set TD-003 --blocked-by "" --by Robin --answer CSV >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "records no answer" "$TMP/err" \
  && ok "an answer recorded by someone other than the gate's person is refused" || bad "other person (rc=$rc): $(cat "$TMP/err")"
g set TD-002 --blocked-by "" --by Sam >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "only Robin's own recorded answer" "$TMP/err" \
  && ok "a session's lift --by someone other than the gate's person is refused" || bad "by other (rc=$rc): $(cat "$TMP/err")"
mkb "$BD" "$LOCAL-000000e4" "two: Go?" "TD-021 decision (Robin)" "Go | Not yet" due="$DUE" "decided=Go:Robin:$LOCAL"
git -C "$W" add -A docs; git -C "$W" commit -qm "a session's own decided item, not on origin"
g set TD-021 --blocked-by "decision (Sam)" --by Robin >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs/ledger && grep -q "records no answer" "$TMP/err" \
  && ok "a decided item only on the session's own branch, not on origin/main, is no recorded answer" || bad "branch only (rc=$rc): $(cat "$TMP/err")"
git -C "$W" reset -q --hard origin/main
g set TD-001 --blocked-by "" --by Robin --answer Ship >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "records no answer" "$TMP/err" \
  && ok "an earlier round's answer, closed on origin's board, is never replayed" || bad "stale closed (rc=$rc): $(cat "$TMP/err")"
g set TD-031 --blocked-by "" --by Kim >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "records no answer" "$TMP/err" \
  && ok "an answer dated before the gate's last 'gate added' line is no record" || bad "before gate (rc=$rc): $(cat "$TMP/err")"
out=$(g set TD-011 --blocked-by "" --by Robin 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && ! grep -q 'Blocked by' "$L/TD-011.md" && grep -q "lifted by a session on Robin's answer 'Go'" "$L/TD-011.md" \
  && ok "the parent's decided item listing the part in Parts: is a record for the part" \
  || bad "parts (rc=$rc): $(cat "$TMP/err") | $(tail -2 "$L/TD-011.md")"
reset
g set TD-002 --blocked-by "decision (Sam)" --by Robin --why "Sam owns it" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "only a person's own session" "$TMP/err" \
  && ok "a reassign from an unattended session is still refused, a recorded answer or not" || bad "reassign (rc=$rc): $(cat "$TMP/err")"
g set TD-002 --blocked-by "" --by Robin --override "away" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && same docs && grep -q "only a person's own session" "$TMP/err" \
  && ok "an override from an unattended session is still refused, a recorded answer or not" || bad "override (rc=$rc): $(cat "$TMP/err")"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
