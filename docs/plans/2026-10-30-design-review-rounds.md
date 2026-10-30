# ADR 2026-10-30: design review rounds have a cap per class, a stop rule, a findings record and one end-of-rounds item when needed

**Status:** decided 2026-10-30 by Paul ("go"; six rounds of review, Sonnet and Fable, the record below)
**Date:** 2026-10-30
**Related:** TD-203 (the build), TD-123, TD-136, TD-173 (the 11-review run this learns from); `docs/review-data/` (the data and the trial)

How the rounds ran (revision 19): Class: in-repo (cap 4), set before round 1; under 2 as widened in round 5 (F83) it would have been wide (cap 6), and it is not reclassed. Paul's answers: after round 2, drop `Simplify`/`Rethink`, one end-of-rounds item, `Hold` hands him the plan; after round 4 (at the cap, with *closing fact-check* recurring), `One more round` ("this design affects how all of our reviews are run"); after round 5, the item only when needed (F84, option a) and a short review of rule 9 (round 6, applied in revision 18); after round 6 and the trial, `Go`.

## Context

- **TD-203** (agent-cadence, open, `Blocked by: decision (Paul)`) makes `review-model` an ordered list and adds `fact-check-model`. This plan adds the rest of the configuration for *design* review rounds to it.
- **Design review rounds** are reviews of a plan before anything is built. They are separate from the review every PR gets before merge (cadence.md §4.8, which keeps its one-round default for a change that adds no mechanism, TD-123). Today cadence.md says how iterated rounds are ordered ("one at a time, cheaper first", §4.8) but not how many to run, when to stop, or what to do when they don't converge. The practice so far is "iterate until READY", uncapped.
- **The data** (the first pass, PR #25; PR #27 extends it to 97 designs and supersedes these figures in `docs/review-data/design-rounds.md`, with the same picture: in-repo median 4 rounds, 54 of 83 within 4) was gathered 2026-10-30 from 50 designs on this machine, most from ShiftLead's `docs/design-history.md`:
  - **In-repo (39 designs, all uncapped):** the median was 4 rounds (range 2–10); 12 finished within 3 rounds, 20 within 4 and 33 within 6. The median last review with 3 or more findings was review 6 (round 3); later reviews mostly held 1–3 findings, labelled "follow-ons of the last adoption". 6 had a later design gap filed (one of them questionable). None is shown to be catchable by another round; three (TD-947, TD-1051, TD-995) look catchable by a careful enumeration of cases. So under a cap of 4, about half of in-repo designs would reach the cap: the at-cap path is a common one, and must cost the person little.
  - **Wide (11 records; 9 with a review count, 8 with a round count):** the median was about 3.75 rounds. The one built after 2 rounds (the predecessor repo's pinned-not-synced plan, kept in the private dev-cadence repo) needed 4 fixes within days; ledger-ids (5 reviews, rounds not recorded) was later redesigned (TD-188), though the data marks that as driven by use. TD-173's ledger writer ran 11 reviews (5.5 rounds); its build-changing findings were 0, ~6, 3, 3, 2, 2, 1–2, 1, 1, 1, 0 per review, and review 10's (the edit actions' output form) would, by the 2026-10-30 post-mortem's judgement, have needed a ledgerboard re-release had it been missed (the tool's own writes would have failed its gate). This rests on about three designs. None of the 6 in-repo gaps is shown to be catchable by the cap or the stop rule (round 5, Sonnet; three look catchable by a careful enumeration), and the wide cap of 6 is a guess (and the data's wide class predates round 5's widening to payload changes, F83, so its medians were not re-cut): the wide failures came from short runs, and a cap is a ceiling, not a floor.
- **A pattern Paul has seen:** rounds that keep going back and forth on one point, which turned out to mean the design was wrong. TD-173 had a mild case: by the round reports (session `sl-tds`, not the plan's summarised record), the archived `Resolved` form came back in reviews 3, 7, 8 and 9 (header or body; a second line after reopen; a header field; reopen destroying it), each fix correct, each spawning the next.
- **The trial (2026-10-30, after round 6)** replayed revision 18's rules over 86 designs of a 97-design extension of the data (`docs/review-data/`, `trial-rev18.md`), with total findings standing in for build-changing ones, which overcounts. In-repo with a cap of 4: the stop rule ends 49% (27% on the strict proxy), the person is asked on 36% (53%), and 29% (22%) of reviews are saved, almost all in a few long loops; a cap of 5 asks on 22%, 6 on 12%. The cap-4 item would have reached 4 of the 7 in-repo designs that later broke (two or three plausibly surfaceable); a wide cap of 6 never binds on this history. On this machine Paul's layer rule asks him on every plan regardless.

## Design

**1. A round is one pass through `review-model`.** With `review-model = "sonnet, fable"` a round is two reviews; with three models, three; with one model, one. A cap is in rounds whatever the list's length, so no model in the list is used fewer times than another. The defaults were fitted to two-model rounds; a repo with a one-model list may raise the keys. The reviews in a round run one at a time in list order, and each review's fixes are applied before the next review reads the plan, so a later model reviews the earlier one's fixes (§4.8's "one at a time").

**2. Two keys, read through `cadence_config.py` (§9.18):**
- `design-rounds` (default `4`): the most rounds for an **in-repo** design.
- `design-rounds-wide` (default `6`): the most rounds for a **wide** design.

A **wide** design is one that is costly to fix after it ships: it changes another repo, what consumers run from the cadence payload (its rules, procedures or scripts, reaching them at their next bump), a vendored or published format (ledgerboard), or something that cannot be undone (a repo made public, a history rewrite). Anything else is in-repo. The author states the class and its reason in the plan's Status line before round 1, and it does not change.

**3. Fact-checks.** `fact-check-model` (TD-203; it falls back to the first `review-model`) checks the plan's claims against the code: at the start of round 1 over the whole plan, at the start of each later round over **only what changed** since the last fact-check (a fact verified once stays verified), and once more, a **closing fact-check**, over the last round's changes after the last round's fixes and before 9's item is raised, however the rounds end. Every fact-check repeats, fix then check, until it raises nothing, and is not one of the reviews a round counts. The closing fact-check's findings are applied, never reviewed, and go into 9's item when one is raised (otherwise into the build entries, 9); when one changes the design itself, the author recommends `One more round`.

**4. Design reviews read the whole plan every round.** A problem between two older parts of a plan, untouched by the latest revision, is only seen by a whole read (TD-173's review 10 was one).

**5. Each finding is labelled by whoever raises it** (a review or a fact-check) `build-changing` or `minor`, and the label stands. The test: would two builders reading the plan as written build different things, or would something the plan states be false or broken? Yes is `build-changing` (an undefined behaviour, a contradiction, a data-loss case, a false claim the design relies on); anything else is `minor`.

**6. The findings record** is the plan's *Findings record* table: id `F<n>`, round (an integer; the closing fact-check's findings are filed under the last round), by (the review or fact-check that raised it), topic, finding, class (its label) and a status: `applied`, `rejected: <why>`, `open`, or, on a new row raising an earlier finding again, `reopens F<n>`, each optionally followed by a parenthetical saying where, with a short note. Every finding gets a row, minor ones too: they carry the why, and a later review can reopen them. Every reviewer is given the record and names a finding it reopens by its id. The **topic** names the mechanism a finding touches, in a phrase (*the archived `Resolved` form*), never a whole numbered rule.

**7. How the rounds end.** A round's fixes are applied before anything else happens. The rounds end by the **stop rule** (after a round whose reviews raise no build-changing finding, the cap's last round included), at the **cap** (after the last round it allows, when that round's reviews raised a build-changing finding), or after the extra round a `One more round` answer buys. Then the closing fact-check (3) runs.

**8. A recurring topic** is one where, in two or more rounds, a review (never a fact-check) raised a build-changing finding that reopens an earlier one or follows a fix of that topic made in an earlier round. Successive findings that refine a mechanism without undoing an earlier fix do not count. It does not end the rounds; the author names it in 9's item with the question *is this the wrong design?*

**9. The end-of-rounds item.** The person gets one board `decide` item for the plan when the rounds end:
- at the cap, or after a bought round;
- with a recurring topic;
- with a build-changing finding from the closing fact-check;
- or in a repo whose own rules require the person's go on a plan.

(Plan note, not for cadence.md: on this machine Paul's §2.4 layer rule is such a rule, so here every plan gets the item.)

Otherwise (a convergence with none of those) there is no item: the fixes no review has read go into the Fix of the build entry each concerns ("fixed, not reviewed; the builder checks it"), and the session that ran the rounds files the builds.

The item carries how the rounds ended; the trend (build-changing findings per round from reviews, the fact-checks' shown separately); the findings whose fixes no review has read (the last review's and the closing fact-check's); any recurring topic, with its findings, the positions taken and *is this the wrong design?*; the author's recommendation; and `Answers:` `Go`, `One more round` and `Hold: <note>`, the recommended answer first and marked ` (default)` (§3.5). While it is open the plan's entry carries `Blocked by: decision (<person>)` (from its filing, where the repo's rules block a plan from the start) with an `**Ask:**` line holding the plan's go question (§2.3), no build is filed unblocked, and the item is escalated by §3.3 like any other.

**The answers:**
- **`Go`:** the person's go on the builds; the unreviewed fixes go into the build entries' Fix as above, and the PR that records the answer drops the `Blocked by` line.
- **`One more round`:** one more round runs, past the cap if it is reached (only the person can choose it), and then the item again.
- **`Hold: <note>`:** the person takes the plan. The item closes; the entry keeps the block, and the PR that records the answer rewrites its `**Ask:**` to carry the note, so the person can pick it up cold, in a session of their own, when they choose. A new revision written then keeps the record's numbering and starts its own count against the cap.

The plan's Status says how the rounds ended, the trend and any answers.

**10. Where it lives:**
- cadence.md §4.8 gains a *Design review rounds* paragraph (1–9) and names the keys; §9.18 lists the keys and defaults; the Adoption checklist step 10 names them.
- `cadence_config.py` gains the two keys in `KEYS` and in `COUNT_KEYS` (whole numbers, as `sweep-every` is); the seed `files/docs/cadence.toml` gains their commented lines, which `tests/test_cadence_config.sh` holds to `KEYS` and §9.18.
- `files/docs/procedures/cadence.md`'s review step names the rounds for a plan.
- `files/docs/adr-template.md` gains an optional *Review record* section with the findings table.
- `files/docs/cadence-changes.md` gets one entry.
- ShiftLead (its techlead review and TD-857's fact-checker seat read these keys): a shiftlead entry, filed once the shape is agreed.

**11. Tests:** in `tests/test_cadence_config.sh`, both keys `get` their defaults and a repo file's value; a non-integer or zero value is a `--check` error naming the key; the parity check covers the seed's two new lines. The rules in 1–9 are prose for sessions; nothing in this plan is enforced by a check.

## Options

- **Uncapped, "iterate until READY"** (the practice the data records): no limit on cost, and nothing tells a session a design is not converging.
- **One cap for every design:** simpler, but a cross-repo or payload change costs far more to fix after it ships (TD-173's writer is vendored by two repos), and the data's wide designs that stopped early needed follow-up fixes.
- **A sticking point that ends the rounds** (revisions 6–16): it cost about ten patch findings in this plan's own run, never ended a round alone, and the one outside case it would have caught (TD-173's `Resolved` form) was a design that was right. Kept only as a named recurring topic.
- **An end-of-rounds item at every end** (revisions 8–16): a new person-facing gate on every design in every repo; replaced by the item only when needed (F84).

## Decision

Paul, 2026-10-30, after the end-of-rounds item: `Go`, with the defaults 4 (in-repo) and 6 (wide). The findings record now labels every finding, so new plans produce real build-changing counts: rerun `docs/review-data/trial_rules.py` against them after about ten plans and retune the defaults.

## Consequences

- Every design plan carries a findings table, so later data passes need no parsing and the build-changing labels the trial lacked accumulate.
- Most in-repo plans end by the stop rule without asking anyone; the cap sends the rest to the person. On a machine whose own rules require a go on every plan (Paul's), the person still sees every plan.
- **Revisit** the defaults after about ten plans run under these rules (rerun `trial_rules.py` with real labels), and the wide cap once a wide design reaches it.

## Open questions for the rounds

1. ~~Should the fact-check count?~~ Sonnet (round 1): keep it outside the count; it is a different job, and its model may not be in the list. Adopted in 3.
2. ~~Twice or once?~~ Sonnet: twice, for both classes; a single reopen is ordinary. The weakness was the trigger's definition (F13, then F23), now fixed. Adopted.
3. ~~One at-cap item for both classes?~~ Paul (2026-10-30): "unified item for both"; after round 5 the item is raised only when needed (9, F84).
4. ~~Machine-readable record?~~ Sonnet: yes, cheaply: the class is exactly `build-changing` or `minor`, the status one of the four forms, id and round integers; no script required now. Adopted in 6.

## Review record

Each review gets this table and names an earlier finding it reopens by its id ("reopens F2") instead of raising it again in new words.

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | fact-check (sonnet) | where it lives | the seed `files/docs/cadence.toml`, `COUNT_KEYS` and the parity test `tests/test_cadence_config.sh` (KEYS, seed and §9.18 name the same keys and defaults) were missing from §10 | build-changing | applied |
| F2 | 1 | fact-check | sticking point | "a sticking point twice" was undefined: which events count, and whether in different rounds | build-changing | applied (8 rewritten) |
| F3 | 1 | fact-check | stop rule | the last round's fixes were never fact-checked; undefined which round a start-of-round fact-check finding counts toward | build-changing | applied (3, 7) |
| F4 | 1 | fact-check | data claims | "none looks catchable by another round" overstated the data: three are marked plausibly catchable by a careful enumeration | build-changing | applied (9 and Context reworded; the in-repo cap no longer rests on it) |
| F5 | 1 | fact-check | tests | `--check` reports problems only; the no-argument form lists keys | minor | applied (11) |
| F6 | 1 | fact-check | data claims | TD-173's per-review sequence was misquoted | minor | applied |
| F7 | 1 | fact-check | data claims | the `Resolved` recurrence is not in the plan's review record | minor | applied (sourced to the round reports) |
| F8 | 1 | fact-check | data claims | the wide follow-up-defect claim was thinner than stated, and "9 designs" vs 11 records | minor | applied |
| F9 | 1 | fact-check | person's go | Paul's §2.4 layer rule vs "the cap ends the rounds" | minor | applied (9) |
| F10 | 1 | fact-check | wording | id and section names inconsistent | minor | applied |
| F11 | 1 | sonnet | stop rule | a closing fact-check that finds something opens a "round" that 1 defines as a full model pass, and its own fix is never checked | build-changing | applied (3, 7) |
| F12 | 1 | sonnet | build-changing call | every incentive favours calling a finding minor; "polish" is no test | build-changing | applied (5; the author downgrade later cut, F27) |
| F13 | 1 | sonnet | sticking point | author-assigned topics can be split to dodge the trigger; "same topic" is a judgement; consecutive rounds unstated | build-changing | applied (6, 8) |
| F14 | 1 | sonnet | sticking point | a pause with no answer has no rule for unattended teams | minor | applied (9) |
| F15 | 1 | sonnet | fact-check count | single-model list, and the fact-check model also in the list, unstated; defaults fitted to two-model rounds | build-changing | applied (1, 3) |
| F16 | 1 | sonnet | cap | no extend path for in-repo; reclassing mid-way and extensions undefined; reclassing as a way around the cap | build-changing | applied (2; reclassing later cut, F24) |
| F17 | 1 | sonnet | at the cap | a plan with no build entry has nowhere to put open findings | minor | applied (9) |
| F18 | 1 | sonnet | defaults | about half of in-repo designs would reach cap 4, so the at-cap path is the common one and must be cheap | minor | applied (Context, 9) |
| F19 | 1 | sonnet | at the cap | in-repo at the cap sends even a data-loss finding to an fyi | build-changing | applied (9) |
| F20 | 1 | fable | at-cap item | 5 and 9 contradicted: nearly every build-changing finding is an undefined behaviour, so the in-repo exception swallowed the in-repo rule; with the strict label test the cap, not the stop rule, will usually end the rounds | build-changing | applied (9 unified; Paul agreed) |
| F21 | 1 | fable | closing fact-check | no fact-check checks the cap round's fixes; a design-changing correction at the cap is undefined | build-changing | applied (3, 9) |
| F22 | 1 | fable | at-cap item | a sticking point found at the cap makes two decide items; after Simplify nothing says whether a round follows | build-changing | applied (9) |
| F23 | 1 | fable | sticking trigger | numbered-rule topics make successive refinements a sticking point, firing on most designs; minor reopens counted | build-changing | applied (6, 8) |
| F24 | 1 | fable | reclass | the reclass rules cover an edge nobody needs | minor | applied (2: the class does not change) |
| F25 | 1 | fable | closing fact-check | opening and closing fact-checks had different shapes | minor | applied (3, 7) |
| F26 | 1 | fable | findings record | no place for a downgrade; which row says reopened; no Status form for the cap | minor | applied (6, 9) |
| F27 | 1 | fable | complexity | about 25 obligations and three item shapes; cut the reclass rules, the in-repo exception and fyi, the author downgrade, the fact-check asymmetry, the two-checker clause | minor | applied |
| F28 | 2 | fact-check (sonnet) | closing fact-check | what follows the uncounted Simplify round was undefined | build-changing | applied (9) |
| F29 | 2 | fact-check (sonnet) | at-cap item | no Answers line for the sticking item or a merged item (§3.5 requires one) | build-changing | applied (9) |
| F30 | 2 | fact-check (sonnet) | sticking point | who drops the decision line; an escalated item; a plan with no entry | minor | applied (9) |
| F31 | 2 | fact-check (sonnet) | findings record | the record's own rows broke the fixed forms; no form for a withdrawn label | minor | applied (6) |
| F32 | 2 | fact-check (sonnet) | person's go | F9 stale; whether Go is the layer rule's go | minor | applied (9) |
| F33 | 2 | fact-check (sonnet) | closing fact-check | "decides nothing" overstated; the person's end lacked a closing check | minor | applied (3, 7) |
| F34 | 2 | fact-check (sonnet) | complexity | a remnant of the cut clause in 3; F11's citation | minor | applied (3) |
| F35 | 2 | sonnet | sticking point | an answer did not clear the topic's events; Go/Keep had two outcomes in one clause | build-changing | applied (8, 9) |
| F36 | 2 | sonnet | at-cap item | the cap round's own findings: applied or left open was undefined | build-changing | applied (9) |
| F37 | 2 | sonnet | at-cap item | the uncounted round after Simplify was undefined in number and cap arithmetic | build-changing | applied (9; Simplify dropped, F46) |
| F38 | 2 | sonnet | at-cap item | the at-cap item did not block the builds | build-changing | applied (9: one pause rule for any item) |
| F39 | 2 | sonnet | at-cap item | a dead clause (a cap reached while paused); a merged item had no Keep | minor | applied (9) |
| F40 | 2 | sonnet | closing fact-check | a closing correction after a converged cap round contradicted 3 and 9; Status written too early | build-changing | applied (7, 9) |
| F41 | 2 | sonnet | sticking point | the Status line omitted F28's event | minor | applied (Status) |
| F42 | 2 | sonnet | sticking point | when the author checks, and whether the round's second review runs | minor | applied (8: once per round, after all reviews) |
| F43 | 2 | fable | at-cap item | 8 and 9 are two items with two lifecycles joined by clauses; one end-of-rounds item, raised however the rounds end, removes them | minor | applied (7, 8, 9; with Paul's cuts) |
| F44 | 2 | fable | at-cap item | under a sticking pause, whether the round's fixes are applied first was undefined | build-changing | applied (7) |
| F45 | 2 | fable | person's go | on convergence nothing said whether builds unblock; the payload cited a personal layer rule | build-changing | applied (9: the item is the go request at every end) |
| F46 | 2 | fable | at-cap item | Simplify at the cap buys one round and re-asks the person | minor | rejected: Simplify dropped (Paul) |
| F47 | 2 | fable | findings record | F19's and F29's statuses carried text outside the fixed forms | minor | reopens F31 |
| F48 | 2 | fable | closing fact-check | when the closing check runs, said three ways | minor | applied (3, 7) |
| F49 | 2 | fable | at-cap item | Hold at the cap could never resume under a spent count | build-changing | applied (9: the session ends the hold) |
| F50 | 3 | fact-check (sonnet) | at-cap item | the Answers line had no order or default (§3.5) | build-changing | applied (9) |
| F51 | 3 | fact-check (sonnet) | sticking point | sticking events never cleared, so One more round would end at once | build-changing | reopens F35 |
| F52 | 3 | fact-check (sonnet) | at-cap item | the blocked entry had no Ask line (§2.3) | minor | applied (9) |
| F53 | 3 | fact-check (sonnet) | at-cap item | a reminder note is not an Ask; the PR that writes it unnamed | minor | applied (9) |
| F54 | 3 | fact-check (sonnet) | person's go | the block runs from filing under the layer rule, not only while the item is open | minor | applied (9) |
| F55 | 3 | fact-check (sonnet) | findings record | stale fix locations; four forms vs five | minor | applied (record) |
| F56 | 3 | fact-check (sonnet) | at-cap item | a Status form claimed an ending under One more round | minor | applied (9) |
| F57 | 3 | sonnet | at-cap item | with every fix applied first, the item had no "open findings"; the residue is the last round's unreviewed fixes | build-changing | applied (9) |
| F58 | 3 | sonnet | Hold resume | resuming with a new revision was undefined: numbering, the cap count, the first fact-check | build-changing | applied (9) |
| F59 | 3 | sonnet | closing fact-check | a closing correction under the cap ran a round even after a sticking-point end | build-changing | applied (3) |
| F60 | 3 | sonnet | at-cap item | Hold on a plan with no entry had nowhere to go | minor | applied (9) |
| F61 | 3 | sonnet | wording | the Status line named the wrong revision | minor | applied (Status) |
| F62 | 3 | sonnet | complexity | five Status forms can be one pattern; the resume list can go | minor | applied (9) |
| F63 | 3 | fable | at-cap item | the build block lapsed under Hold ("while the item is open") | build-changing | applied (9) |
| F64 | 3 | fable | at-cap item | One more round "counted" vs the cap as a maximum | minor | applied (9) |
| F65 | 3 | fable | stop rule | 7's list of endings missed the round One more round buys | minor | applied (7) |
| F66 | 3 | fable | Hold resume | the resume outcomes listed two ways; "end the rounds" undefined | minor | applied (9) |
| F67 | 3 | fable | at-cap item | Go dropped the closing fact-check's findings | minor | applied (9) |
| F68 | 3 | fable | sticking point | "the person's last answer" needed to include a decision recorded in Status | minor | applied (8; the clause later cut, F100) |
| F69 | 3 | fable | person's go | the Ask at filing named an item that did not exist yet | minor | applied (9) |
| F70 | 4 | fact-check (sonnet) | closing fact-check | "under the cap" was ambiguous at the cap's last round: a round past the cap only the person may buy | build-changing | applied (3) |
| F71 | 4 | fact-check (sonnet) | Status forms | ended-by and the extra-round ending had no Status form | minor | applied (9; the forms later cut, F77) |
| F72 | 4 | fact-check (sonnet) | at-cap item | Go's "those findings" pointed at the wrong antecedent; the closing check's findings are fixed in no round | minor | applied (9) |
| F73 | 4 | fact-check (sonnet) | findings record | parentheticals carry notes, not only where | minor | applied (6: a short note allowed) |
| F74 | 4 | sonnet | closing fact-check | rules 3 and 8 disagreed on whether fact-check findings are sticking events | build-changing | reopens F59 |
| F75 | 4 | sonnet | closing fact-check | the design-changing-correction branch is the wrong shape: closing findings always go into the item | minor | applied (3: the branch cut) |
| F76 | 4 | sonnet | the round's reviews | whether a round's second review reads the first's fixes | minor | applied (1: it does) |
| F77 | 4 | sonnet | Status forms | the Status grammar is more than anything reads; the Status line was a changelog | minor | applied (9; history moved to the record) |
| F78 | 4 | fable | sticking point | closing fact-check is a sticking point (F59, F74), coinciding with the cap; the record and Status said only the cap | minor | applied (record, Status) |
| F79 | 4 | fable | the unreviewed residue | after F76 the residue is the last review's findings and the closing check's, not the last round's | minor | applied (9) |
| F80 | 4 | fable | start-of-round fact-check | "since the previous revision" skips the earlier review's fixes; "since the last fact-check" | minor | applied (3) |
| F81 | 4 | fable | findings record | F71's forms were later cut | minor | applied (record) |
| F82 | 4 | fact-check (sonnet) | findings record | the rounds paragraph gave 23 and 13 for rounds 1 and 2; the table has 14 and 10 | build-changing | applied (record; recounted from the table) |
| F83 | 5 | sonnet | classification | "wide" did not say whether a change to what consumers run from the payload counts | build-changing | applied (2; this plan not reclassed) |
| F84 | 5 | sonnet | the end-of-rounds item | an item at every end, even a clean convergence, is a new human gate on every design in every repo (ShiftLead: 43 designs in 15 days); raise it only at the cap, with a sticking topic, with unreviewed findings, or where the repo requires a go | build-changing | applied (9, as modified by F91; Paul chose option a) |
| F85 | 5 | sonnet | the trend | the trend counted fact-check findings while the stop rule and 8 count reviews only | build-changing | applied (9) |
| F86 | 5 | sonnet | sticking point | cut it as a round-ender (8 patch findings; it never ended a round alone); keep one sentence naming the topic in the item | minor | applied (8: names the topic, does not end the rounds) |
| F87 | 5 | sonnet | findings record | cut the rounds paragraph, the topic grouping and the extra status forms; minors as a per-round count | minor | applied (6; minors keep their rows, Fable) |
| F88 | 5 | sonnet | Hold resume | cut the resume rules; Hold keeps the block and the note, the resume is the session's call | minor | applied (9: one sentence kept, Fable) |
| F89 | 5 | sonnet | data claims | the Context should say the rules would not have caught the in-repo gaps and the wide cap is a guess | minor | applied (Context) |
| F90 | 5 | sonnet | fact-check | the run used fact-checks to copy-edit hand-kept derived text; F87 removes the cause | minor | applied (with F87) |
| F91 | 5 | fable | the end-of-rounds item | F84's "unreviewed findings" trigger fires at nearly every end; it must be build-changing ones, and a no-item end needs the handoff | build-changing | applied (9) |
| F92 | 5 | fable | person's go | whether the layer rule already gates every plan; the payload rule must stand without it | minor | applied (9: the repo's own rules are a trigger) |
| F93 | 5 | fable | findings record | the round column took `closing` | minor | applied (6) |
| F94 | 5 | fable | sticking point | TD-173's `Resolved` form would have been a false-positive round-ender | minor | applied (with F86) |
| F95 | 5 | fable | the label | `withdraws` and the author-disagreement path were never used | minor | applied (5, 6: cut) |
| F97 | 6 | fable | the end-of-rounds item | a convergence in the cap's last round both converged and capped (8 of 39 in-repo designs ended in their fourth round, at 3.5 or 4 rounds) | build-changing | applied (7) |
| F98 | 6 | fable | closing fact-check | 3 still sent closing findings to an item that may not exist | minor | applied (3) |
| F99 | 6 | fable | the no-item path | no actor files the builds; Status stated twice | minor | applied (9) |
| F100 | 6 | fable | recurring topic | "since the last answer" hid a topic that returned in a bought round | minor | applied (8: cut) |
| F101 | 6 | fable | person's go | the payload text must not name a personal rule | minor | applied (9: a plan note, not for cadence.md) |
| F102 | 6 | fable | the label | 5 said "the reviewer" though fact-check findings carry labels too | minor | applied (5) |
| F103 | 6 | fact-check (sonnet) | recurring topic | rule 8 lost F23's condition (reopens or follows a fix), so refinement across rounds triggered the item on nearly every design | build-changing | applied (8; fixed, not reviewed) |
| F104 | 6 | fact-check (sonnet) | person's go | the block and Ask from filing were lost in the rewrite | minor | applied (9) |
| F105 | 6 | fact-check (sonnet) | person's go | the personal-rule parenthetical would land in cadence.md | minor | applied (9: a plan note) |
| F106 | 6 | fact-check (sonnet) | data claims | "would not have caught" overstated "not shown catchable" | minor | applied (Context) |
| F107 | 6 | fact-check (sonnet) | data claims | 43 ShiftLead designs, not 39; the wide medians predate F83's class | minor | applied (record, Context) |
| F108 | 6 | fact-check (sonnet) | findings record | open question 3 stale; F96 skipped | minor | applied (questions; F96 was never issued) |
| F109 | 6 | fact-check (sonnet) | the label | rule 6 still said "the reviewer" | minor | applied (6) |
