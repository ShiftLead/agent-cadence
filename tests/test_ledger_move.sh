#!/usr/bin/env bash
# TD-200: `ledger.py archive`, `reopen` and `renumber` move an entry, or rename one, as one command.
# Asserts: archive writes the archived form (Status, the Fix replaced by **Resolved:**) and git-mvs the
# file to archive/ (staged; the archive/ made when none exists), its relative links rewritten one level
# down, a link to it from another file named; reopen moves it back, links one level up;
# archiving again leaves one **Resolved:** section; --superseded-by keeps the Fix; a parent with an open
# part is refused, as is an archived entry archived again or an open one reopened; renumber takes its id
# from the counter, moves the file, rewrites its dependents' Blocked by and Part of (in ledger/ and
# archive/) and the rank file,
# writes the take's Taken by, and names a reference in prose; an entry canonical() refuses stops it
# before any take, writing nothing; an archived entry is not renumbered; none of the three commits.
# Offline: origin is a local bare repo, the roster a temp dir; HOME/XDG are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_CODE_REMOTE CADENCE_FORGE
export CLAUDE_CODE_SESSION_ID=fixture-session LEDGER_IDS_RACE_SECONDS=20
BY=$(printf %s fixture-session | sha256sum | cut -c1-12)
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)

# A v2 ledger: TD-001 (links to TD-004 and a doc), TD-003 a parent with TD-004 Part of it,
# TD-004 Blocked by TD-001, TD-005 a field twice; TD-002 archived; TD-001 ranked.
mkrepo() {  # $1 origin dir, $2 clone dir
  rm -rf "$1" "$2" "$TMP/seed"; git init -q --bare -b main "$1"
  git init -q -b main "$TMP/seed"; local L="$TMP/seed/docs/ledger"; mkdir -p "$L/archive" "$TMP/seed/docs/plans"
  printf '# Ledger\n\nLedgerboard: 2\n' > "$L/README.md"
  printf 'a plan\n' > "$TMP/seed/docs/plans/p.md"
  printf '## TD-001: one\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** see [four](TD-004.md) and [the plan](../plans/p.md).\n\n**Fix:** do it.\n\n**Done when** done.\n' > "$L/TD-001.md"
  printf '## TD-002: archived\n\n**Priority:** Low\n**Status:** Resolved %s: done\n\n**Why:** a fixture.\n\n**Resolved:** %s\n' \
    "$TODAY" "$TODAY" > "$L/archive/TD-002.md"
  printf '## TD-003: parent\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** a parent, after [one](TD-001.md).\n' > "$L/TD-003.md"
  printf '## TD-007: archived part\n\n**Priority:** Low\n**Status:** Resolved %s: done\n**Part of:** TD-003\n\n**Why:** a fixture.\n\n**Resolved:** %s\n' \
    "$TODAY" "$TODAY" > "$L/archive/TD-007.md"
  printf '## TD-004: part\n\n**Priority:** Low\n**Status:** Open\n**Blocked by:** TD-001\n**Part of:** TD-003\n\n**Why:** a part.\n' > "$L/TD-004.md"
  printf '## TD-005: five\n\n**Priority:** Low\n**Priority:** High\n**Blocked by:** TD-003\n\n**Why:** twice.\n' > "$L/TD-005.md"
  printf '# rank\nTD-001: m\nTD-004: n\n' > "$L/rank.yml"
  git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed
  git -C "$TMP/seed" push -q "$1" main; rm -rf "$TMP/seed"
  git clone -q "$1" "$2"
}
O="$TMP/o"; W="$TMP/w"; mkrepo "$O" "$W"
L="$W/docs/ledger"
lp() { (cd "$W" && python3 "$LEDGER_PY" "$@"); }
head_is() { [ "$(git -C "$W" rev-parse HEAD)" = "$(git -C "$W" rev-parse origin/main)" ]; }

# --- 1) archive: the archived form, the file git-mv'd, its links one level down.
out=$(lp archive TD-001 --why "built it" --pr 7 --pointer "tests/x.sh" 2>"$TMP/err"); rc=$?
f="$L/archive/TD-001.md"
if [ $rc -eq 0 ] && [ "$out" = "$f" ] && [ ! -e "$L/TD-001.md" ] \
   && grep -qx "\*\*Status:\*\* Resolved $TODAY: built it" "$f" \
   && grep -qx "\*\*Resolved:\*\* $TODAY (PR #7) — tests/x.sh" "$f" && ! grep -q '^\*\*Fix' "$f" \
   && grep -q '(\.\./TD-004\.md)' "$f" && grep -q '(\.\./\.\./plans/p\.md)' "$f" \
   && git -C "$W" diff --quiet && [ "$(git -C "$W" diff --cached --name-only --no-renames | sort | tr '\n' ' ')" = "docs/ledger/TD-001.md docs/ledger/archive/TD-001.md " ] \
   && grep -q 'check — a link to the moved file.*TD-003.md' "$TMP/err"; then
  ok "archive writes the archived form, rewrites its links for archive/, git-mvs the file staged, and names a link to it"
else
  bad "archive (rc=$rc) out=$out: $(cat "$TMP/err") $(cat "$f" 2>/dev/null) [$(git -C "$W" status --porcelain)]"
fi
head_is && ok "archive commits nothing" || bad "archive committed"
lp archive TD-001 --why x >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'archived already' "$TMP/err" && ok "an archived entry is not archived again" || bad "re-archive (rc=$rc): $(cat "$TMP/err")"

# --- 2) reopen: moved back, links one level up; archive again keeps one Resolved section.
out=$(lp reopen TD-001 --why "it came back" 2>"$TMP/err"); rc=$?
f="$L/TD-001.md"
if [ $rc -eq 0 ] && [ "$out" = "$f" ] && [ ! -e "$L/archive/TD-001.md" ] \
   && grep -qx "\*\*Status:\*\* Open $TODAY: it came back — was: Resolved $TODAY: built it" "$f" \
   && grep -q '(TD-004\.md)' "$f" && grep -q '(\.\./plans/p\.md)' "$f" && grep -q 'edit TD-001 --section Fix' "$TMP/err"; then
  ok "reopen writes the reopened Status, moves the file back with its links, and names the next step"
else
  bad "reopen (rc=$rc) out=$out: $(cat "$TMP/err") $(cat "$f" 2>/dev/null)"
fi
lp reopen TD-001 --why x >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'is open' "$TMP/err" && ok "an open entry is not reopened" || bad "reopen open (rc=$rc): $(cat "$TMP/err")"
lp archive TD-001 --why "built again" --pr 8 >/dev/null 2>"$TMP/err"; rc=$?
f="$L/archive/TD-001.md"
[ $rc -eq 0 ] && [ "$(grep -c '^\*\*Resolved:\*\*' "$f")" = 1 ] && grep -qx "\*\*Resolved:\*\* $TODAY (PR #8)" "$f" \
  && ok "archive, reopen, archive leaves one **Resolved:** section" || bad "re-archive (rc=$rc): $(cat "$TMP/err") $(cat "$f")"
c=$(lp --check 2>&1) && ok "the ledger passes --check after the moves" || bad "check: $c"

# --- 3) Refusals: a parent with an open part; a bad PR; nothing written.
cp "$L/TD-003.md" "$TMP/td3"
lp archive TD-003 --why "done" >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'TD-004' "$TMP/err" && grep -q 'Part of' "$TMP/err" && cmp -s "$L/TD-003.md" "$TMP/td3" \
  && [ ! -e "$L/archive/TD-003.md" ] && ok "archiving a parent with an open part is refused, writing nothing" \
  || bad "open part (rc=$rc): $(cat "$TMP/err")"
lp archive TD-003 --why "done" --superseded-by TD-003 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && cmp -s "$L/TD-003.md" "$TMP/td3" && ok "superseded by itself is refused" || bad "self-supersede (rc=$rc)"
lp archive TD-099 --why x >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'in neither' "$TMP/err" && ok "an unknown id exits 2" || bad "unknown (rc=$rc)"

# --- 4) renumber: a dependent canonical() refuses (TD-005 names TD-003) stops it before any take.
git -C "$W" add -A; git -C "$W" commit -qm moves; git -C "$W" push -q origin HEAD:main
ctr() { git -C "$O" rev-parse -q --verify refs/heads/cadence/ledger-ids || echo none; }
before=$(ctr)
lp renumber TD-003 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'TD-005' "$TMP/err" && [ -e "$L/TD-003.md" ] && [ -z "$(git -C "$W" status --porcelain)" ] \
  && [ "$before" = "$(ctr)" ] && ok "a dependent canonical() refuses stops the renumber before any take, writing nothing" \
  || bad "refused dependent (rc=$rc): $(cat "$TMP/err") $(git -C "$W" status --porcelain)"

# --- 5) renumber: the counter's id, the file moved, dependents and the rank rewritten, prose named.
printf '## TD-005: five\n\n**Priority:** High\n**Blocked by:** TD-003\n\n**Why:** fixed.\n' > "$L/TD-005.md"
printf 'TD-003 is the parent.\n' > "$W/docs/plans/q.md"
git -C "$W" add -A; git -C "$W" commit -qm fixed; git -C "$W" push -q origin HEAD:main
out=$(lp renumber TD-003 2>"$TMP/err"); rc=$?
n="$L/TD-008.md"
if [ $rc -eq 0 ] && [ "$(head -1 <<<"$out")" = "$n" ] && [ ! -e "$L/TD-003.md" ] \
   && head -1 "$n" | grep -qx '## TD-008: parent' && grep -qx "\*\*Taken by:\*\* $BY" "$n" \
   && grep -qx '\*\*Part of:\*\* TD-008' "$L/TD-004.md" && grep -qx '\*\*Blocked by:\*\* TD-008' "$L/TD-005.md" \
   && grep -qx '\*\*Part of:\*\* TD-008' "$L/archive/TD-007.md" \
   && grep -q 'plans/q.md' "$TMP/err"; then
  ok "renumber takes the counter's id, moves the file, writes its Taken by, rewrites Part of and Blocked by in ledger/ and archive/, names prose"
else
  bad "renumber (rc=$rc) out=$out: $(cat "$TMP/err") $(ls "$L")"
fi
[ -z "$(git -C "$W" log origin/main..HEAD --oneline)" ] && ok "renumber commits nothing" || bad "renumber committed"
c=$(lp --check 2>&1) && ok "the ledger passes --check after the renumber" || bad "check after renumber: $c"
git -C "$W" add -A; git -C "$W" commit -qm renum; git -C "$W" push -q origin HEAD:main

# The rank file: TD-004 renumbered keeps its key under the new id; an archived entry is not renumbered.
out=$(lp renumber TD-004 2>"$TMP/err"); rc=$?
nid=$(basename "$(head -1 <<<"$out")" .md)
[ $rc -eq 0 ] && [ "$nid" != TD-004 ] && grep -qx "$nid: n" "$L/rank.yml" && ! grep -q '^TD-004:' "$L/rank.yml" \
  && grep -qx 'TD-001: m' "$L/rank.yml" && ok "renumber moves the id's rank line, keeping its key" \
  || bad "rank (rc=$rc) out=$out: $(cat "$TMP/err") $(cat "$L/rank.yml")"
git -C "$W" add -A; git -C "$W" commit -qm renum2; git -C "$W" push -q origin HEAD:main
lp renumber TD-001 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 1 ] && grep -q 'archive lost TD-001' "$TMP/err" && [ -e "$L/archive/TD-001.md" ] \
  && ok "an archived entry is not renumbered: the gate's archive-loss refuses it" || bad "archived renumber (rc=$rc): $(cat "$TMP/err")"
lp renumber TD-005 TD-002 >/dev/null 2>"$TMP/err"; rc=$?
[ $rc -eq 2 ] && grep -q 'already' "$TMP/err" && ok "renumbering onto an id the ledger holds is refused" || bad "onto held (rc=$rc): $(cat "$TMP/err")"

# --- 6) A ledger with nothing archived has no archive/ in git: archive makes it.
rm -rf "$TMP/o3" "$TMP/w3" "$TMP/seed"; git init -q --bare -b main "$TMP/o3"; git init -q -b main "$TMP/seed"
mkdir -p "$TMP/seed/docs/ledger"; printf '# Ledger\n\nLedgerboard: 2\n' > "$TMP/seed/docs/ledger/README.md"
printf '## TD-001: one\n\n**Priority:** Low\n**Status:** Open\n\n**Why:** a fixture.\n' > "$TMP/seed/docs/ledger/TD-001.md"
git -C "$TMP/seed" add -A; git -C "$TMP/seed" commit -qm seed; git -C "$TMP/seed" push -q "$TMP/o3" main; git clone -q "$TMP/o3" "$TMP/w3"
out=$( (cd "$TMP/w3" && python3 "$LEDGER_PY" archive TD-001 --why done) 2>"$TMP/err"); rc=$?
[ $rc -eq 0 ] && [ -e "$TMP/w3/docs/ledger/archive/TD-001.md" ] && [ ! -e "$TMP/w3/docs/ledger/TD-001.md" ] \
  && grep -q '^\*\*Status:\*\* Resolved' "$TMP/w3/docs/ledger/archive/TD-001.md" \
  && ok "archive makes the archive/ a ledger with nothing archived lacks" || bad "no archive/ (rc=$rc): $(cat "$TMP/err")"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
