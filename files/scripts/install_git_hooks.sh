#!/usr/bin/env bash
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/install_git_hooks.sh
# Edit it there: a repo runs it from its pinned dev-cadence (`dev-cadence path`), and a fix reaches it by a bump PR.
#
# install_git_hooks.sh [REPO] — put this repo's git hooks in force in EVERY worktree of
# the clone, whatever branch each is on (TD-055, cadence.md §4 "Give the rule teeth").
#
# Why not core.hooksPath: a relative core.hooksPath resolves against each worktree's own
# working tree, so a worktree on a branch without scripts/git-hooks/ (pre-adoption, an old
# --detach) pushed HEAD:main with no guard at all, and a branch that edits a hook ran its
# edit. An absolute path breaks silently where a clone is seen at two paths (container and
# host, cadence.md appendix). So instead:
#
#   - one small SHIM per shipped hook goes into the clone's shared hooks directory,
#     $(git rev-parse --git-common-dir)/hooks/ — git runs hooks from there in every
#     linked worktree when core.hooksPath is unset;
#   - the shim finds the MAIN checkout at run time (the common dir's parent) and execs
#     that checkout's copy of the hook, so every worktree runs the same, current hook
#     and no path is baked in;
#   - a clone-local core.hooksPath naming our own hooks directory is then unset, since it
#     would override the shims.
#
# Two modes, read at run time from the MAIN checkout (TD-129, docs/plans/2026-10-25-pinned-not-synced.md
# Decisions 4-6): where its docs/cadence.toml pins dev-cadence — a table header written exactly
# `[dev-cadence]` (a grep, not a TOML parser: another TOML form of the pin is no pin here) — the shim runs
# `dev-cadence hook <name>` — the pinned tree's hook — and never a copy; a launcher exit 2 (it could
# not resolve the pin) fails open with a warning, any other exit is the hook's own and is kept, and
# no launcher on PATH prints the install line and fails open. With no pin, the shim runs the
# checkout's copy as before. The pre-push shim first holds the MAIN-BRANCH GUARD INLINE, in every
# mode, so a missing or broken launcher or copy can never open main: its default_branch() is taken
# verbatim from the shipped pre-push at install time (tests/test_install_git_hooks.sh runs it).
#
# Never clobbers: an existing hook in the shared directory that is not our shim is kept
# (and our relative core.hooksPath is then left set too, so nothing that ran before stops
# running); a core.hooksPath pointing anywhere else is someone's own hooks setup and is
# left alone. Each such case is a WARN naming the fix. Idempotent; run by `dev-cadence adopt`
# (and `sync.sh --pin`), and by hand on a clone that predates it. Exit 0 installed or already fine (WARNs
# may print), 2 cannot install here (not a git clone, a bare repo, a separate git dir,
# no hooks beside this script). CADENCE_HOOKS_SKIP (space-separated hook names; adopt sets
# it from the repo's opt-outs in docs/cadence.toml, TD-072/TD-096) names hooks that get no shim: ours is removed.
set -u

REPO="${1:-.}"
MARK="dev-cadence hook shim (TD-055)"

common="$(cd "$REPO" 2>/dev/null && d="$(git rev-parse --git-common-dir 2>/dev/null)" && cd "$d" && pwd -P)" || {
    echo "  WARN  $REPO is not a git clone — hooks not installed" >&2; exit 2; }
if [ "${common##*/}" != ".git" ]; then
    # Bare repo, submodule (.git/modules/x) or --separate-git-dir: there is no main
    # checkout at the common dir's parent for a shim to run the hooks from.
    echo "  WARN  $common is not a checkout's .git directory — hooks not installed; set core.hooksPath by hand" >&2
    exit 2
fi
root="${common%/*}"

# Which hooks, and where they live relative to the checkout: beside this script
# (scripts/git-hooks in a consumer, files/scripts/git-hooks in dev-cadence itself).
# Follow a symlinked invocation to the real script first: from the link's directory the
# hooks glob below matches nothing, and the run would install nothing and exit 0.
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
here="$(cd "$(dirname "$self")" && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || top=""
rel="scripts/git-hooks"
if [ -n "$top" ]; then
    case "$here/" in
        "$top"/*) rel="${here#"$top"}"; rel="${rel#/}"; rel="${rel:+$rel/}git-hooks" ;;
    esac
fi

# CADENCE_HOOKS_REL names the hooks' directory in the main checkout instead (relative, no ..): set by
# `dev-cadence adopt` and `sync.sh --pin`, which run this from a dev-cadence clone (files/scripts/) for
# a consumer, whose copies — until its pin merges — are in scripts/git-hooks (TD-129).
case "${CADENCE_HOOKS_REL:-}" in
    '') ;;
    /*|..|../*|*/..|*/../*) echo "  WARN  CADENCE_HOOKS_REL='$CADENCE_HOOKS_REL' is not a relative path inside the checkout — ignored" >&2 ;;
    *) rel="${CADENCE_HOOKS_REL%/}" ;;
esac

# no backtick or $ in it: it is written into a double-quoted echo
INSTALL='install the dev-cadence launcher once per machine: clone dev-cadence at its latest tag, then run: install -m 755 launcher/dev_cadence.py ~/.local/bin/dev-cadence'
guard_fn="$(sed -n '/^default_branch() {$/,/^}$/p' "$here/git-hooks/pre-push" 2>/dev/null)"

conflict=0
found=0
mkdir -p "$common/hooks"
for src in "$here"/git-hooks/*; do
    { [ -f "$src" ] && [ -x "$src" ]; } || continue
    name="${src##*/}"
    case "$name" in *.sample) continue ;; esac
    found=$((found+1))
    dst="$common/hooks/$name"
    case " ${CADENCE_HOOKS_SKIP:-} " in
        *" $name "*)
            if [ -f "$dst" ] && grep -qF "$MARK" "$dst" 2>/dev/null; then
                rm -f "$dst" && echo "  hook  $name: shim removed — opted out by the repo (docs/cadence.toml)"
            else
                echo "  hook  $name: opted out by the repo (docs/cadence.toml) — no shim"
            fi
            continue ;;
    esac
    if [ -e "$dst" ] && ! grep -qF "$MARK" "$dst" 2>/dev/null; then
        echo "  WARN  $dst is a hook of this clone's own — kept, so the cadence $name hook does not run from there."
        echo "        Fix: fold $root/$rel/$name into it by hand, or move it aside and rerun $0"
        conflict=1
        continue
    fi
    guard="" feed=""
    if [ "$name" = pre-push ]; then
        if [ -z "$guard_fn" ]; then   # never no guard: main alone, said
            echo "  WARN  $here/git-hooks/pre-push has no default_branch() — the shim's inline guard holds main only" >&2
            guard_fn='default_branch() { echo main; }'
        fi
        # the refs git sends on stdin are read once, by the guard, and handed on to the hook
        guard="input=\$(cat)
$guard_fn
DEFAULT=\"\$(default_branch .)\"
while read -r _local_ref _local_sha remote_ref _remote_sha; do
    if { [ \"\$remote_ref\" = \"refs/heads/main\" ] || [ \"\$remote_ref\" = \"refs/heads/\$DEFAULT\" ]; } \\
        && [ \"\${ALLOW_MAIN_PUSH:-0}\" != \"1\" ]; then
        echo \"pre-push: BLOCKED — direct push to \${remote_ref#refs/heads/} (the default branch; docs/cadence.md §4: use a PR).\" >&2
        echo \"pre-push: deliberate override: ALLOW_MAIN_PUSH=1 git push ...\" >&2
        exit 1
    fi
done <<< \"\$input\"
"
        feed=' <<< "$input"'
    fi
    shim="#!/usr/bin/env bash
# $MARK — written by ${rel%/git-hooks}/install_git_hooks.sh; rerun that, never edit.
# Runs this hook from the dev-cadence the MAIN checkout pins, else the MAIN checkout's copy,
# whatever branch this worktree is on.
d=\$(git rev-parse --git-common-dir 2>/dev/null) && d=\$(cd \"\$d\" && pwd -P) || d=
${guard}if [ -n \"\$d\" ] && grep -qsE '^[[:space:]]*\\[dev-cadence\\][[:space:]]*(#.*)?\$' \"\${d%/*}/docs/cadence.toml\"; then
    if command -v dev-cadence >/dev/null 2>&1; then
        dev-cadence hook \"\${0##*/}\" \"\$@\"$feed
        rc=\$?
        [ \"\$rc\" -ne 2 ] && exit \"\$rc\"
        echo \"git hook shim: the dev-cadence launcher could not run this repo's pin (above) — the \${0##*/} hook did not run (TD-129)\" >&2
    else
        echo \"git hook shim: this repo pins dev-cadence (docs/cadence.toml) but no dev-cadence launcher is on PATH — the \${0##*/} hook did not run; $INSTALL\" >&2
    fi
    exit 0
fi
hook=\"\${d%/*}/$rel/\${0##*/}\"
[ -n \"\$d\" ] && [ -x \"\$hook\" ] && exec \"\$hook\" \"\$@\"$feed
echo \"git hook shim: \$hook is missing or not executable — the \${0##*/} hook did not run (TD-055)\" >&2
exit 0
"
    if [ "$(cat "$dst" 2>/dev/null)" != "${shim%$'\n'}" ]; then
        printf '%s' "$shim" > "$dst" && chmod +x "$dst"
        echo "  hook  $name: shim in $common/hooks -> $root/$rel/$name"
    else
        echo "  hook  $name: shim already in place"
    fi
done

# A shim of ours whose hook neither this copy nor the MAIN checkout (what the shim runs)
# ships — opted out in docs/cadence.toml (TD-072, TD-096), or dropped from the payload —
# only prints "missing" on every run: remove it. While the main checkout still has the hook
# (a sync into a worktree, not yet merged) the shim stays; the next sync there removes it.
for dst in "$common"/hooks/*; do
    { [ -f "$dst" ] && grep -qF "$MARK" "$dst" 2>/dev/null; } || continue
    name="${dst##*/}"
    { [ -x "$here/git-hooks/$name" ] || [ -x "$root/$rel/$name" ]; } && continue
    rm -f "$dst" && echo "  hook  $name: shim removed — no $rel/$name to run (opted out or retired)"
done

if [ "$found" -eq 0 ]; then
    # Never a silent success: no hooks found means nothing was installed.
    echo "  WARN  no hooks found in $here/git-hooks — nothing installed; the pre-push main guard is OFF" >&2
    exit 2
fi

local_hp="$(git -C "$root" config --local core.hooksPath 2>/dev/null || true)"
if [ -n "$local_hp" ]; then
    case "$local_hp" in
        "$rel"|"$rel/"|"$root/$rel"|"$root/$rel/")
            if [ "$conflict" -eq 0 ]; then
                git -C "$root" config --local --unset core.hooksPath
                echo "  conf  core.hooksPath ($local_hp) unset — the shims in $common/hooks run the hooks in every worktree"
            else
                echo "  WARN  core.hooksPath ($local_hp) left set: a hook of this clone's own is in $common/hooks (above), and unsetting would switch it on in place of the cadence hook."
            fi ;;
        *)
            echo "  WARN  core.hooksPath is '$local_hp' — this clone's own hooks setup, left alone, so the shims in $common/hooks do not run."
            echo "        Do NOT just unset it: git honors ONE hooks directory. Fix: copy $root/$rel/pre-push (and the other hooks there) into it" ;;
    esac
fi
eff="$(git -C "$root" config core.hooksPath 2>/dev/null || true)"
if [ -n "$eff" ] && [ -z "$(git -C "$root" config --local core.hooksPath 2>/dev/null || true)" ]; then
    echo "  WARN  core.hooksPath is set outside this clone ('$eff', global or system config) — git uses that directory, not the shims."
fi
exit 0
