# ADR 2026-10-31: a cadence merge writes its own squash body, ending in one trailer paragraph that names who wrote, reviewed, checked and merged the change

**Status:** proposed. Class: **wide** (cap `design-rounds-wide`, 6). The reason: it changes how every consumer merges (cadence.md §4.2, the procedure's step 5, a payload script), and ShiftLead's briefs merge through it. The shape is the Fix of 2026-10-28. Paul's go of 2026-10-30 was on the `Merged-by:` trailer, and it lifted the entry's block. The board line's close says *the Fix's shape stands; its design rounds run before the build*, and the entry's Status leaves the rest of the shape to these rounds: the merge command, `Review:`/`Precheck:` and the signed comments. Review rounds: see `docs/reviews/TD-177.md`.
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

1. **The gate hands the merge what it saw: `check_cadence.py --pr <n> --trailers FILE`** (`--pr` only; with `--branch` or `--since` it is a usage error). Every run first empties FILE, then writes it whole (to a temporary name, then renamed): on exit 0 in the verified form below, on any other exit in the unverified form, and on a run that could not read the PR (exit 2 with no head) not at all, so FILE stays empty and no merge is possible. The verified form:
   - `pr <n>`;
   - `expect <sha>` — the head commit its rows judged, taken from the one read of the PR the rows used, never re-read;
   - then one `Review:` line for each `cadence-review:` comment the `review` row lists, in the order posted, as `Review: <model> (<verdict>)`. `<model>` is the text before the first `·` of the review's `rest` as `row_review` strips it (`strip(" ·-")`), stripped again of spaces. It is `unknown` where that text is empty, or is `code` or `docs` (a comment that skipped the model field). The key is `Review:`, not git's `Reviewed-by:`, because a BLOCK is a review and not an approval. §4.2 says what the verdict in parentheses means. A BLOCK then FIXED gives two lines, `(BLOCK)` then `(FIXED)`. A review comment is not bound to a head, so a `Review:` may name a review of an earlier head; `Precheck:` is bound to this one.
   - then `Precheck: <sha>` when the repo sets `precheck` and the head's `cadence/precheck` commit status reads `success`, as the `ci` row's precheck reader sees it (the status itself, not the row's verdict, which can also pass on check runs). That sha is the same head.

   - **The data comes from the code, not the row's text.** `row_review` and `check_pr` return what they read: each listed comment's model and verdict, and the PR's `head_sha` from its one read. The review row also gains a `carve_out` field (`board-edit`, `queue-edit` or none), set where `board_edit_or_review` passes the PR today by `row_board_edit_pr` or `row_queue_edit_pr`. `--trailers` writes from those fields and never re-parses a rendered row.
   - **On a non-zero exit** the gate writes FILE as `pr <n>`, `expect <sha>` and `unverified <exit code> <the failing rows>`, with no `Review:` or `Precheck:`. That is the deliberate path for a merge the procedure allows on a non-pass: step 5's *an unknown that will not clear*, a late review, the person's own call. It is refused unless the merge says why (2).

   **These trailers are attested, not verified**, like the review row they come from (§4.9): a hand-written file would put its own lines in the squash, and §4.2 says so. The procedure makes FILE with `mktemp`.

   The gate stays a reader. It merges nothing, and with no `--trailers` it behaves as today. The review and precheck logic stays where it is (`row_review`, the `ci` row in `check_cadence.py`), and `forge.py`, which `check_cadence.py` imports, learns the gate file's format and the trailer policy but no row logic.

2. **The message is composed; the merge stays the forge CLI's: `forge.py squash-message <n> --gate FILE --out DIR`** (a new subcommand of `files/scripts/forge.py`, the forge layer). It writes `DIR/subject`, `DIR/body` and `DIR/sha` (the gate's `expect`), and merges nothing. The merge itself stays a literal `gh pr merge` / `glab mr merge` on the session's command line, so whatever guards a merge by that command (a person's permission rule, the harness's classifier, which today refuses a session's `gh pr merge` where the person's word is needed) sees every cadence merge as it does today. A merge hidden inside a script would slip past that guard, and the #429 event is what it exists to stop. FILE is required, with its `pr` line naming this PR and its `expect` line: no gate file, another PR's, or one without the head, and nothing is composed.
   - `--unverified` with a gate file in the verified form is refused. A file marked `unverified` is composed only with `--unverified "<why>"`, which writes `Merge-override: <exit code> <the failing rows' names> — <why>` into the trailer paragraph, the row names taken from the gate file's `unverified` line, the why collapsed to one line (every run of whitespace, newlines included, one space; at most 200 bytes), so it cannot add a trailer of its own. A merge the gate did not pass then still carries `Merged-by:`, and says what it overrode and why.
   - **The commits** are read through a new `forge.py` method, `pr_commits(n)`, oldest first:
     - GitHub: `gh api repos/<o>/<r>/pulls/<n>/commits --paginate`, whose concatenated pages are read through `forge.py`'s `_pages()`, called explicitly (GitHub's other reads, `comments` among them, use `_json`, which reads one page; only GitLab's use `_pages` today), and which never returns more than 250. The list's length is compared with the PR's own `commits` count (`GET pulls/<n>`), and a mismatch refuses, so a longer PR is never squashed with part of its trailers;
     - GitLab: `glab api projects/<id>/merge_requests/<n>/commits --paginate`, newest first, reversed;
     - GitLab's list has no 250 cap and its MR record no count to compare, so there `--paginate` reading every page is the check, and a page that cannot be read refuses;
     - none, or a list that cannot be read, refuses. A squash with no trailers is never written.
   - **The procedure's step 5** becomes, on GitHub: `m=$(mktemp -d); python3 scripts/check_cadence.py --pr <n> --trailers "$m/gate"; python3 scripts/forge.py squash-message <n> --gate "$m/gate" --out "$m" && gh pr merge <n> --squash --match-head-commit "$(cat "$m/sha")" --subject "$(cat "$m/subject")" --body-file "$m/body"`. On GitLab it is the same with `glab mr merge <n> --squash --sha … --squash-message "$(cat "$m/subject"; echo; cat "$m/body")"`. The `;` after the gate is deliberate: `squash-message` refuses an unverified file by itself. `--match-head-commit` / `--sha` makes the forge refuse a push made between the gate and the merge. Step 5's rule stays *merge only on exit 0*, with its one allowance: exit 3, an unknown that will not clear, found out and said in the PR, is composed with `--unverified "<what you found>"`: the session runs the whole line again in one command, with the flag added to `squash-message` (a shell variable such as `$m` does not survive between a tool's separate calls). The confirm that follows is §1.4's, unchanged: `gh pr view <n> --json state`. The line never passes `--delete-branch`.
   - **Subject:** `squash-message` writes it as `<PR title> (#<n>)` (GitLab: `<MR title> (!<n>)`, §4.2's template). With `--subject` given, `gh` uses the text verbatim, so the number is `squash-message`'s to add.
   - **Body:**
     - Each commit's trailer paragraph is the one `git interpret-trailers --parse` finds in its message (git's own rule: the last paragraph, when every line of it is a trailer, or it holds a trailer git knows, such as `Signed-off-by:`, and at least a quarter of it is trailers; folded lines are joined). `Co-Authored-By:` and `Agent-Model:` are not trailers git knows, so a mixed last paragraph holding only those is not parsed, and its lines stay as text, as git itself reads them. Nothing else is read as a trailer. The lines `--parse` returns are matched back to the raw message, so everything else in the paragraph stays as written. From it the six keys the composed paragraph carries are lifted out, matched case-insensitively as git does. `Co-Authored-By:` and `Agent-Model:` are carried into it. `Review:`, `Precheck:`, `Merged-by:` and `Merge-override:` written in a commit are dropped, so only the gate file and the command write those. Any other trailer (`Signed-off-by:`, `Fixes:`) stays where it was in that commit's text, and a paragraph left empty is dropped.
     - A PR of **one commit** gets that commit's body, as GitHub writes a one-commit squash (#57: the title, then the plain body).
     - A PR of **several commits** gets each commit, oldest first, as `* <subject>`, then its body, the commits separated by blank lines (#55's form).
     - Then one blank line and the **trailer paragraph**, the message's last, so `git interpret-trailers --parse` reads every line of it. No `---------` line is written, and no paragraph after it.
   - **What GitHub does with a given body** is an assumption until the build shows it. §4.2 already says that a written body drops GitHub's own `Co-authored-by:` paragraph, which suggests GitHub then appends nothing. The build's own PR is the last one merged here the old way. The first PR after it merges through the command and reads its squash commit back (`git log -1 --format='%(trailers)'`). If anything follows the composed paragraph, that is a defect entry, carrying `Escaped from: TD-177` if its filer judges it a design miss (§2.13's question), and the command is not used again until it is fixed.

3. **The trailer paragraph,** in this order:
   - **`Co-Authored-By:`** — every value from the commits' own trailer paragraphs, deduplicated on the email address with case ignored, first spelling kept. Then every commit's author, `<name> <email>` from git, whose email is not already listed (case ignored). GitHub's own paragraph found its names in the commit authors, so a person's commit with no hook trailer, or a rebased commit by another author, keeps its credit. Unlike GitHub, this does not leave out the PR's author: the forge gives a login, and git has a name and email, so there is nothing to compare them by. A line naming the squash commit's own author is redundant, never wrong.
   - **`Agent-Model:`** — every distinct value from the commits, in first-seen order. A PR worked under two models names both.
   - **`Review:`** and **`Precheck:`** — the gate file's lines of those two keys only. Any other line in it is ignored.
   - **`Merge-override:`** — with `--unverified` only (2).
   - **`Merged-by:`** — `<AGENT_NAME> (<model>)`, where `<model>` is the value the hook writes as `Agent-Model:` (`<adapter>/<model>`, one string; no adapter is read apart from it). With no model it is `Merged-by: <AGENT_NAME>`, and with no `AGENT_NAME` (a person's shell) it is `Merged-by: <git config user.name>`. An `AGENT_NAME` that is set but fails its check, or no `AGENT_NAME` and no `user.name`, refuses the merge, saying which: a merge that cannot say who made it is not made, and a bad name never falls through to the person's. A session with no `AGENT_NAME` at all (a cloud session, a tool ShiftLead did not start) reads as the person, and §4.2 says that a session's merge is traced only where `AGENT_NAME` is set. ShiftLead sets it for every session it starts.

   **The model and the name are read and checked exactly as the hook reads and checks them:**
   - the first line of `$AGENT_MODEL_FILE` when it is a regular, readable file (`-f`, `-r`), read like `read -r`, so an unterminated last line counts; else `$AGENT_MODEL`;
   - an empty first line, or an empty file, falls through to `$AGENT_MODEL` before anything is checked;
   - with `LC_ALL=C` set before anything is stripped, leading and trailing C-locale `[[:space:]]` (space, `\t`, `\n`, `\v`, `\f`, `\r`) stripped. Then the value is matched once against `^[[:graph:]]+( [[:graph:]]+)*$`, at most 120 bytes. In Python that is the bytes read, `strip(b" \t\n\v\f\r")`, then `[\x21-\x7e]+( [\x21-\x7e]+)*`. NUL bytes are dropped first, as bash's `read -r` drops them, so `ab\0cd` reads `abcd` on both sides. Any other non-ASCII byte, invalid UTF-8 included, fails the match;
   - a value that fails is left out, with no fallback to `$AGENT_MODEL`;
   - the hook gains `LC_ALL=C` for the window that holds both strip lines (their `[![:space:]]` globs), the match and the length test, and nothing else, set as a shell assignment around them and restored after, before the next child process (the `git config` before `${#cc}`): the old value put back if `LC_ALL` was set, `unset LC_ALL` if it was not. No child runs inside that window, so it is never seen exported. That keeps `${#cc}` and the comment-line test as they are. Today the match follows the session's locale, so a UTF-8 session accepts non-ASCII and the length counts characters; after this it counts bytes. That is a behaviour change to the hook, listed in 6;
   - `AGENT_NAME` only `[A-Za-z0-9._-]+`;
   - an `AGENT_NAME` that fails refuses the merge (below), where the hook only leaves its co-author line out. `squash-message` does not read `AGENT_DOMAIN`, since `Merged-by:` carries no address, so a bad domain that makes the hook drop the name does not stop the merge.

   The hook is bash and `forge.py` is Python, so they cannot share a helper. They are a **parity pair** (§7.9): §9.9 states the reading once, and a test feeds the same environments to both (double spaces, a tab, `\v` at an edge, a non-ASCII space (U+2003) at an edge, non-ASCII, invalid UTF-8, a NUL, 121 bytes, a CRLF file, an unterminated line, an empty first line) and compares the model each writes.

4. **Everyone merges through step 5's line, so its absence means a bypass.** The person merges with it too, from their shell (`Merged-by: <user.name>`). A squash commit on the default branch with no `Merged-by:` was merged around that line: in the forge's web UI, by a bare `gh pr merge`, or by a session on a pin older than this build. git cannot say which, and §4.2 says so plainly. It can say *that*, and the #429 event (a session merging what should have waited) is one of them.
   - **The detector:** `check_cadence.py --since <window>` (the weekly read) lists each merged PR whose squash commit carries no `Merged-by:`, *merged outside step 5*. It is a detector, never a fail, because a person's web-UI merge is legitimate. A repo reads that list against its own §4.11 rule.
     - It is printed as a section after the rows, and as `merged_outside` (a list of PR numbers) in `--json`.
     - **Cutoff:** only merges after the repo's first squash commit carrying a `Merged-by:` trailer are listed. It is found by reading `git log --format='%H%x00%(trailers:key=Merged-by,valueonly)'` over the default branch: a commit whose value is non-empty counts, the key matched case-insensitively as git matches it, never by `git log --grep`, which would match any message that only mentions it, this design's among them. A repo that has never merged through step 5's line lists nothing, so the weeks before a bump read clean, not as a wall of false bypasses. The cost: a bypass between a bump and that first merge is not listed. Since every trailer here is attested, a one-commit web-UI squash whose commit wrote its own `Merged-by:` would also read as made through the line. §4.2 says both.
     - **Tool merges:** a PR whose review row carries a `carve_out` (a board edit's tool PR, §4.5, which `board_edit.py` commits and ShiftLead opens and merges; a ShiftLead `queue:` rank edit, §2.4) is listed apart as *a tool merge*, not as a bypass. Their merges stay ShiftLead's own call, since the PRs pass no gate. The sweep stamp and a board append are direct commits, not PRs, and stay in `--since`'s direct commits as today.
     - **Unreadable:** a merge commit this clone cannot read (not fetched, no clone) is counted as *unreadable*, never listed as a bypass.

5. **Signed forge comments are deferred.** The Fix's signature line on every comment leaves a forge record, not a git trace, so it does not serve the Why. Dropped from this design (round 3's complexity finding) and filed as TD-211.

6. **Where it lives:**
   - **cadence.md §4.2** — the ban on a written body becomes *step 5's line writes it*. The section names the trailer paragraph, what each key means, that the trailers from the gate file are attested, and that a merge with no `Merged-by:` went around the command. Its advice to put the `Co-Authored-By:` lines on the branch's first commit stays, and so do GitLab's `squash_commit_template` and `adopt_repo_settings.sh`'s setting of it: a web-UI merge still uses them.
   - **cadence.md §9.9** — the one statement of how the model and name are read, which the hook and `forge.py squash-message` share.
   - **cadence.md §7.9's list** — the new parity pair.
   - **The procedure** — step 5's two commands.
   - **`files/scripts/check_cadence.py`** — `--trailers`, and the `--since` section.
   - **`files/scripts/git-hooks/prepare-commit-msg`** — `LC_ALL=C` for the model's match (3). Under a UTF-8 locale a non-ASCII model was accepted and is now left out. The `cadence-changes.md` entry names it.
   - **`files/scripts/forge.py`** — `squash-message` (the subcommand, which merges nothing) and `squash_message(commits, trailers, …)`, the pure function under it.
   - **cadence.md §1.4** — its `gh pr merge <n> --squash` becomes step 5's line. The `gh pr view` confirm stays.
   - **`files/docs/cadence-rationale.md`** — its §1.4 snippet (around lines 28–34, `gh pr merge` and `glab mr merge`) follows §1.4's change to step 5's line, and its restatement of §4.2's *no `--body`* (around line 167) cites §4.2 instead (§7.4).
   - **This repo's own briefs and CLAUDE.md** — `docs/briefs/grinder-ac-1.md`, `manager-ac-1.md`, `techlead-context.md` and CLAUDE.md's merge line name step 5's line, with this repo's `files/scripts/` paths (a bare `scripts/forge.py` token fails the primer test). `tests/test_briefs_primer.sh` holds the primer to what exists.
   - **`files/docs/cadence-changes.md`** — one entry.
   - **ShiftLead** — its briefs' merge lines (the *A merge here is `gh pr merge <n> --squash`* line in each repo's part) move to step 5's line. That is a shiftlead entry, filed by the build, which also lists every merge ShiftLead's `ao` makes in its own code rather than through a session's command line, since `--since` would list those as bypasses. Each consumer's own brief text reaches it on its next `agent-cadence bump`.

7. **Tests:**
   - **`tests/test_forge.sh`, `squash_message`:**
     - the trailer paragraph is last, and `git interpret-trailers --parse` over the message lists every key;
     - `Co-Authored-By:` is deduplicated with case ignored, and a commit author without a trailer is added;
     - two `Agent-Model:` values are both kept;
     - the one-commit and many-commit shapes;
     - a commit body holding `---------` stays text.
   - **`tests/test_forge.sh`, `squash-message` with a `gh` shim for the reads:**
     - it writes `subject`, `body` and `sha`, and calls no merge;
     - no gate file, or no `expect` line, refuses;
     - with no `AGENT_NAME` it writes `user.name`;
     - `AGENT_MODEL_FILE` takes precedence over `AGENT_MODEL`.
   - **`tests/test_procedure_merge.sh`** (new) — step 5's line, run against a `gh` shim, passes `--squash --match-head-commit --subject --body-file` and never `--delete-branch`. The GitLab form passes `--squash --sha --squash-message`, with subject and body in the one string. A gate failure without `--unverified` reaches no merge.
   - **`tests/test_check_cadence.sh`**:
     - `--trailers` empties a pre-filled FILE on a failing PR;
     - it writes the lines and their order on a passing PR with a BLOCK then a FIXED;
     - a comment with no model gives `unknown`;
     - it is refused outside `--pr`;
     - the cutoff ignores a commit that only mentions `Merged-by:` in its text;
     - `--since` lists a squash commit with no `Merged-by:` after the cutoff. It does not list one that has the trailer, one before the cutoff, an unreadable one (counted), or a board-edit carve-out PR (listed apart).
     - On a failing PR `--trailers` writes an `unverified` file; a run that cannot read the PR leaves it empty.
     - The review row carries `carve_out` on a board-edit and a queue-edit PR.
   - **`tests/test_forge.sh`, more `squash-message` cases:**
     - a gate file for another PR is refused;
     - an `unverified` file is refused without `--unverified`, and with it writes `Merge-override:` on one line, a newline in the why collapsed;
     - a bad `AGENT_NAME`, or no name at all, refuses;
     - the trailer paragraph is the one `git interpret-trailers --parse` finds: a mixed last paragraph with a `Signed-off-by:` and a quarter trailers is parsed, one with only `Co-Authored-By:` among text lines is not, and a folded line is joined;
     - `pr_commits` is paginated and ordered, GitLab's reversed;
     - zero commits, or a list shorter than the PR's count, refuse;
     - `--unverified` with a verified gate file refuses;
     - a `Signed-off-by:` stays in its commit's text.
   - **The parity test** — the hook and `forge.py` given one environment write one model.
   - **A git round trip** — a squash commit made with the composed message reads every key back through `%(trailers:key=…)`.

## Options

- **A step in `check_cadence.py`'s exit-0 path** (the Fix's other form), which merges when the gate passes. Not chosen. It turns the reader into the actor, so `check_cadence.py --pr <n>` stops being safe to run just to look, and every reader of the cadence check would have to know it can merge. `--trailers` keeps the check a reader and hands the merge what the check read.
- **Keep GitHub's body and only append a `Merged-by:` paragraph.** Then GitHub's `Co-authored-by:` paragraph is no longer last, so those authors stop being trailers, and the `Agent-Model:` lines stay buried. Not chosen.
- **git notes.** No forge shows them, and one shared notes ref conflicts the way the one-file ledger did. Not chosen (the Fix).
- **A local squash pushed to main.** The pre-push hook and branch protection rightly block it. Not chosen (the Fix).
- **A forge account per agent,** so the forge UI itself shows the actor. It is forge-specific and costs an account each. Out of scope unless Paul asks (the Fix).
- **`forge.py merge <n>`, a command that merges** (the Fix's first form, and this plan until round 3). Not chosen (F45): it runs `gh pr merge` in a subprocess, out of sight of a guard keyed on that command line, which is how a merge is held for the person's word today. It would also have to re-read the state after a forge error, and step 5 already does that by §1.4's confirm.
- **Do nothing.** The transcript stays the only record of who merged, and on another machine there is none.

## Decision

Proposed. The shape is the 2026-10-28 Fix, whose block Paul lifted on 2026-10-30. This plan settles its open forms:
- `forge.py squash-message`, fed by `check_cadence.py --trailers`, composes; the merge stays a literal `gh pr merge` that a merge guard sees; it is not a gate step;
- the gate file and its head sha are required;
- GitHub's own trailer paragraph is replaced by the composed one;
- `Review:` and `Precheck:` are written.

The rounds run to the stop rule or the cap. The builds wait on Paul's go, as his layer's §2.4 rule holds a design's builds until its rounds converge and he says go.

## Consequences

- `git log --format='%(trailers:key=Merged-by,valueonly)'` names the merger of every cadence merge from the build on. `%(trailers:key=Agent-Model)` names every model that worked a change, and `Review:` and `Precheck:` say what the gate saw.
- A squash body is no longer the forge's to write. If a forge changes how its default body looks, nothing here breaks, but a forge without a body option cannot use the command.
- A merge through any other path is visible by what it lacks, and the weekly read (`check_cadence.py --since 7d`) lists it (4).
- Every consumer's merge line changes on its next bump. Until then its sessions merge as today.

## Revisit triggers

- A forge here that cannot take a squash message.
- A second person who merges in the forge UI, which makes a missing `Merged-by:` ambiguous.
- Per-agent forge accounts.
