# ADR 2026-10-29: the tool is renamed agent-cadence, everywhere, in one sitting with no aliases

**Status:** proposed
**Date:** 2026-10-29
**Related:** TD-191 (the cut-over runbook), TD-090; dev-cadence's private plan 2026-10-26-public-scrub
(its *Amendment 2026-10-28*); ShiftLead TD-1208, TD-1014

## Context

The cut-over moves the system from the private repo `ShiftLead/dev-cadence` to `ShiftLead/agent-cadence`
(TD-191). On 2026-10-27, the private public-scrub plan decided that *the tool, its commands and its docs stay
`dev-cadence`, and the public README says dev-cadence, published as agent-cadence*. Steps 1 to 6 of TD-191
are done (2026-10-29). The seed is agent-cadence's root commit `35b4b4a`. `~/agent-cadence` is on the roster
above `~/dev-cadence`. Every consumer pins C (`0ad7b2f`, `ShiftLead/dev-cadence`). The repo is still private.

On 2026-10-29 Paul reversed that line: a cut-over from dev-cadence should be a full one, so an outside reader
never meets a second name. The only consumers are Paul's own repos, and every team can be paused (all are set
to do nothing on new work), so no one needs a period where both names work.

The name sits in five places, counted at `35b4b4a` and at shiftlead `9f05ba0`:

- **agent-cadence:** 568 lines in 113 files.
  - Identifiers: the `dev-cadence` command, and `launcher/dev_cadence.py` installed as `~/.local/bin/dev-cadence`.
  - The pin table `[dev-cadence]`: 73 lines in 22 files, including `cadence_config.py`'s `PIN_TABLE`, the
    launcher's `.get("dev-cadence")` reads, and `bump`'s header match.
  - `~/.config/dev-cadence/` (the roster `repos.txt` and the machine `cadence.toml`) and
    `~/.cache/dev-cadence/` (sources, trees, lock).
  - `DEV_CADENCE_REG_DIR`: 215 lines in 53 files, mostly tests.
  - The `SYNCED FILE` headers: 47 files.
  - The rest is prose.
- **Each consumer's tracked files:**
  - `docs/cadence.toml`'s table.
  - The `.claude/settings.json` SessionStart line, which greps `[dev-cadence]` and runs `dev-cadence hook
    session-start`. The same line is in the Gemini and agents settings where seeded.
  - Prose in AGENTS.md, CLAUDE.md, briefs and memory.
  - Devcontainers: consumer-d's devcontainer creates `~/.config/dev-cadence` and mounts a named volume there (its
    `Dockerfile` and `devcontainer.json`), and its `postCreate.sh` installs the launcher.
  - consumer-a's tracked crontab runs `~/.local/bin/dev-cadence` every 10 minutes.
- **Each clone's untracked git hook shims** (`.git/hooks/*`, TD-055): they grep `[dev-cadence]` and run
  `dev-cadence hook`. They are written by `install_git_hooks.sh` and never edited.
- **ShiftLead:**
  - About 42 sites in `src/`: `PIN_HEADER = "[dev-cadence]"`, `cadence.is_source`, the roster and cache paths,
    and `containers.py`'s `PATH_DEV_CADENCE = "/usr/local/bin/dev-cadence"`.
  - A vendored frozen copy of the launcher, `src/sessionorc/dev_cadence.py`, whose hash a test holds (TD-1014).
  - A console script, `dev-cadence = "sessionorc.dev_cadence_entry:main"`.
  - About 1,500 prose lines in `docs/` and `tests/`.
- **This machine:**
  - `~/.local/bin/dev-cadence`, `~/.config/dev-cadence/{repos.txt,cadence.toml}`, `~/.cache/dev-cadence/`.
  - consumer-a's deploy checkout and consumer-b's devcontainer node.
  - Paul's layer `~/cadence-layer/cadence-personal.md`, which only names the tool in its comments.

**What keeps the name.** `dev-cadence` stays wherever it names the private predecessor repo, because that
repo exists and is kept:

- *dev-cadence's private plan <slug>*.
- `dev-cadence#TD-NNN` refs to ids archived there, which resolve against the `~/dev-cadence` roster clone.
- The archive README's *Private through* line.
- History in TD-191, TD-090 and the changes log.
- `cadence_layer.py`'s `TOOL_NAMES`, so that the publish gate still reads those mentions as the tool's own
  name and not a private one.

## Options

1. **Keep the 2026-10-27 line.** The repo is called agent-cadence, and the tool and its docs stay dev-cadence.
   This costs nothing now, but every outside reader meets two names. That is the reason Paul reversed it.
2. **A rename with a transition.** The launcher installs under both names and reads both tables, the config
   and cache dirs fall back to the old ones, `DEV_CADENCE_*` is read beside `AGENT_CADENCE_*`, and ShiftLead
   reads both headers. A later entry drops the old names. This is safe against out-of-order merges and
   against a machine that was missed. The cost is aliases in the launcher, in ShiftLead and in
   the tests, a second cleanup round, and a public first release that ships names it is about to remove.
3. **A hard cut in one sitting.** The code drops every old name with no alias. The machine keeps the old
   launcher, config and cache in place through the sitting, as a safety net that needs no code, and they
   are deleted at the end. All teams are paused for the sitting. This is cheaper than option 2, and the
   public history starts with one name. The cost: a pin's move, its table rename and the
   settings line have to land together in each repo, and anything missed on this machine breaks
   once the old files are deleted rather than limping on.

## Decision

**Option 3**, decided by Paul on 2026-10-29: *Easier to just make a hard cut instead of the backward
compatibility steps.* It supersedes the public-scrub plan's line *the tool, its commands and its docs
stay `dev-cadence`*.

### The new names

| Was | Becomes |
|---|---|
| `dev-cadence` (command), `launcher/dev_cadence.py`, `~/.local/bin/dev-cadence` | `agent-cadence`, `launcher/agent_cadence.py`, `~/.local/bin/agent-cadence` |
| `[dev-cadence]` in `docs/cadence.toml` (`PIN_TABLE`) | `[agent-cadence]` |
| `${XDG_CONFIG_HOME:-~/.config}/dev-cadence/` | `${XDG_CONFIG_HOME:-~/.config}/agent-cadence/` |
| `${XDG_CACHE_HOME:-~/.cache}/dev-cadence/` | `${XDG_CACHE_HOME:-~/.cache}/agent-cadence/` |
| `DEV_CADENCE_REG_DIR` | `AGENT_CADENCE_REG_DIR` |
| `SYNCED FILE` header: *a repo runs it from its pinned dev-cadence (`dev-cadence path`)* | *… its pinned agent-cadence (`agent-cadence path`)* |
| Shim marker *dev-cadence hook shim (TD-055)* | *agent-cadence hook shim (TD-055)* |
| ShiftLead `PIN_HEADER`, `sessionorc/dev_cadence.py`, the `dev-cadence` console script, `PATH_DEV_CADENCE` | `[agent-cadence]`, `sessionorc/agent_cadence.py` (re-vendored, new hash), `agent-cadence`, `PATH_AGENT_CADENCE = "/usr/local/bin/agent-cadence"` |

Branch names (`cadence/ledger-ids`, `cadence/precheck`), the `cadence-*` files and `cadence.md` are already
name-free and stay as they are.

### The PRs (built before the sitting, merged in it)

1. **agent-cadence, the rename (R).**
   - Every identifier in the table, plus every prose mention of the tool across `files/`, `launcher/`,
     `tests/`, `docs/` and the README. The README's *dev-cadence, published as agent-cadence* note becomes one
     sentence: the history before the cut-over is kept privately.
   - The seeded `settings.json` lines and this repo's own line (`tests/test_cadence_hooks.sh`'s parity pair).
   - The install line in the README, the hooks' messages and `adopt`'s.
   - `snapshot_public.sh`, its test, `docs/seed/` and `tests/fixtures/legacy_sync.sh` are deleted: the seed
     is built, and `sync.sh --pin`'s copy-mode input has no consumer left.
   - A new `tests/test_one_name.sh` fails on any `dev-cadence` or `dev_cadence` outside an allowlist of the
     private-repo forms listed under *What keeps the name*. It holds the line from then on.
   - ac-proofread's proofreading of the docs lands in this PR or straight after it. This PR comes first so
     the two do not collide.
2. **ShiftLead, the rename and its own pin (S).**
   - Every `src/` site above.
   - The vendored launcher re-vendored from R, with the test's hash updated.
   - The console script and the container link renamed.
   - The prose in `docs/` and `tests/`.
   - In the same PR, shiftlead's own pin moves (`source` to agent-cadence, `ref` to R, table renamed,
     settings line updated). The code and the pin then switch together.
   - `cadence.SEED` stays `35b4b4a`, because R descends from it.
3. **One PR per other consumer (C1–C5):** consumer-a to consumer-d, and ShiftLead/ledgerboard.
   - `docs/cadence.toml`: `source = "https://github.com/ShiftLead/agent-cadence"`, `ref` = R, and the table
     header `[agent-cadence]`, edited by hand (`bump` does not cross sources).
   - The `settings.json` SessionStart line (Claude, and the Gemini and agents files where present).
   - Prose that names the tool, in AGENTS.md, CLAUDE.md, the briefs and memory. Refs to the private repo's
     archived ids stay.
   - consumer-a: the crontab line, run as `~/.local/bin/agent-cadence -C <its deploy checkout> run …`.
   - consumer-d: the Dockerfile dir, the volume target `~/.config/agent-cadence`, and `postCreate.sh`'s
     install. The volume's *name* can stay as it is, since it is an identifier inside Docker that no reader
     sees. Renaming it would also orphan the roster the volume holds.

   These replace TD-191 step 8's seven pin PRs. consumer-a's deploy checkout follows its merge when it pulls.
   TD-191's cross-repo re-pointing PRs (`dev-cadence#TD-144` and others to `agent-cadence#`) can fold into
   the same PRs.

Each PR goes through its repo's usual review and precheck before the sitting. They are run against a scratch
install of R's launcher with `AGENT_CADENCE_REG_DIR=$(mktemp -d)`, so the real roster is untouched.

### The sitting

Every team is stopped, ao-grind included. `on_work` is already set to do nothing. The runbook is run from a
session in `~/agent-cadence`, not `~/dev-cadence`: once the old config is deleted, a `~/dev-cadence` session
sees no roster.

1. Merge R. Fetch `~/agent-cadence`. Run `install -m 755 launcher/agent_cadence.py ~/.local/bin/agent-cadence`
   beside the old launcher.
2. Run `cp -a ~/.config/dev-cadence ~/.config/agent-cadence`. The roster keeps `~/agent-cadence` first, and
   keeps `~/dev-cadence` for the archived `dev-cadence#` refs and old-pin ancestry. The machine
   `cadence.toml` comes with it.
3. Merge C1–C5, one at a time. After each merge, fetch the repo's main checkout and rerun its shims with
   `agent-cadence -C <repo> run install_git_hooks.sh` (one per clone, including consumer-a's deploy checkout
   after it pulls). Then start one session in it and check its SessionStart output.
4. Merge S. Check that the host agent rebuilt from it (`ao doctor`: `live <sha> = main`). Rebuild
   consumer-b's devcontainer node and consumer-d's devcontainer.
5. Reinstall consumer-a's crontab from the merged file, and check that its next 10-minute run logs.
6. `ao doctor`: every repo row, no pin-age warning, and dc-grind listed at `agent-cadence`. Then
   `git grep -n 'dev-cadence'` in every consumer, where only the private-repo forms remain.
7. Delete `~/.local/bin/dev-cadence`, `~/.config/dev-cadence/` and `~/.cache/dev-cadence/`. Start one session
   in each repo again to show that nothing reached the old names.
8. Restart the teams from Paul's own shell (not a session pane, so their mail carries over), and dc-grind
   for the first time.

**Rollback during the sitting:** a consumer not yet merged keeps working on the old launcher and config. A
merged one is reverted by a revert PR. S is reverted the same way, and the host agent rebuilds from main.
Nothing is deleted before step 7.

### Where it sits in TD-191

- After TD-191's step 6.3 (done) and before step 7.
- The flip waits for the sitting, so the public history's first release carries one name. Step 7's privacy
  read covers the commits on top of the seed (R, and anything else merged by then).
- `v0.1.0` is tagged on main after the sitting.
- Step 8's pin PRs are C1–C5 and S. Its ShiftLead item is S.
- Step 9 (archive the private ledger entries, archive dev-cadence on GitHub) is unchanged. `~/dev-cadence`
  stays on the roster until no `Blocked by` names `dev-cadence#`.

## Consequences

- An outside reader meets one name. The public history has no compatibility code, and none has to be
  removed later.
- The cost is one sitting with every team paused, and a set of PRs that must merge together. A PR built early
  goes stale against main, so they are rebased just before the sitting.
- Anything on this machine that the sitting misses fails once step 7 deletes the old names. That includes
  untracked shims in a clone nobody fetched, a container not rebuilt, and a script outside a repo. Step 7's
  session-start pass and step 6's greps are there to find these first. A machine other than this one, if one
  appears later, installs the new launcher fresh.
- A `~/dev-cadence` session after the sitting has no roster and no launcher. The private repo is frozen
  (TD-191 step 1), so nothing needs one.
- Paul's personal layer and its machine `cadence.toml` move with the config dir. The comment text in
  `~/cadence-layer/cadence-personal.md` is Paul's to update.
- Out of bounds from now on: a new `dev-cadence` mention outside the private-repo forms (`test_one_name.sh`).

## Revisit triggers

- A second machine or an outside consumer appears before the sitting runs. Then option 2's transition is
  owed to it.
- The sitting cannot finish in one go: some consumer PR cannot merge, or a container cannot be rebuilt.
  Then the old names stay installed and an entry decides whether the old launcher stays as a deliberate
  alias.
