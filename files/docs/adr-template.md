<!-- SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/docs/adr-template.md
     Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR. -->

# ADR <id>: <the decision, as one sentence>

<!-- Copy this file to <the repo's ADR directory>/<id>-<slug>.md and drop this comment and the
     SYNCED FILE header above. <id> is the repo's own scheme (NNN, or YYYY-MM-DD). The rules —
     when a decision earns an ADR, what each field means, why a decided ADR is never edited —
     are cadence.md §7 (Architecture decisions). -->

**Status:** proposed | decided YYYY-MM-DD by <who> | superseded by ADR <id> (its path)
**Date:** YYYY-MM-DD
**Related:** TD-NNN, PR #N, ADR <id>

## Context

What forced the decision: the problem, the constraint, what was measured. Enough that a reader
who was not there can tell whether it still holds.

## Options

Each option considered, one short paragraph, with what it costs — including "do nothing".

## Decision

What was chosen, and by whom. While Status is `proposed`, the question put to the decider and
the recommended answer.

## Consequences

What changes because of it, what gets harder, and what is now out of bounds.

## Revisit triggers

The observable events that would reopen it ("a second consumer needs X", "the table passes
1M rows"). Reopening means a new ADR that supersedes this one — never an edit to this one.

<!-- A design that goes through review rounds (cadence.md §4.8 *Design review rounds*) keeps its
review record in docs/reviews/TD-NNN.md, named by the design's entry — not in this ADR. The Status
line above states the class (in-repo or wide, and why) before round 1, and how the rounds ended.
Each reviewer is given the findings table and names a finding it reopens by its id ("reopens F2").
The record file's form (cadence.md §4.8; Source: backfill only for one written after the fact, §2.13):

# Review record: TD-NNN

**Design:** docs/plans/YYYY-MM-DD-slug.md
**Class:** in-repo | wide
**Decided:** YYYY-MM-DD | pending
**Source:** rounds | backfill

| review | round | role | model | tokens | date |
|---|---|---|---|---|---|
| R1 | 1 | fact-check \| design | <the exact model id, or alias?> | <the runner's total, or ?> | YYYY-MM-DD |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | <the mechanism, in a phrase> | <what is wrong> | build-changing \| minor | applied \| rejected: <why> \| open \| reopens F<n> |
-->
