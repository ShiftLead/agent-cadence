#!/usr/bin/env bash
# TD-034 tier 2: the --fetch report names a repo whose GitHub merge settings drift from
# cadence.md §4 — read-only, one line, silent when gh cannot answer or a field is null.
# settings_line() is exercised directly (a full --fetch run would fetch a real GitHub origin);
# `gh` is a PATH shim answering from a file. HOME/XDG/git config are temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" DEV_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$DEV_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ -f "$GH_FAIL" ] && { echo "gh: HTTP 401" >&2; exit 1; }
[ "$1" = api ] && [ "$2" = "repos/tester/thing" ] && { cat "$GH_JSON"; exit 0; }
exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" GH_FAIL="$TMP/gh.fail" GH_JSON="$TMP/repo.json"
R="$TMP/repo"; git init -q "$R"; git -C "$R" remote add origin git@github.com:tester/thing.git
line() { python3 - "$S" "$1" <<'PY'
import sys, pathlib
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print(N.settings_line(pathlib.Path(sys.argv[2]), {"t": 0.0, "hit": False}) or "NONE")
PY
}
put() { printf '{"allow_squash_merge": %s, "allow_merge_commit": %s, "allow_rebase_merge": %s, "delete_branch_on_merge": %s}\n' "$@" > "$GH_JSON"; }

put true false false true
[ "$(line "$R")" = NONE ] && ok "settings as the cadence wants: no line" || bad "clean: $(line "$R")"
# a repo that keeps auto-delete off on purpose, listed in no_auto_delete.txt: not nagged about it
put true false false false
echo "Tester/Thing  # stacks PRs" > "$DEV_CADENCE_REG_DIR/no_auto_delete.txt"
[ "$(line "$R")" = NONE ] && ok "no_auto_delete.txt: auto-delete off is not drift for a listed repo" || bad "opt-out: $(line "$R")"
put true true false false
line "$R" | grep -q "allow_merge_commit on" && ! line "$R" | grep -q delete_branch && ok "…but its other settings still are" || bad "opt-out others: $(line "$R")"
rm "$DEV_CADENCE_REG_DIR/no_auto_delete.txt"
put true true false false
[ "$(line "$R")" = "⚙ repo settings differ from cadence.md §4: allow_merge_commit on, delete_branch_on_merge off — \`scripts/adopt_repo_settings.sh --check\` for the detail (never applied from here)" ] \
    && ok "drift: one line naming each setting, pointing at the adopt script" || bad "drift: $(line "$R")"
CADENCE_REPO_ROOT="$R" line "$R" | grep -qF "— \`dev-cadence run adopt_repo_settings.sh --check\` for the detail" \
    && ok "drift from a pin: the hint is the launcher's word (TD-164)" || bad "drift pinned: $(CADENCE_REPO_ROOT="$R" line "$R")"
put true true false null
[ "$(line "$R")" = NONE ] && ok "a null field (a non-admin): nothing said — never a guess" || bad "null: $(line "$R")"
touch "$GH_FAIL"; [ "$(line "$R")" = NONE ] && ok "gh cannot answer: nothing said" || bad "gh fail: $(line "$R")"; rm "$GH_FAIL"
git -C "$R" remote set-url origin https://gitea.example/tester/thing.git; : > "$GH_LOG"
[ "$(line "$R")" = "⚙ repo settings not checked: origin is gitea.example, which the cadence cannot read yet (TD-097)" ] && [ ! -s "$GH_LOG" ] \
    && ok "not a GitHub origin: a 'not checked' line, never a clean row, and no gh call (TD-098)" || bad "non-github: $(line "$R") / $(cat "$GH_LOG")"
git -C "$R" remote remove origin
[ "$(line "$R")" = NONE ] && [ ! -s "$GH_LOG" ] && ok "no origin at all: no line, no gh call" || bad "no origin: $(line "$R") / $(cat "$GH_LOG")"
git -C "$R" remote add origin https://gitea.example/tester/thing.git
! grep -rq 'PATCH\|-X' "$GH_LOG" && ok "never a write: only GETs reached gh" || bad "a write reached gh"
# one copy with adopt_repo_settings.sh: its WANT is `forge.py wanted` since TD-104
want=$(python3 "$S/forge.py" wanted tester/thing | sort | tr '\n' ' ')
have=$(python3 -c "import sys; sys.path.insert(0,'$S'); import nudge_user_attention as N; print(' '.join(sorted(f'{k}={str(v).lower()}' for k,v in N.CADENCE_SETTINGS.items())))")
[ "$want" = "$have " ] && ok "CADENCE_SETTINGS matches adopt_repo_settings.sh's WANT (forge.py wanted)" || bad "parity: adopt='$want' nudge='$have'"

# --json carries it for fetched rows of the full report, never for --due-only (report()'s wiring,
# in-process: a real --fetch against a GitHub origin would go to the network)
B="$TMP/wired"; git init -q "$B"; mkdir -p "$B/docs"; echo "# board" > "$B/docs/user_attention.md"
echo "$B" > "$DEV_CADENCE_REG_DIR/repos.txt"
w=$(python3 - "$S" <<'PYW'
import contextlib, io, json, sys
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
N._fetch_board = lambda root, board, deadline=None: N.FetchResult("fetched; board matches origin/main")
N.settings_line = lambda root, spent: "⚙ drift"
N.staleness_line = lambda board: None
N.open_pr_lines = lambda root, deadline: []
def run(**kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        N.report([], True, as_json=True, **kw)
    return json.loads(buf.getvalue())["boards"][0]["settings"]
print(run(), run(due_only=True))
PYW
)
[ "$w" = "⚙ drift None" ] && ok "--json --fetch carries the settings line; --json --due-only never computes it" || bad "json wiring: $w"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
