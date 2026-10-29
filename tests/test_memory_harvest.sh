#!/usr/bin/env bash
# memory_harvest.py — the memory harvest's inventory and record (TD-125 slice 1,
# docs/plans/2026-10-23-memory-harvest.md). Offline and fixture-driven: the roster and the
# machine's cadence.toml live under AGENT_CADENCE_REG_DIR, the repos are temp clones of temp bare
# origins, and HOME/XDG_CONFIG_HOME point into the temp dir.
# Asserts: no roster is exit 2; frontmatter type at the top level, under metadata:, and absent;
# MEMORY.md and README.md left out; each `where` (committed, edited, not-pulled, not-on-origin,
# untracked-dir, origin-unread); a nested docs repo read against its own origin; autoMemoryDirectory
# honoured only while agents lists claude; a shared directory read once; a gone repo named; the
# inventory writes nothing in a roster repo; record writes the table beside the own layer, is
# re-read as judged, shows a changed memory again, keeps the rest of the file, and refuses an
# unknown repo, memory, verdict or a bad --where, and runs nowhere without an own layer; from a
# roster repo's checkout, clone names the layer clone and refuses one off its default branch or dirty.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DC/files/scripts/memory_harvest.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CADENCE_AGENTS
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
mh() { python3 "$SCRIPT" "$@"; }
TODAY=$(date +%F)

# 1. no roster: exit 2, named
out=$(mh inventory 2>&1); rc=$?
[ "$rc" = 2 ] && grep -qF "no roster at $AGENT_CADENCE_REG_DIR/repos.txt" <<< "$out" && ok "1 no roster: exit 2, named" || bad "1 rc=$rc '$out'"

# a repo with a bare origin: $1 name; memories committed and pushed from $2 (a dir of files)
mkrepo() {
  git init -q --bare -b main "$TMP/origins/$1.git"
  git clone -q "$TMP/origins/$1.git" "$TMP/repos/$1" 2>/dev/null
  mkdir -p "$TMP/repos/$1/docs/claude-memory"
}
mkdir -p "$TMP/origins" "$TMP/repos"
mkrepo alpha
M="$TMP/repos/alpha/docs/claude-memory"
printf -- '---\nname: merge-rule\ndescription: "squash every PR"\ntype: feedback\n---\nAlways squash.\n' > "$M/feedback_merge.md"
printf -- '---\nname: meta-typed\ndescription: a metadata type\nmetadata:\n  type: project\n---\nbody\n' > "$M/project_meta.md"
printf 'no frontmatter at all\n' > "$M/plain.md"
printf -- '---\nname: to-edit\ndescription: edited later\ntype: user\n---\nv1\n' > "$M/user_edit.md"
printf -- '- [x](x.md)\n' > "$M/MEMORY.md"
printf 'this directory holds memories\n' > "$M/README.md"
git -C "$TMP/repos/alpha" add -A && git -C "$TMP/repos/alpha" commit -qm mem && git -C "$TMP/repos/alpha" push -q origin main 2>/dev/null
# not-pulled: pushed from a second clone, fetched (never pulled) into alpha
git clone -q "$TMP/origins/alpha.git" "$TMP/alpha2" 2>/dev/null
printf -- '---\nname: remote-only\ndescription: merged elsewhere\ntype: feedback\n---\nx\n' > "$TMP/alpha2/docs/claude-memory/feedback_remote.md"
git -C "$TMP/alpha2" add -A && git -C "$TMP/alpha2" commit -qm r && git -C "$TMP/alpha2" push -q origin main 2>/dev/null
git -C "$TMP/repos/alpha" fetch -q origin
# edited and not-on-origin
printf -- '---\nname: to-edit\ndescription: edited later\ntype: user\n---\nv2\n' > "$M/user_edit.md"
printf -- '---\nname: local-only\ndescription: never committed\ntype: feedback\n---\ny\n' > "$M/feedback_local.md"

# beta shares alpha's directory through autoMemoryDirectory (a constellation, §9.16)
mkrepo beta
mkdir -p "$TMP/repos/beta/.claude"
printf '{"autoMemoryDirectory": "%s"}\n' "$M" > "$TMP/repos/beta/.claude/settings.local.json"
# gamma: agents leaves out claude, so its autoMemoryDirectory is not Claude Code's to honour
mkrepo gamma
mkdir -p "$TMP/repos/gamma/.claude"
printf '{"autoMemoryDirectory": "%s"}\n' "$M" > "$TMP/repos/gamma/.claude/settings.local.json"
printf 'agents = "codex"\n' > "$TMP/repos/gamma/docs/cadence.toml"
printf -- '---\nname: g\ndescription: gamma own\ntype: feedback\n---\ng\n' > "$TMP/repos/gamma/docs/claude-memory/feedback_g.md"
# delta: memory outside any git repo; epsilon: memory in a nested docs repo with its own origin
mkrepo delta
mkdir -p "$TMP/loose" "$TMP/repos/delta/.claude"
printf -- '---\nname: loose\ndescription: d\ntype: feedback\n---\nd\n' > "$TMP/loose/feedback_loose.md"
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/loose" > "$TMP/repos/delta/.claude/settings.json"
mkrepo epsilon
git init -q --bare -b main "$TMP/origins/eps-docs.git"
git clone -q "$TMP/origins/eps-docs.git" "$TMP/repos/epsilon/eps-docs" 2>/dev/null
mkdir -p "$TMP/repos/epsilon/eps-docs/claude-memory" "$TMP/repos/epsilon/.claude"
printf -- '---\nname: nested\ndescription: n\ntype: feedback\n---\nn\n' > "$TMP/repos/epsilon/eps-docs/claude-memory/feedback_nested.md"
git -C "$TMP/repos/epsilon/eps-docs" add -A && git -C "$TMP/repos/epsilon/eps-docs" commit -qm n && git -C "$TMP/repos/epsilon/eps-docs" push -q origin main 2>/dev/null
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/repos/epsilon/eps-docs/claude-memory" > "$TMP/repos/epsilon/.claude/settings.local.json"
# zeta: no origin at all
git init -q -b main "$TMP/repos/zeta"; mkdir -p "$TMP/repos/zeta/docs/claude-memory"
printf -- '---\nname: z\ndescription: z\ntype: feedback\n---\nz\n' > "$TMP/repos/zeta/docs/claude-memory/feedback_z.md"
for r in alpha beta gamma delta epsilon zeta; do echo "$TMP/repos/$r"; done > "$AGENT_CADENCE_REG_DIR/repos.txt"
echo "$TMP/repos/gone" >> "$AGENT_CADENCE_REG_DIR/repos.txt"

snap() { for r in alpha epsilon/eps-docs; do git -C "$TMP/repos/$r" for-each-ref --format='%(refname) %(objectname)'; GIT_OPTIONAL_LOCKS=0 git -C "$TMP/repos/$r" status --porcelain; stat -c %Y "$(git -C "$TMP/repos/$r" rev-parse --absolute-git-dir)/index" 2>/dev/null; done; }
before=$(snap)
J=$(mh inventory --json); rc=$?
q() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$J" "$1"; }
mem() { q "next((m['$2'] for r in d['repos'] if r['repo']=='$1' for m in r['memories'] if m['file']=='$3'), 'MISSING')"; }
[ "$rc" = 0 ] && ok "2 inventory --json exits 0 with no layer set" || bad "2 rc=$rc"
[ "$(mem alpha type feedback_merge.md)" = feedback ] && [ "$(mem alpha type project_meta.md)" = project ] && [ "$(mem alpha type plain.md)" = "" ] \
  && [ "$(mem alpha description feedback_merge.md)" = "squash every PR" ] && ok "3 type at the top level, under metadata:, and absent; quotes stripped" \
  || bad "3 $(mem alpha type feedback_merge.md)/$(mem alpha type project_meta.md)/$(mem alpha type plain.md)/$(mem alpha description feedback_merge.md)"
[ "$(mem alpha file MEMORY.md)" = MISSING ] && [ "$(mem alpha file README.md)" = MISSING ] && ok "4 MEMORY.md and README.md are not memories" || bad "4"
[ "$(mem alpha where feedback_merge.md)" = committed ] && [ "$(mem alpha where user_edit.md)" = edited ] \
  && [ "$(mem alpha where feedback_remote.md)" = not-pulled ] && [ "$(mem alpha where feedback_local.md)" = not-on-origin ] \
  && ok "5 committed, edited, not-pulled (origin as last fetched), not-on-origin" \
  || bad "5 $(mem alpha where feedback_merge.md) $(mem alpha where user_edit.md) $(mem alpha where feedback_remote.md) $(mem alpha where feedback_local.md)"
[ "$(mem alpha sha256 user_edit.md)" = "$(sha256sum "$M/user_edit.md" | cut -d' ' -f1)" ] && ok "6 the disk copy is the text judged (its sha256)" || bad "6"
[ "$(q "[r['note'] for r in d['repos'] if r['repo']=='beta'][0]")" = "shares its memory directory with alpha: read there" ] \
  && [ "$(q "len([r for r in d['repos'] if r['repo']=='beta'][0]['memories'])")" = 0 ] && ok "7 a shared directory is read once" || bad "7 $(q "[r['note'] for r in d['repos'] if r['repo']=='beta']")"
[ "$(mem gamma file feedback_g.md)" = feedback_g.md ] && [ "$(q "[r['source'] for r in d['repos'] if r['repo']=='gamma'][0]")" = default ] \
  && ok "8 agents without claude: docs/claude-memory, not autoMemoryDirectory" || bad "8 $(q "[r for r in d['repos'] if r['repo']=='gamma']")"
[ "$(mem delta where feedback_loose.md)" = untracked-dir ] && grep -q "outside the repo" <<< "$(q "[r['note'] for r in d['repos'] if r['repo']=='delta'][0]")" \
  && ok "9 a directory outside any repo: untracked-dir, said" || bad "9 $(mem delta where feedback_loose.md)"
[ "$(mem epsilon where feedback_nested.md)" = committed ] && ok "10 a nested docs repo is read against its own origin" || bad "10 $(mem epsilon where feedback_nested.md)"
[ "$(mem zeta where feedback_z.md)" = origin-unread ] && grep -q "no origin/main in the clone" <<< "$(q "[r['note'] for r in d['repos'] if r['repo']=='zeta'][0]")" \
  && ok "11 no origin: origin-unread, never not-on-origin" || bad "11 $(mem zeta where feedback_z.md)"
grep -q "not on this machine" <<< "$(q "[r['note'] for r in d['repos'] if r['repo']=='gone'][0]")" && ok "12 a gone roster path is named" || bad "12"
[ "$(q "d['record']")" = None ] && grep -q "no own layer" <<< "$(q "d['record_note']")" && ok "13 no layer: no record, said" || bad "13 $(q "d['record_note']")"
mh inventory >/dev/null
[ "$before" = "$(snap)" ] && ok "14 the inventory writes nothing in a roster repo (refs, status, index)" || bad "14 a roster repo changed"

# 15. record with no own layer: refused; a pinned layer alone is not one's own
out=$(mh record alpha feedback_merge.md covered 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "no own layer" <<< "$out" && ok "15 record without a layer: exit 1, said" || bad "15 rc=$rc '$out'"
out=$(mh stamp 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "no own layer" <<< "$out" && ok "15a stamp without a layer: exit 1, said" || bad "15a rc=$rc '$out'"
LAYER="$TMP/layer"; git init -q -b main "$LAYER"; echo "# rules" > "$LAYER/cadence-personal.md"
git -C "$LAYER" add -A && git -C "$LAYER" commit -qm l && git -C "$LAYER" tag v1
printf '[[layers]]\npath = "%s/cadence-personal.md"\nref = "v1"\n' "$LAYER" > "$AGENT_CADENCE_REG_DIR/cadence.toml"
out=$(mh record alpha feedback_merge.md covered 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "no own layer" <<< "$out" && ok "15b only a pinned layer: not one's own, refused" || bad "15b rc=$rc '$out'"
printf '[[layers]]\npath = "%s/cadence-personal.md"\n' "$LAYER" >> "$AGENT_CADENCE_REG_DIR/cadence.toml"
REC="$LAYER/memory-harvest.md"

# 16. record writes the table beside the own layer; inventory reads it back as judged
out=$(mh record alpha feedback_merge.md covered --where "cadence §4.6" 2>&1); rc=$?
SHA=$(sha256sum "$M/feedback_merge.md" | cut -c1-12)
[ "$rc" = 0 ] && grep -qxF "| alpha | feedback_merge.md | $SHA | covered | $TODAY | cadence §4.6 |" "$REC" \
  && grep -qxF "| Repo | Memory | sha | Verdict | Judged | Where |" "$REC" && grep -q "never edit it by" "$REC" \
  && ok "16 record writes the row, header and preamble beside the own layer" || bad "16 rc=$rc '$out' $(cat "$REC" 2>&1)"
mh record alpha plain.md repo-local >/dev/null 2>&1
grep -qxF "| alpha | plain.md | $(sha256sum "$M/plain.md" | cut -c1-12) | repo-local | $TODAY | — |" "$REC" && ok "16b --where defaults to —" || bad "16b $(cat "$REC")"
out=$(mh inventory)
grep -qF "feedback_merge.md  [feedback] $SHA committed · judged covered $TODAY" <<< "$out" && grep -qF "record: $REC" <<< "$out" \
  && grep -qE "memories in 7 roster repos, [0-9]+ to judge" <<< "$out" && ok "17 inventory shows the judged memory and the record" || bad "17 '$out'"
# 18. a memory whose text moved is shown again, with its last verdict
echo "more" >> "$M/feedback_merge.md"
grep -qF "changed since judged covered $TODAY" <<< "$(mh inventory)" && ok "18 a changed memory is shown again with its last verdict" || bad "18"
# 19. re-judging replaces the row; the rest of the file is kept; rows sorted
printf '\nA note under the table.\n' >> "$REC"
mh record alpha feedback_merge.md promote --where TD-900 >/dev/null 2>&1
[ "$(grep -c '| alpha | feedback_merge.md |' "$REC")" = 1 ] && grep -qF "| promote | $TODAY | TD-900 |" "$REC" && grep -qxF "A note under the table." "$REC" \
  && [ "$(grep '^| alpha' "$REC" | cut -d'|' -f3 | tr -d ' ' | tr '\n' ,)" = "feedback_merge.md,plain.md," ] \
  && ok "19 re-judging replaces the row, keeps the rest, sorts" || bad "19 $(cat "$REC")"
# 20. refusals
out=$(mh record nosuch x.md craft 2>&1); rc1=$?
out2=$(mh record alpha nosuch.md craft 2>&1); rc2=$?
mh record alpha plain.md maybe >/dev/null 2>&1; rc3=$?
mh record alpha plain.md craft --where "a | b" >/dev/null 2>&1; rc4=$?
[ "$rc1" = 1 ] && grep -q "no roster repo named nosuch" <<< "$out" && [ "$rc2" = 1 ] && grep -q "no memory nosuch.md in alpha" <<< "$out2" \
  && [ "$rc3" = 1 ] && [ "$rc4" = 1 ] && ok "20 unknown repo, memory, verdict, a | in --where: each exit 1" || bad "20 $rc1 $rc2 $rc3 $rc4"
# 21. a file the script did not make gets the table at its end, its text kept
rm "$REC"; printf '# my notes\n\nkept\n' > "$REC"
mh record alpha plain.md craft >/dev/null 2>&1
[ "$(head -1 "$REC")" = "# my notes" ] && grep -qxF kept "$REC" && grep -qF "| alpha | plain.md |" "$REC" && ok "21 an existing file keeps its text, the table appended" || bad "21 $(cat "$REC")"

mh record alpha project_meta.md covered --ref TD-1 >/dev/null 2>&1 && grep -qF "| alpha | project_meta.md |" "$REC" && grep -qF "| covered | $TODAY | TD-1 |" "$REC" \
  && ok "21b --ref, the plan's name, is --where" || bad "21b $(cat "$REC")"

# 22. a table line that does not parse is refused with its line, never dropped by a rewrite
cp "$REC" "$TMP/rec.good"
sed -i 's/| repo-local |/| Covered |/; s/| craft |/| Covered |/' "$REC"
bad_before=$(cat "$REC")
out=$(mh record alpha feedback_local.md craft 2>&1); rc=$?
out2=$(mh inventory 2>&1); rc2=$?
[ "$rc" = 1 ] && grep -qE "memory-harvest.md:[0-9]+: not a record row" <<< "$out" && [ "$bad_before" = "$(cat "$REC")" ] && [ "$rc2" = 2 ] \
  && ok "22 a hand-broken row: record exit 1 naming the line, inventory exit 2, the file untouched" || bad "22 rc=$rc/$rc2 '$out'"
# 23. a header a formatter padded is still the one table; a second table is refused
cp "$TMP/rec.good" "$REC"
sed -i 's/^| Repo | Memory | sha |/|  Repo  |  Memory  |  sha  |/; s/^|---|---|---|---|---|---|$/| :--- | --- | --- | --- | --- | --- |/' "$REC"
mh record alpha feedback_local.md craft >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(grep -cE '^\| *Repo' "$REC")" = 1 ] && [ "$(grep -c '| alpha | plain.md |' "$REC")" = 1 ] && grep -qF "| alpha | feedback_local.md |" "$REC" \
  && ok "23 a padded header: one table, rows kept, the new row in it" || bad "23 rc=$rc $(cat "$REC")"
printf '\n| Repo | Memory | sha | Verdict | Judged | Where |\n|---|---|---|---|---|---|\n' >> "$REC"
out=$(mh record alpha plain.md craft 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "2 record tables" <<< "$out" && ok "23b two tables: refused, named" || bad "23b rc=$rc '$out'"
cp "$TMP/rec.good" "$REC"

# 23c. record --stdin (TD-141): a batch in one call; the rest of a line is its where; blank and # lines skipped
out=$(printf '# batch 1\nalpha feedback_local.md repo-local follow-up alpha#12 (to write)\n\nalpha plain.md covered-wrong\n' | mh record --stdin 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qF "| alpha | feedback_local.md |" "$REC" && grep -qF "| repo-local | $TODAY | follow-up alpha#12 (to write) |" "$REC" \
  && grep -qF "| covered-wrong | $TODAY | — |" "$REC" && [ "$(grep -c '^recorded:' <<< "$out")" = 2 ] \
  && ok "23c record --stdin writes the batch, the line's rest as its where" || bad "23c rc=$rc '$out' $(cat "$REC")"
# 23d. one bad line refuses the whole batch, naming each; nothing written
before=$(cat "$REC")
out=$(printf 'alpha feedback_merge.md promote TD-9\nalpha nosuch.md craft\nalpha plain.md maybe\n' | mh record --stdin 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "no memory nosuch.md in alpha" <<< "$out" && grep -q "alpha plain.md: no verdict maybe" <<< "$out" \
  && grep -q "nothing recorded — 2 of 3 lines refused" <<< "$out" && [ "$before" = "$(cat "$REC")" ] \
  && ok "23d a bad line in a batch: nothing written, each refusal named" || bad "23d rc=$rc '$out'"
# 23e. a memory twice in one batch, a short line, an empty batch, and --stdin with arguments: refused
out1=$(printf 'alpha plain.md craft\nalpha plain.md covered\n' | mh record --stdin 2>&1); r1=$?
out2=$(printf 'alpha plain.md\n' | mh record --stdin 2>&1); r2=$?
out3=$(printf '# nothing\n' | mh record --stdin 2>&1); r3=$?
out4=$(echo | mh record alpha plain.md craft --stdin 2>&1); r4=$?
[ "$r1$r2$r3$r4" = 1111 ] && grep -q "judged twice in this batch" <<< "$out1" && grep -q "stdin line 1: want" <<< "$out2" \
  && grep -q "read no judgements" <<< "$out3" && grep -q "or --stdin and no arguments" <<< "$out4" && [ "$before" = "$(cat "$REC")" ] \
  && ok "23e a duplicate, a short line, an empty batch, --stdin with arguments: each exit 1, nothing written" || bad "23e $r1$r2$r3$r4 '$out1' '$out2' '$out3' '$out4'"
mh record alpha plain.md >/dev/null 2>&1; r5=$?
out6=$(printf 'alpha plain.md craft\n' | mh record --stdin --where TD-7 2>&1); r6=$?
[ "$r5" = 2 ] && [ "$r6" = 0 ] && grep -qF "| alpha | plain.md |" "$REC" && grep -q "| craft | $TODAY | TD-7 |" "$REC" \
  && ok "23f the single form missing an argument: exit 2 as before; --where with --stdin is a line's default where" || bad "23f $r5 $r6 '$out6'"
cp "$TMP/rec.good" "$REC"

# 24. settings precedence (local, then project, then home), ~ expanded, a relative value ignored
# (the default stands, as check_claude_memory.sh does), a file that is not JSON skipped
mkrepo eta; E="$TMP/repos/eta"; mkdir -p "$E/.claude" "$HOME/.claude" "$HOME/hm" "$TMP/pm" "$TMP/lm"
for d in "$HOME/hm" "$TMP/pm" "$TMP/lm" "$E/docs/claude-memory"; do printf -- '---\nname: x\n---\n%s\n' "$d" > "$d/feedback_where.md"; done
echo "$E" >> "$AGENT_CADENCE_REG_DIR/repos.txt"
src() { J=$(mh inventory --json); q "[r['source'] + ' => ' + r['memory_dir'] for r in d['repos'] if r['repo']=='eta'][0]"; }
printf '{"autoMemoryDirectory": "~/hm"}\n' > "$HOME/.claude/settings.json"
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/pm" > "$E/.claude/settings.json"
printf '{"autoMemoryDirectory": "%s"}\n' "$TMP/lm" > "$E/.claude/settings.local.json"
s1=$(src); rm "$E/.claude/settings.local.json"; s2=$(src); rm "$E/.claude/settings.json"; s3=$(src)
printf '{"autoMemoryDirectory": "%s",}\n' "$TMP/lm" > "$E/.claude/settings.local.json"; s4=$(src)
printf '{"autoMemoryDirectory": "rel/mem"}\n' > "$E/.claude/settings.local.json"; s5=$(src)
[ "$s1" = "autoMemoryDirectory in $E/.claude/settings.local.json => $TMP/lm" ] && [ "$s2" = "autoMemoryDirectory in $E/.claude/settings.json => $TMP/pm" ] \
  && [ "$s3" = "autoMemoryDirectory in $HOME/.claude/settings.json => $HOME/hm" ] && [ "$s4" = "$s3" ] \
  && [ "$s5" = "default (the relative autoMemoryDirectory in $E/.claude/settings.local.json is ignored) => $E/docs/claude-memory" ] \
  && ok "24 local > project > home; ~ expanded; not-JSON skipped; relative ignored, the default stands" || bad "24 [$s1] [$s2] [$s3] [$s4] [$s5]"
rm -f "$E/.claude/settings.local.json" "$HOME/.claude/settings.json"

# 25. a BOM before the frontmatter; two roster repos sharing a name are not read, and record refuses
printf '\xef\xbb\xbf---\nname: bom\ntype: feedback\n---\nb\n' > "$E/docs/claude-memory/feedback_bom.md"
mkdir -p "$TMP/other"; git init -q -b main "$TMP/other/eta"; echo "$TMP/other/eta" >> "$AGENT_CADENCE_REG_DIR/repos.txt"
J=$(mh inventory --json)
[ "$(mem eta type feedback_bom.md)" = feedback ] && ok "25 a BOM does not hide the frontmatter" || bad "25 $(mem eta type feedback_bom.md)"
out=$(mh record eta feedback_bom.md craft 2>&1); rc=$?
grep -q "shares its name with $E" <<< "$(q "[r['note'] for r in d['repos'] if r['root']=='$TMP/other/eta'][0]")" && [ "$rc" = 1 ] && grep -q "2 roster repos are named eta" <<< "$out" \
  && ok "25b two repos named eta: the second not read, record refused" || bad "25b rc=$rc '$out'"

# 26. the stamp: under the layer's title, set off by blank lines; a second run replaces it in place;
# <n> is the repos whose memories were read; the layer reader skips it; the attention report warns
# once it is past HARVEST_STALE_DAYS and is silent while fresh (the reader's side: tests/test_parity.sh)
L="$LAYER/cadence-personal.md"; printf '# rules\n§4.8 add: one\n' > "$L"
NREAD=$(J=$(mh inventory --json); python3 -c "import json,sys; print(sum(r['read'] for r in json.loads(sys.argv[1])['repos']))" "$J")
out=$(mh stamp 2>&1); rc=$?
HOST=$(hostname | cut -d. -f1)
want="Harvested: $TODAY ($HOST, $NREAD repos)"
[ "$rc" = 0 ] && [ "$(sed -n 1,4p "$L" | tr '\n' '|')" = "# rules||$want||" ] && [ "$(sed -n 5p "$L")" = "§4.8 add: one" ] \
  && ok "26 stamp: a header line under the title, blank lines around it ($want)" || bad "26 rc=$rc '$out' $(cat "$L")"
[ "$NREAD" = 6 ] && ok "26a <n> counts the 6 repos read (not the gone, the shared or the second same-named one)" || bad "26a n=$NREAD"
mh stamp >/dev/null 2>&1
[ "$(grep -c '^Harvested:' "$L")" = 1 ] && [ "$(wc -l < "$L")" = 5 ] && ok "26b a second stamp replaces the first in place" || bad "26b $(cat "$L")"
eff=$(python3 "$DC/files/scripts/cadence_layer.py" --effective 2>&1)
! grep -q "Harvested" <<< "$eff" && grep -q "§4.8" <<< "$eff" && ok "26c --effective never lists the stamp as a rule" || bad "26c '$eff'"
rep=$(python3 "$DC/files/scripts/nudge_user_attention.py" --report 2>&1)
! grep -q "memory harvest" <<< "$rep" && ok "26d a fresh stamp: the attention report says nothing of it" || bad "26d '$rep'"
OLD=$(python3 -c "import datetime as d; print((d.date.today()-d.timedelta(days=31)).isoformat())")
sed -i "s/^Harvested: [0-9-]*/Harvested: $OLD/" "$L"
rep=$(python3 "$DC/files/scripts/nudge_user_attention.py" --report 2>&1)
grep -qF "last memory harvest 31d ago ($OLD, $HOST, $NREAD repos) — run /memory-harvest (cadence.md §7.13)" <<< "$rep" \
  && ok "26e a stamp 31 days old: the report's layers section warns" || bad "26e '$rep'"
printf '# no title line\n' > "$TMP/l2.md"; sed -i '1s/^# no title line$/plain first line/' "$TMP/l2.md"
printf '[[layers]]\npath = "%s"\n' "$TMP/l2.md" > "$AGENT_CADENCE_REG_DIR/cadence.toml"
mh stamp >/dev/null 2>&1
[ "$(sed -n 1,3p "$TMP/l2.md" | tr '\n' '|')" = "Harvested: $TODAY ($HOST, $NREAD repos)||plain first line|" ] && ok "26f no title: the stamp goes at the top" || bad "26f $(cat "$TMP/l2.md")"
printf '# t\n\n```\nHarvested: 2020-01-01 (example)\n```\n' > "$TMP/l2.md"
printf 'not a table\n| Repo | Memory | sha | Verdict | Judged | Where |\n|---|---|---|---|---|---|\n| broken |\n' > "$TMP/memory-harvest.md"
mh stamp >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && grep -qxF "Harvested: 2020-01-01 (example)" "$TMP/l2.md" && [ "$(sed -n 3p "$TMP/l2.md")" = "Harvested: $TODAY ($HOST, $NREAD repos)" ] \
  && ok "26g an example in a code fence is left alone, and a record that does not parse does not block the stamp" || bad "26g rc=$rc $(cat "$TMP/l2.md")"

# 27. run from any cadence repo (TD-135): from a roster repo's checkout, `clone` names the own
# layer's clone and `record` and `stamp` write it by path; `clone` refuses one off its default
# branch, detached, or holding a change the run did not make, and lets untracked .claude/ pass
git init -q --bare -b main "$TMP/origins/layer.git"
git clone -q "$TMP/origins/layer.git" "$TMP/lclone" 2>/dev/null
printf '# rules\n§4.8 add: one\n' > "$TMP/lclone/cadence-personal.md"
git -C "$TMP/lclone" add -A && git -C "$TMP/lclone" commit -qm l && git -C "$TMP/lclone" push -q origin main 2>/dev/null
printf '[[layers]]\npath = "%s/cadence-personal.md"\n' "$TMP/lclone" > "$AGENT_CADENCE_REG_DIR/cadence.toml"
mkdir -p "$TMP/lclone/.claude/worktrees/w"; echo x > "$TMP/lclone/.claude/worktrees/w/f"
alpha_before=$(GIT_OPTIONAL_LOCKS=0 git -C "$TMP/repos/alpha" status --porcelain)
out=$(cd "$TMP/repos/alpha" && mh clone 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$TMP/lclone" ] && ok "27 clone from a roster repo: the layer clone's root, untracked .claude/ allowed" || bad "27 rc=$rc '$out'"
(cd "$TMP/repos/alpha" && mh record alpha feedback_merge.md covered >/dev/null 2>&1 && mh stamp >/dev/null 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qF "| alpha | feedback_merge.md |" "$TMP/lclone/memory-harvest.md" && grep -q '^Harvested: ' "$TMP/lclone/cadence-personal.md" \
  && [ ! -e "$TMP/repos/alpha/memory-harvest.md" ] && [ "$alpha_before" = "$(GIT_OPTIONAL_LOCKS=0 git -C "$TMP/repos/alpha" status --porcelain)" ] \
  && ok "27a record and stamp from a roster repo write the layer clone, nothing in the cwd's repo" || bad "27a rc=$rc"
out=$(cd "$TMP/repos/alpha" && mh clone 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "changes the run did not make" <<< "$out" && grep -qF "memory-harvest.md" <<< "$out" && grep -qF "cadence-personal.md" <<< "$out" \
  && ok "27b clone refuses a clone with a modified and an untracked file, naming both" || bad "27b rc=$rc '$out'"
git -C "$TMP/lclone" add cadence-personal.md memory-harvest.md && git -C "$TMP/lclone" commit -qm h
(cd "$TMP/repos/alpha" && mh clone >/dev/null 2>&1) && ok "27c committed: clone passes again" || bad "27c"
git -C "$TMP/lclone" switch -q -c side
out=$(mh clone 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "is on side, not its default branch main" <<< "$out" && ok "27d clone refuses a clone off its default branch" || bad "27d rc=$rc '$out'"
git -C "$TMP/lclone" switch -q --detach main
out=$(mh clone 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "is detached, not its default branch main" <<< "$out" && ok "27e clone refuses a detached clone" || bad "27e rc=$rc '$out'"
git -C "$TMP/lclone" switch -q main
echo staged > "$TMP/lclone/new.md"; git -C "$TMP/lclone" add new.md
out=$(mh clone 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "new.md" <<< "$out" && ok "27f clone refuses a staged file" || bad "27f rc=$rc '$out'"
git -C "$TMP/lclone" rm -q --cached new.md; rm "$TMP/lclone/new.md"
mkdir -p "$TMP/nogit"; echo '# r' > "$TMP/nogit/l.md"
printf '[[layers]]\npath = "%s/l.md"\n' "$TMP/nogit" > "$AGENT_CADENCE_REG_DIR/cadence.toml"
out=$(mh clone 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "is not in a git clone" <<< "$out" && ok "27g clone refuses a layer outside any git clone" || bad "27g rc=$rc '$out'"
: > "$AGENT_CADENCE_REG_DIR/cadence.toml"
out=$(mh clone 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "no own layer" <<< "$out" && ok "27h clone with no own layer: exit 1, said" || bad "27h rc=$rc '$out'"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
