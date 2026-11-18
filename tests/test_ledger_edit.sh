#!/usr/bin/env bash
# TD-199: `ledger.py set`, `note` and `edit` change one open entry of a v2 ledger through
# ledgerboard's writer (plan_edit: note and edit since TD-216, set since TD-218, whose lift route is
# tests/test_ledger_set_lift.sh's), refusing what the gate would fail. Asserts: set changes a field in place
# and removes one with an empty value; note keeps the Status and adds a dated line to the Log (ledgerboard
# v2.4); edit replaces one section and leaves the header and the other sections alone, and adds a missing Fix
# after the Why; refusals leave the file untouched — an unknown Type, a wait in prose in a field (TD-166), a
# decision with a pointer (v2.4's old form; TD-172), a cross-repo blocker its roster repo lacks, an entry canonical()
# refuses, an archived entry, an unknown id.
# Offline: origin is a local bare repo, the roster a temp dir; HOME/XDG are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)

mkrepo() {  # $1 origin dir, $2 clone dir — a v2 ledger: TD-001, TD-003 (Why, Fix, Done when), TD-004 (Why only), TD-005 (a field twice); TD-002 archived
  rm -rf "$1" "$2" "$TMP/seed"; git init -q --bare -b main "$1"
  git init -q -b main "$TMP/seed"; local L="$TMP/seed/docs/ledger"; mkdir -p "$L/archive"
  printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
  printf '## TD-001: one\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** a fixture.\n' > "$L/TD-001.md"
  printf '## TD-002: archived\n\n**Priority:** Low\n**Status:** Resolved %s\n\n**Why:** a fixture.\n\n**Resolved:** %s\n' \
    "$TODAY" "$TODAY" > "$L/archive/TD-002.md"
  printf '## TD-003: three\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open\n\n**Why:** because.\n\n**Location:** x.py\n\n**Fix:** old fix.\n\n**Done when** it is.\n' \
    "$TODAY" > "$L/TD-003.md"
  printf '## TD-004: four\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** only a why.\n\n**Related:** TD-001.\n' > "$L/TD-004.md"
  printf '## TD-005: five\n\n**Priority:** Low\n**Priority:** High\n**Status:** Open\n\n**Why:** twice.\n' > "$L/TD-005.md"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed
  git -C "$TMP/seed" push -q "$1" main; rm -rf "$TMP/seed"
  git clone -q "$1" "$2"
}
O="$TMP/o"; W="$TMP/w"; mkrepo "$O" "$W"
L="$W/docs/ledger"
lp() { (cd "$W" && python3 "$LEDGER_PY" "$@"); }
same() { git -C "$W" diff --quiet -- "docs/ledger/$1"; }   # the file is as committed

# --- 1) set: a field in place, a new one where the order puts it; an empty value removes one.
out=$(lp set TD-003 --priority High --blocked-by TD-001 --owner grinder 2>"$TMP/err"); rc=$?
hdr=$(sed -n '3,8p' "$L/TD-003.md")
want="**Priority:** High
**Added:** $TODAY
**Owner:** grinder
**Status:** Open
**Blocked by:** TD-001"
[ $rc -eq 0 ] && [ "$out" = "$L/TD-003.md" ] && [ "$hdr" = "$want" ] \
  && ok "set changes a field in place and adds others where SPEC's order puts them" || bad "set (rc=$rc): $(cat "$TMP/err") $hdr"
c=$(lp --check --since origin/main 2>&1) && lp fmt --check TD-003 >/dev/null 2>&1 \
  && ok "the edited entry passes --check --since and fmt --check" || bad "check after set: $c"
lp set TD-003 --blocked-by "" >/dev/null 2>"$TMP/err" && ! grep -q 'Blocked by' "$L/TD-003.md" \
  && ok "set with an empty value removes the field" || bad "set remove: $(cat "$TMP/err")"

# --- 2) note: the Status kept as it was, a dated line added to the entry's Log (ledgerboard v2.4).
lp note TD-003 "reproduced it" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx "\*\*Status:\*\* Open" "$L/TD-003.md" \
  && [ "$(sed -n '/^\*\*Log:\*\*$/,$p' "$L/TD-003.md")" = "$(printf '**Log:**\n- %s: reproduced it' "$(date -u +%F)")" ] \
  && ok "note keeps the Status and adds a dated line (the UTC day, ledgerboard's writer, TD-216) to the Log, the body's last section" || bad "note (rc=$rc): $(cat "$TMP/err") $(cat "$L/TD-003.md")"

# --- 3) edit: one section replaced, the rest untouched; a missing Fix added after the Why.
before_hdr=$(sed -n '1,/^$/p;' "$L/TD-003.md"; sed -n '/^\*\*Why/p;/^\*\*Done when/p' "$L/TD-003.md")
printf 'new fix,\n\n- with a bullet\n' > "$TMP/fix.md"
lp edit TD-003 --section Fix --from "$TMP/fix.md" >/dev/null 2>"$TMP/err"; rc=$?
after_hdr=$(sed -n '1,/^$/p;' "$L/TD-003.md"; sed -n '/^\*\*Why/p;/^\*\*Done when/p' "$L/TD-003.md")
[ $rc -eq 0 ] && grep -qx '\*\*Fix:\*\* new fix,' "$L/TD-003.md" && grep -qx -- '- with a bullet' "$L/TD-003.md" \
  && ! grep -q 'old fix' "$L/TD-003.md" && [ "$before_hdr" = "$after_hdr" ] \
  && ok "edit replaces one section and leaves the header and the other sections as they were" \
  || bad "edit Fix (rc=$rc): $(cat "$TMP/err") $(cat "$L/TD-003.md")"
printf 'add one.\n' | lp edit TD-004 --section Fix --from - >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && [ "$(sed -n '/^\*\*Why/,$p' "$L/TD-004.md" | grep '^\*\*' | cut -d'*' -f3)" = "$(printf 'Why:\nFix:\nRelated:')" ] \
  && ok "edit adds a Fix the entry lacks after its Why (from stdin)" || bad "edit add (rc=$rc): $(cat "$TMP/err") $(cat "$L/TD-004.md")"

# --- 4) Refusals leave the file as it was.
cp "$L/TD-003.md" "$TMP/td3"
lp set TD-003 --type nonsense >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "set refuses an unknown Type, writing nothing" || bad "bad Type (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --field "Stage=next, waits on TD-001 now" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — .*waits on TD-001' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "set refuses a wait written in prose in a field (TD-166; a note goes to the Log, which is no field)" || bad "prose set (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --blocked-by "decision (owner) — after TD-001 lands" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — .*old decision form' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "set refuses a decision with a pointer: the old form is gone at v3.0" || bad "pointer (rc=$rc): $(cat "$TMP/err")"
O2="$TMP/o2"; R2="$TMP/other"; mkrepo "$O2" "$R2"; echo "$R2" > "$AGENT_CADENCE_REG_DIR/repos.txt"
lp set TD-003 --blocked-by "other#TD-099" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'other has no TD-099' "$TMP/err" && grep -q fetch "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "set refuses a cross-repo blocker its roster repo lacks, saying to fetch" || bad "xrepo (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --field "blocked-BY=other#TD-099" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'other has no TD-099' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "the cross-repo check reads Blocked by however --field spells it" || bad "xrepo --field (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --priority High --field "priority=Low" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'given twice: priority' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "a field given twice, in any spelling, is a usage error" || bad "dup field (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --blocked-by "other#TD-001" >/dev/null 2>"$TMP/err" && grep -qx '\*\*Blocked by:\*\* other#TD-001' "$L/TD-003.md" \
  && ok "set writes a cross-repo blocker its repo holds" || bad "xrepo present: $(cat "$TMP/err")"
: > "$TMP/gh.log"   # TD-246: an id missing at origin/main that an open PR there adds is written, with a note naming it
mkdir -p "$TMP/bin"; printf '#!/usr/bin/env bash\necho "$PWD $*" >> "%s/gh.log"\n[ "${GH_FAIL:-}" ] && { echo "HTTP 502: bad gateway" >&2; exit 1; }\ncat "%s/gh.json"\n' "$TMP" "$TMP" > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
git -C "$R2" remote set-url origin https://github.com/o/other.git   # a GitHub origin; its origin/main ref stays as fetched
lpg() { (cd "$W" && PATH="$TMP/bin:$PATH" python3 "$LEDGER_PY" "$@"); }
echo '[{"number":7,"headRefName":"ledger-x","files":[{"path":"docs/ledger/README.md"}]},{"number":9,"headRefName":"td99","files":[{"path":"docs/ledger/TD-099.md"}]}]' > "$TMP/gh.json"
lpg set TD-003 --blocked-by "other#TD-099" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx '\*\*Blocked by:\*\* other#TD-099' "$L/TD-003.md" && grep -q "note — Blocked by other#TD-099: .*open PR #9 adds it" "$TMP/err" \
  && grep -q "^$R2 pr list --state open" "$TMP/gh.log" \
  && ok "set writes a cross-repo blocker an open PR in its repo adds, naming the PR (gh asked in that clone, TD-246)" || bad "xrepo pending (rc=$rc): $(cat "$TMP/err") $(cat "$TMP/gh.log")"
c=$(lp --check 2>&1)
grep -q "TD-003: cannot resolve other#TD-099 — other has no TD-099" <<< "$c" && lp --pickable 2>&1 | grep -q "TD-003.*other#TD-099" \
  && ok "the check flags the pending block, and it holds, until the PR merges and is fetched (so one closed unmerged stays flagged)" \
  || bad "xrepo pending check: $c"
cp "$TMP/td3" "$L/TD-003.md"
echo '[{"number":7,"headRefName":"ledger-x","files":[{"path":"docs/ledger/TD-0990.md"},{"path":"docs/ledger/archive/TD-099.md"}]}]' > "$TMP/gh.json"
lpg set TD-003 --blocked-by "other#TD-099" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'other has no TD-099.*no open PR there adds it' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "an id no open PR adds is still refused (another id's file, an archive file, are not it)" || bad "xrepo no PR (rc=$rc): $(cat "$TMP/err")"
GH_FAIL=1 lpg set TD-003 --blocked-by "other#TD-099" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'open PRs could not be read (HTTP 502' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "an unreadable forge refuses, as before TD-246" || bad "xrepo forge down (rc=$rc): $(cat "$TMP/err")"
: > "$AGENT_CADENCE_REG_DIR/repos.txt"
lp note TD-005 "x" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'twice' "$TMP/err" && same TD-005.md \
  && ok "an entry canonical() refuses is refused with its hand fix" || bad "refused entry (rc=$rc): $(cat "$TMP/err")"
lp set TD-002 --priority High >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'archived' "$TMP/err" && same archive/TD-002.md \
  && ok "an archived entry is not set" || bad "archived set (rc=$rc): $(cat "$TMP/err")"
lp note TD-002 "a later look" >/dev/null 2>"$TMP/err"; rc=$?  # ledgerboard v2.8 (its TD-088): a note on an archived entry
[ $rc -eq 0 ] && grep -q -- "- $(date -u +%F): a later look" "$L/archive/TD-002.md" \
  && ok "an archived entry takes a note (v2.8)" || bad "archived note (rc=$rc): $(cat "$TMP/err")"
lp set TD-099 --priority Low >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'in neither' "$TMP/err" && ok "an unknown id exits 2" || bad "unknown (rc=$rc)"
lp set TD-001 >/dev/null 2>&1; r1=$?
lp edit TD-001 --section Fix --from /dev/null >/dev/null 2>&1; r2=$?
[ $r1 -eq 2 ] && [ $r2 -eq 2 ] && same TD-001.md && ok "set with no field and an empty edit are usage errors" || bad "usage: $r1 $r2"

# --- TD-216/TD-222: an entry with a field below its header block, at origin and untouched, does not refuse a
# note or an edit of another entry (v2.4's check() raised on it and ledger.py guarded it; v2.5 flags it, below-header).
O3="$TMP/o3"; W3="$TMP/w3"; mkrepo "$O3" "$W3"
printf '## TD-006: below\n\n**Priority:** Low\n\n**Blocked by:** decision (Alex)\n\n**Why:** x.\n' > "$W3/docs/ledger/TD-006.md"
git -C "$W3" add -A && git -C "$W3" commit -qm below && git -C "$W3" push -q origin main
r1=$( (cd "$W3" && python3 "$LEDGER_PY" note TD-001 "still fine") >/dev/null 2>"$TMP/err"; echo $?)
printf 'a new why.\n' > "$TMP/why.md"
r2=$( (cd "$W3" && python3 "$LEDGER_PY" edit TD-001 --section Why --from "$TMP/why.md") >/dev/null 2>>"$TMP/err"; echo $?)
[ "$r1" = 0 ] && [ "$r2" = 0 ] && grep -q 'still fine' "$W3/docs/ledger/TD-001.md" && grep -q 'a new why' "$W3/docs/ledger/TD-001.md" \
  && ok "a below-block entry elsewhere, unchanged since origin, refuses no note or edit of another entry (TD-222)" \
  || bad "below-block elsewhere: $r1 $r2 $(cat "$TMP/err")"

# --- TD-265: set --title retitles, edit --remove removes a section (ledgerboard v2.8's writer, passed through)
mkrepo "$O" "$W"
lp set TD-003 --title "three, retitled" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && head -1 "$L/TD-003.md" | grep -qx '## TD-003: three, retitled' && grep -q 'retitled: was "three"' "$L/TD-003.md" \
  && ok "set --title retitles an open entry, logging the old title" || bad "retitle (rc=$rc): $(cat "$TMP/err") $(head -1 "$L/TD-003.md")"
lp set TD-001 --title "one again" --priority High >/dev/null 2>"$TMP/err" && head -1 "$L/TD-001.md" | grep -qx '## TD-001: one again' \
  && grep -qx '\*\*Priority:\*\* High' "$L/TD-001.md" && ok "set --title with a field sets both" || bad "retitle+field: $(cat "$TMP/err")"
cp "$L/TD-004.md" "$TMP/td4"
lp set TD-004 --title "  " >/dev/null 2>&1; r1=$?
lp set TD-004 --title x --by alex >/dev/null 2>&1; r2=$?
[ $r1 -ne 0 ] && [ $r2 -ne 0 ] && cmp -s "$L/TD-004.md" "$TMP/td4" \
  && ok "set refuses an empty --title, and --title beside --by, writing nothing" || bad "title refusals: $r1 $r2"
printf '## TD-006: six\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** a fixture.\n\n**Title:** stray\n' > "$L/TD-006.md"
git -C "$W" add -A; git -C "$W" commit -qm six; git -C "$W" push -q origin main
lp edit TD-006 --section Title --remove >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && ! grep -q '^\*\*Title:' "$L/TD-006.md" && grep -q '^\*\*Why:\*\* a fixture' "$L/TD-006.md" \
  && ok "edit --remove removes a misplaced section (one named Title) and keeps the rest" || bad "remove (rc=$rc): $(cat "$TMP/err")"
cp "$L/TD-003.md" "$TMP/td3"
lp edit TD-003 --section Fix --remove >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'not misplaced' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "edit --remove refuses a section in its place (the writer removes only a misplaced one)" || bad "remove placed (rc=$rc): $(cat "$TMP/err")"
printf 'x\n' > "$TMP/x.md"
lp edit TD-004 --section Related --remove --from "$TMP/x.md" >/dev/null 2>&1; r1=$?
lp edit TD-004 --section Related >/dev/null 2>&1; r2=$?
lp edit TD-004 --section Title --remove >/dev/null 2>&1; r3=$?
lp edit TD-002 --section Why --remove >/dev/null 2>&1; r4=$?
[ $r1 -ne 0 ] && [ $r2 -ne 0 ] && [ $r3 -ne 0 ] && [ $r4 -ne 0 ] && cmp -s "$L/TD-004.md" "$TMP/td4" \
  && ok "edit refuses --remove with --from, neither, a Title, and an archived entry, writing nothing" || bad "remove refusals: $r1 $r2 $r3 $r4"
lp set TD-002 --title nope >/dev/null 2>&1 && bad "set --title on an archived entry was accepted" || ok "set --title refuses an archived entry"

# --- TD-264 (rule 6): nothing that waits on the person is invisible. A set that makes an open entry wait on the
# person (an Owner who is one) with no decision (<person>) gate is refused; one already so on origin is standing;
# the gate with its Ask in one write (set --ask, ledgerboard v3.2, TD-272) is the way in; a person's lift that
# leaves the wait is standing too.
cp "$L/TD-004.md" "$TMP/td4"
lp set TD-004 --owner person >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — ⚠ TD-004 waits on the person (Owner: person) but its Blocked by has no decision' "$TMP/err" \
  && cmp -s "$L/TD-004.md" "$TMP/td4" && ok "set refuses Owner: person with no decision gate, writing nothing" || bad "ungated owner (rc=$rc): $(cat "$TMP/err")"
printf 'Should it go ahead?\n' > "$TMP/ask.md"
lp edit TD-004 --section Ask --from "$TMP/ask.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused' "$TMP/err" && cmp -s "$L/TD-004.md" "$TMP/td4" \
  && ok "an Ask written ahead of its gate is refused, writing nothing (ledgerboard v3.2 decision-missing, TD-272)" \
  || bad "ask before gate (rc=$rc): $(cat "$TMP/err")"
: > "$TMP/empty.md"
lp set TD-004 --blocked-by "decision (Alex)" --ask "$TMP/empty.md" >/dev/null 2>"$TMP/err"; r1=$?
lp set TD-004 --blocked-by "" --by Alex --ask "$TMP/ask.md" >/dev/null 2>"$TMP/err2"; r2=$?
[ $r1 -eq 2 ] && grep -q -- '--ask is empty' "$TMP/err" && [ $r2 -eq 2 ] && grep -q -- '--by lifts one' "$TMP/err2" \
  && cmp -s "$L/TD-004.md" "$TMP/td4" && ok "set refuses an empty --ask, and --ask with --by, writing nothing" \
  || bad "ask refusals (r1=$r1 r2=$r2): $(cat "$TMP/err" "$TMP/err2")"
lp set TD-004 --owner person --blocked-by "decision (Alex)" --ask "$TMP/ask.md" >/dev/null 2>"$TMP/err" \
  && grep -qx '\*\*Blocked by:\*\* decision (Alex)' "$L/TD-004.md" && grep -qx '\*\*Ask:\*\* Should it go ahead?' "$L/TD-004.md" \
  && ok "set --ask writes the Owner, its decision gate and its Ask in one write" || bad "gated owner: $(cat "$TMP/err")"
# TD-284 (ledgerboard v3.3): the Ask's context in its own **Context:** section, through set --context
printf 'The reader is `cache.py`.\n' > "$TMP/ctx1.md"
lp set TD-004 --context "$TMP/ctx1.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -A2 -x '\*\*Ask:\*\* Should it go ahead?' "$L/TD-004.md" | grep -qx '\*\*Context:\*\* The reader is `cache.py`.' \
  && grep -q "warning — the Ask's context: rule 4: .*cache.py" "$TMP/err" \
  && ok "set --context alone writes the Context right after the entry's Ask, rule 4 warning on its code" || bad "set --context (rc=$rc): $(cat "$TMP/err"; cat "$L/TD-004.md")"
printf 'Plain words now.\n' > "$TMP/ctx2.md"
lp set TD-004 --context "$TMP/ctx2.md" >/dev/null 2>"$TMP/err" && grep -qx '\*\*Context:\*\* Plain words now.' "$L/TD-004.md" \
  && [ "$(grep -c '^\*\*Context:\*\*' "$L/TD-004.md")" = 1 ] && ! grep -q 'rule 4' "$TMP/err" \
  && ok "a second set --context replaces the Context, one section, no warning on plain words" || bad "set --context again: $(cat "$TMP/err")"
cp "$L/TD-004.md" "$TMP/td4c"
printf 'Run `cache.py` by hand.\n' > "$TMP/ctx3.md"
lp edit TD-004 --section Context --from "$TMP/ctx3.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -q "warning — the Ask's context: rule 4: .*cache.py" "$TMP/err" && grep -qx '\*\*Context:\*\* Run `cache.py` by hand.' "$L/TD-004.md" \
  && ok "edit --section Context writes it with a rule 4 warning on its code" || bad "edit Context (rc=$rc): $(cat "$TMP/err")"
cp "$TMP/td4c" "$L/TD-004.md"
lp set TD-004 --ask - --context - </dev/null >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'only one section can come from stdin' "$TMP/err" && cmp -s "$L/TD-004.md" "$TMP/td4c" \
  && ok "set refuses --ask and --context both from stdin" || bad "set stdin (rc=$rc): $(cat "$TMP/err")"
lp set TD-001 --context "$TMP/ctx2.md" >/dev/null 2>"$TMP/err"; r1=$?
lp set TD-004 --blocked-by "" --by Alex --context "$TMP/ctx2.md" >/dev/null 2>"$TMP/err2"; r2=$?
lp set TD-004 --context "$TMP/empty.md" >/dev/null 2>"$TMP/err3"; r3=$?
[ $r1 -eq 1 ] && grep -q 'has no Ask' "$TMP/err" && [ $r2 -eq 2 ] && grep -q -- '--by lifts a decision' "$TMP/err2" \
  && [ $r3 -eq 2 ] && grep -q -- '--context is empty' "$TMP/err3" && cmp -s "$L/TD-004.md" "$TMP/td4c" \
  && ok "set refuses --context on an entry with no Ask, with --by, and empty, writing nothing" \
  || bad "set --context refusals (r1=$r1 r2=$r2 r3=$r3): $(cat "$TMP/err" "$TMP/err2" "$TMP/err3")"
# TD-285 (ledgerboard v3.3 SPEC *An entry's own answers*): set --answers/--lifts write the one-line fields the
# gate sweep offers; answers with no Go and no Lifts are refused (answers-unusable), and the pair lands in one write
cp "$L/TD-004.md" "$TMP/td4d"
lp set TD-004 --answers "Works — a session archives it | Not right — a session files a fix" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'answers-unusable' "$TMP/err" && cmp -s "$L/TD-004.md" "$TMP/td4d" \
  && ok "set --answers with no Go and no --lifts is refused (answers-unusable), writing nothing" || bad "unusable (rc=$rc): $(cat "$TMP/err")"
lp set TD-004 --answers "Works — a session archives it | Not right — a session files a fix" --lifts "Works" >/dev/null 2>"$TMP/err"; rc=$?
got=$(cd "$DC/files/scripts" && python3 -c 'import sys, ledgerboard as LB; print(LB.entry_answers(open(sys.argv[1]).read()))' "$L/TD-004.md")
[ $rc -eq 0 ] && [ "$got" = "{'answers': ['Works — a session archives it', 'Not right — a session files a fix'], 'default': None, 'lifts': ['Works']}" ] \
  && [ "$(grep -n '^\*\*Answers:\*\*' "$L/TD-004.md" | cut -d: -f1)" -lt "$(grep -n '^\*\*Lifts:\*\*' "$L/TD-004.md" | cut -d: -f1)" ] \
  && grep -qx '\*\*Blocked by:\*\* decision (Alex)' "$L/TD-004.md" \
  && ok "set --answers --lifts writes both one-line fields in one write, Answers first, readable by entry_answers()" || bad "answers+lifts (rc=$rc): $(cat "$TMP/err"; cat "$L/TD-004.md")"
cp "$L/TD-004.md" "$TMP/td4e"
lp set TD-004 --answers "Works — it is fine | Not right — a session files a fix" --lifts "Works" >/dev/null 2>"$TMP/err"; r1=$?
lp set TD-004 --answers "" >/dev/null 2>"$TMP/err2"; r2=$?
lp set TD-004 --blocked-by "" --by Alex --answers "Go — a session builds it" >/dev/null 2>"$TMP/err3"; r3=$?
[ $r1 -eq 1 ] && grep -q 'refused — the Answers: rule 2: answer 1 names nobody who acts' "$TMP/err" && [ $r2 -eq 2 ] && grep -q -- '--answers is empty' "$TMP/err2" \
  && [ $r3 -eq 2 ] && grep -q -- '--by lifts a decision' "$TMP/err3" && cmp -s "$L/TD-004.md" "$TMP/td4e" \
  && ok "set refuses an answer naming nobody (rule 2), an empty --answers, and --answers with --by, writing nothing" \
  || bad "answers refusals (r1=$r1 r2=$r2 r3=$r3): $(cat "$TMP/err" "$TMP/err2" "$TMP/err3")"
lp set TD-004 --lifts "Not right" >/dev/null 2>"$TMP/err" && grep -qx '\*\*Lifts:\*\* Not right' "$L/TD-004.md" \
  && [ "$(grep -c '^\*\*Lifts:\*\*' "$L/TD-004.md")" = 1 ] && ok "set --lifts alone rewrites the Lifts in place" || bad "lifts alone: $(cat "$TMP/err")"
cp "$TMP/td4d" "$L/TD-004.md"  # no Answers or Lifts yet
lp set TD-004 --priority High --answers "Go — a session builds it | Not yet — nobody picks it" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx '\*\*Priority:\*\* High' "$L/TD-004.md" && grep -qx '\*\*Answers:\*\* Go — a session builds it | Not yet — nobody picks it' "$L/TD-004.md" \
  && ok "set with a field and --answers writes both in one write" || bad "field + answers (rc=$rc): $(cat "$TMP/err")"
cp "$L/TD-004.md" "$TMP/td4f"
lp set TD-004 --answers "$(printf 'Go — a session builds it\n| Not yet — nobody')" >/dev/null 2>"$TMP/err"; r1=$?
lp set TD-002 --answers "Go — a session builds it" >/dev/null 2>"$TMP/err2"; r2=$?
[ $r1 -eq 2 ] && grep -q -- '--answers is one line' "$TMP/err" && [ $r2 -eq 2 ] && grep -q 'archived' "$TMP/err2" && cmp -s "$L/TD-004.md" "$TMP/td4f" \
  && ok "set refuses a multi-line --answers, and --answers on an archived entry" || bad "multi-line/archived (r1=$r1 r2=$r2): $(cat "$TMP/err" "$TMP/err2")"
cp "$TMP/td4d" "$L/TD-004.md"
printf '## TD-007: seven\n\n**Priority:** Low\n**Owner:** person\n**Status:** Open\n\n**Why:** standing.\n' > "$L/TD-007.md"
git -C "$W" add docs/ledger/TD-007.md; git -C "$W" commit -qm seven; git -C "$W" push -q origin main
lp set TD-007 --priority High >/dev/null 2>"$TMP/err"; rc=$?
c=$(lp --check --since origin/main 2>&1); crc=$?
bc=$(lp --check 2>&1); brc=$?
[ $rc -eq 0 ] && [ $crc -eq 0 ] && ! grep -q 'TD-007 .*no decision' <<< "$c" && [ $brc -eq 0 ] && grep -q '^ℹ TD-007 waits on the person (Owner: person) but .*no decision' <<< "$bc" \
  && ok "an entry already ungated on origin is standing: a set on it passes, --check --since passes, a bare --check (adopt's) says it as ℹ, rc 0" \
  || bad "standing ungated (rc=$rc crc=$crc): $(cat "$TMP/err") $c"
out=$(cd "$DC/files/scripts" && python3 - <<'PY'
import ledger as L
was = "## TD-009: x\n\n**Priority:** Low\n**Owner:** person\n**Status:** Open\n**Blocked by:** decision (Alex)\n\n**Why:** x.\n\n**Ask:** Go?\n"
now = was.replace("**Blocked by:** decision (Alex)\n", "")
new = now.replace("TD-009", "TD-010")
print(sorted((r["id"], r["level"]) for r in L.ungated_flags(now + new, "", was)))
PY
)
[ "$out" = "[('TD-009', 'info'), ('TD-010', 'error')]" ] \
  && ok "a lift that leaves the wait is standing (only its person drops a decision); a new ungated entry is an error" || bad "lift standing: $out"

# --- TD-268: text a person reads is checked at its writer (person_text.py: ledgerboard's rules, the process's words)
cp "$L/TD-004.md" "$TMP/td4b"
printf 'Say Go to build it, or Hold with a note.\n' > "$TMP/stmt.md"
lp edit TD-004 --section Ask --from "$TMP/stmt.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — the Ask: rule 1: .*does not end in ?' "$TMP/err" && cmp -s "$L/TD-004.md" "$TMP/td4b" \
  && ok "edit refuses an Ask that is a statement, not a question (rule 1), writing nothing" || bad "stmt ask (rc=$rc): $(cat "$TMP/err")"
printf 'Should the cache live on disk?\n\nThe reader is `cache.py`, which runs nightly.\n' > "$TMP/ctx.md"
cp "$L/TD-004.md" "$TMP/td4b"
lp edit TD-004 --section Ask --from "$TMP/ctx.md" >/dev/null 2>"$TMP/err"; rc=$?
# ledgerboard v3.3 (TD-283): an Ask is one line, so one with later paragraphs is refused (field-lines); rule 4 still
# reads the context and warns. Its context's new place, a **Context:** section, is TD-284's --context.
[ $rc -eq 1 ] && grep -q 'warning — the Ask: rule 4: .*cache.py' "$TMP/err" && grep -q 'refused — .*(field-lines)' "$TMP/err" \
  && cmp -s "$L/TD-004.md" "$TMP/td4b" \
  && ok "an Ask with context paragraphs is refused (field-lines, v3.3), its code still warned by rule 4, nothing written" \
  || bad "ctx ask (rc=$rc): $(cat "$TMP/err")"
cp "$L/TD-004.md" "$TMP/td4b"
printf 'Go — a session builds it | Hold\n' > "$TMP/ans.md"
lp edit TD-004 --section Answers --from "$TMP/ans.md" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — the Answers: rule 2: answer 2 names nobody who acts' "$TMP/err" && ! grep -q 'answer 1' "$TMP/err" \
  && cmp -s "$L/TD-004.md" "$TMP/td4b" && ok "edit refuses an answer that names nobody who acts (rule 2), passing one that names a session" \
  || bad "answers (rc=$rc): $(cat "$TMP/err")"
printf 'Go — a session builds it | Hold — you say what changes first\n' > "$TMP/ans.md"
lp edit TD-004 --section Answers --from "$TMP/ans.md" >/dev/null 2>"$TMP/err" && grep -q '^\*\*Answers:\*\* Go — a session builds it' "$L/TD-004.md" \
  && ok "answers that each say who acts are written" || bad "answers ok: $(cat "$TMP/err")"
out=$(cd "$DC/files/scripts" && python3 -c '
import ledgerboard as LB, person_text as PT
a = ["Go — a session builds it"]
print(len(LB.person_text_problems(None, a, question=True)), len(PT.answers_problems(a[0])))')
[ "$out" = "1 0" ] && ok "a right answer naming a session passes only because person_text.json's actors are passed" || bad "actors: $out"
cp "$L/TD-004.md" "$TMP/td4b"
lp set TD-004 --title "Fix S3 before the next slice" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — the title: rule 3: .*S3' "$TMP/err" && cmp -s "$L/TD-004.md" "$TMP/td4b" \
  && ok "set --title refuses a title holding a label or a coined word (rule 3), writing nothing" || bad "title (rc=$rc): $(cat "$TMP/err")"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
