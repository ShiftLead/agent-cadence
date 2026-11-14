#!/usr/bin/env bash
# TD-206 §3, TD-263: the cadence check's `board` row — each item's net change across a PR, by the writers' rules
# (check_cadence.py board_change_problems / row_board), on ledgerboard v3.0's board directory (items paired by id),
# and the same rules in the direct-commit audit (classify_direct).
# Offline: temp git repos with a bare origin; HOME/XDG_CONFIG_HOME are temp; dates derive from the run date (TD-24).
set -u
export TZ=UTC
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

# --- 1) the rules, on Boards built from item files (board_change_problems): each case passes or fails, a failure
#        naming its command
out=$(python3 - "$S" <<'EOF'
import sys, itertools
from datetime import date, timedelta
sys.path.insert(0, sys.argv[1])
import check_cadence as C
import ledgerboard as lb
T = date.today(); P = T - timedelta(3); F = T + timedelta(9); F2 = T + timedelta(20)
D = C.BOARD_DIR
README = "# board\n\nLedgerboard: 3\nSwept: %s (h, quick)\n\nPeople: Pat\n" % T
def iid(n):
    return f"{P}-{n:08x}"
CAN = lb.item_file("rotate the key", F.isoformat(), P.isoformat(), "abcdef12", "h", "TD-1")
OLD = lb.item_file("an old item", F.isoformat(), P.isoformat(), None, None, None)
DEC = lb.item_file("pick one?", F.isoformat(), P.isoformat(), "aa", "h", "TD-2", kind="decide", answers=["a", "b"],
                   default=0, detail={"context": "c.", "question": "q?", "recommended": "x."})
FYI = lb.item_file("heads up", None, P.isoformat(), None, None, "TD-3", kind="fyi")
def path(i, text):
    it = lb.parse_item(text)
    return f"{D}/" + (lb.item_path(i, it.closed[0].isoformat()) if it and it.closed and it.closed[0] else lb.item_path(i))
def board(*items, readme=README):
    """items: (n, text) pairs; a closed text lands under archive/."""
    tree = {f"{D}/README.md": readme}
    for n, text in items:
        tree[path(iid(n), text)] = text
    return C.board_of(tree)
def fails(r):
    return [m for s, m in r if s == "fail"]
results = []
def case(name, base, head, want_pass, needle=None):
    r = fails(C.board_change_problems(base, head))
    good = (not r) if want_pass else (bool(r) and (needle is None or any(needle in m for m in r)))
    results.append((good, name, r))
def ed(text, *steps):
    for a, kw in steps:
        text = lb.edit_item(text, a, today=kw.pop("today", T), **kw)
    return text
# replay: every order of the writers' edits on several bases reproduces
acts = [("due", {"to": F2}), ("snooze", {"to": F}), ("reply", {"reply": "ok then", "by": "Pat"}),
        ("decide", {"answer": "b", "by": "Pat"}), ("done", {"why": "handled"})]
n = bad_n = 0
for b in (CAN, OLD, DEC, FYI):
    for k in range(1, 4):
        for seq in itertools.permutations(acts, k):
            if any(a == "done" for a, _ in seq[:-1]):
                continue
            try:
                new = ed(b, *[(a, dict(kw)) for a, kw in seq])
            except lb.Refused:
                continue
            n += 1
            if not C.writers_made(b, new):
                bad_n += 1
results.append((bad_n == 0 and n > 100, f"replay: {n} writer sequences, {bad_n} not reproduced", []))
GATE = lb.item_file("lift it?", F.isoformat(), P.isoformat(), "aa", "h", "TD-5 decision (Pat)", kind="decide",
                    answers=["Go", "Not yet"], default=0, detail={"context": "c.", "question": "q?", "recommended": "x."})
results.append((C.writers_made(GATE, lb.edit_item(GATE, "decide", answer="Go", by="Pat", today=T, close=True)),
                "replay: a decide that closes its gate item", []))
# passing cases
case("a writer snooze, reply, decide and done on one item, in one PR", board((1, CAN)),
     board((1, ed(CAN, ("snooze", {"to": F}), ("reply", {"reply": "fine", "by": "Pat"}), ("decide", {"answer": "go", "by": "Pat"}),
                  ("done", {"why": "did it"})))), True)
case("an unchanged board", board((1, CAN)), board((1, CAN)), True)
case("add --decided", board((1, CAN)),
     board((1, CAN), (2, lb.decided_file("decided already", "TD-8", [], None, "Go", T.isoformat(), by="Pat"))), True)
case("a new canonical decide with its block", board((1, CAN)), board((1, CAN), (2, DEC)), True)
case("a detail-block edit is no writer's: fails", board((2, DEC)), board((2, DEC.replace("- **Context:** c.", "- **Context:** c, more."))), False,
     "board_edit.py fmt")
case("a corrected item: done on the old one plus add of the new", board((1, CAN)),
     board((1, ed(CAN, ("done", {"why": "superseded"}))), (2, CAN.replace("rotate the key", "rotate both keys"))), True)
case("fmt's rewrite plus a reply", board((1, CAN.replace("**Due:**", "**due:**"))),
     board((1, ed(lb.canonical_item_file(CAN.replace("**Due:**", "**due:**")), ("reply", {"reply": "y", "by": "Pat"})))), True)
r = C.board_change_problems(board((1, CAN), readme=README.replace("People: Pat", "People: Pat, Pat")),
                           board((1, ed(CAN, ("snooze", {"to": F}))), readme=README.replace("People: Pat", "People: Pat, Pat")))
results.append((not fails(r) and any(s == "info" for s, _ in r), "a faulty People: line the PR does not touch is ℹ", r))
# failing cases, each naming its command
case("a new malformed item file", board((1, CAN)), board((1, CAN), (2, "## no header\n")), False, "board_edit.py add")
case("a reshaped item (fields out of order)", board((1, CAN)), board((1, CAN.replace("**Context:** TD-1\n", "").replace("\n\n", "\n\n", 1).replace(f"**Due:** {F}", f"**Due:** {F}\n**Context:** TD-1"))), False, "board_edit.py")
case("a hand close with no Closed: date the writers write", board((1, CAN)),
     board((1, CAN.replace(f"**Due:** {F}", f"**Due:** {F}\n**Closed:** soon"))), False, "board_edit.py")
case("a hand Decided: without by", board((2, DEC)), board((2, DEC.replace(f"**Answers:**", f"**Decided:** {T} — b\n**Answers:**"))), False)
case("a Decided: by someone not on People:", board((2, DEC)), board((2, ed(DEC, ("decide", {"answer": "b", "by": "Sam"})))), False,
     "not on the board's People:")
case("a new open decide with no detail block", board((1, CAN)),
     board((1, CAN), (2, DEC.split("\n\n- ")[0] + "\n")), False, "board_edit.py add --detail")
case("a deleted open item", board((1, CAN), (2, OLD)), board((2, OLD)), False, "board_edit.py done")
case("editing an item's words in place", board((1, CAN)), board((1, CAN.replace("rotate the key", "rotate both keys"))), False,
     "not what the writers make")
case("a closed item with no open item it closes", board((1, CAN)), board((1, CAN), (2, ed(OLD, ("done", {"why": "x"})))), False,
     "board_edit.py done")
case("an archived item changed", board((1, ed(CAN, ("done", {"why": "x"})))), board((1, ed(CAN, ("done", {"why": "y"})))), False,
     "archived item changed")
case("a new decide whose gate person is not on People:", board((1, CAN)),
     board((1, CAN), (2, DEC.replace("**Context:** TD-2", "**Context:** TD-2 decision (Sam)"))), False, "People:")
case("a PR that touches People: and leaves a fault", board((1, CAN)),
     board((1, CAN), readme=README.replace("People: Pat", "People: Pat, Pat")), False, "People:")
case("an impossible reply date fails, not a crash", board((1, CAN)), board((1, CAN + "\n**Log:**\n- 2026-13-45: Pat: hi\n")), False)
# a closed item at the wrong path
tree = {f"{D}/README.md": README, f"{D}/archive/1999-01/{iid(1)}.md": ed(CAN, ("done", {"why": "x"}))}
case("a done filed under the wrong month", board((1, CAN)), C.board_of(tree), False, "the writers put this item at")
# across the split: a v2 board's items pair by id with the files split_board() gives
v2 = f"# board\n\nPeople: Pat\n\n- [ ] {P} (n/a) — rotate the key. Context: TD-1. Due: {F}.\n"
split = lb.split_board(v2)
v3 = C.board_of({f"{D}/{k}": v for k, v in split.items()})
v2b = C.board_of({C.BOARD_STUB: v2})
results.append((v2b.form == "file" and not fails(C.board_change_problems(C._as_v3(v2b, {C.BOARD_STUB: v2}), v3)),
                "a split PR: the v2 base, split, against the head's files", []))
for good, name, r in results:
    print(("ok" if good else "NO") + "\t" + name + ("" if good else "\t" + repr(r)[:300]))
EOF
)
while IFS=$'\t' read -r st name rest; do
  [ "$st" = ok ] && ok "$name" || bad "$name ${rest:-}"
done <<< "$out"

# --- 2) the row on a PR (row_board): open, multi-commit, judged on its merge-base; merged, on its squash; the
#        direct audit applies the same rules
R="$TMP/r"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"
B="$R/docs/user_attention"; mkdir -p "$B"
P=$(date -d "3 days ago" +%F); F=$(date -d "9 days" +%F); T=$(date +%F)
I1="$P-0000000a"; I2="$P-0000000b"
printf '# board\n\nLedgerboard: 3\n\nPeople: Pat\n' > "$B/README.md"
printf '# board\n\nLedgerboard: 3\n\nThis board is the directory [user_attention/](user_attention/), one file per item.\n' > "$R/docs/user_attention.md"
lbw() { (cd "$S" && python3 -m ledgerboard.board "$@" --json); }
lbw add --board "$B" --id "$I1" --today "$P" --session abcdef12 --host h --text "rotate the key" --context TD-1 --due "$F" >/dev/null
lbw add --board "$B" --id "$I2" --today "$P" --text "plain item" --context TD-2 --due "$F" >/dev/null
echo x > "$R/other.txt"; git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null
git -C "$R" switch -q -c topic
commit() { git -C "$R" add -A; git -C "$R" commit -qm "$1"; }
subj() { python3 -c 'import json,sys; print(json.load(sys.stdin)["subject"])'; }
row() {  # $1 = state (open|merged), $2 = sha
  python3 - "$R" "$1" "$2" "$S" <<'EOF'
import sys
root, state, sha, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", sha], cwd=root).strip()
base = C.git(["rev-parse", "origin/main"], cwd=root).strip()
rng = f"{sha}^..{sha}" if state == "merged" else f"{base}..{sha}"
files = sorted(set(C.git(["diff", "--name-only", rng], cwd=root).split()))
pr = {"state": state, "head_sha": sha, "merge_sha": sha, "files": files}
r = C.row_board(pr, root)
print(r["status"], r["detail"])
EOF
}
commit "$(lbw snooze --board "$B" --id "$I1" --to "$F" | subj)"
commit "$(lbw done --board "$B" --id "$I2" --why handled | subj)"
st=$(row open HEAD); [ "${st%% *}" = pass ] && ok "an open PR: a snooze commit then a done that archives passes (merge-base)" || bad "open snooze+done: $st"
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic; git -C "$R" commit -qm "squash (#9)"
st=$(row merged HEAD); [ "${st%% *}" = pass ] && ok "the same PR after its squash merge passes" || bad "merged: $st"
git -C "$R" reset -q --hard origin/main; git -C "$R" switch -q topic; git -C "$R" reset -q --hard origin/main
# a hand move into the archive fails
mkdir -p "$B/archive/${T:0:7}"; git -C "$R" mv "$B/$I2.md" "$B/archive/${T:0:7}/$I2.md"; commit "move by hand"
st=$(row open HEAD); [ "${st%% *}" = fail ] && echo "$st" | grep -q "board_edit.py" \
  && ok "an open PR: a hand move into the archive fails, naming the command" || bad "hand move: $st"
git -C "$R" reset -q --hard origin/main
# na on a PR that does not touch the board; the row is a hard fail on a hand slip
echo y >> "$R/other.txt"; commit other
st=$(row open HEAD); [ "${st%% *}" = na ] && ok "the row is na on a PR that does not change the board" || bad "na: $st"
sed -i "s/^\*\*Context:\*\* TD-2$/**Context:** TD-22/" "$B/$I2.md"; commit "hand edit"
st=$(row open HEAD); [ "${st%% *}" = fail ] && echo "$st" | grep -q "board_edit.py" && ok "a hand edit fails the row (fail, not ℹ), naming the command" || bad "hand edit: $st"
# a PR whose head is still a v2 board file fails (split first); merged it is a ⚠
git -C "$R" reset -q --hard origin/main
V="$TMP/v"; git init -q --bare -b main "$V.git"; git init -q -b main "$V"; git -C "$V" remote add origin "$V.git"; mkdir -p "$V/docs"
printf '# board\n\nPeople: Pat\n\n- [ ] %s (n/a) — a. Context: TD-1. Due: %s.\n' "$P" "$F" > "$V/docs/user_attention.md"
git -C "$V" add -A; git -C "$V" commit -qm base; git -C "$V" push -q origin main 2>/dev/null; git -C "$V" switch -q -c t
printf -- '- [ ] %s (n/a) — b. Context: TD-2. Due: %s.\n' "$P" "$F" >> "$V/docs/user_attention.md"; git -C "$V" commit -qam add
R0="$R"; R="$V"
st=$(row open HEAD); [ "${st%% *}" = fail ] && echo "$st" | grep -q "split" && ok "a v2 board at an open PR's head fails: split first" || bad "v2 open: $st"
st=$(row merged HEAD); [ "${st%% *}" = pass ] && echo "$st" | grep -q "⚠" && ok "a v2 board at a merged PR's head is a ⚠" || bad "v2 merged: $st"
# the split itself: the v2 base split against the head's directory passes
git -C "$V" reset -q --hard origin/main
(cd "$S" && python3 -m ledgerboard.board split --board "$V/docs/user_attention.md" >/dev/null)
git -C "$V" add -A; git -C "$V" commit -qm split
st=$(row open HEAD); [ "${st%% *}" = pass ] && ok "a split PR (v2 base, directory head) passes" || bad "split: $st"
# TD-263's review: a direct commit to a v2 board passes (⚠ board-v2) only as a v2 writer's, never a hand edit
v2chk() { python3 - "$V" "$S" <<'EOF'
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s"], cwd=root).strip()
files = [f for f in C.git(["diff-tree", "--no-commit-id", "--name-only", "-r", "-z", sha], cwd=root).split("\0") if f]
print(C.classify_direct(root, sha, subj, files)[0])
EOF
}
git -C "$V" reset -q --hard origin/main
printf -- '- [ ] %s (n/a) — c. Context: TD-3. Due: %s.\n' "$P" "$F" >> "$V/docs/user_attention.md"; git -C "$V" commit -qam "hand edit"
[ "$(v2chk)" = fail ] && ok "direct audit: a hand edit of a v2 board fails" || bad "v2 hand: $(v2chk)"
git -C "$V" commit -q --amend -m "board_edit.py: append c (session n/a)"
[ "$(v2chk)" = board-v2 ] && ok "direct audit: a v2 writer's append to a v2 board is board-v2 (⚠)" || bad "v2 writer: $(v2chk)"
echo x > "$V/other.txt"; git -C "$V" add -A; git -C "$V" commit -qm "board_edit.py: append d (session n/a)"
[ "$(v2chk)" = fail ] && ok "direct audit: a v2 writer's subject over a non-board file fails" || bad "v2 other: $(v2chk)"
R="$R0"
# the direct audit: the writer's own edit passes; a hand slip under an edit subject fails
chk() { python3 - "$R" "$S" <<'EOF'
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s"], cwd=root).strip()
files = [f for f in C.git(["diff-tree", "--no-commit-id", "--name-only", "-r", "-z", sha], cwd=root).split("\0") if f]
print(C.classify_direct(root, sha, subj, files)[0])
EOF
}
git -C "$R" switch -q main
s1=$(lbw snooze --board "$B" --id "$I1" --to "$F" | subj); commit "$s1"
[ "$(chk)" = board-edit ] && ok "direct audit: the writer's snooze is board-edit" || bad "direct writer: $(chk)"
git -C "$R" reset -q --hard origin/main
s2=$(lbw done --board "$B" --id "$I2" --why ok | subj); commit "$s2"
[ "$(chk)" = board-edit ] && ok "direct audit: the writer's done (moved into archive/) is board-edit" || bad "direct done: $(chk)"
git -C "$R" reset -q --hard origin/main
sed -i "s/^\*\*Due:\*\* $F$/**Due:** $F\n**Decided:** $T — go/" "$B/$I1.md"; commit "$s1"
[ "$(chk)" = fail ] && ok "direct audit: a hand Decided: without by under an edit subject fails" || bad "direct slip: $(chk)"
git -C "$R" reset -q --hard origin/main
lbw snooze --board "$B" --id "$I1" --to "$F" >/dev/null; commit "ledgerboard: snooze $I1 x to $F (session n/a)"
git -C "$R" commit -q --amend -m "${s1/$I1/$I2}"
[ "$(chk)" = fail ] && ok "direct audit: an edit whose subject names another item's id fails" || bad "direct wrong id: $(chk)"
git -C "$R" reset -q --hard origin/main
s3=$(lbw add --board "$B" --today "$T" --text "a new thing" --context TD-3 --due "$F" | subj); commit "$s3"
[ "$(chk)" = board-append ] && ok "direct audit: the writer's add is board-append" || bad "direct add: $(chk)"
git -C "$R" reset -q --hard origin/main
sed -i 's/^Ledgerboard: 3$/Ledgerboard: 3\nSwept: '"$T"' (h, quick)/' "$B/README.md"; commit "stamp"
[ "$(chk)" = stamp ] && ok "direct audit: a Swept: stamp in README.md is stamp" || bad "direct stamp: $(chk)"
git -C "$R" reset -q --hard origin/main
# TD-263's review: a file under the board that no reader reads rides along with a genuine edit
lbw snooze --board "$B" --id "$I1" --to "$F" >/dev/null; mkdir -p "$B/junk"; echo anything > "$B/junk/$I1.md"; commit "$s1"
[ "$(chk)" = fail ] && ok "direct audit: a writer's edit plus a nested file no reader reads fails" || bad "direct nested: $(chk)"
st=$(row open HEAD); [ "${st%% *}" = fail ] && ok "board row: a PR adding a nested file under the board fails" || bad "row nested: $st"
git -C "$R" reset -q --hard origin/main
git -C "$R" rm -rq "$B" "$R/docs/user_attention.md"; git -C "$R" commit -qm "$s1"
[ "$(chk)" = fail ] && ok "direct audit: removing the board fails" || bad "direct removed: $(chk)"
git -C "$R" reset -q --hard origin/main

# --- 3) the tool-made board PRs (TD-083, TD-237, TD-238; once test_board_writers.sh's sections 3–6c): the review
#        row's board-edit and board-append carve-outs (row_board_edit_pr), read with the direct audit's class
mkrepo() {  # $1 = repo: a v3 board with People: Pat and one open item ($I1), pushed
  rm -rf "$1" "$1.git"; git init -q --bare -b main "$1.git"; git init -q -b main "$1"; git -C "$1" remote add origin "$1.git"
  mkdir -p "$1/docs/user_attention"; printf '# board\n\nLedgerboard: 3\n\nPeople: Pat\n' > "$1/docs/user_attention/README.md"
  (cd "$S" && python3 -m ledgerboard.board add --board "$1/docs/user_attention" --id "$I1" --today "$P" --text "rotate the key" \
    --context TD-1 --due "$F" >/dev/null)
  git -C "$1" add -A; git -C "$1" commit -qm base; git -C "$1" push -q origin main 2>/dev/null
}
apr() {  # $1 = repo, $2 = PR title (default: the commit's subject): "<class> <row status|none> <carve_out|-> <lift row|none>"
  python3 - "$1" "${2:-}" "$S" <<'EOF2'
import sys
root, title, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s", sha], cwd=root).strip()
files = sorted(set(C.git(["diff", "--name-only", "origin/main", sha], cwd=root).split()))
cls_, _ = C.classify_direct(root, sha, subj, files)
pr = {"state": "open", "head_sha": sha, "title": title or subj, "files": files, "ref": "#9",
      "created_at": "2026-01-01T00:00:00Z"}
r = C.row_board_edit_pr(pr, root)
lift = C.row_lift_pr(pr, root)
print(cls_, r["status"] if r else "none", (r or {}).get("carve_out", "-"), lift["status"] if lift else "none")
EOF2
}
w() {  # $1 = repo, then the writer's arguments: writes and commits under the writer's subject
  local r="$1"; shift
  local sj; sj=$(cd "$S" && python3 -m ledgerboard.board "$@" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["subject"])')
  git -C "$r" add -A; git -C "$r" commit -qm "$sj"
}
R="$TMP/e1"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" done --board "$U" --id "$I1" --why handled
[ "$(apr "$R")" = "board-edit pass board-edit none" ] && ok "edit PR (a done, moved into archive/): review passes, carve_out board-edit" || bad "done PR: $(apr "$R")"
git -C "$R" reset -q --soft HEAD^; echo x >> "$U/README.md"; git -C "$R" add -A; git -C "$R" commit -qm "$(git -C "$R" log -1 --format=%s ORIG_HEAD)"
[ "$(apr "$R" | cut -d' ' -f1-2)" = "fail none" ] && ok "a done beside a changed README.md fails the class and takes review" || bad "done+readme: $(apr "$R")"
R="$TMP/e2"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" snooze --board "$U" --id "$I1" --to "$F"
[ "$(apr "$R" "Snooze it" | cut -d' ' -f1-2)" = "board-edit none" ] && ok "an edit under a title that is not the edit subject: ordinary review" || bad "edit title: $(apr "$R" "Snooze it")"
R="$TMP/e3"; mkrepo "$R"; U="$R/docs/user_attention"
mkdir -p "$U/archive/${T:0:7}"; mv "$U/$I1.md" "$U/archive/${T:0:7}/"; git -C "$R" add -A; git -C "$R" commit -qm "board_edit: archive 1 closed item (session n/a)"
[ "$(apr "$R" | cut -d' ' -f1-2)" = "fail none" ] && ok "an archive subject (v2's writer, gone at v3.0) over a hand move: fail, ordinary review" || bad "archive: $(apr "$R")"
# appends
R="$TMP/a1"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --text "Put on the board: renew the cert." --due "$F" --session abcdef12
[ "$(apr "$R")" = "board-append pass board-append none" ] && ok "append PR: review passes, carve_out board-append" || bad "append PR: $(apr "$R")"
R="$TMP/a2"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --text "Back up nightly?" --answer Go --answer No --decided Go --by Pat --context TD-5
[ "$(apr "$R")" = "board-append pass board-append none" ] && ok "append PR (a decided item): review passes, carve_out board-append" || bad "decided append PR: $(apr "$R")"
R="$TMP/a3"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --kind decide --text "q?" --due "$F" --answer a --answer b \
  --detail '{"context": "c.", "question": "q?", "recommended": "x."}'
[ "$(apr "$R" | cut -d' ' -f1-2)" = "fail none" ] && ok "an append with a detail block lands by a reviewed PR (fail, ordinary review)" || bad "detail append: $(apr "$R")"
R="$TMP/a4"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --kind fyi --text "heads up."
[ "$(apr "$R" | cut -d' ' -f1-2)" = "fail none" ] && ok "an fyi append (no Due:) fails the class" || bad "fyi append: $(apr "$R")"
R="$TMP/a5"; mkrepo "$R"; U="$R/docs/user_attention"
(cd "$S" && python3 -m ledgerboard.board add --board "$U" --today "$T" --text "renew the cert." --due "$F" >/dev/null)
echo x > "$R/other.txt"; git -C "$R" add -A; git -C "$R" commit -qm "ledgerboard: append $T-00000001 renew the cert. (session n/a)"
[ "$(apr "$R" | cut -d' ' -f2)" = none ] && ok "append PR with a second file outside the board: ordinary review" || bad "two files: $(apr "$R")"
R="$TMP/a6"; mkrepo "$R"; U="$R/docs/user_attention"
(cd "$S" && python3 -m ledgerboard.board add --board "$U" --today "$T" --text "renew the cert." --due "$F" >/dev/null)
git -C "$R" rm -q "$U/$I1.md"; git -C "$R" add -A; git -C "$R" commit -qm "ledgerboard: append $T-00000001 renew the cert. (session n/a)"
[ "$(apr "$R" | cut -d' ' -f1-2)" = "fail none" ] && ok "append PR that also deletes an item: fail, ordinary review" || bad "removed item: $(apr "$R")"
R="$TMP/a7"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --text "renew the cert." --due "$F"
[ "$(apr "$R" "Add a board line by hand" | cut -d' ' -f1-2)" = "board-append none" ] && ok "an append under a title that is not the append subject: ordinary review" || bad "title: $(apr "$R" "Add a board line by hand")"
R="$TMP/a8"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --text "Go to the builds?" --answer Go --answer Hold --decided Go --by Pat --context "TD-5 decision (Pat)"
[ "$(apr "$R")" = "board-append none - none" ] && ok "a decided append whose Context names a gate: neither carve-out passes it" || bad "gate append: $(apr "$R")"
R="$TMP/a9"; mkrepo "$R"; U="$R/docs/user_attention"
w "$R" add --board "$U" --today "$T" --text "first." --due "$F"
w "$R" add --board "$U" --today "$T" --text "second." --due "$F"
[ "$(apr "$R" | cut -d' ' -f2)" = none ] && ok "append PR of two commits: ordinary review (TD-224)" || bad "two commits: $(apr "$R")"
# TD-238: a README line starting with `--` or `++` is content inside a hunk, never a file header
R="$TMP/s1"; mkrepo "$R"; U="$R/docs/user_attention"
printf -- '---\n' >> "$U/README.md"; git -C "$R" commit -qam "a rule line"; git -C "$R" push -q origin main 2>/dev/null
sed -i '/^---$/d' "$U/README.md"; printf 'Swept: %s (h, quick)\n' "$T" >> "$U/README.md"; git -C "$R" commit -qam stamp
[ "$(apr "$R" | cut -d' ' -f1)" = fail ] && ok "TD-238: a stamp that also removes a --- line is no stamp" || bad "--- removed: $(apr "$R")"
R="$TMP/s2"; mkrepo "$R"; U="$R/docs/user_attention"
printf 'Swept: %s (h, quick)\n++ stray\n' "$T" >> "$U/README.md"; git -C "$R" commit -qam stamp
[ "$(apr "$R" | cut -d' ' -f1)" = fail ] && ok "TD-238: a stamp beside an added ++ line is no stamp" || bad "++ added: $(apr "$R")"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
