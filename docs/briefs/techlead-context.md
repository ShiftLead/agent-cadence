# The techlead's primer for agent-cadence

**What this is.** You are a techlead (ShiftLead design §4.9b): you start cold, for one batch of
questions, and this page is your first read after your brief. It is agent-cadence in a few thousand
words, so that an answer is given with the whole shape in mind and not only the asker's framing.

**What this is not.** It is **an index, never a source.** Nothing here is cited as an answer:
`--source` names the document this page pointed you to — a section of `files/docs/cadence.md`, a
ledger entry, a plan doc, a dated decision — *after you have read it there*. If this page and
that document disagree, **the document is right, this page is stale, and you say so in your
summary.** `tests/test_briefs_primer.sh` holds every path and ledger id named here to ones that
exist; it cannot hold the prose to the truth, so check before you lean on it.

**The one rule that outranks being helpful here.** This system's recurring defect is a confident
claim taken from a *description* rather than the thing — a Status line, a `~line` citation, a
script header that says what the script no longer does. The 2026-09-22 design review found a
header claiming "one setting covers all worktrees" that is false (TD-055) and a docstring
claiming `na` where the code returns `pass` (TD-041). When a grinder asks "is X true?", the
answer is what the code or the test says, and your reply names which you read.

---

## 1. What agent-cadence is

The **canonical source** of a working-cadence system — a spec (`files/docs/cadence.md`),
stdlib-only bash and Python scripts (`files/scripts/`), Claude Code skills and hooks
(`files/.claude/`) — that each consumer repo runs from a pin: `[agent-cadence]` in its
`docs/cadence.toml` names a commit, and the `agent-cadence` launcher runs that tree from a per-machine
cache (`files/docs/cadence.md` §9.19, TD-129). There is no package and no registry, deliberately
(`README.md`, "Philosophy / non-goals"); `sync.sh` no longer copies into anything.
Consumers on this machine: the other repos on its roster (`shiftlead` among them); the
roster is `~/.config/agent-cadence/repos.txt`.

**This repo dogfoods itself.** Its own board, ledger and plans are under `docs/`, and the rules
in `files/docs/cadence.md` govern work here too. The one thing to keep straight before answering
anything about a path:

| Path | What it is |
|---|---|
| `files/**` | the payload consumers run from their pin — **all edits to the system happen here** |
| `files/docs/technical_debt.md`, `files/docs/user_attention.md` | empty **templates** that seed consumers |
| `docs/ledger/`, `docs/user_attention.md` | this repo's **live** ledger (one `TD-<NNN>.md` per entry, TD-160) and board |
| `docs/ledger/archive/` | resolved entries — the richest record of *why* |
| `docs/plans/` | this repo's design decisions; there is no `docs/decisions/` |
| `tests/`, `ruff.toml`, `sync.sh`, `launcher/` | tooling; `sync.sh` holds the payload's file lists and `--pin` (the migration) |

A pinned consumer carries no synced copies, so there is no drift to verify: its convention
changes arrive by an `agent-cadence bump` PR that moves the pin.

## 2. Where answers live

| Question | Read |
|---|---|
| How do we work — worktrees, ledger, board, review, merge | `files/docs/cadence.md` §1–§4; §7 for memory and parity; §9 for machine scope and constellations |
| What this repo enforces on itself, and its known gaps | `CLAUDE.md` — "Conventions this repo enforces on itself", "Known dogfooding gaps" |
| Is this known / already decided | `docs/ledger/TD-<NNN>.md`, then `docs/ledger/archive/` (`grep -r docs/ledger/`), then `docs/user_attention.md` |
| Why is it shaped this way | `docs/ledger/archive/` (the Why survives archiving), `docs/plans/` |
| The distribution contract — the pin, SYNC vs SEED | `CLAUDE.md` "The distribution contract"; `README.md` file-class table; `sync.sh` arrays near the top |
| What changed recently for every consumer | `files/docs/cadence-changes.md` (append-only, newest first) |
| What a script does | its header comment first, **then its code** — headers overclaim (TD-055, TD-058) |
| What a test pins | `tests/*.sh`; each is self-contained and says in its header why it exists |
| The team you serve | `docs/briefs/README.md` and the briefs beside it |

There is no design.md in this repo: `files/docs/cadence.md` is the spec, and its rules carry
their incident history inline (TD-049 says that is a problem; until it is fixed, the rule is
usually the first sentence of a bullet and the rest is why).

## 3. The shape of the questions you will get

The grinder **free-picks** from the live ledger (`docs/ledger/` as it stands on origin/main),
picking from `files/scripts/ledger.py --pickable` — highest Priority first, every entry with an open
`**Blocked by:**` field left out (`files/docs/cadence.md` §2, TD-064). What it escalates is usually one of:

1. **"The entry says line ~N, the code says otherwise — which?"** The code. Every review entry
   cites with `~`; the Why is what is being resolved, the Fix is a proposal. Answer with the grep.
2. **"The Fix proposes X; Y is smaller and covers the Why — may I?"** Usually yes, and say
   the entry stays live with its Status naming what remains (`files/docs/cadence.md` §2,
   *Partially resolved stays live*). A fix that changes a **convention** — a rule's wording in
   `files/docs/cadence.md`, a stamp format, the settings line — is fine when it comes with a
   `files/docs/cadence-changes.md` entry (§3); one that changes what a consumer must *do*
   differently goes up.
3. **"This touches a SYNC file — anything special?"** Yes: the change reaches every consumer on
   its next pin bump. Repo-specific behaviour stays out; a payload file added or removed edits both
   `sync.sh` and the `README.md` table (`tests/test_readme_sync_table.sh`); scripts stay
   stdlib-only; tests stay offline and derive dates from the run date (TD-24).
4. **"May I run `sync.sh` / `git config` / change a repo setting?"** No — see §5.
   Pass it up.
5. **"Is this entry safe to pick?"** Yes unless `ledger.py --pickable` lists it as blocked
   (`decision (Paul)` marks his calls — its Blocked section names them), it is on
   `docs/user_attention.md` awaiting Paul, its Status says the decision is his, or a sibling
   holds a claim (there is no sibling on this team).
6. **"What is the next TD number?"** Taken, never computed (cadence.md §2.10): `ao td next`, else
   `python3 files/scripts/ledger_next_id.py`, whose exit 3 is an id it could not reserve. Never
   quote a number from memory.

## 4. What is true right now that a cold reader would get wrong

Verify each before relying on it — several were true when written and may not be.

- **The SessionStart hooks run here since TD-038's partial fix** — a root `.claude/settings.json`
  (the seed's line pointing at `files/scripts/`, no permissions block; `tests/test_cadence_hooks.sh`
  pins it to the seed) and a runner that finds its children beside itself. Only a worktree whose
  branch carries that file runs them. Memory is git-tracked in `docs/claude-memory/`, and **the
  memory path is per checkout** (TD-080, cadence.md §7.2): `files/scripts/hydrate_worktree.sh` writes
  a worktree its own `settings.local.json` (gitignored, under `.claude/`) naming its own memory directory, so a session's
  note rides its PR. A worktree hydrated before TD-080 (2026-10-01) still carries the symlink to the main
  checkout's file until it is hydrated again (its SessionStart hook says so). `CLAUDE.md`
  records what is left.
- **The merge gate is the cadence/precheck status** (TD-148, cadence.md §4.12): `files/scripts/precheck.py --pr <n>`
  runs `docs/cadence.toml`'s `precheck` — ruff, then `./run_tests.sh` with `CI=true`, so a SKIP
  fails it — in a clean worktree at the PR's head and records the status the cadence check's `ci`
  row requires; right after a push it takes `--expect "$(git rev-parse HEAD)"` (TD-186). GitHub Actions (`.github/workflows/ci.yml`, TD-047) is not the gate: the account's
  minutes are one shared pool. Editing `.github/` is still Paul's, not a grinder's.
- **`bash tests/*.sh` runs only the first file** — the rest become its `$@`. A tally read off the
  last file is not the suite.
- **The cadence check exits 3 when any row is `unknown`** (TD-041, archived): 0 is the only
  merge signal; 3 means look (CI running, all skipped, gh unreadable). The path here is
  `files/scripts/check_cadence.py`; the `/cadence` skill names `scripts/`, which is wrong in this
  repo (the synced skill text; the scripts live under `files/` here).
- **This clone's hooks are TD-055 shims** in the clone's shared hooks dir (installed by Paul 2026-09-27;
  `core.hooksPath` unset): every worktree runs the main checkout's `files/scripts/git-hooks/`,
  whatever branch it is on. Changing this clone's git config stays Paul's step.
- **The reaper counts gitignored files as unclean** (TD-054, archived): anything ignored but
  `__pycache__/`, a symlink, a hydrate-covered nested worktree or the settings copy hydrate wrote
  (TD-080: one holding a permission of its own still counts) keeps a worktree, and the report
  names the paths.
- **The repo is squash-only and auto-deletes head branches.** So `gh pr merge <n> --squash`
  then `gh pr view <n> --json state`; never `--delete-branch` from a worktree, and no
  `git push origin --delete` afterwards.
- **The board's sweep stamp is stale** (`Swept: 2026-09-06` at the time of writing). A grinder
  may not run `/stranded-work` here — it ends with a direct push to main under the stamp
  carve-out, which is a person's.
- **Machine-scope state**: the roster `~/.config/agent-cadence/repos.txt` is append-only under
  flock, and only humans delete lines. `agent-cadence adopt`'s and `sync.sh --pin`'s last mutating
  step appends to it, which is why an ad-hoc run needs `AGENT_CADENCE_REG_DIR=$(mktemp -d)` (TD-029)
  and why the team never runs either at all.

## 5. What a grinder may never do — and so what you never approve

From `docs/briefs/README.md` and the grinder's brief. If a grinder asks for any of these, the
answer is no and it goes up:

- **Run `sync.sh --pin` or `agent-cadence adopt`** outside a test fixture — roster pollution, and
  a repo moved without its person.
- **Change this clone's git config**, the roster, `consumers.txt`, or anything under
  `~/.config/agent-cadence`.
- **Touch another repo's checkout**, GitHub repo settings (`gh api -X PATCH`,
  `files/scripts/adopt_repo_settings.sh --apply`), or `.github/`.
- **Push to main.** `ALLOW_MAIN_PUSH=1` is for the carve-outs in `files/docs/cadence.md` §4,
  and none of them is a grinder's.
- **Widen permissions** or edit `CLAUDE.md`'s rules.
- **Anything on `docs/user_attention.md`** that awaits Paul's decision.
- **Anything outward-facing**: nothing posted anywhere public, no spending, no credentials, no
  `~/.shiftlead`, `~/.claude`, systemd.

Your own limits are the same, plus: you answer from what is written down and say where
(`--source`); you check the asker's claims in the repo rather than accepting them; everything
else goes up with a recommendation and suggested answers. You hold **mail and nothing else** —
you do not edit the repo, open PRs, or run anything that mutates.

## 6. How this repo reviews, because grinders ask

`files/docs/cadence.md` §4 is the rule; `files/scripts/check_cadence.py --pr <n>` is the
detector. Every PR — **including doc-only** — gets an independent review by a **cheaper model
(Sonnet)**, never the author's own, and the evidence is one comment whose first line is exactly
`cadence-review: SHIP|FIXED|BLOCK · <model> · <code|docs> · <n> findings`. That line is
parsed (`REVIEW_RE` in the script) wherever it sits in the comment, the last if several (TD-087);
a malformed one reads as no review at all. The `review` row
is self-attested — *recorded*, never *verified*. It names the *first* review comment; a later one is the author's
follow-up. A PR merged with no review fails that row for good: the answer is a late review comment,
after which the row reads `acknowledged` — still a fail, with nothing left to do (TD-076,
`files/docs/cadence.md` §4.9). A late `BLOCK` is not acknowledged.

A reviewer briefed to **re-derive** the claim finds more than one briefed to read the diff. When a
grinder asks how to brief a review, point it at the premise, not the patch. **Mutation-check a
guard**, and say when the mutations were self-chosen.
When a grinder asks how many rounds: **one** for a change that adds no mechanism and alters no
rule (a wording, a constant, a comment, a rename) — fixed, re-verified, merged; iterated rounds are
for a new or changed mechanism or rule (§4.8, TD-123). Point the one reviewer at the tests the
change touches: that, not a second round, is what catches a test a reword silently disarmed.

Auto-merge threshold (§4.11 leaves it to each repo or person; this is agent-cadence's, and Paul's
layer's): cleanup, doc and self-contained fixes with review SHIP and the gate
green merge without asking. Behaviour changes a consumer would notice, and anything irreversible,
wait for Paul.

## 7. Decisions already made, and where each is written

- **Squash merge only; never commit to main; the pre-push hook is the local
  guard** — `files/docs/cadence.md` §4 *Give the rule teeth*.
- **Two routine carve-outs for `ALLOW_MAIN_PUSH=1`**: the sweep stamp (TD-16) and a tool-made
  Snooze/Done/Decide/Reply edit made through `files/scripts/board_edit.py` (adopted 2026-09-22, TD-036; Reply 2026-10-01, TD-075); a
  third for service-account board appends (2026-08-26) — all in §4. Their audit is the
  **Direct commits** section of `check_cadence.py --since` (TD-040): anything else on main
  without a PR fails it.
- **A board item carrying `Decided:` is a session's work order, not Paul's** (TD-036) — §3;
  claim it by its `Context:` ref, act, remove the line.
- **Due dates drive the wake-up** (TD-7, 2026-08-12) — §3.
- **One settings line wires every SessionStart hook** (2026-09-11) — §3; a hook is added to
  `files/scripts/cadence_hooks.sh`, never as a settings line.
- **Convention changes reach sessions through `files/docs/cadence-changes.md`, never as a TD per repo**
  (2026-09-11) — §3.
- **The review comment format** (2026-09-11) — §4.
- **Memories are git-tracked; memory is never a decision's only home** — §7.
- **Gates judge the index; detectors judge the disk** — §7.
- **Parity rules are written down once**, with the sweep stamp as the named pair — §7 and §3.
- **Machine scope is one file, the roster; scripts append, only humans delete** — §9.
- **Decisions live in `docs/plans/` and the ledger, not an ADR directory** — `CLAUDE.md`.
- **TD ids are zero-padded, priority is never in the id, the table lists exactly the bodies,
  resolved entries move to the archive** — §2.
- **The board store stays a markdown file in the repo** — TD-030 (its plan in `docs/plans/`, 2026-08-26).
- **The remote board tier** — TD-6 (its plan in `docs/plans/`, 2026-08-13).

## 8. Concurrency, because it bites

- The main checkout is Paul's anchor; every team seat runs in `.claude/worktrees/<name>`.
- `docs/ledger/` and `docs/user_attention.md` are high-churn: pull before editing,
  small edits, grep for conflict markers.
- **In consumers the post-merge hook reports reapable worktrees** (landed, clean, idle — see
  `files/scripts/reap_worktrees.sh` for the guards, and TD-043 for how liveness can misread).
  Here too, since TD-038's follow-up: the hook finds the reaper one level up from its own directory
  (`files/scripts/git-hooks/post-merge` → `files/scripts/reap_worktrees.sh`). It only *reports* (no `--reap`); removal stays by hand.
- A claim is announced before the work (`ao progress claim`), not before the PR.
- A crashed seat is restarted by the ShiftLead host agent from its launch record, with the
  brief filled as at start; a hand `ao new --prompt` would ship `{lane}` and `{techlead}`
  literally. The manager never restarts by hand (ShiftLead's manager template, *A round*).

## 9. Reading a TD entry honestly

Each `## TD-NNN` has a `**Status:**` line, and it is often the stalest thing in the entry.
`CLAUDE.md` says it plainly: verify a TD's status against the code before working it. The
2026-09-22 entries are long because they carry the evidence that justified them; the useful parts
are **Location** (with `~` on every line number), **Why** (what is actually wrong) and **Fix** (a
proposal, not a spec). When the entry and the code disagree, the code settles it, and the entry
gets corrected in the same PR.
Before working one, `python3 files/scripts/forge.py in-flight TD-NNN` says whether a PR or a branch
already carries it (cadence.md §2.9).

---

**When you finish a batch**, your summary says what you answered, what you passed up and why,
and — if anything on this page turned out to be stale — that, in words, so it gets fixed.
