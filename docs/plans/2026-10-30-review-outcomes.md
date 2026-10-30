# ADR 2026-10-30: design reviews record their models and tokens, a defect a design missed names it in `Escaped from:`, and `review-stats` rebuilds the data on demand

**Status:** proposed (shape agreed with Paul 2026-10-30; review rounds under way, round 1). Class: **wide** (cap 6): it adds a ledger field and a key to what consumers run from the payload, a payload script, a field to a vendored format (a ledgerboard release), and its backfill edits ShiftLead's ledger.
**Date:** 2026-10-30
**Related:** TD-204 (the build), TD-203 and ADR `2026-10-30-design-review-rounds.md` (which this extends, not supersedes); `docs/review-data/` (the 97-design dataset and `trial-rev18.md`); shiftlead TD-857 (the Gemini fact-checker, a model this must name)

## Context

- **The ADR this extends** (decided 2026-10-30) gives every design plan a findings table (its rule 6): each finding's id, round, reviewer, topic, class (`build-changing` | `minor`) and status. That fixes the labels the dataset lacked. A decided ADR is immutable (cadence.md §7.5), so this one adds to it rather than editing it; the table's change lands in `files/docs/adr-template.md`'s *Review record*, which TD-203's build adds.
- **The dataset** (`docs/review-data/`, 97 designs) was mined by hand. It can say how long review loops run but not whether they work:
  - build-changing labels exist for one design (TD-173's ledger writer);
  - tokens exist for 278 reviews, covering 43 of the 97 designs;
  - models are named loosely (letters F, S, O);
  - the link from a design to a defect it later let through was found by reading which ledger entries cite the design: a lower bound: 7 firm ShiftLead pairs (one a doc leftover after the build), 3 dev-cadence designs with firm defects (the repo is archived), and 5 "(questionable)" designs carrying 6 defect entries.
- **The trial** (`trial-rev18.md`) had to use total findings as a proxy for build-changing ones and could not test the link at all.
- **Paul's direction:** "the real help is to be able to check against issues that arose after the designs"; "as tokens get cheaper and agents get stronger … people will want to rely on them more, and expand the number of allowed cycles"; "We might want to record the actual models involved."

## Design

**1. A Reviews table beside the findings table.** The plan's *Review record* gains a second table, one row per review, fact-checks included (each repeat of a fix-then-check fact-check is its own row):

| review | round | role | model | tokens | date | findings |
|---|---|---|---|---|---|---|
| R1 | 1 | fact-check | gemini/gemini-2.5-flash | 41210 | 2026-11-02 | F1–F4 |
| R2 | 1 | design | claude-sonnet-5-5 | 88034 | 2026-11-02 | F5–F9 |
| R3 | 1 | design | claude-fable-5-1 | 101877 | 2026-11-02 | - |

- **review:** `R<n>`, in the order run. The findings table's `by` column names it (`R2`) in new records. A record kept before this (the decided ADR's own, with free text such as `fact-check (sonnet)`) is left as it is, and `review-stats` reads either form.
- **round:** as the findings table's (the closing fact-check under the last round).
- **role:** `fact-check` or `design`.
- **model:** the exact id the runner reports (`claude-sonnet-5-5`; `<adapter>/<model>` for a non-Claude seat, TD-203's form). In Claude Code this is the Agent result's `resolvedModel`. Where a runner reports only the alias it was given, the alias followed by `?` (`sonnet?`), never a guessed id.
- **tokens:** the review's total as the runner returns it, a whole number (in Claude Code, the completion notification's `subagent_tokens`, a single total with no input/output split); `?` where it returns none. It arrives when the review ends, so the session writes the row then.
- **date:** ISO.
- **findings:** the ids it raised, or `-` for a clean review. A clean review still gets a row: it is the stop rule's round, and its cost is part of what the data must show.

The rows are recorded **whatever the key (3) says**: data not written when the review runs cannot be filled in later.

**2. `Escaped from:`, a ledger field on a defect a design missed.**
- **Form:** `**Escaped from:** <design>` in the entry's header block (cadence.md §2.12: the first word is the value, the rest a free comment). The value is a design's entry, `TD-NNN` or `<repo>#TD-NNN` (§2.2's form), or a plan's path (`docs/plans/<file>.md`, or `<repo>:docs/plans/<file>.md` for another repo's). One value per entry.
- **Meaning:** a design review of that design should have caught this. A defect the design got right and the build got wrong gets no field.
- **Who sets it:** the session filing the defect, which asks one question: *did the design miss this, or the build?* A later session may add or remove the field like any other edit, with a word why in the PR.
- **Parsing:** it is a field the cadence defines, so it joins ledgerboard's `CADENCE_FIELDS` as a free-valued field, in a ledgerboard minor release, vendored here by `vendor_ledgerboard.sh`; ShiftLead's copy is held byte-equal to its agent-cadence pin, so it arrives by an `agent-cadence bump` there. Without that, a ledger with a `Fields:` line (ShiftLead's) flags it `undeclared-field`, an error under `--check --since` and so in the cadence check's `ledger` row, and a `Fields:` line cannot declare a free-valued field. `review-stats` (4) resolves each value from the raw field text, split and stripped as ledgerboard's `first_word` does (`WORD_RE`; surrounding `*_` and backticks, a trailing `.` or `:`) but not lowercased and reports one it cannot resolve; `ledger.py --check` does not resolve it.
- An archived entry may take the field (the backfill edits closed defects).

**3. The key `review-outcomes`** (`off` | `on`, default `off`, in `cadence_config.py`'s `KEYS`, §9.18). It turns on **only the filing question** of 2:
- `ledger_next_id.py` prints the question once, on stderr (stdout stays the ids, one a line), when it hands out ids in a repo with the key on (every new entry takes its id there, §2.10). Under `--json` it adds a `question` key. It prints whenever ids are printed, exit 3's unreserved ids included, and not on `--claim` or exit 2. Under `--json` with the key off, `question` is absent; the docstring's *Output:* line names it;
- a repo whose front end hands out ids (shiftlead's `ao td next`) asks it the same way: a shiftlead entry.

No reminder to run `review-stats`: each run prints how many plans carry a Review record, and the decided ADR already says to rerun the trial after about ten plans.

**4. `review-stats`** (`files/scripts/review_stats.py`, stdlib only), run on demand, never by a hook or a sweep. **It is mechanical and keeps no state:** every run rebuilds everything from the repos' files as they are now, with no model, no agent and no judgement, so an `Escaped from:` added since the last run (a defect found months after its design) is counted the next time anyone runs it, with nothing to update in between.
- **Age:** a design's defects keep arriving long after it is built, so every figure carries each design's age (days since the date in the plan's `**Status:** decided YYYY-MM-DD` line, else its `**Date:**`, else its first commit). The trial and the aggregates count escapes only for designs older than an `--aged DAYS` threshold (default 14), and print the young ones separately, so a young design's zero escapes is not read as a clean design.
- **Scope:** every repo on the machine's roster (cadence.md §9; `$AGENT_CADENCE_REG_DIR` honoured); `--repo PATH` for one.
- **Reads:** each repo's tracked `.md` files holding a *Review record* (the two tables of 1 and the ADR's rule 6; `by` as `R<n>` or free text), and its ledger's `Escaped from:` fields through `ledger.py`/ledgerboard (never a hand regex, §2.12).
- **Writes:** the rebuilt dataset (json, and the md's tables) to `review-stats/` beside the roster, never into a repo. Publishing a scrubbed copy, as `docs/review-data/` was, is a separate deliberate step.
- **The trial:** reruns the decided ADR's rules over the rebuilt data against each repo's `design-rounds` and `design-rounds-wide`, now with real `build-changing` labels and escaped-from links. Its logic is ported from `docs/review-data/trial_rules.py` and `aggregate.py`, which stay as they are: the frozen first form, reproducing the published dataset.
- **`--candidates [--since DATE]`:** the backfill pass (5). It lists defect entries (`Type: debt`, ledgerboard's default) since the date that cite a design entry or plan and carry no `Escaped from:`. It judges nothing.

**5. Backfill.**
- **Any repo** turning the key on later runs `review-stats --candidates --since <date>`, which is mechanical (4). Judging each candidate with 2's question is the one step that needs judgement: the session does it, and **may hand it to an agent only if the person, asked first, agrees**, because judging many candidates can cost many tokens. The session adds the fields in one PR. After that, `review-stats` counts them like any others.
- **This repo's backfill**, part of TD-204's build, is a ShiftLead PR adding `Escaped from:` to the six firm pairs: TD-960 ← TD-947, TD-1128 ← TD-995, TD-1095 ← TD-1051, TD-1129 ← TD-909, TD-1031 ← TD-804, TD-854 ← TD-820.
  - Left out: TD-935 ← TD-931 (the data marks it a doc leftover after the build, so a build miss by 2's test) and the five "(questionable)" pairs.
  - dev-cadence is archived, so its pairs stay in the dataset only. agent-cadence has none yet.

**6. Where it lives:**
- cadence.md §2 gains the `Escaped from:` paragraph (2); §2.12's list of fields the cadence defines names it; §4.8's *Design review rounds* paragraph (TD-203) names the Reviews table; §9.18 lists `review-outcomes`.
- ledgerboard (ShiftLead/ledgerboard): a minor release adding `escaped from` to `CADENCE_FIELDS` and to `SPEC.md`'s list of spec fields, vendored here, and reaching ShiftLead by its agent-cadence bump before the backfill PR.
- the seed `files/docs/technical_debt.md`'s entry template gains an optional `**Escaped from:**` line beside `Part of` (`tests/test_parity.sh` holds that template and §2.12's list to `CADENCE_FIELDS`); `ledger.py --fields` then reports it `defined_by: cadence`.
- `files/docs/adr-template.md`'s *Review record* (TD-203) gains the Reviews table and `R<n>` in `by`.
- `files/scripts/review_stats.py` (new, SYNC: `sync.sh`'s `SYNC_FILES` and README's file-class table).
- `cadence_config.py`: the key, with an `off`|`on` validator; the seed `files/docs/cadence.toml` gains its commented line.
- `ledger_next_id.py`: the question when the key is on.
- `files/docs/cadence-changes.md`: one entry.
- ShiftLead: an entry for `ao td next`'s question, and the backfill PR (5).

**7. Tests:**
- `tests/test_cadence_config.sh`: the key's default, a repo value, a bad value as a `--check` error, and the seed parity.
- `ledger_next_id.py` prints the question on stderr with the key on (stdout unchanged; `--json` carries `question`), and stays silent with it off and on `--claim`.
- ledgerboard's own tests (its release): `Escaped from:` in a ledger with a `Fields:` line raises no `undeclared-field`.
- `tests/test_parity.sh` passes with the new field in §2.12, the seed template and `CADENCE_FIELDS`.
- A new `tests/test_review_stats.sh`, over fixture repos on a temporary roster: both tables are read, `Escaped from:` resolves (including `<repo>#TD-NNN` and a mixed-case `<repo>:` plan path), `by` is read as `R<n>` and as free text, an unresolvable value is reported, `--candidates` lists a citing defect without the field and skips one with it, the output lands beside the roster and nothing is written into a repo, and `--repo` limits the scope. An `Escaped from:` added to a fixture after a first run is counted by the second, and a design younger than `--aged` is listed apart and not counted as clean.

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

1. ~~Does the runner report the exact model id and tokens?~~ Fact-check (round 1): yes in Claude Code: the Agent result's `resolvedModel` and the notification's `subagent_tokens`, a single total. Adopted in 1; `?` stays for a seat that reports neither.
2. Should `--candidates` also list a defect citing a design only in its Why, or only in `Related:`/`Blocked by`? The dataset's pairs came from any citation.

## Review record

| review | round | role | model | tokens | date | findings |
|---|---|---|---|---|---|---|
| R1 | 1 | fact-check | claude-sonnet-5-5 | 100982 | 2026-10-30 | F1–F7 |
| R2 | 1 | fact-check | claude-sonnet-5-5 | 69466 | 2026-10-30 | F8–F13 |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | `Escaped from:` parsing | not a ledgerboard field, it is flagged `undeclared-field` (an error under `--check --since`) in any ledger with a `Fields:` line, ShiftLead's included, and a `Fields:` line cannot declare a free-valued field; "no ledgerboard release" was false | build-changing | applied (2, 6, 7, Status: a ledgerboard minor release adds it to `CADENCE_FIELDS`) |
| F2 | 1 | R1 | the filing question | `ledger_next_id.py`'s stdout is its contract (the ids); the plan named no stream, no `--json` form, and no rule for `--claim` or a no-id exit | build-changing | applied (3, 7) |
| F3 | 1 | R1 | `Escaped from:` parsing | ledgerboard's `first_word` lowercases, so a mixed-case path would not resolve | minor | applied (2, 7) |
| F4 | 1 | R1 | data claims | the pair counts undercounted dev-cadence's firm designs and miscounted the questionable ones | minor | applied (Context) |
| F5 | 1 | R1 | design age | "the plan's Decision date" is no field | minor | applied (4: Status's decided date, else `Date:`, else first commit) |
| F6 | 1 | R1 | findings record | `by` as `R<n>` changes the decided ADR's form; old records keep free text | minor | applied (1, 4, 7) |
| F7 | 1 | R1 | wording | TD-203's "rules 1–11" was called stale | minor | rejected: the decided ADR has rules 1–11 (10 is where it lives, 11 the tests) |
| F8 | 1 | R2 | `Escaped from:` parsing | adding the field to `CADENCE_FIELDS` fails `tests/test_parity.sh` unless the seed `technical_debt.md` template gains it too; the plan named neither | build-changing | applied (6, 7) |
| F9 | 1 | R2 | data claims | the questionable designs carry 6 defect entries, not 7 | build-changing | applied (Context) |
| F10 | 1 | R2 | `Escaped from:` parsing | "first whitespace-delimited token" differs from `first_word`'s split and strip; a backticked path would not resolve | minor | reopens F3 (applied: 2) |
| F11 | 1 | R2 | `Escaped from:` parsing | ShiftLead's ledgerboard is a byte-equal copy of its agent-cadence pin, so it arrives by a bump, not a separate vendoring | minor | applied (2, 6) |
| F12 | 1 | R2 | the filing question | exit 3 (unreserved ids) unstated; `--json` with the key off; the docstring's Output line | minor | reopens F2 (applied: 3) |
| F13 | 1 | R2 | `Escaped from:` parsing | `Taken by` is a non-spec field with the same problem (`ledger_next_id.py:338`, its `"taken by" in LB.CADENCE_FIELDS` false today); add it in the same release | minor | rejected: out of this plan's scope; raised with Paul as its own entry |
