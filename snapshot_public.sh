#!/usr/bin/env bash
# snapshot_public.sh [--seed] <out-dir> — build the public snapshot of this repo (TD-090, ADR 2026-10-26).
#
# --seed (TD-190, the ADR's Amendment 2026-10-28) builds the cut-over's first commit instead: the
# repo as it dogfoods itself, docs/ and all, minus docs/plans/, the ledger's archive and the private
# accept list, with each file under docs/seed/ laid over its path (the public repo's docs/cadence.toml,
# its accept list, the archive's README), the board trimmed to its open items, and the gate run with
# that public accept list.
#
# Before the cut-over (TD-191) the canonical repo was private, and a release was published as one
# commit of a separate public repo (ShiftLead/agent-cadence) sharing no history with it; --seed
# built this repo's first commit that way. This script writes that tree:
# every file of HEAD (`git archive`, so only what is committed, never the working tree) except
# PRIVATE below, with a note under the README's title, the repo's address made the public one's and
# its private spans dropped (both below), then runs the scrub gate over it.
#
# <out-dir> is a new or empty directory, or a clean clone of the public repo (no untracked file
# either) — then every file it tracks is replaced, an ignored one stays, and `git -C <out-dir> status`
# shows the release as a diff to commit. A clone that shares a commit with this repo is refused:
# pushing it would publish this repo's history; so is an out-dir inside this repo or holding it.
# Nothing is committed or pushed; that, and the repo itself, are the person's (the ADR's `gh` steps).
#
# The gate is `cadence_layer.py --publish-check --accept ACCEPT` (the snapshot's own copy, TD-189)
# over every file written, reading this machine's roster and its `publish-names` (cadence.md §9.18) —
# the names to flag live only in the machine's file, which is why this runs here and no test can hold
# them. A finding that is meant to be public is accepted by a line of ACCEPT (`<path-glob>
# <finding-glob>[ :: <line-glob>]`, fnmatch, `#` comments); that file lives in docs/, which never goes
# public. An accept line that matched nothing is named, so the list cannot rot quietly. A relative
# markdown link to a file the tree lacks is a finding too (a link into docs/ goes dead the moment it
# is published).
#
# Exit 0 the tree is written and the gate is clean; 1 written, with findings to judge (scrub them
# here, or accept them); 2 refused before anything was written, or the gate could not run or its
# output could not be read (a crash never reads as clean). Tooling; never synced.
set -euo pipefail
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "snapshot_public: $*" >&2; exit 2; }
seed=0; [ "${1:-}" = --seed ] && { seed=1; shift; }
if [ $seed = 0 ]; then
    PRIVATE=(docs CLAUDE.md .claude .github .shiftlead.yml)
    NOTE='> *dev-cadence, published as agent-cadence.* Each release here is one snapshot commit of the canonical tree, which is kept elsewhere; the tool, its commands and its docs keep the name dev-cadence.'
    ACCEPT="${SNAPSHOT_ACCEPT:-$DC/docs/publish-accept.txt}"
else
    # the cut-over's seed (TD-190): the repo as it dogfoods itself — its ledger, board, briefs, team,
    # settings and CLAUDE.md — minus what stays private for good, with docs/seed/'s files laid over
    PRIVATE=(docs/plans docs/ledger/archive docs/publish-accept.txt docs/seed)
    NOTE='> *dev-cadence, published as agent-cadence.* This is the canonical repo; its history before the cut-over is kept privately. The tool, its commands and its docs keep the name dev-cadence.'
    ACCEPT="${SNAPSHOT_ACCEPT:-$DC/docs/seed/docs/publish-accept.txt}"
fi

out="${1:-}"
[ -n "$out" ] && [ $# -eq 1 ] || die "usage: snapshot_public.sh [--seed] <out-dir>"
here="$(cd "$DC" && pwd -P)"
out="$(realpath -m -- "$out")"
case "$out/" in "$here/"*) die "$out is inside this repo";; esac
case "$here/" in "$out/"*) die "$out holds this repo";; esac
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ -e "$out/.git" ]; then
    [ "$(git -C "$out" rev-parse --show-toplevel 2>/dev/null)" = "$out" ] || die "$out/.git is not the top of a git repo"
    [ -z "$(git -C "$out" status --porcelain --untracked-files=all)" ] \
        || die "$out has uncommitted or untracked changes — commit or remove them first"
    roots=$(git -C "$out" rev-list --max-parents=0 --all) || die "cannot list $out's root commits"
    for root in $roots; do
        git -C "$DC" cat-file -e "$root^{commit}" 2>/dev/null \
            && die "$out shares commit ${root:0:12} with this repo — pushing it would publish this repo's history"
    done
    # only what the clone tracks: an ignored file (a .env) is the person's, and stays ignored
    git -C "$out" ls-files -z > "$TMP/tracked" || die "cannot list $out's files"
    (cd "$out" && xargs -0 -r rm -f -- < "$TMP/tracked")
    find "$out" -mindepth 1 -depth -type d -empty ! -path "$out/.git" ! -path "$out/.git/*" -delete
elif [ -e "$out" ] && [ -n "$(ls -A "$out")" ]; then
    die "$out is neither empty nor a git repo"
fi
mkdir -p "$out"

head=$(git -C "$DC" rev-parse HEAD)
excl=(); for p in "${PRIVATE[@]}"; do excl+=(":(exclude)$p"); done
git -C "$DC" archive --format=tar -o "$TMP/snap.tar" HEAD -- . "${excl[@]}"
tar -x -C "$out" -f "$TMP/snap.tar"
mapfile -t written < <(tar -tf "$TMP/snap.tar" | grep -v '/$' | LC_ALL=C sort)
if [ $seed = 1 ]; then
    # docs/seed/<path> replaces <path>: the public repo's own settings and accept list, the archive's README
    git -C "$DC" archive --format=tar -o "$TMP/overlay.tar" HEAD docs/seed/ 2>/dev/null \
        || die "HEAD has no docs/seed/ — the seed's own files (cadence.toml, the accept list, the archive README)"
    tar -x -C "$TMP" -f "$TMP/overlay.tar"
    (cd "$TMP/docs/seed" && find . -type f -printf '%P\n') | LC_ALL=C sort > "$TMP/overlay"
    while IFS= read -r rel; do mkdir -p "$out/$(dirname "$rel")"; cp "$TMP/docs/seed/$rel" "$out/$rel"; done < "$TMP/overlay"
    mapfile -t written < <(printf '%s\n' "${written[@]}" | cat - "$TMP/overlay" | LC_ALL=C sort -u)
    # the archive's README names the last private id: the counter's LAST on origin, else the highest
    # id this tree files (an id taken but never filed is still private, and never handed out again)
    last_id=$(git -C "$DC" show origin/cadence/ledger-ids:LAST 2>/dev/null | tr -dc 0-9 || true)
    [ -n "$last_id" ] || last_id=$(git -C "$DC" ls-tree -r --name-only HEAD docs/ledger | sed -n 's|.*/TD-0*\([0-9][0-9]*\)\.md$|\1|p' | sort -n | tail -1)
    [ -n "$last_id" ] || die "no last ledger id to name in the archive's README"
    ar="$out/docs/ledger/archive/README.md"
    [ -f "$ar" ] && sed -i "s/TD-@LAST@/TD-$last_id/" "$ar"
    # a Blocked by naming an entry the seed does not carry names one archived privately, so it blocks
    # nothing: the id goes from the field, its note with it (`TD-5 (landed)`); a field left with no
    # item goes whole, its prose with it, since nothing blocks the entry any more
    python3 - "$out/docs/ledger" <<'EOF2' || die "the ledger's blockers could not be rewritten — the tree is written, but unchecked"
import os, re, sys
d = sys.argv[1]
if os.path.isdir(d):
    carried = {int(m[1]) for f in os.listdir(d) if (m := re.fullmatch(r"TD-0*(\d+)\.md", f))}
    for f in sorted(os.listdir(d)):
        if not re.fullmatch(r"TD-\d+\.md", f):
            continue
        path = os.path.join(d, f)
        lines = open(path, encoding="utf-8").read().split("\n")
        for i, line in enumerate(lines):
            m = re.fullmatch(r"\*\*Blocked by:\*\* (.*)", line)
            if not m:
                continue
            items, dash, prose = m[1].partition(" — ")
            parts = [y.strip() for y in re.split(r",(?![^()]*\))", items)]   # a comma inside (…) is the item's
            def private(x):
                t = re.match(r"TD-0*(\d+)(?![\w#-])", x)
                return bool(t) and int(t[1]) not in carried
            kept = [x for x in parts if not private(x)]
            if len(kept) == len(parts):
                continue
            lines[i] = f"**Blocked by:** {', '.join(kept)}{dash}{prose}" if kept else None
        lines = [x for x in lines if x is not None]
        open(path, "w", encoding="utf-8").write("\n".join(lines))
EOF2
    # a link into docs/plans/ (private for good) keeps its text and names the plan, never a dead link
    python3 - "$out" "${written[@]}" <<'EOF2' || die "the plan links could not be rewritten — the tree is written, but unchecked"
import os, re, sys
out, files = sys.argv[1], sys.argv[2:]
LINK = re.compile(r"\[([^\]]+)\]\(((?:\.\./)*(?:docs/)?plans/([^)#\s]+?)\.md)(#[^)\s]*)?\)")
SPAN = re.compile(r"(`+)(?!`).*?(?<!`)\1(?!`)")
carried = set(files)
for rel in files:
    if not rel.endswith(".md"):
        continue
    path = f"{out}/{rel}"
    text = open(path, encoding="utf-8", newline="").read()
    def sub(m):
        target = os.path.normpath(os.path.join(os.path.dirname(rel), m[2]))
        if not target.startswith("docs/plans/") or target in carried:   # docs/plans/README.md is the seed's own
            return m[0]
        slug = f"dev-cadence's private plan *{m[3]}*"
        # link text that is the path itself is replaced, so the dead path is not left in the text
        return slug if m[1].strip("`").endswith(".md") or "plans/" in m[1] else f"{m[1]} ({slug})"
    def outside_spans(t):   # a link in a code span is an example: left as written
        out_, last = [], 0
        for s in SPAN.finditer(t):
            out_.append(LINK.sub(sub, t[last:s.start()])); out_.append(s[0]); last = s.end()
        return "".join(out_) + LINK.sub(sub, t[last:])
    new = outside_spans(text)
    if new != text:
        open(path, "w", encoding="utf-8", newline="").write(new)
EOF2
    # the board carries its open items: a done one is this repo's history, kept privately
    if [ -f "$out/docs/user_attention.md" ]; then
        python3 - "$out/docs/user_attention.md" <<'EOF2' || die "the board could not be trimmed — the tree is written, but unchecked"
import re, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
out, skipping = [], False
for line in lines:
    if re.match(r"- \[[xX]\] ", line):
        skipping = True
        continue
    if skipping and line.startswith((" ", "\t")) and line.strip():
        continue   # a done item's continuation line goes with it
    skipping = False
    out.append(line)
open(path, "w", encoding="utf-8").write("\n".join(out))
EOF2
    fi
fi
[ -f "$out/README.md" ] || die "HEAD has no README.md"
python3 - "$out/README.md" "$NOTE" <<'EOF'
import sys
path, note = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().split("\n")
if not lines[0].startswith("# "):
    sys.exit("snapshot_public: README.md does not open with a title line")
lines[1:1] = ["", note]
open(path, "w", encoding="utf-8").write("\n".join(lines))
EOF
# the public tree names its own repo: every address of the private canonical repo becomes the public
# one's, and in a .md file a span marked `<!-- private: -->…<!-- :private -->` (true only of the
# private repo, such as needing a token to clone it) is dropped
python3 - "$out" "${written[@]}" <<'EOF' || die "the public tree could not be rewritten — it is written, but unchecked"
import re, sys
out, files = sys.argv[1], sys.argv[2:]
PRIVATE_REPO = "ShiftLead/" + "dev-cadence"   # in pieces, so the published copy of this line is not rewritten
SPAN = re.compile(r"<!-- private: -->.*?<!-- :private -->[ \t]*", re.S)
for rel in files:
    path = f"{out}/{rel}"
    try:
        text = open(path, encoding="utf-8", newline="").read()   # newline="": a CRLF file keeps its CRs
    except (UnicodeDecodeError, OSError):
        continue
    new = re.sub(re.escape(PRIVATE_REPO) + r"(?![\w-])", "ShiftLead/agent-cadence", text)
    if rel.endswith(".md"):
        new = SPAN.sub("", new)
        if "<!-- private:" in new or "<!-- :private -->" in new:
            sys.exit(f"snapshot_public: {rel} has a private span that does not close")
    if new != text:
        open(path, "w", encoding="utf-8", newline="").write(new)
EOF

ACCEPT="$(realpath -m -- "$ACCEPT")"   # the gate runs inside $out: a relative path would be read from there
[ -f "$ACCEPT" ] || { echo "note: no accept list at $ACCEPT — every finding is shown"; ACCEPT="$TMP/none"; : > "$ACCEPT"; }
set +e
(cd "$out" && PYTHONDONTWRITEBYTECODE=1 python3 files/scripts/cadence_layer.py --publish-check --accept "$ACCEPT" "${written[@]}") > "$TMP/gate" 2>&1
grc=$?
set -e
echo "wrote ${#written[@]} files of ${head:0:12} to $out"
cat "$TMP/gate"
# the gate is the snapshot's own copy: one that crashed, or that ends without its `gate:` line, is no clean bill
last=$(tail -n 1 "$TMP/gate")
[ "$grc" -le 1 ] || die "the gate could not run (exit $grc) — the tree is written, but unchecked"
grep -qE '^gate: [0-9]+ findings? to judge, [0-9]+ accepted' <<< "$last" \
    || die "the gate ended with a line this script cannot read ($last) — the tree is written, but unchecked"
exit "$grc"
