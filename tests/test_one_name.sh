#!/usr/bin/env bash
# The tool has one name (the plan 2026-10-29-hard-rename): no tracked file names it by its old one,
# bar what tests/one_name_allow.txt keeps — the frozen files, the two prose forms for the private
# predecessor repo, and the publish gate's own name list. A gate, so it reads `git ls-files`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# check <repo> <allow-file>: prints each hit no line allows, then a note for each allow line that
# matches nothing (a note, as the publish gate's: the archive line waits for the first archived entry)
check() {
  (cd "$1" && git ls-files -z | python3 -c '
import fnmatch, re, sys
OLD = re.compile("dev[-_]cadence", re.I)
rules, used = [], set()
for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    line = line.rstrip("\n")
    if line.strip() and not line.lstrip().startswith("#"):
        path, _, text = line.partition(" ")
        rules.append((n, path.lower(), text.lower()))
for f in sys.stdin.read().split("\0"):
    if not f:
        continue
    try:
        lines = open(f, encoding="utf-8").read().split("\n")
    except (UnicodeDecodeError, OSError):
        continue
    for i, t in enumerate(lines, 1):
        if not OLD.search(t):
            continue
        hit = [n for n, p, g in rules if fnmatch.fnmatchcase(f.lower(), p) and fnmatch.fnmatchcase(t.lower(), g)]
        used.update(hit)
        if not hit:
            print(f"{f}:{i}: {t.strip()[:160]}")
for n, p, g in rules:
    if n not in used:
        print(f"note: allow line {n} ({p} {g}) matches nothing — drop it if it is stale")
' "$2")
}

out=$(check "$ROOT" "$ROOT/tests/one_name_allow.txt")
grep '^note: ' <<< "$out"; out=$(grep -v '^note: ' <<< "$out")
[ -z "$out" ] && ok "this repo names the tool once: every old-name line is one the allowlist keeps" \
  || bad "old-name lines the allowlist does not keep (rename them, or the plan's *What keeps the name* gains them):
$out"

# the check itself, on a fixture: it catches a stray mention and a stale allow line, case-insensitively
OLD="dev""-cadence"; F="$TMP/f"; mkdir -p "$F/docs"; git init -q -b main "$F"
printf 'run %s path\n' "$OLD" > "$F/a.md"
printf 'kept in the private %s repo\n' "$OLD" > "$F/docs/b.md"
printf 'X=%s\n' "DEV_""CADENCE_REG_DIR" > "$F/c.sh"
printf '* *the private %s repo*\nnothing.md *\n' "$OLD" > "$F/allow.txt"
git -C "$F" add -A
out=$(check "$F" "$F/allow.txt")
grep -q '^a.md:1: ' <<< "$out" && grep -q '^c.sh:1: ' <<< "$out" && ! grep -q 'docs/b.md' <<< "$out" \
  && grep -q '^note: allow line 2 (nothing.md \*) matches nothing' <<< "$out" \
  && ok "fixture: a stray mention and an upper-case variable fail, an allowed form passes, a stale allow line is named" \
  || bad "fixture: $out"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
