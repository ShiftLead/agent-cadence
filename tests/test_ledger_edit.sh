#!/usr/bin/env bash
# TD-199: `ledger.py set`, `note` and `edit` change one open entry of a v2 ledger through
# ledgerboard's edit_entry(), refusing what the gate would fail. Asserts: set changes a field in place
# and removes one with an empty value; note keeps the earlier Status and adds a dated line; edit
# replaces one section and leaves the header and the other sections alone, and adds a missing Fix
# after the Why; refusals leave the file untouched — an unknown Type, a wait in prose (TD-166), an id
# in a decision's pointer (TD-172), a cross-repo blocker its roster repo lacks, an entry canonical()
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
  printf '## TD-002: archived\n\n**Priority:** Low\n**Status:** Resolved %s: done\n\n**Why:** a fixture.\n\n**Resolved:** %s\n' \
    "$TODAY" "$TODAY" > "$L/archive/TD-002.md"
  printf '## TD-003: three\n\n**Priority:** Low\n**Added:** %s\n**Status:** Open — first look done\n**Location:** x.py\n\n**Why:** because.\n\n**Fix:** old fix.\n\n**Done when** it is.\n' \
    "$TODAY" > "$L/TD-003.md"
  printf '## TD-004: four\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** only a why.\n\n**Related:** TD-001.\n' > "$L/TD-004.md"
  printf '## TD-005: five\n\n**Priority:** Low\n**Priority:** High\n\n**Why:** twice.\n' > "$L/TD-005.md"
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
hdr=$(sed -n '3,9p' "$L/TD-003.md")
want="**Priority:** High
**Added:** $TODAY
**Owner:** grinder
**Status:** Open — first look done
**Blocked by:** TD-001
**Location:** x.py"
[ $rc -eq 0 ] && [ "$out" = "$L/TD-003.md" ] && [ "$hdr" = "$want" ] \
  && ok "set changes a field in place and adds others where SPEC's order puts them" || bad "set (rc=$rc): $(cat "$TMP/err") $hdr"
c=$(lp --check --since origin/main 2>&1) && lp fmt --check TD-003 >/dev/null 2>&1 \
  && ok "the edited entry passes --check --since and fmt --check" || bad "check after set: $c"
lp set TD-003 --blocked-by "" >/dev/null 2>"$TMP/err" && ! grep -q 'Blocked by' "$L/TD-003.md" \
  && ok "set with an empty value removes the field" || bad "set remove: $(cat "$TMP/err")"

# --- 2) note: the earlier Status kept, a dated line added.
lp note TD-003 "reproduced it" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 0 ] && grep -qx "\*\*Status:\*\* Open — first look done $TODAY: reproduced it" "$L/TD-003.md" \
  && ok "note keeps the earlier Status text and appends a dated line" || bad "note (rc=$rc): $(cat "$TMP/err") $(grep Status "$L/TD-003.md")"

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
lp note TD-003 "waits on TD-001 now" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — .*waits on TD-001' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "note refuses a wait written in prose (TD-166)" || bad "prose note (rc=$rc): $(cat "$TMP/err")"
lp set TD-003 --blocked-by "decision (paul) — after TD-001 lands" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'refused — .*decision pointer names TD-001' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && ok "set refuses an id in a decision's pointer (TD-172)" || bad "pointer (rc=$rc): $(cat "$TMP/err")"
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
: > "$AGENT_CADENCE_REG_DIR/repos.txt"
lp note TD-005 "x" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'twice' "$TMP/err" && same TD-005.md \
  && ok "an entry canonical() refuses is refused with its hand fix" || bad "refused entry (rc=$rc): $(cat "$TMP/err")"
lp note TD-002 "x" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'archived' "$TMP/err" && same archive/TD-002.md \
  && ok "an archived entry is not edited" || bad "archived (rc=$rc): $(cat "$TMP/err")"
lp set TD-099 --priority Low >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'in neither' "$TMP/err" && ok "an unknown id exits 2" || bad "unknown (rc=$rc)"
lp set TD-001 >/dev/null 2>&1; r1=$?
lp edit TD-001 --section Fix --from /dev/null >/dev/null 2>&1; r2=$?
[ $r1 -eq 2 ] && [ $r2 -eq 2 ] && same TD-001.md && ok "set with no field and an empty edit are usage errors" || bad "usage: $r1 $r2"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
