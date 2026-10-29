<!-- SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/docs/procedures/attention.md
     Edit it there: a repo runs it from its pinned dev-cadence (`dev-cadence path`), and a fix reaches it by a bump PR. -->

# Attention — machine-wide board report

Answer "what needs the user's attention across all repos on this machine?" in one shot.
Thin wrapper around the report mode of the synced nudge script — never reimplement its
parsing, ordering, or roster reading (spec: cadence.md §Machine scope).

**Running it (TD-093):** this file is the procedure, and any agent runs it by reading it and following it. Claude Code also has it as a skill — `/attention`, `/attention all`, `/attention <repo>`, each with `fetch` or `remote` added — whose `SKILL.md` only points here, and so do Codex (`$attention`) and Gemini CLI, from the same pointer under `.agents/skills/` (TD-127); a tool with no skills needs nothing installed. Asked for *fetch* or *remote*, add that flag below.

## Run

```bash
python3 scripts/nudge_user_attention.py --report --own-board "$(git rev-parse --show-toplevel)/docs/user_attention.md"  # /attention
python3 scripts/nudge_user_attention.py --report                    # /attention all
python3 scripts/nudge_user_attention.py --report --repo <name>      # /attention <repo>
python3 scripts/check_tmp.py --report                               # every form: this machine's temp filesystem (TD-154)
```

**Which repos are shown in full (TD-146):** with no argument, this repo's board — the one under
the session's checkout; in a constellation's sibling (§9.12), name the home's board instead — in
full, and every other roster repo folded to one line: its open and due counts and its most
overdue item's age, plus any line saying the row could not be read (a missing roster path, an
unreadable board or setting, a failed fetch), so nothing elsewhere is hidden, only folded; its
sweep, size and archive warnings wait for its own view. A repo with no board and not on the
roster gets every board in full. *all* is every board in full; a repo's name (as the report's
`==` headings print it, or its path where two roster repos share a name) shows that repo in full
and folds the rest, and a name that matches none, or more than one, exits 2 saying which. The
header line counts every board either way. `--json` refuses `--own-board` and `--repo`: a tool
reading the boards gets every one in full — the director's view stays machine-wide.

Run the current repo's synced copy (any consumer's copy is the same file — that's what
SYNC means). For *fetch*, add `--fetch`: serial, hang-proofed origin fetches
that compare each local board with its `origin/<default>` copy three ways (local, origin,
their merge-base — TD-030). A clone that is merely **behind** (local board untouched,
origin's moved — a service-account append, or another machine's push) has its board read
from origin and its header tagged `— showing origin/<default>`; local-only edits and
two-sided divergence keep reading the local file and say which. Plus a per-repo
cadence-staleness line when a repo's dev-cadence pin lacks upstream's latest payload commit
(the cure: a `dev-cadence bump` PR), or the repo still carries a sync lock and no pin (the
cure: `sync.sh --pin`) — so a behind repo names itself in the fetch view.

For *remote*, add `--remote` instead (it implies `--fetch`): after the local
sections, a labeled remote tier lists boards discovered on GitHub (gh CLI) and on any GitLab host
`remote_repos.txt` names (glab CLI, TD-110) in repos no
local row covers — repos living only on other machines. Pushed state only; archived
repos are skipped; discovery scans the authenticated user + orgs unless
`remote_repos.txt` in the machine-scope directory (`$DEV_CADENCE_REG_DIR`, else `${XDG_CONFIG_HOME:-~/.config}/dev-cadence`) narrows it (one `owner`,
`owner/repo` or `host/owner/repo` per line, `gitlab.com/<group>` or a bare `gitlab.com` for GitLab, cadence.md §9.5;
empty/missing = scan all of GitHub). Every failure mode (gh or glab missing,
unauthenticated, per-repo 403/5xx, truncated listing, budget exhaustion) degrades to a
⚠ note in the tier — surface those notes; absence of a note is the coverage claim.

## Present

The **temp filesystem** line from `check_tmp.py --report` goes after the boards. It always gives one line of inode and space use for the temp directory every session on this machine shares. Past 80% it adds the largest directories and the cleanups. Show the cleanups as commands for the person to run, and never run one yourself: the directory is shared, and the files may be other sessions'.

A **your cadence layers** section at the end names one of your own layers (cadence.md §9.18) whose layer file has an uncommitted edit, or whose clone has a commit not pushed. That edit is on this machine alone, so say to commit and push it in that repo. The same section says when the last memory harvest (its `Harvested:` stamp in the layer file, cadence.md §7.13) is over a month old: offer `/memory-harvest`, which the person starts in any cadence repo.

Lead with the report's own header line (N boards, M open items, K due/overdue) as the
TL;DR, then the per-repo sections; a folded repo's line is offered as `/attention <repo>`. The report is already ordered (decided items first —
they wait on a session, not the user — then overdue-most-first, dated soonest-first,
undated; then `watch` items, then `fyi` last — TD-039) — do not re-sort or re-derive tags.
An item tagged *ledger it* is overdue `escalate-overdue-days` or more (cadence.md §9.18, default 14): offer to ledger it and close it here.
An item's detail block (the indented lines the report prints under it, `detail` in `--json` —
TD-084) is what the person decides from: when they turn to an item, show its Context, Question,
Caveats and Recommended as written rather than summarising them away. An item that asks for a
decision without one is worth offering to have its session fill in (cadence.md §3.3).

When the user answers, snoozes or closes an item here, make the edit with
`scripts/board_edit.py decide|snooze|done --board <board> --line <N> --expect "<item text>"`
(the line and text from `--report --json`), never by hand-editing the line — it refuses a
board that moved and commits under cadence.md §4's tool-made-edit carve-out. An item's
`Answers:` are the choices to offer; the user may answer in their own words. Surface any ⚠ lines
(unreadable/missing boards, fetch skips) rather than smoothing
them over.

## No registry on this machine

The report degrades to the current repo's board by itself; say that's what happened.
Offer — never do unasked — to create `repos.txt` in the machine-scope directory: `$DEV_CADENCE_REG_DIR` when it is set (an isolated run — never the real one then), else `${XDG_CONFIG_HOME:-~/.config}/dev-cadence` (cadence.md §9).
The registry is append-only and nothing auto-cleans it, so the seed algorithm is pinned
and conservative:

- Seed with exactly ONE line: the **current repo's** canonicalized main-checkout root
  (`git rev-parse --git-common-dir` → parent dir → `realpath` — same resolution as
  `dev-cadence adopt`; spec: cadence.md §Machine scope).
- You may *mention* other candidate repos you happen to know of, but each one is added
  only on the user's explicit per-path confirmation AND after verifying on disk that the
  path exists, is a git repo, and resolves to a main checkout — never from session
  memory alone.
- The normal registration path is `dev-cadence adopt` (or `sync.sh --pin`) on a repo on this
  machine; hand-seeding is the exception for repos adopted by hand.

## Cross-machine questions

Offer `--report --fetch`, with the machine-scope caveat (same as [stranded-work.md](stranded-work.md)): a
behind clone's row already shows origin's board, but **un-pushed board edits on another
machine are invisible** to every view. A "board DIFFERS from origin" line is the cue to
pull (or push) before trusting that row; "showing origin/<default>" means the row is
ahead of the local file, and a pull will make the file match what was reported.

## Bounds

Read-only by default — the report path makes no writes. The only writes this procedure may
ever make are registry creation/append under the explicit opt-in above. Checking items
off, snoozing (editing `Due:` dates), and any other board edits are user-directed
follow-ups, not part of the report.
