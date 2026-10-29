#!/usr/bin/env bash
# generate_workspace.sh — the all-topics overview and the per-topic view.
#
# The per-topic mode is the one with a contract worth pinning: open_worktree.sh
# CAPTURES ITS STDOUT and opens whatever it prints. So "prints exactly the path,
# and prints nothing when there is nothing to show" is not cosmetic — a stray
# echo becomes a path the caller hands to `code`, and a missing one silently
# demotes every constellation window back to a single root.
#
# Fully offline: real git repos in a tmpdir, no origins needed (this script only
# reads `git worktree list` and the filesystem).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/generate_workspace.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Isolation (TD-046): never read the real ~/.gitconfig or ~/.config — a global
# init.templateDir or core.hooksPath would otherwise leak into every fixture.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# $1 = name. A checkout at $TMP/$1 with the script installed, on main.
mkrepo() {
    local r="$TMP/$1"
    mkdir -p "$r/scripts" "$r/docs"
    git init -q -b main "$r"
    cp "$SCRIPT" "$r/scripts/"
    (
        cd "$r" || exit 1
        git config user.email t@t; git config user.name t
        echo base > base.txt
        printf '.claude/worktrees/\n*.code-workspace\n' > .gitignore
        git add -A; git commit -qm base
    )
}

# Adds two sibling repos inside $1 and the nested-repos.txt that names them.
# One `worktree`, one `link`, one `skip` — the three modes hydrate knows.
mkconstellation() {
    local r="$TMP/$1"
    printf '# path mode\ndocs-repo  worktree\napp-repo   link\nabsent     skip\n' \
        > "$r/docs/nested-repos.txt"
    local s
    for s in docs-repo app-repo; do
        mkdir -p "$r/$s"
        git init -q -b main "$r/$s"
        (cd "$r/$s" && git config user.email t@t && git config user.name t \
            && echo x > f.txt && git add -A && git commit -qm base)
    done
}

# $1 = repo, $2 = topic, $3.. = siblings to materialise. A name given as
# "link:NAME" is created as a SYMLINK to the main checkout's copy, which is what
# hydrate_worktree.sh does for a `link` sibling -- and the shape the real
# constellation runs on, so nested()'s isdir() has to see through it.
mkwt() {
    local r="$TMP/$1" t="$2"
    git -C "$r" worktree add -q -b "$t" "$r/.claude/worktrees/$t"
    # Hydration is a different script; fake just its output that we care about.
    local s
    for s in "${@:3}"; do
        if [ "${s#link:}" != "$s" ]; then
            ln -s "$r/${s#link:}" "$r/.claude/worktrees/$t/${s#link:}"
        else
            mkdir -p "$r/.claude/worktrees/$t/$s"
            git init -q -b main "$r/.claude/worktrees/$t/$s"
        fi
    done
}

wt()  { echo "$TMP/$1/.claude/worktrees/$2"; }
run() { (cd "$TMP/$1" && ./scripts/generate_workspace.sh "${@:2}"); }

# roots of a workspace file, one "name<TAB>path" per line
roots() {
    python3 -c '
import json,sys
for f in json.load(open(sys.argv[1]))["folders"]:
    print("%s\t%s" % (f["name"], f["path"]))
' "$1"
}

# --- 1. overview mode is unchanged by the new flag ----------------------------
mkrepo r1
mkwt r1 topic-a
out=$(run r1 2>&1); rc=$?
WS="$TMP/r1/r1.code-workspace"
if [ $rc -eq 0 ] && [ -f "$WS" ] && [ "$(roots "$WS" | wc -l)" -eq 2 ]; then
    ok "overview: checkout + one worktree = two roots"
else
    bad "overview mode broke (rc=$rc, roots=$( [ -f "$WS" ] && roots "$WS" | wc -l )): $out"
fi

# --- 2. --topic on a repo with NO siblings prints nothing and writes nothing --
# This is the single-repo-consumer path. The caller must fall back to opening
# the plain folder, and it decides that by getting empty stdout.
out=$(run r1 --topic "$(wt r1 topic-a)" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ] && [ ! -e "$TMP/r1/topic-a.code-workspace" ]; then
    ok "--topic with no siblings: exit 0, empty stdout, no file (single-repo no-op)"
else
    bad "--topic without siblings should be silent (rc=$rc, stdout='$out', file exists=$([ -e "$TMP/r1/topic-a.code-workspace" ] && echo yes || echo no))"
fi

# --- 3. --topic in a constellation writes the topic's roots -------------------
mkrepo r2
mkconstellation r2
mkwt r2 topic-b docs-repo link:app-repo
out=$(run r2 --topic "$(wt r2 topic-b)" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$TMP/r2/topic-b.code-workspace" ] && [ -f "$out" ]; then
    ok "--topic prints exactly the workspace path on stdout"
else
    bad "--topic stdout was '$out' (rc=$rc), want $TMP/r2/topic-b.code-workspace"
fi

if [ -f "$TMP/r2/topic-b.code-workspace" ]; then
    got=$(roots "$TMP/r2/topic-b.code-workspace" | cut -f2 | sort)
    want=$(printf '%s\n%s\n%s\n' \
        "$(wt r2 topic-b)" "$(wt r2 topic-b)/app-repo" "$(wt r2 topic-b)/docs-repo" | sort)
    if [ "$got" = "$want" ]; then
        ok "--topic roots are the worktree plus its present siblings, and nothing else"
    else
        bad "--topic roots wrong. got:
$got
want:
$want"
    fi

    # app-repo is reached through a symlink here, as `link` mode produces. A
    # root that resolved the link would point at the MAIN checkout's copy, and
    # the window would silently edit another topic-s tree.
    if roots "$TMP/r2/topic-b.code-workspace" | grep -qF "$(wt r2 topic-b)/app-repo"; then
        ok "--topic lists a link-mode symlink sibling at its path inside the worktree"
    else
        bad "--topic dropped the symlinked link-mode sibling"
    fi

    # `skip` siblings are deliberately absent from the tree; a root pointing at
    # nothing is a phantom folder in the explorer, which is worse than omitting.
    if ! roots "$TMP/r2/topic-b.code-workspace" | grep -q absent; then
        ok "--topic omits a skip sibling"
    else
        bad "--topic listed the skip sibling as a root"
    fi

    # The siblings are also subdirectories of the topic root. Without these
    # patterns every one shows twice in the explorer.
    ex=$(python3 -c '
import json,sys
print(" ".join(sorted(json.load(open(sys.argv[1]))["settings"]["files.exclude"])))
' "$TMP/r2/topic-b.code-workspace")
    if [ "$ex" = "app-repo docs-repo" ]; then
        ok "--topic hides the sibling subdirectory copies inside each root"
    else
        bad "--topic files.exclude was '$ex', want 'app-repo docs-repo'"
    fi
fi

# --- 4. the overview file is not clobbered by a topic run ---------------------
# Both land at the clone root, so an off-by-one in the name would have the two
# modes overwriting each other every time open_worktree.sh runs.
run r2 >/dev/null 2>&1
before=$(cat "$TMP/r2/r2.code-workspace")
run r2 --topic "$(wt r2 topic-b)" >/dev/null 2>&1
if [ "$before" = "$(cat "$TMP/r2/r2.code-workspace")" ]; then
    ok "a --topic run leaves the overview file untouched"
else
    bad "--topic overwrote the overview file"
fi

# --- 5. a topic named after the repo does not collide with the overview -------
mkwt r2 r2 docs-repo
out=$(run r2 --topic "$(wt r2 r2)" 2>/dev/null)
if [ "$out" = "$TMP/r2/r2+topic.code-workspace" ] && [ -f "$out" ] \
   && [ "$(roots "$TMP/r2/r2.code-workspace" | wc -l)" -gt 1 ]; then
    ok "topic named after the repo gets a disambiguated file, overview survives"
else
    bad "repo-named topic collided with the overview (stdout='$out')"
fi

# --- 5b. the disambiguation cannot itself be produced by another topic --------
# Regression: the first version suffixed `.topic`, and `.` IS in the topic
# charset -- so a topic literally named "<repo>.topic" produced the same
# filename as the disambiguated "<repo>", each silently overwriting the other,
# and reap deleting one would take the other-s file with it. `+` is outside the
# charset, so no ordinary topic name can ever collide with it.
mkwt r2 r2.topic docs-repo
a=$(run r2 --topic "$(wt r2 r2)" 2>/dev/null)
b=$(run r2 --topic "$(wt r2 r2.topic)" 2>/dev/null)
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then
    ok "a topic named <repo>.topic does not collide with the disambiguated <repo>"
else
    bad "collision: <repo> -> '$a', <repo>.topic -> '$b'"
fi

# --- 6. bad arguments are refused, not half-honoured --------------------------
out=$(run r2 --topic 2>&1); rc=$?
if [ $rc -eq 2 ]; then
    ok "--topic with no path exits 2"
else
    bad "--topic with no path exited $rc, want 2: $out"
fi

out=$(run r2 --topic "$TMP/r2/nope" 2>&1); rc=$?
if [ $rc -eq 2 ]; then
    ok "--topic with a nonexistent path exits 2"
else
    bad "--topic on a missing directory exited $rc, want 2: $out"
fi

out=$(run r2 --topic "$(wt r2 topic-b)" extra 2>&1); rc=$?
if [ $rc -eq 2 ]; then
    ok "a trailing argument after --topic <path> exits 2"
else
    bad "trailing argument was ignored (rc=$rc): $out"
fi

out=$(run r2 --wat 2>&1); rc=$?
if [ $rc -eq 2 ]; then
    ok "an unknown flag exits 2 rather than being ignored"
else
    bad "unknown flag exited $rc, want 2: $out"
fi

# --- 7. runs from inside a worktree, output still at the clone root -----------
# generate_workspace.sh resolves via git-common-dir precisely so this holds; the
# per-topic file must obey the same rule or reap cannot find it to delete.
out=$( (cd "$(wt r2 topic-b)" && "$TMP/r2/scripts/generate_workspace.sh" --topic "$(wt r2 topic-b)") 2>/dev/null )
if [ "$out" = "$TMP/r2/topic-b.code-workspace" ]; then
    ok "--topic run from inside a worktree still writes to the clone root"
else
    bad "--topic from inside a worktree wrote '$out'"
fi

# --- TD-031. the overview prunes a topic file whose worktree was removed by hand, and
#     nothing else: not a live topic's file, not a person's own workspace file
mkrepo r31
mkconstellation r31
mkwt r31 gone docs-repo; mkwt r31 alive docs-repo; mkwt r31 r31 docs-repo   # r31: the +topic name
for t in gone alive r31; do run r31 --topic "$(wt r31 $t)" >/dev/null 2>&1; done
printf '{"folders": [{"path": "/somewhere/else"}]}\n' > "$TMP/r31/mine.code-workspace"
printf '{"folders": [{"path": "%s"}]}\n' "$TMP/r31/src" > "$TMP/r31/gone2.code-workspace"   # a person's, named like a topic
printf 'not json\n' > "$TMP/r31/broken.code-workspace"
for t in gone r31; do rm -rf "$(wt r31 $t)"; done; git -C "$TMP/r31" worktree prune
out=$(run r31 2>&1)
[ ! -e "$TMP/r31/gone.code-workspace" ] && [ ! -e "$TMP/r31/r31+topic.code-workspace" ] && grep -q "pruned $TMP/r31/gone.code-workspace" <<< "$out" \
    && ok "overview prunes topic files (incl. the +topic spelling) whose worktree is gone" || bad "prune: $(ls "$TMP/r31"/*.code-workspace) / $out"
[ -e "$TMP/r31/alive.code-workspace" ] && [ -e "$TMP/r31/mine.code-workspace" ] && [ -e "$TMP/r31/gone2.code-workspace" ] && [ -e "$TMP/r31/broken.code-workspace" ] \
    && ok "a live topic's file, a person's own files and an unreadable one are never touched" || bad "over-pruned: $(ls "$TMP/r31"/*.code-workspace)"
[ -e "$TMP/r31/r31.code-workspace" ] && ok "the overview itself stays" || bad "overview gone"
# a worktree still REGISTERED but unreachable (an unmounted volume) keeps its file
mkwt r31 away docs-repo; run r31 --topic "$(wt r31 away)" >/dev/null 2>&1
mv "$(wt r31 away)" "$TMP/away.aside"
run r31 >/dev/null 2>&1
[ -e "$TMP/r31/away.code-workspace" ] && ok "a registered worktree that is only unreachable keeps its file" || bad "pruned an unreachable registered worktree's file"
mv "$TMP/away.aside" "$(wt r31 away)"
# a relative first root resolves against the FILE (as the editor does), not the caller's cwd
printf '{"folders": [{"path": ".claude/worktrees/rel"}]}\n' > "$TMP/r31/rel.code-workspace"
out=$(cd "$(wt r31 alive)" && "$TMP/r31/scripts/generate_workspace.sh" 2>&1)
[ ! -e "$TMP/r31/rel.code-workspace" ] && ok "a relative root, run from inside another worktree: resolved against the file, pruned" || bad "relative root: $out"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
