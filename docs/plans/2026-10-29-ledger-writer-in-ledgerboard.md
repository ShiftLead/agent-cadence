# ADR 2026-10-29: TD-173's ledger writer lives in ledgerboard; agent-cadence's `ledger.py` is the CLI over it

**Status:** decided 2026-10-30 by Paul ("file it"; eleven review rounds, Sonnet and Fable alternating, converged 2026-10-29)
**Date:** 2026-10-29
**Related:** TD-173 and its builds TD-197 to TD-202, TD-188; ledgerboard#TD-005, ledgerboard#TD-004

Review record (revision 11):
- Shape agreed by Paul: "ledgerboard is the right home".
- Round 1, a fact-check by Sonnet: no false claims; four gaps closed.
- Round 2, a design review by Fable: "sound with changes"; all of its changes applied.
- Round 3, a fact-check by Sonnet: three false claims and four partly-wrong ones corrected, with real-ledger counts added.
- Round 4, a design review by Fable: "not converged"; three build-changing findings and three definitions, all applied.
- Round 5, a fact-check by Sonnet: four errors and two contradictions in revision 4's additions, all corrected.
- Round 6, a design review by Fable: "not converged, narrowly"; two build-changing gaps and three one-line definitions, applied.
- Round 7, a fact-check and whole-plan consistency read by Sonnet: one gap, one miscount and five consistency items, fixed.
- Round 8, a design review by Fable: "not converged, narrowly"; one undefined step and one unnamed risk, both fixed.
- Round 9, a fact-check and consistency read by Sonnet: nothing false; one gap and three wording items, fixed.
- Round 10, a design review by Fable: "not converged, narrowly"; one definition (the edit actions' output form), added.
- Round 11, a consistency check by Sonnet: the round-10 sentence contradicts nothing; one clarification (commands on a refused entry), added below.

## Context

- **TD-173** (agent-cadence, design agreed 2026-10-28): every routine ledger write goes through a helper, and the gate refuses a changed entry file the helper would not have written.
- **PR #20** (agent-cadence, open) files the builds TD-197 to TD-202, with the renderer in `ledger.py`. This plan replaces that placement.
- **ledgerboard** (v2.1) owns the formats (agent-cadence cadence.md §2.12). Two consumers vendor it byte-for-byte. It is pure functions over text.
  - It parses entries but writes none. Its board writers (`item_line`, `edit_line`, `decided_line`, `Refused`, SPEC *Edits*) refuse any edit whose re-parse does not read back what was meant.
  - `header_block()` silently drops a header line that is not a field and keeps only the first of a repeated field. `entries()` returns no section text.
  - The repo is public: its fixtures are invented, never copied from a real ledger.

## ledgerboard v2.2 (the format: pure text in, text out)

**Entry model, written into SPEC as a new *Ledger entries and their edits* section** (today's `## Edits` covers board items only):
- **Heading:** `## TD-NNN: title`.
- **Header block:** the lines after the heading, up to the first blank line. Every line in it must be a `**Name:** value` field, and a field name may appear once.
- **Body:** everything after the header block, as *sections*. A section's *lead* is the bold opening of its first paragraph. A section is a paragraph whose first run is `**Name**` or `**Name:**` (for example *Why*, *Fix*, *Done when*, *Related*, *Ask*), plus every following paragraph up to the next paragraph that opens that way. So a Fix keeps its bullet list.
  - Section names match by `field_key`, with the colon optional.
  - A lead with a qualifier (`**Fix (to design):**`, `**Fix, in slices a PR each:**`, a dated `**Note (2026-09-10, …):**`) is its own section, matched only by its whole text, so `edit` never mistakes it for *Fix*.
  - A body lead named like a header field (`**Location:**`, `**Status:**` in a body, as 71 and 18 ShiftLead entries have) is a body section, never a field: only the header block holds fields, and only `entries()`'s four lifted fields are read from below it.
  - `**Done when**` and `**Done when:**` are one name (both occur: 13 and 0 here, 681 and 163 in ShiftLead); `canonical()` keeps whichever the file has, since the body is byte for byte.
  - Text before the first bold-led paragraph is an unnamed lead section, kept verbatim.
- **Canonical form:**
  - the heading;
  - one blank line;
  - the header block in this order: `Priority, Type, Added, Owner, Kind, Status, Taken by, Id take, Blocked by, Waits, Part of, Location`, then any other field (ShiftLead's header `Resolved`, `Pickable` and `Was` among them) in the order the file had it. `Owner`, `Kind`, `Taken by` and `Waits` are not cadence fields (`CADENCE_FIELDS` holds seven today, and eight once v2.2 adds `Id take`); their place in the order is a rendering convention SPEC states, not a declaration. `Resolved` is not in the order: the archived form writes it as a body section (below). For `canonical()` and `fmt`, a header `Resolved` (36 ShiftLead archived entries) is just another field, kept as found;
  - one blank line;
  - the body, byte for byte, with line endings normalised to `\n` and one trailing newline. Normalisation comes first: `canonical()` normalises the input's endings, then parses and renders, and its refusal rule compares against the parse of the normalised input (a CRLF file would otherwise always differ, since `FIELD_RE` keeps a trailing `\r` in a value).
- **`Id take` is defined in this release** (agent-cadence TD-188's step 1: in `CADENCE_FIELDS` and SPEC; bundled by Paul's decision, 2026-10-29: "bundle the take id"), so the canonical order does not change again in a later minor.
- **A change to the canonical form is a minor release.** Each consumer absorbs it with its own `fmt` PR when it vendors that release.

**Functions:**
- `canonical(text) -> str`: the entry in canonical form. It presumes a file `v2_problems()` passes (exactly one `## TD-n:` heading, matching its file name) and refuses any other. It renders from the raw header lines, not only the parsed dict: the twelve ordered fields are spelled as SPEC lists them, and any other field is written as the file spells it, so the result is idempotent. It is **refused** for an entry whose header block holds:
  - a line that is not a field (a wrapped Location, for instance);
  - a repeated field;
  - or a field written below the header block that `entries()` would lift.

  Rendering from the parse would lose or duplicate those lines, so the person fixes them by hand. Refusal rule: the body text is unchanged and the header dict is unchanged, or the result is refused.
- `entry_text(id, title, fields, sections) -> str`: a new entry in canonical form.
- `edit_entry(text, action, *, today, …) -> str`, with `ENTRY_ACTIONS`, mirroring `edit_line` and `EDIT_ACTIONS`. Each action is refused unless its re-parse reads back exactly the intended change, with nothing else changed. **Every action returns its result in canonical form** (`canonical()` of the edited text), so a write by any command passes the gate's canonical test; "nothing else changed" is judged by re-parse, not by bytes, and an action on an entry `canonical()` refuses is refused the same way.
  - **`set`:** set or remove fields; an empty value removes one.
  - **`note`:** appends ` YYYY-MM-DD: words` to the Status line. It is refused if the Status's first word would change or `words` holds a newline, because a field is one line (§2.12).
  - **`edit`:** replaces one named section's paragraphs. A named section the body does not have is **added**: after the first *Why* when there is one, else before whichever of *Done when* and *Related* comes first, else at the end of the body. That is what `reopen`'s follow-up `edit fix` needs, since archiving removed the Fix.
  - **`archive`:** the archived form, following §2.8.
    - Resolved: the Status becomes `Resolved YYYY-MM-DD: why` (a form §2.8 does not give today; SPEC defines it), and **Fix** is replaced by one line, `**Resolved:** YYYY-MM-DD (PR #n) — <pointer>`.
      - `pr` is an int or None. With None the parenthesis is left out; it is never free text (§2.8's forge rule).
      - The pointer, to the doc, test or code that now carries the lasting content, is optional and goes on the same line after ` — `, so ShiftLead's `RESOLVED_LINE` keeps reading it as the resolved text.
      - With `pr` None, a pointer holding `#<digits>` is refused: ShiftLead's `ANY_PR` fallback would read that number as the PR.
      - With nothing lasting to promote, `as_is=True` keeps Fix and adds the `**Resolved:**` line after the whole Fix *section* (after its last paragraph, before *Done when* or *Related*).
    - An entry with no section named exactly *Fix* (7 live and 372 archived in ShiftLead; a `Kind: decision` entry often has none, and five live entries have only a qualified lead such as `**Fix (to design):**`) gets the `**Resolved:**` line as a new section at the end of its body, with or without `as_is`. ShiftLead's `RESOLVED_LINE` reads it wherever the body writes it. A qualified Fix lead is left as it is.
    - A header `Resolved` field is **removed** when `archive` writes the body section. On `reopen` it is **moved** into a body `**Resolved:**` section, never deleted: 36 ShiftLead entries hold their only resolved record (date, PR, pointer) there. Both readers prefer it over the body line (ShiftLead's `queue.py` lifts the body line only when no header field exists; agent-cadence's `_resolved_dates` matches the header line first), so leaving it would report the old date. SPEC says the archived form carries `Resolved` only as the body section.
    - An entry that already has a `**Resolved:**` section (one reopened and archived again) has that section **replaced**, never a second one added: both readers take the first match (ShiftLead's `queue.py`, agent-cadence's `_resolved_dates`), so a second line would report the old date and PR.
    - An entry with no Status field (19 in ShiftLead's archive) gets one, for `archive` and for `note`. From `note` it reads `**Status:** YYYY-MM-DD: words`.
    - Superseded: the Status becomes `Superseded YYYY-MM-DD by TD-n: why`, and Why and Fix stay as written (§2.8).
    - Both consumers already read `**Resolved:**` from archived bodies (agent-cadence's `_resolved_dates`, ShiftLead's `queue.py`), so SPEC adopts the form as *the archived entry*, and §2.8 points there.
  - **`reopen`:** not an inverse, since archiving dropped the Fix. The Status becomes `Open YYYY-MM-DD: why — was: <old Status value>` (added if the entry had none, and then without the `— was:` clause). The `**Resolved:**` section stays as history, and Fix is not reconstructed: the caller follows with `edit fix`. The CLI moves the file back out of `archive/` (`git mv`, and `relink()` one level up); agent-cadence's `archive_loss_flags` then names the move (`archive-reopened`, ℹ), which fires only on that move.
  - **`renumber`:** rewrites the heading's id.
  - **`rename_ref`:** rewrites `old` to `new` in `Blocked by` and `Part of`.
- **No `field_problems()`.** The writers refuse only on form. Validity (vocabulary, `Blocked by` and `Part of` items, cross-repo resolution, cycles) stays in `check()`/`pickable()`, which the caller runs on the result, so there is one copy of each format rule.
- **`check()` gains one relationship rule in v2.2:** given `old=`, an id that has left the ledger while an open entry is still `Part of` it is an error, `archive-open-parts`, naming the parts. Today's only flag for that case is `part-of-archived`, ℹ, on the part. ShiftLead archives entries too, so the rule belongs in the format.
  - It must escape `check(old=)`'s demotion, which turns a flag into standing ℹ unless its id is an entry whose header changed. The parent has left the ledger and the part's header did not change, so either way the flag would be demoted. Like `rank`, the kind is never standing: it is computed only from the move between `old` and the new text, so every instance is this edit's.
- **Dates are passed in**, as `edit_line(today=)` takes them. Ledger writes are ordinary PRs, not tool edits under agent-cadence §4.5, so there is no commit-subject helper.
- **Not here:** relative-link depth on archive. That needs the file system, and `split()` already leaves it to the consumer (agent-cadence's `relink()`). v1 ledgers are out of scope too: every writer refuses a v1 ledger with "split first".

**Release:**
- Tests on invented fixtures in a new case type, `fixtures/ledger_edit/`, with **`fixtures/run.py` extended to run it** (today `cases()` globs only `ledger/*.md`, `board/*.md` and the board's `edit/cases.json`). `release.sh` runs `fixtures/run.py`, and `vendor_ledgerboard.sh` copies `fixtures/` whole, so both consumers' `tests/ledgerboard/run.py` run the new cases once they vendor v2.2 (with `MANIFEST` regenerated). The cases cover:
  - `canonical` is idempotent;
  - each refusal fires;
  - each action round-trips;
  - section extents (a Fix with bullets, a qualified lead, an unnamed lead);
  - `check()`'s new `archive-open-parts` rule, including that it is never standing;
  - `archive` and `note` on an entry with no Status, `archive` on an entry with no Fix or only a qualified one, `archive` after `reopen` (one `**Resolved:**` section), `archive` on an entry with a header `Resolved` (removed), and `edit fix` after `reopen` (the section added), and `reopen` on an entry with a header `Resolved` (moved to the body);
  - CRLF input.
- **v2.2 is a minor release.** It reads everything v2.x wrote, and it writes files that v2.1 reads.
- One sitting in ledgerboard ships TD-004 (the header names agent-cadence), TD-005 (this writer) and TD-188 step 1 (`Id take`), then `release.sh 2.2`, its PR, and `release.sh --tag 2.2`.

## agent-cadence `ledger.py` (the CLI: side effects and policy)

**Commands:** `fmt [TD-n…] [--check]`, `new`, `set`, `note`, `edit`, `archive`, `reopen`, `renumber`.
- Each reads files, calls ledgerboard, then **validates by running `ledger.py --check --since`'s own flag set**: `L.check` (ledgerboard's `check()` with the roster resolver, and the rank file), `archive_loss_flags` and the id flags, plus `prose_wait_flags`, which the gate does not run. That is a superset of the gate's `ledger` row, which runs `L.check` without the rank file plus `archive_loss_flags` (with the id flags in its separate `ledger_ids_check`, open PRs only). It refuses the write on:
  - every error the gate counts. `cross-repo` is printed as a note, never a refusal, as `ledger_edit_check` treats it;
  - **two additions of the CLI's own**, each about the entry being written, which a tool should not produce though a person's hand edit may:
    - a cross-repo id that **this command introduces** (`new`, `set --blocked-by` or `--part-of`, `renumber`) whose roster repo *was* read and has the id in neither file. `Roster.resolve()` drops this case today (it does not pass `Roster.state`'s `missing`, TD-153, through), so the CLI calls `Roster.state` itself for the ids it adds. Ids already in the entry stay a `cross-repo` note, as at the gate, so a stale clone or a cross-repo entry still in review never blocks a `note` or an `edit`. The refusal carries `state()`'s `why` (it names the clone and its source) and says to fetch there; the reads are offline, so a clone fetched before the other repo merged reads as missing. A hand edit in canonical form still passes the gate, which tests form only, so no refusal is a dead end;
    - a wait written in prose (`prose_wait_flags`, TD-166 and TD-172), which `ledger.py --check` reports as ℹ and the gate's row does not run at all.
- They own:
  - the id from the counter (`ledger_next_id.py`). Until TD-188's consumer side lands, `new` writes only the hashed `Taken by`; after it, only `Id take`;
  - roster resolution;
  - `relink()` then `git mv` for archive, and the reverse for reopen (`relink()` is general in source and destination but has only been used by the split, so TD-200 tests it on both moves);
  - the PR number only as the forge returned it (§2.8);
  - for `renumber`: claim the new id, `git mv` the file (`v2_problems()` requires name = heading), `rename_ref` across this ledger, `set_rank()` on the rank file, and *list* references in prose and in other repos for the session to judge.

**The gate (TD-201):**
- An entry counts as changed when its **file bytes** differ from REF, or it is new, including a file new in `archive/`. Today `--since` compares the header dict (`ledgerboard.py` `check(old=)`), which would exempt a reordered field and any body edit.
- The test is `canonical(text) == text`. A refused `canonical` is an error that names the hand fix.
- The file-bytes rule decides only this canonical test. The field checks keep ledgerboard's header-dict `old=` comparison, so the first `fmt` PR, which changes every file once, is not judged on every standing field flag.

**Tests:** in agent-cadence's own `tests/`, every entry in this repo's ledger and archive round-trips through `canonical`, or is named as refused.

**What the first `fmt` meets (counted 2026-10-29):** agent-cadence's 19 entries have no entry `canonical()` would refuse. ShiftLead's 1128 have 12: 11 with a wrapped line in the header block (live TD-943; archived TD-022, TD-623, TD-625, TD-627, TD-629, TD-630, TD-940, TD-941, TD-944, TD-950) and one with a field below the header (archived TD-126). Those are ShiftLead's hand fixes, in its own `fmt` PR. Until an entry is fixed, every command on it is refused with the same hand-fix message the gate gives, so ShiftLead hand-fixes the 12 before its first routine write to them. A command that rewrites references across the ledger (`renumber`) stops at a refused entry and names it, writing nothing.

**Scope:** v2 only; v1 is refused with "split first".

## ShiftLead

After vendoring v2.2, ShiftLead writes through ledgerboard directly or calls `ledger.py`, its choice. agent-cadence's TD-202 files that as a new shiftlead entry (its id from ShiftLead's own counter); TD-202 itself is the agent-cadence entry for the rule.

**Note:** ShiftLead's ledger declares `Fields:`. Today an undeclared `Taken by` is an error there under `--since`, which is why `Id take` ships as a cadence field in v2.2. Until agent-cadence's `new` writes `Id take` (TD-188's consumer side), it writes `Taken by`, so in ShiftLead `new` would refuse its own entry: ShiftLead declares `Taken by` or waits for that before using `new`. The shiftlead entry TD-202 files says so.

## Entries and order

1. **ledgerboard TD-005** (the writer and SPEC section; filed as ledgerboard#29), with an id from ledgerboard's own counter (`origin/cadence/ledger-ids`). It goes in as a PR in ledgerboard, since sessions can't file there through ShiftLead, and **Paul merges it first**.
2. **Then** PR #20 is reshaped and merged.
   - TD-197 becomes "vendor v2.2 and add `fmt`", `Blocked by: ledgerboard#TD-005`. It also points agent-cadence cadence.md §2.8 at SPEC's archived entry, and states the canonical field order in §2.12, with one `cadence-changes.md` entry for both.
   - TD-202 keeps its own `cadence-changes.md` entry, for the rule.
   - TD-198 to TD-200 keep their CLI scope and drop the rendering and validation text.
   - TD-201 takes the file-bytes rule.
   - TD-202 adds the note that whole-file rewrites conflict more often, so §2.5's "rebase right before merge" matters more.
   - **Ordering is a nicety, not a gate.** Neither the precheck (which runs ruff, the suite and the publish gate) nor the cadence check's ledger row fails on a cross-repo blocker it cannot resolve: the row lists it in its note (`check_cadence.py` `ledger_edit_check`). Only a hand-run `ledger.py --check --since` exits 1 on it. Merging TD-005 first just means #20's blocker resolves cleanly from the start.
3. **A session Paul starts in ledgerboard** runs the sitting: TD-004, TD-005, TD-188 step 1, then v2.2. No team has a ledgerboard seat, and granting one is ShiftLead org config, which is slower than the build.
4. agent-cadence TD-197: `vendor_ledgerboard.sh v2.2`, then `fmt`.
   - The first `fmt` over the ledger lands as its own PR, and says that every entry's file changes once.
   - ShiftLead's history reads are unaffected: they keep only added and deleted files (`_dir_events`), and `fmt` modifies. The only effect is one mtime-triggered re-read of the ledger.
5. TD-198, TD-199 and TD-200 (in any order), then TD-201, then TD-202.
6. ShiftLead re-vendors v2.2 on its own schedule.

## Settled by the rounds

- The archived form goes in the format, minus the link depth.
- One validator for format rules: `check()`, run by the caller, plus one new rule (`archive-open-parts`). The CLI refuses every error the gate counts, plus two cases on the entry it writes: an id missing from a roster repo that was read, and a wait written in prose.
- v2.2 is a minor release, with the canonical order fixed now, `Id take` included.
- A Paul-started session in ledgerboard builds TD-005.
