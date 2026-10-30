# ADR 2026-10-30: a design's review record is its own file, `docs/reviews/TD-NNN.md`, with each review's model and tokens; a defect a design missed names it in `Escaped from:`; `review-stats` rebuilds the data on demand

**Status:** decided 2026-10-30 by Paul (`Go`; the rounds ended by the stop rule after round 4 (in a cap of 6); build-changing findings per round from reviews 10, 6, 3, 0, from fact-checks 4, 0, 0, 0 and the closing fact-check 0; 15 reviews, 1,300,069 tokens; recurring topic: the design-to-build link, F43–F45 and F54). Class: **wide** (cap 6): it moves where the payload's design-rounds rule keeps its table, adds a ledger field (a ledgerboard release) and a key to what consumers run, a payload script, and its backfill writes into ShiftLead.
**Date:** 2026-10-30
**Related:** TD-204 (the build); ADR `2026-10-30-design-review-rounds.md` and TD-203 (built, PR #29), whose findings table this moves and extends; `docs/review-data/` (the 97-design dataset and `trial-rev18.md`); shiftlead TD-857 (the Gemini fact-checker, a model this must name). This plan's own record: `docs/reviews/TD-204.md`.

## Context

- **TD-203** (built, #29) made every design plan keep a findings table in its *Review record* (`files/docs/adr-template.md`; cadence.md §4.8 *Design review rounds*): each finding's id, round, reviewer, topic, class (`build-changing` | `minor`) and status. That fixes the labels the dataset lacked.
- **Designs live in different places:** this repo writes an ADR per plan in `docs/plans/`; ShiftLead writes ADRs in `docs/decisions/` and most designs as edits to its living `docs/design/` with prose entries in `docs/design-history.md` (TD-947's from line 139). A table inside "the plan" has no fixed place for most of ShiftLead's designs, and nothing links a TD to the file holding its table.
- **The dataset** (`docs/review-data/`, 97 designs) was mined by an agent from design-history (49 records), transcripts (35), ADRs (10) and 3 others. It can say how long review loops run but not whether they work:
  - build-changing labels exist for one design (TD-173's ledger writer);
  - tokens exist for 278 reviews, covering 43 of the 97 designs;
  - models are named loosely (letters F, S, O);
  - the link from a design to a defect it later let through was found by reading which ledger entries cite the design: a lower bound: 7 firm ShiftLead pairs (one a doc leftover after the build), 3 dev-cadence designs with firm defects (the repo is archived), and 5 "(questionable)" designs carrying 6 defect entries.
- **The trial** (`trial-rev18.md`) had to use total findings as a proxy for build-changing ones and could not test the link at all.
- **Paul's direction:** "the real help is to be able to check against issues that arose after the designs"; "as tokens get cheaper and agents get stronger … people will want to rely on them more, and expand the number of allowed cycles"; "We might want to record the actual models involved." Stats are generated mechanically on demand, and more `Escaped from:` links will appear as time goes by; the backfill may need an agent, with the person's permission.

## Design

**1. A design's review record is one file, `docs/reviews/TD-NNN.md`,** named by the design's entry (the TD whose rounds they are), in the repo that holds that entry. A design that runs rounds has its entry before round 1 (in ShiftLead, a `Kind: design-first` entry); a design without one is filed one first, or gets no record and nothing can escape from it. It replaces the plan's *Review record* section: the design text stays wherever the repo keeps designs (an ADR, a living design doc), and nothing is renamed. The file is:

```
# Review record: TD-204

**Design:** docs/plans/2026-10-30-review-outcomes.md
**Class:** wide
**Decided:** 2026-11-02
**Source:** rounds

| review | round | role | model | tokens | date |
|---|---|---|---|---|---|
| R1 | 1 | fact-check | claude-sonnet-5-5 | 100982 | 2026-10-30 |

| id | round | by | topic | finding | class | status |
|---|---|---|---|---|---|---|
| F1 | 1 | R1 | `Escaped from:` parsing | ... | build-changing | applied |
```

- **Header:** `Design:` where the design text is: a path, and for a living-doc design the doc and its section (`docs/design/4.2-state-feed.md §4.2 Permissions`). `Class:` `in-repo` | `wide` (§4.8); the plan's Status line still states it (rule 2), and the record's is the one `review-stats` reads; the Status line's is TD-203's rule for the plan's readers. `Decided:` the date the rounds ended for the build: the `Go` answer's date when an item was raised, else the closing fact-check's date; `pending` until then, and while a `Hold` stands; written by the PR that records the answer or files the builds (rule 9's PR); a `backfill` record takes its source's design date (the dataset's `date`), else `pending`. `Source:` `rounds` (written as the reviews ran) or `backfill` (5).
- **Reviews table,** one row per review that completed, fact-checks included (each repeat of a fix-then-check fact-check is a row): `R<n>` in the order run; round (the closing fact-check under the last round; it never restarts in a record, so a `Hold` revision's rounds carry on the numbering, and its own count against the cap is the session's); role `fact-check` | `design`; the exact model id the runner reports (`claude-sonnet-5-5`, or `<adapter>/<model>` for a non-Claude seat; in Claude Code the Agent result's `resolvedModel`), else the alias given with `?` (`sonnet?`), never a guessed id; tokens, the total the runner returns (in Claude Code the completion notification's `subagent_tokens`, one total), else `?`; date. A review that was aborted, killed or discarded gets no row.
- **Findings table,** TD-203's, with `by` naming the review (`R2`). A review's findings are the rows whose `by` names it; a review with none is clean. A `backfill` record whose source gives only a count writes that many rows with topic `?`, finding `(not recorded)` and class `unlabelled`, a class only a `backfill` record may use; in a `rounds` record `review-stats` lists the row as malformed and reads it as the proxy.
- **The Reviews table is written whatever the key (3) says:** one row costs a few dozen tokens against a review's tens of thousands, and data not written when the review runs cannot be filled in later.

**2. `Escaped from:`, a ledger field on a defect a design missed.**
- **Form:** `**Escaped from:** <design entry>` in the entry's header block (cadence.md §2.12: the first word is the value, the rest a free comment): `TD-NNN` or `<repo>#TD-NNN` (§2.2's form), the entry whose `docs/reviews/TD-NNN.md` holds the design's record. One value: the design that should first have caught it; any other goes in the free comment.
- **Meaning:** a design review of that design should have caught this. A defect the design got right and the build got wrong gets no field.
- **Who sets it:** the session filing the defect, which asks one question (3): *did a design miss this, or the build?* A later session may add or remove the field like any other edit, with a word why in the PR.
- **Finding the design** is the filer's judgement, from the defect: (1) what the defect itself cites (its Location or Why naming a design section, a build TD or a PR; the six backfilled defects all do one of these); (2) else `git log`/`blame` on the broken code, a commit and its PR to a build TD, knowing a later refactor or a squash subject may hide it, and an omission has no line to log; (3) a build TD maps to its design through the build's own `Part of:` where it has one, and a design section through the records' `Design:` lines (grepping `docs/reviews/` is the cheap route). A design is found by its TD, and its record file is its link. If no design is found, the field is left off.
- **No new design-to-build link is written.** A build's existing `Part of:` (same ledger, one parent, §2.4; 86 of ShiftLead's entries carry one) is read where it is there, and nothing requires it: requiring it would make the design wait on its builds and cannot cross repos, and a hand-kept list of builds in the record would go stale with nothing to check it. A cross-repo build is reached by citation. `Part of:` stays same-repo **by decision** (Paul, 2026-10-30): a build that needs another repo's entry first says so in its own `Blocked by: <repo>#TD-NNN` (§2.4).
- **ledgerboard:** it joins `CADENCE_FIELDS` as a free-valued field, in ledgerboard v2.2 (ledgerboard#TD-005's minor release, which also adds TD-188's `Id take`; Paul: ride v2.2). `check()` reads live entries only, so the release is what future live defects need; the backfill's fields, on archived entries, would pass without it. Without it, a ledger with a `Fields:` line (ShiftLead's) flags the field `undeclared-field`, an error under `--check --since` and so in the cadence check's `ledger` row, and a `Fields:` line cannot declare a free-valued field. The release is vendored here by `vendor_ledgerboard.sh`; ShiftLead's copy is held byte-equal to its agent-cadence pin, so it arrives by an `agent-cadence bump` PR that also runs ShiftLead's own `vendor_ledgerboard.sh <tag>`.

**3. The key `review-outcomes`** (`off` | `on`, default `off`, in `cadence_config.py`'s `KEYS`, §9.18), for a repo that wants design efficacy and its defects tracked; off is the cheapest way to work. It turns on:
- **the filing question:** `ledger_next_id.py` prints one fixed line on stderr, last after every other stderr line (stdout stays the ids) whenever it hands out ids, exit 3's unreserved ones and `--json` included, and not on `--claim` or exit 2: *if this entry is a defect, did a design miss it? then `**Escaped from:** <design TD>` (cadence.md §2)*. A repo whose front end hands out ids prints the same line: shiftlead's `ao td reserve` wraps `ledger_next_id.py` with its stderr piped (`src/sessionorc/agent_ids.py`), so it reads the key and reprints the line itself: a shiftlead entry.
- **the backfill (5):** nothing offers or runs it. The key's §9.18 text and §2's paragraph suggest that a repo turning it on runs it once, and give the formats: `review-stats --candidates --since <date>`; a record file per design in `adr-template.md`'s form (1), `Source: backfill`; and `**Escaped from:** TD-NNN` or `<repo>#TD-NNN` (`**Escaped from:** shiftlead#TD-947`).

**4. `review-stats`** (`files/scripts/review_stats.py`, stdlib only), run on demand, never by a hook or a sweep. **It is mechanical and keeps no state:** every run rebuilds everything from the repos' files as they are, with no model, no agent and no judgement, so an `Escaped from:` added since the last run is counted the next time anyone runs it.
- **Reads** the roster, each repo's `docs/reviews/TD-*.md`, its `design-rounds` and `design-rounds-wide` (`cadence_config.py`), and the `Escaped from:` fields of its live **and archived** entries (`ledgerboard.entries()` over both texts; the backfill's six defects are all archived, and `--list` and `check()` read live entries only), from the raw field text, split and stripped as `first_word` does but not lowercased; a `<repo>` basename is compared case-insensitively and `TD` read upper-cased. Nothing else: no design text, no transcript.
- **Scope:** every repo on the machine's roster (cadence.md §9; `$AGENT_CADENCE_REG_DIR` honoured), or `--repo PATH`. `<repo>` in a value resolves through `ledger.py`'s `Roster` (a roster basename, or `owner/name` where basenames collide, §2.4), and the record is looked for under that root; a value its `XREPO_ITEM_RE` (or the bare `TD-NNN` form) does not match is listed as unresolved and never passed to it. A value is **resolved** (its record file exists), **out of scope** (its repo is not on the roster, the `Roster` cannot resolve it, or it is outside `--repo`) or **unresolved** (in scope, no record file). Out-of-scope and unresolved escapes are listed and left out of every rate. Results follow the roster, so two machines can differ.
- **Age:** escapes keep arriving after a build, so only designs whose `Decided:` is more than `--aged DAYS` (default 14) ago count toward escape rates; younger and `pending` ones are left out of escape rates only, and listed apart.
- **Writes** to `review-stats/` beside the roster, never into a repo, in the published dataset's shape (`docs/review-data/design-rounds.json` and the md beside it): per design one row (repo, TD, class, source, reviews, rounds, tokens by model, build-changing per round from reviews and from fact-checks, age, escapes resolved), the aggregates, and the trial. Per class: the **escape rate** is aged `rounds` designs with at least one resolved escape over aged `rounds` designs (a `backfill` record is written only for a design with an escape, so `backfill` designs are listed with their escapes, not rated); **build-changing per round** is the count of findings labelled build-changing in that round, reviews' and fact-checks' apart; rounds and tokens as medians and totals. Publishing a scrubbed copy, as `docs/review-data/` was, is a separate deliberate step.
- **The trial:** reruns the decided rounds ADR's rules over the rebuilt data against each repo's `design-rounds` and `design-rounds-wide`, real labels where a record has them and the total-findings proxy for `unlabelled` rows. Ported from `docs/review-data/trial_rules.py` and `aggregate.py`, which stay frozen, reproducing the published dataset.
- **`--candidates [--since DATE]`** (`DATE` against each entry's `Added:`): the backfill's mechanical half. A design entry is a TD with a record file. It lists ledger entries, live and archived, since the date that carry no `Escaped from:` and either cite one (any citation, listed with where it appears: a header field, the Why, the Fix) or cite a TD whose same-ledger `Part of:` names one (that design offered, the hop shown; one hop, `part_of_raw` through `ledgerboard.parse_part_of`, and a hint: most candidates come from direct citations), and TDs named in `Escaped from:` with no record file. It judges nothing. A repo with no records yet gets nothing from it: its first backfill seeds its design records by hand from its history (as 5 does from the dataset), and later passes find the rest.

**5. Backfill: it writes the missing record files and fields,** so `review-stats` stays one reader.
- **The pass:** after `review-stats --candidates`, a session judges each candidate with 2's question and writes, for each design with an escape and no record, a `docs/reviews/TD-NNN.md` with `Source: backfill` from what the repo holds (its design history, ADR or plan text; a transcript only where it is on the machine), reviews and counts it cannot find written `?`. Mining and judging need judgement: the session may hand them to an agent **only if the person, asked first, agrees**, since they can cost many tokens. One PR per repo.
- **This repo's backfill**, part of TD-204's build:
  - here, `docs/reviews/TD-203.md` (`Source: backfill`, real labels) copied from the rounds ADR's own *Review record*, whose body stays as it is. Its free-text `by` maps to `R<n>`: within a round, every fact-check row is one `fact-check` review (`fact-check` and `fact-check (sonnet)` alike; the last round's read as the closing fact-check), and each model's rows one `design` review, in the order the models ran in that table (sonnet, then fable), a review taking the position of its first row; a merged review's model is `sonnet?` when any of its rows names it, else `?`; a review the table does not show (round 5 has no fact-check row) is not written. agent-cadence has no escapes yet.
  - a ShiftLead PR: `docs/reviews/` records for TD-947, TD-995, TD-1051, TD-909, TD-804 and TD-820 from `docs/review-data/design-rounds.json` and ShiftLead's design history, and `Escaped from:` on TD-960, TD-1128, TD-1095, TD-1129, TD-1031 and TD-854. Left out: TD-935 ← TD-931 (a doc leftover after the build, a build miss by 2's test) and the five "(questionable)" designs.
  - dev-cadence is archived, so its pairs stay in the frozen dataset only.

**6. Where it lives:**
- cadence.md §4.8 *Design review rounds*: "the plan's findings table" becomes the design's record file (1), and the Reviews table is named; §2 gains the `Escaped from:` paragraph (2) and §2.12's list of fields the cadence defines names it; §9.18 lists `review-outcomes`.
- The rounds ADR's rule 6 and rule 10's `adr-template.md` line (where the table lives) are superseded by this ADR when it is decided: its Status line gains one clause, `rule 6 and rule 10's adr-template line superseded by ADR 2026-10-30-review-outcomes.md`, and its body is left byte for byte; `docs/reviews/TD-203.md` is a copy (5). §7.5 gains that partial `superseded` clause as an allowed Status edit, and its list of the ADR's sections loses the *Review record*, now the record file.
- This repo's CLAUDE.md (the layout and decisions lines) and the techlead primer (`docs/briefs/`, `tests/test_briefs_primer.sh`) name `docs/reviews/`; cadence.md §9 names `review-stats/` beside the roster as output, not state.
- `files/docs/adr-template.md`'s `## Review record` heading goes; the record file's template (1) follows *Revisit triggers* as a commented block saying it goes in `docs/reviews/TD-NNN.md`, not the ADR; no new seed file. `tests/test_parity.sh`'s check of the template's headings against §7.5 (its lines 215–219: the expected list and the check's name string) loses *Review record* on both sides.
- `files/docs/procedures/cadence.md` step 3: each finding a row of the design's record file.
- `files/scripts/review_stats.py` (new, SYNC: `sync.sh`'s `SYNC_FILES` and README's file-class table).
- `cadence_config.py`: the key, with an `off`|`on` validator; the seed `files/docs/cadence.toml` gains its commented line.
- `ledger_next_id.py`: the filing question when the key is on; its docstring says so.
- ledgerboard (ShiftLead/ledgerboard): v2.2 adds `escaped from` to `CADENCE_FIELDS` and `SPEC.md`'s list of spec fields; the seed `files/docs/technical_debt.md`'s entry template gains an optional `**Escaped from:**` line beside `Part of` (`tests/test_parity.sh` holds that template and §2.12's list to `CADENCE_FIELDS`).
- `files/docs/cadence-changes.md`: one entry.
- **The builds, filed by the rounds' session (rule 9), in order:**
  1. `ledgerboard#TD-006`: `escaped from` in `CADENCE_FIELDS` and `SPEC.md`, shipped in v2.2 with ledgerboard#TD-005 (Paul).
  2. TD-204 here, blocked by 1: the payload (record files, `review-stats`, the key, `ledger_next_id.py`, the docs) and, unless another build has already vendored v2.2, the vendor with §2.12's list and the seed template in the same PR, since `tests/test_parity.sh` holds §2.12's list to the vendored `CADENCE_FIELDS` in order and the template as a set (so both follow whatever v2.2's `CADENCE_FIELDS` holds, `id take` included); and the TD-203 record copy (5). The rounds ADR's Status clause (6) lands here too, with §7.5's edit. TD-204's `Blocked by:` names `ledgerboard#TD-006`.
  3. `shiftlead#TD-NNN`, blocked by 2: the `agent-cadence bump` PR, running its `vendor_ledgerboard.sh <tag>`, with `ao td reserve`'s line and its `review-outcomes` reader.
  4. `shiftlead#TD-NNN`, blocked by 3: the backfill PR (5); its agent, if any, only with the person's leave.

**7. Tests:**
- `tests/test_parity.sh`'s template-headings check follows 6.
- `tests/test_cadence_config.sh`: the key's default, a repo value, a bad value as a `--check` error, and the seed parity.
- `ledger_next_id.py` prints the line last on stderr with the key on, stdout unchanged, on exit 3 and under `--json` too, and stays silent with it off, on `--claim` and on exit 2.
- ledgerboard's own tests (its release): `Escaped from:` in a ledger with a `Fields:` line raise no `undeclared-field`; `tests/test_parity.sh` passes with the new field.
- A new `tests/test_review_stats.sh`, over fixture repos on a temporary roster: a record file's tables are read and a review with no findings rows is clean; `unlabelled` rows count toward the proxy only; `Escaped from:` resolves for `TD-NNN` and a mixed-case `<repo>#TD-NNN`, and an unresolved and an out-of-scope value are each listed and not counted; `--repo` limits the scope; a `pending` or young design is listed apart from escape rates; an `Escaped from:` added to a fixture after a first run is counted by the second; `--candidates` lists a citing defect without the field, a defect citing only a build whose `Part of:` names a design (with the hop), and a design TD with no record, and `--since` compares `Added:`; a `Decided:` date and `pending`; tokens summed by model; the port's output over one fixture roster matches the frozen `docs/review-data/trial_rules.py` and `aggregate.py` run over the same json, copied with it into a temporary directory (they read and write beside themselves, so never in `docs/review-data/`); the output lands beside the roster and nothing is written into a repo.

## Options

- **The table stays in the plan, with a `Plan:` field on the design TD:** most of ShiftLead's designs have no plan file to hold it, so the backfill would have to create and name plan files; one more ledger field. Not chosen (Paul, 2026-10-30).
- **Standardize where designs are written:** ShiftLead's living design would have to be split per TD. Not chosen.
- **Run the frozen `trial_rules.py` and `aggregate.py` in place of a port** (R5): `docs/review-data/` is this repo's, not the payload, so a pinned consumer has no copy to run. Not chosen.
- **`review-stats` also reads the frozen dataset's json:** a second input format kept for good; the backfill writing record files keeps one reader. Not chosen (Paul).
- **Two more columns in the findings table** (TD-204's first draft): a clean review leaves no row. Not chosen.
- **The key also gates the Reviews table:** it saves a few dozen tokens a review and loses the cost data for good. Not chosen (Paul).
- **No key, the question always in §2:** a cost for repos that do not want the data. Not chosen (Paul).
- **A cross-repo `Part of:`** (`<repo>#TD-NNN`, skipped where the repo is absent): a parent waits on its open parts, so a design here would stay open on another machine's build, and unreadable forever where that repo is not checked out; `Blocked by:` already carries a cross-repo dependency. Not chosen (Paul, 2026-10-30).
- **Suggesting cap values from the data:** fewer than 100 designs, almost none labelled; it would fit noise. Later, not now.

## Decision

Paul, 2026-10-30, after the end-of-rounds item: `Go`. The rounds ended by the stop rule after round 4 of 6; the fixes no review read (F84–F91) go to the builds. Filing the builds then found TD-205 at odds with TD-188 (`Id take` replaces `Taken by`, decided 2026-10-28): TD-205 is superseded by TD-188, and `escaped from` rides ledgerboard v2.2 with TD-005 (Paul).

## Consequences

- Every design's cost becomes visible per review and per model, and "would a cheaper model or one more round have caught it?" becomes answerable as records and escapes accumulate.
- A repo with the key off still records the Reviews table, so turning the key on later loses only the filing question's past answers, which the backfill recovers.
- `backfill` records may be lower-grade (counts, not labelled findings; TD-203's is fully labelled); the trial says how many of its designs are `backfill`.

## Open questions for the rounds

1. ~~Does the runner report the exact model id and tokens?~~ Fact-check (round 1): yes in Claude Code. Adopted in 1.
2. ~~Which citations does `--candidates` list?~~ Any, with where they appear (R4). Adopted in 4.
