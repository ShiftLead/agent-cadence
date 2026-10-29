#!/usr/bin/env bash
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/generate_session_index.sh
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
# Materialize the Claude Code session index (docs/cadence.md §1) to a file.
#
# Wraps list_sessions.py for cron use: adds a generated-at header, renders the
# index as markdown (--format md: overview table + per-session details), and
# writes atomically (tmp + mv) so a reader never sees a half-written file. The
# output file should be gitignored — it is derived, host-local state, not repo
# content.
#
# Usage: generate_session_index.sh [REPO] [OUT] [EXTRA_REPO...]
#   REPO        repo whose sessions to index  (default: $CADENCE_REPO_ROOT, else this script's repo root)
#   OUT         output file                   (default: REPO/docs/session_index.md)
#   EXTRA_REPO  further repos to fold into the same combined index (their rows are
#               distinguished by the Where directory column) — when several repos
#               run Claude sessions on one machine
# Env:  PYTHON — interpreter to use (default: python3; stdlib only, any 3.x works)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo: the argument, else the one the launcher names (TD-129: run from a cached tree,
# the script's own parent is no repo), else the checkout this copy sits in.
REPO="${1:-${CADENCE_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
OUT="${2:-$REPO/docs/session_index.md}"
PY="${PYTHON:-python3}"
TMP="$OUT.tmp"
trap 'rm -f "$TMP"' EXIT

REPO_ARGS=(--repo "$REPO")
REPO_LIST="$REPO"
for r in "${@:3}"; do
    REPO_ARGS+=(--repo "$r")
    REPO_LIST="$REPO_LIST, $r"
done

{
    echo "# Claude Code session index — $REPO_LIST"
    echo
    echo "Generated $(date -u '+%Y-%m-%d %H:%M UTC') by \`generate_session_index.sh\` (cron) — do not edit; regenerate with \`scripts/list_sessions.py\`."
    echo
    "$PY" "$SCRIPT_DIR/list_sessions.py" "${REPO_ARGS[@]}" --days 30 --format md
} > "$TMP"
mv "$TMP" "$OUT"
