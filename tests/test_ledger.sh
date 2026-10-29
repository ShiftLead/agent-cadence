#!/usr/bin/env bash
# TD-064: ledger.py --pickable — the Blocked by: field, pickable derived from the archive.
# Offline, fixture-driven: a ledger and an archive in a temp dir; HOME/XDG are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_PY="$DC/files/scripts/ledger.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg"; mkdir -p "$HOME" "$XDG_CONFIG_HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TODAY=$(date +%F)
L="$TMP/technical_debt.md"; A="$TMP/technical_debt_archive.md"

cat > "$L" <<EOF2
# ledger

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| TD-005 | low first in the table | Low | Open |
| TD-003 | medium open | Medium | Open |
| TD-4 | high but blocked on a live entry | High | Open |
| TD-006 | blocked on an archived entry | Medium | Open |
| TD-007 | blocked on a decision | High | Open |
| TD-008 | blocked on nothing that exists | Low | Open |
| TD-009 | unreadable blocker | Low | Open |
| TD-010 | no Priority line in the body | High | Open |
| TD-011 | empty field, next line a field | Low | Open |
| TD-012 | decision written first | Low | Open |

## TD-005: low first in the table

**Priority:** Low
**Added:** $TODAY
**Status:** Open

## TD-003: medium open

**Priority:** Medium
**Status:** Open

## TD-4: high but blocked on a live entry

**Priority:** High
**Status:** Open
**Blocked by:** TD-003

## TD-006: blocked on an archived entry

**Priority:** Medium
**Status:** Open
**Blocked by:** TD-001, TD-002

## TD-007: blocked on a decision

**Priority:** High
**Status:** Open
**Blocked by:** decision (Alex) — docs/user_attention.md, the $TODAY item

## TD-008: blocked on nothing that exists

**Priority:** Low
**Status:** Open
**Blocked by:** TD-999

## TD-009: unreadable blocker

**Priority:** Low
**Status:** Open
**Blocked by:** once CI lands

## TD-010: no Priority line in the body

**Status:** Open

## TD-011: empty field, next line a field

**Priority:** Low
**Status:** Open
**Blocked by:**
**Location:** somewhere

## TD-012: decision written first

**Priority:** Low
**Status:** Open
**Blocked by:** Decision(Alex), TD-003

## Design notes — not an entry

**Blocked by:** TD-003
EOF2
printf '# archive\n\n## TD-001: gone\n\n**Resolved:** %s (PR #1)\n\n## TD-2: legacy spelling\n' "$TODAY" > "$A"

out=$(python3 "$LEDGER_PY" --pickable --ledger "$L" --json 2>&1)
chk=$(python3 -c '
import json, sys
r = json.loads(sys.argv[1])
pick = [e["id"] for e in r["pickable"]]
blk = {e["id"]: e["blocked_by"] for e in r["blocked"]}
flags = "\n".join(r["flags"])
# TD-119: TD-003 (Medium) blocks High TD-4, so their card sorts at the High key of TD-4, ahead of TD-010
assert pick == ["TD-003", "TD-010", "TD-006", "TD-005", "TD-011"], pick
assert blk == {"TD-4": ["TD-003"], "TD-007": ["decision (Alex)"], "TD-008": ["TD-999"],
               "TD-009": ["\x27once CI lands\x27"],
               "TD-012": ["decision (Alex)", "\x27after the decision: TD-003\x27"]}, blk
assert "TD-006: every blocker is archived (TD-001, TD-002)" in flags, flags
assert "TD-008: Blocked by TD-999, which names no entry" in flags, flags
assert "TD-009: cannot read Blocked by item" in flags, flags
assert "TD-012: cannot read Blocked by item \x27after the decision: TD-003\x27" in flags, flags
assert "TD-011" not in flags, flags
assert len(r["flags"]) == 4, flags
print("ok")' "$out" 2>&1)
[ "$chk" = ok ] && ok "pick order by card (Priority, Type, id); blocked kinds; archived blockers lift; flags" || bad "--json: $chk / $out"

# archiving the blocker lifts the dependent with no edit to it
printf '\n## TD-003: medium open\n\n**Resolved:** %s (PR #3)\n' "$TODAY" >> "$A"
python3 - "$L" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"^## TD-003:.*?(?=^## )", "", s, flags=re.S | re.M)
s = re.sub(r"^\| TD-003 .*\n", "", s, flags=re.M)
open(p, "w").write(s)
PY
python3 "$LEDGER_PY" --pickable --ledger "$L" | grep -q "^  TD-4 .*high but blocked" \
  && ok "archiving the blocker makes its dependent pickable, no edit to it" || bad "TD-4 not lifted: $(python3 "$LEDGER_PY" --pickable --ledger "$L")"
python3 "$LEDGER_PY" --pickable --ledger "$L" | grep -q "^Blocked (4):" \
  && ok "text output: a Blocked section with its count" || bad "text Blocked section"

# no archive yet: nothing is archived, so a blocker naming no live entry is flagged
python3 "$LEDGER_PY" --pickable --ledger "$L" --archive "$TMP/none.md" | grep -q "TD-006: Blocked by TD-001, which names no entry" \
  && ok "a missing archive reads as empty" || bad "missing archive"

python3 "$LEDGER_PY" --pickable --ledger "$TMP/nope.md" >/dev/null 2>&1; [ $? = 2 ] \
  && ok "an unreadable ledger exits 2" || bad "unreadable ledger exit"

# the real ledger parses without flags it cannot explain (smoke: runs, exits 0)
# a published snapshot (snapshot_public.sh's README note, TD-090) carries none of this repo's own docs/,
# CLAUDE.md or .claude/: there a dogfood check whose file is absent is not run, said; here it always runs
snapshot() { grep -q '^> \*dev-cadence, published as agent-cadence\.\*' "$1/README.md"; }
if [ ! -e "$DC/docs/technical_debt.md" ] && snapshot "$DC"; then echo "NOTE: a published snapshot has no docs/ ledger — the own-ledger smoke check, not run"
else (cd "$DC" && python3 "$LEDGER_PY" --pickable >/dev/null 2>&1) && ok "runs on this repo's own ledger" || bad "own ledger"; fi

# §2.11 Type: debt before feature within a Priority; unmarked is debt; unknown is flagged, read as debt
T="$TMP/typed.md"
cat > "$T" <<EOF2
| ID | Title | Priority | Status |
|----|-------|----------|--------|
| TD-021 | feature, high, first in table | High | Open |
| TD-022 | unmarked, high | High | Open |
| TD-023 | debt spelled out, medium | Medium | Open |
| TD-024 | feature, medium, capitalised | Medium | Open |
| TD-025 | unknown type, low | Low | Open |
| TD-026 | empty Type field, low, blocked | Low | Open |

## TD-021: feature, high, first in table

**Priority:** High
**Type:** feature

## TD-022: unmarked, high

**Priority:** High

## TD-023: debt spelled out, medium

**Priority:** Medium
**Type:** debt

## TD-024: feature, medium, capitalised

**Priority:** Medium
**Type:** Feature

## TD-025: unknown type, low

**Priority:** Low
**Type:** chore

## TD-026: empty Type field, low, blocked

**Priority:** Low
**Type:**
**Blocked by:** TD-021
EOF2
out=$(python3 "$LEDGER_PY" --pickable --ledger "$T" --archive "$TMP/none.md" --json 2>&1)
chk=$(python3 -c '
import json, sys
r = json.loads(sys.argv[1])
assert [e["id"] for e in r["pickable"]] == ["TD-022", "TD-021", "TD-023", "TD-024", "TD-025"], r["pickable"]
t = {e["id"]: e["type"] for e in r["pickable"] + r["blocked"]}
assert t == {"TD-021": "feature", "TD-022": "debt", "TD-023": "debt", "TD-024": "feature",
             "TD-025": "debt", "TD-026": "debt"}, t
assert r["flags"] == ["⚠ TD-025: unknown Type \x27chore\x27 — write one of debt | feature; read as debt"], r["flags"]
print("ok")' "$out" 2>&1)
[ "$chk" = ok ] && ok "Type: debt before feature within a Priority; default debt; unknown flagged" || bad "Type: $chk / $out"
python3 "$LEDGER_PY" --pickable --ledger "$T" --archive "$TMP/none.md" | grep -q "^  TD-021  High    feature  feature, high" \
  && ok "text output shows the type" || bad "text type column: $(python3 "$LEDGER_PY" --pickable --ledger "$T" --archive "$TMP/none.md")"

# the seed ledger's commented-out entry template is not an entry (found in a consumer, 2026-09-28)
python3 "$LEDGER_PY" --pickable --ledger "$DC/files/docs/technical_debt.md" --archive "$TMP/none.md" --json \
  | python3 -c 'import json,sys; r=json.load(sys.stdin); sys.exit(0 if not r["pickable"] and not r["blocked"] else 1)' \
  && ok "the seed template's commented example entry is not read as an entry" || bad "commented template entry read as live"
printf '# l\n\n<!-- a note\n## TD-050: inside a comment\n**Priority:** High\n-->\n\n## TD-051: real\n\n**Priority:** Low\n' > "$TMP/c.md"
[ "$(python3 "$LEDGER_PY" --pickable --ledger "$TMP/c.md" --archive "$TMP/none.md" --json | python3 -c 'import json,sys; print(",".join(e["id"] for e in json.load(sys.stdin)["pickable"]))')" = "TD-051" ] \
  && ok "an entry inside an HTML comment is skipped; the real one after it is read" || bad "comment skipping"

# TD-070: every header field is read; --list / --where / --counts / --fields; a Fields: preamble
F="$TMP/fields.md"
cat > "$F" <<EOF2
# ledger with repo fields

Fields: \`Owner = grinder | designer | anchor; Kind = build | design-first | live-check\` — this repo's own
Fields: Priority = urgent | whenever; Broken

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| TD-031 | grinder build | High | Open |
| TD-032 | designer design-first | High | Open |
| TD-033 | grinder, blocked | Medium | Open |
| TD-034 | no owner | Medium | Open |
| TD-035 | owner out of vocabulary, pickable line wrong | Low | Open |
| TD-036 | Blocked by below the header block | Low | Open |

## TD-031: grinder build

**Priority:** High
**Owner:** grinder — anyone on the team
**Kind:** Build
**Added:** $TODAY
**Pickable:** yes

**Why:** the header block ends at the blank line above.
**Owner:** anchor

## TD-032: designer design-first

**Priority:** High
**Type:** feature — something new
**Owner:** designer
**Kind:** design-first

## TD-033: grinder, blocked

**Priority:** Medium
**Owner:** \`grinder\`
**Kind:** build
**Blocked by:** TD-031

## TD-034: no owner

**Priority:** Medium
**Kind:**

## TD-035: owner out of vocabulary, pickable line wrong

**Priority:** Low
**Owner:** alex
**Pickable:** no

## TD-036: Blocked by below the header block

**Priority:** Low
**Owner:** grinder

**Blocked by:** decision (Alex)
EOF2
lj() { python3 "$LEDGER_PY" --ledger "$F" --archive "$TMP/none.md" --json "$@"; }
ids() { python3 -c 'import json,sys; print(",".join(e["id"] for e in json.load(sys.stdin)["entries"]))'; }
[ "$(lj --list | ids)" = "TD-031,TD-033,TD-032,TD-034,TD-035,TD-036" ] \
  && ok "--list: every entry, pick order (Priority, Type, id; TD-033 rides on TD-031's card)" || bad "--list order: $(lj --list | ids)"
# --- TD-119: the rank file beside the ledger is the pick order (ledgerboard SPEC *The rank*)
RK="$TMP/rank"; mkdir -p "$RK"; cp "$F" "$RK/technical_debt.md"
rj() { python3 "$LEDGER_PY" --ledger "$RK/technical_debt.md" --archive "$TMP/none.md" --json "$@"; }
printf '# rank\nTD-035: 0h\nTD-033: 1i\n' > "$RK/technical_debt_rank.yml"
[ "$(rj --list | ids)" = "TD-035,TD-032,TD-031,TD-033,TD-034,TD-036" ] \
  && ok "--list in rank order: a lined Low entry first; a lined card (TD-031+TD-033) keeps its line's place, prerequisite first" \
  || bad "rank order: $(rj --list | ids)"
python3 "$LEDGER_PY" --ledger "$RK/technical_debt.md" --archive "$TMP/none.md" --pickable | grep -q "^  TD-035 " \
  && ok "--pickable prints rank order too" || bad "--pickable rank: $(python3 "$LEDGER_PY" --ledger "$RK/technical_debt.md" --archive "$TMP/none.md" --pickable)"
printf 'TD-035 0h\n' > "$RK/technical_debt_rank.yml"
python3 "$LEDGER_PY" --ledger "$RK/technical_debt.md" --archive "$TMP/none.md" --check --json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if [f for f in d["flags"] if f["kind"] == "rank" and f["level"] == "error"] else 1)' \
  && ok "--check flags an unreadable rank file line as an error" || bad "rank flag: $(python3 "$LEDGER_PY" --ledger "$RK/technical_debt.md" --archive "$TMP/none.md" --check)"
[ "$(rj --list | ids)" = "TD-031,TD-033,TD-032,TD-034,TD-035,TD-036" ] \
  && ok "an unreadable line ranks nothing: the implicit order" || bad "bad rank line order: $(rj --list | ids)"
[ "$(lj --list --owner grinder | ids)" = "TD-031,TD-033,TD-036" ] \
  && ok "--owner: first word, case- and markup-insensitive; below-the-block lines are not fields" || bad "--owner: $(lj --list --owner grinder | ids)"
[ "$(lj --list --owner grinder --pickable yes | ids)" = "TD-031" ] \
  && ok "--pickable yes filters on the derived pickable" || bad "--pickable yes: $(lj --list --owner grinder --pickable yes | ids)"
[ "$(lj --list --pickable no | ids)" = "TD-033,TD-036" ] \
  && ok "--pickable no; a Blocked by below the block still blocks" || bad "--pickable no: $(lj --list --pickable no | ids)"
[ "$(lj --list --where kind=BUILD --where OWNER=grinder | ids)" = "TD-031,TD-033" ] \
  && ok "--where terms AND, keys and values case-insensitive" || bad "--where AND: $(lj --list --where kind=BUILD --where OWNER=grinder | ids)"
[ "$(lj --list --where owner= | ids),$(lj --list --kind= | ids)" = "TD-034,TD-034,TD-035,TD-036" ] \
  && ok "FIELD= keeps entries with the field absent or empty" || bad "FIELD=: $(lj --list --where owner= | ids) / $(lj --list --kind= | ids)"
[ "$(lj --list --type debt | ids)" = "TD-031,TD-033,TD-034,TD-035,TD-036" ] \
  && ok "--type matches the derived type (no field is debt)" || bad "--type: $(lj --list --type debt | ids)"
[ "$(lj --list --where 'blocked-by=decision' | ids)" = "TD-036" ] \
  && ok "a spaced field name reads with - or _" || bad "blocked-by: $(lj --list --where blocked-by=decision | ids)"
out=$(lj --list)
chk=$(python3 -c '
import json, sys
r = json.loads(sys.argv[1]); e = {x["id"]: x for x in r["entries"]}
a = e["TD-031"]
assert a["fields"] == {"priority": "High", "owner": "grinder — anyone on the team", "kind": "Build",
                       "added": a["fields"]["added"], "pickable": "yes"}, a["fields"]
assert (a["pickable"], a["blocked_by"], a["type"], a["priority"]) == (True, [], "debt", "High"), a
assert e["TD-032"]["type"] == "feature", e["TD-032"]
assert e["TD-033"]["blocked_by"] == ["TD-031"] and e["TD-033"]["pickable"] is False, e["TD-033"]
fl = "\n".join(r["flags"])
assert "TD-035: owner \x27alex\x27 is not in the preamble" in fl, fl
assert "TD-035: its Pickable line says no, the derived pickable is yes" in fl, fl
assert "TD-031: its Pickable" not in fl, fl
assert "TD-036: its Blocked by line is below the header block" in fl, fl
assert "Fields: cannot read \x27Broken\x27" in fl, fl
assert "Fields: \x27priority\x27 is the cadence" in fl, fl
assert "TD-032" not in fl and "TD-034" not in fl, fl
assert len(r["flags"]) == 5, fl
print("ok")' "$out" 2>&1)
[ "$chk" = ok ] && ok "--json: fields raw; written Pickable only flagged; vocabulary, below-block and Fields: flags" || bad "fields json: $chk / $out"
[ "$(lj --counts owner,kind | python3 -c 'import json,sys; print(";".join(f"{r["owner"]}/{r["kind"]}={r["count"]}" for r in json.load(sys.stdin)["counts"]))')" \
  = "grinder/build=2;alex/(none)=1;designer/design-first=1;grinder/(none)=1;(none)/(none)=1" ] \
  && ok "--counts owner,kind: per value pair, (none) for absent, most first" || bad "--counts: $(lj --counts owner,kind)"
python3 "$LEDGER_PY" --ledger "$F" --archive "$TMP/none.md" --counts owner --pickable no | grep -q '^     2  owner=grinder$' \
  && ok "--counts text, filtered by --pickable" || bad "--counts text: $(python3 "$LEDGER_PY" --ledger "$F" --archive "$TMP/none.md" --counts owner --pickable no)"
out=$(lj --fields)
chk=$(python3 -c '
import json, sys
f = {x["field"]: x for x in json.loads(sys.argv[1])["fields"]}
assert f["owner"]["defined_by"] == "preamble" and f["owner"]["declared"] == ["grinder", "designer", "anchor"], f["owner"]
assert f["owner"]["values"] == {"grinder": 3, "designer": 1, "alex": 1}, f["owner"]
assert f["pickable"]["defined_by"] == "undeclared" and f["priority"]["defined_by"] == "cadence", f
assert f["kind"]["values"]["(empty)"] == 1, f["kind"]
print("ok")' "$out" 2>&1)
[ "$chk" = ok ] && ok "--fields: every field, who defines it, values seen, vocabulary" || bad "--fields: $chk / $out"
python3 "$LEDGER_PY" --ledger "$F" --pickable | grep -q '^Pickable (4)' \
  && ok "--pickable alone is unchanged by the new fields" || bad "--pickable report"
for args in "--list --counts owner" "--pickable yes" "--list --where owner" "--fields --owner x" "--counts a,b,c" "" "--list --pickable maybe"; do
  # shellcheck disable=SC2086
  python3 "$LEDGER_PY" --ledger "$F" $args >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok "unusable arguments exit 2: '$args'" || bad "args '$args' exited $rc"
done

# TD-071: <repo>#TD-NNN resolves through the roster to another clone's ledger and archive
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
X="$TMP/xrepo"; mkdir -p "$X/roster"
mkrepo() {  # mkrepo DIR LIVE_IDS ARCHIVED_IDS — a repo with a ledger and an archive in its working tree
  mkdir -p "$1/docs"; git -C "$1" init -q -b main
  : > "$1/docs/technical_debt.md"; for i in $2; do printf '## %s: live\n\n**Priority:** Low\n\n' "$i" >> "$1/docs/technical_debt.md"; done
  : > "$1/docs/technical_debt_archive.md"; for i in $3; do printf '## %s: gone\n\n**Resolved:** %s\n\n' "$i" "$TODAY" >> "$1/docs/technical_debt_archive.md"; done
  git -C "$1" add -A && git -C "$1" commit -qm init
}
git init -q --bare -b main "$X/other.git"
mkrepo "$X/other" "TD-040" "TD-036"
git -C "$X/other" remote add origin "$X/other.git"; git -C "$X/other" push -q origin main; git -C "$X/other" fetch -q origin
# the working tree moves on (TD-040 archived, not pushed): origin/main must win
mv "$X/other/docs/technical_debt.md" "$X/other/docs/gone.md"; : > "$X/other/docs/technical_debt.md"
printf '## TD-040: now gone locally\n' >> "$X/other/docs/technical_debt_archive.md"
mkrepo "$X/plain" "" "TD-002"
mkrepo "$X/a/dup" "" "TD-001"; git -C "$X/a/dup" remote add origin https://github.com/acme/dup.git
mkrepo "$X/b/dup" "TD-001" ""; git -C "$X/b/dup" remote add origin git@github.com:zed/dup.git
mkdir -p "$X/noledger"; git -C "$X/noledger" init -q
printf '%s\n' "$X/other" "$X/plain" "$X/a/dup" "$X/b/dup" "$X/noledger" "# a comment" > "$X/roster/repos.txt"
XL="$TMP/xl.md"
cat > "$XL" <<'EOF2'
## TD-101: blocked on another repo's archived entry

**Priority:** High
**Blocked by:** other#TD-036

## TD-102: blocked on another repo's open entry (origin, not the working tree)

**Priority:** High
**Blocked by:** other#TD-040

## TD-103: repo not on the roster

**Priority:** High
**Blocked by:** nowhere#TD-001

## TD-104: entry the other repo does not have

**Priority:** High
**Blocked by:** other#TD-999

## TD-105: ambiguous basename

**Priority:** High
**Blocked by:** dup#TD-001

## TD-106: owner/name and a working-tree-only repo, both archived

**Priority:** Medium
**Blocked by:** acme/dup#TD-001, plain#TD-002

## TD-107: on the roster with no ledger

**Priority:** Medium
**Blocked by:** noledger#TD-001

## TD-108: cross-repo archived, but a decision too

**Priority:** Low
**Blocked by:** other#TD-036, decision (Alex) — see the board

## TD-109: owner/name that is open

**Priority:** Low
**Blocked by:** Zed/Dup#TD-001, TD-101
EOF2
out=$(DEV_CADENCE_REG_DIR="$X/roster" python3 "$LEDGER_PY" --pickable --ledger "$XL" --archive "$TMP/none.md" --json 2>&1)
chk=$(python3 -c '
import json, sys
r = json.loads(sys.argv[1])
assert [e["id"] for e in r["pickable"]] == ["TD-101", "TD-106"], r["pickable"]
blk = {e["id"]: e["blocked_by"] for e in r["blocked"]}
assert blk == {"TD-102": ["other#TD-040"], "TD-103": ["nowhere#TD-001"], "TD-104": ["other#TD-999"],
               "TD-105": ["dup#TD-001"], "TD-107": ["noledger#TD-001"], "TD-108": ["decision (Alex)"],
               "TD-109": ["Zed/Dup#TD-001", "TD-101"]}, blk
x = {e["id"]: e["cross_repo"] for e in r["pickable"] + r["blocked"]}
assert [(c["state"], c["source"]) for c in x["TD-102"]] == [("open", "origin/main")], x["TD-102"]
assert [(c["state"], c["source"]) for c in x["TD-106"]] == [("archived", "working tree")] * 2, x["TD-106"]
assert x["TD-101"][0]["root"].endswith("/other") and x["TD-101"][0]["state"] == "archived", x["TD-101"]
assert x["TD-109"][0]["state"] == "open" and x["TD-109"][0]["root"].endswith("/b/dup"), x["TD-109"]
fl = "\n".join(r["flags"])
for want in ("TD-101: every blocker is archived (other#TD-036)",
             "TD-106: every blocker is archived (acme/dup#TD-001, plain#TD-002)",
             "TD-103: cannot resolve nowhere#TD-001 — not on this machine\x27s roster; the block stays",
             "TD-104: cannot resolve other#TD-999 — other has no TD-999 in its ledger or archive (origin/main)",
             "TD-105: cannot resolve dup#TD-001 — 2 roster repos are named dup — write owner/name",
             "TD-107: cannot resolve noledger#TD-001 — no readable docs/technical_debt.md"):
    assert want in fl, (want, fl)
assert "TD-108" not in fl and "TD-102" not in fl and "TD-109" not in fl, fl
assert len(r["flags"]) == 6, fl
print("ok")' "$out" 2>&1)
[ "$chk" = ok ] && ok "<repo>#TD-NNN: lifted, open (origin wins), unknown repo/entry, ambiguous, owner/name, no ledger" || bad "cross-repo: $chk / $out"
mkdir -p "$X/empty"
DEV_CADENCE_REG_DIR="$X/empty" python3 "$LEDGER_PY" --pickable --ledger "$XL" --archive "$TMP/none.md" | grep -q "TD-101: cannot resolve other#TD-036 — no roster on this machine; the block stays" \
  && ok "no roster file: every cross-repo item keeps its block" || bad "no roster: $(DEV_CADENCE_REG_DIR="$X/empty" python3 "$LEDGER_PY" --pickable --ledger "$XL" --archive "$TMP/none.md")"
DEV_CADENCE_REG_DIR="$X/roster" python3 "$LEDGER_PY" --pickable --ledger "$XL" --archive "$TMP/none.md" | grep -q "^  TD-102 .* — by other#TD-040$" \
  && ok "text output names the cross-repo blocker" || bad "text cross-repo"
# a hung git in another clone (a stuck NFS mount, a held lock) degrades to unresolved, never a crash
mkdir -p "$X/shim"; REALGIT=$(command -v git)
printf '#!/bin/sh\ncase " $* " in *" show "*|*" cat-file "*) sleep 5;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$X/shim/git"; chmod +x "$X/shim/git"
hung=$(PATH="$X/shim:$PATH" LEDGER_GIT_TIMEOUT=1 DEV_CADENCE_REG_DIR="$X/roster" python3 "$LEDGER_PY" --pickable --ledger "$XL" --archive "$TMP/none.md" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "TD-102: cannot resolve other#TD-040 — no readable docs/technical_debt.md" <<<"$hung" \
  && grep -q "TD-101: cannot resolve other#TD-036" <<<"$hung" \
  && ok "a git call that times out leaves the item blocked and flagged; the run exits 0" || bad "hung git: rc=$rc $hung"
DEV_CADENCE_REG_DIR="$X/roster" python3 "$LEDGER_PY" --list --owner nobody --ledger "$XL" --archive "$TMP/none.md" >/dev/null 2>&1 \
  && ok "--list runs with cross-repo items" || bad "--list cross-repo"

[ -x "$LEDGER_PY" ] && ok "ledger.py is executable" || bad "ledger.py not executable"
grep -q '"scripts/ledger.py"' "$DC/sync.sh" && ok "sync.sh ships ledger.py" || bad "sync.sh does not ship ledger.py"


# --- TD-073: --check exits 1 on an error; --since judges the edit, not the ledger -------
# A git repo, because --since reads the ledger at a ref. No roster: DEV_CADENCE_REG_DIR is empty.
C="$TMP/chk"; mkdir -p "$C/docs" "$TMP/reg"; git init -q -b main "$C"
export DEV_CADENCE_REG_DIR="$TMP/reg"
cgit() { git -C "$C" -c user.email=t@t -c user.name=t "$@"; }
CL="$C/docs/technical_debt.md"
ent() { # id, then header lines
  local id=$1; shift; printf '## %s: entry %s\n\n' "$id" "$id"; printf '%s\n' "$@"; printf '\n**Why:** because.\n\n---\n\n'
}
chk() { ( cd "$C" && python3 "$LEDGER_PY" --check "$@" 2>&1 ); }
{ printf '# ledger\n\n'; ent TD-001 '**Priority:** Low' '**Added:** '"$TODAY" '**Status:** Open'; } > "$CL"
out=$(chk); rc=$?; [ $rc -eq 0 ] && [ "$out" = "ledger check: 0 error(s)" ] && ok "--check: a clean ledger exits 0 and prints only the tally" || bad "clean: rc=$rc $out"
# each ⚠ kind exits 1 and names the entry
one() { # label, kind, id-or-null — judges the ledger just written to $CL
  local out rc; out=$(chk --json); rc=$?
  echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); e=[f for f in d["flags"] if f["level"]=="error"]; want=None if sys.argv[2]=="null" else sys.argv[2]; assert d["errors"]==len(e)==1 and e[0]["kind"]==sys.argv[1] and e[0]["id"]==want and e[0]["standing"] is False and set(e[0])=={"level","id","field","kind","text","standing"}, d' "$2" "$3" 2>/dev/null \
    && [ $rc -eq 1 ] && ok "--check: $1 is an error, rc 1, kind $2 on $3" || bad "$1: rc=$rc $out"
}
{ printf '# ledger\n\n'; ent TD-001 '**Priority:** Low' '**Type:** chore' '**Status:** Open'; } > "$CL"; one "an unknown Type" type TD-001
{ printf '# ledger\n\nFields: Owner = grinder | designer\n\n'; ent TD-001 '**Priority:** Low' '**Owner:** nobody' '**Status:** Open'; } > "$CL"; one "a value outside a declared vocabulary" vocabulary TD-001
{ printf '# ledger\n\n'; ent TD-001 '**Priority:** Low' '**Status:** Open' '**Blocked by:** after lunch'; } > "$CL"; one "an unreadable Blocked by item" blocked-item TD-001
{ printf '# ledger\n\n'; ent TD-001 '**Priority:** Low' '**Status:** Open' '**Blocked by:** TD-999'; } > "$CL"; one "a Blocked by naming no entry" blocked-unknown TD-001
{ printf '# ledger\n\n'; ent TD-001 '**Priority:** Low' '**Status:** Open' '**Blocked by:** nowhere#TD-001'; } > "$CL"; one "an unresolvable cross-repo item" cross-repo TD-001
{ printf '# ledger\n\nFields: Owner\n\n'; ent TD-001 '**Priority:** Low' '**Status:** Open'; } > "$CL"; one "a Fields: line it cannot read" fields-decl null
# ℹ lines stay information without --since: a written Pickable that disagrees, an undeclared field
{ printf '# ledger\n\nFields: Owner = grinder | designer\n\n'; ent TD-001 '**Priority:** Low' '**Status:** Open' '**Pickable:** no — design-first: later' '**Owner:** grinder'; } > "$CL"
out=$(chk); rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q "^ℹ TD-001: its Pickable line says no" && echo "$out" | grep -q "^ℹ TD-001: field 'pickable' has no vocabulary" \
  && ok "--check without --since: a Pickable disagreement and an undeclared field are information, rc 0" || bad "info stays info: rc=$rc $out"
# TD-166: a wait on an id written in a field's prose, not in Blocked by, is an ℹ (kind prose-wait) —
# on a live entry, an archived one and another repo's; never one Blocked by names, a bare id that names
# no entry here (someone else's, written without its repo), a Waits: event citing one, or Related
printf '# archive\n\n## TD-005: done\n\n**Status:** Resolved\n\n**Why:** x.\n' > "$C/docs/technical_debt_archive.md"
{ printf '# ledger\n\n'
  ent TD-001 '**Priority:** Low' '**Status:** Open; waits on TD-002 landing.'
  ent TD-002 '**Priority:** Low' '**Status:** Open'
  ent TD-003 '**Priority:** Low' '**Status:** Built. Left: waits for TD-005, then this archives'
  ent TD-004 '**Priority:** Low' '**Status:** Open, blocked by shiftlead#TD-1038'"'"'s live run'
  ent TD-006 '**Priority:** Low' '**Status:** waits on TD-002' '**Blocked by:** TD-002'
  ent TD-007 '**Priority:** Low' '**Status:** app-repo waits on shiftlead TD-1014 slice 5'
  ent TD-008 '**Priority:** Low' '**Status:** Open' '**Waits:** event — shiftlead#TD-9'"'"'s live look'
  ent TD-009 '**Priority:** Low' '**Status:** Open' '**Related:** waits on TD-002'; } > "$CL"
out=$(chk --json); rc=$?
echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
got = sorted((f["id"], f["field"], f["text"].split(" waits on ")[1].split(",")[0]) for f in d["flags"] if f["kind"] == "prose-wait")
assert got == [("TD-001", "status", "TD-002"), ("TD-003", "status", "TD-005"), ("TD-004", "status", "shiftlead#TD-1038")], got
assert all(f["level"] == "info" and not f["standing"] for f in d["flags"] if f["kind"] == "prose-wait") and d["errors"] == 0, d' \
  && [ $rc -eq 0 ] && ok "--check: a prose wait on a live, an archived and another repo's id is an ℹ; Blocked by, a foreign bare id, a Waits: event and Related are not" \
  || bad "prose-wait: rc=$rc $out"
out=$(chk); grep -qx "ℹ TD-001: its Status field waits on TD-002, which its Blocked by does not name — name it in Blocked by, where --pickable sees it archived (cadence.md §2.4)" <<< "$out" \
  && ok "--check text: the prose wait names the entry, the field and the id" || bad "prose-wait text: $out"
cgit add -A; cgit commit -qm "prose waits"
out=$(cd "$C" && python3 "$LEDGER_PY" --check --since HEAD --json)
echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); w=[f for f in d["flags"] if f["kind"]=="prose-wait"]; assert len(w)==3 and all(f["standing"] for f in w), w' \
  && ok "--check --since: a prose wait already there at REF is standing" || bad "prose-wait standing: $out"
# TD-172: an id in Blocked by's decision pointer (never parsed) is a prose wait too, unless an item names it
cp "$CL" "$TMP/ledger.saved"
{ printf '# ledger\n\n'
  ent TD-002 '**Priority:** Low' '**Status:** Open'
  ent TD-010 '**Priority:** Low' '**Status:** Open' '**Blocked by:** decision (Alex) — once TD-005 is built, and TD-002'
  ent TD-011 '**Priority:** Low' '**Status:** Open' '**Blocked by:** TD-002, decision (Alex) — once TD-002 lands'
  ent TD-012 '**Priority:** Low' '**Status:** Open' '**Blocked by:** decision (Alex) — after shiftlead#TD-77 is live'
  ent TD-013 '**Priority:** Low' '**Status:** Open' '**Blocked by:** decision (Alex) — see shiftlead TD-1014'; } > "$CL"
out=$(chk --json); rc=$?
echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
got = sorted((f["id"], f["field"], f["text"].split(" names ")[1].split(",")[0]) for f in d["flags"] if f["kind"] == "prose-wait")
assert got == [("TD-010", "blocked by", "TD-002"), ("TD-010", "blocked by", "TD-005"), ("TD-012", "blocked by", "shiftlead#TD-77")], got
assert d["errors"] == 0, d' && [ $rc -eq 0 ] \
  && ok "--check: an id in a Blocked by's decision pointer is a prose wait; one an item names, or a foreign bare id, is not (TD-172)" || bad "pointer wait: rc=$rc $out"
out=$(chk); grep -qF "ℹ TD-012: its Blocked by's decision pointer names shiftlead#TD-77, which no item of it names — move it before the decision (shiftlead#TD-77, decision (…) — …)" <<< "$out" \
  && ok "--check text: the pointer wait says to move the id before the decision" || bad "pointer wait text: $out"
cp "$TMP/ledger.saved" "$CL"
rm "$C/docs/technical_debt_archive.md"; cgit rm -q --cached docs/technical_debt_archive.md; cgit commit -qm "no archive"
# the text form prints the flag, then the tally
{ printf '# ledger\n\n'; ent TD-001 '**Priority:** Low' '**Type:** chore' '**Status:** Open'; } > "$CL"
out=$(chk); rc=$?; [ $rc -eq 1 ] && echo "$out" | head -1 | grep -q "^⚠ TD-001: unknown Type 'chore'" && [ "$(echo "$out" | tail -1)" = "ledger check: 1 error(s)" ] \
  && ok "--check text: the flag, then the tally, rc 1" || bad "text: rc=$rc $out"
# the other modes are untouched: same ledger, exit 0, flags still strings
out=$( cd "$C" && python3 "$LEDGER_PY" --pickable --json ); rc=$?
echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert set(d)=={"pickable","blocked","flags"} and all(isinstance(f,str) for f in d["flags"]) and len(d["flags"])==1' && [ $rc -eq 0 ] \
  && ok "--pickable is unchanged by --check: exit 0, flags are sentences" || bad "pickable json changed: rc=$rc $out"

# --since: a ledger that was never clean passes; the edit that adds a bad field does not
{ printf '# ledger\n\nFields: Owner = grinder | designer\n\n'
  ent TD-001 '**Priority:** Low' '**Type:** chore' '**Status:** Open'
  ent TD-002 '**Priority:** Low' '**Status:** Open' '**Pickable:** no — design-first'
  ent TD-003 '**Priority:** Low' '**Status:** Open' '**Owner:** grinder'; } > "$CL"
cgit add -A; cgit commit -qm "a ledger with standing flags"; cgit branch -q base
out=$(chk); rc=$?; [ $rc -eq 1 ] && ok "--check on the standing ledger fails (TD-001's Type)" || bad "standing plain: rc=$rc $out"
out=$(chk --since base); rc=$?; [ $rc -eq 0 ] && [ "$out" = "ledger check: 0 error(s); 3 standing flag(s) on entries unchanged since base, not shown" ] \
  && ok "--since: standing flags pass, counted and not printed" || bad "standing since: rc=$rc $out"
# a body edit below the header block does not make an entry count
sed -i 's/^\*\*Why:\*\* because\.$/**Why:** because, and more./' "$CL"
out=$(chk --since base); rc=$?; [ $rc -eq 0 ] && ok "--since: a changed body with an unchanged header is not counted" || bad "body edit: rc=$rc $out"
# a NEW entry with a Pickable that disagrees: the ShiftLead case — an error under --since
ent TD-004 '**Priority:** Low' '**Status:** Open' '**Pickable:** no — design-first: wait' '**Owner:** designer' >> "$CL"
out=$(chk --since base); rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q "^⚠ TD-004: its Pickable line says no, the derived pickable is yes" && echo "$out" | grep -q "^⚠ TD-004: field 'pickable' has no vocabulary" && ! echo "$out" | grep -q "TD-002\|TD-001" \
  && echo "$out" | tail -1 | grep -q "^ledger check: 2 error(s); 3 standing" && ok "--since: a new entry's Pickable disagreement and undeclared field are errors; standing ones stay out" || bad "new disagreement: rc=$rc $out"
out=$(chk --since base --json); echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); e=sorted((f["id"],f["kind"],f["field"]) for f in d["flags"] if f["level"]=="error"); assert e==[("TD-004","pickable-disagrees","pickable"),("TD-004","undeclared-field","pickable")] and d["errors"]==2 and all(f["standing"] and f["level"]=="info" for f in d["flags"] if f["id"]!="TD-004"), d' \
  && ok "--since --json: errors keyed by id, kind and field; standing flags are info" || bad "since json: $out"
cgit checkout -q -- docs
# an EDITED header on a standing entry makes its old flag count again
sed -i 's/^\*\*Type:\*\* chore$/**Type:** chore\n**Added:** '"$TODAY"'/' "$CL"
out=$(chk --since base); rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "^⚠ TD-001: unknown Type" && ok "--since: touching a flagged entry's header makes its flag count" || bad "edited header: rc=$rc $out"
cgit checkout -q -- docs
# a changed Fields: declaration that cannot be read counts; an unchanged one would not
sed -i 's/^Fields: Owner = grinder | designer$/Fields: Owner = grinder | designer; Kind/' "$CL"
out=$(chk --since base); rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "^⚠ Fields: cannot read 'Kind'" && ok "--since: a Fields: line edited into something unreadable is an error" || bad "decl edit: rc=$rc $out"
cgit checkout -q -- docs
# a ledger that did not exist at the ref: every entry is new
e=$(cgit commit-tree -m none "$(cgit hash-object -t tree /dev/null)")
out=$(chk --since "$e"); rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "TD-001" && echo "$out" | grep -q "TD-002" && ok "--since a ref with no ledger: every entry is new" || bad "no ledger at ref: rc=$rc $out"
# a CRLF ledger at the ref and in the tree: nothing changed, so nothing counts (the ref is read as bytes)
sed -i 's/$/\r/' "$CL"; cgit commit -qam crlf; cgit branch -q crlf
out=$(chk --since crlf); rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q "^ledger check: 0 error(s); 3 standing" && ok "--since: a CRLF ledger unchanged since the ref has no counted entries" || bad "crlf: rc=$rc $out"
cgit checkout -q base -- docs
# a Type value that is only whitespace-like (a lone CR) is no Type, never a traceback
printf '# ledger\n\n## TD-001: x\n\n**Priority:** Low\n**Type:** \r\n**Status:** Open\n' > "$CL"
out=$(chk); rc=$?; [ $rc -eq 0 ] && ! echo "$out" | grep -q Traceback && ok "--check: a Type of only a carriage return reads as no Type, no traceback" || bad "cr type: rc=$rc $out"
cgit checkout -q base -- docs
# an unknown ref, and --since without --check: exit 2, said
out=$(chk --since no-such-ref); rc=$?; [ $rc -eq 2 ] && echo "$out" | grep -q "no commit 'no-such-ref'" && ok "--since an unknown ref exits 2 and says so" || bad "bad ref: rc=$rc $out"
out=$( cd "$C" && python3 "$LEDGER_PY" --pickable --since base 2>&1 ); rc=$?; [ $rc -eq 2 ] && ok "--since without --check is a usage error" || bad "since alone: rc=$rc $out"
unset DEV_CADENCE_REG_DIR

# TD-167: a parent held by its open parts says so in every text mode — never an empty reason
P="$TMP/parts.md"
cat > "$P" <<EOF2
# ledger

## TD-001: parent held only by its parts

**Priority:** Medium
**Status:** Open

## TD-002: a part of TD-001

**Priority:** Low
**Status:** Open
**Part of:** TD-001

## TD-003: parent held by its part and a blocker

**Priority:** Medium
**Status:** Open
**Blocked by:** TD-005

## TD-004: a part of TD-003

**Priority:** Low
**Status:** Open
**Part of:** TD-003

## TD-005: the blocker

**Priority:** Low
**Status:** Open
EOF2
pp() { python3 "$LEDGER_PY" --ledger "$P" --archive "$TMP/none.md" "$@" 2>&1; }
out=$(pp --pickable)
echo "$out" | grep -q "^  TD-001 .* — by parts open: TD-002$" && echo "$out" | grep -q "^  TD-003 .* — by TD-005; parts open: TD-004$" \
  && ok "--pickable names a parent's open parts, alone and after its blocker" || bad "--pickable parts: $out"
out=$(pp --list)
echo "$out" | grep -q "^  TD-001 .* — blocked by parts open: TD-002$" && echo "$out" | grep -q "^  TD-003 .* — blocked by TD-005; parts open: TD-004$" \
  && ok "--list names a parent's open parts, alone and after its blocker" || bad "--list parts: $out"
out=$(pp --summary)
echo "$out" | grep -q "^| TD-001 | .* | blocked by parts open: TD-002 |$" && echo "$out" | grep -q "^| TD-003 | .* | blocked by TD-005; parts open: TD-004 |$" \
  && ok "--summary names a parent's open parts, alone and after its blocker" || bad "--summary parts: $out"
for m in --pickable --list --summary; do
  pp "$m" | grep -Eq "(— by|blocked by) *(\||$)" && bad "$m prints an empty blocked reason: $(pp "$m")"
done

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
