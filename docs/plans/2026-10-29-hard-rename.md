# ADR 2026-10-29: the tool is renamed agent-cadence, everywhere, in one sitting with no aliases

**Status:** decided 2026-10-29 by Paul (four review rounds, Fable and Sonnet, converged READY)
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

The name has readers in five places. The counts below are for `dev[-_]cadence`, case-insensitive, at `35b4b4a`
and at shiftlead `319dfbd`. Every reader is renamed, except what *What keeps the name* lists.

- **agent-cadence:** 787 lines in 134 files.
  - The `dev-cadence` command, `launcher/dev_cadence.py`, and its install as `~/.local/bin/dev-cadence`.
  - The pin table `[dev-cadence]`: 73 lines in 22 files, including `cadence_config.py`'s `PIN_TABLE`, the
    launcher's `.get("dev-cadence")` reads, and `bump`'s header match (`PIN_HEADER_RE`).
  - `~/.config/dev-cadence/`: the roster `repos.txt`, and the machine `cadence.toml` that names Paul's layer
    and the publish names. `~/.cache/dev-cadence/`: sources, trees, lock.
  - `DEV_CADENCE_REG_DIR`, the only `DEV_CADENCE_*` variable here: 211 lines in 53 files, mostly tests.
  - The `SYNCED FILE` header's *pinned dev-cadence (`dev-cadence path`)*: 46 files.
  - The git hook shims' marker `dev-cadence hook shim (TD-055)` and messages (`install_git_hooks.sh`).
  - The seeded `.agents/skills/*/SKILL.md` pointers.
  - The texts the scripts emit: `check_cadence.py`'s `RUN_PRECHECK`, `forge.py`, `hydrate_worktree.sh`,
    `reap_worktrees.sh`, `open_worktree.sh`, `nudge_user_attention.py`, `adopt`'s PR text.
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
    - `scripts/tdgrind.sh` (`command -v dev-cadence`, already dead under cron, whose PATH lacks `~/.local/bin`);
    - `tests/pinned_cadence.py` (`shutil.which("dev-cadence")`, run by its precheck);
    - the tracked crontab. It runs `~/.local/bin/dev-cadence -C <deploy checkout>` every 10 minutes, and its
      last argument indexes `~/dev-cadence` as a repo.
  - consumer-b: its devcontainer node's `setup_scripts/postCreate.sh` clones `ShiftLead/dev-cadence` into a
    `dev-cadence` sibling and writes the node's roster at `~/.config/dev-cadence/repos.txt`.
  - consumer-d:
    - `.shiftlead.yml`'s `test: dev-cadence run ledger.py --check`;
    - `scripts/check_all_memory.sh` (`dev-cadence -C … path …`);
    - the devcontainer. It creates `~/.config/dev-cadence`, mounts a named volume (its name holds the old one too)
      there (its `Dockerfile` and `devcontainer.json`), and its `postCreate.sh` installs the launcher;
    - `.gitignore` comments.
  - ShiftLead/ledgerboard: its own release text names dev-cadence as a vendoring consumer (see *What keeps the
    name*).
- **Each clone's untracked git hook shims** (`.git/hooks/*`, TD-055). All eight clones carry them. They grep
  `[dev-cadence]` and run `dev-cadence hook`, and when the grep fails they fall through to
  `scripts/git-hooks/<hook>`, which a pinned repo lacks. A moved repo therefore keeps the main-push guard (it is
  inline) but silently loses post-merge and prepare-commit-msg until its shims are replaced.
  - `install_git_hooks.sh` replaces only a hook that carries its own marker (`MARK`, lines 98-104). It keeps
    any other hook as the clone's own, with a WARN.
  - So R's installer, whose marker is `agent-cadence hook shim (TD-055)`, refuses to replace an old shim.
    Old shims are deleted first (the sitting's *shim swap*).
- **Each worktree's own `.claude/settings.json`.** It is tracked on the worktree's branch, so a worktree
  branched before its repo's PR keeps the old line, and its SessionStart hooks go silent until it merges
  main. Worktree counts on 2026-10-29: shiftlead 73, consumer-a 25, consumer-b 8, consumer-d 5, ledgerboard 4,
  consumer-c 3.
- **ShiftLead** (`319dfbd`): 299 lines in 34 files in `src/` and `scripts/`, and about 1,600 prose lines in
  `docs/` and `tests/`. The code readers:
  - The pin, the source and the roster:
    - `cadence.py`: `PIN_HEADER = "[dev-cadence]"`, `is_source`, the container venv's `bin/dev-cadence`;
    - `hosts.py`: `DEV_CADENCE_ROSTER`;
    - `seams.py`: `SHIM_MARKER`, `PINNED_SHIM`;
    - `agent_sync.py`, `agent_tick.py`.
  - The launcher:
    - a vendored frozen copy, `src/sessionorc/dev_cadence.py`, whose hash `tests/test_cadence_pin.py` holds
      (TD-1014);
    - its `dev_cadence_entry.py`;
    - the console script `dev-cadence` and the `extend-exclude` entry in `pyproject.toml`;
    - `containers.py`: `PATH_DEV_CADENCE = "/usr/local/bin/dev-cadence"` and its cache path.
  - The hook line:
    - `adapters/claude_code/__init__.py`: the SessionStart line, a byte-parity pair with R's seed;
      `CADENCE_PINNED_MARKER`; the past vintages;
    - `adapters/gemini/hook.py`: `PINNED_HOOK`;
    - `doctor.py`: `CADENCE_HOOK_NAMES`.
  - Adopt and the CLI:
    - `adopt.py` reads `launcher/dev_cadence.py`, and writes `dev-cadence` into the adopt PR's title, body and
      commit, and into its after-merge instruction;
    - `cli.py`: `NO_DEV_CADENCE`.
  - `scripts/look_home.py`: `SCRATCH_ENV` sets `DEV_CADENCE_REG_DIR` for scratch homes.
  - Tests:
    - three pass `DEV_CADENCE_REG_DIR` to the pinned scripts (`test_ledger_derived.py`, `test_rank_order.py`,
      `test_repo_adopt.py`);
    - five monkeypatch `DEV_CADENCE_ROSTER` (`conftest.py`, `_agent_child.py`, `test_hosts.py`,
      `test_seams.py`, `test_pinned_cures.py`);
    - three read the source checkout through `DEV_CADENCE_SOURCE` (default `~/dev-cadence`) and compare against
      its `origin/HEAD` (`test_cadence_hook_line.py`, `test_pinned_cures.py`, `test_repo_adopt.py`).
  - ShiftLead promotes itself: `promote.auto` is on for shiftlead, and a promote waits for a
    `cadence/precheck` success on main's head. The home runs that precheck through
    `cadence.precheck_script`, which finds the script by reading `~/shiftlead`'s working-tree pin.
- **This machine:**
  - `~/.local/bin/dev-cadence`, `~/.config/dev-cadence/`, `~/.cache/dev-cadence/`. The launcher makes the cache's
    trees read-only.
  - The host agent's venv, which installs its own `dev-cadence` console script
    (`~/.local/share/shiftlead-venv/bin/`). The agent and ui user units, and the tmux and watch system units, put
    that venv ahead of `~/.local/bin` on PATH, so sessions under ShiftLead resolve the launcher there.
  - `~/.shiftlead/org.yml`'s project `dev-cadence` (repo `~/dev-cadence`).
  - consumer-a's deploy checkout. It pulls main every hour at :55 and has no git hook shims.
  - consumer-b's devcontainer node and consumer-d's devcontainer.
  - Paul's layer repo `~/cadence-layer`. `cadence-personal.md`, its README and `craft.md` name the tool in body
    text, and that text is Paul's to update.

Nothing else on the machine reads the name. No systemd unit or timer, and no `~/.claude`, `~/.gemini` or
`~/.codex` settings file does. ShiftLead's generated `~/.shiftlead/claude-hooks/*.json` are rewritten at every
launch.

**What keeps the name.** `dev-cadence` stays where it names the private predecessor repo, because that repo
exists and is kept, and where the text is frozen.

- **Frozen or historical files, kept whole:**
  - `files/docs/cadence-changes.md`. It is append-only, and an old entry is never edited.
  - `docs/ledger/TD-*.md` and `docs/ledger/archive/TD-*.md`. Entries are records, and `dev-cadence#TD-NNN` refs
    to ids archived in the private repo must keep resolving. The two ledger READMEs are not records: R renames
    their headings and rewrites their private-repo mentions into the two forms. `ledger.py` resolves them by roster basename, and live `Blocked by` lines in the
    consumers name them: consumer-a TD-470, consumer-b TD-059 and TD-096.
  - This plan.
  - `files/scripts/ledgerboard.py` and `tests/ledgerboard/**`. The vendored release is byte-frozen: lines 2 and
    14 name dev-cadence, `tests/ledgerboard/run.py --check-header` hashes every byte after line 1, and ShiftLead
    holds its copy byte-equal to the pinned tree's. It changes only with a ledgerboard release that renames
    it.
  - `tests/fixtures/legacy_sync.sh`, the retired copy mode, kept verbatim as `sync.sh --pin`'s input.
- **Two prose forms, anywhere:** *dev-cadence's private plan <slug>*, and *the private dev-cadence repo* (with
  what is in it: *its TD-24*, *its PR #206*). R rewrites every other mention of the private repo into one of
  these forms. That covers `cadence.md`'s *dev-cadence TD-24* and *dev-cadence's `docs/plans/…`*,
  `cadence-rationale.md`, `ledger_next_id.py`, `agent_sessions.py`, `docs/briefs/README.md`'s *PR dev-cadence
  #206*, and `docs/plans/README.md`. A code example of a cross-repo ref (`ledger.py`, the memory-harvest
  procedure, `test_report_fields.sh`) becomes `other-repo#TD-NNN`.
- **The publish gate's own name list:** `cadence_layer.py`'s `TOOL_NAMES` line, and `test_cadence_layer.sh`'s
  cases for it. They keep "dev-cadence" so that the gate still reads the private-repo mentions as the tool's
  own name and not a private one.
- **consumer-d's Docker volume name.** It is an identifier inside Docker that no reader sees, and renaming it
  would orphan the roster it holds.

## Options

1. **Keep the 2026-10-27 line.** The repo is called agent-cadence, and the tool and its docs stay dev-cadence.
   This costs nothing now, but every outside reader meets two names. That is the reason Paul reversed it.
2. **A rename with a transition.** The launcher installs under both names and reads both tables, the config
   and cache dirs fall back to the old ones, `DEV_CADENCE_*` is read beside `AGENT_CADENCE_*`, ShiftLead reads
   both headers, and the installer recognises both shim markers. A later entry drops the old names. This is
   safe against out-of-order merges and against a machine that was missed. The cost is aliases in the
   launcher, in ShiftLead and in the tests, a second cleanup round, and a public first release that ships names
   it is about to remove.
3. **A hard cut in one sitting.** The code drops every old name with no alias. The machine keeps the old
   launcher, config and cache in place through the sitting, as a safety net that needs no code, and they
   are deleted at the end. All teams are paused for the sitting. This is cheaper than option 2, and the
   public history starts with one name. The cost: a pin's move, its table rename and every reader of the old
   name in that repo have to land together, old shims are swapped by hand, and anything missed on this machine
   breaks once the old files are deleted rather than limping on.

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
| ShiftLead: `PIN_HEADER`, `sessionorc/dev_cadence.py` and `dev_cadence_entry.py`, the `dev-cadence` console script, `PATH_DEV_CADENCE`, `DEV_CADENCE_ROSTER`, `DEV_CADENCE_SOURCE` | `[agent-cadence]`, `sessionorc/agent_cadence.py` (re-vendored, new hash) and `agent_cadence_entry.py`, `agent-cadence`, `PATH_AGENT_CADENCE = "/usr/local/bin/agent-cadence"`, `AGENT_CADENCE_ROSTER`, `AGENT_CADENCE_SOURCE` (default `~/agent-cadence`) |

Branch names (`cadence/ledger-ids`, `cadence/precheck`), the `cadence-*` files and `cadence.md` are already
name-free and stay as they are.

### The PRs (built and reviewed before the sitting, merged in it)

1. **agent-cadence, the rename (R).**
   - Every identifier in the table, every emitted text, and every prose mention of the tool across `files/`,
     `launcher/`, `tests/`, `docs/` and the README. The README's *dev-cadence, published as agent-cadence* note
     becomes one sentence: the history before the cut-over is kept privately.
   - The private-repo mentions rewritten into the two forms (*What keeps the name*). `docs/user_attention.md`'s
     heading and `docs/claude-memory/dc-grind-team.md` are renamed.
   - The seeded `settings.json` line and this repo's own line (`tests/test_cadence_hooks.sh`'s parity pair);
     the seeded skills; the shims' marker and messages; the install line in the README, the hooks' messages
     and `adopt`'s.
   - `tests/test_install_git_hooks.sh` gains the case *an old-marker shim is kept with a WARN*. That case is the
     reason for the sitting's shim swap.
   - Deleted, because the seed is built:
     - `snapshot_public.sh`, `tests/test_snapshot_public.sh`, and `docs/publish-accept.txt`'s line for that test;
     - the `snapshot()` branches keyed on the README note in the six dogfood suites: `test_briefs_primer.sh`,
       `test_cadence_hooks.sh`, `test_ledger.sh`, `test_ledger_archive.sh`, `test_ledger_links.sh`,
       `test_parity.sh`.

     `sync.sh --pin` and `tests/fixtures/legacy_sync.sh` stay.
   - A new `tests/test_one_name.sh` matches `dev[-_]cadence`, case-insensitively, over `git ls-files`. It fails
     on any match not covered by `tests/one_name_allow.txt`, whose lines are `<path-glob> <line-glob>` like
     `docs/publish-accept.txt`'s. The allowlist holds exactly *What keeps the name*: the frozen files whole,
     the two prose forms on any path, the `TOOL_NAMES` line and its cases, and the allowlist file itself (as
     `docs/publish-accept.txt` accepts itself). Untracked `.git/hooks` are beyond
     its reach, and the sitting's step 9 is the check for them.
   - A `files/docs/cadence-changes.md` entry: the command, table, dirs, variable and shim marker are renamed,
     with the old names in that entry and the shim swap's one-liner. The techlead primer and `docs/briefs/`
     follow the rename.
   - The docs proofread, held since 2026-10-29, lands in R's review or straight after R merges.
2. **ShiftLead, the rename and its own pin (S).**
   - Every code reader listed under Context, the tests' variables, and the prose in `docs/` and `tests/`.
   - The vendored launcher re-vendored from R, with the test's hash updated.
   - The console script and the container link renamed.
   - The parity tests read `AGENT_CADENCE_SOURCE` and a new `AGENT_CADENCE_REF` (default `origin/HEAD`) in place
     of the hard-coded `origin/HEAD`. Before the sitting they are pointed at R's branch head. In the sitting
     they run on their defaults, against R on main.
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
     Dockerfile dir, the volume's mount target, `postCreate.sh`'s install, and the `.gitignore` comments. The
     volume's name stays.
   - TD-191's cross-repo re-pointing of refs to carried entries (`dev-cadence#TD-144` and others to
     `agent-cadence#`) folds into these PRs and S.

   These replace TD-191 step 5's seven pin PRs. consumer-a's deploy checkout follows its merge.

**The ref.** agent-cadence squash-merges, so R's commit on main does not exist until the sitting, and the
launcher fetches only branches and tags (`ensure_tree`).
- Before the sitting:
  - R is rebased onto main once, and only then do the other PRs pin its branch head. After that, R changes
    only by plain pushes, and any rewrite of R means re-pinning every PR.
  - agent-cadence's main is held still, with nothing merged but R. The teams are paused, and this plan's PR
    merges first.
  - Each PR is reviewed and prechecked against R's head, using a scratch install of R's launcher with
    `AGENT_CADENCE_REG_DIR=$(mktemp -d)`, so the real roster is untouched. The machine `cadence.toml` is then
    absent, which no precheck needs. An unresolvable cross-repo `Blocked by` reads as still blocked, not as an
    error.
  - R's branch is kept until the sitting ends.
- In the sitting, once R is merged:
  - each PR gets a one-line commit that sets `ref` to R's merged commit;
  - the merged commit's tree must equal the pinned head's (`git diff --quiet <head> <merged>`);
  - its precheck then reruns on that commit, with TD-186's `--expect`.
- A merge commit instead of the squash would keep the pinned head in main's history and save the re-pin, but
  it puts R's working commits into the public history, so the squash stands.

**Precheck time.** consumer-a, consumer-b and ShiftLead have a `precheck`; consumer-c, consumer-d and ledgerboard
have none. consumer-b's takes its long path (node and Flutter on Chrome) whenever `tools/precheck.sh` changes,
and C2 edits that file. Budget 15–30 minutes for the sitting's reruns. Run S's alone, and the other two
together.

### The sitting

Before it:
- Every team is stopped, ao-grind included. `on_work` is already set to do nothing.
- `reap_worktrees.sh --reap` runs in every repo, and the surviving worktrees are listed. Each of them must merge
  main after the sitting to get its hooks back.
- The runbook is run from a session in `~/agent-cadence`, not `~/dev-cadence`: once the old config is deleted, a
  `~/dev-cadence` session sees no roster.

The **shim swap**, for one clone: delete the hooks that carry the old marker
(`grep -lF 'dev-cadence hook shim (TD-055)' "$(git -C <clone> rev-parse --path-format=absolute --git-common-dir)"/hooks/* | xargs -r rm`;
without `--path-format=absolute`, a main checkout prints a relative `.git` and the glob reads the session's own
clone), then run `agent-cadence -C <clone> run install_git_hooks.sh`. The launcher and the installer read the
clone's working tree, so the clone is pulled to its merged main first.

1. Merge R. Check that the merged tree equals the pinned head. Run `git -C ~/agent-cadence pull --ff-only`, so the working tree is R. Run
   `install -m 755 launcher/agent_cadence.py ~/.local/bin/agent-cadence` beside the old launcher. Do the shim
   swap in `~/agent-cadence`.
2. Check that `~/.config/agent-cadence` is absent, run `cp -aT ~/.config/dev-cadence ~/.config/agent-cadence`,
   and delete the copy's `repos.txt.bak-*`. The roster keeps `~/agent-cadence` first, and keeps `~/dev-cadence`
   for the archived `dev-cadence#` refs and `seams.descends`. The machine `cadence.toml` comes with it.
3. Push each PR's `ref` commit (R's merged SHA) and run its precheck.
4. Merge C1 (consumer-a), between :05 and :50 so the hourly deploy pull does not land mid-step. At once:
   - pull its deploy checkout by hand;
   - reinstall its crontab from the merged file;
   - `git pull --ff-only` in consumer-a's main checkout, then do its shim swap, and start one session there.

   Check that the next 10-minute index run logs.
5. Merge C2–C5, one at a time. After each merge:
   - `git pull --ff-only` in the repo's main checkout;
   - do the shim swap, once per clone;
   - start one session in it and check its SessionStart output.
6. Merge S. Leave `~/shiftlead`'s working tree on the old pin until the home has promoted the merge. The old
   agent finds the precheck script through that pin, and pulling first stalls the promote with *no
   cadence/precheck*. If the promote does not come, run `dev-cadence -C ~/shiftlead run precheck.py --commit
   <sha>` by hand. It must be the old launcher, because the working tree still holds `[dev-cadence]`, and the
   old launcher stays installed until step 9. The promote's own pull then moves `~/shiftlead` to S.

   Once `ao doctor` shows `live <sha> = main`:
   - check that `~/.local/share/shiftlead-venv/bin/` holds `agent-cadence` and no `dev-cadence`;
   - check that `~/shiftlead` is at S (the promote pulls it), do its shim swap, and start one session there;
   - rebuild consumer-b's devcontainer node and consumer-d's devcontainer.
7. Run `ao doctor` (read it only now, after S is live: between steps 4 and 6 the old agent sees each moved
   repo as unpinned). It must show every repo row present, no pin-age warning, and dc-grind listed at
   `agent-cadence`.
8. Run `git grep -n -i -E 'dev[-_]cadence' origin/HEAD` in every consumer, and in ShiftLead over `src/`,
   `scripts/` and `tests/`. It must show no reader. Each hit must be prose history, an archived entry, a
   `dev-cadence#` ref to an archived id, or consumer-d's volume name.
9. Delete the old names:
   - run `chmod -R u+w ~/.cache/dev-cadence`, then delete it;
   - delete `~/.local/bin/dev-cadence` and `~/.config/dev-cadence/`;
   - delete R's branch.

   Start one session in each repo again, and make one commit in each to show that its prepare-commit-msg and
   post-merge shims still run. Nothing should reach the old names.
10. Restart the teams from Paul's own shell, not a session pane, so their mail carries over. Start dc-grind for
    the first time.

**Rollback during the sitting:** a consumer not yet merged keeps working on the old launcher and config. A
merged one is reverted by a revert PR, then its shims are swapped back by the old installer: pull the revert, delete the
new-marker hooks (the same `grep -lF`, with `--path-format=absolute`, on `agent-cadence hook shim (TD-055)`), then run `dev-cadence -C <clone> run install_git_hooks.sh`. S is reverted the same way, and
the host agent rebuilds from main. Nothing is deleted before step 9.

### Where it sits in TD-191

TD-191 numbers its steps 1–6.
- The sitting runs between step 3 (done) and step 4.
- Step 4's flip waits for the sitting, so the public history's first release carries one name. Step 4's
  privacy read then covers the commits on top of the seed: R, this plan, and anything else merged by then.
- `v0.1.0` is tagged on main after the flip.
- Step 5's ShiftLead registration is done. The sitting's step 10 starts dc-grind. Its pin PRs are C1–C5 and
  S, and its re-pointing of cross-repo refs folds into them.
- Step 6 is unchanged: archive the private ledger's open entries, then archive dev-cadence on GitHub. When it
  runs, it also drops `~/.shiftlead/org.yml`'s `dev-cadence` project. `~/dev-cadence` stays on the roster
  until no `Blocked by` names `dev-cadence#`.

### Not in the sitting

- A ledgerboard release that renames its own text. It is filed as an entry in ShiftLead/ledgerboard, and it
  lands through `vendor_ledgerboard.sh` in a later agent-cadence PR, and in ShiftLead's re-vendor, whenever
  it ships. Until then the allowlist keeps `ledgerboard.py` whole.
- A one-name test in ShiftLead. Step 8's grep is the check there for now.
- Paul's layer repo text.

## Consequences

- An outside reader meets one name. The public history has no compatibility code, and none has to be
  removed later.
- The cost is one sitting with every team paused, and a set of PRs that merge together. A PR built early
  goes stale against main, so each is rebased just before the sitting.
- Anything on this machine that the sitting misses fails once step 9 deletes the old names. That includes
  untracked shims in a clone nobody fetched, a container not rebuilt, and a script outside a repo. The
  session and commit checks in steps 4–6 and 9 are there to find these first. A machine other than this one,
  if one appears later, installs the new launcher fresh.
- A worktree branched before its repo's PR has silent SessionStart hooks until it merges main.
- A `~/dev-cadence` session after the sitting has no roster and no launcher, and its clone keeps its old shims
  (never swapped), so a commit there prints *no dev-cadence launcher on PATH*. The private repo is frozen
  (TD-191 step 1), so nothing needs one.
- `test_one_name.sh` puts a new `dev-cadence` mention, outside the allowlisted forms, out of bounds.
- `docs/publish-accept.txt` accepts Paul's name in every plan under `docs/plans/`. It is deliberate (Paul,
  2026-10-29): a plan records who decided.

## Revisit triggers

- A second machine or an outside consumer appears before the sitting runs. Then option 2's transition is
  owed to it.
- The sitting cannot finish in one go: some consumer PR cannot merge, or a container cannot be rebuilt.
  Then the old names stay installed, and an entry decides whether the old launcher stays as a deliberate
  alias.
