# ADR 2026-11-17: a design's rounds end by a counted verdict that a judge other than the designer confirms, no build-changing fix ends them unread, and only a far-reaching design's Go is the person's

**Status:** proposed. Class: **wide** (it changes cadence.md §4.8, which every consumer runs, and a seed key of `docs/cadence.toml`), cap 6, set before round 1. Reach: **far-reaching** (it changes who gives a design's Go for the person). Shape agreed with Paul in session `td-1911` on 2026-11-17, before any review round; the rounds have not run.
**Date:** 2026-11-17
**Related:** TD-281 (this design), TD-243 (folded in: no round ends while a build-changing fix is unread), TD-249 (the synopsis, apart); ADR `2026-10-30-design-review-rounds.md` (rules 7 and 9 are what this replaces), ADR `2026-10-30-review-outcomes.md` (the review record); ShiftLead TD-1911 (its techlead is the judge, and its `design_go` setting), ShiftLead TD-1910 (the director), ledgerboard TD-132 (an answer made for the person)

## Context

- **How rounds end today** (cadence.md §4.8; ADR 2026-10-30 rules 7 and 9): by the stop rule (a round whose reviews raise nothing build-changing), at the cap, or after a bought round. Then the closing fact-check runs. The end-of-rounds item carries the evidence: how the rounds ended, the trend of build-changing findings per round, the findings no review has read, any recurring topic. It also carries the **author's** recommendation, and the author is the designer. Nothing says how to choose `Go`, `One more round` or `Hold` from that evidence.
- **That choice is being made card by card.** During ledgerboard's v3 migration (2026-11-04 to 2026-11-16), one interactive session judged about 175 end-of-rounds items. It disagreed with the item's own recommendation 41 times (23%), almost all on how a design's rounds should end, and Paul sided with it 31 times.
- **A build-changing fix can end the rounds unread** (TD-243). The cap ends them even when its last round raised a build-changing finding, and the closing fact-check's findings are *applied, never reviewed*. Seen on ShiftLead's TD-1434, TD-1437 and TD-1435 on 2026-11-06. Paul pressed `One more round` six times that day to get those fixes read, which buys a whole round when only the fixes needed reading.
- **The person's Go is all or nothing.** Paul's layer (§2.4 add) holds the builds of every design filed while its conversation is still going, which is how his designs are filed, until he says go. He wants to decide far-reaching designs (a new seat, a new flow, what every session reads) and not routine ones (*add a button that does X*). No repo can say which is which today.
- **What the review records show** (97 records with rounds and findings across ShiftLead, ledgerboard and agent-cadence, read 2026-11-17 from their main branches; 104 files, backfills left out). The counts use this plan's own definitions:
  - **Role kinds:** a role starting `fact-check` is a fact-check. One starting `design` or `review` is a design review; that includes the free-form `review` and `design and fact-check` some records carry.
  - **Round counts:** a round's count is the sum of its design reviews' build-changing findings.
  - **Recurrence:** only a design review's `reopens` row counts.
  - **Unread:** rule 1's sense.
  
  Each count applies a rule to a design's whole record, after its rounds had run to the stop rule or the cap. Applied round by round, a hold would have fired earlier on some. What the counts show:
  - 19 ended with a build-changing finding unread: raised by or after the last design review, and not rejected.
  - A design review's build-changing finding whose status holds `reopens F<n>` appeared in 2 or more rounds of 15 designs, and in 3 or more rounds of 10.
  - Build-changing findings were non-zero in the last round and fell at no step within the last 2 rounds in 10 designs, within the last 3 in 3.
  - A Hold at 2 rounds (either condition) would have held 25 of 97; at 3 rounds, 13 of 97. Paul chose 3, on a first count of 23 and 11; that count read every role's reopens and only statuses beginning `reopens`.
  - **Ledgerboard TD-132's record is one the rule at 3 holds.** Its build-changing counts per round are 7, 8, 2, 2, 2, 2, 1, 2, 1. Its design reviews raised build-changing reopens in rounds 2 to 7: six rounds, so it would have been held by round 4, before its rounds 5 to 9. On 2026-11-17 its item recommended `One more round` three times instead.
  - **Recurrence is counted only where reviews write `reopens F<n>`**, as §4.8 asks them to. Once a finding is applied, its status carries it inside its text (`applied: … (reopens F19)`), so the count reads it anywhere in the status, not only at its start.

## Options

1. **Do nothing.** The designer recommends, and the person re-judges every item. That is the 23% above, at the cost of the person's attention on every design.
2. **Write the guidance as prose, for a judge to apply.** Better, but the judgement stays felt: two judges reading the same record can differ, and nothing shows where they did.
3. **Count the verdict, and have a judge confirm it or override it in writing** (chosen). The inputs are already in the review record. A script reads them and prints the verdict. The judge's work narrows to an override with a reason, a question only the person can settle, and the design's reach.
4. **Let the script decide alone, with no judge.** Nothing would catch a design that is wrong in a way the counts do not show, or a question that is the person's to settle.

For TD-243's unread fixes: a **closing read** (one review of only the unread fixes) instead of a whole round. A whole round would cost every review re-reading the plan, for what is often one or two fixes.

For what is far-reaching: **paths alone** can be checked at merge, but miss a design whose effect is not in a file (a new default that changes who acts for the person). **Prose alone** cannot be checked. Chosen: **both**, prose for the judgement and paths as the floor the check enforces.

## Decision

Proposed. The question for Paul, after the rounds: *Should design rounds end by a counted verdict a judge confirms, with only far-reaching designs' Go coming to you?* Recommended answer: `Go`.

### 1. Read and unread

**Role kinds.** The Reviews table's role is read by its first word:
- `fact-check` (with any qualifier, such as `fact-check (closing)`) is a **fact-check**;
- `closing-read` (rule 3) is a **closing read**;
- `judge` (rule 4) is the **judge**, which raises no findings and reads nothing for rule 1;
- any other role is a **design review**: `design`, and older records' free-form roles such as `review`, `design and fact-check`, `trial` or `confirming`.

The last kind is what `read_record` does today: it reads any role but `design` and `fact-check` as `design`, with a warning. Build 2 keeps that and its warning, and adds the `closing-read` and `judge` kinds, so a `judge` row no longer inflates the design counts.

A finding is **read** once a design review or a closing read runs after it in the Reviews table's order. The table numbers reviews in the order they ran, and a round's fixes are applied before the next review reads the plan (ADR 2026-10-30 rule 1). So "read" is derived from the record and needs no status of its own. A finding is **unread** while no such review follows it. That covers:
- a round's last design review's findings, at the cap or not;
- the closing fact-check's findings;
- a closing read's own findings.

A `rejected` finding is never unread.

### 2. The verdict is counted

`review_stats.py --verdict TD-<n> [--repo PATH] [--json]` reads the design's review record and prints one verdict, with the counts behind it.

**When it runs.** It runs once the rounds end by the stop rule or the cap and the closing fact-check's fixes are applied, and again after a closing read's fixes are applied.

**The definitions** (N is `design-hold-rounds`, default 3):
- **A round's count** is the sum of the build-changing findings its design reviews raised; fact-checks are counted apart and never in it.
- **A reopen round** is a round in which a design review (never a fact-check, as §4.8's recurring topic already says) raised a build-changing finding whose status holds `reopens F<n>` anywhere in its text. The status starts `reopens F<n>` while the finding is open, and keeps it inside the text once the finding is applied or rejected (`applied: … (reopens F19)`). This is narrower than §4.8's recurring topic, which also counts a finding "following that topic's fix". That half needs judgement, so it stays with the item and the judge (rule 4), not the count.
- **Not falling** is read over the last N rounds' counts alone (N values, N−1 steps, nothing before them): within them each count is at least the one before it, and the last is non-zero. With N = 3, the last three counts 1, 1, 2 are not falling; 3, 1, 2 fall. A design with fewer than N rounds is never not falling.

The first rule that matches wins:

| Verdict | When |
|---|---|
| **Hold: split or narrow** | N or more reopen rounds, or the last N rounds' counts are not falling. |
| **One more round** | A closing read has run since the last design review, and a build-changing finding it raised, or one raised after it, is unread. |
| **Closing read** | A build-changing finding is unread, and no closing read has run since the last design review. |
| **Go** | No build-changing finding is unread. |

So a closing read runs at most once per end of rounds. If it, or anything after it, leaves a build-changing finding unread, the next verdict is `One more round`.

The counts it prints:
- each round's count, with the fact-checks' counted apart;
- the unread findings, split into build-changing and minor, each by `F<n>`;
- the reopen rounds.

`design-hold-rounds` is a new `docs/cadence.toml` key, read through `cadence_config.py` like `design-rounds` (an integer of at least 2).

### 3. The closing read (TD-243)

When the verdict is `Closing read`, one review reads only the unread build-changing fixes: the plan's diff since the review that raised them, with the findings those fixes answer.
- It is a row of the Reviews table with the role `closing-read`, under the last round. It does not count against the cap, as fact-checks do not.
- It runs after the closing fact-check, so it reads that check's fixes too.
- It runs at most once per end of rounds. If it raises a build-changing finding, that finding is unread, and the verdict becomes `One more round` (rule 2's order).
- Within the cap, `One more round` runs without asking anyone. Past the cap, it is the end-of-rounds item, to the person, whatever the design's reach.

### 4. The judge

The judge is a seat independent of the design: never the designer's session, and never one of the design's own reviews. In ShiftLead that is the techlead (ShiftLead TD-1911). Elsewhere it is a fresh agent, run the way the PR review is (§4.9). The judge is given:
- the plan;
- the review record;
- the verdict's output;
- §4.8's definition of far-reaching, and the repo's `[far-reaching]` paths and note (rule 5).

The judge returns three things:
- **The verdict confirmed, or overridden with a reason.**
- **Hold and raise**, where a question only the person can settle remains (scope, product, cost). It goes to the person, or to whoever the repo's rules say answers for them.
- **The reach**: the designer's mark checked, raised to far-reaching if the judge disagrees, never lowered.

The record gets a Reviews row with the role `judge`. The header gets `Verdict:` (the counted verdict, the judge's, and an override's reason) and `Reach:`.

### 5. Reach and `[far-reaching]`

**The definition** (cadence.md §4.8, for every repo): a design is **far-reaching** when it changes any of these:
- what every session reads (roles, briefs, the spec, the glossary);
- who acts or decides for the person;
- what waits for the person;
- something that cannot be undone.

Anything else is **routine**. Any doubt counts as far-reaching.

**The mark.** Before round 1 the designer marks Reach, with a reason, beside the class. It goes in the plan's Status line and in the record's header as `Reach: routine | far-reaching — <reason>`. Reach is not the class. Class is about the cap: a change another repo or a consumer runs. Reach is about who gives the Go. A wide design can be routine, and an in-repo one far-reaching.

**The paths.** A repo names what is far-reaching in `docs/cadence.toml`, read by a new `cadence_config.far_reaching()`:

    [far-reaching]
    paths = ["docs/briefs/**", "docs/glossary.md"]   # globs, fnmatch on the repo-relative path, as [precheck-paths]
    note = "anything that changes the org schema or a seat's powers"   # optional: the repo's own prose, printed to the judge

The globs match as `[precheck-paths]`' do: fnmatch on the repo-relative path, with `*` crossing `/`, so `**` matches as `*` does. The table is a list and a string, not `[precheck-paths]`' map of globs to commands. `cadence_config.check()` refuses an unknown table or key today, so `[far-reaching]` and `design-hold-rounds` are added to what it accepts, each with its own `--check` errors: a `paths` that is not a list of strings, an unknown key in the table, and a `design-hold-rounds` under 2.

A design is far-reaching whatever its mark if any of its builds' `Location:` names a path one of these globs matches. With no `[far-reaching]` table, only the definition applies, and the check in rule 7 finds nothing.

### 6. Who gives the Go

| The design | What happens |
|---|---|
| Far-reaching | The end-of-rounds item goes to the person, carrying the verdict and the judge's reading as its recommendation. |
| Routine, verdict `Go` | No item. The builds are filed under §4.8's "with no item" path, and the record says `Go by: <judge>`. |
| Routine, verdict `Hold: split or narrow` | No item. The designer revises as the judge's reason says, and the revision starts its own count against the cap (as `Hold` does today). |
| Any, *Hold and raise*, or `One more round` past the cap | The item goes to the person. |

The header gets `Go by: <person> | <judge seat> | pending`. `Decided:` keeps its date, the `Go`'s.

**A repo's or a person's own rules that require the person's Go still raise the item.** §4.8 says "a repo whose own rules require the person's go on a plan" today. This design widens that to the person's layer (§9.18), which binds the sessions of every repo the person works in. Paul's layer (§2.4 add) does so for every design whose conversation is still going when it is filed, and changing it is his own edit, not this design's. Separately, a judge lifting a gate written for the person (`decision (paul)`) is answering for the person, which no check accepts until ledgerboard TD-132 builds a recorded delegated answer. Until then, a routine design that carries such a gate still reaches the person.

### 7. The backstop at merge

`check_cadence.py` gets a `reach` row, one of the structural rows (as `person` is). It works in four steps:
1. **The PR's entries.** It finds the entries the PR names, as the `ledger` row does.
2. **Each entry's design.** It reads each entry's `Part of:` at the base, through ledgerboard's `parse_part_of`; `check_cadence.py` reads no `Part of:` today.
3. **Each design's record.** It reads `docs/reviews/TD-<design>.md` at the base.
4. **The paths.** It reads the `[far-reaching]` globs from the base tree (`_DocsTree` at the base, never the PR, so a PR cannot change the check it is judged by), and matches the PR's changed files against them.

On an open PR it **fails** when the PR changes a far-reaching path and a design it builds has a `Go by:` that is not the person. It is **unknown**, naming the design, when that design has no record or its record has no `Go by:`. It is `na` when:
- no far-reaching path changes;
- the PR names no entry;
- no entry it names is `Part of:` a design. §4.11 already holds behaviour changes for the person.

On a fail the person reads and merges the PR, as the `person` row has them do for their own paths. Merged, a fail is a pass with a ⚠, as `row_person` does (a sweep never fails history). The row is a detector, like every row (§7).

### 8. The end-of-rounds item

The item keeps what it carries today. It adds:
- the verdict line, counted and judged, with an override's reason;
- the reach;
- the unread findings split into build-changing and minor.

When no build-changing fix is unread, it says *every build-changing fix has been read by a review*; otherwise it names each unread one by its `F<n>` (TD-243's line). The recommendation is the judge's, not the author's.

### Open for the rounds

- **agent-cadence's own `[far-reaching]` paths.** Every payload change reaches every consumer, so the question is how much of it Paul decides. Proposed: `files/docs/cadence.md`, `files/docs/procedures/**` and the seeds. The scripts that carry those rules out are routine, unless the definition catches them.
- **Whether the verdict should run after every round from round `design-hold-rounds` on**, so a Hold ends the rounds early instead of at the stop rule or the cap. That would save the rounds the data's caveat counts. Proposed: yes, for Hold alone.
- **Which model runs the closing read.** Proposed: `review-model`'s last (in ShiftLead, the stronger), since it reads only a few fixes.
- **TD-249's synopsis.** The item would link it once TD-249 lands. Nothing here waits on it.

## Consequences

- **The builds** (each `Part of: TD-281`; a session files them after the Go):
  1. **The docs:**
     - cadence.md §4.8: the definition, the verdict, the closing read, the judge, Reach, the item;
     - §9.18's list of `docs/cadence.toml` keys, which `tests/test_cadence_config.sh` tests 10 and 10b hold to the seed;
     - the Adoption checklist's step 10, which names the design-rounds keys;
     - the procedure, `files/docs/procedures/cadence.md` step 3;
     - the adr-template's record comment: the role cell becomes `fact-check | design | closing-read | judge`, plus the `Reach:`, `Verdict:` and `Go by:` header lines;
     - the seed `files/docs/cadence.toml`: a commented `design-hold-rounds` and `[far-reaching]`;
     - a `files/docs/cadence-changes.md` line.
  2. **The scripts behind the verdict:**
     - `cadence_config.py`: `design-hold-rounds`, and `far_reaching()` with `check()`'s errors, with tests;
     - `review_stats.py`: `read_record` reads the role kinds of rule 1 in place of folding every other role into `design`, and `--verdict` is added, with fixtures for each verdict, each role kind, and a `rejected` finding.
  3. **The `reach` row:** `check_cadence.py`'s new row, with tests for each state: open and merged, globs read from the base, no entry, no design, no record.
  4. agent-cadence's own `[far-reaching]` in `docs/cadence.toml`, from the open question above.
- **This supersedes** ADR 2026-10-30-design-review-rounds rule 7 (how the rounds end: no build-changing fix ends them unread) and rule 9 (the end-of-rounds item: when it is raised and whose recommendation it carries). On the Go, that ADR's Status line gets the clause *rules 7 and 9 superseded by ADR 2026-11-17-design-round-endings.md*.
- **TD-243 is covered** by rules 1, 3 and 8. It is archived when build 1 merges, its Log naming this design.
- **ShiftLead** is told the number, so that TD-1911 (the techlead as judge, `design_go`) mirrors it after its next pin bump.
- **What gets harder:** a design records two more header lines and one more review row. A judge must be run, and that costs one agent read per design.
- **Out of bounds:** the designer recommending its own design's end. A routine Go reaching the person when no rule asks for it.

## Revisit triggers

- The judge overrides the counted verdict on more than 1 design in 5 over a month: the counts are missing something.
- A defect escapes (`Escaped from:`, §2.13) from a routine design that the judge gave its Go: the definition or the paths are too narrow.
- Paul answers `Hold` or `One more round` on far-reaching items the verdict called `Go`, more than rarely.
