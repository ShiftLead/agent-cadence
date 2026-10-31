# Briefs for the unattended agent-cadence team

A **brief** is the opening prompt of an unattended session. `ao team start ac-grind` (ShiftLead,
on the person's machine) reads the team definition (below), launches every seat in its own worktree under
`.claude/worktrees/<name>`, and hands each one ShiftLead's built-in template for its role with the
file named there filled into the template's *This repo's rules* section (ShiftLead design §4.8,
its TD-114). **The files here are supplements, not whole briefs**: every ShiftLead mechanic —
claims, the review loop, asking, the end-of-run declarations, the usage gate — is the template's
and moves with each ShiftLead promote. A file here holds only what agent-cadence does differently,
and where it and the template disagree, it wins; so a rule copied from the template goes stale
and then overrides the newer one. `ao team start` names any heading a supplement repeats from
the template. `ao team --skill` is the
recipe if a seat ever has to be launched by hand.

**Why this directory exists.** The 2026-09-22 design review filed TD-038…TD-058 and the team is
how they get worked without a person at the keyboard. The package's templates assume
`pdm run test`, a `scripts/` layout this repo does not have, and that a SYNCED FILE header means
hands off, and nothing in them stops a run of `agent-cadence adopt` against real repos — so the
supplements carry this repo's rules. Every rule below
that looks arbitrary is a scar recorded in `CLAUDE.md`, the ledger or its archive.

| File | Seat | Notes |
|---|---|---|
| `manager-ac-1.md` | manager | Holds the `control` grant; watches the grinder, reads the cadence check's readings, winds the team down, creates no work of its own |
| `techlead-context.md` | techlead | **Not a brief** — the primer the techlead reads on every fill, after the role preset's own brief. `tests/test_briefs_primer.sh` holds its pointers to things that exist |
| `grinder-ac-1.md` | grinder | `free-pick` from the live ledger via `ledger.py --pickable` (blocked entries left out) |

The team definition lives in this repo's `.shiftlead.yml` (moved from the machine's `org.yml`,
now `~/.shiftlead/org.yml`, on 2026-10-03, PR #206 in the private dev-cadence repo; named `.agentorc.yml` until TD-091); while `org.yml` still names `ac-grind` it wins the name and this file reads
*shadowed* — removing it there is the switch, and Paul's.

## The rules every seat shares

Written into each supplement that needs them rather than linked, because a brief is read cold
and a link can be skipped:

- **Never work in the main checkout** — it is Paul's anchor (cadence.md §1). Each seat has its
  own worktree.
- **Never commit to main.** The pre-push hook blocks it; `ALLOW_MAIN_PUSH=1` is for the two
  carve-outs in cadence.md §4 and for nobody on this team.
- **Every PR gets an independent review by a cheaper model (Sonnet)**, doc-only PRs included,
  with the `cadence-review:` comment (cadence.md §4). The cadence check here is
  `python3 files/scripts/check_cadence.py --pr <n>` — `files/scripts/`, not `scripts/`.
- **The gate is the bash suite and ruff:** `./run_tests.sh` and `ruff check files/scripts/`, run by
  hand before a PR and on its head by `files/scripts/precheck.py --pr <n>`, which records the
  `cadence/precheck` status the `ci` row requires (`docs/cadence.toml`, TD-148). GitHub Actions
  runs only on a fork's PR (TD-192), and a session never prechecks one: that is Paul's. The SessionStart
  hooks (TD-038) are detectors, not the suite.
- **Never run `sync.sh` (its `--pin`) or `agent-cadence adopt` outside a test fixture.** An ad-hoc run appends
  to the machine roster `~/.config/agent-cadence/repos.txt`; moving a consumer is Paul's. Tests
  already isolate under their own `AGENT_CADENCE_REG_DIR`.
- **Never change this clone's git config** (the hook shims in the clone's shared hooks dir are the push guard, TD-055), the machine
  roster, another repo's checkout, GitHub repo settings (`gh api -X PATCH`, `adopt_repo_settings.sh
  --apply`), or anything under `~/.shiftlead`, `~/.claude` or systemd.
- **Edits to the system go under `files/**`**; `docs/**` is this repo's own board, ledger and
  plans. `docs/ledger/` is the live ledger (one file per entry, TD-160); `files/docs/technical_debt.md` is the empty
  template that seeds consumers. Same trap for `user_attention.md`.
- **A PR that changes a convention adds an entry to `files/docs/cadence-changes.md`**; a PR that
  adds or removes a payload file edits both the array in `sync.sh` and the table in `README.md`.
- **Coordinate through ShiftLead, never Claude Code's peer channel.** `ao progress claim` / `done`,
  and `ao msg <id>` for mail.
- **A run ends with a declaration, not a summary** (`ao progress none --why` / `restart --why`).
  The manager reads records, never screens.

## Keeping them honest

`tests/test_briefs_primer.sh` holds the primer's paths and ledger ids to ones that exist, and
checks that every brief this README lists is present. It cannot hold any brief's prose to the
truth — that is a person reading it. Treat every brief as stale-by-default and check a rule
against the repo before leaning on it, which is the same instruction the primer gives the
techlead about itself.
