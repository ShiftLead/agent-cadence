#!/usr/bin/env bash
# sync.sh — the payload's file lists, and the migration of a synced repo to a pin (TD-129).
#
#   ./sync.sh --pin /path/to/target-repo       # the migration: pin the repo to this clone's HEAD and
#                                              # retire its synced copies — opt-in, per repo
#   ./sync.sh --pin --siblings-moved /path/to/home  # a constellation's home, once its siblings' hooks
#                                              # no longer call its scripts/ (TD-147)
#
# sync.sh no longer copies into anything (TD-129's closing slice, decided 2026-10-28): every repo
# runs agent-cadence from its pin (cadence.md §9.19), so the copy mode, `--verify`, the
# docs/cadence-sync.lock it wrote and its roster registration are gone, and so is sync-all.sh.
# A new repo is adopted by `agent-cadence -C <clone> adopt <repo>`. What stays is the three lists
# below, which `adopt` reads (launcher/words.py _sh_array) and README's file-class table mirrors
# (tests/test_readme_sync_table.sh):
#   SYNC  — the files a synced repo carried as copies; `--pin` removes each one still matching its
#           lock hash, and `adopt` refuses a repo that still carries one.
#   SEED  — skeletons `adopt` creates only if missing; never overwritten (they hold the repo's own
#           living content: ledger, board, memory index, settings).
#   RETIRED — once SYNC, dropped from the payload before the pin (TD-057).
set -euo pipefail

PIN=0
MOVED=0
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --pin) PIN=1 ;;
        --siblings-moved) MOVED=1 ;;
        --verify) echo "ERROR: sync.sh --verify is retired (TD-129): a pinned repo carries no copies to check — \`agent-cadence bump\` lists what is newer than its pin" >&2; exit 1 ;;
        -*) echo "ERROR: unknown option '$arg' — usage: sync.sh --pin [--siblings-moved] /path/to/target-repo" >&2; exit 1 ;;
        *)  if [ -n "$TARGET" ]; then
                echo "ERROR: more than one target given ('$TARGET', '$arg')" >&2; exit 1
            fi
            TARGET="$arg" ;;
    esac
done
if [ "$PIN" = 0 ]; then
    [ "$MOVED" = 1 ] && { echo "ERROR: --siblings-moved goes with --pin (a constellation's home, TD-147)" >&2; exit 1; }
    echo "ERROR: sync.sh no longer copies into a repo (TD-129): adopt a new repo with" >&2
    echo "  agent-cadence -C <this clone> adopt <repo>" >&2
    echo "and move a synced one to a pin with ./sync.sh --pin <repo> (cadence.md §9.19)" >&2
    exit 1
fi
[ -n "$TARGET" ] || { echo "usage: sync.sh --pin [--siblings-moved] /path/to/target-repo" >&2; exit 1; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The payload's lists: one quoted path a line (launcher/words.py _sh_array reads them so, and
# tests/test_adopt.sh holds that reading to bash's own). A path is in exactly one of the three.
SYNC_FILES=(
    "docs/cadence.md"
    "docs/cadence-rationale.md"
    "docs/cadence-incidents.md"
    "docs/cadence-changes.md"
    "docs/adr-template.md"
    "docs/procedures/stranded-work.md"
    "docs/procedures/attention.md"
    "docs/procedures/cadence.md"
    "docs/procedures/memory-harvest.md"
    ".claude/skills/stranded-work/SKILL.md"
    ".claude/skills/attention/SKILL.md"
    ".claude/skills/cadence/SKILL.md"
    ".claude/skills/memory-harvest/SKILL.md"
    ".agents/skills/stranded-work/SKILL.md"
    ".agents/skills/attention/SKILL.md"
    ".agents/skills/cadence/SKILL.md"
    ".agents/skills/memory-harvest/SKILL.md"
    "scripts/check_claude_memory.sh"
    "scripts/check_anchor.py"
    "scripts/agent_sessions.py"
    "scripts/forge.py"
    "scripts/nudge_user_attention.py"
    "scripts/board_edit.py"
    "scripts/ledger.py"
    "scripts/ledger_next_id.py"
    "scripts/ledgerboard.py"
    "scripts/list_sessions.py"
    "scripts/generate_session_index.sh"
    "scripts/generate_workspace.sh"
    "scripts/open_worktree.sh"
    "scripts/hydrate_worktree.sh"
    "scripts/reap_worktrees.sh"
    "scripts/adopt_repo_settings.sh"
    "scripts/check_cadence.py"
    "scripts/precheck.py"
    "scripts/check_base.py"
    "scripts/check_tmp.py"
    "scripts/cadence_changes.py"
    "scripts/cadence_config.py"
    "scripts/cadence_layer.py"
    "scripts/memory_harvest.py"
    "scripts/cadence_hooks.sh"
    "scripts/install_git_hooks.sh"
    "scripts/git-hooks/pre-push"
    "scripts/git-hooks/post-merge"
    "scripts/git-hooks/prepare-commit-msg"
)
# RETIRED (TD-057): once SYNC, dropped from the payload. Empty: nothing was retired before the
# pin, and `--pin` removes every synced copy by its lock hash whichever list it is in.
RETIRED_FILES=(
)
SEED_FILES=(
    "docs/user_attention.md"
    "docs/technical_debt.md"
    "docs/technical_debt_archive.md"
    "docs/claude-memory/MEMORY.md"
    ".claude/settings.json"
    "docs/cadence.toml"
    "AGENTS.md"
    ".gemini/settings.json"
    ".gitattributes"
)

# --- --pin: the migration (TD-129, docs/plans/2026-10-25-pinned-not-synced.md Decision 11) -------
# A synced repo's last sync: the [agent-cadence] pin at this clone's HEAD, the synced copies and the lock
# retired by the RETIRED rule (a copy still matching its lock hash is removed, an edited one kept with
# a WARN), the seeds and the skill pointers (SEED once pinned, Decision 5), the hook shims, the roster.
# Commits nothing. It is `agent-cadence adopt`'s code (launcher/words.py w_adopt, --migrate), never a
# copy of it; a person moves each repo, one at a time.
if [ "$MOVED" = 1 ]; then
    exec python3 "$SRC/launcher/words.py" adopt --migrate --siblings-moved "$TARGET"
fi
exec python3 "$SRC/launcher/words.py" adopt --migrate "$TARGET"
