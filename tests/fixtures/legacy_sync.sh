#!/usr/bin/env bash
# FIXTURE, never run outside a test: sync.sh as it was before TD-129's closing slice (2026-10-28),
# kept only to make the input `sync.sh --pin` migrates — a repo the copy mode synced (tests/test_sync_pin.sh).
# A test copies it beside a temp build of files/ and runs it there, with HOME, XDG and the roster temp.
# Its SYNC_FILES is frozen: a path later removed from files/ makes it fail, and the test then prunes it from
# this copy rather than growing the copy mode back.
#
# sync.sh — install or update the dev-cadence system in a target repo.
#
#   ./sync.sh /path/to/target-repo             # install/update
#   ./sync.sh --verify /path/to/target-repo    # read-only drift check (TD-8)
#   ./sync.sh --pin /path/to/target-repo       # the migration (TD-129): pin the repo to this clone's
#                                              # HEAD and retire its synced copies — opt-in, per repo
#   ./sync.sh --pin --siblings-moved /path/to/home  # a constellation's home, once its siblings' hooks
#                                              # no longer call its scripts/ (TD-147)
#
# Three file classes:
#   SYNC  — canonical files, always overwritten on every run (edit them HERE,
#           never in the consumer repo; the target's `git diff` shows what changed).
#   SEED  — skeletons created only if missing; never overwritten (they hold the
#           target repo's own living content: ledger, board, memory index, settings).
#   RETIRED — once SYNC, dropped from the payload: the next sync deletes the consumer's
#           copy only while it still matches its lock hash; an edited copy is kept (TD-057).
#
# Writes docs/cadence-sync.lock in the target recording the source commit and a
# sha256 per SYNC file, then prints next steps. Review the diff in the target
# repo and PR it like any change. --verify compares each consumer copy against
# the lock's recorded hash and mode (local drift) and against the published canonical —
# origin/<default> after a bounded fetch, else this clone's working tree with a printed
# caveat (upgrade available); it mutates nothing in the target.
# CADENCE_VERIFY_REFERENCE=worktree skips the fetch and uses this clone's working tree. Exit: 0 = no drift (UPGRADE/
# NEW/RETIRED advice may still print; RETIRED = no longer in SYNC_FILES), 1 =
# DRIFT/MISSING/AHEAD/MODE/SYMLINK, 2 = cannot verify (no lock, pre-hash lock lines,
# a listed file missing from files/, or unreadable/unhashable files).
set -euo pipefail

# Position-independent parsing, and unknown flags are fatal: `sync.sh <repo>
# --verify` must never fall through to a mutating sync of a repo the caller
# asked to inspect read-only (review finding, PR #57).
VERIFY=0
PIN=0
MOVED=0
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --verify) VERIFY=1 ;;
        --pin) PIN=1 ;;
        --siblings-moved) MOVED=1 ;;
        -*) echo "ERROR: unknown option '$arg' — usage: sync.sh [--verify|--pin] /path/to/target-repo" >&2; exit 1 ;;
        *)  if [ -n "$TARGET" ]; then
                echo "ERROR: more than one target given ('$TARGET', '$arg')" >&2; exit 1
            fi
            TARGET="$arg" ;;
    esac
done
[ -n "$TARGET" ] || { echo "usage: sync.sh [--verify|--pin] /path/to/target-repo" >&2; exit 1; }
[ "$VERIFY$PIN" = 11 ] && { echo "ERROR: --verify reads and --pin migrates — pick one" >&2; exit 1; }
[ "$MOVED" = 1 ] && [ "$PIN" = 0 ] && { echo "ERROR: --siblings-moved goes with --pin (a constellation's home, TD-147)" >&2; exit 1; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- --pin: the migration (TD-129, docs/plans/2026-10-25-pinned-not-synced.md Decision 11) -------
# A synced repo's last sync: the [dev-cadence] pin at this clone's HEAD, the synced copies and the lock
# retired by the RETIRED rule (a copy still matching its lock hash is removed, an edited one kept with
# a WARN), the seeds and the skill pointers (SEED once pinned, Decision 5), the hook shims, the roster.
# Commits nothing. It is `dev-cadence adopt`'s code (launcher/words.py w_adopt, --migrate), never a
# copy of it; never run by sync-all.sh — a person moves each repo, one at a time.
if [ "$PIN" = 1 ]; then
    if [ "$MOVED" = 1 ]; then
        exec python3 "$SRC/launcher/words.py" adopt --migrate --siblings-moved "$TARGET"
    fi
    exec python3 "$SRC/launcher/words.py" adopt --migrate "$TARGET"
fi

git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: $TARGET is not a git repo" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
# Clone root: for a linked worktree this is the MAIN checkout — per-clone settings
# (git config, settings.local.json) belong there, while file content goes to $TARGET.
# cd-based absolutization instead of --path-format=absolute (git ≥2.31 only, and
# rev-parse echoes unknown flags to stdout with exit 0 — a silent-garbage failure).
COMMON_DIR="$(cd "$TARGET" && cd "$(git rev-parse --git-common-dir)" && pwd)"
CLONE_ROOT="$(dirname "$COMMON_DIR")"
SHA=$(git -C "$SRC" rev-parse --short HEAD)
DIRTY=""
git -C "$SRC" diff --quiet HEAD -- files/ sync.sh 2>/dev/null || DIRTY="+dirty"

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
# RETIRED (TD-057): once SYNC, now dropped from the payload. Sync removes a consumer's
# copy — but only while it still matches the hash its lock recorded; a copy the consumer
# edited is kept, with a warning, for a person to port and delete. A path is in exactly
# one of the three arrays. (Empty so far: nothing has been retired.)
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
)

for f in ${RETIRED_FILES[@]+"${RETIRED_FILES[@]}"}; do
    for g in "${SYNC_FILES[@]}" "${SEED_FILES[@]}"; do
        [ "$f" = "$g" ] && { echo "ERROR: $f is in RETIRED_FILES and in SYNC_FILES/SEED_FILES — pick one" >&2; exit 1; }
    done
done
RETIRED_LIST="$(printf '%s\n' ${RETIRED_FILES[@]+"${RETIRED_FILES[@]}"})"
export RETIRED_LIST

# --- consumer opt-outs (TD-072; read through cadence_config.py since TD-096) ----------------
# The repo's `docs/cadence.toml` declares them — `[not-adopted]` "§N" = "<ADR>" drops the SYNC
# files that exist only to enforce rule §N (the table below); `[skip-seed]` "<path>" = "<ADR>"
# never creates that SEED file — and the older `docs/cadence-local.conf` (`not-adopted: §N —
# <ADR>`, `skip-seed: <path> — <ADR>`) is still read, with a WARN to move it (TD-096). Both are
# consumer-owned and read only by `scripts/cadence_config.py opt-outs`, never parsed here; this
# block judges what the helper found. An opted-out SYNC file is neither copied nor locked, and a
# copy still matching its lock is removed; --verify reports it as OPTED-OUT. Anything that
# cannot be read is a WARN and is ignored — the payload ships whole.
# Parity (cadence.md §7.9): the seed template and cadence.md's Adoption checklist write this.
optout_files() {  # $1 = rule number — the SYNC files that exist only to enforce it
    case "$1" in
        4) echo "scripts/git-hooks/pre-push" ;;   # §4's teeth: the main-branch push guard (§4.7)
        *) return 1 ;;
    esac
}
OPTOUT_SYNC=""   # lines "path<TAB>why", SYNC files not shipped
OPTOUT_SEED=""   # lines "path<TAB>why", SEED files never created
OPTOUT_FROM=""   # lines "path<TAB>file", the file that declared each
OPTOUT_WARN=""   # lines "<file>: <what is wrong>"
if ! optout_lines="$(python3 "$SRC/files/scripts/cadence_config.py" opt-outs --repo "$TARGET" 2>&1)"; then
    OPTOUT_WARN+="docs/cadence.toml: the opt-outs could not be read ($(echo "$optout_lines" | tr '\n' ' ')) — nothing is opted out"$'\n'
    optout_lines=""
fi
while IFS=$'\x1f' read -r kind val why src line; do
    case "$kind" in
        '') continue ;;
        warn) OPTOUT_WARN+="$val"$'\n'; continue ;;
    esac
    noadr="$src: '$line' names no decision (ADR) — honoured; add the ADR that decided it"$'\n'
    [ -n "$why" ] && noadr=""
    why="${why:-no ADR named}"
    case "$kind" in
        not-adopted)
            n="${val#§}"
            if files="$(optout_files "$n")"; then
                for f in $files; do OPTOUT_SYNC+="$f"$'\t'"§$n not adopted: $why"$'\n'; OPTOUT_FROM+="$f"$'\t'"$src"$'\n'; done
                OPTOUT_WARN+="$noadr"
            else
                OPTOUT_WARN+="$src: not-adopted: $val — no cadence rule by that number can be opted out (only §4 today); ignored, shipped"$'\n'
            fi ;;
        skip-seed)
            found=0
            for g in "${SEED_FILES[@]}"; do [ "$g" = "$val" ] && found=1; done
            if [ "$found" = 1 ] && [ "$val" != "docs/cadence.toml" ]; then
                OPTOUT_SEED+="$val"$'\t'"skip-seed: $why"$'\n'; OPTOUT_FROM+="$val"$'\t'"$src"$'\n'
                OPTOUT_WARN+="$noadr"
            else
                OPTOUT_WARN+="$src: skip-seed: $val — not a SEED file sync.sh creates; ignored"$'\n'
            fi ;;
    esac
done <<< "$optout_lines"
opted() {  # $1 = path, $2 = list — prints the why and succeeds when the path is in it
    local p w
    while IFS=$'\t' read -r p w; do [ -n "$p" ] && [ "$p" = "$1" ] && { printf '%s' "$w"; return 0; }; done <<< "$2"
    return 1
}
export OPTOUT_SYNC OPTOUT_SEED
SHIP_FILES=()    # SYNC_FILES minus the opted-out: what is copied and locked
for f in "${SYNC_FILES[@]}"; do opted "$f" "$OPTOUT_SYNC" >/dev/null || SHIP_FILES+=("$f"); done

# --- --verify: read-only drift report (TD-8) -----------------------------------
# Three distinguishable states per file, from two comparisons:
#   consumer copy vs lock hash   -> local drift since the last sync (the rule
#                                   "edit SYNC files in dev-cadence, never in
#                                   consumers" finally has a detector)
#   consumer copy vs canonical   -> upgrade available (canonical moved upstream)
# Runs entirely before the mutating section and exits — --verify must never
# write a byte in the target.
if [ "$VERIFY" -eq 1 ]; then
    # TD-096: a key or value the settings reader cannot use is reported, never drift
    if cfg_check="$(python3 "$SRC/files/scripts/cadence_config.py" --check --repo "$TARGET" 2>&1)"; then :
    elif [ $? -eq 1 ]; then OPTOUT_WARN+="$cfg_check"$'\n'
    elif ! grep -qF "docs/cadence.toml: cannot read" <<< "$OPTOUT_WARN"; then   # said once already
        OPTOUT_WARN+="docs/cadence.toml: cannot check the settings ($(echo "$cfg_check" | tr '\n' ' '))"$'\n'
    fi
    OPTOUT_WARN="$OPTOUT_WARN" exec python3 - "$SRC" "$TARGET" "${SYNC_FILES[@]}" <<'PY'
import hashlib, os, re, subprocess, sys

src, target = sys.argv[1], sys.argv[2]
canonical_set = sys.argv[3:]

# TD-057: the canonical side is PUBLISHED state — origin/<default> of this clone, after a
# bounded fetch — never "wherever this checkout happens to stand": from a stale clone an
# ahead consumer read UPGRADE, and from a branch clone a file added upstream read RETIRED.
# The SYNC set comes from that ref's sync.sh too. When origin cannot be read, fall back to
# this clone's working tree and say so. CADENCE_VERIFY_REFERENCE=worktree forces the
# fallback (the verdict tests drive the canonical side by editing files/).
def git(*args, timeout=15):
    try:
        r = subprocess.run(["git", "-C", src, *args], capture_output=True, timeout=timeout, check=False,
                           env={**os.environ, "GIT_TERMINAL_PROMPT": "0",
                                "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=5"})
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None

REF = None
reference = "this clone's working tree"
caveat = None
ref_files = {}   # path -> (sha256, "755"|"644") at REF
if os.environ.get("CADENCE_VERIFY_REFERENCE") == "worktree":
    caveat = "CADENCE_VERIFY_REFERENCE=worktree"
else:
    head = git("symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
    branch = head.decode().strip().removeprefix("origin/") if head and head.strip() else "main"
    fetched = git("fetch", "-q", "--no-prune", "origin",
                  f"+refs/heads/{branch}:refs/remotes/origin/{branch}", timeout=30) is not None
    tip = git("rev-parse", "--verify", "-q", f"refs/remotes/origin/{branch}^{{commit}}")
    sync_sh = git("show", f"refs/remotes/origin/{branch}:sync.sh") if tip else None
    m = re.search(rb"^SYNC_FILES=\((.*?)^\)", sync_sh or b"", re.S | re.M)
    tree = git("ls-tree", "-r", f"refs/remotes/origin/{branch}", "--", "files/") if m else None
    if tip and m and tree is not None:
        canonical_set = [x.decode() for x in re.findall(rb'"([^"]+)"', m.group(1))]
        # the RETIRED set from the same ref, so both sets describe one published state
        mr = re.search(rb"^RETIRED_FILES=\((.*?)^\)", sync_sh, re.S | re.M)
        os.environ["RETIRED_LIST"] = "\n".join(x.decode() for x in re.findall(rb'"([^"]+)"', mr.group(1))) if mr else ""
        for line in tree.decode().splitlines():
            meta, _, path = line.partition("\t")
            mode, kind, obj = meta.split()
            if kind == "blob" and path.startswith("files/"):
                ref_files[path[6:]] = (obj, "755" if mode == "100755" else "644")
        REF = f"refs/remotes/origin/{branch}"
        reference = f"origin/{branch} @ {tip.decode().strip()[:7]}" + ("" if fetched else " (fetch failed: as of the last fetch)")
    else:
        caveat = f"origin/{branch} unreadable here"
if caveat:
    reference += f" — CAVEAT: {caveat}; the verdicts below depend on what this checkout holds"

def canon_sha(path):
    """sha256 of the canonical copy, or None when the reference has no such file."""
    if REF is None:
        spath = os.path.join(src, "files", path)
        return sha(spath) if os.path.exists(spath) else None
    if path not in ref_files:
        return None
    blob = git("cat-file", "blob", ref_files[path][0])
    if blob is None:
        raise OSError(f"cannot read {path} at {REF}")
    return hashlib.sha256(blob).hexdigest()

def canon_exec(path):
    if REF is None:
        return os.stat(os.path.join(src, "files", path)).st_mode & 0o100 != 0
    return ref_files[path][1] == "755"

# A tool malfunction must never impersonate a verdict: any OSError on the lock
# or a hashed file routes to exit 2 (cannot verify), never exit 1 (drift) and
# never a raw traceback (review finding, PR #57).
def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

lock_path = os.path.join(target, "docs", "cadence-sync.lock")
if not os.path.exists(lock_path):
    print(f"CANNOT VERIFY: no {lock_path} — this repo has never been synced (or the lock was deleted). Run sync.sh first.")
    sys.exit(2)

locked = {}   # path -> sha256 | None (pre-hash lock line)
modes = {}    # path -> "755" | "644", when the lock line records one (TD-057)
commit = "?"
try:
    with open(lock_path, encoding="utf-8") as f:
        lock_lines = f.readlines()
except OSError as e:
    print(f"CANNOT VERIFY: {lock_path} is unreadable ({e.strerror or e}).")
    sys.exit(2)
for line in lock_lines:
    line = line.rstrip("\n")
    if line.startswith("commit: "):
        commit = line[8:]
    elif line.startswith("file: "):
        m = re.fullmatch(r"file: (.+?) ([0-9a-f]{64})(?: (755|644))?", line)
        if m:
            locked[m.group(1)] = m.group(2)
            if m.group(3):
                modes[m.group(1)] = m.group(3)
        else:
            locked[line[6:].strip()] = None

print(f"== dev-cadence verify {target} (lock: commit {commit}; canonical: {reference})")
drift = unverifiable = upgrades = 0
canonical = set(canonical_set)
# TD-072: what the repo opts out (docs/cadence.toml, or the older cadence-local.conf) is a decision, not drift
def tsv(name):
    return dict(ln.split("\t", 1) for ln in os.environ.get(name, "").splitlines() if "\t" in ln)
optout, optseed = tsv("OPTOUT_SYNC"), tsv("OPTOUT_SEED")
for w in os.environ.get("OPTOUT_WARN", "").splitlines():
    if w:
        print(f"  WARN          {w}")
for path, why in {**optout, **optseed}.items():
    if path in optout and os.path.lexists(os.path.join(target, path)):
        print(f"  OPTED-OUT     {path} — {why}; still present — re-run sync.sh to remove it")
        upgrades += 1
    else:
        print(f"  OPTED-OUT     {path} — {why}")
for path, lock_hash in locked.items():
    tpath = os.path.join(target, path)
    if path in optout:
        continue
    # TD-057: retired means "no longer in SYNC_FILES", not "no longer under files/" —
    # a file moved to SEED still exists there, and the consumer's edits to it are now
    # legitimate, so it is reported before (and instead of) any drift verdict.
    if path not in canonical:
        state = "still present" if os.path.lexists(tpath) else "already removed"
        print(f"  RETIRED       {path} — no longer in the SYNC set (retired, or now SEED: the consumer owns it); {state}")
        upgrades += 1
        continue
    try:
        canon = canon_sha(path)
    except OSError:
        canon = None
    if os.path.islink(tpath):
        print(f"  SYMLINK       {path} — the consumer's copy is a symlink; sync.sh refuses to write through it (replace it with a file)")
        drift += 1
        continue
    if not os.path.exists(tpath):
        print(f"  MISSING       {path} — in the lock but deleted from the consumer")
        drift += 1
        continue
    if lock_hash is None:
        print(f"  UNVERIFIABLE  {path} — lock line predates content hashes; re-run sync.sh to record them")
        unverifiable += 1
        continue
    try:
        got = sha(tpath)
    except OSError as e:
        print(f"  UNVERIFIABLE  {path} — exists but cannot be hashed ({e.strerror or e}); not a file?")
        unverifiable += 1
        continue
    if got != lock_hash:
        if canon is not None and got == canon:
            # matches upstream HEAD but not what this consumer's sync installed —
            # a hand-copy that skipped the lock; a re-sync makes it honest
            print(f"  AHEAD         {path} — matches the canonical copy ({reference.split(' — ')[0]}) but not the lock; re-run sync.sh to update the lock")
        else:
            print(f"  DRIFT         {path} — local edit since the last sync (canonical home is dev-cadence; port the change there or re-sync to discard it)")
        drift += 1
        continue
    if path in modes and (os.stat(tpath).st_mode & 0o100 != 0) != (modes[path] == "755"):
        # TD-057: the runner skips a child that is not executable ([ -x ] || return 0),
        # so a lost +x is a silently disabled hook — drift, not a detail
        what = "lost its executable bit" if modes[path] == "755" else "gained an executable bit"
        print(f"  MODE          {path} — {what} since the sync (chmod, or re-run sync.sh)")
        drift += 1
        continue
    if canon is None:
        print(f"  UNVERIFIABLE  {path} — in SYNC_FILES but missing from files/ in {reference.split(' — ')[0]}")
        unverifiable += 1
    elif got == canon and canon_exec(path) != (os.stat(tpath).st_mode & 0o100 != 0):
        print(f"  UPGRADE       {path} — canonical's executable bit changed since this sync")
        upgrades += 1
    elif got != canon:
        print(f"  UPGRADE       {path} — canonical has moved since this sync")
        upgrades += 1
    else:
        print(f"  ok            {path}")

for path in [p for p in os.environ.get("RETIRED_LIST", "").splitlines() if p]:
    if path not in locked and os.path.lexists(os.path.join(target, path)):
        # still in the consumer, no longer in its lock: a sync since the retirement kept
        # an edited copy (a copy still in the lock is reported RETIRED above)
        print(f"  RETIRED       {path} — dropped from the payload, still present (kept by a sync: edited locally?)")
        upgrades += 1

for path in canonical_set:
    if path not in locked and path not in optout:
        print(f"  NEW           {path} — in the canonical SYNC set but not in this consumer's lock; re-run sync.sh")
        upgrades += 1

parts = []
if drift:        parts.append(f"{drift} drifted/missing")
if unverifiable: parts.append(f"{unverifiable} unverifiable")
if upgrades:     parts.append(f"{upgrades} behind canonical")
print("== " + (", ".join(parts) if parts else "clean — every SYNC copy matches its lock and canonical"))
sys.exit(1 if drift else (2 if unverifiable else 0))
PY
fi
# -------------------------------------------------------------------------------

echo "== dev-cadence sync ${SHA}${DIRTY} -> ${TARGET}"
while IFS= read -r w; do if [ -n "$w" ]; then echo "  WARN  $w"; fi; done <<< "$OPTOUT_WARN"

# TD-057: refuse, before writing anything, a target path that cp would not write AS a
# file in this repo — a symlink (cp writes through it, into another repo, and the
# consumer's diff stays clean), a directory (cp writes dir/<basename>), or a parent that
# resolves outside the target (a symlinked scripts/).
# An EXISTING SEED path is exempt: SEED never writes a path that exists, so a
# dotfiles-managed symlinked .claude/settings.json is left alone, as it always was.
REAL_TARGET="$(cd "$TARGET" && pwd -P)"
bad_targets=""
check_target() {  # $1 = path relative to the target
    local f="$1" t="$TARGET/$1" d r
    if [ -L "$t" ]; then bad_targets+="    $f is a symlink"$'\n'; return; fi
    if [ -d "$t" ]; then bad_targets+="    $f is a directory"$'\n'; return; fi
    # Climb to the nearest component that EXISTS OR IS A LINK: `[ -e ]` dereferences, so a
    # dangling or looping symlinked directory would otherwise read as absent and be
    # climbed past, and cp would fail on it half-way through the copy.
    d="$(dirname "$t")"
    while [ ! -e "$d" ] && [ ! -L "$d" ] && [ "$d" != "$TARGET" ]; do d="$(dirname "$d")"; done
    r="$(cd "$d" 2>/dev/null && pwd -P || true)"
    if [ -z "$r" ]; then
        bad_targets+="    $f: ${d#"$TARGET"/} is a dangling or looping symlink"$'\n'
    else
        case "$r/" in
            "$REAL_TARGET"/*) ;;
            *) bad_targets+="    $f: its directory resolves outside the target ($r)"$'\n' ;;
        esac
    fi
}
# TD-160: a repo whose ledger is a directory (docs/ledger/, ledgerboard v2) holds its entries and
# archive there, so the v1 ledger seeds are never created beside it — the readers would then see two.
v2_holds() {
    case "$1" in docs/technical_debt.md|docs/technical_debt_archive.md) [ -d "$TARGET/docs/ledger" ] ;; *) return 1 ;; esac
}
for f in "${SHIP_FILES[@]}"; do check_target "$f"; done
for f in "${SEED_FILES[@]}"; do [ -e "$TARGET/$f" ] || opted "$f" "$OPTOUT_SEED" >/dev/null || v2_holds "$f" || check_target "$f"; done
if [ -n "$bad_targets" ]; then
    echo "ERROR: refusing to sync — these target paths would not be written as files in $TARGET:" >&2
    printf '%s' "$bad_targets" >&2
    echo "  Replace them with plain files/directories, then re-run. Nothing was written." >&2
    exit 1
fi

# TD-133: the ledger and board a sync keeps (SEED: never overwritten) are read first, with the
# ledgerboard.py this sync installs. On every sync, one declaring a newer major of the formats
# (`Ledgerboard: N`) stops it — the scripts it would install cannot read that file. On the first
# sync (no lock yet: the adopt), a repo's own ledger must also pass `ledger.py --check` and hold
# nothing the readers would skip — an entry that is not a `## TD-NNN:` body, a summary row with no
# body, a board line that is not a `- [ ]` item — or the adopt stops with the list; converting a
# foreign ledger or board is the person's. Nothing is written before this.
LB_KEPT=()
for f in docs/technical_debt.md docs/technical_debt_archive.md docs/user_attention.md; do
    if [ -e "$TARGET/$f" ] && ! opted "$f" "$OPTOUT_SEED" >/dev/null; then LB_KEPT+=("$f"); fi
done
[ -f "$TARGET/docs/ledger/README.md" ] && LB_KEPT+=("docs/ledger/README.md")   # a v2 ledger's version line
ADOPT=0; [ -e "$TARGET/docs/cadence-sync.lock" ] || ADOPT=1
if { [ "${#LB_KEPT[@]}" -gt 0 ] || [ -d "$TARGET/docs/ledger" ]; } && ! python3 - "$SRC/files/scripts" "$TARGET" "$ADOPT" "${LB_KEPT[@]}" <<'PY'
import json, os, re, subprocess, sys
scripts, target, adopt, kept = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4:]
sys.path.insert(0, scripts)
import ledgerboard as LB
LEDGER, ARCHIVE, BOARD = "docs/technical_debt.md", "docs/technical_debt_archive.md", "docs/user_attention.md"
V2 = "docs/ledger"  # TD-160: its README.md carries the version; ledger.py --check reads the directory
SKIP_HEAD = re.compile(r"^(?!## TD-\d+:)#{1,6}[ \t]*[*_`]*TD-\d+", re.MULTILINE)
SKIP_ITEM = re.compile(r"^[ \t]*[-*+][ \t]+[*_`]*TD-\d+", re.MULTILINE)
NO_ID_SHAPE = re.compile(r"^(?:[ \t]*[-*+][ \t]+\S|#{2,6}[ \t]+(?!Summary[ \t]*$)\S)", re.MULTILINE)  # a list line, a section
SKIP_BOARD = re.compile(r"^[-*+][ \t]+(?!\[[ xX]\][ \t])(?!\(none\))", re.MULTILINE)
problems, texts = [], {}
for f in kept:
    try:
        texts[f] = open(os.path.join(target, f), encoding="utf-8", errors="replace").read()
    except OSError as e:
        problems.append(f"{f}: cannot read: {e}")
        continue
    why = LB.version_problem(texts[f])
    if why:
        problems.append(f"{f}: {why}")
def lineno(text, m):
    return text.count("\n", 0, m.start()) + 1
if adopt and not problems:
    for f in (LEDGER, ARCHIVE):
        if f in texts:
            t = LB.COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), texts[f])  # keep line numbers
            for rx, what in ((SKIP_HEAD, "a heading the readers skip — an entry is `## TD-NNN: title`"),
                             (SKIP_ITEM, "a list item the readers skip — an entry is a `## TD-NNN: title` body")):
                problems += [f"{f}:{lineno(t, m)}: {what}" for m in rx.finditer(t)]
    if LEDGER in texts:
        bodies = LB.heading_nums(texts[LEDGER])
        problems += [f"{LEDGER}: summary row {r['id']} has no `## {r['id']}:` body — the readers never see it"
                     for r in LB.rows(texts[LEDGER]) if LB._num(r["id"]) not in bodies]
        if not bodies and not LB.rows(texts[LEDGER]):  # no TD ids at all: entries in a shape of its own?
            t = LB.COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), texts[LEDGER])
            problems += [f"{LEDGER}:{lineno(t, m)}: a ledger with no `## TD-NNN:` entry holds this — the readers skip it"
                         for m in NO_ID_SHAPE.finditer(t)]
        cmd = [sys.executable, os.path.join(scripts, "ledger.py"), "--check", "--json",
               "--ledger", os.path.join(target, LEDGER), "--archive", os.path.join(target, ARCHIVE)]
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=target)
        try:
            problems += [f"{LEDGER}: ledger.py --check: {x['text']}" for x in json.loads(r.stdout)["flags"]
                         if x["level"] == "error"]
        except (ValueError, KeyError, TypeError):
            problems.append(f"{LEDGER}: ledger.py --check did not run (exit {r.returncode}): "
                            f"{(r.stderr.strip() or r.stdout.strip())[:300]}")
    # the readers take any docs/ledger/ directory as the ledger (ledger_at()), README or not, and
    # before a v1 file beside it — so the directory is checked whenever there is one
    if os.path.isdir(os.path.join(target, V2)):
        cmd = [sys.executable, os.path.join(scripts, "ledger.py"), "--check", "--json", "--ledger", os.path.join(target, V2)]
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=target)
        try:
            problems += [f"{V2}/: ledger.py --check: {x['text']}" for x in json.loads(r.stdout)["flags"]
                         if x["level"] == "error"]
        except (ValueError, KeyError, TypeError):
            problems.append(f"{V2}/: ledger.py --check did not run (exit {r.returncode}): "
                            f"{(r.stderr.strip() or r.stdout.strip())[:300]}")
    if BOARD in texts:
        t = LB.COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), texts[BOARD])
        problems += [f"{BOARD}:{lineno(t, m)}: a list line the readers skip — an item is `- [ ] …`"
                     for m in SKIP_BOARD.finditer(t)]
if problems:
    print("ERROR: refusing to sync — " + ("this repo's own ledger or board does not read as the format "
          "(ledgerboard SPEC.md), and sync keeps them as they are:" if adopt else
          "a ledger or board this sync keeps declares a format its scripts cannot read:"), file=sys.stderr)
    for p in problems:
        print(f"    {p}", file=sys.stderr)
    print("  Convert or fix them (the list above is where to start), then re-run. Nothing was written.", file=sys.stderr)
    sys.exit(1)
PY
then
    exit 1
fi

for f in "${SYNC_FILES[@]}"; do
    if why="$(opted "$f" "$OPTOUT_SYNC")"; then
        echo "  skip  $f ($why — $(opted "$f" "$OPTOUT_FROM"))"
        continue
    fi
    mkdir -p "$TARGET/$(dirname "$f")"
    cp -p "$SRC/files/$f" "$TARGET/$f"
    echo "  sync  $f"
done

for f in "${SEED_FILES[@]}"; do
    if why="$(opted "$f" "$OPTOUT_SEED")"; then
        echo "  skip  $f ($why — $(opted "$f" "$OPTOUT_FROM"); never created)"
    elif [ ! -e "$TARGET/$f" ] && v2_holds "$f"; then
        echo "  skip  $f (the ledger is docs/ledger/, a directory: never created)"
    elif [ -e "$TARGET/$f" ]; then
        echo "  keep  $f (exists — never overwritten)"
    else
        mkdir -p "$TARGET/$(dirname "$f")"
        cp -p "$SRC/files/$f" "$TARGET/$f"
        echo "  seed  $f"
    fi
done

# --- retired and opted-out files (TD-057, TD-072): removed while they still match what sync
# installed. Runs BEFORE the lock is rewritten: the old lock's hash is the proof the copy is unedited.
OPTOUT_LIST="$(while IFS=$'\t' read -r p _; do if [ -n "$p" ]; then printf '%s\n' "$p"; fi; done <<< "$OPTOUT_SYNC")"
export OPTOUT_LIST
if [ -n "$RETIRED_LIST$OPTOUT_LIST" ]; then
    if ! python3 - "$TARGET" <<'PY'
import hashlib, os, re, sys
target = sys.argv[1]
lock = {}
try:
    for line in open(os.path.join(target, "docs", "cadence-sync.lock"), encoding="utf-8"):
        m = re.fullmatch(r"file: (.+?) ([0-9a-f]{64})(?: (?:755|644))?", line.rstrip("\n"))  # as --verify parses it
        if m:
            lock[m.group(1)] = m.group(2)
except OSError:
    pass
for kind, f in ([("retired", p) for p in os.environ["RETIRED_LIST"].splitlines() if p]
                + [("opted-out", p) for p in os.environ["OPTOUT_LIST"].splitlines() if p]):
    t = os.path.join(target, f)
    if not os.path.lexists(t):
        continue
    if os.path.islink(t) or not os.path.isfile(t):
        print(f"  WARN  {kind} {f} is not a plain file — left for you to remove")
        continue
    # a symlinked ANCESTOR (check_target guards SYNC/SEED against one, never this list):
    # open()/remove() would follow it out of the target and delete someone else's file
    if os.path.realpath(t) != os.path.join(os.path.realpath(target), f):
        print(f"  WARN  {kind} {f} reaches through a symlinked directory — left for you to remove")
        continue
    with open(t, "rb") as fh:
        now = hashlib.sha256(fh.read()).hexdigest()
    if lock.get(f) != now:
        why = "differs from what sync installed" if f in lock else "is not in this repo's lock"
        print(f"  WARN  {kind} {f} {why} — kept; port any edits, then delete it yourself")
        continue
    os.remove(t)
    print(f"  retire {f}" if kind == "retired" else f"  optout {f} removed (opted out by the repo)")
PY
    then
        # never a sync half-done over a traceback: SYNC/SEED are already written and the
        # lock is next — a failure here keeps every retired file and says so
        echo "  WARN  the retired-file pass failed (above; it also removes opted-out files) — no file was removed after the failure; re-run sync.sh"
    fi
fi

# --- settings reader (TD-096, cadence §9.18) -----------------------------------------------
# docs/cadence.toml is read with tomllib (Python >= 3.11). An older python3 still syncs; the
# reader then errors on that file rather than guess — say so now, not at the first review.
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
    || echo "  WARN  python3 is $(python3 -c 'import platform; print(platform.python_version())') — scripts/cadence_config.py needs >= 3.11 to read docs/cadence.toml (cadence §9.18)"

# --- hook wiring detector (cadence §3, 2026-09-11) ------------------------------
# settings.json is SEED, so sync never rewrites it. Since 2026-09-11 dev-cadence's
# SessionStart set is ONE line calling scripts/cadence_hooks.sh; a consumer still carrying
# the old per-hook lines (or none) misses every hook added since. Warn, never rewrite.
if [ -e "$TARGET/.claude/settings.json" ]; then
    python3 - "$TARGET/.claude/settings.json" "$SRC/files/.claude/settings.json" <<'PY' || echo "  WARN  hook-line detector failed; check $TARGET/.claude/settings.json by hand"
import json, sys
p, seed = sys.argv[1], sys.argv[2]
def commands(path):
    return [str(h.get("command", "")) for g in json.load(open(path)).get("hooks", {}).get("SessionStart", []) for h in g.get("hooks", [])]
want = commands(seed)[0]  # the one seeded line, verbatim
try:
    cmds = commands(p)
except (OSError, ValueError, AttributeError, TypeError):
    print(f"  WARN  {p}: not readable as JSON; cannot check the SessionStart hook line")
    sys.exit(0)
if want in cmds:
    sys.exit(0)
if any("scripts/cadence_hooks.sh" in c for c in cmds):
    print(f"  WARN  {p}: the cadence_hooks.sh SessionStart line differs from the seed — make it")
    print("        byte-identical to files/.claude/settings.json (cadence §3; the 2026-09-25 line runs")
    print("        the main checkout's runner, so every worktree gets the current hook set — TD-055)")
else:
    print(f"  WARN  {p}: SessionStart lacks the cadence_hooks.sh line — replace the per-hook")
    print("        dev-cadence lines with the one line from files/.claude/settings.json (cadence §3)")
PY
fi

# --- Gemini map detector (TD-111) ------------------------------------------------
# Gemini CLI reads AGENTS.md only when context.fileName names it; the SEED says so, but a
# consumer that already had its own .gemini/settings.json is never seeded. Warn, never rewrite.
if [ -e "$TARGET/.gemini/settings.json" ] && ! printf '%s' "$OPTOUT_SEED" | grep -q "^\.gemini/settings\.json"$'\t'; then
    python3 - "$TARGET/.gemini/settings.json" <<'PY' || echo "  WARN  Gemini map detector failed; check $TARGET/.gemini/settings.json by hand"
import json, sys
p = sys.argv[1]
try:
    names = (json.load(open(p)).get("context") or {}).get("fileName")
except (OSError, ValueError, AttributeError):
    print(f"  WARN  {p}: not readable as JSON; cannot check that Gemini CLI reads AGENTS.md")
    sys.exit(0)
if (names if isinstance(names, list) else [names]).count("AGENTS.md"):
    sys.exit(0)
print(f"  WARN  {p}: context.fileName does not name AGENTS.md, so a Gemini CLI session gets no map")
print('        and no wake-up — add "AGENTS.md" to it, as files/.gemini/settings.json does (cadence §7.6, TD-111)')
PY
fi

# --- per-clone setup sync.sh can do itself (plan P1 / TD-1) -------------------
# These are the adoption-checklist steps that used to be printed and forgotten.
# All idempotent; never clobber a divergent existing value (warn instead).

# 1) git hooks — the pre-push main guard and post-merge, in force in every worktree of
#    this clone whatever its branch (TD-055): shims in the shared .git/hooks that run the
#    main checkout's copy; a relative core.hooksPath naming scripts/git-hooks is unset
#    (it resolved per worktree branch). Never clobbers a hook or a hooksPath of the
#    clone's own — warns instead. The logic lives in the synced script so a clone that
#    predates it is fixed by running that one script.
# TD-072: an opted-out hook gets no shim — even when an edited copy of it was kept above.
CADENCE_HOOKS_SKIP="$(while IFS=$'\t' read -r p _; do case "$p" in scripts/git-hooks/*) printf '%s ' "${p##*/}" ;; esac; done <<< "$OPTOUT_SYNC")" \
    bash "$TARGET/scripts/install_git_hooks.sh" "$TARGET" || true

# 2) autoMemoryDirectory — merge into the CLONE ROOT's .claude/settings.local.json
#    (machine-local file; value must be an absolute path). Never clobber a
#    different existing value; never touch a file that fails to parse.
python3 - "$CLONE_ROOT/.claude/settings.local.json" "$CLONE_ROOT/docs/claude-memory" <<'PY'
import json, os, sys
path, memdir = sys.argv[1], sys.argv[2]
if os.path.islink(path):
    print(f"  WARN  {path} is a symlink — left untouched (a rewrite would replace the link with a plain file); set autoMemoryDirectory to {memdir} at its real target")
    sys.exit(0)
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError) as e:
        print(f"  WARN  {path} exists but could not be parsed ({e}) — left untouched; set autoMemoryDirectory to {memdir} by hand")
        sys.exit(0)
cur = data.get("autoMemoryDirectory")
if cur == memdir:
    print(f"  conf  autoMemoryDirectory already set (settings.local.json)")
elif "autoMemoryDirectory" not in data:
    data["autoMemoryDirectory"] = memdir
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    print(f"  conf  autoMemoryDirectory = {memdir} (settings.local.json)")
else:
    print(f"  WARN  autoMemoryDirectory is {json.dumps(cur)} (expected {memdir}) — left alone")
PY

# 3) .gitignore — derived/local files that must not be committed. The entry must
#    live in the REPO's own .gitignore (a machine's global gitignore covering the
#    path doesn't protect collaborators' machines), so test for the literal line,
#    not effective ignore status; a redundant line under a broader pattern is fine.
#    `.claude/worktrees/` sits INSIDE the checkout, so without the entry every
#    worktree shows as untracked noise and a stray `git add -A` can reach into
#    one. `*.code-workspace` is generated per-topic and ephemeral (§1); a tracked
#    copy would churn and conflict across the very sessions it exists to show.
#    A repo that moved its worktrees (the worktree-root setting, TD-101) gets that
#    directory ignored too; `.claude/worktrees/` stays, since `claude --worktree` uses it.
wt_ign=""
if wt_root="$(python3 "$SRC/files/scripts/cadence_config.py" get worktree-root --repo "$TARGET" 2>/dev/null)" \
   && [ -n "$wt_root" ] && [ "$wt_root" != ".claude/worktrees" ]; then
    wt_ign="$wt_root/"
fi
for ign in "docs/session_index.md" ".claude/settings.local.json" ".claude/worktrees/" "*.code-workspace" ${wt_ign:+"$wt_ign"}; do
    if grep -qxF "$ign" "$TARGET/.gitignore" 2>/dev/null; then
        echo "  conf  $ign already in .gitignore"
    else
        [ -s "$TARGET/.gitignore" ] && [ -n "$(tail -c 1 "$TARGET/.gitignore" 2>/dev/null)" ] && echo >> "$TARGET/.gitignore"
        echo "$ign" >> "$TARGET/.gitignore"
        echo "  conf  $ign added to .gitignore"
    fi
done
# -------------------------------------------------------------------------------

# Lock source: normalized anonymous-https origin URL (plan P2 / TD-2). Credentials
# are STRIPPED — the lock is committed to every consumer's history — and ssh forms
# become https so the nudge's staleness ls-remote never depends on this clone's auth.
SOURCE_URL="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
SOURCE_URL="$(python3 - "$SOURCE_URL" <<'PY'
import re, sys
u = sys.argv[1].strip()
out = ""
if u:
    m = re.fullmatch(r"(?:ssh://)?git@([\w.-]+)(?::\d+)?[:/](.+?)(?:\.git)?/?", u)
    if m:  # ssh port (if any) dropped — the https host serves the web UI/API
        out = f"https://{m.group(1)}/{m.group(2)}"
    else:
        m = re.fullmatch(r"https?://(?:[^@/]+@)?([\w.-]+(?::\d+)?)/(.+?)(?:\.git)?/?", u)
        if m:
            out = f"https://{m.group(1)}/{m.group(2)}"
print(out)
PY
)"
# No hardcoded fallback: an empty source disables the consumer's staleness check
# (a safe no-op) — better than committing a wrong upstream claim for a fork.
if [ -z "$SOURCE_URL" ]; then
    echo "  WARN  could not derive an anonymous https URL from this clone's origin — lock 'source:' left empty (staleness check disabled for this consumer)"
fi

LOCK="$TARGET/docs/cadence-sync.lock"
{
    echo "# Written by ShiftLead/agent-cadence sync.sh — do not edit by hand."
    echo "source: $SOURCE_URL"
    echo "commit: ${SHA}${DIRTY}"
    # TD-035: the last commit that changed what sync ships — the staleness line compares
    # this, so an upstream commit touching only the ledger or CLAUDE.md is not "behind"
    echo "files_commit: $(git -C "$SRC" log -1 --format=%H HEAD -- files/ sync.sh 2>/dev/null)${DIRTY}"
    echo "synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    # TD-8: sha256 per SYNC file, hashed from THIS clone's working tree — the
    # exact bytes the cp above installed (matters when the source is +dirty).
    # `sync.sh --verify <target>` reads these to distinguish local drift from
    # an upstream upgrade.
    # TD-057: plus the mode as git sees it (755 / 644), so --verify catches a lost +x.
    # TD-072: an opted-out file is not locked; its line says what was left out, and why
    while IFS=$'\t' read -r p w; do if [ -n "$p" ]; then echo "opted-out: $p — $w"; fi; done <<< "$OPTOUT_SYNC"
    (cd "$SRC/files" && python3 - "${SHIP_FILES[@]}" <<'PY'
import hashlib, os, sys
for p in sys.argv[1:]:
    with open(p, "rb") as f:
        mode = "755" if os.stat(p).st_mode & 0o100 else "644"
        print(f"file: {p} {hashlib.sha256(f.read()).hexdigest()} {mode}")
PY
    )
} > "$LOCK.tmp"
# Keep the old lock when only the synced: timestamp would change — a re-sync
# that changed nothing must be a true no-op (so `git status` reads clean and
# sync-all's up-to-date detection works).
if [ -f "$LOCK" ] && diff -q <(grep -v '^synced:' "$LOCK") <(grep -v '^synced:' "$LOCK.tmp") >/dev/null 2>&1; then
    rm -f "$LOCK.tmp"
    echo "  lock  docs/cadence-sync.lock unchanged"
else
    mv "$LOCK.tmp" "$LOCK"
    echo "  lock  docs/cadence-sync.lock"
fi

# --- the repo's post-sync step (TD-113, cadence §9.18) ----------------------------------------
# A repo whose own files must follow the synced ones (ShiftLead's wheel copy of ledgerboard.py,
# held byte-equal to scripts/ledgerboard.py by its tests) names the command in its
# docs/cadence.toml as post-sync; sync runs it here, from the repo root, after every file and
# the lock are written, so sync-all commits its changes in the same sync commit. The command is
# the repo's (its own file only — never env or the machine's, cadence_config.py REPO_KEYS);
# this script only runs it. A failure fails the sync, before registration, with its output.
# get exits 1 for an unset key; 2 when docs/cadence.toml cannot be read — then, as with the
# opt-outs read from the same file (Adoption checklist step 9), a WARN and the sync goes on:
# whatever post-sync the file may name is not run, and the WARN says so.
post_rc=0
post_sync="$(python3 "$SRC/files/scripts/cadence_config.py" get post-sync --repo "$TARGET" 2>&1)" || post_rc=$?
# an exit 1 that said something is not "unset" (a traceback exits 1 too): the WARN below names it
if [ "$post_rc" -gt 1 ] || { [ "$post_rc" = 1 ] && [ -n "$post_sync" ]; }; then
    echo "  WARN  post-sync not run: ${post_sync#cadence_config: } — fix docs/cadence.toml and re-run sync.sh if it names one"
fi
[ "$post_rc" = 0 ] || post_sync=""
if [ -n "$post_sync" ]; then
    echo "  post  $post_sync (post-sync, docs/cadence.toml)"
    if ! (cd "$TARGET" && bash -c "$post_sync" </dev/null 2>&1 | sed 's/^/        /'); then
        echo "ERROR: post-sync failed — '$post_sync' (docs/cadence.toml) exited non-zero; the files above are written, the sync is not done" >&2
        exit 1
    fi
fi

# --- machine registry (plan 2026-08-10 P1) -------------------------------------
# Register the target's MAIN checkout root in this machine's roster so
# machine-scope views (guard check #6, nudge --report, /attention) can find its
# board. LAST mutating step by design: sync.sh's output is sometimes piped
# (sync-all.sh does) and a SIGPIPE death mid-script must never leave a repo
# registered whose file-copy/lock write didn't complete; the converse
# (synced-but-unregistered) is tolerated by all readers. Path-resolution spec:
# cadence.md §Machine scope — keep sync-all.sh, guard check #6, and the report
# mode in step with any change here.
# DEV_CADENCE_REG_DIR isolates ONLY the roster (TD-029): an ad-hoc run sets it to a temp
# dir and keeps gh's credentials, which live under XDG_CONFIG_HOME.
REG_DIR="${DEV_CADENCE_REG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dev-cadence}"
REG="$REG_DIR/repos.txt"
REG_ROOT="$(realpath "$CLONE_ROOT" 2>/dev/null || echo "$CLONE_ROOT")"
# TD-068: never write a temp-dir repo into a roster that is not itself in a temp dir. A test
# or review run that forgot DEV_CADENCE_REG_DIR put /tmp fixtures on the real roster twice
# (2026-08-10, 2026-09-23), and every roster reader then polled the dead lines. Temp roots:
# $CADENCE_TEMP_ROOTS (colon-separated; the suite's override), else $TMPDIR, /tmp, /var/tmp.
# Parity (§7): this function is copied verbatim into sync.sh and sync-all.sh;
# tests/test_reg_dir.sh runs both.
under_temp() {
    local p t roots
    p="$(realpath "$1" 2>/dev/null || realpath -m "$1" 2>/dev/null || echo "$1")"
    IFS=: read -r -a roots <<< "${CADENCE_TEMP_ROOTS:-${TMPDIR:-/tmp}:/tmp:/var/tmp}"
    for t in "${roots[@]}"; do
        [ -n "$t" ] || continue
        t="$(realpath "$t" 2>/dev/null || realpath -m "$t" 2>/dev/null || echo "$t")"; t="${t%/}"
        [ -n "$t" ] || continue          # a root of "/" would call every path temporary
        case "$p/" in "$t"/*) return 0 ;; esac
    done
    return 1
}
# Registration failure must never break the real work above — every path below
# (mkdir, lock, append) degrades to a WARN + skip, not an abort under -e.
if under_temp "$REG_ROOT" && ! under_temp "$REG_DIR"; then
    echo "  WARN  $REG_ROOT is in a temp dir and $REG is not — registration skipped (a fixture on the"
    echo "        machine roster is polled by every roster reader). Set DEV_CADENCE_REG_DIR=\$(mktemp -d) for a test run."
elif ! mkdir -p "$REG_DIR" 2>/dev/null; then
    echo "  WARN  cannot create $REG_DIR — registration skipped; re-run sync.sh to retry"
elif grep -qxF "$REG_ROOT" "$REG" 2>/dev/null; then
    echo "  reg   already in machine registry ($REG)"
elif command -v flock >/dev/null 2>&1; then
    # flock'd check-then-append (fd 9 = the registry itself, O_APPEND); a lock
    # timeout skips registration rather than corrupting — re-run to retry.
    if ( flock -w 5 9 && { grep -qxF "$REG_ROOT" "$REG" 2>/dev/null || printf '%s\n' "$REG_ROOT" >&9; } ) 9>>"$REG"; then
        echo "  reg   $REG_ROOT -> machine registry ($REG)"
    else
        echo "  WARN  could not lock/append $REG — registration skipped; re-run sync.sh to retry"
    fi
else
    # no flock on this machine (plan: degrade — read-time dedupe hides a racing duplicate)
    if printf '%s\n' "$REG_ROOT" >>"$REG" 2>/dev/null; then
        echo "  reg   $REG_ROOT -> machine registry ($REG)"
    else
        echo "  WARN  could not append to $REG — registration skipped; re-run sync.sh to retry"
    fi
fi
# -------------------------------------------------------------------------------

cat <<EOF

Next steps in the target repo:
  1. git -C "$TARGET" diff        # review what changed; then branch + PR it
     (the git hook shims + autoMemoryDirectory + gitignore entries were set up
      above — heed any WARN lines; re-run sync.sh on each additional machine's
      clone, since those two are per-clone/per-machine)
  2. First-time setup only (adoption checklist, docs/cadence.md):
     - if .claude/settings.json already existed, add the ONE SessionStart
       line from files/.claude/settings.json (it calls scripts/cadence_hooks.sh,
       which carries the whole set — heed the WARN above if it is missing)
     - CLAUDE.md session-hygiene section + doc-map rows
     - repo settings: squash-only + auto-delete merged heads —
       scripts/adopt_repo_settings.sh --check (then --apply; TD-034)
     - optional: daily cron -> scripts/nudge_user_attention.py --board <board>
       (channel: NUDGE_COMMAND, or TELEGRAM_BOT_TOKEN+TELEGRAM_CHAT_ID)
     - optional: */10 cron -> scripts/generate_session_index.sh (atomic write
       to the gitignored docs/session_index.md)
EOF
