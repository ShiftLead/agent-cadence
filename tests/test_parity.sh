#!/usr/bin/env bash
# Parity pairs (cadence.md §7, TD-045): a format written in one place and parsed in another.
# Every other suite feeds its reader a HAND-TYPED fixture, so a format change on either
# side passes them all. This one takes the WRITER's own literal example — the line a
# session copies — and runs it through the READER's own regex, imported from the script.
# Change either side alone and this fails until both move.
#
# The registry of pairs is the table in cadence.md §7 ("Parity pairs"); a row there whose
# test column names this file has a case here, and case 0 checks the table says so.
#
# Offline, no git, no network: reads files in this repo only. HOME is a temp dir.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg"; mkdir -p "$HOME"
# a published snapshot (snapshot_public.sh's README note, TD-090) carries none of this repo's own docs/,
# CLAUDE.md or .claude/: there a dogfood check whose file is absent is not run, said; here it always runs
snapshot() { grep -q '^> \*dev-cadence, published as agent-cadence\.\*' "$1/README.md"; }
snapshot "$DC" && export DC_SNAPSHOT=1

out=$(cd "$DC" && PYTHONPATH="$DC/files/scripts" python3 - <<'PY' 2>&1
import datetime as dt, re, sys
import nudge_user_attention as N, check_cadence as K, cadence_changes as C, list_sessions as L, ledger as LG

today = dt.date.today().isoformat()          # never a hardcoded calendar date (TD-24)
import os
# the seed's board and this repo's own; a published snapshot (DC_SNAPSHOT) has only the seed's
BOARDS = [b for b in ("files/docs/user_attention.md", "docs/user_attention.md")
          if not (os.environ.get("DC_SNAPSHOT") == "1" and b.startswith("docs/") and not os.path.exists(b))]
if len(BOARDS) == 1:
    print("NOTE: a published snapshot has no docs/user_attention.md — its board-format pairs, not run")
res = []
def check(name, cond, detail=""):
    res.append(("PASS" if cond else "FAIL") + ": " + name + ("" if cond else f" — {detail}"))

def fill(tmpl, **kw):
    """A writer's template with its placeholders filled the way a session fills them."""
    s = tmpl.replace("YYYY-MM-DD", today)
    for k, v in kw.items():
        s = s.replace(k, v)
    return s

def read(p):
    return open(p, encoding="utf-8").read()

# --- 1) sweep stamps: the stranded-work procedure (writer, TD-093) -> SWEEP_RE / SWEEP_DEEP_RE / sweep_mode
skill = read("files/docs/procedures/stranded-work.md")
m = re.search(r"`(Swept: YYYY-MM-DD \([^`]*\))`", skill)
check("stranded-work procedure states the Swept: template", m, "no `Swept: YYYY-MM-DD (...)` literal")
if m:
    for mode in ("quick", "deep"):
        line = fill(m.group(1), **{"<host>": "testhost", "quick|deep": mode})
        g = N.SWEEP_RE.search(line)
        check(f"Swept: ({mode}) — SWEEP_RE reads the date", g and g.group("date") == today, line)
        check(f"Swept: ({mode}) — sweep_mode reads '{mode}'", g and N.sweep_mode(g.group("meta")) == mode, line)
m = re.search(r"`(Swept-deep: YYYY-MM-DD[^`]*)`", skill)
check("stranded-work procedure states the Swept-deep: template", m, "no `Swept-deep: YYYY-MM-DD` literal")
if m:
    g = N.SWEEP_DEEP_RE.search(fill(m.group(1)))
    check("Swept-deep: — SWEEP_DEEP_RE reads the date", g and g.group("date") == today, m.group(1))
check("the procedure's modes are the reader's SWEEP_MODES",
      set(N.SWEEP_MODES) == {"quick", "deep"} and "quick|deep" in skill, str(N.SWEEP_MODES))

# --- 2) the review comment: the cadence procedure (writer, TD-093) -> REVIEW_RE
cskill = read("files/docs/procedures/cadence.md")
lines = [l.strip() for l in cskill.splitlines() if l.strip().startswith("cadence-review:")]
check("cadence procedure shows a cadence-review: example", lines)
for l in lines:
    g = K.REVIEW_RE.match(l)
    check(f"REVIEW_RE reads the procedure's example '{l}'", g and g.group("verdict").upper() in ("SHIP", "FIXED", "BLOCK"), l)
m = re.search(r"`(cadence-review: ([A-Z |]+?) · [^`]*)`", read("files/docs/cadence.md"))
check("cadence.md §4 states the cadence-review: template", m, "no `cadence-review: SHIP | FIXED | BLOCK · …` literal")
if m:
    for v in [x.strip() for x in m.group(2).split("|")]:
        line = m.group(1).replace(m.group(2), v).replace("<reviewer model>", "sonnet").replace("<code|docs>", "code").replace("<n>", "2")
        g = K.REVIEW_RE.match(line)
        check(f"REVIEW_RE reads cadence.md's template with verdict {v}", g and g.group("verdict").upper() == v, line)

# --- 3) the board Format line: seed user_attention.md (writer) -> ITEM_RE / DUE_RE / SESSION_RE
for board in BOARDS:
    fm = re.search(r"^Format: `([^`]+)`", read(board), re.M)
    check(f"{board}: states a Format: line", fm)
    if not fm:
        continue
    item = fill(fm.group(1), **{"<first-8-of-session-uuid>": "0a1b2c3d", "<host>": "testhost"})
    gi = N.ITEM_RE.match(item)
    check(f"{board}: ITEM_RE reads the Format example as an open item", gi, item)
    gd = N.DUE_RE.search(item)
    check(f"{board}: DUE_RE reads its Due: date", gd and gd.group("due") == today, item)
    check(f"{board}: list_sessions.SESSION_RE reads its session id",
          L.SESSION_RE.findall(item) == ["0a1b2c3d"], str(L.SESSION_RE.findall(item)))
    # TD-039: the Kinds: line names exactly the reader's KINDS, and each reads back as the kind
    fk = re.search(r"^Kinds: `([^`]+)`", read(board), re.M)
    check(f"{board}: states a Kinds: line", fk)
    if fk:
        kinds = tuple(k.strip() for k in fk.group(1).split("|"))
        check(f"{board}: Kinds: matches KIND_RE's KINDS", sorted(kinds) == sorted(N.KINDS), str(kinds))
        for k in kinds:
            kitem = item.replace("- [ ] ", f"- [ ] {k} ", 1)
            check(f"{board}: KIND_RE reads '{k}' before the Format example's date",
                  N.parse_board(kitem, warn=False)[0].kind == k, kitem)
    # TD-036: the trailing fields, appended the way the header shows them, read back
    fa = re.search(r"`(Answers: [^`]+)`", read(board))
    fd = re.search(r"`(Decided: [^`]+)`", read(board))
    check(f"{board}: states the Answers: and Decided: templates", fa and fd)
    if fa and fd:
        full = f"{item} {fill(fa.group(1), **{'<answer>': 'yes'})} {fill(fd.group(1), **{'<text>': 'yes'})}"
        check(f"{board}: ANSWERS_RE reads the Answers: template", N.parse_answers(full) == ["yes", "yes"], full)
        fdef = re.search(r"`(Answers: <answer> \(default\)[^`]*)`", read(board))
        check(f"{board}: states the Answers: (default) template", fdef)
        if fdef:
            full2 = f"{item} {fill(fdef.group(1), **{'<answer>': 'yes'})}"
            check(f"{board}: DEFAULT_MARK_RE reads the (default) template",
                  N.parse_default(full2) == "yes" and N.parse_answers(full2) == ["yes", "yes"], full2)
        check(f"{board}: DECIDED_RE reads the Decided: template",
              N.parse_decided(full) == ("yes", dt.date.today()), full)
        check(f"{board}: DUE_RE still reads the Due: date with both fields after it",
              N.parse_board(full, warn=False)[0].due == dt.date.today(), full)

# --- 3a) TD-062 closing: the seed's Closed: literal -> CLOSED_ITEM_RE / CLOSED_RE / item_key;
#          the archive threshold as written in cadence.md, the seed and the procedure -> ARCHIVE_AT
seed = read("files/docs/user_attention.md")
m = re.search(r"`(Closed: YYYY-MM-DD[^`]*)`", seed)
check("seed board states the Closed: template", m, "no `Closed: YYYY-MM-DD …` literal")
if m:
    open_ = f"- [ ] {today} (session n/a) — an item. Context: TD-1. Due: {today}."
    closed = "- [x]" + open_[5:] + " " + fill(m.group(1), **{"<why>": "done in PR #1"})
    g = N.CLOSED_RE.search(closed)
    check("Closed: — CLOSED_RE reads the date", g and g.group("date") == today, closed)
    check("Closed: — CLOSED_ITEM_RE reads the line as closed, ITEM_RE not as open",
          N.CLOSED_ITEM_RE.match(closed) and not N.ITEM_RE.match(closed), closed)
    check("Closed: — item_key matches its open twin", N.item_key(closed) == N.item_key(open_), closed)
for f in ("files/docs/cadence.md", "files/docs/user_attention.md", "files/docs/procedures/stranded-work.md"):
    check(f"{f} states the archive threshold ARCHIVE_AT={N.ARCHIVE_AT}",
          f"{N.ARCHIVE_AT} or more closed" in read(f), "no '<N> or more closed' phrase")

# --- 3b) TD-064 Blocked by: the seed template's field line and §2's example -> ledger.py
tmpl = read("files/docs/technical_debt.md")
g = LG.BLOCKED_RE.search(tmpl)
check("seed ledger template carries a **Blocked by:** line BLOCKED_RE reads", g, "no **Blocked by:** line")
sec2 = read("files/docs/cadence.md")
m = re.search(r"comma-separated entry IDs \(`([^`]+)`", sec2)
check("cadence.md §2 gives a Blocked by ID example", m, "no `(TD-…, TD-…)` example")
if m:
    ids, who, bad = LG.parse_blocked(m.group(1) + ", decision (Alex) — a pointer, with a comma")
    check("§2's example parses: its IDs, one decision, nothing unreadable",
          ids == [x.strip() for x in m.group(1).split(",")] and who == ["Alex"] and not bad, (ids, who, bad))

m = re.search(r"as `<repo>#TD-NNN` \(TD-071\)\*\* \(`([^`]+)`\)", sec2)
check("cadence.md §2.4 gives a <repo>#TD-NNN example", m, "no `(<repo>#TD-NNN)` example")
if m:
    ids, who, bad = LG.parse_blocked(m.group(1))
    check("§2.4's cross-repo example parses as one XREPO item", ids == [m.group(1)] and LG.XREPO_ITEM_RE.match(ids[0]) and not bad, (ids, bad))
g0 = LG.BLOCKED_RE.search(tmpl)
check("the seed template's Blocked by line names the <repo>#TD-NNN form", g0 and "<repo>#TD-NNN" in g0.group(1), g0.group(1) if g0 else "no line")

# --- 3c) §2.11 Type: the seed template's field line and §2.11's vocabulary -> ledger.py
g = LG.TYPE_RE.search(tmpl)
check("seed ledger template carries a **Type:** line TYPE_RE reads", g, "no **Type:** line")
if g:
    check("the template's Type line names exactly TYPES", all(t in g.group(1) for t in LG.TYPES), g.group(1))
m = re.search(r"\*\*§2\.11\*\*.*?`\*\*Type:\*\* ([a-z |]+)`", sec2)
check("cadence.md §2.11 names the Type vocabulary TYPES", m and [x.strip() for x in m.group(1).split("|")] == list(LG.TYPES),
      m.group(1) if m else "no §2.11 `**Type:** …` phrase")

# --- 3c2) §2.12 header block: the cadence's field list and the seed template -> ledger.py
m = re.search(r"\*\*§2\.12\*\*.*?The cadence defines `([^`]+)`", sec2)
check("cadence.md §2.12 names exactly CADENCE_FIELDS", m and [LG.field_key(x) for x in m.group(1).split(",")] == list(LG.CADENCE_FIELDS),
      m.group(1) if m else "no §2.12 'The cadence defines `…`' phrase")
g = re.search(r"^.*<!-- Entry template:\n\n## TD-001:[^\n]*\n\n(.*?)\n\n", tmpl, re.S | re.M)
fields = LG.header_block(g.group(1)) if g else {}
check("the seed template's header block reads as exactly CADENCE_FIELDS", sorted(fields) == sorted(LG.CADENCE_FIELDS), sorted(fields))
m = re.search(r"`(Fields: [^`]+)`", tmpl)
vocab, bad = LG.declared(m.group(1) + "\n") if m else ({}, ["no example"])
check("the seed template's Fields: example parses", vocab and not bad, (vocab, bad))
m = re.search(r"\*\*§2\.12\*\*.*?\(`(Fields: [^`]+)`\)", sec2)
vocab, bad = LG.declared(m.group(1) + "\n") if m else ({}, ["no example"])
check("cadence.md §2.12's Fields: example parses", vocab and not bad, (vocab, bad))

# --- 3d) every rule number in cadence.md is used once (a new rule takes the next free number)
from collections import Counter
dups = [n for n, c in Counter(re.findall(r"^\s*- \*\*(§[0-9A]+\.[0-9]+)\*\*", sec2, re.M)).items() if c > 1]
check("cadence.md rule numbers are unique", not dups, dups)

# --- 3e) TD-084: §3.3's detail-block example (writer) reads back through detail_block() with
# its labels in order, its fields still on the head line; each board header names the same labels
LABELS = ["Context", "Question", "Caveats", "Recommended"]
m = re.search(r"An item explains itself.*?```\n(.*?)\n\s*```", read("files/docs/cadence.md"), re.S)
check("cadence.md §3.3 shows a detail-block example", m)
if m:
    ex = "\n".join(ln[2:] for ln in fill(m.group(1), **{"<id>": "0a1b2c3d", "<host>": "testhost"}).splitlines())
    it = N.parse_board(ex, warn=False)
    got = [re.match(r"- \*\*(\w+):\*\*", d).group(1) for d in (it[0].detail if it else []) if re.match(r"- \*\*(\w+):\*\*", d)]
    check("§3.3's example: detail_block() reads the labels in order", got == LABELS, got)
    check("§3.3's example: Due:, Answers: and (default) read from the head line",
          it and it[0].due and it[0].default == "Nightly" and len(it[0].answers) == 3, it)
for board in BOARDS:
    got = re.findall(r"`\*\*(\w+):\*\*", read(board))
    check(f"{board}: names the detail block's labels in §3.3's order", got[:4] == LABELS, got)

# --- 4) cadence-changes.md: every heading is one HEADING_RE reads (an entry typed with '-'
#        or '###' silently merges into the entry above and never prints), newest first,
#        and at most three lines per entry (the file's own header rule)
text = read("files/docs/cadence-changes.md")
heads = [l for l in text.splitlines() if l.startswith("## ")]
bad = [h for h in heads if not C.HEADING_RE.match(h)]
check(f"cadence-changes.md: all {len(heads)} '## ' headings match HEADING_RE", heads and not bad, "; ".join(bad))
odd = [l for l in text.splitlines() if re.match(r"^#{3,} \d{4}-", l) or re.match(r"^## \d{4}-\d{2}-\d{2} [-–] ", l)]
check("cadence-changes.md: no near-miss heading ('###' or a hyphen/en dash for the em dash)", not odd, "; ".join(odd))
entries = C.parse(text)
dates = [e["date"] for e in entries]
check("cadence-changes.md: newest first", dates == sorted(dates, reverse=True),
      next((f"{a} before {b}" for a, b in zip(dates, dates[1:]) if a < b), ""))
long_ = [f"{e['date']} {e['title'][:40]}… ({len(e['body'].splitlines())} lines)" for e in entries if len(e["body"].splitlines()) > 3]
check("cadence-changes.md: every entry is at most 3 lines", not long_, "; ".join(long_))

# --- 5) TD-069: the ADR template (writer's shape) and cadence.md §7's ADR rule name the same
#        Status states and the same sections
tpl = read("files/docs/adr-template.md")
rule = next((l for l in read("files/docs/cadence.md").splitlines() if "Architecture decisions get ADRs" in l), "")
check("cadence.md §7 states the ADR rule", rule)
heads = re.findall(r"^## (.+)$", tpl, re.M)
check("adr-template.md has the five sections, in order",
      heads == ["Context", "Options", "Decision", "Consequences", "Revisit triggers"], str(heads))
for h in heads:
    check(f"  ... and §7 names **{h}**", f"**{h}**" in rule, rule[:100])
st = re.search(r"^\*\*Status:\*\* (.+)$", tpl, re.M)
check("adr-template.md has a Status line", st)
for state in ("proposed", "decided YYYY-MM-DD by <who>", "superseded by"):
    check(f"  ... naming '{state}', as §7 does", st and state in st.group(1) and state in rule, state)

# --- 6) TD-093: every skill is a pointer to its procedure doc, which syncs — the
#        procedure is the writer the pairs above read, so a step added back into a SKILL.md
#        would be a second copy no test reads. Two pointer sets (TD-127): `.claude/skills/`
#        for Claude Code, `.agents/skills/` for Codex and Gemini CLI.
import glob, os
sync_sh = read("sync.sh")
skills = sorted(glob.glob("files/.claude/skills/*/SKILL.md") + glob.glob("files/.agents/skills/*/SKILL.md"))
check("there are skills to check", skills)
for sk in skills:
    name = sk.split("/")[-2]
    tooldir = sk.split("/")[1]
    proc = f"docs/procedures/{name}.md"
    body = read(sk).split("\n---\n", 1)[-1]
    rest = re.sub(r"\A\s*<!-- SYNCED FILE.*?-->\s*", "", body, flags=re.S)   # the provenance header only
    lines = [l for l in rest.splitlines() if l.strip()]
    check(f"{sk} names {proc}", proc in body, body[:120])
    link = re.search(r"\]\(([^)]*docs/procedures/[^)]+)\)", rest)
    check(f"  ... and links it by a path that resolves from {tooldir}/skills/{name}/",
          link and os.path.normpath(os.path.join(tooldir, "skills", name, link.group(1))) == proc, link.group(1) if link else "no link")
    check(f"  ... which exists and is in SYNC_FILES", glob.glob("files/" + proc) and f'"{proc}"' in sync_sh, proc)
    check(f"  ... and holds no step of its own (a title and one two-line paragraph)",
          len(lines) == 3 and lines[0].startswith("# ") and not any(l.lstrip().startswith(("#", "-", "*", "1.", "```")) for l in lines[1:]), len(lines))

# --- 6c) TD-125: the Harvested: stamp — memory_harvest.py writes it with the reader's own HARVEST_RE,
#         the reader warns on it past HARVEST_STALE_DAYS and is silent when fresh, and the layer
#         reader never takes it for a rule
import memory_harvest as MH, cadence_layer as CL
check("memory_harvest.py imports the reader's HARVEST_RE, never a copy", MH.HARVEST_RE is N.HARVEST_RE)
line = MH.stamp_line(dt.date.today().isoformat(), "testhost", 7)
hm = N.HARVEST_RE.match(line)
check("  ... the writer's stamp_line() parses with the reader's HARVEST_RE", hm and hm.group("date") == dt.date.today().isoformat() and hm.group("meta") == "testhost, 7 repos", line)
check("  ... a fresh stamp is silent", N.harvest_note(line, dt.date.today()) is None)
# the threshold as the docs say it (cadence.md §7.13: "past 30 days"), a literal on purpose — a
# test derived from the constant could never fail when the constant moved
age = lambda d: MH.stamp_line((dt.date.today() - dt.timedelta(days=d)).isoformat(), "h", 1)
check("  ... 30 days old is silent and 31 warns (cadence.md §7.13's 30 days)",
      N.harvest_note(age(30), dt.date.today()) is None and "last memory harvest 31d ago" in (N.harvest_note(age(31), dt.date.today()) or ""),
      N.HARVEST_STALE_DAYS)
check("  ... and §7.13 says the same number", f"past {N.HARVEST_STALE_DAYS} days" in read("files/docs/cadence.md"), N.HARVEST_STALE_DAYS)
check("  ... the layer reader skips it", CL.rules("# t\n\n" + line + "\n\nrule one\n") == [{"line": 5, "sec": None, "verb": None, "text": "rule one"}], CL.rules(line))
check("  ... and SWEEP_RE cannot match it", N.SWEEP_RE.search(line) is None)

# --- 6b) TD-127: the two pointer sets are one pair — every procedure has both, and each
#         `.agents` pointer is its `.claude` twin byte for byte apart from the header's own path,
#         so a description or body changed in one set and not the other fails here
for proc in sorted(glob.glob("files/docs/procedures/*.md")):
    name = os.path.basename(proc)[:-3]
    cl, ag = f"files/.claude/skills/{name}/SKILL.md", f"files/.agents/skills/{name}/SKILL.md"
    check(f"{proc} has a Claude Code pointer and a .agents pointer", os.path.isfile(cl) and os.path.isfile(ag), name)
    if os.path.isfile(cl) and os.path.isfile(ag):
        twin = read(cl).replace(cl, ag, 1)
        check(f"  ... and {ag} is {cl} apart from the header's path", read(ag) == twin, name)
        check(f"  ... and both are in SYNC_FILES", f'"{cl[6:]}"' in sync_sh and f'"{ag[6:]}"' in sync_sh, name)

# --- 6d) TD-129: the [dev-cadence] pin — adopt (writer) appends it under the header the shims and
#         the seeded SessionStart line grep for, and refuses a pin they could not see; the launcher's
#         read_pin() and words.py agree on what a source and a ref are
import json, subprocess
sys.path.insert(0, "launcher")
import words as W, dev_cadence as D
check("words.py's SOURCE_RE and COMMIT_RE are the launcher's", W.SOURCE_RE.pattern == D.SOURCE_RE.pattern and W.COMMIT_RE.pattern == D.COMMIT_RE.pattern,
      (W.SOURCE_RE.pattern, D.SOURCE_RE.pattern))
shim = re.search(r"grep -qsE '([^']+)'", read("files/scripts/install_git_hooks.sh"))
seed = re.search(r"grep -qsE '([^']+)'", json.load(open("files/.claude/settings.json"))["hooks"]["SessionStart"][0]["hooks"][0]["command"])
# the shim's pattern sits in a double-quoted bash string, so its \\[ and \$ are unescaped once
shim_ere = shim.group(1).replace("\\\\", "\\").replace("\\$", "$") if shim else None
check("the shims and the seeded SessionStart line grep for the same pin header", shim and seed and shim_ere == seed.group(1), (shim_ere, seed and seed.group(1)))
samples = ["[dev-cadence]", "  [dev-cadence]   # pinned", "[dev-cadence]\r", "\t[dev-cadence]", "[ dev-cadence ]",
           '["dev-cadence"]', "[dev-cadence.x]", "# [dev-cadence]", "[dev-cadence] x", "[[dev-cadence]]"]
for smp in samples:
    g = subprocess.run(["grep", "-qsE", seed.group(1)], input=smp + "\n", text=True).returncode == 0 if seed else None
    check(f"  ... adopt's PIN_HEADER_RE and the hooks' grep agree on {smp!r}", bool(W.PIN_HEADER_RE.search(smp + "\n")) == g, g)
block = re.search(r'block = \((.*?)\n        after = ', read("launcher/words.py"), re.S)
check("adopt writes the header as the hooks detect it", block and '[dev-cadence]\\nsource = ' in block.group(1), block and block.group(1)[-200:])

# --- 0) the registry: cadence.md §7's Parity pairs table names this test on the pairs above
tbl = read("files/docs/cadence.md")
sect = tbl[tbl.find("**Parity pairs"):tbl.find("- **§7.10**")]   # the table, however long it grows
for key in ("Swept:", "cadence-review:", "Format:", "cadence-changes.md", "CADENCE_HOOK_LINE", "Harvested:", "[dev-cadence]"):
    row = next((l for l in sect.splitlines() if l.lstrip().startswith("|") and key in l), "")
    check(f"cadence.md §7 Parity pairs table has a row for {key}", row, "row missing")
for key in ("Swept:", "cadence-review:", "Format:", "cadence-changes.md", "Harvested:", "[dev-cadence]"):
    row = next((l for l in sect.splitlines() if l.lstrip().startswith("|") and key in l), "")
    check(f"  ... and that row names tests/test_parity.sh", "test_parity.sh" in row, row[:120])

print("\n".join(res))
PY
)
echo "$out"
PASS=$(grep -c '^PASS' <<< "$out"); FAIL=$(grep -c '^FAIL' <<< "$out")
if ! grep -q '^PASS' <<< "$out"; then FAIL=$((FAIL+1)); echo "FAIL: the parity check did not run"; fi
echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
