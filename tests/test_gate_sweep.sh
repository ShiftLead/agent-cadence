#!/usr/bin/env bash
# TD-219 (slice 2): gate_sweep.py, the gate sweep's reads around ledgerboard's sweep(), as a plan. It reads
# this repo's ledger and every roster board at origin/<default> (never a work tree's edit in progress), runs
# the event checks, and prints what sweep() would file, close and lift — writing nothing.
#
# Offline: origin/main is a ref made with update-ref, never fetched; `gh` is a PATH shim answering
# `gh api <path>` from fixture files. HOME, XDG_CONFIG_HOME, AGENT_CADENCE_REG_DIR and git config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CADENCE_FORGE
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BIN="$TMP/bin"; FIX="$TMP/fix"; mkdir -p "$BIN" "$FIX"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ "$1" = api ] || { echo "gh-shim: unhandled: $*" >&2; exit 64; }
key=$(printf %s "$2" | tr '/?=' '___')
[ -e "$FIX/$key.404" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
[ -e "$FIX/$key" ] && { cat "$FIX/$key"; exit 0; }
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" FIX
fx() { printf '%s' "$2" > "$FIX/$(printf %s "$1" | tr '/?=' '___')"; }
fx repos/o/own '{"visibility":"private","default_branch":"main"}'
fx repos/o/oth '{"visibility":"private","default_branch":"main"}'
fx repos/o/oth/pulls/3 '{"state":"closed","merged":true}'

TODAY=$(date -u +%F)
PAST=$(date -u -d "$TODAY -3 days" +%F 2>/dev/null || python3 -c 'import datetime as d; print(d.date.fromisoformat("'"$TODAY"'") - d.timedelta(days=3))')
board() { printf '# Attention\n\nPeople: %s\n\n## Needs the user\n\n%s\n' "$1" "${2:-}"; }
entry() {   # entry <dir> <n> <blocked by> [more body]
  { printf '## TD-%03d: entry %s\n\n**Priority:** Medium\n**Added:** 2026-01-01\n**Status:** Open\n' "$2" "$2"
    printf '**Blocked by:** %s\n**Location:** x\n\n**Why:** y\n' "$3"
    [ -n "${4:-}" ] && printf '\n%s\n' "$4"
  } > "$1/docs/ledger/TD-$(printf %03d "$2").md"
}
publish() { git -C "$1" add -A && git -C "$1" commit -qm "fixture" && git -C "$1" update-ref refs/remotes/origin/main HEAD; }
mkrepo() {
  git init -q -b main "$1"; git -C "$1" remote add origin "$2"
  mkdir -p "$1/docs/ledger/archive"; printf '# Ledger\n' > "$1/docs/ledger/README.md"
  echo "$1" >> "$AGENT_CADENCE_REG_DIR/repos.txt"
}
OWN="$TMP/own"; mkrepo "$OWN" https://github.com/o/own.git
OTH="$TMP/oth"; mkrepo "$OTH" https://github.com/o/oth.git
board alex > "$OWN/docs/user_attention.md"
board sam > "$OTH/docs/user_attention.md"
entry "$OWN" 1 "decision (alex)" '**Ask:** Ship the thing?'
entry "$OWN" 2 "decision (sam)" '**Ask:** Rename it?'
entry "$OWN" 3 "until $PAST"
entry "$OWN" 4 "event (landed)" "$(printf '**Event (landed):** the PR lands.\ncheck: pr-merged o/oth#3')"
entry "$OWN" 5 "event (broken)" "$(printf '**Event (broken):** the PR lands.\ncheck: pr-merged o/gone#1')"
entry "$OWN" 6 "decision (nobody)" '**Ask:** Anyone?'
publish "$OWN"; publish "$OTH"
entry "$OWN" 7 "decision (alex)" '**Ask:** Uncommitted?'   # in the work tree only: not swept

out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1); rc=$?
has() { grep -qF -- "$1" <<< "$out"; }
[ "$rc" = 0 ] && ok "1a the plan is made, exit 0" || bad "1a rc=$rc: $out"
has "gate sweep of o/own (origin/main; 2 board(s) read) — a plan: nothing written" && ok "1b reads origin/main and every roster board" || bad "1b: $out"
has "file on github.com/o/own: [decide] Ship the thing? — Context: TD-001 decision (alex)" \
  && ok "2a an uncovered decision whose person is on this board: asked here" || bad "2a: $out"
has "file on github.com/o/oth: [decide] Rename it? — Context: o/own#TD-002 decision (sam)" \
  && ok "2b a person on another roster board only: asked there, the id naming this repo" || bad "2b: $out"
grep -q "file on github.com/o/own: \[act\] .*has no board.* — Context: TD-006 decision (nobody)" <<< "$out" \
  && ok "2c a person on no board: an act item here" || bad "2c: $out"
has "lift TD-003 until $PAST — date reached" && ok "3a an until reached: a lift" || bad "3a: $out"
has "check TD-004 event (landed): passed — o/oth#3" && has "lift TD-004 event (landed) — o/oth#3" \
  && ok "3b a passed event check: its outcome, and a lift with its evidence" || bad "3b: $out"
has "check TD-005 event (broken): error — o/gone: not on this machine's roster" \
  && grep -q "file on github.com/o/own: \[act\] Event check broken on TD-005.* — Context: TD-005 event (broken)" <<< "$out" \
  && ok "3c an event check that errors: an act item on this board" || bad "3c: $out"
! has "TD-007" && ok "4a an entry only in the work tree is not swept (origin/main is)" || bad "4a: $out"
[ -z "$(git -C "$OWN" status --porcelain -- docs/user_attention.md)" ] && [ "$(git -C "$OTH" status --porcelain)" = "" ] \
  && ok "4b writes nothing: both boards as they were" || bad "4b: $(git -C "$OWN" status --porcelain; git -C "$OTH" status --porcelain)"

# 5. an item already on the board covers its gate; a second worktree of this repo is read once
L1=$(cd "$OWN" && python3 - "$S" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import ledgerboard as LB, datetime as d
t = d.date.today().isoformat(); it = LB._sweep_item("uncovered", "TD-001", "TD-001", "decision (alex)", ask="Ship the thing?", title="entry 1")
print(LB.item_line(it.pop("text"), t, t, "s", None, **it))
PY
)
board alex "$L1" > "$OWN/docs/user_attention.md"; rm "$OWN/docs/ledger/TD-007.md"; publish "$OWN"
git -C "$OWN" worktree add -q "$TMP/own-wt" HEAD 2>/dev/null; echo "$TMP/own-wt" >> "$AGENT_CADENCE_REG_DIR/repos.txt"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1)
! has "Ship the thing?" && ok "5a a decision with an open item on its board: nothing filed" || bad "5a: $out"
has "2 board(s) read" && ok "5b another worktree of this repo is not read as a second board" || bad "5b: $out"

# 7. a board's archive is read: an item there answered "Not yet" within the window is not asked again
L2=$(cd "$OWN" && python3 - "$S" <<'PY2'
import sys; sys.path.insert(0, sys.argv[1]); import ledgerboard as LB, datetime as d
t = d.date.today(); it = LB._sweep_item("uncovered", "TD-002", "o/own#TD-002", "decision (sam)", ask="Rename it?", title="entry 2")
line = LB.item_line(it.pop("text"), t.isoformat(), t.isoformat(), "s", None, **it).split("\n")[0]
print(LB.edit_line(line, "decide", answer="Not yet", by="sam", today=t, close=True))
PY2
)
grep -q 'Closed: .* kept waiting' <<< "$L2" || bad "7 fixture: $L2"
printf '# Archive\n\n%s\n' "$L2" > "$OTH/docs/user_attention_archive.md"; publish "$OTH"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1)
! has "Rename it?" && ok "7a an item closed in the other board's archive, answered Not yet: not re-filed" || bad "7a: $out"

# 8. a board that is there and cannot be read is named, never read as absent; a clone with no origin/main reads its work tree
blob=$(git -C "$OTH" rev-parse origin/main:docs/user_attention.md)
mv "$OTH/.git/objects/${blob:0:2}/${blob:2}" "$TMP/blob.bak"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "⚠ board not read: oth (origin/main): docs/user_attention.md is there and could not be read" <<< "$out" \
  && ok "8a an unreadable board: left out and named" || bad "8a rc=$rc: $out"
mv "$TMP/blob.bak" "$OTH/.git/objects/${blob:0:2}/${blob:2}"
NEW="$TMP/new"; mkrepo "$NEW" https://github.com/o/new.git; board sam > "$NEW/docs/user_attention.md"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1)
has "board github.com/o/new (working tree)" && has "board github.com/o/oth (origin/main)" \
  && ok "8b each board says where it was read: a clone with no origin/main, its work tree" || bad "8b: $out"
blob=$(git -C "$OWN" rev-parse origin/main:docs/ledger/TD-001.md)
mv "$OWN/.git/objects/${blob:0:2}/${blob:2}" "$TMP/blob.bak"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1); rc=$?
[ "$rc" = 2 ] && has "no plan — own: docs/ledger/TD-001.md is there and could not be read" && ok "8c an unreadable entry of this ledger: no plan, exit 2" || bad "8c rc=$rc: $out"
mv "$TMP/blob.bak" "$OWN/.git/objects/${blob:0:2}/${blob:2}"

# 6. --json, and no own board
js=$(cd "$OWN" && python3 "$S/gate_sweep.py" --json 2>/dev/null)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["repo"]=="o/own" and d["source"]=="origin/main"; assert {"id":"TD-003","gate":"until '"$PAST"'","kind":"until","evidence":"date reached"} in d["lifts"]; assert d["unread"] == [] and {"board":"github.com/o/oth","source":"origin/main"} in d["boards"]; assert "github.com/o/own" in d["to_file"]; assert any(c["id"]=="TD-004" and c["outcome"]=="passed" for c in d["checks"])' "$js" \
  && ok "6a --json: repo, source, boards with their sources, unread, checks, to_file and lifts" || bad "6a: ${js:0:400}"
git -C "$OWN" rm -q docs/user_attention.md; publish "$OWN"
out=$(cd "$OWN" && python3 "$S/gate_sweep.py" 2>&1); rc=$?
[ "$rc" = 2 ] && has "no plan — no docs/user_attention.md (origin/main)" && ok "6b no board of its own: no plan, exit 2" || bad "6b rc=$rc: $out"

# 9. host-log (TD-230): the repo's log-sources.toml is read from origin/main, the tree the ledger came from,
# never the checkout's edit; a gate with no outcome is left out of sweep()'s results
board alex > "$OWN/docs/user_attention.md"
LOGS="$TMP/hostlogs"; mkdir -p "$LOGS"
AT=$(python3 -c 'from datetime import date, timedelta; print((date.today() - timedelta(days=1)).isoformat() + "T01:00:00Z")')
printf '%s boom\n' "$AT" > "$LOGS/good.log"; printf '%s quiet\n' "$AT" > "$LOGS/bad.log"   # after PAST + 1
src() { printf '[sources.app]\nshape = "file"\npath = "%s/%s"\nrecords = "lines"\nat = ["%%Y-%%m-%%dT%%H:%%M:%%SZ"]\n' "$LOGS" "$1"; }
entry "$OWN" 8 "event (red)" "$(printf '**Event (red):** it fails.\ncheck: host-log app "boom"\n\n**Log:**\n- %s: gate added: event (red)' "$PAST")"
src good.log > "$OWN/docs/ledger/log-sources.toml"; publish "$OWN"
src bad.log > "$OWN/docs/ledger/log-sources.toml"   # the checkout's edit: never read
printf '[repos."*"]\n[[allow]]\nroot = "%s"\nvisibility = "private"\n' "$LOGS" > "$AGENT_CADENCE_REG_DIR/host-log.toml"
js=$(cd "$OWN" && python3 "$S/gate_sweep.py" --json 2>&1)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); c=[c for c in d["checks"] if c["id"]=="TD-008"][0]; assert c["outcome"]=="passed", c; assert any(l["id"]=="TD-008" for l in d["lifts"]), d["lifts"]' "$js" \
  && ok "9a a host-log gate answered from origin/main's log-sources.toml, and lifted" || bad "9a: ${js:0:600}"
rm "$AGENT_CADENCE_REG_DIR/host-log.toml"
js=$(cd "$OWN" && python3 "$S/gate_sweep.py" --json 2>&1)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); c=[c for c in d["checks"] if c["id"]=="TD-008"][0]; assert c["outcome"] is None, c; assert not any(l["id"]=="TD-008" for l in d["lifts"]); assert not any("TD-008" in str(f) for f in d["to_file"].values()), d["to_file"]' "$js" \
  && ok "9b no host file: no outcome — no lift, and nothing filed about it" || bad "9b: ${js:0:600}"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
