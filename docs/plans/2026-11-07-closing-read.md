# ADR 2026-11-07: a design's rounds do not end while a build-changing fix is unread — one closing read reads them

**Status:** proposed: a draft of the shape for Paul to agree before any review round runs (his layer, §4.8 add). No round has run. Class: **wide**, because it changes cadence.md §4.8, which every consumer runs from the payload (cap `design-rounds-wide`, 6). It supersedes clauses 3, 7 and 9 of ADR 2026-10-30-design-review-rounds.md where named below, and leaves the rest of that ADR standing.
**Date:** 2026-11-07
**Related:** TD-243 (this design); ADR `2026-10-30-design-review-rounds.md` (TD-203, decided); ADR `2026-10-30-review-outcomes.md` (TD-204, the record's form); ShiftLead TD-1434, TD-1435, TD-1437 (the cases)

## Context

Today the design rounds can end, and reach the person, while a build-changing fix has been read by no review (TD-243's Why):

- **At the cap**, the last round may raise build-changing findings. Their fixes are applied, and the rounds end anyway (ADR 2026-10-30, clause 7). ShiftLead TD-1434 is an example: F55 and F56 were recorded *applied (fixed, not reviewed)*. So was TD-1437's F51.
- **The closing fact-check**'s findings are *applied, never reviewed* (clause 3). One that changes the design makes the author recommend `One more round`. That recommendation buys a whole round, in which every review re-reads the whole plan. TD-1435's F41 is an example.
- **The end-of-rounds item** lists *the findings no review has read*. But nothing ties the author's recommendation to that list, so the default can be `Go` with such a fix in it.

On 2026-11-06 Paul chose `One more round` six times across designs. It was prompted by a rule kept in one session's memory, not in §4.8. The cost of each press was a full round, when what was wanted was a read of a few fixes.

## Design (the shape to agree)

**1. A closing read.** When the rounds end by the stop rule, at the cap, or after a bought round, and the closing fact-check has run, the author lists every build-changing finding whose status is `applied` and that no review has read since its fix. If the list is not empty, one **closing read** runs. It is a review by the first `review-model` and it reads only:
- the diff of the plan since the last review that read the whole plan;
- the findings the diff answers, from the findings table.

It does not re-read the whole plan; that is a round's job. Its findings are labelled and recorded like any review's.

**2. Order: the closing fact-check, then the closing read.** The fact-check runs first, as today, over the last round's changes. Its build-changing fixes then join the closing read's list. This covers TD-1435's case, a closing fact-check that changes the design, with a read of that change alone. It replaces today's recommendation of `One more round` for that case.

**3. A closing read that raises a build-changing finding.** Its fix is applied, and one more closing read runs over that fix alone. **At most two closing reads** run. If the second still raises a build-changing finding, the rounds end with that finding unread. The end-of-rounds item names it, and the author recommends `One more round`, because a fix that keeps breaking is a round's matter. A minor finding from a closing read is applied and not read again, as minor findings are today.

**4. The cap counts whole rounds only.** `design-rounds` and `design-rounds-wide` keep counting rounds. A closing read is outside the count, as fact-checks already are.

**5. The record.**
- A closing read is a row of the Reviews table. Its role is `closing-read` and its round is the last round, the same convention as the closing fact-check.
- A finding a closing read has read gets the status `applied (read R<n>)`. This uses the parenthetical that clause 6 already allows on a status, so no new column is needed.
- A finding still unread stays `applied (fixed, not reviewed)`, the form ShiftLead's records already use.
- `review_stats.py` learns the new role and counts its build-changing findings in the fact-checks' column of the trend. It is not a round's review.

**6. The end-of-rounds item says which it is**, in one line before the recommendation. Either:
- *Every build-changing fix has been read by a review.*
- *Unread: F<n>, F<m> (the closing read's limit)*.

The author may recommend `Go` only on the first line. With no item (a convergence with none of clause 9's triggers), the closing read still runs whenever its list is not empty. *Fixed, not reviewed* in a build entry's Fix is then left only for minor fixes.

**7. Where it lives.**
- cadence.md §4.8's *Design review rounds* paragraph: the closing read, its order, its limit and the item's line.
- `files/docs/procedures/cadence.md` step 3.
- `review_stats.py`: the `closing-read` role, with tests.
- The `adr-template.md` record comment: the role and the status form.
- `files/docs/cadence-changes.md`: one line.
- Once decided, tell ShiftLead's techlead this entry's number, so its flow and designer brief can mirror it after the next pin bump.

## Options

- **Do nothing.** The person keeps pressing `One more round` to buy a whole round when they need a read of a few fixes, and only a session that happens to hold the memory rule recommends it.
- **Recommend `One more round` whenever a build-changing fix is unread.** This puts the memory rule in §4.8. It is cheap to write and costly to run: every such ending buys a whole-plan round, past the cap.
- **A closing read (this draft).** It reads only the unread fixes, once or twice, outside the cap. The cost is one review of a small diff per design that ends with unread fixes.

## Decision

Proposed. The question for Paul: is this shape right (the closing read, the fact-check first, a limit of two closing reads, `applied (read R<n>)`, the item's line)? If so, the review rounds run on it, and the §4.8 text and the builds follow the decision. The draft recommends this shape.

## Consequences

- A design reaches the person, or its builds, with every build-changing fix read, except the case the limit catches, which the item names.
- One short review is added per design that ends with unread fixes. ShiftLead's 2026-11-06 designs would each have had one closing read instead of a `One more round` press.
- `review_stats.py` and every consumer's records gain a role and a status form.

## Revisit triggers

- The two-read limit is reached on more than one design in ten: the closing read is then hiding a design that needs another round.
- A build breaks on a fix that a closing read passed.

## Open questions for the rounds

1. Should the closing read use the first `review-model`, or the last one (the model that has not yet read the last round's fixes)?
2. Should a closing read's minor fix be re-checked by a fact-check when it states a fact about the code?
