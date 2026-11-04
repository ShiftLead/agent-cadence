#!/usr/bin/env bash
# TD-206 §3: the cadence check's `board` row — each item's net change across a PR, by the writers' rules
# (check_cadence.py board_change_problems / row_board), and the same rules in the direct-commit audit.
# Offline: temp git repos with a bare origin; HOME/XDG_CONFIG_HOME are temp; dates derive from the run date (TD-24).
set -u
export TZ=UTC
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
EDIT="$S/board_edit.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- 1) the rules, on board texts (board_change_problems): each case passes or fails, a failure naming its command
out=$(python3 - "$S" <<'EOF'
import sys, itertools
from datetime import date, timedelta
sys.path.insert(0, sys.argv[1])
import check_cadence as C
import ledgerboard as lb
T = date.today(); P = T - timedelta(3); F = T + timedelta(9); F2 = T + timedelta(20)
HEAD = "# board\n\nPeople: Pat\n\nSwept: %s (h, quick)\n\n## Needs the user\n\n" % T
CAN = f"- [ ] {P} (session `abcdef12` on h) — rotate the key. Context: TD-1. Due: {F}."
OLD = f"- [ ] {P} (session x on host) — an old head. Due: {F}."
DEC = (f"- [ ] decide {P} (session `aa` on h) — pick one? Context: TD-2. Due: {F}. Answers: a (default) | b.\n"
       "  - **Context:** c.\n  - **Question:** q?\n  - **Recommended:** a — x.")
FYI = f"- [ ] fyi {P} (n/a) — heads up. Context: TD-3."
UNP = f"- [ ] {P} (n/a) — undated and unpunctuated"
def board(*items, head=HEAD):
    return head + "\n".join(items) + "\n"
def judge(base, head, **kw):
    return C.board_change_problems(base, head, **kw)
def fails(r):
    return [m for s, m in r if s == "fail"]
results = []
def case(name, base, head, want_pass, needle=None, **kw):
    r = fails(judge(base, head, **kw))
    good = (not r) if want_pass else (bool(r) and (needle is None or any(needle in m for m in r)))
    results.append((good, name, r))
def ed(line, *steps):
    for a, kw in steps:
        line = lb.edit_line(line, a, today=kw.pop("today", T), **kw)
    return line
dec_head = DEC.split("\n")[0]
# replay: every order of the writers' edits on several bases reproduces
acts = [("due", {"to": F2}), ("snooze", {"to": F}), ("reply", {"reply": "ok then", "by": "Pat"}),
        ("decide", {"answer": "b", "by": "Pat"}), ("done", {"why": "handled"})]
n = bad_n = 0
for b in (CAN, OLD, dec_head, FYI, UNP):
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
results.append((C.writers_made(UNP, ed(UNP, ("decide", {"answer": "b", "by": "Pat"}), ("reply", {"reply": "x", "by": "Pat"}))),
                "replay: decide then reply on a line fmt refused (the second order)", []))
# passing cases
case("a writer snooze, reply, decide and done on one item, in one PR", board(CAN), board(ed(CAN, ("snooze", {"to": F}), ("reply", {"reply": "fine", "by": "Pat"}), ("decide", {"answer": "go", "by": "Pat"}), ("done", {"why": "did it"}))), True)
case("a hand-typed line the writer would write", board(CAN), board(CAN), True)
case("an old line fmt refused takes a writer's snooze, reply and done", board(OLD), board(ed(OLD, ("snooze", {"to": F}), ("reply", {"reply": "ok", "by": "Pat"}), ("done", {"why": "x"}))), True)
case("add --decided (no block)", board(CAN), board(lb.decided_line("decided already.", "TD-8", [], None, "Go", T.isoformat(), by="Pat").rstrip("\n"), CAN), True)
case("a moved item", board(CAN, OLD), board(OLD, CAN), True)
case("a reordered section", board(CAN, OLD, FYI), board(FYI, CAN, OLD), True)
case("two open copies sharing a key, one closed", board(CAN, CAN), board(CAN, ed(CAN, ("done", {"why": "duplicate of the other"}))), True)
case("an untouched malformed line beside an unrelated edit", board(UNP, "- [ ] garbage no date", CAN), board(UNP, "- [ ] garbage no date", ed(CAN, ("snooze", {"to": F}))), True)
case("a detail-block edit", board(DEC), board(DEC.replace("  - **Context:** c.", "  - **Context:** c, and more.")), True)
case("fmt's rewrite plus a reply", board(f"- [ ] {P} (n/a) — needs a reorder. Due: {F}. Context: TD-9."),
     board(ed(lb.canonical_item(f"- [ ] {P} (n/a) — needs a reorder. Due: {F}. Context: TD-9.\n").rstrip("\n"), ("reply", {"reply": "y", "by": "Pat"}))), True)
case("a new canonical decide with its block", board(CAN), board(*DEC.split("\n"), CAN), True)
case("a corrected item: done on the old line plus add of the new", board(CAN),
     board(CAN.replace("rotate the key", "rotate both keys"), ed(CAN, ("done", {"why": "superseded by a corrected item"}))), True)
r = judge(board(CAN).replace("People: Pat", "People: Pat, Pat"), board(ed(CAN, ("snooze", {"to": F}))).replace("People: Pat", "People: Pat, Pat"))
results.append((not fails(r) and any(s == "info" for s, _ in r), "a faulty People: line the PR does not touch is ℹ", r))
# failing cases, each naming its command
case("a new malformed line", board(CAN), board(f"- [ ] {T} (n/a) — no context. Due: {F}.", CAN), False, "board_edit.py add")
case("a same-key reshaped line (Due: moved before Context:)", board(CAN), board(CAN.replace(f"Context: TD-1. Due: {F}.", f"Due: {F}. Context: TD-1.")), False, "board_edit.py")
case("a hand close with no Closed: field", board(CAN), board(CAN.replace("- [ ]", "- [x]")), False, "board_edit.py done")
case("a hand Decided: without (by …)", board(dec_head), board(dec_head + f" Decided: b ({T})."), False, "board_edit.py decide")
case("a Decided: by someone not on People:", board(dec_head), board(ed(dec_head, ("decide", {"answer": "b", "by": "Sam"}))), False, "not on the board's People:")
case("a new open decide with no detail block", board(CAN), board(dec_head, CAN), False, "board_edit.py add --detail")
case("an indented item inside a detail block", board(CAN), board(CAN, "  - [ ] " + CAN[6:]), False, "board_edit.py add")
case("a deleted open item", board(CAN, OLD), board(OLD), False, "board_edit.py done")
case("a hand-typed Due: nonsense on an old line", board(OLD), board(OLD.replace(" Due:", " Due: nonsense. Due:")), False, "changed outside the writer's fields")
case("the same slip plus a writer snooze", board(OLD), board(ed(OLD, ("snooze", {"to": F})).replace(" Due:", " Due: nonsense. Due:", 1)), False)
case("a hand-typed second Due:", board(CAN), board(CAN + f" Due: {F2}."), False)
case("a closed line with no twin", board(CAN), board(CAN, ed(OLD, ("done", {"why": "x"}))), False, "board_edit.py done")
case("editing an item's text in place", board(CAN), board(CAN.replace("rotate the key", "rotate both keys")), False, "changed outside the writer's fields")
case("deleting one of two open copies", board(CAN, CAN), board(CAN), False, "board_edit.py done")
case("a new decide whose gate person is not on People:", board(CAN),
     board(*DEC.replace("Context: TD-2.", "Context: TD-2, decision (Sam).").split("\n"), CAN), False, "People:")
case("an untouched old Decided: without by, then changed", board(dec_head + f" Decided: b ({P})."), board(dec_head + f" Decided: a ({T})."), False, "(by <person>)")
case("a PR that touches People: and leaves a fault", board(CAN), board(CAN).replace("People: Pat", "People: Pat, Pat"), False, "People:")
r = fails(judge(board(dec_head + f" Decided: b ({P})."), board(dec_head + f" Decided: b ({P}).", CAN)))
results.append((not r, "an untouched old Decided: without by passes", r))
# archive (rule 5): the archive's gain exempts what it took; the merged net check
closed = [f"- [x] {P} (n/a) — old thing {i}. Context: TD-1. Due: {P}. Closed: {P} — done." for i in range(9)]
b0 = board(CAN, OLD, *closed)
b1 = board(ed(CAN, ("done", {"why": "x"})), OLD, *closed)
nb, na = lb.archive_closed(b1, "")
case("a threshold done that archives (squashed): net check passes", b0, nb, True, base_arch="", head_arch=na, net_archive=True)
nb2, na2 = lb.archive_closed(board(ed(CAN, ("snooze", {"to": F})), OLD, *closed).replace(ed(CAN, ("snooze", {"to": F})), ed(ed(CAN, ("snooze", {"to": F})), ("done", {"why": "y"}))), "# archive\n\nsome prose")
case("a snooze then a threshold done, into an archive ending in prose: net check passes", b0, nb2, True, base_arch="# archive\n\nsome prose", head_arch=na2, net_archive=True)
case("a hand move of one open item into the archive fails the net check", board(CAN, OLD), board(OLD), False, base_arch="", head_arch=CAN + "\n", net_archive=True)
case("a closed line moved with no Closed: fails the net check", board(CAN, "- [x] " + OLD[6:]), board(CAN), False, base_arch="", head_arch="- [x] " + OLD[6:] + "\n", net_archive=True)
case("a hand move of a lone closed item below the threshold fails", board(CAN, closed[0]), board(CAN), False, base_arch="", head_arch=closed[0] + "\n", net_archive=True)
b8 = board(CAN, CAN, OLD, *closed[:8])
hand = ed(CAN, ("done", {"why": "x"}))
case("a hand close from eight closed plus an open twin, then a hand move, fails", b8, board(OLD), False,
     base_arch="", head_arch="\n".join([hand, CAN, *closed[:8]]) + "\n", net_archive=True)
case("ten copies of one deleted item's closed form fail the net check", board(CAN, OLD), board(OLD), False,
     base_arch="", head_arch="\n".join([ed(CAN, ("done", {"why": "k"}))] * 10) + "\n", net_archive=True)
moved = [c.replace("— done.", "— TOTALLY DIFFERENT.") for c in closed] + [ed(CAN, ("done", {"why": "x"}))]
case("a hand move at the threshold that changes the moved lines' text fails the net check", b0, board(OLD), False,
     base_arch="", head_arch="\n".join(moved) + "\n", net_archive=True)
case("an impossible Closed: date fails, not a crash", board(CAN), board(ed(CAN, ("done", {"why": "x"})).replace(f"Closed: {T}", "Closed: 2026-13-45")), False)
case("an impossible reply date fails, not a crash", board(CAN), board(CAN + " — Pat, 2026-13-45: hi."), False)
case("an archive whose earlier lines changed fails", board(CAN), board(CAN), False, base_arch="a\nb\n", head_arch="a\nc\n")
for good, name, r in results:
    print(("ok" if good else "NO") + "\t" + name + ("" if good else "\t" + repr(r)[:300]))
EOF
)
while IFS=$'\t' read -r st name rest; do
  [ "$st" = ok ] && ok "$name" || bad "$name ${rest:-}"
done <<< "$out"

# --- 2) the row on a PR (row_board): open, multi-commit, judged on its merge-base diff; a hand archive commit fails;
#        the direct audit applies the same rules
R="$TMP/r"; git init -q --bare -b main "$R.git"; git init -q -b main "$R"; git -C "$R" remote add origin "$R.git"; mkdir -p "$R/docs"
P=$(date -d "3 days ago" +%F); F=$(date -d "9 days" +%F); T=$(date +%F)
{
  printf '# board\n\nPeople: Pat\n\n## Needs the user\n\n'
  printf -- '- [ ] %s (session `abcdef12` on h) — rotate the key. Context: TD-1. Due: %s.\n' "$P" "$F"
  printf -- '- [ ] %s (n/a) — plain item. Context: TD-2. Due: %s.\n' "$P" "$F"
  for i in $(seq 1 9); do printf -- '- [x] %s (n/a) — old thing %s. Context: TD-1. Due: %s. Closed: %s — done.\n' "$P" "$i" "$P" "$P"; done
} > "$R/docs/user_attention.md"
echo x > "$R/other.txt"; git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" push -q origin main 2>/dev/null
git -C "$R" switch -q -c topic
B="$R/docs/user_attention.md"
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
"$EDIT" snooze --board "$B" --line 7 --expect "$P (session" --to "$F" >/dev/null 2>&1
"$EDIT" done --board "$B" --line 8 --expect "$P (n/a) — plain" --why handled >/dev/null 2>&1
st=$(row open HEAD)
[ "$(git -C "$R" log -1 --format=%s | grep -c 'archived 10')" = 1 ] && [ "${st%% *}" = pass ] \
  && ok "an open PR: a snooze commit then a threshold done that archives passes (merge-base diff)" || bad "open snooze+done: $st"
git -C "$R" switch -q main; git -C "$R" merge -q --squash topic; git -C "$R" commit -qm "squash (#9)"
st=$(row merged HEAD); [ "${st%% *}" = pass ] && ok "the same PR after its squash merge passes the net check" || bad "merged: $st"
git -C "$R" reset -q --hard origin/main; git -C "$R" switch -q topic; git -C "$R" reset -q --hard origin/main
# a hand-appended archive commit on an open PR fails the per-commit class check
python3 - "$B" "$R/docs/user_attention_archive.md" <<'EOF'
import sys
b, a = sys.argv[1:]
lines = open(b).read().splitlines(keepends=True)
moved = [ln for ln in lines if ln.startswith("- [x]")]
open(b, "w").write("".join(ln for ln in lines if ln not in moved)); open(a, "w").write("".join(moved))
EOF
git -C "$R" add -A; git -C "$R" commit -qm "move the closed items by hand"
st=$(row open HEAD); [ "${st%% *}" = fail ] && echo "$st" | grep -q "not the writer.s archive" \
  && ok "an open PR: a hand-made archive commit fails the per-commit check" || bad "hand archive: $st"
git -C "$R" reset -q --hard origin/main
# na on a PR that does not touch the board; the row is a hard fail on a hand slip
echo y >> "$R/other.txt"; git -C "$R" commit -qam other
st=$(row open HEAD); [ "${st%% *}" = na ] && ok "the row is na on a PR that does not change the board" || bad "na: $st"
sed -i "s/Context: TD-2. Due: $F\./Due: $F. Context: TD-2./" "$B"; git -C "$R" commit -qam "hand reshape"
st=$(row open HEAD); [ "${st%% *}" = fail ] && echo "$st" | grep -q "board_edit.py" && ok "a hand reshape fails the row (fail, not ℹ), naming the command" || bad "reshape: $st"
# the direct audit: a direct commit with a hand slip under an edit subject fails; the writer's own passes
git -C "$R" reset -q --hard origin/main
"$EDIT" snooze --board "$B" --line 7 --expect "$P (session" --to "$F" >/dev/null 2>&1
chk() { python3 - "$R" "$S" <<'EOF'
import sys
root, s = sys.argv[1:]
sys.path.insert(0, s)
import check_cadence as C
sha = C.git(["rev-parse", "HEAD"], cwd=root).strip()
subj = C.git(["log", "-1", "--format=%s"], cwd=root).strip()
print(C.classify_direct(root, sha, subj, ["docs/user_attention.md"])[0])
EOF
}
[ "$(chk)" = board-edit ] && ok "direct audit: the writer's snooze is board-edit" || bad "direct writer: $(chk)"
subj=$(git -C "$R" log -1 --format=%s); git -C "$R" reset -q --hard HEAD^
sed -i "s/^- \[ \] $P (session \`abcdef12\` on h) — rotate the key. Context: TD-1. Due: $F\./- [ ] $P (session \`abcdef12\` on h) — rotate the key. Context: TD-1. Due: $F. Decided: go ($T)./" "$B"
git -C "$R" commit -qam "$subj"
[ "$(chk)" = fail ] && ok "direct audit: a hand Decided: without by under an edit subject fails" || bad "direct slip: $(chk)"

echo; echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
