# agent-cadence

agent-cadence is a working cadence for repos where AI coding agents do work: a rule set for how
concurrent sessions share a checkout, track what they defer, keep the person informed and get changes merged,
plus the hooks, checks and CLI helpers that enforce or detect each rule. It is for a developer running one or
more agent sessions (currently Claude Code, Codex, Gemini CLI, with more coming) on a repo who has lost work that only existed in a chat,
merged a PR nobody reviewed, or found two sessions committing on one checkout.

The goal is that different agent tools can work the same repo, or a set of repos, side by side, with every
piece of work tracked and nothing lost between sessions. That lets someone who understands how LLM agents work
get the most out of them: run several at once, hand work from one tool to another, and step away without
losing the thread.

None of the tooling is copied into your repo, which holds only the files it owns. A repo names a commit of this repo in `docs/cadence.toml` (a *pin*), and a
one-file launcher, `agent-cadence`, runs the pinned tree's tools from a per-machine cache. Everything in the tree
is stdlib-only Python 3 or bash, so an agent session can read, run and patch any of it on the spot. Claude Code is
wired through one SessionStart hook line and skills; Codex and Gemini CLI get the same rules and procedures
through `AGENTS.md` and `.agents/skills/`.

**The rules are [`files/docs/cadence.md`](files/docs/cadence.md)**, numbered so any one is citable; the reasoning
behind each is [`files/docs/cadence-rationale.md`](files/docs/cadence-rationale.md). The rest of this file is what
the tooling gives you and how to adopt it.

## What you get

Each rule ships with the tool that enforces it, or the check that notices when it is broken.

- **One session per checkout** (cadence.md §1). The first session in a checkout keeps it (the *anchor*); every
  other concurrent session works in a git worktree, so no two sessions share a HEAD, index or working files. A
  SessionStart hook, `check_anchor.py`, reads the live sessions of every tool it can see (Claude Code, Codex,
  Gemini CLI), says so when a tool the repo lists in its `agents` setting cannot be seen, and warns a second
  session into a worktree.
  `hydrate_worktree.sh` completes a worktree with what git does not track, `reap_worktrees.sh` removes those
  whose work has landed, and `check_base.py` tells a resumed session when its branch has already merged.
- **A ledger of deferred work** (§2). Anything found and not fixed gets a `TD-NNN` (technical debt) entry, with a *Why* and a
  *Fix*, in `docs/technical_debt.md` or, split, one file per entry under `docs/ledger/`. `ledger.py --check`
  validates entries and `--pickable` prints what is ready to work, in order; `ledger_next_id.py` takes ids from a
  counter branch on origin so two sessions never take the same number; `forge.py in-flight TD-NNN` says whether
  a PR or branch already has an entry.
- **Never strand work** (§3). Anything that needs the person goes on a board, `docs/user_attention.md`, as an
  item with a due date. The SessionStart hook prints what is due; `/attention` is the full report; the
  `/stranded-work` sweep hunts for work left in worktrees, branches, stashes and closed sessions' transcripts.
  Convention changes are announced in an append-only `cadence-changes.md`, which the hook prints once per
  worktree.
- **Branch, PR, review, squash** (§4). A pre-push hook blocks a direct push to the default branch
  (`ALLOW_MAIN_PUSH=1` is the deliberate override). Every PR gets an independent review by a cheaper model,
  recorded as a `cadence-review:` comment on the PR. `precheck.py` runs the repo's own test command on the PR's
  head in a clean worktree and records a `cadence/precheck` commit status, so the merge gate spends no CI
  minutes. `/cadence` (`check_cadence.py --pr N`) reads a PR against the §1–§5 rules and prints one row per rule;
  it is a detector, not a gate.
- **Memory in the repo** (§7). A session's memory lives in `docs/claude-memory/` whichever tool it runs in
  (Claude Code writes it through its auto-memory; Codex and Gemini CLI, by hand as `AGENTS.md` tells them),
  git-tracked and reviewed like any other change. A hook warns when memory is left uncommitted or when this
  clone's git hooks are missing (so the main-push block is off), and, for Claude Code, when its auto-memory
  points elsewhere. `/memory-harvest`
  moves process lessons out of memories and into your own rules.
- **The wiring.** One SessionStart line in `.claude/settings.json` (Claude Code), or `agent-cadence hook
  session-start`, which the seeded `AGENTS.md` has Codex and Gemini CLI run first, runs the hook set (memory guard, anchor guard,
  worktree hydration, due items, base check, convention changes, a temp-space check, your layers;
  `cadence_hooks.sh --list` names them), and three git hook shims run `pre-push` (blocks a push to main), `post-merge` (names worktrees that can now be
  reaped) and `prepare-commit-msg` (the last adds an agent's `Co-Authored-By:` trailer when `AGENT_NAME` is set). The hook
  line and the shims read the main checkout's pin, so every worktree runs the same version.

## How it runs: pinned, not copied

A repo names the agent-cadence it runs in `docs/cadence.toml`:

```toml
[agent-cadence]
source = "https://github.com/ShiftLead/agent-cadence"
ref = "<a full commit>"
```

The launcher, `agent-cadence`, is one Python file installed once per machine. It resolves that pin, makes a
read-only tree of the commit under `~/.cache/agent-cadence/trees/<commit>` on first use, and runs a word from it:

| Word | Does |
|---|---|
| `agent-cadence run <script> [args]` | run a tool from the pinned tree's `scripts/` (`agent-cadence run ledger.py --pickable`) |
| `agent-cadence path [<name>]` | print the pinned tree, or a file in it (`agent-cadence path cadence.md`) |
| `agent-cadence hook <name>` | what the SessionStart line and the git hook shims call; reads the main checkout's pin |
| `agent-cadence bump [<tag or commit>]` | say how far the pin is behind and name newer tags, or move it (see Upgrading) |
| `agent-cadence adopt <repo>` | pin a new repo (see Adopt a repo) |
| `agent-cadence gc [--apply]` | list cached trees no repo on this machine pins; `--apply` removes them |

`-C <dir>` works as git's. The pin is a full commit, never a tag or branch, so what a repo runs cannot change
without a PR. The rule is cadence.md §9.19.

## Requirements

- git, bash and Python 3.11 or later (the launcher and the settings reader use `tomllib`).
- `gh` (GitHub) or `glab` (GitLab) for everything that reads PRs: the review check, the precheck status, the
  open-PR line at session start. A repo with no PR host (no GitHub or GitLab API) sets `forge = "none"`, and the review line goes in the
  squash commit's body instead.
- Claude Code runs the SessionStart hook and the skills as shipped. Codex and Gemini CLI run the same hook set by
  hand, `agent-cadence hook session-start`, which the seeded `AGENTS.md` asks for first, and read the same
  procedures from `.agents/skills/`.

## Install the launcher

Once per machine, or in a cloud environment's setup script. The line installs release `v0.1.0`; when a newer
tag exists, change the tag in the line:

```bash
d=$(mktemp -d) && git clone -q --depth 1 --branch v0.1.0 https://github.com/ShiftLead/agent-cadence "$d" \
  && mkdir -p ~/.local/bin && install -m 755 "$d/launcher/agent_cadence.py" ~/.local/bin/agent-cadence \
  && rm -rf "$d"   # ~/.local/bin must be on PATH
```

The launcher is the one unpinned piece and its interface is frozen: two launchers on one machine share one cache,
and an older one refuses a tree it cannot run, printing the install line.

## Adopt a repo

**Evaluate first, if you want to.** Have a session in the candidate repo read the rules and compare them with how
the repo really works, in both directions:

```text
Let's evaluate https://github.com/ShiftLead/agent-cadence for our use case
here in <this repo>. Read its README and files/docs/cadence.md, compare
against how this repo actually works, and tell me what fits, what needs
adapting, and what doesn't apply. Also look the other direction: are there
lessons we have learned here (conventions, guards, incidents) that
agent-cadence should take? Write those up as findings, or as PRs against
agent-cadence if you can open them. No silent local adaptations. Don't
install anything yet.
```

**Then adopt:**

```bash
git clone https://github.com/ShiftLead/agent-cadence
agent-cadence -C agent-cadence adopt /path/to/your-repo
```

`adopt` runs from the clone's HEAD, which must be clean and on origin's default branch (the pin names a commit
origin has). It reads the target repo's existing ledger and board first and refuses, naming what it found, if they
do not parse. Otherwise it

- creates the *seed* files the repo then owns, where missing: the ledger and board, `docs/claude-memory/MEMORY.md`,
  `docs/cadence.toml`, `AGENTS.md`, `.gemini/settings.json`, `.gitattributes`, `.claude/settings.json` with the
  SessionStart line, and the skill pointers under `.claude/skills/` and `.agents/skills/`;
- appends the `[agent-cadence]` pin to `docs/cadence.toml`;
- installs the git hook shims in the target repo's `.git/hooks` (the main checkout's, shared by its worktrees);
- adds the `.gitignore` lines the cadence needs (the worktree directory, the session index, local settings, `*.code-workspace`);
- sets this clone's memory path for Claude Code (`autoMemoryDirectory` in `.claude/settings.local.json`);
- registers the repo in this machine's *roster*, `~/.config/agent-cadence/repos.txt`, which the attention report
  and cross-repo `Blocked by` references read.

It commits nothing: review the result and land it through a PR like any change. Then finish cadence.md's
*Adoption checklist*: the map in `AGENTS.md`, the `precheck`
command in `docs/cadence.toml`, and the forge's merge settings (`agent-cadence run adopt_repo_settings.sh --check`
shows the drift, `--apply` sets them).

<details>
<summary>Or have a session do the setup: a prompt to paste</summary>

```text
Set up agent-cadence in this repo:

1. If `agent-cadence` is not on PATH, install the launcher (its README,
   "Install the launcher"). Clone https://github.com/ShiftLead/agent-cadence
   (or pull the existing clone) and run `agent-cadence -C <the clone> adopt
   <this repo's root>`. Heed any WARN lines. Then read the rules this repo
   now runs: `agent-cadence path cadence.md`.
2. Do the Adoption checklist's one-time steps that adopt does not:
   - for Claude Code, if .claude/settings.json already existed, add the ONE SessionStart line
     from agent-cadence's files/.claude/settings.json;
   - on each other machine's clone, run adopt again (it changes only what is
     missing, the memory path among it).
3. Fill in the AGENTS.md map that adopt seeded: a Session Hygiene section
   and doc-map rows for the rules, the ledger and the board. Codex reads
   AGENTS.md as is, and adopt's .gemini/settings.json points Gemini CLI at it;
   for Claude Code, make CLAUDE.md the one line `@AGENTS.md`.
4. Set `precheck` in docs/cadence.toml to this repo's whole check as one
   command. Propose, without applying, the forge settings from cadence.md §4:
   squash-merge only, delete branches on merge, and a 0-approval PR-required
   ruleset if the plan allows one (`agent-cadence run adopt_repo_settings.sh
   --check` shows the drift).
5. Adapt anything cadence.md marks *(adapt per repo)* to this repo's stack,
   in AGENTS.md or docs/cadence.toml, never in the pinned files.
6. If other git repos are nested inside this one, run
   `agent-cadence run hydrate_worktree.sh --detect` and ask me which mode
   each gets in docs/nested-repos.txt (cadence.md, Constellations: nested repos).
7. Verify: `agent-cadence run list_sessions.py` runs; the pre-push shim blocks
   a main push (`echo "r s refs/heads/main s" | .git/hooks/pre-push origin x`
   exits 1); `agent-cadence run check_claude_memory.sh` passes.
8. Commit all of it through a branch and a PR with a review, not to main.
```

</details>

## Day to day

| What | How |
|---|---|
| What does the cadence check say about this PR? | `/cadence` (or `agent-cadence run check_cadence.py --pr N`) |
| Run the merge gate | `agent-cadence run precheck.py --pr N --expect <sha>` |
| What needs me? | `/attention` (or `agent-cadence run nudge_user_attention.py --report`) |
| Has any work been left behind? | `/stranded-work` |
| What can be worked next? | `agent-cadence run ledger.py --pickable` |
| Is someone already on TD-NNN? | `agent-cadence run forge.py in-flight TD-NNN` |
| A new ledger id | `agent-cadence run ledger_next_id.py` |
| Which session holds this checkout? | `agent-cadence run check_anchor.py` |
| Clean up landed worktrees | `agent-cadence run reap_worktrees.sh [--reap]` |
| Carry memories' process rules into your own rules | `/memory-harvest` |
| Move to a newer agent-cadence | `agent-cadence bump [<tag or commit>]` |

## Configuration

- **A repo's settings** live in its `docs/cadence.toml`: the `precheck` command, the review model, the agent
  tools that work it (`agents`), the forge, the worktree root, the thresholds (when an open PR is named at
  session start, when an overdue board item is escalated) and its opt-outs. Every reader goes through
  `cadence_config.py`; `agent-cadence run cadence_config.py` prints each key with its value and source. People
  write the file and tools never rewrite it. The keys are listed in cadence.md §9.18.
- **Your own rules, for all your repos,** live in a *layer*: a markdown file of rules keyed to the § they change
  (`§4.11 override: …`, `§4.8 add: …`), kept in a git repo you own and named under `[[layers]]` in the
  machine's `~/.config/agent-cadence/cadence.toml`. The SessionStart hook prints it. When rules conflict, the
  repo's `AGENTS.md` wins, then the layers (a later one over an earlier), then `cadence.md`. A layer is prose,
  so it cannot replace a shared tool or turn off a gate. `agent-cadence run cadence_layer.py --effective` shows what each rule does;
  `--follow` takes someone else's published layer at a pinned ref.

## Upgrading

An agent-cadence upgrade is a PR in your repo. `agent-cadence bump` lists what is newer than the pin; `agent-cadence bump <tag
or commit>` moves the `ref` line to a commit on the source's default branch, refreshes any skill pointer the repo
has not edited, and prints the PR body: the compare and the `cadence-changes.md` entries since the old pin.
Review the compare and merge it like any other change.

## With ShiftLead (optional)

[ShiftLead](https://github.com/ShiftLead/shiftlead), not released yet, is this organization's product: a self-hosted
dashboard and CLI that runs teams of unattended agent sessions (a manager, an optional techlead and workers that
pick ledger entries and take them to merged PRs) on a cadence repo. It reads a repo's ledger and board through
the same `ledgerboard` module the cadence tools use, and this machine's roster, so a repo needs nothing beyond
the cadence to be worked by it. agent-cadence supports it, and is used on its own just as well: nothing here
depends on ShiftLead. This repo's own team definition is its
`.shiftlead.yml`.

## Philosophy and non-goals

- **Many tools, one record.** The rules are written for any agent tool, and the record they keep (ledger, board,
  memory, PRs) lives in git, where every tool and every session can read it. No session's chat is the only copy
  of anything.
- **A pinned tree, not a package.** Every upgrade is a reviewable diff in the repo's own history, the pin line
  and nothing the repo edited, and the tools stay plain files a session can read. There is one vendored file:
  `files/scripts/ledgerboard.py`, the ledger and board formats, copied from a tagged
  [ShiftLead/ledgerboard](https://github.com/ShiftLead/ledgerboard) release so every reader parses them the
  same way.
- **The repo carries only what it owns**: its board, ledger, memory, settings and map. A repo shared with people
  who do not use the cadence is not asked to carry anything else.
- **Detectors over gates.** Most checks report and leave the decision to the session; the hard stops are the
  pre-push guard and the precheck, and each has a documented override or carve-out.
- **Not goals:**
  - merging bump PRs automatically: review stays with a person, or a session they direct;
  - a GitHub Actions distribution path: repos may live where an Action cannot reach;
  - any central service: the git remotes, the boards and the ledgers are the only shared state.

## Working on agent-cadence

This repo runs its own cadence. Its live ledger is `docs/ledger/` and its board `docs/user_attention.md`, which
are distinct from the `files/docs/` templates that `adopt` seeds. Its decisions are in `docs/plans/`. Every edit
to the system happens under `files/`; `launcher/`, `tests/` and `sync.sh` are tooling. Run the suite with
`./run_tests.sh`, which the precheck runs with `CI=true`, and `ruff check files/scripts/` for lint.

### File classes

What `adopt` reads from `sync.sh`'s three lists. Nothing is copied into a repo: a pinned repo runs the SYNC files from the pinned tree.

| Class | Behavior | Files |
|---|---|---|
| SYNC | the payload, run from the pinned tree and never present in the repo — edit here | `docs/cadence.md`, `docs/cadence-rationale.md`, `docs/cadence-incidents.md`, `docs/cadence-changes.md`, `docs/adr-template.md`, `docs/procedures/stranded-work.md`, `docs/procedures/attention.md`, `docs/procedures/cadence.md`, `docs/procedures/memory-harvest.md` (the procedures any agent follows, TD-093; the memory harvest, TD-125), stranded-work + attention + cadence + memory-harvest skills (each a pointer to its procedure, once under .claude/skills for Claude Code and again under .agents/skills for Codex and Gemini CLI, TD-127), `check_claude_memory.sh`, `check_anchor.py`, `agent_sessions.py`, `forge.py`, `nudge_user_attention.py`, `board_edit.py`, `ledger.py`, `ledger_next_id.py` (hands out ledger ids from the counter branch on origin, TD-124), `ledgerboard.py` (vendored from ShiftLead/ledgerboard: the ledger and board formats, defined once), `list_sessions.py`, `generate_session_index.sh`, `generate_workspace.sh`, `open_worktree.sh`, `hydrate_worktree.sh`, `reap_worktrees.sh`, `adopt_repo_settings.sh`, `check_cadence.py`, `precheck.py` (a repo's own checks on a PR's head, recorded as a commit status, TD-117), `check_base.py`, `check_tmp.py` (warns at session start before the shared temp filesystem runs out of inodes or space, TD-154), `cadence_changes.py`, `cadence_config.py`, `cadence_layer.py` (prints the person's own cadence layers at session start, TD-126, and follows someone else's at a checked pin, TD-130), `memory_harvest.py` (the memory harvest's read-only inventory of every roster repo's memories, and the record of what was judged, TD-125), `review_stats.py` (design-review outcomes rebuilt on demand from every roster repo's review records and Escaped from fields, TD-204), `cadence_hooks.sh`, `install_git_hooks.sh`, `git-hooks/pre-push`, `git-hooks/post-merge`, `git-hooks/prepare-commit-msg` |
| SEED | created by `adopt` if missing, never overwritten — the repo owns the content | `technical_debt.md` + archive (neither beside a v2 ledger directory, TD-160), `user_attention.md`, `claude-memory/MEMORY.md`, `.claude/settings.json`, `cadence.toml` (the repo's settings, TD-096), `AGENTS.md` (the map any agent tool reads, with the cadence's wake-up first, TD-092), `.gemini/settings.json` (makes Gemini CLI read `AGENTS.md`, TD-111), `.gitattributes` (text is LF, cadence.md §7.14, TD-187) |
| RETIRED | once SYNC, now dropped from the payload | (none yet) |

Adding or removing a payload file means editing both the array in `sync.sh` and this table
(`tests/test_readme_sync_table.sh` holds them together). Every SYNC file carries a two-line header naming its
canonical path here.

## License

MIT; see [LICENSE](LICENSE).
