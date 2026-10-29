# ADR 2026-10-29: the tool is renamed agent-cadence, everywhere, in one sitting with no aliases

**Status:** proposed
**Date:** 2026-10-29
**Related:** TD-191 (the cut-over runbook), TD-090; dev-cadence's private plan 2026-10-26-public-scrub
(its *Amendment 2026-10-28*); ShiftLead TD-1208, TD-1014

## Context

The cut-over moves the system from the private repo `ShiftLead/dev-cadence` to `ShiftLead/agent-cadence`
(TD-191). On 2026-10-27, the private public-scrub plan decided that *the tool, its commands and its docs stay
`dev-cadence`, and the public README says dev-cadence, published as agent-cadence*.

By 2026-10-29, TD-191's steps 1–3 are done:
- The seed is agent-cadence's root commit `35b4b4a`.
- `~/agent-cadence` is on the roster above `~/dev-cadence`.
- Every consumer pins C (`0ad7b2f`, `ShiftLead/dev-cadence`).
- The repo is still private.

On 2026-10-29 Paul reversed that line: a cut-over from dev-cadence should be a full one, so an outside reader
never meets a second name. The only consumers are Paul's own repos, and every team can be paused (all are set
to do nothing on new work), so no one needs a period where both names work.

The name has readers in five places. Counts are at `35b4b4a` and at shiftlead `9f05ba0`. Every one of these is
renamed unless *What keeps the name* says otherwise.

- **agent-cadence:** 568 lines in 113 files.
  - The `dev-cadence` command, `launcher/dev_cadence.py`, and its install as `~/.local/bin/dev-cadence`.
  - The pin table `[dev-cadence]`: 73 lines in 22 files, including `cadence_config.py`'s `PIN_TABLE`, the
    launcher's `.get("dev-cadence")` reads, and `bump`'s header match.
  - `~/.config/dev-cadence/`: the roster `repos.txt`, and the machine `cadence.toml` that names Paul's layer
    and the publish names. `~/.cache/dev-cadence/`: sources, trees, lock.
  - `DEV_CADENCE_REG_DIR`, the only `DEV_CADENCE_*` variable: 211 lines in 53 files, mostly tests.
  - The `SYNCED FILE` header text: 54 files.
  - The git hook shims' marker and messages (`install_git_hooks.sh`).
  - The seeded `.agents/skills/*/SKILL.md` pointers (`dev-cadence path`/`run`).
  - The rest is prose.
- **The consumers.** All tracked text: consumer-a 183 lines in 70 files, consumer-b 106/39, consumer-c 45/15,
  consumer-d 140/37, ShiftLead/ledgerboard 56/21. The code and config readers among it, each of which must
  change in the same PR as its pin:
  - Every repo: `docs/cadence.toml`'s table; the `.claude/settings.json` SessionStart line, which greps
    `[dev-cadence]` and runs `dev-cadence hook session-start` (only the Claude settings carry it); the seeded
    `.agents/skills/*/SKILL.md`; the comments in `docs/cadence-local.conf`.
  - consumer-a:
    - `.shiftlead.yml`'s `worktree_setup` (`command -v dev-cadence … run hydrate_worktree.sh`, which ShiftLead
      runs for every team worktree);
    - `scripts/tdgrind.sh` (`command -v dev-cadence`, which skips its reap step silently when the command is
      missing);
    - `tests/pinned_cadence.py` (`shutil.which("dev-cadence")`, run by its precheck);
    - the tracked crontab. It runs `~/.local/bin/dev-cadence -C <deploy checkout>` every 10 minutes, and its
      last argument indexes `~/dev-cadence` as a repo.
  - consumer-b: its devcontainer node's `setup_scripts/postCreate.sh` clones `ShiftLead/dev-cadence` into a
    `dev-cadence` sibling and writes the node's roster at `~/.config/dev-cadence/repos.txt`.
  - consumer-d:
    - `.shiftlead.yml`'s `test: dev-cadence run ledger.py --check`;
    - `scripts/check_all_memory.sh` (`dev-cadence -C … path …`);
    - the devcontainer. It creates `~/.config/dev-cadence`, mounts a named volume there (its `Dockerfile` and
      `devcontainer.json`), and its `postCreate.sh` installs the launcher.
  - ShiftLead/ledgerboard: its own release text names dev-cadence as a vendoring consumer (see the ledgerboard
    header below).
- **Each clone's untracked git hook shims** (`.git/hooks/*`, TD-055). They grep `[dev-cadence]` and run
  `dev-cadence hook`, and when the grep fails they fall through to `scripts/git-hooks/<hook>`. A shim is written
  by `install_git_hooks.sh` and never edited, so a moved repo keeps the main-push guard (it is inline) but
  silently loses post-merge and prepare-commit-msg until its shims are rewritten.
- **ShiftLead:**
  - 295 lines in 34 files in `src/`. Among them:
    - `PIN_HEADER = "[dev-cadence]"`, `cadence.is_source`;
    - the roster and cache paths, and `hosts.py`'s `DEV_CADENCE_ROSTER`;
    - `containers.py`'s `PATH_DEV_CADENCE = "/usr/local/bin/dev-cadence"` and its cache path;
    - a vendored frozen copy of the launcher, `src/sessionorc/dev_cadence.py`, whose hash
      `tests/test_cadence_pin.py` holds (TD-1014);
    - the console script `dev-cadence = "sessionorc.dev_cadence_entry:main"`.
  - Three tests pass `DEV_CADENCE_REG_DIR` to the pinned scripts: `test_ledger_derived.py`,
    `test_rank_order.py`, `test_repo_adopt.py`.
  - About 1,500 prose lines in `docs/` and `tests/`.
- **This machine:**
  - `~/.local/bin/dev-cadence`, `~/.config/dev-cadence/`, `~/.cache/dev-cadence/`.
  - The host agent's venv, which installs its own `dev-cadence` console script
    (`~/.local/share/shiftlead-venv/bin/`). The agent unit and the tmux and watch units put that venv ahead of
    `~/.local/bin` on PATH, so sessions under ShiftLead resolve the launcher there.
  - `~/.shiftlead/org.yml`'s project `dev-cadence` (repo `~/dev-cadence`).
  - consumer-a's deploy checkout. It pulls main on the hour, at :55, and has no git hook shims.
  - consumer-b's devcontainer node and consumer-d's devcontainer.
  - Paul's layer repo `~/cadence-layer`. `cadence-personal.md`, its README and `craft.md` name the tool in body
    text, and that text is Paul's to update.

Nothing else on the machine reads the name. No systemd unit or timer, and no `~/.claude`, `~/.gemini` or
`~/.codex` settings file does. ShiftLead's generated `~/.shiftlead/claude-hooks/*.json` are rewritten at every
launch.

**What keeps the name.** `dev-cadence` stays wherever it names the private predecessor repo, because that
repo exists and is kept, or where the text is frozen:

- *dev-cadence's private plan <slug>*.
- `dev-cadence#TD-NNN` refs to ids archived there. `ledger.py` resolves them by roster basename, and live
  `Blocked by` lines name them: consumer-a TD-470 names `dev-cadence#TD-187`; consumer-b TD-059 and TD-096 name
  `#TD-156` and `#TD-187`.
- The archive README's *Private through* line, and history in TD-191 and TD-090.
- `files/docs/cadence-changes.md` entries dated before the sitting. The log is append-only, and an old entry is
  never edited.
- Ledger entries in the archive. They are records.
- `files/scripts/ledgerboard.py`'s release header, *vendored by dev-cadence as …*. It is byte-frozen:
  `tests/ledgerboard/run.py --check-header` hashes it, and ShiftLead holds its copy byte-equal to the pinned
  tree's. It changes only with a ledgerboard release that renames it, vendored by `vendor_ledgerboard.sh`.
- `tests/fixtures/legacy_sync.sh`, the retired copy mode kept verbatim as `sync.sh --pin`'s input.
- `cadence_layer.py`'s `TOOL_NAMES`, so that the publish gate still reads those mentions as the tool's own
  name and not a private one.

## Options

1. **Keep the 2026-10-27 line.** The repo is called agent-cadence, and the tool and its docs stay dev-cadence.
   This costs nothing now, but every outside reader meets two names. That is the reason Paul reversed it.
2. **A rename with a transition.** The launcher installs under both names and reads both tables, the config
   and cache dirs fall back to the old ones, `DEV_CADENCE_*` is read beside `AGENT_CADENCE_*`, and ShiftLead
   reads both headers. A later entry drops the old names. This is safe against out-of-order merges and
   against a machine that was missed. The cost is aliases in the launcher, in ShiftLead and in the tests, a
   second cleanup round, and a public first release that ships names it is about to remove.
3. **A hard cut in one sitting.** The code drops every old name with no alias. The machine keeps the old
   launcher, config and cache in place through the sitting, as a safety net that needs no code, and they
   are deleted at the end. All teams are paused for the sitting. This is cheaper than option 2, and the
   public history starts with one name. The cost: a pin's move, its table rename and every reader of the old
   name in that repo have to land together, and anything missed on this machine breaks once the old files
   are deleted rather than limping on.

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
| ShiftLead `PIN_HEADER`, `sessionorc/dev_cadence.py`, the `dev-cadence` console script, `PATH_DEV_CADENCE`, `DEV_CADENCE_ROSTER` | `[agent-cadence]`, `sessionorc/agent_cadence.py` (re-vendored, new hash), `agent-cadence`, `PATH_AGENT_CADENCE = "/usr/local/bin/agent-cadence"`, `AGENT_CADENCE_ROSTER` |

Branch names (`cadence/ledger-ids`, `cadence/precheck`), the `cadence-*` files and `cadence.md` are already
name-free and stay as they are.

### The PRs (built and reviewed before the sitting, merged in it)

1. **agent-cadence, the rename (R).**
   - Every identifier in the table, plus every prose mention of the tool across `files/`, `launcher/`, `tests/`,
     `docs/` and the README. The README's *dev-cadence, published as agent-cadence* note becomes one sentence:
     the history before the cut-over is kept privately.
   - The seeded `settings.json` line and this repo's own line (`tests/test_cadence_hooks.sh`'s parity pair);
     the seeded skills; the shims' marker and messages; the install line in the README, the hooks' messages
     and `adopt`'s.
   - `snapshot_public.sh` and `tests/test_snapshot_public.sh` are deleted, because the seed is built. With them
     go `docs/publish-accept.txt`'s line for that test, and the `snapshot()` branches in
     `tests/test_cadence_hooks.sh` and `tests/test_briefs_primer.sh`, which key on the README note R rewrites.
     `sync.sh --pin` and `tests/fixtures/legacy_sync.sh` stay.
   - A new `tests/test_one_name.sh` matches `dev[-_]cadence`, case-insensitively, over `git ls-files`. It fails
     on any match not covered by `tests/one_name_allow.txt`, whose lines are `<path-glob> <line-glob>` like
     `docs/publish-accept.txt`'s. The allowlist holds exactly *What keeps the name*: the private-repo forms,
     `cadence-changes.md` entries dated before the sitting, `docs/ledger/archive/*`, the ledgerboard header,
     the legacy fixture and `TOOL_NAMES`. Untracked `.git/hooks` are beyond its reach, and the sitting's step
     8 is the check for them.
   - A `files/docs/cadence-changes.md` entry: the command, table, dirs and variable are renamed, with the old
     names in that entry. The techlead primer and `docs/briefs/` follow the rename.
   - The docs proofread, held since 2026-10-29, lands in R's review or straight after R merges.
2. **ShiftLead, the rename and its own pin (S).**
   - Every `src/` site above, the three tests' `AGENT_CADENCE_REG_DIR`, and the prose in `docs/` and `tests/`.
   - The vendored launcher re-vendored from R, with the test's hash updated.
   - The console script and the container link renamed.
   - ShiftLead's own pin moves in the same PR, so the code and the pin switch together: `source` to
     agent-cadence, `ref` to R, the table renamed, and its settings line updated.
   - `cadence.SEED` stays `35b4b4a`, because R descends from it.
3. **One PR per other consumer (C1–C5):** consumer-a to consumer-d, and ShiftLead/ledgerboard.
   - `docs/cadence.toml`: `source = "https://github.com/ShiftLead/agent-cadence"`, `ref` = R, and the table
     header `[agent-cadence]`, edited by hand (`bump` does not cross sources).
   - Every code and config reader listed under Context for that repo, and its seeded skills and settings
     line.
   - The prose that describes the tool. History, archived entries and `dev-cadence#TD-NNN` refs to archived
     ids stay.
   - consumer-a's crontab: the launcher is `~/.local/bin/agent-cadence`, and the indexed repo is
     `~/agent-cadence`, not `~/dev-cadence`.
   - consumer-b's node: the clone target, the sibling and the roster path. consumer-d's devcontainer: the
     Dockerfile dir, the volume's mount target, and `postCreate.sh`'s install. The volume's *name* stays,
     because it is an identifier inside Docker that no reader sees, and renaming it would orphan the roster it
     holds.
   - TD-191's cross-repo re-pointing of refs to carried entries (`dev-cadence#TD-144` and others to
     `agent-cadence#`) folds into these PRs and S.

   These replace TD-191 step 5's seven pin PRs. consumer-a's deploy checkout follows its merge when it pulls.

**The ref.** agent-cadence squash-merges, so R's commit on main does not exist until the sitting, and the
launcher fetches only branches and tags (`ensure_tree`). Until then, C1–C5 and S pin R's branch head, which
stays fetchable while R's branch exists. Each PR is reviewed and prechecked against that head, using a scratch
install of R's launcher with `AGENT_CADENCE_REG_DIR=$(mktemp -d)`, so the real roster is untouched. R's branch
is not deleted until the sitting ends. In the sitting, once R is merged, each PR gets a one-line commit that
sets `ref` to R's merged commit, whose tree must equal the branch head's (`git diff --quiet <head> <merged>`).
Its precheck then reruns on that commit, with TD-186's `--expect`.

### The sitting

Every team is stopped, ao-grind included. `on_work` is already set to do nothing. The runbook is run from a
session in `~/agent-cadence`, not `~/dev-cadence`: once the old config is deleted, a `~/dev-cadence` session
sees no roster.

1. Rebase R onto main if it moved, and merge it. Check that the merged tree equals the branch head. Fetch
   `~/agent-cadence`. Run `install -m 755 launcher/agent_cadence.py ~/.local/bin/agent-cadence` beside the old
   launcher. Rewrite `~/agent-cadence`'s own shims with `install_git_hooks.sh`.
2. Run `cp -a ~/.config/dev-cadence ~/.config/agent-cadence` and delete the copy's `repos.txt.bak-*`. The
   roster keeps `~/agent-cadence` first, and keeps `~/dev-cadence` for the archived `dev-cadence#` refs and
   `seams.descends`. The machine `cadence.toml` comes with it.
3. Push each PR's `ref` commit (R's merged SHA) and run its precheck. The prechecks can run in parallel.
4. Merge C1 (consumer-a). At once, pull its deploy checkout by hand and reinstall its crontab from the merged
   file, so the 10-minute job never pairs an old launcher with a new pin. Check that the next run logs.
5. Merge C2–C5, one at a time. After each merge:
   - fetch the repo's main checkout;
   - rewrite its shims with `agent-cadence -C <repo> run install_git_hooks.sh`, once per clone (the deploy
     checkout has none and gets none);
   - start one session in it and check its SessionStart output.
6. Merge S. Check that the host agent rebuilt from it (`ao doctor`: `live <sha> = main`). Check that
   `~/.local/share/shiftlead-venv/bin/` holds `agent-cadence` and no `dev-cadence`. Rewrite `~/shiftlead`'s
   shims, and start one session there. Rebuild consumer-b's devcontainer node and consumer-d's devcontainer.
7. Run `ao doctor`: every repo row present, no pin-age warning, and dc-grind listed at `agent-cadence`. In every
   consumer, `git grep -n -i -E 'dev[-_]cadence' origin/HEAD` must show no reader. Each hit must be prose
   history, an archived entry, or a `dev-cadence#` ref to an archived id.
8. Delete `~/.local/bin/dev-cadence`, `~/.config/dev-cadence/` and `~/.cache/dev-cadence/`, then delete R's
   branch. Start one session in each repo again, and run one commit in each to show that its prepare-commit-msg
   and post-merge shims still run. Nothing should reach the old names.
9. Restart the teams from Paul's own shell, not a session pane, so their mail carries over. Start dc-grind for
   the first time.

**Rollback during the sitting:** a consumer not yet merged keeps working on the old launcher and config. A
merged one is reverted by a revert PR. S is reverted the same way, and the host agent rebuilds from main.
Nothing is deleted before step 8.

### Where it sits in TD-191

TD-191 numbers its steps 1–6.
- The sitting runs between step 3 (done) and step 4.
- Step 4's flip waits for the sitting, so the public history's first release carries one name. Step 4's
  privacy read then covers the commits on top of the seed: R, this plan, and anything else merged by then.
- `v0.1.0` is tagged on main after the flip.
- Step 5's ShiftLead registration is done. The sitting's step 9 starts dc-grind. Its pin PRs are C1–C5 and
  S, and its re-pointing of cross-repo refs folds into them.
- Step 6 is unchanged: archive the private ledger's open entries, then archive dev-cadence on GitHub. When it
  runs, it also drops `~/.shiftlead/org.yml`'s `dev-cadence` project. `~/dev-cadence` stays on the roster
  until no `Blocked by` names `dev-cadence#`.

### Not in the sitting

- A ledgerboard release that renames its own header and text. It is filed as an entry in ShiftLead/ledgerboard,
  and it lands through `vendor_ledgerboard.sh` in R's successor and S's re-vendor whenever it ships. Until then,
  the allowlist names the header.
- Paul's layer repo text.

## Consequences

- An outside reader meets one name. The public history has no compatibility code, and none has to be
  removed later.
- The cost is one sitting with every team paused, and a set of PRs that merge together. A PR built early goes
  stale against main, so each is rebased just before the sitting.
- Anything on this machine that the sitting misses fails once step 8 deletes the old names. That includes
  untracked shims in a clone nobody fetched, a container not rebuilt, and a script outside a repo. Steps 5–8's
  session and commit checks are there to find these first. A machine other than this one, if one appears
  later, installs the new launcher fresh.
- A `~/dev-cadence` session after the sitting has no roster and no launcher. The private repo is frozen
  (TD-191 step 1), so nothing needs one.
- `test_one_name.sh` puts a new `dev-cadence` mention, outside the allowlisted forms, out of bounds.
- `docs/publish-accept.txt` accepts Paul's name in every plan under `docs/plans/`. It is deliberate: a plan
  records who decided.

## Revisit triggers

- A second machine or an outside consumer appears before the sitting runs. Then option 2's transition is
  owed to it.
- The sitting cannot finish in one go: some consumer PR cannot merge, or a container cannot be rebuilt.
  Then the old names stay installed, and an entry decides whether the old launcher stays as a deliberate
  alias.
