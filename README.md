# agent-cadence

agent-cadence is a working cadence for AI coding agents. It is a set of rules for how sessions share a repo, keep
track of work and get changes merged, with small scripts that check those rules. It grew out of one person
running several Claude Code sessions at once on the same repos. An audit there showed that anything written to a
ledger survived when a session closed, and anything left in chat was lost. The rules exist to make the first one
the default.

The scripts are plain bash and stdlib-only Python, so a session can read, run and patch any of them on the spot.
A repo runs them from a **pin**, a commit of this repo named in its own config. None of the system's files are
copied into the repo, and there is no package. It works with Claude Code directly. Codex and Gemini CLI read the same rules
through `AGENTS.md` and `.agents/skills/`.

**The rules themselves are [`files/docs/cadence.md`](files/docs/cadence.md).** Everything below is how to get
them into a repo.

## What a repo gets

Each rule comes with the tool that enforces it, or the check that notices when it is broken.

- **Worktrees, and one anchor** (cadence.md §1). One session, the *anchor*, keeps the main checkout; every other session works
  in a worktree of its own, so concurrent sessions never edit the same files. `open_worktree.sh` makes one,
  `hydrate_worktree.sh` brings in what git does not track, and `reap_worktrees.sh` removes those whose work has
  landed.
- **A ledger of deferred work** (§2). Every problem not fixed now gets an entry: one file per entry under
  `docs/ledger/`, with a *Why*, a *Fix* and an optional `Blocked by`. `ledger_next_id.py` hands out ids from a
  counter on origin, so two sessions never take the same number. `ledger.py --pickable` lists what is ready to
  work.
- **Never strand work** (§3). Anything that needs the person goes on an attention board,
  `docs/user_attention.md`, with a due date. A session-start hook prints what is due. The `/stranded-work`
  sweep finds work left in worktrees, branches and stashes.
- **Branch, PR, review, squash** (§4). Nothing goes straight to main: the pre-push hook blocks it. Every PR
  gets an independent review, and a local *precheck* (`precheck.py`, which runs the repo's own tests on the PR's
  head in a clean worktree) records a `cadence/precheck` status. `/cadence` reads a PR against every rule and says which hold.
- **Memory in the repo** (§7). A session's memory lives in the repo's `docs/claude-memory/` and goes through
  review like any other change, instead of sitting in one machine's home directory.
- **Delivery.** All of this reaches a session through one SessionStart line in `.claude/settings.json` and
  three git hook shims (`pre-push`, `post-merge`, `prepare-commit-msg`). The settings line and the shims both run
  the main checkout's pin.

## How it runs: pinned, not copied

A repo names the agent-cadence it runs in `docs/cadence.toml`:

```toml
[agent-cadence]
source = "https://github.com/ShiftLead/agent-cadence"
ref = "<a full commit>"
```

The **launcher**, `agent-cadence`, is one Python file installed once per machine. It fetches that commit into a
read-only cache (`~/.cache/agent-cadence/trees/<commit>`) and runs the scripts from there:
`agent-cadence run ledger.py --pickable`, or `agent-cadence path cadence.md` to name a file. An upgrade is a
bump: `agent-cadence bump` lists what is newer than the pin, and `agent-cadence bump <tag or commit>` moves the
one `ref` line and prints what the PR body carries, the compare and the convention changes since the old pin.
The repo reviews and merges that PR like any other. The rule is
cadence.md §9.19.

## Quick start

You need git and Python 3.11 or later. The PR checks use `gh` (GitHub) or `glab` (GitLab).

**1. Install the launcher**, once per machine or in a cloud environment's setup script. Use the latest release
tag in place of `main` once one exists:

```bash
d=$(mktemp -d) && git clone -q --depth 1 --branch main https://github.com/ShiftLead/agent-cadence "$d" \
  && install -Dm755 "$d/launcher/agent_cadence.py" ~/.local/bin/agent-cadence && rm -rf "$d"   # ~/.local/bin on PATH
```

**2. Evaluate before adopting.** Have a session in the candidate repo read the system and compare it with how
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

Both directions have paid off: evaluations have caught bugs before they were adopted, and several of the
system's guards came from lessons sent upstream this way.

**3. Adopt the repo:**

```bash
git clone https://github.com/ShiftLead/agent-cadence
agent-cadence -C agent-cadence adopt /path/to/your-repo
```

`adopt` pins the repo to the clone's HEAD, so that HEAD must be clean and on origin's default branch: the pin
names a commit, and it must be one origin has. It writes the *seed* files the repo then owns (ledger, board,
memory index, `AGENTS.md`, settings), the skill pointers, the pin, the git hook shims, and this machine's
*roster* line: `~/.config/agent-cadence/repos.txt`, the list of cadence repos that the attention report and
cross-repo `Blocked by` read. It commits nothing. Then follow cadence.md's *Adoption checklist*: the
memory path, `.gitignore`, the map in `AGENTS.md`, and the GitHub settings.

<details>
<summary>Or have a session do the setup: a prompt to paste</summary>

```text
Set up agent-cadence in this repo:

1. If `agent-cadence` is not on PATH, install the launcher (its README,
   "Quick start"). Clone https://github.com/ShiftLead/agent-cadence (or pull
   the existing clone) and run `agent-cadence -C <the clone> adopt <this
   repo's root>`. Heed any WARN lines. Then read the rules this repo now runs:
   `agent-cadence path cadence.md`.
2. Do the Adoption checklist's one-time steps that adopt does not:
   - merge this clone's absolute docs/claude-memory path into
     .claude/settings.local.json as autoMemoryDirectory;
   - add .claude/worktrees/ and .claude/settings.local.json to .gitignore;
   - if .claude/settings.json already existed, add the ONE SessionStart line
     from agent-cadence's files/.claude/settings.json;
   - on each other machine's clone, run adopt again (it changes only what is
     missing) and set the memory path there.
3. Fill in the AGENTS.md map that adopt seeded: a Session Hygiene section
   and doc-map rows for the rules, the ledger and the board; make CLAUDE.md
   the one line `@AGENTS.md`.
4. Propose, without applying, the GitHub settings from cadence.md §4:
   squash-merge only, delete branches on merge, and a 0-approval PR-required
   ruleset if the plan allows one (`agent-cadence run adopt_repo_settings.sh`
   checks them).
5. Adapt anything cadence.md marks *(adapt per repo)* to this repo's stack,
   in AGENTS.md or docs/cadence.toml, never in the pinned files.
6. If other git repos are nested inside this one, run
   `agent-cadence run hydrate_worktree.sh --detect` and ask me which mode
   each gets in docs/nested-repos.txt (cadence.md, Constellations).
7. Verify: `agent-cadence run list_sessions.py` runs; the pre-push shim blocks
   a main push (`echo "r s refs/heads/main s" | .git/hooks/pre-push origin x`
   exits 1); `agent-cadence run check_claude_memory.sh` passes.
8. Commit all of it through a branch and a PR with a review, not to main.
```

</details>

## Day to day

| What | How |
|---|---|
| Is this PR ready to merge? | `/cadence` (or `agent-cadence run check_cadence.py --pr N`) |
| Run the merge gate | `agent-cadence run precheck.py --pr N --expect <sha>` |
| What needs me? | `/attention` (or `agent-cadence run nudge_user_attention.py --report`) |
| Has any work been left behind? | `/stranded-work` |
| What can be worked next? | `agent-cadence run ledger.py --pickable` |
| A new ledger id | `agent-cadence run ledger_next_id.py` |
| Clean up landed worktrees | `agent-cadence run reap_worktrees.sh [--reap]` |
| Move to a newer agent-cadence | `agent-cadence bump [<tag or commit>]` |
| Carry memories' process rules into your own rules | `/memory-harvest` |

## Your own rules

- **A repo's settings** live in its `docs/cadence.toml`: its `precheck` command, its opt-outs, and thresholds
  such as when an overdue board item is escalated (cadence.md §9.18).
- **A person's own rules** live in a *layer*: a markdown file of rules keyed to the § they change, such as
  `§4.11 override: …`, named in the machine's `~/.config/agent-cadence/cadence.toml`. The session-start hook prints
  it. When rules conflict, the repo's `AGENTS.md` wins, then the layers (a later one over an earlier), then
  `cadence.md`. A layer is prose, so it cannot switch off a gate.
  `agent-cadence run cadence_layer.py --effective` shows what each rule does.

## With ShiftLead (optional)

[ShiftLead](https://github.com/ShiftLead/shiftlead) runs teams of unattended sessions: a manager, a techlead and
grinders that pick ledger entries and take them to review. It reads the same pin, ledger and board, so a repo
needs nothing extra. This repo's own team is defined in its `.shiftlead.yml`.

## Philosophy and non-goals

- **A pinned tree, not a package.** Every upgrade is a reviewable one-line diff in the repo's own history, and
  the scripts stay plain files a session can read. There is one vendored file: `files/scripts/ledgerboard.py`,
  the ledger and board formats, copied from a tagged
  [ShiftLead/ledgerboard](https://github.com/ShiftLead/ledgerboard) release.
- **The repo carries only what it owns**: its board, ledger, memory, settings and map. A repo shared with people
  who do not use the cadence is not asked to carry its files.
- **Not goals:**
  - merging bump PRs automatically: review stays with a person, or a session they direct;
  - a GitHub Actions distribution path: repos may live where an Action cannot reach;
  - any central service: the git remotes, the boards and the ledgers are the only shared state.

## Working on agent-cadence

This repo runs its own cadence. Its live ledger is `docs/ledger/` and its board `docs/user_attention.md`, which
are distinct from the `files/docs/` templates that `adopt` seeds. Its decisions are in `docs/plans/`. Every edit
to the system happens under `files/`; `launcher/`, `tests/` and `sync.sh` are tooling. Run the suite with
`./run_tests.sh`, which the precheck runs with `CI=true`.

### File classes

What `adopt` reads from `sync.sh`'s three lists. Nothing is copied into a repo any more: a pinned repo runs the SYNC files from the pinned tree (TD-129).

| Class | Behavior | Files |
|---|---|---|
| SYNC | the payload, run from the pinned tree and never present in the repo — edit here; `adopt` refuses a repo that still carries a copy, and `sync.sh --pin` removes each one still matching its lock | `docs/cadence.md`, `docs/cadence-rationale.md`, `docs/cadence-incidents.md`, `docs/cadence-changes.md`, `docs/adr-template.md`, `docs/procedures/stranded-work.md`, `docs/procedures/attention.md`, `docs/procedures/cadence.md`, `docs/procedures/memory-harvest.md` (the procedures any agent follows, TD-093; the memory harvest, TD-125), stranded-work + attention + cadence + memory-harvest skills (each a pointer to its procedure, once under .claude/skills for Claude Code and again under .agents/skills for Codex and Gemini CLI, TD-127), `check_claude_memory.sh`, `check_anchor.py`, `agent_sessions.py`, `forge.py`, `nudge_user_attention.py`, `board_edit.py`, `ledger.py`, `ledger_next_id.py` (hands out ledger ids from the counter branch on origin, TD-124), `ledgerboard.py` (vendored from ShiftLead/ledgerboard: the ledger and board formats, defined once), `list_sessions.py`, `generate_session_index.sh`, `generate_workspace.sh`, `open_worktree.sh`, `hydrate_worktree.sh`, `reap_worktrees.sh`, `adopt_repo_settings.sh`, `check_cadence.py`, `precheck.py` (a repo's own checks on a PR's head, recorded as a commit status, TD-117), `check_base.py`, `check_tmp.py` (warns at session start before the shared temp filesystem runs out of inodes or space, TD-154), `cadence_changes.py`, `cadence_config.py`, `cadence_layer.py` (prints the person's own cadence layers at session start, TD-126, and follows someone else's at a checked pin, TD-130), `memory_harvest.py` (the memory harvest's read-only inventory of every roster repo's memories, and the record of what was judged, TD-125), `cadence_hooks.sh`, `install_git_hooks.sh`, `git-hooks/pre-push`, `git-hooks/post-merge`, `git-hooks/prepare-commit-msg` |
| SEED | created by `adopt` if missing, never overwritten — the repo owns the content | `technical_debt.md` + archive (neither beside a v2 ledger directory, TD-160), `user_attention.md`, `claude-memory/MEMORY.md`, `.claude/settings.json`, `cadence.toml` (the repo's settings, TD-096), `AGENTS.md` (the map any agent tool reads, with the cadence's wake-up first, TD-092), `.gemini/settings.json` (makes Gemini CLI read `AGENTS.md`, TD-111) |
| RETIRED | once SYNC, dropped from the payload before the pin (TD-057) | (none yet) |

Adding or removing a payload file means editing both the array in `sync.sh` and this table
(`tests/test_readme_sync_table.sh` holds them together). Every SYNC file carries a two-line header naming its
canonical path here. A repo that still carries the old synced copies moves to a pin with `./sync.sh --pin
<repo>`, by hand, one repo at a time.

## License

MIT; see [LICENSE](LICENSE). The history before the cut-over to this repo is not published.
