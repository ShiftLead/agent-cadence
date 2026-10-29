#!/usr/bin/env bash
# TD-25: lint gate on the shipped scripts. Rules live in ruff.toml (opt-in
# DTZ/PLW1510/I001 on top of ruff's defaults — the defaults alone find none
# of the silent-failure classes this repo distributes guards against).
# Skips loudly-but-green when ruff is absent so `bash tests/*.sh` stays
# runnable on machines without it — a skip is visible, never silent.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Isolation (TD-046): never read the real ~/.gitconfig or ~/.config — a global
# init.templateDir or core.hooksPath would otherwise leak into every fixture.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
cd "$ROOT"
if ! command -v ruff >/dev/null 2>&1; then
  echo "SKIP: ruff not installed — lint gate did not run (TD-25). Install ruff to enable."
  echo
  echo "0 passed, 0 failed (1 skipped)"
  # Green on a laptop without ruff; red wherever CI is set, where a skipped gate is a
  # gate that did not run (TD-046).
  [ -n "${CI:-}" ] && exit 1
  exit 0
fi
if ruff check files/scripts/ launcher/; then
  echo
  echo "1 passed, 0 failed"
else
  echo
  echo "0 passed, 1 failed"
  exit 1
fi
