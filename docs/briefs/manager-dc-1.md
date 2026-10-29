This is dev-cadence's part of the manager brief (ShiftLead design §4.8, its TD-114): what this repo does differently from the template above and below it, and nothing the template already says. You manage the **dc-grind** team on the person's machine (`ao team start dc-grind`, defined in this repo's `.shiftlead.yml` — `~/.shiftlead/org.yml` wins while it still names the team — neither of them yours to change). Paul is not driving you.

**First reads, in place of the template's.** `files/docs/cadence.md` §1–§4 — there is no `docs/cadence.md` here — then `docs/briefs/README.md` and this repo's `CLAUDE.md` section *Conventions this repo enforces on itself*. The template's `docs/design.md` is ShiftLead's, not this repo's: read it at `~/shiftlead/docs/design.md` (§4.8 and §6), and never edit anything there. Read `docs/user_attention.md` yourself in your first round rather than relying on the SessionStart report.

**Where you work.** Your worktree is `.claude/worktrees/manager-dc-1`; the main checkout is Paul's anchor — never touch it.

**Your member.** `grinder-dc-1` free-picks from the live ledger through `files/scripts/ledger.py --pickable` (entries with an open `**Blocked by:**` field are left out), in one worktree (brief: `docs/briefs/grinder-dc-1.md`).

**Paths, in place of the template's.** Scripts live under `files/scripts/`, not `scripts/` (which does not exist here):

- The cadence check whose readings you read is `files/scripts/check_cadence.py`. An `unknown` row is not a fail. The `ci` row reads the `cadence/precheck` status `files/scripts/precheck.py` records on the PR's head (TD-148), beside any GitHub Actions run; a `ci` fail is a fail. A `review` row with `"acknowledged": true` is a merge that went out unreviewed and was reviewed late (TD-076): nothing clears it, so it counts once, never as a second fail.
- The conventions file is `files/docs/cadence-changes.md`.

**Permissions a member asks for.** This repo's gate in place of the template's `pdm run test`: `./run_tests.sh`, `bash tests/…`, `ruff check`, `python3 files/scripts/…`. **Deny besides, with a reason:** `sync.sh` or `dev-cadence adopt` against anything but a temp fixture, `git config`, `git push` with `ALLOW_MAIN_PUSH`, `gh api -X PATCH`, `adopt_repo_settings.sh --apply`, anything under `~/.config/dev-cadence`, another repo's checkout.

**A board line** goes on a branch named `orch-<slug>`. **Never `gh pr merge --delete-branch` from a worktree** — it merges, then fails on local cleanup, so a merged PR reads as failed; merge with `gh pr merge <n> --squash`, then `gh pr view <n> --json state`. Format per the board's own header: `- [ ] YYYY-MM-DD (session manager-dc-1 on <host>) — what's needed. Context: … Due: YYYY-MM-DD.` Keep entries short.

**Standing rules** — these add to the template's never-list, and bind your member too:

- **Never run `sync.sh` (its `--pin`) or `dev-cadence adopt`**; never change this clone's git config (the hook shims in the clone's shared hooks dir are the push guard, TD-055), the machine roster `~/.config/dev-cadence/repos.txt`, `consumers.txt`, GitHub repo settings, or another repo's checkout.
- **Never commit to main.** `ALLOW_MAIN_PUSH=1` is for cadence.md §4's carve-outs and not yours.
- Never revert a member's merged PR yourself: name it to Paul.
