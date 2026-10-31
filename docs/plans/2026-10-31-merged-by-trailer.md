# ADR 2026-10-31: a cadence merge writes its own squash body, ending in one trailer paragraph that names who wrote, reviewed, checked and merged the change

**Status:** proposed. Class: **wide** (cap `design-rounds-wide`, 6). The reason: it changes how every consumer merges (cadence.md §4.2, the procedure's step 5, a payload script), and ShiftLead's briefs merge through it. The shape is the Fix of 2026-10-28. Paul's go of 2026-10-30 was on the `Merged-by:` trailer, and it lifted the entry's block. The board line's close says *the Fix's shape stands; its design rounds run before the build*, and the entry's Status leaves the rest of the shape to these rounds: the merge command, `Reviewed-by:`/`Precheck:` and the signed comments. Review rounds: see `docs/reviews/TD-177.md`.
**Date:** 2026-10-31
**Related:** TD-177 (this design and its build); TD-067 (§4.2's squash keeps the trailers); TD-181 (the `Agent-Model:` commit trailer, built: cadence.md §9.9 and the hook name it, and its entry is not in this repo's ledger); shiftlead#TD-645 (the same trailer on ShiftLead's side); TD-117 and TD-148 (the precheck the gate reads); cadence.md §4.9 (the evidence comment).

## Context

- **Authorship traces; the merge does not.** §9.9's `prepare-commit-msg` hook writes `Co-Authored-By: <AGENT_NAME> <…>` and `Agent-Model: <adapter>/<model>` (TD-181) on every agent commit. §4.2's squash keeps the commit messages in the body.
- **The forge writes the squash commit.** Its committer is `GitHub <noreply@github.com>`. Who pressed merge lives only in the forge's PR data, under an account that sessions and the person share.
  - On 2026-10-28 dev-cadence #429 was held for Paul's merge under his §4.11 rule, and it read as merged by that account. git could not say whether Paul or a session had merged it.
- **What GitHub's squash body holds today** (this repo's #55, `git log -1 origin/main` on 2026-10-31):
  - each commit's message as `* <subject>`, then its body, with that commit's own trailer paragraph;
  - then a `---------` line;
  - then one paragraph of `Co-authored-by:` lines that GitHub writes itself.
- **What survives as a trailer.** git reads trailers only from the last paragraph, so only GitHub's `Co-authored-by:` lines survive. Every `Agent-Model:` is buried mid-body, and `git log --format='%(trailers:key=Agent-Model)'` on a squash commit prints nothing.
- **What that trace is for.** Paul wants to go from a bad behaviour back through git to the session and the model that did it, then fix that session's brief, rule or code. With on-prem models coming, the model matters as much as the session.

## Design

1. **The gate hands the merge what it saw: `check_cadence.py --pr <n> --trailers FILE`.** On exit 0, and only then, it writes FILE:
   - the first line is `expect <sha>`, the head commit its rows judged;
   - then one `Reviewed-by:` line for each `cadence-review:` comment the `review` row lists, in the order posted, as `Reviewed-by: <model> (<verdict>)`. `<model>` is the first `·`-separated field after the verdict in `REVIEW_RE`'s match, as written. A BLOCK then FIXED gives two lines, `(BLOCK)` then `(FIXED)`.
   - then `Precheck: <sha>` when the repo sets `precheck` and the `ci` row passed on its status. That sha is the same head.

   The gate stays a reader. It merges nothing, and with no `--trailers` it behaves as today. The review and precheck logic stays where it is (`row_review`, the `ci` row in `check_cadence.py`), and `forge.py`, which `check_cadence.py` imports, learns no cadence rows.

2. **One merge command: `forge.py merge <n> --gate FILE`** (a new subcommand of `files/scripts/forge.py`, the forge layer). It merges the PR as a squash, with a message it composes, and decides nothing. FILE is required and its `expect` line too: no gate file, no merge.
   - The forge is asked to merge only while the PR's head is that sha: `gh pr merge <n> --squash --match-head-commit <sha> --subject … --body …`, and `glab mr merge <n> --squash --sha <sha> --squash-message …` (one string: the subject, a blank line, the body). A push between the gate and the merge is refused, and the command exits non-zero saying so.
   - It never passes `--delete-branch`, so the §1.4 caution holds.
   - **The procedure's step 5** becomes `python3 scripts/check_cadence.py --pr <n> --trailers <tmp> && python3 scripts/forge.py merge <n> --gate <tmp>`, replacing `gh pr merge <n> --squash`.
   - **Subject:** the command writes it as `<PR title> (#<n>)` (GitLab: `<MR title> (!<n>)`, §4.2's template). With `--subject` given, `gh` uses the text verbatim, so the number is the command's to add.
   - **Body:**
     - A PR of **one commit** gets that commit's body with its trailer paragraph removed, as GitHub writes a one-commit squash (#57: the title, then the plain body).
     - A PR of **several commits** gets each commit, oldest first, as `* <subject>`, then its body with its trailer paragraph removed, the commits separated by blank lines (#55's form).
     - Then one blank line and the **trailer paragraph**, the message's last, so `git interpret-trailers --parse` reads every line of it. No `---------` line is written, and no paragraph after it.
   - **What GitHub does with a given body** is an assumption until the build shows it. §4.2 already says that a written body drops GitHub's own `Co-authored-by:` paragraph, which suggests GitHub then appends nothing. The build's first real merge through the command, in this repo, reads its squash commit back (`git log -1 --format='%(trailers)'`). If anything follows the composed paragraph, the build stops there, and that becomes a finding on this design.

3. **The trailer paragraph,** in this order:
   - **`Co-Authored-By:`** — every value from the commits' own trailer paragraphs, deduplicated on the email address with case ignored, first spelling kept. Then the author of every commit whose author is not the squash commit's author (the PR's author, whom the forge sets) and who is not already listed. That is where GitHub's own paragraph found its names, so a person's commit with no hook trailer, or a rebased commit by another author, keeps its credit.
   - **`Agent-Model:`** — every distinct value from the commits, in first-seen order. A PR worked under two models names both.
   - **`Reviewed-by:`** and **`Precheck:`** — the gate file's lines, as written.
   - **`Merged-by:`** — `<AGENT_NAME> (<model>)`, where `<model>` is the value the hook writes as `Agent-Model:` (`<adapter>/<model>`, one string; no adapter is read apart from it). With no model it is `Merged-by: <AGENT_NAME>`, and with no `AGENT_NAME` (a person's shell) it is `Merged-by: <git config user.name>`.

   **The model and the name are read and checked exactly as the hook reads and checks them:**
   - the first line of `$AGENT_MODEL_FILE` when set and readable, else `$AGENT_MODEL`;
   - trimmed, printable characters only, at most 120;
   - `AGENT_NAME` only `[A-Za-z0-9._-]+`;
   - a value that fails is left out, as the hook leaves it out.

   The hook is bash and `forge.py` is Python, so they cannot share a helper. They are a **parity pair** (§7.9): §9.9 states the reading once, and a test feeds the same environments to both and compares the model each writes.

4. **What is absent is read too.** A merge from the forge's web UI, or by a bare `gh pr merge`, writes no `Merged-by:`, and its absence reads as *a person, in the forge UI*. That is accurate while Paul is the only one who merges outside the cadence, and §4.2 says so. A session's merge that skips the command shows up the same way, which is the event this design exists to catch.

5. **The evidence comments are signed.** A comment is not git and cannot carry a trailer. So each comment the cadence procedure has a session post, the §4.9 `cadence-review:` evidence comment and its late form (*a PR that merged with no review*), ends with one line `— <AGENT_NAME> (<model>)`, or `— <user.name>` from a person's shell, read as in 3. Comments a session posts for its own brief's reasons are that brief's to sign, ShiftLead's among them. `REVIEW_RE` reads the verdict on whichever line it is, and takes the last such line (§4.9, TD-087). The signature carries no `cadence-review:`, so it changes no reader.

6. **Where it lives:**
   - **cadence.md §4.2** — the ban on a written body becomes *the merge command writes it*. The section names the trailer paragraph, what each key means, and that a web-UI merge carries no `Merged-by:`.
   - **cadence.md §4.9** — the signature line.
   - **cadence.md §9.9** — the one statement of how the model and name are read, which the hook and `forge.py merge` share.
   - **cadence.md §7.9's list** — the new parity pair.
   - **The procedure** — step 5's two commands; step 3's comment form gains the signature.
   - **`files/scripts/check_cadence.py`** — `--trailers`.
   - **`files/scripts/forge.py`** — `merge` and `squash_message(commits, trailers, …)`, a pure function under test.
   - **`files/docs/cadence-changes.md`** — one entry.
   - **ShiftLead** — its briefs' merge lines (the *A merge here is `gh pr merge <n> --squash`* line in each repo's part) move to the command. That is a shiftlead entry, filed by the build. Each consumer's own brief text reaches it on its next `agent-cadence bump`.

7. **Tests:**
   - **`tests/test_forge.sh`, `squash_message`:**
     - the trailer paragraph is last, and `git interpret-trailers --parse` over the message lists every key;
     - `Co-Authored-By:` is deduplicated with case ignored, and a commit author without a trailer is added;
     - two `Agent-Model:` values are both kept;
     - the one-commit and many-commit shapes;
     - a commit body holding `---------` stays text.
   - **`tests/test_forge.sh`, `merge` with a `gh` shim:**
     - the arguments, including `--match-head-commit`;
     - never `--delete-branch`;
     - no gate file, or no `expect` line, refuses;
     - with no `AGENT_NAME` it writes `user.name`;
     - `AGENT_MODEL_FILE` takes precedence over `AGENT_MODEL`;
     - a forge refusal exits non-zero.
   - **`tests/test_forge_gitlab.sh`** — glab's `--squash --sha --squash-message`, with subject and body in the one string.
   - **`tests/test_check_cadence.sh`** — `--trailers` writes nothing on a failing PR, and the lines and their order on a passing one with a BLOCK then a FIXED.
   - **The parity test** — the hook and `forge.py` given one environment write one model.
   - **A git round trip** — a squash commit made with the composed message reads every key back through `%(trailers:key=…)`.

## Options

- **A step in `check_cadence.py`'s exit-0 path** (the Fix's other form), which merges when the gate passes. Not chosen. It turns the reader into the actor, so `check_cadence.py --pr <n>` stops being safe to run just to look, and every reader of the cadence check would have to know it can merge. `--trailers` keeps the check a reader and hands the merge what the check read.
- **Keep GitHub's body and only append a `Merged-by:` paragraph.** Then GitHub's `Co-authored-by:` paragraph is no longer last, so those authors stop being trailers, and the `Agent-Model:` lines stay buried. Not chosen.
- **git notes.** No forge shows them, and one shared notes ref conflicts the way the one-file ledger did. Not chosen (the Fix).
- **A local squash pushed to main.** The pre-push hook and branch protection rightly block it. Not chosen (the Fix).
- **A forge account per agent,** so the forge UI itself shows the actor. It is forge-specific and costs an account each. Out of scope unless Paul asks (the Fix).
- **Do nothing.** The transcript stays the only record of who merged, and on another machine there is none.

## Decision

Proposed. The shape is the 2026-10-28 Fix, whose block Paul lifted on 2026-10-30. This plan settles its open forms:
- the command is `forge.py merge`, fed by `check_cadence.py --trailers`, not a gate step;
- the gate file and its head sha are required;
- GitHub's own trailer paragraph is replaced by the composed one;
- `Reviewed-by:` and `Precheck:` are written.

The rounds run to the stop rule or the cap. The builds wait on Paul's go, as his layer's §2.4 rule holds a design's builds until its rounds converge and he says go.

## Consequences

- `git log --format='%(trailers:key=Merged-by,valueonly)'` names the merger of every cadence merge from the build on. `%(trailers:key=Agent-Model)` names every model that worked a change, and `Reviewed-by:` and `Precheck:` say what the gate saw.
- A squash body is no longer the forge's to write. If a forge changes how its default body looks, nothing here breaks, but a forge without a body option cannot use the command.
- A merge through any other path is visible by what it lacks, and a weekly read (`check_cadence.py --since 7d`) can list those merges later. That is a detector, not built here.
- Every consumer's merge line changes on its next bump. Until then its sessions merge as today.

## Revisit triggers

- A forge here that cannot take a squash message.
- A second person who merges in the forge UI, which makes a missing `Merged-by:` ambiguous.
- Per-agent forge accounts.
