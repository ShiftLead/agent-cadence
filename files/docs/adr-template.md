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

## Review record

Optional: a plan that went through design review rounds (cadence.md §4.8 *Design review rounds*)
keeps every finding here, minor ones too. Each reviewer is given this table and names a finding
it reopens by its id ("reopens F2") rather than raising it again in new words. The Status line
states the class (in-repo or wide, and why) before round 1, and how the rounds ended after them.

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | fact-check (<model>) | <the mechanism, in a phrase> | <what is wrong> | build-changing \| minor | applied \| rejected: <why> \| open \| reopens F<n> |
