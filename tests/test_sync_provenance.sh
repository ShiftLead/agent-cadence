#!/usr/bin/env bash
# Provenance headers: every SYNC file says, in the file, that it is synced.
#
# TD-8 gave the lock content hashes and `sync.sh --verify` a way to DETECT a
# consumer-local edit. Nothing PREVENTED one: a consumer's scripts/ holds
# upstream-owned files and locally-owned files side by side, distinguishable
# only by opening docs/cadence-sync.lock — which nobody does mid-edit. These
# tests pin the in-band marker that closes that gap, and the placement rules
# that keep it from breaking the things which parse each file's head.
#
# The SYNC list is parsed from sync.sh rather than restated here, so a file
# added to the canonical set without a header fails this suite instead of
# shipping unmarked. Since TD-129 nothing copies these files into a consumer
# (the end-to-end case left with the copy mode): a repo runs them from its pinned
# tree, and the header's second line says so (TD-169) — an edit goes upstream and
# arrives by a bump PR. These cases hold the canonical tree.
#
# Isolation: HOME and XDG_CONFIG_HOME point into the tmpdir.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

MARKER="SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/"
# A file this repo vendors from another names that repo as canonical, and itself as vendored here
# (ShiftLead ADR 2026-10-12: ledgerboard.py, the one vendored file) — still opening "SYNCED FILE".
VENDORED_MARKER="SYNCED FILE — canonical copy: ShiftLead/ledgerboard ledgerboard.py (vendored by agent-cadence as files/"
VENDORED="scripts/ledgerboard.py"
marker() {  # $1 = a SYNC path -> the marker its header must carry, without the path
  case " $VENDORED " in *" $1 "*) printf '%s' "$VENDORED_MARKER" ;; *) printf '%s' "$MARKER" ;; esac
}

# The canonical lists, straight from sync.sh — never restated.
list_files() {  # $1 = SYNC_FILES | SEED_FILES
  python3 - "$DC/sync.sh" "$1" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
block = re.search(rf"{sys.argv[2]}=\(\n(.*?)\n\)", src, re.S)
if not block:
    sys.exit(f"could not parse {sys.argv[2]} out of sync.sh")
print("\n".join(re.findall(r'"(.+?)"', block.group(1))))
PY
}
SYNC_FILES=$(list_files SYNC_FILES) || { bad "cannot parse SYNC_FILES from sync.sh"; exit 1; }
SEED_FILES=$(list_files SEED_FILES) || { bad "cannot parse SEED_FILES from sync.sh"; exit 1; }
[ -n "$SYNC_FILES" ] || { bad "SYNC_FILES parsed empty — the tests below would vacuously pass"; exit 1; }

# --- 1) Every SYNC file carries the marker, naming ITS OWN path. Naming the
#        path is what catches a header copy-pasted from a sibling file.
missing=""; wrongpath=""
for f in $SYNC_FILES; do
  if ! grep -qF "$(marker "$f")" "$DC/files/$f"; then
    missing="$missing $f"
  elif ! grep -qF "$(marker "$f")$f" "$DC/files/$f"; then
    wrongpath="$wrongpath $f"
  fi
done
[ -z "$missing" ]   && ok "every SYNC file carries a provenance header" \
                    || bad "SYNC files with no provenance header:$missing"
[ -z "$wrongpath" ] && ok "every provenance header names its own path" \
                    || bad "provenance header names the wrong path in:$wrongpath"

# --- 2) In the first 10 lines: the marker exists to be seen on open, and a
#        header buried under a 40-line preamble is not.
buried=""
for f in $SYNC_FILES; do
  head -10 "$DC/files/$f" | grep -qF "$(marker "$f")" || buried="$buried $f"
done
[ -z "$buried" ] && ok "every header sits in the first 10 lines" \
                 || bad "header below line 10 (invisible on open) in:$buried"

# --- 3) Shebang stays on line 1. An interpreter reads it there or not at all,
#        and these files are executed directly (hooks, SessionStart commands).
shebang=""
for f in $SYNC_FILES; do
  case "$(head -1 "$DC/files/$f")" in
    '#!'*) ;;
    *) grep -q '^#!' "$DC/files/$f" && shebang="$shebang $f" ;;
  esac
done
[ -z "$shebang" ] && ok "no header displaced a shebang off line 1" \
                  || bad "shebang no longer on line 1 in:$shebang"

# --- 4) Exec bits survive. A pass that rewrites every SYNC file is exactly the
#        operation that silently drops a mode bit, and sync.sh installs with
#        `cp -p`: a canonical file that loses +x ships a non-executable hook to
#        every consumer, where it fails as a no-op nobody notices. (Cost this
#        change's own author an afternoon of a bogus 18-case failure.)
notexec=""
for f in $SYNC_FILES; do
  grep -q '^#!' "$DC/files/$f" || continue
  { [ -x "$DC/files/$f" ] && [ "$(git -C "$DC" ls-files -s "files/$f" | cut -d' ' -f1)" = 100755 ]; } \
    || notexec="$notexec $f"
done
[ -z "$notexec" ] && ok "shebanged SYNC files are executable (worktree and index)" \
                  || bad "lost the exec bit:$notexec"

# --- 5) Python SYNC scripts still compile AND still have a module docstring.
#        The header must be a COMMENT above the docstring, never text prepended
#        into it: list_sessions.py passes __doc__ to argparse as its --help
#        description, so a header absorbed there leaks into user-facing output.
pyfail=""
for f in $SYNC_FILES; do
  case "$f" in *.py) ;; *) continue ;; esac
  python3 - "$DC/files/$f" <<'PY' || pyfail="$pyfail $f"
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
doc = ast.get_docstring(ast.parse(src))          # also proves it compiles
sys.exit(0 if doc and "SYNCED FILE" not in doc else 1)
PY
done
[ -z "$pyfail" ] && ok "python SYNC scripts compile with an unpolluted __doc__" \
                 || bad "docstring missing or contaminated by the header in:$pyfail"

# --- 6) SKILL.md frontmatter still opens at line 1 and still parses — strictly, as YAML. The
#        harness reads name/description from there; a header pushed above it
#        would silently unregister the skill.
fmfail=""
for f in $SYNC_FILES; do
  case "$f" in *SKILL.md) ;; *) continue ;; esac
  [ "$(head -1 "$DC/files/$f")" = "---" ] \
    && sed -n '2,/^---$/p' "$DC/files/$f" | grep -q '^name: [a-z]' \
    && python3 - "$DC/files/$f" <<'PY' || fmfail="$fmfail $f"
import re, sys
# Each frontmatter line is one YAML scalar: Codex's strict loader drops a skill whose
# frontmatter does not parse (`description: "What needs my attention?" — …`, TD-127), where
# Claude Code's reads it. A quoted value is the whole value; a plain one holds no ": " or " #"
# and does not open with an indicator.
fm = open(sys.argv[1], encoding="utf-8").read().split("\n---", 1)[0].splitlines()[1:]
for ln in fm:
    m = re.fullmatch(r"([a-z-]+): (.*)", ln)
    v = m and m.group(2)
    if not m or not (re.fullmatch(r'"(?:[^"\\]|\\.)*"|\'(?:[^\']|\'\')*\'', v)
                     or (v[:1] not in "\"'[]{}>|*&!%@`#," and not v.startswith(("- ", "? "))
                         and ": " not in v and " #" not in v and not v.endswith(":"))):
        sys.exit(1)
PY
done
[ -z "$fmfail" ] && ok "SKILL.md frontmatter intact at line 1" \
                 || bad "frontmatter broken in:$fmfail"

# --- 7) SEED files carry NO marker. They are the consumer's own living content
#        (its board, ledger, memory index, settings); telling their owner not to
#        edit them would be exactly backwards.
seeded=""
for f in $SEED_FILES; do
  grep -qF "$MARKER" "$DC/files/$f" && seeded="$seeded $f"
done
[ -z "$seeded" ] && ok "no SEED file claims to be synced" \
                 || bad "SEED file carries a SYNC provenance header:$seeded"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
