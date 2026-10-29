#!/usr/bin/env bash
# TD-075: what nudge_user_attention.py --report --json gives a tool, so that no tool parses a
# board line or a fetch_note sentence itself — per item `session`, `host`, `refs`; per board
# `fetch_case` (one of FETCH_CASES) and `fetch_why`; and the SessionStart line keeps a reply
# tail whole past the clip.
#
# Offline: every origin is a local bare repo (or a path that does not exist); HOME,
# XDG_CONFIG_HOME and DEV_CADENCE_REG_DIR are temp; dates derive from the run date (TD-24).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$DC/files/scripts/nudge_user_attention.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
T0=$(date +%F); RAISED=$(date -d '2 days ago' +%F)

# --- 1) per item: session, host, refs ------------------------------------------------
B="$TMP/r/docs/user_attention.md"; mkdir -p "$(dirname "$B")"
cat > "$B" <<BOARD
# board

## Needs the user

- [ ] decide $RAISED (session abcdef12 on testhost) — pick one. Context: TD-036 / PR #184 / td036-answers. Due: $T0. Answers: a | b.
- [ ] watch $RAISED (session \`grinder-y-2\` on \`testhost\`, branch x) — look. Context: TD-250 (archived), PR #871, PR #873. Due: $T0.
- [ ] $RAISED (session \`c0ffee01\` / \`grinder-x-2\` on testhost) — two names. Context: dev-cadence#TD-071 / branch \`td437-x\` / TD-071. Due: $T0.
- [ ] $RAISED (n/a) — no session, no context. Due: $T0.
- [ ] act $RAISED (session c0ffee02 on devcontainer \`ab01\`; updated) — prose says session zz on elsewhere. Context: n/a. Due: $T0.
- [ ] $RAISED (the anchor session on testhost) — not the documented head. Context: PR #5 and PR #5 again, TD-9. Due: $T0.
- [ ] $RAISED (session n/a on n/a) — the Format line's n/a. Context: PRs #12/#13, PR #14, #15 and #16. Due: $T0.
- [ ] $RAISED (session ab12cd34 on testhost) — not branches. Context: none / shiftlead / docs/plans/x.md / c0ffee03 / branch main. Due: $T0.
BOARD
got=$(python3 "$N" --report --json --board "$B" | python3 -c '
import json, sys
b = json.load(sys.stdin)["boards"][0]
assert b["fetch_case"] is None and b["fetch_why"] is None, b   # no --fetch: no case
it = b["items"]
f = lambda i: (i["session"], i["host"], i["refs"])
assert f(it[0]) == ("abcdef12", "testhost", ["TD-036", "PR #184", "branch td036-answers"]), f(it[0])
assert f(it[1]) == ("grinder-y-2", "testhost", ["TD-250", "PR #871", "PR #873"]), f(it[1])
assert f(it[2]) == ("c0ffee01", "testhost", ["dev-cadence#TD-071", "branch td437-x", "TD-071"]), f(it[2])
assert f(it[3]) == (None, None, []), f(it[3])
assert f(it[4]) == ("c0ffee02", "devcontainer", []), f(it[4])
assert f(it[5]) == (None, None, ["PR #5", "TD-9"]), f(it[5])
assert f(it[6]) == (None, None, ["PR #12", "PR #13", "PR #14", "PR #15", "PR #16"]), f(it[6])
assert f(it[7]) == ("ab12cd34", "testhost", ["branch main"]), f(it[7])   # a word, a file, an id: not a branch; "branch main" says so
print("ok")' 2>&1)
[ "$got" = ok ] && ok "--json items: session and host from the head, refs from Context: (TD, PR, branch), null/empty when absent" || bad "item fields: $got"

# --- 2) per board: fetch_case, one word per case ---------------------------------------
# mk <name>: a clone of a bare origin with a board on main; prints nothing
mk() {
  git init -q --bare -b main "$TMP/$1.git"; git clone -q "$TMP/$1.git" "$TMP/$1" 2>/dev/null
  ( cd "$TMP/$1" && git checkout -q -b main 2>/dev/null; mkdir -p docs \
    && printf '# board\n\n## Needs the user\n\n- [ ] %s (session abcdef12 on h) — base item. Due: %s.\n' "$RAISED" "$T0" > docs/user_attention.md \
    && git add -A && git commit -qm board && git push -q -u origin main ) 2>/dev/null
}
add() { printf -- '- [ ] %s (n/a) — %s. Due: %s.\n' "$RAISED" "$2" "$T0" >> "$1/docs/user_attention.md"; }
# another clone pushes a board edit, so origin moves without this clone knowing
push_from_elsewhere() {
  git clone -q "$TMP/$1.git" "$TMP/$1.other" 2>/dev/null
  ( cd "$TMP/$1.other" && add . "origin item" && git commit -qam other && git push -q origin HEAD:main ) 2>/dev/null
}
mk matches
mk behind;  push_from_elsewhere behind
mk local;   add "$TMP/local" "local item"; git -C "$TMP/local" commit -qam local
mk both;    push_from_elsewhere both; add "$TMP/both" "local item"; git -C "$TMP/both" commit -qam local
mk none;    ( cd "$TMP/none" && git rm -q docs/user_attention.md && git commit -qm "no board" && git push -q origin main \
              && printf '# board\n\n## Needs the user\n\n- [ ] %s (n/a) — only here. Due: %s.\n' "$RAISED" "$T0" > docs/user_attention.md ) 2>/dev/null
mk unrelated; ( cd "$TMP/unrelated" && git checkout -q --orphan fresh && add . "orphan item" && git add -A && git commit -qm orphan ) 2>/dev/null
mk skipped; git -C "$TMP/skipped" remote set-url origin "$TMP/no-such-origin.git"
args=(); for r in matches behind local both none unrelated skipped; do args+=(--board "$TMP/$r/docs/user_attention.md"); done
got=$(python3 "$N" --report --json --fetch "${args[@]}" 2>/dev/null | python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as NA
rows = {r["label"]: r for r in json.load(sys.stdin)["boards"]}
want = ["matches", "behind", "local", "both", "none", "unrelated", "skipped"]
assert sorted(want) == sorted(NA.FETCH_CASES), ("the suite covers every FETCH_CASES word", NA.FETCH_CASES)
for name in want:
    r = rows[name]
    assert r["fetch_case"] == name, (name, r["fetch_case"], r["fetch_note"])
    assert (r["fetch_why"] is not None) == (name == "skipped"), (name, r["fetch_why"])
    assert r["fetch_note"], name                       # the sentence stays, for people
assert rows["skipped"]["fetch_why"] in rows["skipped"]["fetch_note"], rows["skipped"]
assert rows["behind"]["source"] == "origin/main" and any("origin item" in i["text"] for i in rows["behind"]["items"]), rows["behind"]
print("ok")' "$DC/files/scripts" 2>&1)
[ "$got" = ok ] && ok "--json --fetch: fetch_case is one word per case (all of FETCH_CASES), fetch_why only on a skip, fetch_note kept" || bad "fetch cases: $got"

# --- 3) the SessionStart line keeps a reply tail whole past the clip ---------------------
LONG=$(printf 'word %.0s' $(seq 1 80))   # 400 chars: well past MAX_ITEM_CHARS
TAILTXT="— Alex, $T0: yes, but only the second half — and keep the old name. — Alex, $T0: also tell the techlead"
cat > "$B" <<BOARD
# board

## Needs the user

- [ ] decide $RAISED (session abcdef12 on testhost) — ${LONG}end-of-prose. Context: TD-1. Due: $T0. $TAILTXT
- [ ] act $RAISED (session abcdef12 on testhost) — ${LONG}no-reply-here. Due: $T0.
- [ ] act $RAISED (session abcdef12 on testhost) — short. Due: $T0. — Alex, $T0: fine
- [ ] act $RAISED (session abcdef12 on testhost) — looks-like-a-reply — Merged, $T0: ${LONG}prose-end. Due: $T0.
BOARD
out=$(python3 "$N" --report --due-only --board "$B" 2>&1)
l1=$(grep "decide $RAISED" <<< "$out"); l2=$(grep "no-reply-here\|word word" <<< "$out" | grep -v "decide $RAISED" | head -1); l3=$(grep "short\." <<< "$out")
grep -qF "… $TAILTXT" <<< "$l1" && ! grep -q "end-of-prose" <<< "$l1" && ok "due-only: a clipped item prints its reply tails whole after the clipped head" || bad "reply tail: $l1"
[ -n "$l2" ] && ! grep -q "no-reply-here" <<< "$l2" && [[ "$l2" == *"…" ]] && ok "due-only: an item with no reply is clipped as before" || bad "plain clip: $l2"
grep -qF "short. Due: $T0. — Alex, $T0: fine" <<< "$l3" && ok "due-only: a short item with a reply is printed as written" || bad "short reply: $l3"

chk=$(python3 "$N" --report --json --board "$B" 2>&1 | python3 -c '
import json, sys
t0 = sys.argv[1]
it = json.load(sys.stdin)["boards"][0]["items"]
by = {i["line"]: i["replies"] for i in it}
assert by[5] == [{"by": "Alex", "date": t0, "text": "yes, but only the second half — and keep the old name."},
                 {"by": "Alex", "date": t0, "text": "also tell the techlead"}], by[5]
assert by[6] == [] and by[8] == [], (by[6], by[8])
assert by[7] == [{"by": "Alex", "date": t0, "text": "fine"}], by[7]
print("ok")' "$T0" 2>&1)
[ "$chk" = ok ] && ok "--json: replies (by, date, text) in order; none for a plain item or for prose before the Due:" || bad "replies json: $chk"

l4=$(grep "looks-like-a-reply" <<< "$out")
! grep -q "prose-end" <<< "$l4" && [[ "$l4" == *"…" ]] && ok "due-only: prose shaped like a reply, before the Due:, does not defeat the clip" || bad "false reply: ${l4:0:300}"

# --- 4) TD-152: each ref's state, stated and never judged — a bare TD is the board's own repo's
# (archived, with its Resolved date; open; unresolved), a PR is asked of the forge only under --fetch
O4="$TMP/o4.git"; R4="$TMP/r4"; git init -q --bare -b main "$O4"; git clone -q "$O4" "$R4" 2>/dev/null
mkdir -p "$R4/docs"
printf '# ledger\n\n## TD-050: an open one\n\n**Priority:** low\n**Status:** Open\n' > "$R4/docs/technical_debt.md"
printf '# archive\n\n## TD-275: done\n\n**Priority:** low\n\n**Why:** x.\n\n**Resolved:** %s (PR #9). Done.\n\n## TD-276: no date\n\n**Why:** y.\n' "$RAISED" > "$R4/docs/technical_debt_archive.md"
cat > "$R4/docs/user_attention.md" <<BOARD
# board

## Needs the user

- [ ] act $RAISED (session s1 on testhost) — refs. Context: TD-275 / TD-050 / TD-999 / TD-276 / PR #784 / branch td-x. Due: $T0.
BOARD
git -C "$R4" add -A && git -C "$R4" commit -qm seed && git -C "$R4" push -q origin main 2>/dev/null
states() { python3 -c '
import json, sys
it = json.load(sys.stdin)["boards"][0]["items"][0]
print("|".join("%s=%s:%s" % (r["ref"], r["state"], r["resolved"] or "") for r in it["ref_states"]))
print(next(r["why"] for r in it["ref_states"] if r["ref"] == "PR #784"))'; }
got=$(cd "$R4" && python3 "$N" --report --json --board "$R4/docs/user_attention.md" | states)
want="TD-275=archived:$RAISED|TD-050=open:|TD-999=unresolved:|TD-276=archived:|PR #784=None:
not looked up (no --fetch)"
[ "$got" = "$want" ] && ok "TD-152 --json: archived with its date, open, unresolved, archived without one; a PR not looked up without --fetch; a branch left out" || bad "ref states: $got"
mkdir -p "$TMP/bin4"
cat > "$TMP/bin4/gh" <<'SHIM'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "pr view 784") st=MERGED; [ "$PWD" = "$R5" ] && st=OPEN
                 echo '{"number":784,"url":"u","state":"'"$st"'","title":"t","body":"","baseRefName":"main","headRefName":"x","headRefOid":"0000000000000000000000000000000000000000","files":[]}' ;;
  *) echo '[]' ;;
esac
SHIM
chmod +x "$TMP/bin4/gh"
got=$(cd "$R4" && PATH="$TMP/bin4:$PATH" CADENCE_FORGE=github python3 "$N" --report --json --fetch --board "$R4/docs/user_attention.md" | states | head -1)
[[ "$got" == *"|PR #784=merged:" ]] && ok "TD-152 --json --fetch: the PR's state from the forge" || bad "ref states fetch: $got"
R5="$TMP/r5"; git clone -q "$O4" "$R5" 2>/dev/null; export R5
got=$(cd "$TMP" && PATH="$TMP/bin4:$PATH" CADENCE_FORGE=github python3 "$N" --report --json --fetch \
      --board "$R4/docs/user_attention.md" --board "$R5/docs/user_attention.md" | python3 -c '
import json, sys
print(" ".join(next(r["state"] for r in b["items"][0]["ref_states"] if r["ref"] == "PR #784") for b in json.load(sys.stdin)["boards"]))')
[ "$got" = "merged open" ] && ok "TD-152 --fetch over two boards: each PR asked of its own board's repo" || bad "two repos: $got"
out=$(cd "$R4" && python3 "$N" --report --board "$R4/docs/user_attention.md")
grep -qF "      refs: TD-275 archived $RAISED · TD-050 open · TD-999 unresolved (r4 has no TD-999 in its ledger or archive (origin/main)) ⚠ not this repo's: write \`<repo>#TD-999\` · TD-276 archived · PR #784 state unknown (not looked up (no --fetch))" <<< "$out" \
  && ok "TD-152 text report: a refs: line under the item" || bad "refs line: $(grep refs: <<< "$out")"

# TD-153: a bare TD neither the ledger nor the archive has is warned about; one it has, or one unreadable, is not
got=$(cd "$R4" && python3 "$N" --report --json --board "$R4/docs/user_attention.md" | python3 -c '
import json, sys
print("|".join("%s=%s" % (r["ref"], r.get("warning")) for r in json.load(sys.stdin)["boards"][0]["items"][0]["ref_states"]))')
[ "$got" = 'TD-275=None|TD-050=None|TD-999=not this repo'"'"'s: write `<repo>#TD-999`|TD-276=None|PR #784=None' ] \
  && ok "TD-153 --json: a bare id the ledger and archive lack carries the warning; the others carry none" || bad "warning: $got"
R6="$TMP/r6"; mkdir -p "$R6/docs"; cp "$R4/docs/user_attention.md" "$R6/docs/"
got=$(cd "$R6" && python3 "$N" --report --json --board "$R6/docs/user_attention.md" | python3 -c '
import json, sys
print(next(r.get("warning") for r in json.load(sys.stdin)["boards"][0]["items"][0]["ref_states"] if r["ref"] == "TD-999"))')
[ "$got" = None ] && ok "TD-153: no warning when the board's ledger cannot be read (it may well have the id)" || bad "unreadable ledger warned: $got"

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
