#!/usr/bin/env bash
# TD-219 (slice 1): event_checks.py, the event runner. Each open entry's `event (<name>)` gate has its
# check run against the forge, with ledgerboard's four outcomes (target design §4.2) and the host's rules
# (§4.4): a check reaches only a roster repo at least as visible as the ledger's own. Its passed evidence
# is what lift_gate() accepts, and its results are what sweep() takes.
#
# Offline: origins are only named, never fetched; `gh` is a PATH shim answering `gh api <path>` from
# fixture files ($FIX/<path with / ? = turned to _>, or <that>.404 / .422 for the forge's "no such").
# HOME, XDG_CONFIG_HOME, AGENT_CADENCE_REG_DIR and git config are temp.
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
for code in 404 422 500; do
  [ -e "$FIX/$key.$code" ] && { echo "gh: Not Found (HTTP $code)" >&2; exit 1; }
done
[ -e "$FIX/$key" ] && { cat "$FIX/$key"; exit 0; }
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
cat > "$BIN/glab" <<'SHIM'
#!/usr/bin/env bash
# GitLab (TD-228): the one project and MR 4e reads, in the shapes gitlab-org/gitlab-test gave
echo "$*" >> "$GH_LOG"
case "$*" in
  "api --hostname gitlab.com projects/g%2Flab") echo '{"visibility":"public","default_branch":"main"}' ;;
  "api --hostname gitlab.com projects/g%2Flab/merge_requests/1") echo '{"iid":1,"state":"merged"}' ;;
  *) echo "glab-shim: unhandled: $*" >&2; exit 64 ;;
esac
SHIM
chmod +x "$BIN/glab"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" FIX
fx() { printf '%s' "$2" > "$FIX/$(printf %s "$1" | tr '/?=' '___')"; }   # fx <api path> <answer>
fx404() { : > "$FIX/$(printf %s "$1" | tr '/?=' '___').${2:-404}"; }

mkrepo() {   # mkrepo <dir> <origin url>: a clone on the roster
  git init -q -b main "$1"; git -C "$1" commit -q --allow-empty -m base
  git -C "$1" remote add origin "$2"; echo "$1" >> "$AGENT_CADENCE_REG_DIR/repos.txt"
}
OWN="$TMP/own"; mkrepo "$OWN" https://github.com/o/own.git
mkrepo "$TMP/tgt" https://github.com/o/tgt.git
mkrepo "$TMP/priv" https://github.com/o/priv.git
mkrepo "$TMP/lab" https://gitlab.com/g/lab.git
git init -q -b main "$TMP/off"; git -C "$TMP/off" remote add origin https://github.com/o/off.git   # not on the roster
fx repos/o/own '{"visibility":"public","default_branch":"main"}'
fx repos/o/tgt '{"visibility":"public","default_branch":"trunk"}'
fx repos/o/priv '{"visibility":"private","default_branch":"main"}'

SHA_T=1111111111111111111111111111111111111111
SHA_R=2222222222222222222222222222222222222222
fx repos/o/tgt/pulls/5 '{"state":"closed","merged":true,"merged_at":"2026-01-01T00:00:00Z"}'
fx repos/o/tgt/pulls/6 '{"state":"closed","merged":false,"merged_at":null}'
fx repos/o/tgt/pulls/7 '{"state":"open","merged":false,"merged_at":null}'
fx404 repos/o/tgt/pulls/8
fx repos/o/tgt/commits/trunk "$SHA_T"
fx "repos/o/tgt/contents/docs/v.txt?ref=$SHA_T" 'version: v2.4 shipped'
fx404 "repos/o/tgt/contents/docs/none.txt?ref=$SHA_T"
fx repos/o/tgt/commits/release/1 "$SHA_R"
fx404 repos/o/tgt/commits/gone 422
fx "repos/o/tgt/compare/abc1234...$SHA_R" ahead
fx "repos/o/tgt/compare/def5678...$SHA_R" diverged
fx404 "repos/o/tgt/compare/fff9999...$SHA_R"
fx "repos/o/tgt/compare/aaa1111...$SHA_R" behind
fx404 "repos/o/tgt/compare/bbb2222...$SHA_R" 422
fx404 repos/o/tgt/pulls/9 500
fx "repos/o/tgt/contents/docs?ref=$SHA_T" '[{"type":"file","path":"docs/v.txt","sha":"x","name":"v.txt"}]'
printf 'caf\xe9 v2.4' > "$FIX/$(printf %s "repos/o/tgt/contents/latin.txt?ref=$SHA_T" | tr '/?=' '___')"

entry() {   # entry <n> <status> <blocked by> <event sections…>
  local n=$1 st=$2 bl=$3; shift 3
  { printf '## TD-%03d: entry %s\n\n**Priority:** Medium\n**Added:** 2026-01-01\n**Status:** %s\n' "$n" "$n" "$st"
    [ -n "$bl" ] && printf '**Blocked by:** %s\n' "$bl"
    printf '**Location:** x\n\n**Why:** y\n'
    for s in "$@"; do printf '\n%s\n' "$s"; done
  } > "$OWN/docs/ledger/TD-$(printf %03d "$n").md"
}
mkdir -p "$OWN/docs/ledger/archive"
printf '# Ledger\n' > "$OWN/docs/ledger/README.md"
ev() { printf '**Event (%s):** it happens.\ncheck: %s' "$1" "$2"; }
entry 1 Open "event (merged)"      "$(ev merged 'pr-merged o/tgt#5')"
entry 2 Open "event (shut)"        "$(ev shut 'pr-merged o/tgt#6')"
entry 3 Open "event (waiting)"     "$(ev waiting 'pr-merged tgt#7')"
entry 4 Open "event (lost)"        "$(ev lost 'pr-merged o/tgt#8')"
entry 5 Open "event (has), event (lacks), event (nofile)" \
  "$(ev has 'file-contains o/tgt docs/v.txt "v2.4"')" "$(ev lacks 'file-contains o/tgt docs/v.txt "v9"')" \
  "$(ev nofile 'file-contains o/tgt docs/none.txt "x"')"
entry 6 Open "event (in), event (out), event (unknown), event (noref)" \
  "$(ev in 'ref-includes o/tgt@release/1 abc1234')" "$(ev out 'ref-includes o/tgt@release/1 def5678')" \
  "$(ev unknown 'ref-includes o/tgt@release/1 fff9999')" "$(ev noref 'ref-includes o/tgt@gone abc1234')"
entry 7 Open "event (secret)"      "$(ev secret 'pr-merged o/priv#1')"
entry 8 Open "event (stray)"       "$(ev stray 'pr-merged o/off#1')"
entry 9 Open "event (lab)"         "$(ev lab 'pr-merged g/lab#1')"
entry 10 Open "event (nosection)"
entry 13 Open "event (behind), event (ambiguous), event (down), event (dir), event (latin)" \
  "$(ev behind 'ref-includes o/tgt@release/1 aaa1111')" "$(ev ambiguous 'ref-includes o/tgt@release/1 bbb2222')" \
  "$(ev down 'pr-merged o/tgt#9')" "$(ev dir 'file-contains o/tgt docs "v.txt"')" \
  "$(ev latin 'file-contains o/tgt latin.txt "v2.4"')"
entry 11 Resolved "event (old)"    "$(ev old 'pr-merged o/tgt#7')"
entry 12 Open "TD-001"

: > "$GH_LOG"
out=$(cd "$OWN" && python3 "$S/event_checks.py" 2>&1); rc=$?
line() { grep -F "$1" <<< "$out"; }
want() {   # want <label> <line start> <outcome — rest>
  if [ "$(line "$2")" = "$2 $3" ]; then ok "$1"; else bad "$1: got '$(line "$2")'"; fi
}
want "1a pr-merged, merged: passed, the PR as evidence" "TD-001 event (merged):" "passed — o/tgt#5"
want "1b pr-merged, closed unmerged: impossible" "TD-002 event (shut):" "impossible — o/tgt#6 closed unmerged"
want "1c pr-merged, open, a bare roster name: not yet" "TD-003 event (waiting):" "not yet — tgt#7 is open"
grep -q '^TD-004 event (lost): error — o/tgt#8: not found' <<< "$out" && ok "1d pr-merged, not found: an error, never not yet" || bad "1d: $(line TD-004)"
want "2a file-contains at the default branch: passed, repo@sha" "TD-005 event (has):" "passed — o/tgt@$SHA_T"
grep -q '^TD-005 event (lacks): not yet — docs/v.txt at trunk .* does not hold the text' <<< "$out" && ok "2b file-contains, text absent: not yet" || bad "2b: $(line '(lacks)')"
grep -q '^TD-005 event (nofile): not yet — docs/none.txt at trunk .* has no such file' <<< "$out" && ok "2c file-contains, no file: not yet" || bad "2c: $(line '(nofile)')"
want "3a ref-includes, ahead: passed, repo@the ref's sha" "TD-006 event (in):" "passed — o/tgt@$SHA_R"
grep -q '^TD-006 event (out): not yet — def5678: o/tgt release/1 .* does not include it' <<< "$out" && ok "3b ref-includes, diverged: not yet" || bad "3b: $(line '(out)')"
grep -q '^TD-006 event (unknown): not yet — fff9999: o/tgt does not know the commit yet' <<< "$out" && ok "3c ref-includes, an unknown commit: not yet" || bad "3c: $(line '(unknown)')"
want "3d ref-includes, a ref not there: not yet" "TD-006 event (noref):" "not yet — o/tgt has no gone yet"
grep -q '^TD-007 event (secret): error — o/priv is private, less visible' <<< "$out" && ok "4a a public ledger's check of a private repo: refused, an error" || bad "4a: $(line TD-007)"
! grep -q 'repos/o/priv/pulls' "$GH_LOG" && ok "4b the refused check asks the private repo nothing past its visibility" || bad "4b: $(grep priv "$GH_LOG")"
grep -q '^TD-008 event (stray): error — o/off: not on this machine.s roster' <<< "$out" && ok "4c a repo off the roster: an error" || bad "4c: $(line TD-008)"
! grep -q 'o/off' "$GH_LOG" && ok "4d the forge is never asked about a repo off the roster" || bad "4d: $(grep o/off "$GH_LOG")"
want "4e a GitLab repo's check: read through glab (TD-228), passed" "TD-009 event (lab):" "passed — g/lab#1"
grep -q '^TD-013 event (behind): not yet — aaa1111: o/tgt release/1 .* does not include it' <<< "$out" && ok "3e ref-includes, behind: not yet" || bad "3e: $(line '(behind)')"
grep -q '^TD-013 event (ambiguous): error — ' <<< "$out" && ok "3f a 422 from compare (an ambiguous commit): an error, not not yet" || bad "3f: $(line '(ambiguous)')"
grep -q '^TD-013 event (down): error — gh: Not Found (HTTP 500)' <<< "$out" && ok "1e a forge failure (HTTP 500): an error, never not yet" || bad "1e: $(line '(down)')"
grep -q '^TD-013 event (dir): error — o/tgt: docs at .* is a directory, not a file' <<< "$out" && ok "2d file-contains on a directory: an error, never its listing matched" || bad "2d: $(line '(dir)')"
grep -q '^TD-013 event (latin): error — gh gave output that is not UTF-8 text' <<< "$out" && ok "2e a file that is not UTF-8: an error for that gate alone" || bad "2e: $(line '(latin)')"
grep -q '^TD-010 event (nosection): error — no \*\*Event (nosection):\*\* section' <<< "$out" && ok "5a a gate with no section: an error" || bad "5a: $(line TD-010)"
! grep -q 'TD-011\|TD-012' <<< "$out" && ok "5b an archived entry's gate, and an id-only block, run nothing" || bad "5b: $out"
[ "$rc" = 1 ] && ok "5c exit 1 when any check is an error" || bad "5c rc=$rc"
[ "$(grep -c '^api repos/o/tgt$' "$GH_LOG")" = 1 ] && ok "5d each repo's facts are read once a run" || bad "5d: $(grep -c '^api repos/o/tgt$' "$GH_LOG")"

# 6. the passed evidence is what lift_gate() takes, and results() is sweep()'s input
py=$(cd "$OWN" && python3 - "$S" <<'PY'
import sys, pathlib
sys.path.insert(0, sys.argv[1])
import event_checks as E, ledger as L, ledgerboard as LB
from datetime import datetime, timezone
today = datetime.now(timezone.utc).date()
top = pathlib.Path(".").resolve()
text, arch = L.read_pair(str(top / "docs/ledger"), None, L.fs_io())
res = E.results(text, E.Runner(top))
body = LB._entry_texts(text)["TD-001"]
out = LB.lift_gate(body, "event (merged)", "host-x", evidence=res[("TD-001", "merged")][1], today=today)
print("lifted" if "gate lifted: event (merged) — by host-x; pr-merged passed; o/tgt#5" in out else "not lifted: " + out)
board = "# Board\n\nPeople: alex\n\n## Open\n"
sw = LB.sweep([text, arch], [("https://github.com/o/own.git", "own", board, "")], res, today, today, repo="o/own")
print(sorted((x["id"], x["gate"]) for x in sw["lifts"]))
print(res[("TD-002", "shut")], res[("TD-004", "lost")][0])
PY
)
grep -q '^lifted$' <<< "$py" && ok "6a lift_gate() accepts the runner's pr-merged evidence" || bad "6a: $py"
grep -qF "[('TD-001', 'event (merged)'), ('TD-005', 'event (has)'), ('TD-006', 'event (in)'), ('TD-009', 'event (lab)')]" <<< "$py" \
  && ok "6b sweep() lifts exactly the passed gates from results()" || bad "6b: $py"
grep -qF "('impossible', None) error" <<< "$py" && ok "6c results() pairs each outcome with its evidence" || bad "6c: $py"

# 7. --json, a ledger with no event gate, and the own repo unreadable
js=$(cd "$OWN" && python3 "$S/event_checks.py" --json 2>/dev/null)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); r=[c for c in d["checks"] if c["id"]=="TD-001"][0]; sys.exit(0 if r["outcome"]=="passed" and r["evidence"]=="o/tgt#5" and r["check"]["type"]=="pr-merged" else 1)' "$js" \
  && ok "7a --json gives each check's outcome, evidence and parsed check" || bad "7a: ${js:0:300}"
E="$TMP/empty"; mkrepo "$E" https://github.com/o/empty.git; mkdir -p "$E/docs/ledger/archive"; printf '# L\n' > "$E/docs/ledger/README.md"
out=$(cd "$E" && python3 "$S/event_checks.py" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q '^no open event gates in ' <<< "$out" && ok "7b no event gate: says so, exit 0" || bad "7b rc=$rc: $out"
rm "$FIX/repos_o_own"; fx404 repos/o/own
out=$(cd "$OWN" && python3 "$S/event_checks.py" 2>&1)
grep -q "^TD-001 event (merged): error — this ledger's own repo: o/own: not found" <<< "$out" && ok "7c the ledger's own visibility unreadable: every check an error" || bad "7c: $(line TD-001)"
rm "$FIX/repos_o_own.404"; fx repos/o/own '{"visibility":"private","default_branch":"main"}'
fx repos/o/priv/pulls/1 '{"state":"open","merged":false}'
out=$(cd "$OWN" && python3 "$S/event_checks.py" 2>&1)
want "7d a private ledger's check reaches a private repo" "TD-007 event (secret):" "not yet — o/priv#1 is open"

# --- 8: host-log (TD-230): the runner asks this host's reader, hostlog.py; o/own is private from 7d on
SINCE=$(python3 -c 'from datetime import date, timedelta; print(date.today() - timedelta(days=10))')
AT=$(python3 -c 'from datetime import date, timedelta; print((date.today() - timedelta(days=9)).isoformat() + "T01:00:00Z")')
LOGS="$TMP/hostlogs"; mkdir -p "$LOGS"; printf '%s boom\n' "$AT" > "$LOGS/app.log"
hl() { printf '**Event (%s):** it happens.\ncheck: %s' "$1" "$2"; }
entry 20 Open "event (red)" "$(hl red 'host-log app "boom"')"
printf '\n**Log:**\n- %s: gate added: event (red)\n' "$SINCE" >> "$OWN/docs/ledger/TD-020.md"
entry 21 Open "event (undated)" "$(hl undated 'host-log app "boom"')"
entry 22 Open "event (quiet)" "$(hl quiet 'host-log app times 2 "boom"')"
printf '\n**Log:**\n- %s: gate added: event (quiet)\n' "$SINCE" >> "$OWN/docs/ledger/TD-022.md"
printf '[sources.app]\nshape = "file"\npath = "%s/app.log"\nrecords = "lines"\nat = ["%%Y-%%m-%%dT%%H:%%M:%%SZ"]\n' "$LOGS" \
  > "$OWN/docs/ledger/log-sources.toml"
out=$(cd "$OWN" && python3 "$S/event_checks.py" 2>&1)
grep -q '^TD-020 event (red): no outcome — no host file' <<< "$out" && ok "8a no host file: no outcome, the reader not run" || bad "8a: $(line TD-020)"
printf '[repos."*"]\n[[allow]]\nroot = "%s"\nvisibility = "private"\n' "$LOGS" > "$AGENT_CADENCE_REG_DIR/host-log.toml"
out=$(cd "$OWN" && python3 "$S/event_checks.py" 2>&1)
want "8b a host-log gate: passed, the reader's evidence" "TD-020 event (red):" "passed — app@$(python3 -c "print('$AT'.replace('-','').replace(':',''))")"
grep -q '^TD-021 event (undated): error — since unknown' <<< "$out" && ok "8c no gate added line: an error, since unknown" || bad "8c: $(line TD-021)"
grep -q '^TD-022 event (quiet): not yet — 1 counted' <<< "$out" && ok "8d fewer than N: not yet" || bad "8d: $(line TD-022)"
printf '[repos."other/x"]\n[[allow]]\nroot = "%s"\nvisibility = "private"\n' "$LOGS" > "$AGENT_CADENCE_REG_DIR/host-log.toml"
res=$(cd "$OWN" && python3 - "$S" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path
import event_checks as E, ledger as L
text, _ = L.read_pair("docs/ledger", "docs/ledger/archive", L.fs_io())
r = E.results(text, E.Runner(Path(".")))
print(sorted(k for k in r if k[0] in ("TD-020", "TD-022")))
PY
)
[ "$res" = "[]" ] && ok "8e no table for the repo: no outcome, and results() leaves the gate out (sweep() sees nothing)" || bad "8e: $res"
res=$(cd "$OWN" && python3 - "$S" "$AGENT_CADENCE_REG_DIR/host-log.toml" <<'PY'
import sys, subprocess; sys.path.insert(0, sys.argv[1]); from pathlib import Path
import event_checks as E, ledgerboard as LB
g = {"id": "TD-1", "name": "x", "problem": None, "since": "2026-01-01", "check": LB.parse_check('host-log app "boom"')}
r = E.Runner(Path("."), host_file=Path(sys.argv[2]))
r._own_vis = (0, "")
outs = []
for fake in (lambda *a, **k: subprocess.CompletedProcess(a, 0, "not json", ""),
             lambda *a, **k: subprocess.CompletedProcess(a, 2, "", "usage"),
             lambda *a, **k: subprocess.CompletedProcess(a, 0, '{"outcome": "maybe"}', "")):
    E.subprocess.run = fake
    outs.append(r.run(g)["outcome"])
def slow(*a, **k):
    raise subprocess.TimeoutExpired(a, 120)
E.subprocess.run = slow
outs.append(r.run(g)["outcome"])
print(outs)
PY
)
[ "$res" = "['error', 'error', 'error', 'error']" ] && ok "8f non-JSON output, a non-zero exit, an unknown outcome or the 120 s timeout: error" || bad "8f: $res"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
