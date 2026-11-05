#!/usr/bin/env bash
# TD-230: the cadence check's `sources` and `person` rows (check_cadence.py row_sources, row_person).
# sources: on a PR touching the ledger or docs/ledger/log-sources.toml, hostlog.py's validate over the head
# commit — the repo file's checks, and an open entry's host-log gate whose source nothing declares.
# person: a PR changing log-sources.toml (PERSON_PATHS) fails while open — the person merges it, never a session.
# Offline: temp git repos with a bare origin; HOME/XDG_CONFIG_HOME are temp; no dates are judged (TD-24).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
python3 -c 'import tomllib' 2>/dev/null || { echo "SKIP: no tomllib (Python < 3.11): the sources row reads unknown"; echo "0 passed, 0 failed"; exit 0; }

R="$TMP/widgets"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"
mkdir -p "$R/docs/ledger/archive"; printf '# Ledger\n' > "$R/docs/ledger/README.md"; echo x > "$R/other.txt"
entry() {   # entry <n> <blocked by> [more body]
  { printf '## TD-%03d: entry %s\n\n**Priority:** Medium\n**Added:** 2026-01-01\n**Status:** Open\n' "$1" "$1"
    printf '**Blocked by:** %s\n**Location:** x\n\n**Why:** y\n' "$2"
    [ -n "${3:-}" ] && printf '\n%s\n' "$3"
  } > "$R/docs/ledger/TD-$(printf %03d "$1").md"
}
entry 1 ""
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null

row() {  # $1 = the row (sources|person), $2 = state (open|merged): the row on HEAD
  python3 - "$R" "$1" "$2" "$S" <<'EOF'
import sys
root, which, state, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
base = C.git(["rev-parse", "origin/main"], cwd=root).strip()
rng = f"{sha}^..{sha}" if state == "merged" else f"{base}..{sha}"
files = sorted(set(C.git(["diff", "--name-only", rng], cwd=root).split()))
pr = {"state": state, "head_sha": sha, "merge_sha": sha, "files": files}
r = (C.row_sources if which == "sources" else C.row_person)(pr, root)
print(r["status"], r["detail"])
EOF
}
topic() { git -C "$R" switch -q -C topic origin/main; }
commit() { git -C "$R" add -A; git -C "$R" commit -qm "${1:-change}"; }
GATE="$(printf '**Event (paged):** it pages.\ncheck: host-log pager "page"')"
src() { printf '[sources.%s]\nshape = "file"\npath = "~/logs/%s.log"\nrecords = "lines"\nat = ["%%Y-%%m-%%dT%%H:%%M:%%SZ"]\n%s' "$1" "$1" "${2:-}"; }

topic; echo y >> "$R/other.txt"; commit
st=$(row sources open); [ "${st%% *}" = na ] && ok "1a a PR touching neither the ledger nor log-sources.toml: sources na" || bad "1a: $st"
st=$(row person open); [ "${st%% *}" = na ] && ok "1b ... and person na" || bad "1b: $st"

topic; entry 2 "event (paged)" "$GATE"; commit
st=$(row sources open); [ "${st%% *}" = fail ] && grep -q "TD-002: event (paged) names source pager, which no default or profile" <<< "$st" \
  && ok "2a a host-log gate whose source nothing declares (no log-sources.toml): fails, named" || bad "2a: $st"
st=$(row person open); [ "${st%% *}" = na ] && ok "2b a ledger-only PR is not the person's" || bad "2b: $st"
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic >/dev/null 2>&1; git -C "$R" commit -qm "ledger (#2)"
st=$(row sources merged); [ "${st%% *}" = pass ] && grep -q "⚠ TD-002: event (paged) names source pager" <<< "$st" \
  && ok "2c the same merged: a ⚠, never a fail (a sweep never fails history)" || bad "2c: $st"
git -C "$R" reset -q --hard origin/main

topic; entry 2 "event (paged)" "$GATE"; src pager > "$R/docs/ledger/log-sources.toml"; commit
st=$(row sources open); [ "${st%% *}" = pass ] && ok "3a its source declared in the head's log-sources.toml: sources pass" || bad "3a: $st"
st=$(row person open); [ "${st%% *}" = fail ] && grep -q "docs/ledger/log-sources.toml is the person's" <<< "$st" \
  && ok "3b a PR changing log-sources.toml: the person row fails (the person merges it)" || bad "3b: $st"
rm "$R/docs/ledger/log-sources.toml"
st=$(row sources open); [ "${st%% *}" = pass ] && ok "3c it reads the head commit, not the working tree (the file deleted on disk)" || bad "3c: $st"
git -C "$R" checkout -q -- docs
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic >/dev/null 2>&1; git -C "$R" commit -qm "sources (#3)"
st=$(row person merged); [ "${st%% *}" = pass ] && grep -q "⚠ docs/ledger/log-sources.toml is the person's" <<< "$st" \
  && ok "3d merged, the person row is a ⚠" || bad "3d: $st"
git -C "$R" push -q origin main 2>/dev/null

topic; git -C "$R" mv docs/ledger/log-sources.toml docs/ledger/sources-old.toml; commit "rename"
st=$(row person open); [ "${st%% *}" = fail ] && grep -q "log-sources.toml is the person's" <<< "$st" \
  && ok "3e a rename (the forge lists only the new name): the person row still fails" || bad "3e: $st"

topic; printf '[repos."*"]\n' >> "$R/docs/ledger/log-sources.toml"; commit
st=$(row sources open); [ "${st%% *}" = fail ] && grep -q "host-only key" <<< "$st" \
  && ok "4a a host-only key in log-sources.toml: refused, the row fails" || bad "4a: $st"

topic; src quiet 'enabled = false
' >> "$R/docs/ledger/log-sources.toml"; commit
st=$(row sources open); [ "${st%% *}" = pass ] && grep -q "⚠ source quiet is enabled = false in the defaults and enabled by no profile" <<< "$st" \
  && ok "4b a warning (a source disabled everywhere): pass with a ⚠" || bad "4b: $st"

topic; entry 3 "event (other)" "$(printf '**Event (other):** x.\ncheck: host-log nowhere "x"')"; mkdir -p "$R/docs/ledger/archive"
git -C "$R" add -A; git -C "$R" commit -qm one; git -C "$R" mv docs/ledger/TD-003.md docs/ledger/archive/TD-003.md
sed -i 's/^\*\*Status:\*\* Open/**Status:** Resolved 2026-01-02/' "$R/docs/ledger/archive/TD-003.md"; commit two
st=$(row sources open); [ "${st%% *}" = pass ] && ok "5a an archived entry's host-log gate is not judged" || bad "5a: $st"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
