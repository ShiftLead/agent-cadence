# ADR 2026-10-30: design reviews record their models and tokens, a defect a design missed names it in `Escaped from:`, and `review-stats` rebuilds the data on demand

**Status:** proposed (shape agreed with Paul 2026-10-30; review rounds not started). Class: **wide** (cap 6): it adds a ledger field and a key to what consumers run from the payload, a payload script, and its backfill edits ShiftLead's ledger.
**Date:** 2026-10-30
**Related:** TD-204 (the build), TD-203 and ADR `2026-10-30-design-review-rounds.md` (which this extends, not supersedes); `docs/review-data/` (the 97-design dataset and `trial-rev18.md`); shiftlead TD-857 (the Gemini fact-checker, a model this must name)

## Context

- **The ADR this extends** (decided 2026-10-30) gives every design plan a findings table (its rule 6): each finding's id, round, reviewer, topic, class (`build-changing` | `minor`) and status. That fixes the labels the dataset lacked. A decided ADR is immutable (cadence.md §7.5), so this one adds to it rather than editing it; the table's change lands in `files/docs/adr-template.md`'s *Review record*, which TD-203's build adds.
- **The dataset** (`docs/review-data/`, 97 designs) was mined by hand. It can say how long review loops run but not whether they work:
  - build-changing labels exist for one design (TD-173's ledger writer);
  - tokens exist for 278 reviews, covering 43 of the 97 designs;
  - models are named loosely (letters F, S, O);
  - the link from a design to a defect it later let through was found by reading which ledger entries cite the design: a lower bound, with 7 firm and 5 "(questionable)" pairs, all ShiftLead's or the archived dev-cadence's.
- **The trial** (`trial-rev18.md`) had to use total findings as a proxy for build-changing ones and could not test the link at all.
- **Paul's direction:** "the real help is to be able to check against issues that arose after the designs"; "as tokens get cheaper and agents get stronger … people will want to rely on them more, and expand the number of allowed cycles"; "We might want to record the actual models involved."

## Design

**1. A Reviews table beside the findings table.** The plan's *Review record* gains a second table, one row per review, fact-checks included (each repeat of a fix-then-check fact-check is its own row):

| review | round | role | model | tokens | date | findings |
|---|---|---|---|---|---|---|
| R1 | 1 | fact-check | gemini/gemini-2.5-flash | 41210 | 2026-11-02 | F1–F4 |
| R2 | 1 | design | claude-sonnet-5-5 | 88034 | 2026-11-02 | F5–F9 |
| R3 | 1 | design | claude-fable-5-1 | 101877 | 2026-11-02 | - |

- **review:** `R<n>`, in the order run. The findings table's `by` column names it (`R2`), replacing the free text (`fact-check (sonnet)`).
- **round:** as the findings table's (the closing fact-check under the last round).
- **role:** `fact-check` or `design`.
- **model:** the exact id the runner reports (`claude-sonnet-5-5`; `<adapter>/<model>` for a non-Claude seat, TD-203's form). Where the runner reports only the alias it was given, the alias followed by `?` (`sonnet?`), never a guessed id.
- **tokens:** the review's total as the runner returns it, a whole number; `?` where it returns none.
- **date:** ISO.
- **findings:** the ids it raised, or `-` for a clean review. A clean review still gets a row: it is the stop rule's round, and its cost is part of what the data must show.

The rows are recorded **whatever the key (3) says**: data not written when the review runs cannot be filled in later.

**2. `Escaped from:`, a ledger field on a defect a design missed.**
- **Form:** `**Escaped from:** <design>` in the entry's header block (cadence.md §2.12: the first word is the value, the rest a free comment). The value is a design's entry, `TD-NNN` or `<repo>#TD-NNN` (§2.2's form), or a plan's path (`docs/plans/<file>.md`, or `<repo>:docs/plans/<file>.md` for another repo's). One value per entry.
- **Meaning:** a design review of that design should have caught this. A defect the design got right and the build got wrong gets no field.
- **Who sets it:** the session filing the defect, which asks one question: *did the design miss this, or the build?* A later session may add or remove the field like any other edit, with a word why in the PR.
- **Parsing:** ledgerboard reads it as any other header-block field; it is not a ledgerboard-defined field and needs no ledgerboard release. `review-stats` (4) resolves each value and reports one it cannot resolve; `ledger.py --check` does not.
- An archived entry may take the field (the backfill edits closed defects).

**3. The key `review-outcomes`** (`off` | `on`, default `off`, in `cadence_config.py`'s `KEYS`, §9.18). It turns on **only the filing question** of 2:
- `ledger_next_id.py` prints the question once when it hands out an id in a repo with the key on (every new entry takes its id there, §2.10);
- a repo whose front end hands out ids (shiftlead's `ao td next`) asks it the same way: a shiftlead entry.

No reminder to run `review-stats`: it prints, itself, how many plans with a Review record are newer than its last run, and the decided ADR already says to rerun the trial after about ten plans.

**4. `review-stats`** (`files/scripts/review_stats.py`, stdlib only), run on demand, never by a hook or a sweep:
- **Scope:** every repo on the machine's roster (cadence.md §9; `$AGENT_CADENCE_REG_DIR` honoured); `--repo PATH` for one.
- **Reads:** each repo's tracked `.md` files holding a *Review record* (the two tables of 1 and the ADR's rule 6), and its ledger's `Escaped from:` fields through `ledger.py`/ledgerboard (never a hand regex, §2.12).
- **Writes:** the rebuilt dataset (json, and the md's tables) to `review-stats/` beside the roster, never into a repo. Publishing a scrubbed copy, as `docs/review-data/` was, is a separate deliberate step.
- **The trial:** reruns the decided ADR's rules over the rebuilt data against each repo's `design-rounds` and `design-rounds-wide`, now with real `build-changing` labels and escaped-from links. Its logic is ported from `docs/review-data/trial_rules.py` and `aggregate.py`, which stay as they are: the frozen first form, reproducing the published dataset.
- **`--candidates [--since DATE]`:** the backfill pass (5). It lists defect entries (`Type: debt`, ledgerboard's default) since the date that cite a design entry or plan and carry no `Escaped from:`. It judges nothing.

**5. Backfill.**
- **Any repo** turning the key on later runs `review-stats --candidates --since <date>`. A session judges each candidate with 2's question and adds the field in one PR.
- **This repo's backfill**, part of TD-204's build, is a ShiftLead PR adding `Escaped from:` to the six firm pairs: TD-960 ← TD-947, TD-1128 ← TD-995, TD-1095 ← TD-1051, TD-1129 ← TD-909, TD-1031 ← TD-804, TD-854 ← TD-820.
  - Left out: TD-935 ← TD-931 (the data marks it a doc leftover after the build, so a build miss by 2's test) and the five "(questionable)" pairs.
  - dev-cadence is archived, so its pairs stay in the dataset only. agent-cadence has none yet.

**6. Where it lives:**
- cadence.md §2 gains the `Escaped from:` paragraph (2); §2.12's list of fields the cadence defines names it; §4.8's *Design review rounds* paragraph (TD-203) names the Reviews table; §9.18 lists `review-outcomes`.
- `files/docs/adr-template.md`'s *Review record* (TD-203) gains the Reviews table and `R<n>` in `by`.
- `files/scripts/review_stats.py` (new, SYNC: `sync.sh`'s `SYNC_FILES` and README's file-class table).
- `cadence_config.py`: the key, with an `off`|`on` validator; the seed `files/docs/cadence.toml` gains its commented line.
- `ledger_next_id.py`: the question when the key is on.
- `files/docs/cadence-changes.md`: one entry.
- ShiftLead: an entry for `ao td next`'s question, and the backfill PR (5).

**7. Tests:**
- `tests/test_cadence_config.sh`: the key's default, a repo value, a bad value as a `--check` error, and the seed parity.
- `ledger_next_id.py` prints the question with the key on and stays silent with it off.
- A new `tests/test_review_stats.sh`, over fixture repos on a temporary roster: both tables are read, `Escaped from:` resolves (including `<repo>#TD-NNN` and a plan path), an unresolvable value is reported, `--candidates` lists a citing defect without the field and skips one with it, the output lands beside the roster and nothing is written into a repo, and `--repo` limits the scope.

## Options

- **Two more columns in the findings table** (TD-204's first draft): a clean review leaves no row, so the stop rule's round has no cost recorded, and a review's tokens repeat on every row it raised. Not chosen (Paul, 2026-10-30).
- **A separate review log file per plan:** one more file to keep in step with the record. Not chosen.
- **A later check judges `Escaped from:`, not the filer:** the filer knows the defect best when filing it, and a later pass is the backfill's job anyway (`--candidates`). Not chosen.
- **The key also turns on a periodic reminder to run `review-stats`:** one more mechanism for what `review-stats` can say itself. Cut (Paul, 2026-10-30).
- **Suggesting cap values from the data:** fewer than 100 designs, almost none labelled; it would fit noise. Later, not now.

## Decision

Pending the review rounds and Paul's go (his §2.4 layer rule: TD-204 stays `Blocked by: decision (Paul)` until then).

## Consequences

- Every design plan's cost becomes visible per review and per model. The question "would a cheaper model or one more round have caught it?" becomes answerable once enough plans carry both tables and their defects carry `Escaped from:`.
- A repo that leaves the key off still records the Reviews table, so turning the key on later loses only the filing question's past answers, and the backfill recovers those.
- Plans with a hand-kept Review record from before TD-203 have no Reviews table. `review-stats` reads them as findings-only.

## Open questions for the rounds

1. Does the Claude Code runner report the exact model id and the token count back to the session that ran the review? Rule 1's `?` forms assume sometimes not. The fact-check checks this against what an Agent call returns.
2. Should `--candidates` also list a defect citing a design only in its Why, or only in `Related:`/`Blocked by`? The dataset's pairs came from any citation.

## Review record

| review | round | role | model | tokens | date | findings |
|---|---|---|---|---|---|---|

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
