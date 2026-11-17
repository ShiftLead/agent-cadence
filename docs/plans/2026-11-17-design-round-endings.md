# ADR 2026-11-17: a design's rounds end by a counted verdict that a judge other than the designer confirms or raises, no build-changing fix ends them unread, and a routine design's Go need not be the person's

**Status:** proposed. Class: **wide** (it changes cadence.md §4.8, which every consumer runs, and a seed key of `docs/cadence.toml`), cap 6, set before round 1. Reach: **far-reaching** (it changes who gives a design's Go for the person). Shape agreed with Paul in session `td-1911` on 2026-11-17, before any review round; he narrowed the judge and moved the merge-time check out in round 3. The rounds are running: the record is `docs/reviews/TD-281.md`.
**Date:** 2026-11-17
**Related:** TD-281 (this design), TD-243 (folded in: no round ends while a build-changing fix is unread), TD-249 (the synopsis, apart); ADR `2026-10-30-design-review-rounds.md` (rules 7 and 9 are what this replaces), ADR `2026-10-30-review-outcomes.md` (the review record); ShiftLead TD-1911 (its techlead is the judge, and its `design_go` setting), ShiftLead TD-1910 (the director), ledgerboard TD-132 (an answer made for the person)

## Context

- **How rounds end today** (cadence.md §4.8; ADR 2026-10-30 rules 7 and 9): by the stop rule (a round whose reviews raise nothing build-changing), at the cap, or after a bought round. Then the closing fact-check runs. The end-of-rounds item carries the evidence: how the rounds ended, the trend of build-changing findings per round, the findings no review has read, any recurring topic. It also carries the **author's** recommendation, and the author is the designer. Nothing says how to choose `Go`, `One more round` or `Hold` from that evidence.
- **That choice is being made card by card.** During ledgerboard's v3 migration (2026-11-04 to 2026-11-16), one interactive session judged about 175 end-of-rounds items. It disagreed with the item's own recommendation 41 times (23%), almost all on how a design's rounds should end, and Paul sided with it 31 times.
- **A build-changing fix can end the rounds unread** (TD-243). The cap ends them even when its last round raised a build-changing finding, and the closing fact-check's findings are *applied, never reviewed*. Seen on ShiftLead's TD-1434, TD-1437 and TD-1435 on 2026-11-06. Paul pressed `One more round` six times that day to get those fixes read, which buys a whole round when only the fixes needed reading.
- **The person's Go is all or nothing.** Paul's layer (§2.4 add) holds the builds of every design filed while its conversation is still going, which is how his designs are filed, until he says go. He wants to decide far-reaching designs (a new seat, a new flow, what every session reads) and not routine ones (*add a button that does X*). No repo can say which is which today.
- **What the review records show** (97 records with rounds and findings across ShiftLead, ledgerboard and agent-cadence, read 2026-11-17 from their main branches; 104 files, backfills left out). The counts use this plan's own definitions:
  - **Role kinds:** rule 1's. A role whose first word is `fact-check` is a fact-check; `judge` and `closing-read` are their own kinds (no record has them yet); any other role is a design review. That last kind includes the free-form `review`, `design and fact-check`, `trial` and `confirming` some records carry.
  - **Round counts:** a round's count is the sum of its design reviews' build-changing findings.
  - **Recurrence:** only a design review's `reopens` row counts.
  - **Unread:** rule 1's sense.
  
  Each count applies a rule to a design's whole record, after its rounds had run to the stop rule or the cap. Applied round by round, a hold would have fired earlier on some. What the counts show:
  - 20 ended with a build-changing finding unread: raised by or after the last design review, rejected findings included (rule 1).
  - A design review's build-changing finding whose status holds `reopens F<n>` appeared in 2 or more rounds of 15 designs, and in 3 or more rounds of 10.
  - Build-changing findings were non-zero in the last round and fell at no step within the last 2 rounds in 10 designs, within the last 3 in 3.
  - A Hold at 2 rounds (either condition) would have held 25 of 97; at 3 rounds, 13 of 97. Paul chose 3, on a first count of 23 and 11; that count read every role's reopens and only statuses beginning `reopens`.
  - **Ledgerboard TD-132's record is one the rule at 3 holds.** Its build-changing counts per round are 7, 8, 2, 2, 2, 2, 1, 2, 1. Its design reviews raised build-changing reopens in rounds 2 to 7: six rounds. With the verdict run after every round for Hold (rule 2), it would have held the design after round 4, before its rounds 5 to 9. On 2026-11-17 its item recommended `One more round` three times instead.
  - **Recurrence is counted only where reviews write `reopens F<n>`**, as §4.8 asks them to. Once a finding is applied, its status carries it inside its text (`applied: … (reopens F19)`), so the count reads it anywhere in the status, not only at its start.

## Options

1. **Do nothing.** The designer recommends, and the person re-judges every item. That is the 23% above, at the cost of the person's attention on every design.
2. **Write the guidance as prose, for a judge to apply.** Better, but the judgement stays felt: two judges reading the same record can differ, and nothing shows where they did.
3. **Count the verdict, and have a judge confirm it or send it to the person with a reason** (chosen). The inputs are already in the review record. A script reads them and prints the verdict. The judge's work narrows to agreeing, raising what the counts miss (a disagreement, a weak rejection, an untagged recurrence, a question only the person can settle), and the design's reach. An earlier draft let the judge override the verdict toward caution; its rules for which outcome wins kept failing review, and Paul chose the narrower judge on 2026-11-17.
4. **Let the script decide alone, with no judge.** Nothing would catch a design that is wrong in a way the counts do not show, or a question that is the person's to settle.

For TD-243's unread fixes: a **closing read** (one review of only the unread fixes) instead of a whole round. A whole round would cost every review re-reading the plan, for what is often one or two fixes.

For what is far-reaching: **paths alone** can be checked at merge, but miss a design whose effect is not in a file (a new default that changes who acts for the person). **Prose alone** cannot be checked. Chosen: **both**, prose for the judgement and paths as the floor the check enforces.

## Decision

Proposed. The question for Paul, after the rounds: *Should design rounds end by a counted verdict a judge confirms or raises, with a routine design's Go no longer coming to you once its gate can be lifted for you?* Recommended answer: `Go`.

### 1. Read and unread

**Role kinds.** The Reviews table's role is read by its first word:
- `fact-check` (with any qualifier, such as `fact-check (closing)`) is a **fact-check**;
- `closing-read` (rule 3) is a **closing read**;
- `judge` (rule 4) is the **judge**, which raises no findings and reads nothing for rule 1;
- any other role is a **design review**: `design`, and older records' free-form roles such as `review`, `design and fact-check`, `trial` or `confirming`.

This changes `review_stats.py`. Today `read_record` reads any role other than exactly `design` or `fact-check` as `design`, with a warning. That includes `fact-check (closing)` and `fact-check (re-check)`, so today's counts take a qualified fact-check's findings as a design review's. Build 2 makes `read_record` read the first word as above:
- the four kinds;
- a warning kept for every role other than exactly `design`, `fact-check`, `closing-read` or `judge`.

So a qualified fact-check counts as a fact-check, and a `judge` row inflates no design count.

A finding is **read** once a design review or a closing read runs after it in the Reviews table's order. The table numbers reviews in the order they ran, and a round's fixes are applied before the next review reads the plan (ADR 2026-10-30 rule 1). So "read" is derived from the record and needs no status of its own. A finding is **unread** while no such review follows it. That covers:
- a round's last design review's findings, at the cap or not;
- the closing fact-check's findings;
- a closing read's own findings.

**A rejected finding follows the same rule.** A build-changing finding the designer rejected is unread until a later review has read the plan and the findings table with the rejection in it. So a rejection alone never spares a design a closing read, and the closing read reads the rejection's reason.

**Since the last Hold.** A `Hold` revision keeps the record's numbering (ADR 2026-10-30) and starts its own count against the cap. The record's header lists the round of every Hold, `Holds: 4, 9` (none: `Holds: none`), whoever gave it: the judge on a routine design, or the person's `Hold: <note>` answer to an item. A person's `Hold: <note>` is given in the last round the Reviews table holds. Rules 2 and 9 count only the rounds after the last round that line names; until a later round is recorded, `--verdict` prints `next: revise` (rule 9). With a Hold at round 4, round 5 is the revision's first round: its reopen rounds, its not-falling window and its cap all start there, and rounds 1 to 4 count for nothing. A finding a revision round raises that `reopens` a finding from before the Hold still makes a reopen round. Reopen rounds are counted over the whole window since the last Hold, not the last N rounds alone: a design that reopened findings in three rounds is held even if its latest round is clean, since its rounds have shown the same concern returning.

**A round the person bought.** When the person answers `One more round` on an item, the round it buys ends the rounds after it, and the item comes back to them (§4.8: "then asks again"). The header records it: `Bought: 7` (none: `Bought: none`) names the last round the Reviews table held when the answer came, so **round 8 is the bought round**; with several, `Bought: 7, 12`, the last one counts. A bought round counts toward the cap like any other. The Hold rule needs no restart for it: a bought round always ends at the item, so the count never runs on past it. No record has a `Bought:` line yet, so the Context's counts are unchanged by it.

**A finding the person raises** (`person` in its `by` cell) belongs to no review. It is never unread and is in no round's count.

### 2. The verdict is counted

`review_stats.py --verdict TD-<n> [--repo PATH] [--json]` reads the design's review record and prints one verdict, the counts behind it, and a last line `next: <step>` naming the next step in rule 9's table (`hold`, `end` and `continue` are step 1's three outcomes). It knows the cap, `design-rounds` or `design-rounds-wide` by the record's `Class:`, read through `cadence_config.py`. The rounds since the last Hold, bought rounds included, are **past the cap** when they number at least the cap: with a cap of 6, a `One more round` after round 6 since the last Hold is past it, and after round 5 within it. It counts rounds, for the cap and for the Hold rule, since the last Hold (rule 1). `--after-round` checks the Hold rule and whether the rounds have ended, and prints `next: hold`, `next: end` or `next: continue`. It prints `end` when the round just run raised no build-changing finding (the stop rule), when the rounds since the last Hold number at least the cap, or when it was the bought round, and `continue` only otherwise; a bought round that also trips the Hold rule prints `next: end` (both lead to step 2, and the item then recommends `Hold`). Rule 9 says when each form runs.

**The definitions** (N is `design-hold-rounds`, default 3):
- **A round's count** is the sum of the build-changing findings its design reviews raised; fact-checks are counted apart and never in it.
- **A reopen round** is a round in which a design review (never a fact-check, as §4.8's recurring topic already says) raised a build-changing finding whose status holds `reopens F<n>` anywhere in its text. The status starts `reopens F<n>` while the finding is open, and keeps it inside the text once the finding is applied or rejected (`applied: … (reopens F19)`). This is narrower than §4.8's recurring topic, which also counts a finding "following that topic's fix". That half needs judgement, so it stays with the item and the judge (rule 4), not the count.
- **Not falling** is read over the last N rounds' counts alone (N values, N−1 steps, nothing before them): within them each count is at least the one before it, and the last is non-zero. With N = 3, the last three counts 1, 1, 2 are not falling; 3, 1, 2 fall. A design with fewer than N rounds is never not falling.

The first rule that matches wins:

| Verdict | When |
|---|---|
| **Hold: split or narrow** | Counted since the last Hold (rule 1): N or more reopen rounds, or the last N rounds' counts are not falling. |
| **One more round** | A closing read has run since the last design review, and a build-changing finding is unread (one the closing read raised). |
| **Closing read** | A build-changing finding is unread, and no closing read has run since the last design review. |
| **Go** | No build-changing finding is unread. |

So a closing read runs at most once per end of rounds. If it raises a build-changing finding, the next verdict is `One more round`.

`One more round` arises only when the rounds have ended (by the stop rule, or at the cap), a closing read has run, and a build-changing finding it raised is unread. That round counts toward the cap. It ends as any round does, and a new end of rounds may run a new closing read. A closing read's own fixes are not fact-checked: if they are build-changing, the next round's opening fact-check reads them; if they are minor, they are applied unreviewed, as the closing fact-check's minor findings are today.

The counts it prints:
- each round's count, with the fact-checks' counted apart;
- the unread findings, split into build-changing and minor, each by `F<n>`;
- the reopen rounds.

`design-hold-rounds` is a new `docs/cadence.toml` key, read through `cadence_config.py` like `design-rounds` (an integer of at least 2).

### 3. The closing read (TD-243)

When the verdict is `Closing read`, one review reads only the unread build-changing findings. For an applied finding it reads the plan's diff since the review that raised it, with the finding. For a rejected one, which has no diff, it reads the rejection's reason and the plan text the finding concerns.
- It is a row of the Reviews table with the role `closing-read`, under the last round, its model the one that ran it. It does not count against the cap, as fact-checks do not.
- It runs after the closing fact-check, so it reads that check's fixes too.
- It runs at most once per end of rounds. If it raises a build-changing finding, that finding is unread, and the verdict becomes `One more round` (rule 2's order).
- It runs on `review-model`'s last model (in ShiftLead, the stronger), since it reads only a few fixes.
- Within the cap, `One more round` runs without asking anyone. Past the cap, it is the end-of-rounds item, to the person, whatever the design's reach. After a bought round no closing read runs: the item goes to the person (rule 9), listing the unread findings, and the person chooses whether another round reads them.

### 4. The judge

The judge is independent of the design: never the designer's session, and never one of the design's own reviews. By default it is a fresh agent on `review-model`'s last model. The session that ran the rounds launches it with the **fixed judge prompt** in the procedure (`files/docs/procedures/cadence.md` step 3), filling in only the paths; the session never words the question. A repo's own rules (its AGENTS.md or CLAUDE.md) may name a seat to judge in its place, as ShiftLead's TD-1911 will name its techlead.

**The judge never changes the verdict** (Paul, 2026-11-17). It confirms the counted verdict, or it sends the design to the person with its reason. Only the person, answering the item, chooses another outcome.

**When it runs.** On a counted `Go` or `Hold` (rule 9), after the closing fact-check, except after a bought round, when the item goes to the person with no judge. `Closing read` and `One more round` need no judge: within the cap the round runs, and past it the item goes to the person.

**What it is given:**
- the plan;
- the review record;
- the verdict's output;
- §4.8's definition of far-reaching, and the repo's `[far-reaching]` paths and note (rule 5).

**What it returns:**
- **`CONFIRM`**: it agrees with the counted verdict.
- **`RAISE`, with one sentence of reason**: the item goes to the person. It raises when:
  - it disagrees with the counted verdict, either way;
  - a rejected build-changing finding's reason does not hold up;
  - it sees a recurrence the reviews did not tag: a later build-changing finding reopening an earlier one on the same topic (the findings table's `topic` column), with no `reopens` written;
  - a question only the person can settle remains (scope, product, cost);
  - the rounds ended at the cap with its last round still raising build-changing findings, which today always reaches the person.
- **The reach**: its own reading, from the definition and the paths matched against the files the plan says its builds change. The designer's mark stays in `Reach:`; the judge's reading is in its line. **The design is far-reaching if either says so**, so the judge can raise the reach and never lower it.

**Its reply ends with one fixed line**, read as the `cadence-review:` line is:

    cadence-judge: CONFIRM | RAISE · reach <routine|far-reaching> · <one sentence of reason>

The session records the line verbatim in the header's `Verdict:`, after the counted verdict it judged and the judge's `R<n>` (`Verdict: Go (R12) · cadence-judge: CONFIRM · reach routine · …`). Its Reviews row is under the last round, its model the one that ran it, or `?` for a seat whose model is not reported. A seat that judges (ShiftLead's techlead) sends the same line to the session in its reply, so the session that ran the rounds writes the judge's line too.

**The record.** Every completed judge run is a Reviews row with the role `judge`. Unlike other reviews, a judge run may not be discarded: the record's rule that an aborted or discarded review gets no row covers only an aborted judge run. **One judge run per verdict.** A second judge run on the same verdict, with no other row (a design review, a closing read or a fact-check) between, is not a fresh opinion to choose from: `--verdict` reads two `judge` rows after the last other row (a design review, a closing read or a fact-check) as `next: item`, and the item goes to the person.

**`reopens` is the reviewer's word, not the designer's.** The procedure's review prompt asks each design review to name a finding it reopens by its id, as §4.8 does today. The designer copies that into the status and keeps it there when the finding is applied or rejected. The judge's look for untagged recurrence is the check on that copy.

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

At the judge's run (rule 4), a design is far-reaching whatever its mark if a file the plan says its builds change matches one of these globs. The builds do not exist yet then, so their `Location:` lines cannot be read; a check after the fact, on each build's PR, is a later entry's (rule 7). With no `[far-reaching]` table, only the definition applies.

### 6. Who gives the Go

| The verdict, the judge's line, and the design | What happens |
|---|---|
| The rounds ended after a bought round, any verdict | The item goes to the person, as §4.8 says ("then asks again"): they bought the round and are asked again whatever it found. It recommends `Go` on a counted `Go`, `Hold` on a counted `Hold`, and `One more round` on a counted `Closing read`, since a closing read is not an answer the person can give and a round reads the unread fixes. Read first. |
| Two or more `judge` rows after the last other row (a design review, a closing read or a fact-check), any reach | The item goes to the person; its recommendation is the counted verdict. Read next. |
| `One more round` within the cap, any reach | The round runs; no judge and no item. Rounds within the cap never asked the person, and still do not. |
| `One more round` past the cap | The item goes to the person. |
| `RAISE`, any reach | The item goes to the person, with the judge's reason; its recommendation is the counted verdict. |
| `CONFIRM`, far-reaching | The item goes to the person, carrying the confirmed verdict as its recommendation. |
| `CONFIRM` on `Go`, routine, and the design's entry carries no `decision (<person>)` gate | No item. The builds are filed under §4.8's "with no item" path. The record says `Go by: judge` (or `judge (<seat>)` where a seat judged), and the design entry's Log gets a line saying so through `ledger.py note`. |
| `CONFIRM` on `Go`, routine, and the entry carries such a gate | The item goes to the person, carrying the confirmed `Go` as its recommendation. |
| `CONFIRM` on `Hold`, routine, and `Holds:` names no earlier round | No item. The designer revises (split or narrow, as the reviews' findings show), and the revision starts its own count (rule 1, *Since the last Hold*). |
| `CONFIRM` on `Hold`, routine, and `Holds:` names an earlier round | The item goes to the person. Two Holds mean the design keeps failing the same way, which is the person's to judge. |

The header gets `Go by: judge | judge (<seat>) | <person> | pending`, written `pending` when the record is first written; anything but the two judge forms and `pending` is a person's name, as the board's `People:` line spells it. It also gets `Holds:`, the rounds of the Holds (rule 1); a round is named once however many Holds it saw, and their count is the number of rounds it names. `Decided:` keeps its date, the `Go`'s.

**What holds a design for the person is its gate.** A repo's or a person's rule that requires the person's Go works by putting `Blocked by: decision (<person>)` on the design's entry, as Paul's layer (§2.4 add) does, so the table reads the entry, not prose.

**This rule is a floor for repos, and the person's to lower** (Paul, 2026-11-17). By default every far-reaching design reaches the person. A repo's rules may send more to the person (every design, say), never fewer. The person's own layer may send fewer for themselves, since it is their attention: ShiftLead's `design_go: techlead` (TD-1911) is such a choice, made by the person.

**A repo's or a person's own rules that require the person's Go still raise the item.** §4.8 says "a repo whose own rules require the person's go on a plan" today. This design widens that to the person's layer (§9.18), which binds the sessions of every repo the person works in. Paul's layer (§2.4 add) does so for every design whose conversation is still going when it is filed, and changing it is his own edit, not this design's. Separately, a judge lifting a gate written for the person (`decision (paul)`) is answering for the person, which no check accepts until ledgerboard TD-132 builds a recorded delegated answer. Until then, a routine design that carries such a gate still reaches the person. Once TD-132 lands, the judge's lift is recorded as made for the person, and only where a delegation the board declares covers it.

**So the routine path reaches Paul only once two things outside this design land:** his own layer edit (§2.4 add), and ledgerboard TD-132. Almost every design he files carries the gate. Until both land, this design still changes what his items say (the counted verdict, the judge's reading, the closing read), not how many reach him.

### 7. The backstop at merge (a later entry)

A cadence-check row that holds a far-reaching build for the person at merge, when its design's Go was not theirs, is its own entry, filed after this design's Go (Paul, 2026-11-17). Nothing in rules 1 to 6 or 9 depends on it. Its Fix carries what these rounds found about it:
- the globs read from the base tree, never the PR;
- builds in the same repo only, since `Part of:` never names another repo (§2.4);
- the person read from the board's `People:` line, and what to do with no board or no such line;
- a record with no `Reach:` line predates this design and is not checked.

### 8. The end-of-rounds item

The item keeps what it carries today. It adds:
- the counted verdict, with the judge's `CONFIRM` or `RAISE` (and its reason) where a judge ran;
- the reach: far-reaching if the designer's mark or the judge's reading says so, with both shown;
- the unread findings split into build-changing and minor.

When no build-changing fix is unread, it says *every build-changing fix has been read by a review*; otherwise it names each unread one by its `F<n>` (TD-243's line). The recommendation is the counted verdict, confirmed or raised by the judge, never the author's, except after a bought round, where rule 6's first row gives it.

### 9. The ending, step by step

The session that ran the rounds does every step below and writes every line it names. **The design stops at the item** (Paul, 2026-11-17): the person's answer to it is handled as §4.8 handles it today, by the session that acts on it (§3.5), with one line added to the record (*After the item*, below). `review_stats.py --verdict` prints the next step as its last line, so a session in any repo follows the script, not its memory.

| # | When | The session does | It writes |
|---|---|---|---|
| 1 | After each round's last review is recorded | `--verdict --after-round` (its Hold check counts only from the Nth round since the last Hold) | nothing; on `next: hold` go to 2, on `next: end` go to 2 (the stop rule, the cap, or a bought round has ended the rounds; a bought round, the one after the last round `Bought:` names, ends them as §4.8 says today); on `next: continue` run the next round |
| 2 | Step 1 printed `next: hold` or `next: end` | the closing fact-check, fix-then-check | its rows and fixes, as §4.8 |
| 3 | After 2, 4 and 5 | `--verdict` | nothing |
| 4 | `next: closing-read` | the closing read (rule 3) | its row, findings and fixes; then 3 |
| 5 | `next: judge` (a counted `Go` or `Hold` that no judge's line applies to) | the judge (rule 4) | its row and `Verdict:`; then 3 |
| 6 | `next: go` | files the builds, unblocked, putting the fixes no review has read into the Fix of the build each concerns (*fixed, not reviewed; the builder checks it*), as §4.8's "with no item" path does | `Go by: judge` (or `judge (<seat>)`), `Decided:`, a Log line on the design's entry (`ledger.py note`) |
| 7 | `next: item` | raises the end-of-rounds item (rule 8), naming its gate and the builds it holds as §4.8 does: the builds are filed held, each `Part of:` the design, the first time an item is raised for it, whatever the item recommends (on a `Hold`, they are brought into line when the next item is raised, by the later-item rule below); a later item for the same design files none twice: the session first brings the filed builds into line with the design as it now stands (revising, adding or closing them, as §4.8's "write a new one listing every held build" allows), and the item lists every held build in its `Parts:`. If the design's entry has no `decision (<person>)` gate, it first adds one, naming the person §4.8's item names today (one the board's `People:` line holds), with an `**Ask:**` (one plain question of one sentence, at most 25 words, ending in `?`, §2.3) through `ledger.py set --blocked-by … --ask`, passing the entry's existing blockers with the gate, since `--blocked-by` replaces the field | the gate if missing, the held builds, then the board item, through `board_edit.py add` |
| 8 | `next: revise` | revises the design, as the findings show | the Hold's round in `Holds:` (the last round the Reviews table holds, as for a person's Hold); the revision's first round opens with its fact-check |
| 9 | `next: round` | runs one more round | its rows; then 1 |

**After the item.** The person answers as §4.8 has them answer today, and the session that acts on the answer (§3.5) does what §4.8 says today for that answer. It adds one line to the record, so the count can read the answer:
- on `Go`: `Go by: <person>` (the name the board's `Decided:` line carries) and `Decided:`;
- on `One more round`: the last round the Reviews table holds, in `Bought:`;
- on `Hold: <note>`: the last round the Reviews table holds, in `Holds:`.

The session then runs the round (as step 9 runs one) or the revision (as step 8 does, opening with its fact-check), and step 1 follows the round's last review.

**What `--verdict` prints at 3.** First, if the rounds ended after a bought round (the last round in the Reviews table is the one after the last round `Bought:` names), it prints `next: item` whatever the counted verdict: no closing read and no judge run, as §4.8 asks the person again after the round they bought, and the item carries the unread findings, and recommends as rule 6's first row says. Otherwise, with a counted `Closing read`, `next: closing-read`. With `One more round`, `next: round` within the cap and `next: item` past it. With a `Go` or `Hold`, it first counts the `judge` rows after the last other row (a design review, a closing read or a fact-check): two or more print `next: item`, whatever any line says (rule 4, *One judge run per verdict*). Otherwise it reads the header's `Verdict:`. A judge's line there applies when no other row (a design review, a closing read or a fact-check) has been recorded since the judge's row and the counted verdict is the one it judged. If none applies, it prints `next: judge`. If one does, it prints the outcome by rule 6's table: `go`, `item` or `revise`. **While `Holds:` names the last round in the Reviews table**, the revision has not yet recorded a round, so there is nothing to count: `--verdict` prints `next: revise` before any other test, an exception to rule 1's count, until a later round is recorded. So a rerun between step 8 and the revision's first round prints `revise` again. A judge row whose reply has no valid `cadence-judge:` line is a spent run: the next judge row makes two, and the item follows. To choose among them it reads the design entry's `Blocked by:` (through the module's `ledger_entries()`), the header's `Holds:`, and the reach: far-reaching if the header's `Reach:` mark or the `reach` token of the judge's line in `Verdict:` says so (the judge's reading includes rule 5's path match).

A Hold found at 1 reaches 3 as a Hold again: the Hold rule comes first in rule 2's table, and the closing fact-check cannot undo a reopen. So a mid-round Hold's order is the closing fact-check, then the judge, then the item or the revision, except after a bought round, where the item follows the closing fact-check with no judge.

### Open for the rounds

- **TD-249's synopsis.** The item would link it once TD-249 lands. Nothing here waits on it.

## Consequences

- **The builds** (each `Part of: TD-281`; a session files them after the Go):
  1. **The docs:**
     - cadence.md §4.8: the definition, the verdict, the closing read, the judge, Reach, the item;
     - §9.18's list of `docs/cadence.toml` keys, which `tests/test_cadence_config.sh` tests 10 and 10b hold to the seed;
     - the Adoption checklist's step 10, which names the design-rounds keys;
     - the procedure, `files/docs/procedures/cadence.md` step 3: rule 9's steps, the fixed judge prompt with its `cadence-judge:` line, and the review prompt's ask to name each reopened finding by its id;
     - the adr-template's record comment: the role cell becomes `fact-check | design | closing-read | judge`, plus the `Reach:`, `Verdict:`, `Go by:`, `Holds:` and `Bought:` header lines, and `person` in a finding's `by` cell for one the person raises;
     - the seed `files/docs/cadence.toml`: a commented `design-hold-rounds` and `[far-reaching]`;
     - a `files/docs/cadence-changes.md` line.
  2. **The scripts behind the verdict:**
     - `cadence_config.py`: `design-hold-rounds`, and `far_reaching()` with `check()`'s errors, with tests;
     - `review_stats.py`: `HEADER_RE` reads the new header lines (`Reach:`, `Verdict:` with its judge's line and its `reach` token, `Go by:`, `Holds:`, `Bought:`); `read_record` reads rule 1's role kinds by first word, as rule 1 says, and accepts a finding whose `by` is `person`; `to_row`'s per-round line, which today counts any role but `design` as a fact-check, counts closing reads and judge rows under keys of their own (`closing_reads`, `judges`); the trial reads design rows only and is unchanged; the per-round aggregate (a list) and the per-design table read that line's keys and show the two new ones as figures, and columns, of their own; the token totals keep summing every row, judge and closing-read rows included, a seat's `?` counted as unknown as today; and the findings' topic and status columns (`reopens F<n>`), where it reads only the id, the round's reviewer and the class today; and `--verdict` is added (rounds counted since the last Hold, the cap read from the record's `Class:`, `--after-round` with its `hold`, `end` and `continue`, the `next:` line of rule 9 including `item` after a bought round, and a warning on a `Go by:` whose first word is `judge` with no `judge` row), with fixtures for each verdict, each role kind, two judge rows on one verdict, a finding whose `by` is `person`, a rejected finding, a Hold revision, a person's Hold, a bought round (and the rounds ending after it, with a counted `Go`, a counted `Hold`, and a counted `Closing read`), two bought rounds (`Bought: 7, 12`), a bought round that also trips the Hold rule (`--after-round` prints `next: end`), a clean round and a cap round (`next: end`), a round within the cap that raised a build-changing finding (`next: continue`), a Hold from `--after-round` (`next: hold`, and `hold` over `end` when a clean round or a cap round also trips the Hold rule), no Hold check before the Nth round since the last Hold, a rerun after step 8, a judge row with no valid line, `Holds: none`, the cap at 5 and at 6 rounds of 6, a bought round counted toward the cap, and the cap counted from a Hold (a Hold at round 4 of a cap of 6, so round 10 is past it).
  3. agent-cadence's own `[far-reaching]` in `docs/cadence.toml` (Paul, 2026-11-17). Every payload change reaches every consumer, and he decides these:
     - `files/docs/cadence.md`, `files/docs/procedures/**` and the seeds;
     - the scripts that decide whose Go counts, by the definition's "who acts or decides for the person": `files/scripts/check_cadence.py`, `files/scripts/review_stats.py` and `files/scripts/cadence_config.py`.
- **This supersedes** ADR 2026-10-30-design-review-rounds rule 7 (how the rounds end: no build-changing fix ends them unread) and rule 9 (the end-of-rounds item: when it is raised and whose recommendation it carries). On the Go, that ADR's Status line gets the clause *rules 7 and 9 superseded by ADR 2026-11-17-design-round-endings.md*.
- **The merge-time check** (rule 7) is filed as its own entry after the Go, by the session that files the builds.
- **TD-243 is covered** by rules 1, 3 and 8. It is archived when build 1 merges, its Log naming this design.
- **ShiftLead** is told this design's entry, TD-281, so that TD-1911 (the techlead as judge, through ShiftLead's own rules; `design_go`, the person's choice under rule 6's floor) mirrors it after its next pin bump. TD-1911's Fix is reworded after the Go: its techlead judges by `CONFIRM` or `RAISE`, not by choosing among four answers. Its current last bullet says ShiftLead's `[far-reaching]` globs go in "agent-cadence's `docs/cadence.toml`"; the rewording puts them in ShiftLead's own.
- **What gets harder:** a design records five more header lines and a judge row per ending verdict. A judge must be run, and that costs one agent read per ending verdict. A routine Go is seen only in the record and the entry's Log, not on the board.
- **Out of bounds:** the designer recommending its own design's end. A routine Go reaching the person when no rule asks for it.

## Revisit triggers

- The judge raises on more than 1 design in 5 over a month for a disagreement with the counted verdict: the counts are missing something.
- A defect escapes (`Escaped from:`, §2.13) from a routine design that the judge gave its Go: the definition or the paths are too narrow.
- Paul answers `Hold` or `One more round` on far-reaching items the verdict called `Go`, more than rarely.
