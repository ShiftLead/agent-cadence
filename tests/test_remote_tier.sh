#!/usr/bin/env bash
# Remote board tier tests (TD-6, plan 2026-08-13). Fully offline: `gh` is a
# PATH-shimmed fake driven by fixture files; XDG_CONFIG_HOME + HOME overrides
# keep the real registry, filter file, and any real gh auth out of reach.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/files/scripts/nudge_user_attention.py"
TMP=$(mktemp -d)
export HOME="$TMP/home"; mkdir -p "$HOME"
export XDG_CONFIG_HOME="$TMP/config"
REG_DIR="$XDG_CONFIG_HOME/agent-cadence"; REG="$REG_DIR/repos.txt"
FILTER="$REG_DIR/remote_repos.txt"
mkdir -p "$REG_DIR"
PASS=0; FAIL=0
LATE=$(date -d '3 days ago' +%F)
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Local fixture repo with a github origin, registered in the roster.
mk() { git init -q -b main "$1"; mkdir -p "$1/docs"; git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init; }
R1="$TMP/localrepo"; mk "$R1"
git -C "$R1" remote add origin git@github.com:tester/localrepo.git
printf '# board\n\n- [ ] 2026-08-13 (n/a) — local item.\n' > "$R1/docs/user_attention.md"
echo "$R1" > "$REG"

# --- fake gh -----------------------------------------------------------------
# Behavior is driven by files under $FAKE: login, orgs, list_<owner>.json,
# board_<owner>_<repo>.md, http403_/http500_<owner>_<repo> markers, fail_user /
# fail_orgs markers, sleep_probe (seconds). Every invocation is appended to
# $FAKE/calls.log so tests can assert call absence.
FAKE="$TMP/fake"; mkdir -p "$FAKE"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls.log"
if [ "$1 $2" = "api user" ] && [ "${3:-}" = "--jq" ] && [ "${4:-}" = ".login" ]; then
  [ -f "$FAKE/fail_user" ] && { echo "gh: HTTP 401: Bad credentials" >&2; exit 1; }
  cat "$FAKE/login"; exit 0
fi
if [ "$1 $2" = "api user/orgs" ]; then
  [ -f "$FAKE/fail_orgs" ] && { echo "gh: HTTP 500: org boom" >&2; exit 1; }
  cat "$FAKE/orgs" 2>/dev/null; exit 0
fi
if [ "$1 $2" = "repo list" ]; then
  f="$FAKE/list_$3.json"
  [ -f "$f" ] && { cat "$f"; exit 0; }
  echo "gh: HTTP 404: unknown owner (HTTP 404)" >&2; exit 1
fi
if [ "$1" = "api" ] && [[ "$2" == repos/*/contents/docs/user_attention.md ]]; then
  [ -f "$FAKE/sleep_probe" ] && sleep "$(cat "$FAKE/sleep_probe")"
  slug="${2#repos/}"; slug="${slug%/contents/docs/user_attention.md}"; key="${slug//\//_}"
  [ -f "$FAKE/http403_${key}" ] && { echo "gh: Must have push access (HTTP 403)" >&2; exit 1; }
  [ -f "$FAKE/http500_${key}" ] && { echo "gh: server exploded (HTTP 500)" >&2; exit 1; }
  [ -f "$FAKE/board_${key}.md" ] && { cat "$FAKE/board_${key}.md"; exit 0; }
  echo "gh: Not Found (HTTP 404)" >&2; exit 1
fi
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export FAKE
export PATH="$BIN:$PATH"

reset_fake() {
  rm -f "$FAKE"/*
  echo tester > "$FAKE/login"
  : > "$FAKE/orgs"
  : > "$FAKE/calls.log"
  rm -f "$FILTER"
}
run() { python3 "$NEW" --report --remote 2>/dev/null; }

# --- 1) remote-only repo with a due item appears, due-ordered, in the tier
reset_fake
printf '[{"nameWithOwner":"tester/remoteonly","isArchived":false}]\n' > "$FAKE/list_tester.json"
printf '# board\n\n- [ ] 2026-08-10 (n/a) — remote undated.\n- [ ] 2026-08-10 (n/a) — remote late. Due: %s.\n' "$LATE" > "$FAKE/board_tester_remoteonly.md"
out=$(run)
if echo "$out" | grep -q "== tester/remoteonly (remote-only, pushed state)"; then
  ok "remote-only board renders"; else bad "remote-only board missing"; fi
l_late=$(echo "$out" | grep -n "remote late" | cut -d: -f1)
l_und=$(echo "$out" | grep -n "remote undated" | cut -d: -f1)
if [ -n "$l_late" ] && [ -n "$l_und" ] && [ "$l_late" -lt "$l_und" ]; then
  ok "remote items due-ordered (overdue before undated)"; else bad "remote ordering off ($l_late vs $l_und)"; fi
if echo "$out" | grep -q "1 remote-only board(s)"; then ok "tier header counts boards"; else bad "tier header: $(echo "$out" | grep 'Remote tier')"; fi

# --- 2) remote repo matching a roster entry's origin is deduped out
reset_fake
printf '[{"nameWithOwner":"tester/localrepo","isArchived":false},{"nameWithOwner":"tester/remoteonly","isArchived":false}]\n' > "$FAKE/list_tester.json"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — x.\n' > "$FAKE/board_tester_remoteonly.md"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — should not appear.\n' > "$FAKE/board_tester_localrepo.md"
out=$(run)
if ! echo "$out" | grep -q "== tester/localrepo (remote-only"; then ok "roster-covered repo deduped"; else bad "local repo double-listed"; fi
if grep -q "repos/tester/localrepo/contents" "$FAKE/calls.log"; then bad "deduped repo still probed"; else ok "deduped repo not even probed"; fi

# --- 3) repo without a board (404) dropped silently
reset_fake
printf '[{"nameWithOwner":"tester/noboard","isArchived":false}]\n' > "$FAKE/list_tester.json"
out=$(run)
if ! echo "$out" | grep -q "noboard"; then ok "404 board dropped silently"; else bad "404 repo rendered"; fi
if ! echo "$out" | grep -q "unprobeable"; then ok "404 not counted unprobeable"; else bad "404 counted unprobeable"; fi

# --- 4) archived repo skipped (never probed)
reset_fake
printf '[{"nameWithOwner":"tester/oldstuff","isArchived":true}]\n' > "$FAKE/list_tester.json"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — ghost.\n' > "$FAKE/board_tester_oldstuff.md"
out=$(run)
if ! echo "$out" | grep -q "oldstuff"; then ok "archived repo skipped"; else bad "archived repo rendered"; fi

# --- 5) gh absent -> unavailable-note, local report intact, exit 0
#         PATH stripped to a dir with only python3/coreutils shims — the real gh
#         must be unreachable for subprocess to raise FileNotFoundError.
reset_fake
NOGH="$TMP/nogh"; mkdir -p "$NOGH"
out=$(PATH="$NOGH" "$(command -v python3)" "$NEW" --report --remote 2>/dev/null); rc=$?
if echo "$out" | grep -q "remote tier unavailable (gh not installed)"; then ok "gh-absent note"; else bad "gh-absent: $(echo "$out" | grep '⚠')"; fi
if echo "$out" | grep -q "local item" && [ "$rc" -eq 0 ]; then ok "gh-absent leaves local intact, exit 0"; else bad "local report harmed (rc=$rc)"; fi

# --- 6) unauthenticated (user lookup fails) -> unavailable-note w/ distinct reason
reset_fake
touch "$FAKE/fail_user"
out=$(run)
if echo "$out" | grep -q "remote tier unavailable" && echo "$out" | grep -q "401"; then
  ok "auth failure -> unavailable with reason"; else bad "auth failure note: $(echo "$out" | grep '⚠')"; fi
if echo "$out" | grep -q "local item"; then ok "auth failure leaves local intact"; else bad "local report lost"; fi

# --- 7) hung probe -> budget trips -> incomplete-note
reset_fake
# 3 slow repos: the first two burn the 1.5s budget on 1s+0.5s timeouts, so the
# THIRD is refused outright — that refusal is what sets the exhausted flag.
printf '[{"nameWithOwner":"tester/slow1","isArchived":false},{"nameWithOwner":"tester/slow2","isArchived":false},{"nameWithOwner":"tester/slow3","isArchived":false}]\n' > "$FAKE/list_tester.json"
echo 5 > "$FAKE/sleep_probe"
out=$(ATTENTION_GH_TIMEOUT=1 ATTENTION_GH_BUDGET=1.5 python3 "$NEW" --report --remote 2>/dev/null)
if echo "$out" | grep -q "remote tier incomplete (budget exhausted"; then
  ok "budget exhaustion -> incomplete-note"; else bad "budget: $(echo "$out" | grep '⚠')"; fi

# --- 8) --due-only never runs the remote tier's GitHub discovery. --remote implies --fetch, so
#        its one gh call — this repo's own `pr list` (TD-052) — does happen here; nothing else may.
reset_fake
printf '[{"nameWithOwner":"tester/x","isArchived":false}]\n' > "$FAKE/list_tester.json"
python3 "$NEW" --report --remote --due-only >/dev/null 2>&1
other=$(grep -v '^pr list --state open ' "$FAKE/calls.log" 2>/dev/null)
if [ -z "$other" ] && grep -q '^pr list --state open ' "$FAKE/calls.log"; then ok "--due-only: TD-052's own pr list, and no discovery gh call"
else bad "--due-only gh calls: $(cat "$FAKE/calls.log")"; fi

# --- 9) --remote without --report errors, matching --fetch's contract
if python3 "$NEW" --remote >/dev/null 2>&1; then bad "--remote alone did not error"; else ok "--remote requires --report"; fi

# --- 10) per-repo 403/500 -> unprobeable-note, NOT a silent drop
reset_fake
printf '[{"nameWithOwner":"tester/secret","isArchived":false},{"nameWithOwner":"tester/broken","isArchived":false}]\n' > "$FAKE/list_tester.json"
touch "$FAKE/http403_tester_secret" "$FAKE/http500_tester_broken"
out=$(run)
if echo "$out" | grep -q "2 repo(s) unprobeable (first: tester/broken:"; then
  ok "403/500 surface as unprobeable"; else bad "unprobeable note: $(echo "$out" | grep '⚠')"; fi

# --- 11) --remote --board X dedups against X's origin, no registry read
reset_fake
printf '[{"nameWithOwner":"tester/localrepo","isArchived":false}]\n' > "$FAKE/list_tester.json"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — nope.\n' > "$FAKE/board_tester_localrepo.md"
out=$(python3 "$NEW" --report --remote --board "$R1/docs/user_attention.md" 2>/dev/null)
if ! echo "$out" | grep -q "== tester/localrepo (remote-only"; then
  ok "--board repo's origin dedups remote twin"; else bad "--board dedup failed"; fi

# --- 12) repo list at exactly the limit -> truncation warning
reset_fake
printf '[{"nameWithOwner":"tester/a","isArchived":false},{"nameWithOwner":"tester/b","isArchived":false},{"nameWithOwner":"tester/c","isArchived":false}]\n' > "$FAKE/list_tester.json"
out=$(ATTENTION_GH_LIST_LIMIT=3 python3 "$NEW" --report --remote 2>/dev/null)
if echo "$out" | grep -q "repo list truncated at 3 for tester"; then ok "truncation warns"; else bad "no truncation warning"; fi

# --- 13) filter file with owner/repo probes directly — discovery never runs
reset_fake
printf 'tester/handpicked\n' > "$FILTER"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — picked.\n' > "$FAKE/board_tester_handpicked.md"
out=$(run)
if echo "$out" | grep -q "== tester/handpicked"; then ok "filter owner/repo entry probed"; else bad "filter entry not probed"; fi
if ! grep -q "repo list" "$FAKE/calls.log" && ! grep -q "api user " "$FAKE/calls.log"; then
  ok "filter skips discovery entirely"; else bad "filter still ran discovery: $(cat "$FAKE/calls.log")"; fi

# --- 14) filter file present but empty -> full discovery (D1 as amended)
reset_fake
printf '# just a comment\n\n' > "$FILTER"
printf '[{"nameWithOwner":"tester/viadiscovery","isArchived":false}]\n' > "$FAKE/list_tester.json"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — found.\n' > "$FAKE/board_tester_viadiscovery.md"
out=$(run)
if echo "$out" | grep -q "== tester/viadiscovery"; then ok "empty filter -> full scan"; else bad "empty filter blocked scan"; fi

# --- 15) org listing fails -> partial coverage with note, user repos still scanned
reset_fake
touch "$FAKE/fail_orgs"
printf '[{"nameWithOwner":"tester/mine","isArchived":false}]\n' > "$FAKE/list_tester.json"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — mine.\n' > "$FAKE/board_tester_mine.md"
out=$(run)
if echo "$out" | grep -q "org discovery failed" && echo "$out" | grep -q "== tester/mine"; then
  ok "org failure degrades to partial + note"; else bad "org partial: $(echo "$out" | grep '⚠')"; fi

# --- 16) filter with a bare owner scans that owner only (no user/orgs discovery)
reset_fake
printf 'someorg\n' > "$FILTER"
printf '[{"nameWithOwner":"someorg/theirs","isArchived":false}]\n' > "$FAKE/list_someorg.json"
printf '# b\n\n- [ ] 2026-08-10 (n/a) — theirs.\n' > "$FAKE/board_someorg_theirs.md"
out=$(run)
if echo "$out" | grep -q "== someorg/theirs" && ! grep -q "api user " "$FAKE/calls.log"; then
  ok "owner filter scans that owner only"; else bad "owner filter: $(cat "$FAKE/calls.log")"; fi

rm -rf "$TMP"
echo; echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
