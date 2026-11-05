#!/usr/bin/env bash
# TD-103: the forge adapter. scripts/forge.py is the one place a script runs the forge's CLI;
# the `forge` setting picks the backend (auto / github / gitlab / none); an unsupported forge
# reads "PRs not checked" from every caller, never an empty answer; a `host/owner/repo` line in
# remote_repos.txt / no_auto_delete.txt equals its `owner/repo` form on github.com; the squash's
# parent count comes from git when the clone holds the merge commit.
#
# Offline: origins are only named, never fetched; `gh` is a PATH shim that logs every call.
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

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list") echo '[]'; exit 0 ;;
  "pr view") cat "$GH_PRVIEW"; exit 0 ;;
  "auth status") exit 0 ;;
esac
echo "gh-shim: unhandled: $*" >&2; exit 64
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log"
R="$TMP/repo"; git init -q -b main "$R"; git -C "$R" commit -q --allow-empty -m base
seturl() { git -C "$R" remote remove origin 2>/dev/null; [ -n "$1" ] && git -C "$R" remote add origin "$1"; : > "$GH_LOG"; }
classify() { (cd "$R" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import forge; print(*forge.origin_forge("."))' "$S"); }

# 1. the forge key decides, origin's host only under auto
seturl https://ghe.example.com/Org/Thing.git
[ "$(classify)" = "other ghe.example.com" ] && ok "1a auto: an unknown host is other, never GitHub" || bad "1a: $(classify)"
[ "$(CADENCE_FORGE=github classify)" = "github org/thing" ] && ok "1b forge=github: a GitHub under another host reads as GitHub" || bad "1b: $(CADENCE_FORGE=github classify)"
mkdir -p "$R/docs"; printf 'forge = "github"\n' > "$R/docs/cadence.toml"
[ "$(classify)" = "github org/thing" ] && ok "1c forge=github read from docs/cadence.toml" || bad "1c: $(classify)"
rm "$R/docs/cadence.toml"
seturl https://github.com/o/r.git
[ "$(CADENCE_FORGE=gitlab classify)" = "gitlab github.com/o/r" ] && ok "1d forge=gitlab: GitLab, whatever the host (TD-104)" || bad "1d: $(CADENCE_FORGE=gitlab classify)"
[ "$(CADENCE_FORGE=none classify)" = "other none" ] && ok "1e forge=none: other (TD-105)" || bad "1e: $(CADENCE_FORGE=none classify)"
[ "$(CADENCE_FORGE=bitbucket classify)" = "other !bitbucket" ] && ok "1f an unknown forge value is other, naming it" || bad "1f: $(CADENCE_FORGE=bitbucket classify)"
out=$(cd "$R" && CADENCE_FORGE=bitbucket python3 "$S/check_cadence.py" --pr 1 2>&1)
grep -q "the forge setting 'bitbucket' is not one of auto, github, gitlab, none" <<< "$out" && ! grep -q "origin is" <<< "$out" && ok "1h a bad setting is named as the setting, not blamed on origin" || bad "1h: $out"
[ "$(classify)" = "github o/r" ] && ok "1g auto on github.com: github, owner/repo" || bad "1g: $(classify)"

# 2. an unsupported forge says "PRs not checked" from every caller, and asks gh nothing
seturl https://gitea.example/o/r.git
out=$(cd "$R" && python3 "$S/check_cadence.py" --pr 1 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "CANNOT CHECK: PRs not checked: origin is gitea.example" <<< "$out" && ok "2a check_cadence.py: CANNOT CHECK, exit 2" || bad "2a rc=$rc: $out"
out=$(cd "$R" && python3 "$S/forge.py" check 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "PRs not checked" <<< "$out" && ok "2c forge.py check: the line, exit 2" || bad "2c rc=$rc: $out"
out=$(bash "$S/adopt_repo_settings.sh" --check gitea.example/o/r 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "cannot verify: PRs not checked: origin is gitea.example" <<< "$out" && ok "2d adopt_repo_settings.sh host/owner/repo off GitHub: cannot verify, exit 2" || bad "2d rc=$rc: $out"
nudge=$(python3 - "$S" "$R" <<'PY'
import sys, pathlib, time
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
root = pathlib.Path(sys.argv[2])
print(N.open_pr_lines(root, time.monotonic() + 30)[0])
print(N.settings_line(root, {"t": 0.0, "hit": False}))
PY
)
grep -q "^⚠ PRs not checked: origin is gitea.example" <<< "$nudge" && grep -q "^⚙ repo settings not checked: origin is gitea.example" <<< "$nudge" \
  && ok "2e the nudge's open-PR and settings lines: not checked" || bad "2e: $nudge"
[ ! -s "$GH_LOG" ] && ok "2f no gh call for an unsupported forge" || bad "2f gh was asked: $(cat "$GH_LOG")"
seturl https://github.com/o/r.git
out=$(cd "$R" && CADENCE_FORGE=none python3 "$S/check_cadence.py" --pr 1 2>&1)
grep -q 'forge = "none"' <<< "$out" && grep -q TD-105 <<< "$out" && ok "2g forge=none names itself and TD-105" || bad "2g: $out"

# 3. a host/owner/repo line equals its owner/repo form
py3() { python3 - "$S" "$@"; }
[ "$(py3 <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import forge as F
print(F.repo_key("github.com/O/R") == F.repo_key("o/r") == ("github.com", "o/r"), F.repo_key("gitlab.example.com/a/b"), F.repo_key("nope"))
PY
)" = "True ('gitlab.example.com', 'a/b') None" ] && ok "3a repo_key: github.com/O/R == o/r; another host kept; junk None" || bad "3a"
printf 'Alpha/One\ngithub.com/beta/two  # stacked\n' > "$AGENT_CADENCE_REG_DIR/no_auto_delete.txt"
got=$(py3 <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print(sorted(N._no_auto_delete()))
PY
)
[ "$got" = "['alpha/one', 'beta/two']" ] && ok "3b no_auto_delete.txt: both forms name the same repo" || bad "3b: $got"
printf 'someowner\ngithub.com/c/d\ne/f\ngitlab.com/g/h\ngitlab.com/grp\ngitlab.com\nexample.org/x/y\n' > "$AGENT_CADENCE_REG_DIR/remote_repos.txt"
got=$(py3 <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print(N._read_remote_filter())
PY
)
[ "$got" = "({'github.com': {'discover': False, 'owners': ['someowner'], 'repos': ['c/d', 'e/f']}, 'gitlab.com': {'discover': True, 'owners': ['grp'], 'repos': ['g/h']}}, ['example.org/x/y'])" ] && ok "3c remote_repos.txt: github.com/c/d reads as c/d; a GitLab host's group, project and bare host (TD-110); another host set aside" || bad "3c: $got"

# 4. the squash's parents from git when the clone holds the merge commit; the forge otherwise
git -C "$R" commit -q --allow-empty -m "squash (#1)"
SQ=$(git -C "$R" rev-parse HEAD)
got=$(py3 "$R" "$SQ" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import check_cadence as C
class Forge:
    def commit_parents(self, sha): return f"forge:{sha}"
C.FORGE = Forge(); C._FETCHED.add(sys.argv[2])
print(C.merge_parents(sys.argv[3], sys.argv[2]), C.merge_parents("abc1234", sys.argv[2]))
PY
)
[ "$got" = "1 forge:abc1234" ] && ok "4 merge_parents: git for a commit in the clone, the forge for one that is not" || bad "4: $got"

# 4b. a shallow clone's boundary commit lists no parents: never read as "0 parents, not a squash"
SH="$TMP/shallow"; git clone -q --depth 1 "file://$R" "$SH" 2>/dev/null
got=$(py3 "$SH" "$(git -C "$SH" rev-parse HEAD)" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import check_cadence as C
class Forge:
    def commit_parents(self, sha): return "forge"
C.FORGE = Forge(); C._FETCHED.add(sys.argv[2])
print(C.merge_parents(sys.argv[3], sys.argv[2]))
PY
)
[ "$got" = forge ] && ok "4b merge_parents: a shallow boundary (0 parents from git) asks the forge" || bad "4b: $got"

# 4c. a remote_repos.txt naming only other hosts is still a filter: no discovery of the user's GitHub
printf 'example.org/g/h\n' > "$AGENT_CADENCE_REG_DIR/remote_repos.txt"; : > "$GH_LOG"
out=$(py3 <<'PY'
import sys, datetime; sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
print("\n".join(N.remote_tier([], datetime.date.today())))
PY
)
grep -q "not covered (first: example.org/g/h" <<< "$out" && ! grep -q "user" "$GH_LOG" && ok "4c only other-host lines: reported, and no user/org discovery" || bad "4c: $out / $(cat "$GH_LOG")"

# 5. Done when (TD-103): no script outside forge.py runs gh
hits=$(cd "$DC" && grep -nE '\["gh"|which\("gh"\)|^[^#]*\bgh (pr|api|auth|repo) |^[^#]*command -v gh' files/scripts/*.py files/scripts/*.sh | grep -v '^files/scripts/forge.py:')
[ -z "$hits" ] && ok "5 no gh call outside forge.py (files/scripts)" || bad "5 gh outside forge.py: $hits"

# 6. TD-114: `forge.py nothing-left N` — exit 0 when every file the PR changed is already the
# same on origin/<base> (landed by another PR), 1 when one differs, 2 when git here cannot tell
N="$TMP/nl"; git init -q --bare -b main "$N.git"; git clone -q "$N.git" "$N" 2>/dev/null
git -C "$N" commit -q --allow-empty -m base; git -C "$N" push -q -u origin main 2>/dev/null
git -C "$N" remote set-url origin https://github.com/o/r.git; git -C "$N" remote set-url --push origin "$N.git"
git -C "$N" checkout -q -b landed; echo x > "$N/f"; git -C "$N" add f; git -C "$N" commit -qm landed
git -C "$N" checkout -q -b live main; echo y > "$N/g"; git -C "$N" add g; git -C "$N" commit -qm live
git -C "$N" checkout -q main; echo x > "$N/f"; git -C "$N" add f; git -C "$N" commit -qm "stacked PR, squashed"
git -C "$N" push -q origin main 2>/dev/null; git -C "$N" update-ref refs/remotes/origin/main main
export GH_PRVIEW="$TMP/prview.json"
nl() { printf '{"number":%s,"state":"%s","baseRefName":"main","headRefOid":"%s"}' "$1" "${3:-OPEN}" "$2" > "$GH_PRVIEW"; (cd "$N" && python3 "$S/forge.py" nothing-left "$1" 2>&1); }
out=$(nl 3 "$(git -C "$N" rev-parse landed)"); rc=$?
[ $rc = 0 ] && [ "$out" = "#3 nothing left to merge — close it as superseded" ] && ok "6a landed by another PR: exit 0, superseded" || bad "6a rc=$rc: $out"
out=$(nl 4 "$(git -C "$N" rev-parse live)"); rc=$?
[ $rc = 1 ] && grep -q "#4 has changes left to merge" <<< "$out" && ok "6b a change main lacks: exit 1" || bad "6b rc=$rc: $out"
out=$(nl 3 "$(git -C "$N" rev-parse landed)" MERGED); rc=$?
[ $rc = 1 ] && [ "$out" = "#3 is merged, not open — nothing to close" ] && ok "6d a PR that is not open: exit 1, never superseded" || bad "6d rc=$rc: $out"
out=$(nl 5 0123456789abcdef0123456789abcdef01234567); rc=$?
[ $rc = 2 ] && grep -q "cannot tell" <<< "$out" && ok "6c a head not fetched here: exit 2, cannot tell" || bad "6c rc=$rc: $out"

# 7. the PR record carries created_at (TD-218: a lift PR's lower bound), asked of gh in PR_FIELDS
: > "$GH_LOG"
printf '{"number":7,"state":"OPEN","createdAt":"2026-01-02T03:04:05Z","mergedAt":null}' > "$GH_PRVIEW"
out=$(cd "$N" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import forge; r = forge.backend(".").pr(7); print(r["created_at"], r["merged_at"])' "$S" 2>&1)
[ "$out" = "2026-01-02T03:04:05Z None" ] && grep -q -- '--json .*createdAt' "$GH_LOG" \
  && ok "7a pr() asks gh for createdAt and maps it to created_at" || bad "7a: $out $(cat "$GH_LOG")"

# 8. TD-224: the record carries how many commits the PR had, asked of gh in PR_FIELDS; none asked, None
: > "$GH_LOG"
printf '{"number":8,"state":"MERGED","commits":[{"oid":"a"},{"oid":"b"}]}' > "$GH_PRVIEW"
out=$(cd "$N" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import forge; b = forge.backend("."); r = b.pr(8); print(r["commits"], b.pr_commits(r), b.pr_commits(b.record({"number": 8})))' "$S" 2>&1)
[ "$out" = "2 2 None" ] && grep -q -- '--json .*commits' "$GH_LOG" \
  && ok "8a pr() asks gh for commits and counts them; a record without them gives None" || bad "8a: $out $(cat "$GH_LOG")"

# 9. TD-232 (TD-177's design 2–3): the squash message composed for a cadence merge, and the model and
# merger read as the commit hook reads them. Pure: no forge, no merge.
SQ="$TMP/sq"; mkdir -p "$SQ"
py() { (cd "$SQ" && python3 -I - "$S" "$@"); }
out=$(py <<'P'
import sys, subprocess; sys.path.insert(0, sys.argv[1]); import forge as F
c1 = {"message": "Fix a thing\n\nBody one.\n\nCo-Authored-By: A Bot <bot@x>\nAgent-Model: claude-code/opus\n", "author_name": "Pat", "author_email": "pat@x"}
c2 = {"message": "Second\n\nbody text\n---------\n\nco-authored-by: A BOT <BOT@X>\nAgent-Model: codex/gpt\nAgent-Model: claude-code/opus\nMerged-by: forged\nReview: forged (SHIP)\n", "author_name": "Pat", "author_email": "PAT@x"}
s, b = F.squash_message("Title", "#7", [c1, c2], ["pr 7", "expect abc", "Review: sonnet (BLOCK)", "Review: sonnet (FIXED)", "Precheck: abc", "Merged-by: gate"], "g1 (claude-code/opus)")
msg = s + "\n\n" + b
parsed = subprocess.run(["git", "interpret-trailers", "--parse"], input=msg, capture_output=True, text=True).stdout
want = ("Co-Authored-By: A Bot <bot@x>\nCo-Authored-By: Pat <pat@x>\nAgent-Model: claude-code/opus\nAgent-Model: codex/gpt\n"
        "Review: sonnet (BLOCK)\nReview: sonnet (FIXED)\nPrecheck: abc\nMerged-by: g1 (claude-code/opus)\n")
assert s == "Title (#7)", s
assert parsed == want, parsed
assert b.endswith(want), b
assert b.startswith("* Fix a thing\n\nBody one.\n\n* Second\n\nbody text\n---------\n\n"), b
assert "forged" not in b and "gate" not in b, b
s, b = F.squash_message("T", "!3", [c1], [], "p")
assert s == "T (!3)" and b == "Body one.\n\nCo-Authored-By: A Bot <bot@x>\nCo-Authored-By: Pat <pat@x>\nAgent-Model: claude-code/opus\nMerged-by: p\n", b
# git's own rule: a mixed last paragraph is a trailer block only with a trailer git knows and a quarter trailers
mixed = {"message": "S\n\ntext one\nSigned-off-by: X <x@x>\nCo-Authored-By: M <m@x>\n", "author_name": "", "author_email": ""}
_, b = F.squash_message("T", "#1", [mixed], [], "p")
assert b.startswith("text one\nSigned-off-by: X <x@x>\n\nCo-Authored-By: M <m@x>\nMerged-by: p"), b
prose = {"message": "S\n\nwe paired with\nCo-Authored-By: M <m@x>\non this one\n", "author_name": "", "author_email": ""}
_, b = F.squash_message("T", "#1", [prose], [], "p")
assert b == "we paired with\nCo-Authored-By: M <m@x>\non this one\n\nMerged-by: p\n", b
folded = {"message": "S\n\nCo-Authored-By: Long\n  Name <l@x>\nAgent-Model: a/b\n", "author_name": "", "author_email": ""}
_, b = F.squash_message("T", "#1", [folded], [], "p")
assert b == "Co-Authored-By: Long Name <l@x>\nAgent-Model: a/b\nMerged-by: p\n", b
_, b = F.squash_message("T", "#1", [c1], [], "p", override="3 ci — the precheck host is down")
assert "\nMerge-override: 3 ci — the precheck host is down\nMerged-by: p\n" in b, b
try:
    F.squash_message("T", "#1", [], [], "p"); print("no refusal")
except F.SquashRefused:
    pass
# review of #142: what the composed paragraph takes is one line each, and only whole Review:/Precheck: lines
_, b = F.squash_message("T", "#1", [c1], ["Review", "Review:", "review: x (SHIP)", "Reviewed: x", "Precheck: abc"], "p", override="x\nMerged-by: evil")
assert b.endswith("Agent-Model: claude-code/opus\nPrecheck: abc\nMerge-override: x Merged-by: evil\nMerged-by: p\n"), b
odd = {"message": "S\n\nCo-Authored-By:\nAgent-Model:  \nSigned-off-by: Q <q@x>\n", "author_name": "N", "author_email": "n@x\nMerged-by: evil"}
_, b = F.squash_message("T", "#1", [odd], [], "p")
assert b == "Signed-off-by: Q <q@x>\n\nCo-Authored-By: N <n@x Merged-by: evil>\nMerged-by: p\n", b
crlf = {"message": "S\r\n\r\nbody\r\n---\r\nmore\r\n\r\nCo-Authored-By: C <c@x>\r\nAGENT-MODEL: a/b\r\n", "author_name": "", "author_email": ""}
_, b = F.squash_message("T", "#1", [crlf], [], "p")
assert b == "body\n---\nmore\n\nCo-Authored-By: C <c@x>\nAgent-Model: a/b\nMerged-by: p\n", b
tab = {"message": "\n\nS\n\nb\n\nCo-Authored-By : Long\n\tName <l@x>\n\n# a comment\n", "author_name": "", "author_email": ""}
subj, b, lifted = F.split_commit(tab["message"])
assert subj == "S" and lifted == [("co-authored-by", "Long Name <l@x>")] and b == "b\n\n# a comment", (subj, b, lifted)
print("ok")
P
)
[ "$out" = ok ] && ok "9a squash_message: subject, the one- and many-commit shapes, one trailer paragraph last (git parses every key), co-authors deduplicated with case ignored plus commit authors, two models, gate lines only Review/Precheck, a commit's own Merged-by/Review dropped, ---- stays text, git's mixed-paragraph rule, a folded line joined, Merge-override, no commits refused" || bad "9a: $out"

out=$(py "$SQ" <<'P'
import sys, os; sys.path.insert(0, sys.argv[1]); import forge as F
d = sys.argv[2]
def f(name, data):
    p = os.path.join(d, name); open(p, "wb").write(data); return p
cases = [
    ({"AGENT_MODEL": "claude-code/opus"}, "claude-code/opus"),
    ({"AGENT_MODEL_FILE": f("m1", b"codex/gpt-5\nignored\n"), "AGENT_MODEL": "x/y"}, "codex/gpt-5"),
    ({"AGENT_MODEL_FILE": f("m2", b"\r\n"), "AGENT_MODEL": "x/y"}, None),          # a CR is not empty: stripped, then fails
    ({"AGENT_MODEL_FILE": f("m3", b"\nnext\n"), "AGENT_MODEL": "x/y"}, "x/y"),     # an empty first line falls through
    ({"AGENT_MODEL_FILE": f("m4", b""), "AGENT_MODEL": "x/y"}, "x/y"),             # an empty file too
    ({"AGENT_MODEL_FILE": f("m5", b"  a/b c\r\n")}, "a/b c"),                       # CRLF and edge blanks stripped
    ({"AGENT_MODEL_FILE": f("m6", b"a/b")}, "a/b"),                                 # an unterminated line counts
    ({"AGENT_MODEL_FILE": f("m7", b"ab\0cd\n")}, "abcd"),                           # NUL dropped, as read -r drops it
    ({"AGENT_MODEL_FILE": f("m8", b"\va/b\f\n")}, "a/b"),                           # \v and \f are C-locale blanks
    ({"AGENT_MODEL": "a  b"}, None),                                                # two spaces
    ({"AGENT_MODEL": "a\tb"}, None),                                                # a tab inside
    ({"AGENT_MODEL": " a/b"}, None),                                           # a non-ASCII space at an edge
    ({"AGENT_MODEL": "modèle"}, None),                                              # non-ASCII
    ({"AGENT_MODEL_FILE": f("m9", b"a\xffb\n")}, None),                             # invalid UTF-8
    ({"AGENT_MODEL": "m" * 120}, "m" * 120),
    ({"AGENT_MODEL": "m" * 121}, None),
    ({"AGENT_MODEL_FILE": f("m10", b"bad  value\n"), "AGENT_MODEL": "x/y"}, None),  # a failing value never falls back
    ({"AGENT_MODEL_FILE": d, "AGENT_MODEL": "x/y"}, "x/y"),                         # a directory is not a file
]
for env, want in cases:
    got = F.agent_model(env)
    assert got == want, (env, got, want)
assert F.merged_by({"AGENT_NAME": "g1", "AGENT_MODEL": "a/b"}, "Pat") == "g1 (a/b)"
assert F.merged_by({"AGENT_NAME": "g1"}, "Pat") == "g1"
assert F.merged_by({"AGENT_MODEL": "a/b"}, "Pat  Smith") == "Pat Smith"
assert F.merged_by({"AGENT_NAME": "", "AGENT_MODEL": "a/b"}, "Pat") == "Pat"
for env, user in (({"AGENT_NAME": "g 1"}, "Pat"), ({"AGENT_NAME": "g1\n"}, "Pat"), ({}, ""), ({}, None)):
    try:
        F.merged_by(env, user); print("no refusal", env, user); break
    except F.SquashRefused:
        pass
else:
    print("ok")
P
)
[ "$out" = ok ] && ok "9b agent_model and merged_by read as the hook reads (file first, empty falls through, C-locale strip, NUL dropped, ASCII words single-spaced, 120 bytes, no fallback after a fail); a bad AGENT_NAME or no name refuses" || bad "9b: $out"

# 10. TD-232: `forge.py squash-message` against a gh shim for the reads — it writes subject, body and
# sha, calls no merge, and refuses what it cannot compose whole.
B2="$TMP/bin2"; mkdir -p "$B2"; QF="$TMP/q"; mkdir -p "$QF"
cat > "$B2/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$*" in
  "pr view"*) cat "$QF/pr.json" ;;
  "api --paginate repos/{owner}/{repo}/pulls/"*"/commits") cat "$QF/commits.json" ;;
  "api repos/{owner}/{repo}/pulls/"*) cat "$QF/count.json" ;;
  *) echo "gh-shim2: unhandled: $*" >&2; exit 64 ;;
esac
SHIM
chmod +x "$B2/gh"
Q="$TMP/qrepo"; git init -q -b main "$Q"; git -C "$Q" remote add origin git@github.com:o/r.git
git -C "$Q" config user.name "Pat Person"
echo '{"number":9,"title":"Add\na thing","state":"OPEN","headRefOid":"fff9999","commits":[{},{}]}' > "$QF/pr.json"
# gh --paginate writes the pages back to back
printf '%s%s' '[{"commit":{"message":"one\n\nCo-Authored-By: g1 <g1@x>\nAgent-Model: a/b\n","author":{"name":"Pat","email":"pat@x"}}}]' \
  '[{"commit":{"message":"two\n\nbody two\n","author":{"name":"Pat","email":"pat@x"}}}]' > "$QF/commits.json"
echo '{"commits":2}' > "$QF/count.json"
printf 'pr 9\nexpect abc1234\nReview: sonnet (SHIP)\nPrecheck: abc1234\n' > "$QF/gate"
sq() { (cd "$Q" && PATH="$B2:$PATH" QF="$QF" python3 "$S/forge.py" squash-message "$@" 2>&1); }
: > "$GH_LOG"; out=$(env -u AGENT_MODEL_FILE AGENT_NAME=g1 AGENT_MODEL=a/b bash -c "$(declare -f sq); S='$S' Q='$Q' QF='$QF' B2='$B2' sq 9 --gate '$QF/gate' --out '$QF/o1'"); rc=$?
want=$(printf '* one\n\n* two\n\nbody two\n\nCo-Authored-By: g1 <g1@x>\nCo-Authored-By: Pat <pat@x>\nAgent-Model: a/b\nReview: sonnet (SHIP)\nPrecheck: abc1234\nMerged-by: g1 (a/b)')
[ $rc -eq 0 ] && [ "$(cat "$QF/o1/subject")" = "Add a thing (#9)" ] && [ "$(cat "$QF/o1/body")" = "$want" ] && [ "$(cat "$QF/o1/sha")" = abc1234 ] \
  && ! grep -qE "^pr merge|/merge( |$)" "$GH_LOG" \
  && ok "10a squash-message writes subject, body (pages joined, trailers last, Merged-by with the model) and sha, and calls no merge" || bad "10a rc=$rc $out | $(cat "$QF/o1/body" 2>/dev/null) | $(cat "$GH_LOG")"
out=$(env -u AGENT_NAME -u AGENT_MODEL -u AGENT_MODEL_FILE bash -c "$(declare -f sq); S='$S' Q='$Q' QF='$QF' B2='$B2' sq 9 --gate '$QF/gate' --out '$QF/o2'"); rc=$?
[ $rc -eq 0 ] && [ "$(tail -1 "$QF/o2/body")" = "Merged-by: Pat Person" ] && ok "10b no AGENT_NAME: Merged-by is git's user.name" || bad "10b rc=$rc $out"
out=$(env AGENT_NAME=g1 AGENT_MODEL=x/y AGENT_MODEL_FILE="$QF/model" bash -c "printf 'a/file\n' > '$QF/model'; $(declare -f sq); S='$S' Q='$Q' QF='$QF' B2='$B2' sq 9 --gate '$QF/gate' --out '$QF/o3'"); rc=$?
[ $rc -eq 0 ] && [ "$(tail -1 "$QF/o3/body")" = "Merged-by: g1 (a/file)" ] && ok "10c AGENT_MODEL_FILE takes precedence over AGENT_MODEL" || bad "10c rc=$rc $out"
refuse() {  # <label> <expect-in-stderr> <args...>
  local label=$1 want=$2; shift 2; rm -rf "$QF/or"
  out=$(env AGENT_NAME="${AN-g1}" bash -c "$(declare -f sq); S='$S' Q='$Q' QF='$QF' B2='$B2' sq $*"); rc=$?
  [ $rc -eq 2 ] && echo "$out" | grep -q -- "$want" && [ ! -e "$QF/or/body" ] && [ ! -e "$QF/or/subject" ] && [ ! -e "$QF/or/sha" ] && ok "$label" || bad "$label: rc=$rc $out"
}
refuse "10d no gate file refuses" "no gate file" 9 --gate "$QF/none" --out "$QF/or"
: > "$QF/empty"; refuse "10e an empty gate file (the gate could not read the PR) refuses" "is empty" 9 --gate "$QF/empty" --out "$QF/or"
printf 'pr 8\nexpect abc1234\n' > "$QF/g8"; refuse "10f another PR's gate file refuses" "not PR 9's" 9 --gate "$QF/g8" --out "$QF/or"
printf 'pr 9\nReview: x (SHIP)\n' > "$QF/gnx"; refuse "10g a gate file with no expect refuses" "names no head" 9 --gate "$QF/gnx" --out "$QF/or"
printf 'pr 9\nexpect abc1234\nunverified 3 ci\n' > "$QF/gu"; refuse "10h an unverified gate file refuses without --unverified" "did not pass" 9 --gate "$QF/gu" --out "$QF/or"
printf 'pr 90\nexpect abc1234\n' > "$QF/g90"; refuse "10f2 PR 90's gate file is not PR 9's" "not PR 9's" 9 --gate "$QF/g90" --out "$QF/or"
printf 'pr 9\nexpect abc1234\nunverified\n' > "$QF/gbare"; refuse "10h2 a bare unverified mark refuses, never read as a pass" "is not \`unverified" 9 --gate "$QF/gbare" --out "$QF/or"
mkdir -p "$QF/or"; for x in subject body sha; do echo stale > "$QF/or/$x"; done
: > "$GH_LOG"; refuse "10h3 an unverified file refuses before any forge read, and leaves no earlier run's files" "did not pass" 9 --gate "$QF/gu" --out "$QF/or"
[ ! -s "$GH_LOG" ] && ok "10h4 no gh call before the gate file is judged" || bad "10h4: $(cat "$GH_LOG")"
refuse "10i --unverified with a gate file that passed refuses" "nothing to override" 9 --gate "$QF/gate" --out "$QF/or" --unverified "'because'"
AN="g 1" refuse "10j a bad AGENT_NAME refuses, never the person's name" "is not \[A-Za-z0-9._-\]" 9 --gate "$QF/gate" --out "$QF/or"
echo '{"commits":3}' > "$QF/count.json"; refuse "10k a list shorter than the PR's count refuses" "lists 2 commit(s) but counts 3" 9 --gate "$QF/gate" --out "$QF/or"
echo '{"commits":1}' > "$QF/count.json"; refuse "10k2 a list longer than the PR's count refuses" "lists 2 commit(s) but counts 1" 9 --gate "$QF/gate" --out "$QF/or"
echo '{}' > "$QF/count.json"; refuse "10k3 no count refuses" "but counts None" 9 --gate "$QF/gate" --out "$QF/or"
echo '{"commits":0}' > "$QF/count.json"; echo '[]' > "$QF/commits.json"; refuse "10l zero commits refuse" "no commits" 9 --gate "$QF/gate" --out "$QF/or"
printf '%s%s' '[{"commit":{"message":"one\n","author":{"name":"Pat","email":"pat@x"}}}]' '[{"commit":{"message":"two\n","author":{"name":"Pat","email":"pat@x"}}}]' > "$QF/commits.json"
echo '{"commits":2}' > "$QF/count.json"
printf 'pr 9\nexpect abc1234\nReview: x (SHIP)\nunverified 3 ci\n' > "$QF/gu"
out=$(env -u AGENT_MODEL -u AGENT_MODEL_FILE AGENT_NAME=g1 bash -c "$(declare -f sq); S='$S' Q='$Q' QF='$QF' B2='$B2' sq 9 --gate '$QF/gu' --out '$QF/o4' --unverified \"\$(printf 'the host\nis down')\""); rc=$?
[ $rc -eq 0 ] && [ "$(cat "$QF/o4/body")" = "$(printf '* one\n\n* two\n\nCo-Authored-By: Pat <pat@x>\nMerge-override: 3 ci — the host is down\nMerged-by: g1')" ] \
  && ok "10m --unverified composes an unverified gate file, its why on one Merge-override line" || bad "10m rc=$rc $out $(cat "$QF/o4/body" 2>/dev/null)"
long=$(python3 -c 'print("é" * 150)')
out=$(env AGENT_NAME=g1 bash -c "$(declare -f sq); S='$S' Q='$Q' QF='$QF' B2='$B2' sq 9 --gate '$QF/gu' --out '$QF/o5' --unverified '$long'"); rc=$?
[ $rc -eq 0 ] && [ "$(grep '^Merge-override:' "$QF/o5/body")" = "Merge-override: 3 ci — $(python3 -c 'print("é" * 100)')" ] \
  && ok "10m2 the why is cut at 200 bytes, never inside a character" || bad "10m2 rc=$rc $out $(grep Merge "$QF/o5/body")"
out=$(cd "$Q" && python3 -I - "$S" <<'P'
import sys; sys.path.insert(0, sys.argv[1]); import forge as F
g = F.GitLab(slug="gitlab.com/o/r")
g._get = lambda ep, paginate=False: [{"message": "new", "author_name": "B", "author_email": "b@x"}, {"message": "old", "author_name": "A", "author_email": "a@x"}] if paginate and "/commits" in ep else None
print([c["message"] for c in g.commit_list(4)])
def boom(ep, paginate=False): raise F.ForgeUnreadable("page 2: HTTP 502")
g._get = boom
try:
    g.commit_list(4); print("no raise")
except F.ForgeUnreadable:
    print("raised")
P
)
[ "$out" = "$(printf "['old', 'new']\nraised")" ] && ok "10n GitLab's commit list is read oldest first, and a page it cannot read raises" || bad "10n: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
