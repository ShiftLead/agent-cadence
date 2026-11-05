#!/usr/bin/env bash
# TD-218: the review row's decide-lift carve-out (check_cadence.py row_lift_pr, ledgerboard v2.4's
# lift_pr_verdict) and the direct audit's (d) (classify_direct: a gate item's answer lands by PR only).
# The verdict's own cases are ledgerboard's fixtures (tests/ledgerboard/verdict, run by
# test_ledgerboard_fixtures.sh); this suite lays a few into a git repo and reads the rows. A gate-less decide
# staying the plain board-edit carve-out is test_board_writers.sh's.
# Offline: temp git repos with a bare origin and a stub forge; HOME/XDG_CONFIG_HOME are temp. The fixtures'
# dates are ledgerboard's own, and created_at is given to match them, so nothing reads the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
V="$DC/tests/ledgerboard/verdict"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/widgets"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"
cp -r "$V/base/docs" "$R/docs"; echo x > "$R/other.txt"
git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null
LIFT="a lift, closed in the same write"
DECIDE="board: decide Warm the cache nightly?: Go (session w-1)"

# the review row (board_edit_or_review) on HEAD, and the direct audit's class of HEAD: "<status>\t<class>\t<detail>"
judge() {  # $1 = state (open|merged), $2 = created_at
  python3 - "$R" "$1" "$2" "$S" <<'EOF'
import sys
root, state, created, s = sys.argv[1:]
import os
sys.path.insert(0, s)
import check_cadence as C
class Stub:
    cli = "gh"
    def comments(self, n):
        return []
    def pr_commits(self, pr):  # TD-224: a merged PR's one-commit property is the forge's count
        return pr.get("commits")
C.FORGE = Stub()
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
base = C.git(["rev-parse", "origin/main"], cwd=root).strip()
rng = f"{sha}^..{sha}" if state == "merged" else f"{base}..{sha}"
files = sorted(set(C.git(["diff", "--name-only", rng], cwd=root).split()))
subj = C.git(["log", "-1", "--format=%s", sha], cwd=root).strip()
pr = {"number": 5, "ref": "#5", "state": state, "head_sha": sha, "merge_sha": sha, "files": files, "title": subj,
      "created_at": created, "merged_at": "2026-01-15T12:00:00Z" if state == "merged" else None,
      "commits": int(os.environ.get("COMMITS", "1"))}
r = C.board_edit_or_review(pr, root)
one = sorted(C.git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd=root).split())
cls, _ = C.classify_direct(root, sha, subj, one)
print(f"{r['status']}\t{cls}\t{r['detail']}\t{r.get('carve_out')}")
EOF
}
case_pr() {  # $1 = a verdict case, $2 = the commit's subject, $3.. = only these paths of its head (default all)
  local name=$1 subj=$2; shift 2
  git -C "$R" switch -q -C topic origin/main
  if [ $# -eq 0 ]; then cp -r "$V/cases/$name/head/docs/." "$R/docs/"
  else for p in "$@"; do cp "$V/cases/$name/head/$p" "$R/$p"; done; fi
  git -C "$R" add -A; git -C "$R" commit -qm "$subj"
}

# a decide lift, one commit: the person's answer is its review
case_pr "$LIFT" "$DECIDE"
IFS=$'\t' read -r st cls det co <<< "$(judge open 2026-01-15T09:00:00Z)"
[ "$st" = pass ] && echo "$det" | grep -q "decide lift" && ok "a one-commit decide lift passes the review row (no comment)" || bad "lift: $st $det"
[ "$co" = decide-lift ] && ok "TD-234: the lift's review row carries carve_out decide-lift (a tool merge to --since, not a bypass)" || bad "lift carve_out: '$co'"
# the gate's other rows accept it too: the board row (the writer's line) and the gates row (the tripwire)
rows=$(python3 - "$R" "$S" <<'EOF2'
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
pr = {"state": "open", "head_sha": sha, "files": ["docs/ledger/TD-100.md", "docs/user_attention.md"]}
print(C.row_board(pr, root)["status"], C.row_gates(pr, root)["status"])
EOF2
)
[ "$rows" = "pass pass" ] && ok "the lift passes the board and gates rows" || bad "other rows: $rows"
# the same, squash-merged under the PR's title with (#5): still the carve-out
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic >/dev/null 2>&1; git -C "$R" commit -qm "$DECIDE (#5)"
IFS=$'\t' read -r st cls det <<< "$(judge merged 2026-01-15T09:00:00Z)"
[ "$st" = pass ] && echo "$det" | grep -q "decide lift" && ok "the lift squash-merged (subject ending (#5)) passes" || bad "merged lift: $st $det"
# TD-224: the same tip from a PR the forge says carried two commits (a rebase merge): not a lift
IFS=$'\t' read -r st cls det <<< "$(COMMITS=2 judge merged 2026-01-15T09:00:00Z)"
[ "$st" = fail ] && echo "$det" | grep -q "is not a decide lift" && ok "the same tip from a two-commit PR takes review (TD-224)" || bad "merged two-commit lift: $st $det"
git -C "$R" reset -q --hard origin/main

# opened two days after the answer's date: out of the window, so ordinary review — with no comment, a fail naming why
case_pr "$LIFT" "$DECIDE"
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-18T09:00:00Z)"
[ "$st" = fail ] && echo "$det" | grep -q "answers a gate item and is not a decide lift" \
  && ok "a lift dated outside the PR's window takes review, the row naming why" || bad "window: $st $det"
# two commits, the decide last: not a lift PR
git -C "$R" switch -q -C topic origin/main; echo z >> "$R/other.txt"; git -C "$R" commit -qam unrelated
cp -r "$V/cases/$LIFT/head/docs/." "$R/docs/"; git -C "$R" add -A; git -C "$R" commit -qm "$DECIDE"
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-15T09:00:00Z)"
[ "$st" = fail ] && echo "$det" | grep -q "one commit" && ok "a two-commit lift takes review (a lift PR is one commit)" || bad "two commits: $st $det"
# a subject that is not the board's decide
case_pr "$LIFT" "ledger: set TD-100 (session w-1)"
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-15T09:00:00Z)"
[ "$st" = fail ] && echo "$det" | grep -q "subject is not a board decide" && ok "a lift under another subject takes review" || bad "subject: $st $det"
# no createdAt from the forge: not judged a lift
case_pr "$LIFT" "$DECIDE"
IFS=$'\t' read -r st cls det <<< "$(judge open "")"
[ "$st" = fail ] && echo "$det" | grep -q "createdAt" && ok "no createdAt: ordinary review, said" || bad "no created: $st $det"

# the board's answer alone, under the decide subject: the old board-edit carve-out no longer takes it, and the
# direct audit refuses it — a gate item's answer lands by PR only (d)
case_pr "$LIFT" "$DECIDE" docs/user_attention.md
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-15T09:00:00Z)"
[ "$st" = fail ] && [ "$cls" = fail ] && echo "$det" | grep -q "not a decide lift" \
  && ok "a gate item answered on the board alone is not the board-edit carve-out" || bad "board alone: $st $cls $det"
python3 - "$R" "$S" <<'EOF' | grep -q "lands by PR only" && ok "the direct audit fails a gate item's answer: by PR only (d)" || bad "direct (d)"
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
print(C.classify_direct(root, sha, C.git(["log", "-1", "--format=%s"], cwd=root).strip(), ["docs/user_attention.md"]))
EOF

# a board holding a line break other than a newline (here U+2028 in a gate item's text, already at the base) is
# never a carve-out's: the carve-outs read lines by splitlines(), the verdicts by "\n" (TD-218 review, PR #101)
git -C "$R" switch -q -C sep origin/main
python3 - "$R/docs/user_attention.md" <<'EOF2'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("Warm the cache", "Warm\u2028 the cache", 1))
EOF2
git -C "$R" commit -qam "a separator on the board"
python3 - "$R/docs/user_attention.md" <<'EOF2'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
lines = t.split("\n")
i = next(n for n, ln in enumerate(lines) if "Warm" in ln)
lines[i] = lines[i].replace("One more round.", "One more round. Decided: Go (by pat) (2026-01-15).")
open(p, "w", encoding="utf-8").write("\n".join(lines))
EOF2
git -C "$R" commit -qam "$DECIDE"
python3 - "$R" "$S" <<'EOF2' | grep -q "^none fail fail$" && ok "a U+2028 board: no carve-out passes a gate answer, PR or direct" || bad "separator: $(python3 - "$R" "$S" <<<'' 2>&1 | tail -1)"
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
class Stub:
    cli = "gh"
    def comments(self, n):
        return []
C.FORGE = Stub()
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s", sha], cwd=root).strip()
C.git(["update-ref", "refs/remotes/origin/main", f"{sha}^"], cwd=root)  # the PR is the answer commit alone
pr = {"number": 5, "ref": "#5", "state": "open", "head_sha": sha, "files": ["docs/user_attention.md"], "title": subj,
      "created_at": "2026-01-15T09:00:00Z"}
e = C.row_board_edit_pr(pr, root)
r = C.board_edit_or_review(pr, root)
print("none" if e is None else e["status"], r["status"], C.classify_direct(root, sha, subj, ["docs/user_attention.md"])[0])
EOF2
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R.git" rev-parse main)"

# the forge's file list is not trusted: a lift whose forge list names only the board and ledger, but whose one
# commit also changes another file, takes review (the commit's own files are judged)
case_pr "$LIFT" "$DECIDE"; echo w >> "$R/other.txt"; git -C "$R" commit -q --amend -a --no-edit
st=$(python3 - "$R" "$S" <<'EOF2'
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
class Stub:
    cli = "gh"
    def comments(self, n):
        return []
C.FORGE = Stub()
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
pr = {"number": 5, "ref": "#5", "state": "open", "head_sha": sha, "title": "x", "created_at": "2026-01-15T09:00:00Z",
      "files": ["docs/ledger/TD-100.md", "docs/user_attention.md"]}
print(C.board_edit_or_review(pr, root)["status"])
EOF2
)
[ "$st" = fail ] && ok "a lift whose commit changes a file the forge's list leaves out takes review" || bad "files: $st"

# a PR answering no gate item is not this carve-out's: a ledger-only PR reads as ordinary review, nothing appended
case_pr "a gate removed by hand" "ledger: set TD-150 (session w-1)"
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-15T09:00:00Z)"
! echo "$det" | grep -q "decide lift" && ok "a PR that answers no gate item is not judged as a lift" || bad "not a lift: $st $det"

echo "test_lift_pr.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
