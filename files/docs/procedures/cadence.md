<!-- SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/docs/procedures/cadence.md
     Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR. -->

# Cadence — check a PR against cadence.md §1–§5 before merging

Thin wrapper around `scripts/check_cadence.py` — never reimplement its rows here. The script
is a **detector, not a gate** (cadence §7): nothing stops a merge that skipped it, and
that is deliberate — a gate that gets bypassed disables itself. The backstop is
the stranded-work sweep ([stranded-work.md](stranded-work.md)), which runs the same script over the week's merges (`--since 7d`), so a
skipped check is found, not prevented.

**Running it (TD-093):** this file is the procedure, and any agent runs it by reading it and following it. Claude Code also has it as a skill — `/cadence`, `/cadence <n>` or `/cadence week` — whose `SKILL.md` only points here, and so do Codex (`$cadence`) and Gemini CLI, from the same pointer under `.agents/skills/` (TD-127); a tool with no skills needs nothing installed. Asked about a PR number, check that PR; asked about the week, run `--since 7d`; otherwise the current branch's PR.

## Steps

The commands are GitHub's (`gh`), with GitLab's (`glab`, a PR is a merge request, `!N`) beside them (cadence.md, *Forges*). The script asks through `scripts/forge.py`, which has a GitHub and a GitLab backend (TD-104): on any other forge its PR rows say *PRs not checked* (TD-098), and a GitHub or GitLab under another host name sets `forge = "github"` or `"gitlab"` in `docs/cadence.toml` (cadence.md §9.18). On GitLab the `ci` row reads the pipelines on the head commit, and one that failed with no jobs (it never ran) is *unknown*, not red. On GitHub a job Actions refused to start (*The job was not started because recent account payments have failed or your spending limit…* — the account's billing, the person's to fix) is reported as a failure; the row reads that run's annotation and says *unknown*, naming the reason, not red (TD-115). **On an open PR whose base branch requires checks** (GitHub's branch protection or a ruleset's *required status checks*, TD-178) the row judges those and the `cadence/precheck` status only, as ShiftLead's `done --pr` does: a required check that never reported is *unknown*, and a run nothing requires that failed or still runs is named after the verdict, never in it. With nothing required — a private repo on a plan with neither feature among them — or on GitLab, every run is judged; a required set that cannot be read is *unknown*. A merged PR is judged on every run.

**No forge** (`forge = "none"` in `docs/cadence.toml`, cadence.md §4.9, TD-105): there is no PR, so `--pr` exits 2. Run the review the same way, put the `cadence-review:` line (step 3's form) in the squash commit's body, and land it on the default branch; `python3 scripts/check_cadence.py --since 7d` then reads every commit from git, and a commit with neither that line nor a carve-out fails.

1. Find the PR: the current branch's (`gh pr view --json number`; GitLab: `glab mr view -F json`, its `iid`), or the number you were
   given. The week means `--since 7d` (report only; the precheck and steps 3–5 do not apply); its
   **Direct commits** section lists what reached main with no PR — only §4's carve-outs pass.
2. **The repo's precheck (TD-117, cadence §4.12):** when `python3 scripts/cadence_config.py get precheck`
   prints a command, run `python3 scripts/precheck.py --pr <n>` first, on every head you mean to merge.
   It runs that command in a clean worktree at the PR's head and records a `cadence/precheck`
   commit status there (no CI minutes); exit 1 is a failed check — fix it, push, run it again;
   3 is a pass the forge would not record, which the `ci` row cannot see — say in the PR that
   it passed and on what. GitHub and GitLab both record it (GitLab since TD-118). **Right after a
   push, pass `--expect "$(git rev-parse HEAD)"`** (TD-186): the forge names the new head seconds
   later, and without it a precheck in the same breath tests the previous head. Without it, it
   still waits up to 30s while origin's branch is ahead of the PR's head, then exits 2 naming both shas; its last lines
   name the full sha it tested — read it.
   Then run `python3 scripts/check_cadence.py --pr <n>` and read every row. Exit 0 = every row
   pass or n/a; 1 = a fail; 2 = nothing could be checked (no forge CLI such as `gh`, a CLI error, no PR);
   3 = no fail, but a row is `unknown` — evidence the forge could not give (CI still running, every
   check skipped, a deleted head's check runs, a rate limit, a precheck required and not recorded on
   the head). Say so, never call it a pass; a CI still running is waited on as step 5 says.
3. **`review` fails and no review has been done:** do it now — an independent agent on the
   repo's review model (`python3 scripts/cadence_config.py get review-model`; default
   `sonnet`, cadence §9.18), started however your tool starts another agent on a chosen
   model (a subagent, or a separate session) and never the session that wrote the diff, reviews the diff for correctness (code) or fact-checks it
   against the repo (docs). **Where it reads, and what it re-derives (cadence §4.8, TD-136):** it reads
   refs (`git show`/`git diff` on the head commit) or its own detached worktree pinned to the head,
   never your tree or the anchor, and compares against the base in its own worktree, never by stash
   or checkout — and you leave its tree alone until it reports; the prompt names the change's
   load-bearing claims, marks which figures are unchecked, and asks for each to be re-derived and
   its premise tested, not only the diff read; with more than one reviewer model, one round at a
   time, cheaper first, each round's fixes committed before the next. **Its prompt names the verdict words:** *end your report with
   `cadence-review: <SHIP|FIXED|BLOCK> · <your model> · <code|docs> · <n> findings` — SHIP,
   FIXED or BLOCK and no other word*. A reviewer asked in its own words writes its own
   (`CLEAN`), which the row never reads as a review: it fails naming the word, and the cure is a
   new comment (TD-116). **One round for a change that adds no mechanism and alters no rule**
   (a wording, a constant, a comment, a rename); iterated rounds are for a new or changed mechanism
   or rule (cadence §4.8, TD-123). Fix the findings, re-verify, and then post the evidence comment (§4; on GitLab the same body through `glab mr note <n> -m`, which glab 1.123 marks deprecated but runs; a fine-grained token needs the notes permissions):

   ```
   gh pr comment <n> --body "$(cat <<'MSG'
   cadence-review: FIXED · sonnet · code · 3 findings
   - <finding 1 and what changed>
   - ...
   MSG
   )"
   ```

   (GitLab: `glab mr note <n> -m "…"`, the same body.) First line exactly in that shape — `SHIP` (nothing to change), `FIXED` (findings fixed
   before merge), or `BLOCK` (do not merge) — then `<reviewer model>` (the model that actually reviewed), `<code|docs>`,
   `<n> findings`, separated by ` · `. Findings in prose below. **Never edit the comment
   afterwards** (an edit after the merge fails the row: the forge stamps `updated_at`). Post a
   new comment if there is more to say. The script's `REVIEW_RE` reads this line — the two
   are a parity pair (cadence §7): change the shape in both or in neither. It reads it on
   any line of the comment, the last if several (TD-087), so a report that ends with its
   verdict still counts — but write it first.
4. **Any other row fails:** fix the cause, not the row — a `ledger` fail means the TD named
   in the title needs its status line or archive move in this PR (§2), or — when it says *bad
   field(s)* — that an entry this PR added or changed has a field the reader rejects: run
   `python3 scripts/ledger.py --check --since origin/<default>` and fix what it prints (§2.12); `pushed` means
   commits exist only on this machine (§3); `worktree` after a merge means scratch or
   unlanded commits are sitting in the worktree (§1); `base` means the PR targets a branch
   other than the default — retarget it (`gh api -X PATCH repos/{owner}/{repo}/pulls/<n> -f base=main` — not
   `gh pr edit --base`, which fails on gh 2.46, TD-143; GitLab: `glab mr update <n> --target-branch main`)
   before deleting the old base, which would close the PR for good — or, for a stack you
   meant, add a `cadence-stack: <why>` line to the PR body (§1).
5. Merge only on exit 0 (`gh pr merge <n> --squash` — no `--delete-branch` from a worktree,
   cadence §1.4; GitLab: `glab mr merge <n> --squash`). Exit 3 is *look*, not *merge*: wait for a running CI and re-run.
   **The wait is one background command, never a poll in the turn (TD-180):** where ShiftLead's `ao` is on PATH,
   `ao pr wait <n> && python3 scripts/check_cadence.py --pr <n>` — it folds the PR's checks into one word and names a
   *conflicting* PR, which runs no checks and which `gh pr checks` prints nothing for (a nonzero exit is
   that word — conflicting, failing, none — to read and act on, never to re-run blind); elsewhere (no ShiftLead, a cloud
   session) the forge's own wait, `gh pr checks <n> --watch` (GitLab: `glab ci status --wait` on the branch; in the
   cloud, the forge's MCP tools), then the check. `ao` is optional: the cadence never requires it.
   A `ci` row that says *too early to call it no CI* or *CI is starting* is the minute after a
   push, before the workflow has registered its run — wait as above, then re-run; it clears by itself. For an
   unknown that will not clear (a rate limit, a workflow that skips everything), find out
   why before merging and say in the PR what you found. Then re-run with `--pr <n>` once merged if you want the record: the `pr`,
   `review` (created and last edited before the merge) and `worktree` (gone or reapable)
   rows change meaning after the merge.

## What the rows prove, and what they don't

`review` is self-attested: the session that ran the review posted the comment. Green means
the ritual was recorded. An orchestrator that nudges or escalates on this check, and a sweep
that reports a clean week, should say "recorded", not "verified". `pr`'s squash is inferred
from the merge commit having one parent, read from git when this clone holds it (TD-103) — GitHub records no merge method. `deploy` runs the
consumer's own `scripts/cadence_deploy_check.sh <pr> <sha>` if one exists (exit 0 pass,
1 fail, 2 n/a; cadence §5, *adapt per repo*) and is n/a otherwise; where `origin/<default>` has changed the hook since this checkout branched from it
and the copy here is missing or different, it is `unknown` — pull (or rebase) and re-run.

`review` names the **first** `cadence-review:` comment as the review. A later one — your own
`FIXED · <model>` follow-up, before the merge — is listed after it and decides only a standing `BLOCK`.

**A PR that merged with no review** fails `review` for good: do the review now, post the
comment as usual with `(post-merge)` after the findings count, and re-run. The row still says
FAIL, now `acknowledged` (`"acknowledged": true` in `--json`; the run's `"acknowledged"` list
names the PRs with no other fail; a late `BLOCK` is a plain fail — act on it). That is the end state — do not edit or re-post, and do not
treat an acknowledged fail as a second offence.
