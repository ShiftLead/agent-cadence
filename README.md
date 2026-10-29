# agent-cadence

> This is the canonical repo of agent-cadence; its history before the cut-over is kept privately.

The portable working-cadence system for one human plus multiple concurrent Claude Code sessions: never-strand-work rules, a technical-debt ledger, a user-attention board with due-date nudges, a review-before-merge loop, and guard rails (pre-push main block, memory guard). Born in a consumer repo after a stranded-work audit showed that everything written to a ledger survives session closure and everything left in chat does not.

**Read [`files/docs/cadence.md`](files/docs/cadence.md) first** — it is the system; this repo is its canonical source, which each repo runs from a pin.

## Evaluate before adopting (recommended first step)

Don't install blind — have a session in the candidate repo evaluate the system first, in **both directions**. Paste something like:

```text
Let's evaluate https://github.com/ShiftLead/agent-cadence for our use case
here in <this repo>. Read its README and files/docs/cadence.md, compare
against how this repo actually works, and tell me what fits, what needs
adapting, and what doesn't apply. Also look the other direction: are there
lessons we have learned here (conventions, guards, incidents) that we should
consider incorporating into agent-cadence? File those as PRs against agent-cadence
(clone it if needed and branch → PR there, per its cadence.md §4) — or, if you
can't open PRs from here, write them up as findings for me to hand over. No
silent local adaptations. Don't install anything yet.
```

Both directions have paid off in practice: the evaluate-first direction catches upstream
bugs before they're adopted (a path-munging bug that only manifests in repos with `_` in
their name was found exactly this way, during an adoption evaluation), and the
lessons-upstream direction is where several of the system's guards and diagnostics came
from. Evaluation PRs against this repo go through the normal branch → PR → review loop
(cadence.md §4) — the adopting session opens them; review and merge stay with the
maintainer's sessions.

When the evaluation says adopt, continue with the setup prompt below.

## Set up via an LLM

Most repos will be set up by a Claude Code session (or another LLM agent) running in the target repo. Paste this prompt — the agent does the rest; if the agent is reading this README during setup, this section is the instruction set and everything else here is context:

```text
Set up the agent-cadence working-cadence system in this repo:

1. Install the agent-cadence launcher once on this machine if `agent-cadence` is
   not on PATH (README "Install the launcher"). Clone
   https://github.com/ShiftLead/agent-cadence (or git pull the existing clone)
   and run `agent-cadence -C <the clone> adopt <this repo's root>`. It writes the
   seeds, the [agent-cadence] pin in docs/cadence.toml, the git hook shims and
   this machine's roster line, and commits nothing; heed any WARN lines. Then
   read the rules the repo now runs: `agent-cadence path cadence.md`.
2. One-time setup adopt does not do (cadence.md Adoption checklist step 2):
   - merge this clone's absolute docs/claude-memory path into
     .claude/settings.local.json as autoMemoryDirectory
   - add .claude/worktrees/ and .claude/settings.local.json to .gitignore
   - if .claude/settings.json already existed, add the ONE SessionStart
     line from agent-cadence's files/.claude/settings.json
   - on each additional machine's clone, run adopt again (it changes only
     what is missing) and set the memory path there
3. Add to this repo's AGENTS.md map (seeded; CLAUDE.md is the line
   @AGENTS.md): a "Session Hygiene — Never Strand Work" section
   (ledger-before-idle; user_attention.md board entries with Due: dates;
   periodic /stranded-work sweep) and doc-map rows for the rules
   (`agent-cadence path cadence.md`), docs/technical_debt.md and
   docs/user_attention.md.
4. Propose (don't apply without my go-ahead) the GitHub settings from
   cadence.md §4: squash-merge as the PR merge method, and a 0-approval
   PR-required branch ruleset if the plan allows it. The pre-push hook shim
   is already the local guard either way.
5. Due-date surfacing needs NO wiring — the SessionStart due-items line
   ships live in the settings template. Ask me only about the OPTIONAL
   external push channel (a cron/scheduler running
   `agent-cadence run nudge_user_attention.py --board <this repo's docs/user_attention.md>`
   with NUDGE_COMMAND, or TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID via the
   repo's secrets manager) — don't wire that without asking.
6. Adapt anything marked (adapt per repo) in cadence.md to this repo's stack.
6b. If this repo has OTHER git repos nested inside it (a constellation: an
   umbrella with sibling clones, a docs repo, vendored subprojects), run
   `agent-cadence run hydrate_worktree.sh --detect` and write
   docs/nested-repos.txt giving each one a mode (worktree | link | skip) —
   see cadence.md Constellations. Ask me which mode per repo; the tradeoff is
   isolation vs reusing that clone's build artifacts, and it differs per repo.
   Without this file every worktree is silently missing the siblings.
7. Verify: `agent-cadence run list_sessions.py` runs; the pre-push hook blocks a
   simulated main push (echo "r s refs/heads/main s" | .git/hooks/pre-push
   origin x should exit 1); the memory guard passes
   (`agent-cadence run check_claude_memory.sh`).
8. Commit everything through a branch + PR with a pre-merge review, per
   cadence.md §4 — not directly to main.
```

## Install the launcher

Once per machine, or in a cloud environment's setup script (cadence.md §9.19):

```bash
d=$(mktemp -d) && git clone -q --depth 1 --branch <tag> https://github.com/ShiftLead/agent-cadence "$d" \
  && install -Dm755 "$d/launcher/agent_cadence.py" ~/.local/bin/agent-cadence && rm -rf "$d"   # ~/.local/bin on PATH
```

`launcher/` is tooling: it is never copied into a repo.

## Adopt a repo (manual)

```bash
git clone https://github.com/ShiftLead/agent-cadence
agent-cadence -C agent-cadence adopt /path/to/your-repo
# then the Adoption checklist in files/docs/cadence.md: memory path, .gitignore, the map, settings
```

`adopt` runs from the clone's HEAD, which must be clean and on origin's default branch, and pins the repo to it.

## Update a repo after editing canonical files

Edit files under `files/`, PR + merge **here**, then in each repo:

```bash
agent-cadence bump              # what is newer than the pin
agent-cadence bump <tag|commit> # move the pin; prints the compare and the cadence-changes.md entries
# review the compare, PR the one-line change there like any other change
```

The bump also refreshes each skill pointer the repo never edited (TD-158); nothing else in the repo changes. Review stays with you; nothing here merges.

## File classes

What `adopt` reads from `sync.sh`'s three lists. Nothing is copied into a repo any more: a pinned repo runs the SYNC files from the pinned tree (TD-129).

| Class | Behavior | Files |
|---|---|---|
| SYNC | the payload, run from the pinned tree and never present in the repo — edit here; `adopt` refuses a repo that still carries a copy, and `sync.sh --pin` removes each one still matching its lock | `docs/cadence.md`, `docs/cadence-rationale.md`, `docs/cadence-incidents.md`, `docs/cadence-changes.md`, `docs/adr-template.md`, `docs/procedures/stranded-work.md`, `docs/procedures/attention.md`, `docs/procedures/cadence.md`, `docs/procedures/memory-harvest.md` (the procedures any agent follows, TD-093; the memory harvest, TD-125), stranded-work + attention + cadence + memory-harvest skills (each a pointer to its procedure, once under .claude/skills for Claude Code and again under .agents/skills for Codex and Gemini CLI, TD-127), `check_claude_memory.sh`, `check_anchor.py`, `agent_sessions.py`, `forge.py`, `nudge_user_attention.py`, `board_edit.py`, `ledger.py`, `ledger_next_id.py` (hands out ledger ids from the counter branch on origin, TD-124), `ledgerboard.py` (vendored from ShiftLead/ledgerboard: the ledger and board formats, defined once), `list_sessions.py`, `generate_session_index.sh`, `generate_workspace.sh`, `open_worktree.sh`, `hydrate_worktree.sh`, `reap_worktrees.sh`, `adopt_repo_settings.sh`, `check_cadence.py`, `precheck.py` (a repo's own checks on a PR's head, recorded as a commit status, TD-117), `check_base.py`, `check_tmp.py` (warns at session start before the shared temp filesystem runs out of inodes or space, TD-154), `cadence_changes.py`, `cadence_config.py`, `cadence_layer.py` (prints the person's own cadence layers at session start, TD-126, and follows someone else's at a checked pin, TD-130), `memory_harvest.py` (the memory harvest's read-only inventory of every roster repo's memories, and the record of what was judged, TD-125), `cadence_hooks.sh`, `install_git_hooks.sh`, `git-hooks/pre-push`, `git-hooks/post-merge`, `git-hooks/prepare-commit-msg` |
| SEED | created by `adopt` if missing, never overwritten — the repo owns the content | `technical_debt.md` + archive (neither beside a v2 ledger directory, TD-160), `user_attention.md`, `claude-memory/MEMORY.md`, `.claude/settings.json`, `cadence.toml` (the repo's settings, TD-096), `AGENTS.md` (the map any agent tool reads, with the cadence's wake-up first, TD-092), `.gemini/settings.json` (makes Gemini CLI read `AGENTS.md`, TD-111) |
| RETIRED | once SYNC, dropped from the payload before the pin (TD-057) | (none yet) |

Every SYNC file still carries a two-line **provenance header** naming its canonical path here, from when the files were copied (`tests/test_sync_provenance.sh` holds it, and its placement rules: shebangs stay on line 1, `SKILL.md` frontmatter at line 1, the header a comment above a module docstring). Its "re-run sync.sh" wording goes with TD-169.

Repo-specific behavior stays out of SYNC files — anything marked *(adapt per repo)* in cadence.md gets its concrete form in the repo's own AGENTS.md/CLAUDE.md or `docs/cadence.toml`, never by editing the payload.

## Staying current, across machines

- **Upgrades are a bump PR:** `agent-cadence bump` with no argument lists the source's newer tags and commits since the pin; the move is one reviewed line, and the PR body carries the compare and the convention changes since the old pin (cadence.md §3.7).
- **Per-machine setup self-heals:** the git hook shims (`install_git_hooks.sh`, in the clone's shared `.git/hooks`, TD-055) and `autoMemoryDirectory` are per-clone; `adopt` installs the shims on the clone it runs against, and the SessionStart guard warns on any machine where either is missing — a fresh machine self-reports instead of silently regressing.
- **Due items find you where you work:** a SessionStart hook (`nudge_user_attention.py --report --due-only`) prints the machine's due/overdue attention items into session context and stays silent otherwise — offline, no external service, firing exactly where action can be taken. (The former `Nudge:` claim-header machinery — push cron + guard verification — retired 2026-08-12, TD-7; an external channel remains available but optional and unverified.)

## Pinned, not synced (TD-129)

A repo names the agent-cadence it runs — `[agent-cadence] source` and `ref` (a full commit) in its `docs/cadence.toml` — and the per-machine launcher, `launcher/agent_cadence.py`, runs the scripts from a cached read-only tree of that commit (`${XDG_CACHE_HOME:-~/.cache}/agent-cadence/trees/<commit>`), with its pinned words in `launcher/words.py` (`run`, `path`, `hook`, `gc`, `bump`, `adopt`, `words`; ADR 2026-10-25, option C; the rule is [cadence.md §9.19](files/docs/cadence.md)). The seeded SessionStart line and the git hook shims run `agent-cadence hook …` where the main checkout pins. Every repo on the roster was moved by 2026-10-27, and on 2026-10-28 the copy was retired: `sync.sh` keeps only the three lists above and **`./sync.sh --pin <repo>`**, the migration for a repo that still carries synced copies (run by hand, one repo at a time: it writes the pin, removes the copies that still match the lock and the lock itself, and commits nothing). Its copy mode, `--verify`, the lock and `sync-all.sh` are gone.

## Philosophy / non-goals

**A pinned tree over packaging, deliberately.** A repo names the commit it runs, so every upgrade lands as a reviewable one-line diff in that repo's own history, with the compare beside it; the scripts are plain, stdlib-only files a session can read and run (`agent-cadence path` names the tree), and a fix goes upstream rather than into the repo. No package registry, no version range — with one exception: `files/scripts/ledgerboard.py`, the ledger and board formats, is vendored from a tagged ShiftLead/ledgerboard release (`vendor_ledgerboard.sh`; its first line names the release and its hash) — no framework. The repo carries only what it owns (its board, ledger, memory, settings and map), so a repo shared with people who do not use the cadence is not asked to carry its files (TD-129's *Why*). Non-goals: auto-merge of bump PRs (review stays with a human or a session they direct), a GitHub-Actions distribution path (repos may live on machines an Action can't reach), and any central service — the git remotes, the boards, and the ledgers are the only shared state.

## This repo dogfoods itself

agent-cadence runs its own cadence: its live board is `docs/user_attention.md` and its live ledger `docs/ledger/`, one file per entry (distinct from the `files/docs/` *templates* that `adopt` seeds into a repo), and its plans live in `docs/plans/` (those written before the cut-over are kept in the private dev-cadence repo).

## License

MIT — see [LICENSE](LICENSE).

