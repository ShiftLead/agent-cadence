# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

dev-cadence is the **canonical source** of a working-cadence system (docs + stdlib-only bash/python scripts + Claude Code skills/hooks) that each consumer repo runs from a **pin**: `[dev-cadence]` in its `docs/cadence.toml` names a commit, and the `dev-cadence` launcher (`launcher/`) runs that tree from a per-machine cache (cadence.md §9.19, TD-129). Nothing is copied into a consumer any more. There is no package and no registry — deliberately (see README "Philosophy / non-goals"; one exception: `files/scripts/ledgerboard.py`, vendored from a ShiftLead/ledgerboard release by `vendor_ledgerboard.sh`).

**Read [`files/docs/cadence.md`](files/docs/cadence.md) first.** It is the system, and its rules (§1 worktrees, §2 the TD ledger, §3 never strand work, §4 review/merge loop, §7 memory and docs) govern how work is done *in this repo* as well — this repo dogfoods itself.

## Commands

```bash
./run_tests.sh                  # full suite as one pass/fail (the precheck runs it with CI=true; a SKIP fails under CI or --strict)
for t in tests/*.sh; do bash "$t"; done   # the same by hand (each file prints its own "N passed, M failed";
                                #  `bash tests/*.sh` runs ONLY the first file — the rest become its $@)
bash tests/test_p2_report.sh    # one suite
ruff check files/scripts/       # lint (rules pinned in ruff.toml; tests/test_lint.sh gates it,
                                # and SKIPs loudly-but-green when ruff is absent)

dev-cadence -C . adopt /path/to/repo   # pin a new repo to this clone's HEAD (seeds, pin, shims, roster; commits nothing)
./sync.sh --pin /path/to/repo          # the migration of a repo still carrying synced copies (TD-129) — by hand, one repo at a time
                                       # sync.sh no longer copies: its copy mode, --verify and sync-all.sh are retired (2026-10-28)

files/scripts/list_sessions.py            # index of local Claude sessions
files/scripts/check_anchor.py             # who holds the anchor checkout
files/scripts/nudge_user_attention.py --report   # machine-wide attention view (the /attention skill)
files/scripts/reap_worktrees.sh [--reap]  # report/remove worktrees whose work has landed
files/scripts/check_cadence.py --pr N     # the cadence check (the /cadence skill): one row per §1–§5 rule, a detector not a gate
files/scripts/cadence_changes.py --list   # convention changes (--hook prints unseen ones once per worktree at SessionStart)
files/scripts/cadence_hooks.sh --list     # the SessionStart hook set; a new hook is added here, never as a settings.json line
```

**Any ad-hoc run of `dev-cadence adopt` or `sync.sh --pin` against a fixture or a scratch path must set `DEV_CADENCE_REG_DIR=$(mktemp -d)` first.** Registering the target in this machine's roster (`~/.config/dev-cadence/repos.txt`) is their last mutating step (one writer, `launcher/words.py` `_register`), the file is append-only with no auto-clean, and removing a bad line is manual. The committed test suites already isolate; ad-hoc and review-time runs are the gap — a reviewer polluted the real roster with `/tmp` fixture paths on 2026-08-10. `DEV_CADENCE_REG_DIR` moves only the roster (every reader and writer honours it, cadence.md §9), so `gh` keeps its credentials; the older `XDG_CONFIG_HOME=$(mktemp -d)` recipe hid them (TD-029, resolved 2026-09-25). `sync-all.sh`, which read its targets from the roster (TD-048), is retired with the copy (TD-129, 2026-10-28), and `consumers.txt` is read by nothing (delete it).

Tests are plain bash: each is self-contained, overrides `HOME`/`XDG_CONFIG_HOME` (and PATH-shims `gh`) so the real registry, real `~/.claude`, and the network are never touched. Keep new tests fully offline and fixture-driven, and **derive date fixtures from the run date** — hardcoded calendar dates rot the suite (TD-24).

## Layout that matters

- `files/**` — the canonical payload that consumers run from their pin. **All edits to the system happen here.**
- `docs/**` — this repo's *own* live board/ledger/plans (dogfooding). Do not confuse `docs/ledger/` (live) with `files/docs/technical_debt.md` (the empty template that seeds consumers). Same trap for `user_attention.md`.
- `tests/**`, `ruff.toml`, `sync.sh`, `launcher/` — tooling; nothing here is copied anywhere (`launcher/dev_cadence.py` is installed once per machine by hand). `tests/fixtures/legacy_sync.sh` is the retired copy mode, kept only to make `sync.sh --pin`'s input in a test.
- This clone's hooks are TD-055 shims in `.git/hooks` (`files/scripts/install_git_hooks.sh`, installed 2026-09-27; `core.hooksPath` is unset), so every worktree runs the main checkout's `files/scripts/git-hooks/` — the shipped pre-push main guard runs against its own canonical copy whatever branch a worktree is on.

## The distribution contract

A consumer runs the commit its pin names; an upgrade is a `dev-cadence bump` PR in that repo (cadence.md §9.19). `sync.sh` keeps the payload's three file lists, `SYNC_FILES` / `SEED_FILES` / `RETIRED_FILES`, which `dev-cadence adopt` reads (`launcher/words.py` `_sh_array`):

- **SYNC** — the payload, run from the pinned tree and never present in a consumer. Edit here. `adopt` refuses a repo that still carries a copy; `sync.sh --pin` removes each one still matching its lock hash and keeps an edited one with a WARN.
- **SEED** — created by `adopt` only if missing (ledger, board, `MEMORY.md`, `.claude/settings.json`, …). The consumer owns the content.
- **RETIRED** — once SYNC, dropped from the payload before the pin (TD-057).

**Adding or removing a file from the payload means editing both the array in `sync.sh` and the file-class table in README.md** (`tests/test_readme_sync_table.sh`). Until TD-129's closing slice (2026-10-28) `sync.sh` copied the SYNC files into each consumer and wrote `docs/cadence-sync.lock` (a sha256 per file) for `--verify`; a consumer migrated by `--pin` has no lock and no copies.

Repo-specific behavior stays out of SYNC files. Anything marked *(adapt per repo)* in `cadence.md` gets its concrete form in the consumer's own CLAUDE.md/AGENTS.md or `docs/cadence.toml` — never by editing the payload.

Machine-scope state lives in exactly one machine-local file, `${XDG_CONFIG_HOME:-~/.config}/dev-cadence/repos.txt` (roster of cadence repos on this machine; `remote_repos.txt` optionally filters `/attention remote`). Scripts append idempotently under flock; only humans delete lines.

## Conventions this repo enforces on itself

- **Branch → PR → squash merge; never commit to main.** The pre-push hook blocks it; `ALLOW_MAIN_PUSH=1` is the deliberate override. The sanctioned routine uses are a commit touching *only* the board's `Swept:`/`Swept-deep:` stamp lines (TD-16) and a tool-made Snooze/Done edit to one board item (cadence.md §4, proposed 2026-09-06) — anything else in the commit voids it. Every self-authored PR gets an independent cheaper-model review before merge (doc-only PRs get a fact-check against the repo).
- **From a worktree, never `gh pr merge --delete-branch`** — it merges, then fails on local cleanup, so a merged PR reads as failed. Use `gh pr merge <n> --squash` → `gh pr view <n> --json state` → `git push origin --delete <branch>` (cadence.md §1).
- **Every deferred problem gets a `TD-NNN` entry** in `docs/ledger/`, one file per entry (Priority/Added/Status/Location/Why/Fix; the Why is the point). Verify a TD's status against the code before working it — status lines lag. A fully resolved entry moves to `docs/ledger/archive/`, which is the richest record of *why* things are shaped the way they are; a partly resolved one stays live with the remainder spelled out in its Status (cadence.md §2).
- **Parity rules get written down once (§7).** Several behaviors are enforced in two places and must change together — most notably the sweep stamp format/thresholds, split between the `stranded-work` skill (writer) and `nudge_user_attention.py`'s `SWEEP_RE`/`SWEEP_DEEP_RE`/`SWEEP_*_STALE_DAYS`/`sweep_mode()` (reader).
- **Gates judge the index; detectors judge the disk.** A check that blocks something reads `git ls-files`; a check hunting for stranded work walks the filesystem (untracked files are its highest-value target). Mixing them is the trap.
- **A PR that changes a convention adds an entry to `files/docs/cadence-changes.md`** (append-only, ≤3 lines, newest first: what to do, where the rule lives). That file is how sessions in old worktrees and sessions already running learn the change (cadence.md §3); a convention changed without an entry reaches nobody until they reread cadence.md.
- **Decisions live in `docs/plans/` and in the ledger/archive, not in `docs/decisions/`** — this repo has no ADR directory; a plan doc under `docs/plans/` is the ADR and a plan doc that records a decision follows `files/docs/adr-template.md`'s fields (cadence.md §7), and a decision made while working a TD is recorded in that entry (cadence.md §7 routing line).
- **Known dogfooding gaps (2026-09-22 design review, updated 2026-09-25):** the SessionStart hooks run here from `files/scripts/` through this repo's own `.claude/settings.json` — the seed's line with `files/` added, a parity pair `tests/test_cadence_hooks.sh` pins — and memory is git-tracked in `docs/claude-memory/` (TD-038, resolved). The merge gate is the local precheck, not GitHub Actions (TD-148: the account's Actions minutes are one shared pool): `python3 files/scripts/precheck.py --pr <n>` runs `docs/cadence.toml`'s `precheck` (`ruff` and `CI=true ./run_tests.sh`) on the PR's head in a clean worktree and records the `cadence/precheck` status, which the `ci` row of `/cadence` reads; `.github/workflows/ci.yml` runs only by hand (`workflow_dispatch`). Still run the suite before opening a PR.
- **An unattended team works the ledger here** (`ao team start dc-grind` on the person's machine, ShiftLead): its briefs and the techlead's primer live in `docs/briefs/` (README there), the team definition in this repo's `.shiftlead.yml`. `tests/test_briefs_primer.sh` holds the primer's pointers to things that exist; a PR that changes a convention, the merge rules or the layout updates the primer too.
- Scripts are stdlib-only Python 3 and bash by design — a consumer session must be able to read, run, and patch them on the spot. Keep them dependency-free.
