#!/usr/bin/env bash
# TD-218: the review row's decide-lift carve-out (check_cadence.py row_lift_pr, ledgerboard v2.4's
# lift_pr_verdict), TD-262's ledger lift (row_ledger_lift_pr, v3.3's ledger_lift_verdict) and the direct
# audit's (d) (classify_direct: a gate item's answer lands by PR only), on
# ledgerboard v3.0's board directory (TD-263).
# The verdict's own cases are ledgerboard's fixtures (tests/ledgerboard/verdict, run by
# test_ledgerboard_fixtures.sh); this suite lays a few into a git repo and reads the rows. A gate-less decide
# staying the plain board-edit carve-out is test_board_row.sh's.
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
case_pr() {  # $1 = a verdict case, $2 = the commit's subject, $3.. = only these paths of its head (default all);
  #             the case's deletes (cases.json) are made with the paths they pair with
  local name=$1 subj=$2; shift 2
  git -C "$R" switch -q -C topic origin/main
  if [ $# -eq 0 ]; then cp -r "$V/cases/$name/head/docs/." "$R/docs/"
  else for p in "$@"; do mkdir -p "$(dirname "$R/$p")"; cp "$V/cases/$name/head/$p" "$R/$p"; done; fi
  python3 - "$V/cases.json" "$name" <<'EOF' | while IFS= read -r p; do rm -f "$R/$p"; done
import json, sys
for c in json.load(open(sys.argv[1]))["verdict"]:
    if c["name"] == sys.argv[2]:
        print("\n".join(c.get("delete", [])))
EOF
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
files = sorted(set(C.git(["diff", "--name-only", "origin/main", sha], cwd=root).split()))
pr = {"state": "open", "head_sha": sha, "files": files}
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
git -C "$R" switch -q -C topic origin/main; git -C "$R" commit -q --allow-empty -m unrelated
cp -r "$V/cases/$LIFT/head/docs/." "$R/docs/"; rm "$R/docs/user_attention/2026-01-06-85a7b461.md"
git -C "$R" add -A; git -C "$R" commit -qm "$DECIDE"
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
case_pr "$LIFT" "$DECIDE" docs/user_attention/archive/2026-01/2026-01-06-85a7b461.md
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-15T09:00:00Z)"
[ "$st" = fail ] && [ "$cls" = fail ] && echo "$det" | grep -q "not a decide lift" \
  && ok "a gate item answered on the board alone is not the board-edit carve-out" || bad "board alone: $st $cls $det"
python3 - "$R" "$S" <<'EOF' | grep -q "lands by PR only" && ok "the direct audit fails a gate item's answer: by PR only (d)" || bad "direct (d)"
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
files = sorted(C.git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd=root).split())
print(C.classify_direct(root, sha, C.git(["log", "-1", "--format=%s"], cwd=root).strip(), files))
EOF

# a board holding a line break other than a newline (here U+2028 in a gate item's text, already at the base) is
# never a carve-out's: the carve-outs read lines by splitlines(), the verdicts by "\n" (TD-218 review, PR #101)
git -C "$R" switch -q -C sep origin/main
IT="$R/docs/user_attention/2026-01-06-85a7b461.md"
python3 - "$IT" <<'EOF2'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("**Session:** w-1", "**Session:** w-1\n**Note:** a\u2028b", 1))
EOF2
git -C "$R" commit -qam "a separator on the board"
python3 - "$IT" <<'EOF2'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("**Answers:**", "**Decided:** 2026-01-15 by pat — Go\n**Answers:**", 1)
         if "**Decided:**" not in t else t)
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
files = ["docs/user_attention/2026-01-06-85a7b461.md"]
pr = {"number": 5, "ref": "#5", "state": "open", "head_sha": sha, "files": files, "title": subj,
      "created_at": "2026-01-15T09:00:00Z"}
e = C.row_board_edit_pr(pr, root)
r = C.board_edit_or_review(pr, root)
print("none" if e is None else e["status"], r["status"], C.classify_direct(root, sha, subj, files)[0])
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
      "files": ["docs/ledger/TD-100.md", "docs/user_attention/2026-01-06-85a7b461.md",
                "docs/user_attention/archive/2026-01/2026-01-06-85a7b461.md"]}
print(C.board_edit_or_review(pr, root)["status"])
EOF2
)
[ "$st" = fail ] && ok "a lift whose commit changes a file the forge's list leaves out takes review" || bad "files: $st"

# a PR answering no gate item is not this carve-out's: a ledger-only PR reads as ordinary review, nothing appended
case_pr "a gate removed by hand" "ledger: set TD-150 (session w-1)"
IFS=$'\t' read -r st cls det <<< "$(judge open 2026-01-15T09:00:00Z)"
! echo "$det" | grep -q "decide lift" && ok "a PR that answers no gate item is not judged as a lift" || bad "not a lift: $st $det"

# --- TD-262: the ledger lift (ledgerboard v3.3's ledger_lift_verdict), ShiftLead's Lift the hold press's PR. Each
# case is laid as ledgerboard's run.py lays it: main = the verdict base plus the case's base overlay, less its
# delete_base; the topic's one commit = its head overlay, less its delete, under the case's subject (the PR's title).
LR="$TMP/lifts"; git init -q --bare -b main "$LR.git"; git init -q -b main "$LR"; git -C "$LR" remote add origin "$LR.git"
lift_case() {  # $1 = a ledger_lift case; $2 = extra: "" or "other" (also change a file outside the lift)
  local name=$1 extra=${2:-}
  python3 - "$V" "$name" "$LR" "$extra" <<'EOF'
import json, os, shutil, subprocess, sys
v, name, root, extra = sys.argv[1:]
c = next(x for x in json.load(open(f"{v}/cases.json"))["ledger_lift"] if x["name"] == name)
def git(*a): subprocess.run(["git", "-C", root, *a], check=True, capture_output=True)
def lay(src):
    if os.path.isdir(src):
        shutil.copytree(src, root, dirs_exist_ok=True)
def drop(paths):
    for p in paths:
        q = os.path.join(root, p)
        shutil.rmtree(q) if os.path.isdir(q) else (os.path.exists(q) and os.remove(q))
git("switch", "-q", "--orphan", "b"); subprocess.run(["git", "-C", root, "rm", "-rqf", "--ignore-unmatch", "."], check=True)
for e in os.listdir(root):
    if e != ".git":
        drop([e])
lay(f"{v}/base"); lay(f"{v}/cases/{name}/base"); drop(c.get("delete_base", []))
open(os.path.join(root, "other.txt"), "w").write("x\n")
git("add", "-A"); git("commit", "-qm", "base"); git("branch", "-M", "main"); git("push", "-qf", "origin", "main")
git("fetch", "-q", "origin"); git("switch", "-q", "-C", "topic", "origin/main")
lay(f"{v}/cases/{name}/head"); drop(c.get("delete", []))
if extra == "other":
    open(os.path.join(root, "other.txt"), "a").write("w\n")
git("add", "-A"); git("commit", "-qm", c["subject"])
EOF
}
ljudge() {  # $1 = state (open|merged) — "<status>\t<carve_out>\t<detail>" of the review row (board_edit_or_review)
  python3 - "$LR" "$1" "$S" <<'EOF'
import sys
root, state, s = sys.argv[1:]
sys.path.insert(0, s)
import os
import check_cadence as C
class Stub:
    cli = "gh"
    def comments(self, n):
        return []
    def pr_commits(self, pr):
        return pr.get("commits")
C.FORGE = Stub()
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
base = C.git(["rev-parse", "origin/main"], cwd=root).strip()
rng = f"{sha}^..{sha}" if state == "merged" else f"{base}..{sha}"
files = sorted(set(C.git(["diff", "--name-only", rng], cwd=root).split()))
if os.environ.get("FORGE_FILES"):  # the forge's list, when a case says it differs from the commit's own
    files = os.environ["FORGE_FILES"].split(",")
title = C.git(["log", "-1", "--format=%s", sha], cwd=root).strip().removesuffix(" (#7)")
pr = {"number": 7, "ref": "#7", "state": state, "head_sha": sha, "merge_sha": sha, "files": files, "title": title,
      "created_at": "2026-01-15T09:00:00Z", "merged_at": "2026-01-15T12:00:00Z" if state == "merged" else None,
      "commits": 1}
r = C.board_edit_or_review(pr, root)
print(f"{r['status']}\t{r.get('carve_out')}\t{r['detail']}")
EOF
}
# a lift with no covering item: the entry's file alone, as lift_gate() writes it — the press is its review
lift_case "lift-none"
IFS=$'\t' read -r st co det <<< "$(ljudge open)"
[ "$st" = pass ] && [ "$co" = lift ] && echo "$det" | grep -q "ledger lift" \
  && ok "TD-262: a ledger lift (the entry alone) passes the review row as carve-out lift, no comment" || bad "ledger lift: $st $co $det"
# the same squash-merged under its title with (#7): still the carve-out, so --since lists it as a tool merge
git -C "$LR" switch -q main; git -C "$LR" merge -q --squash topic >/dev/null 2>&1
git -C "$LR" commit -qm "shiftlead: lift decision (pat) on TD-160 (session n/a) (#7)"
IFS=$'\t' read -r st co det <<< "$(ljudge merged)"
[ "$st" = pass ] && [ "$co" = lift ] && ok "TD-262: the ledger lift squash-merged (#7) is still carve-out lift" || bad "merged ledger lift: $st $co $det"
# a lift that closes its covering decided item — lifted, as edit_item() writes it
lift_case "lift-decided"
IFS=$'\t' read -r st co det <<< "$(ljudge open)"
[ "$st" = pass ] && [ "$co" = lift ] && ok "TD-262: a ledger lift closing its covering item — lifted passes" || bad "decided lift: $st $co $det"
# the lift's title with another file changed: ordinary review, the row naming why
lift_case "lift-none" other
IFS=$'\t' read -r st co det <<< "$(ljudge open)"
[ "$st" = fail ] && [ "$co" = None ] && echo "$det" | grep -q "is not a ledger lift (the PR changes other.txt" \
  && ok "TD-262: a lift's title that also changes another file takes review, saying why" || bad "lift + other file: $st $co $det"
# the lift's title over a diff that does not recompute (the gate dropped, no lift Log line): ordinary review
lift_case "lift-no new Log line"
IFS=$'\t' read -r st co det <<< "$(ljudge open)"
[ "$st" = fail ] && [ "$co" = None ] && echo "$det" | grep -q "is not a ledger lift (TD-160's Log does not gain" \
  && ok "TD-262: a lift's title over a diff lift_gate() does not write takes review" || bad "no log line: $st $co $det"
# two commits, the lift last: not a lift PR (the verdict is told 2, so the lift's one-commit rule fails)
lift_case "lift-none"; git -C "$LR" reset -q --soft HEAD^; git -C "$LR" stash -q
git -C "$LR" commit -q --allow-empty -m unrelated; git -C "$LR" stash pop -q; git -C "$LR" add -A
git -C "$LR" commit -qm "shiftlead: lift decision (pat) on TD-160 (session n/a)"
IFS=$'\t' read -r st co det <<< "$(ljudge open)"
[ "$st" = fail ] && [ "$co" = None ] && echo "$det" | grep -q "a lift PR is one commit" \
  && ok "TD-262: a two-commit ledger lift takes review" || bad "two-commit ledger lift: $st $co $det"
# the forge's list is not trusted: it names the entry alone, but the one commit also changes other.txt
lift_case "lift-none" other
IFS=$'\t' read -r st co det <<< "$(FORGE_FILES=docs/ledger/TD-160.md ljudge open)"
[ "$st" = fail ] && [ "$co" = None ] && echo "$det" | grep -q "other.txt" \
  && ok "TD-262: a ledger lift whose commit changes a file the forge's list leaves out takes review" || bad "forge files: $st $co $det"
# a lift by someone not the gate's person on People: ordinary review
lift_case "lift-the gate's person not on People"
IFS=$'\t' read -r st co det <<< "$(ljudge open)"
[ "$st" = fail ] && [ "$co" = None ] && ok "TD-262: a lift by a person not on People: takes review" || bad "not on People: $st $co $det"

echo "test_lift_pr.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
