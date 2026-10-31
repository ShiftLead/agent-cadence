# Technical Debt

Known issues, compromises, and deferred work. Add an entry any time a problem is identified but not immediately fixed — no exceptions, however small (see [`cadence.md`](cadence.md) §2). Once this file is split into `docs/ledger/` (`scripts/ledger.py --split`), every entry is written with `scripts/ledger.py` — `new`, `set`, `note`, `edit`, `archive`, `reopen`, `renumber` — never by hand (§2.12).

**This file holds open work only.** The summary table below lists exactly the entries that have a body in this file — one row each, no history. When an entry is fully resolved, move the whole body to [`technical_debt_archive.md`](technical_debt_archive.md), delete its summary row, and replace **Fix** with the resolution date plus a pointer to whichever doc/code now carries the lasting content. An entry that is only *partly* resolved stays here, with what shipped and what remains spelled out in its **Status**.

The format is defined once in ShiftLead/ledgerboard's [`SPEC.md`](https://github.com/ShiftLead/ledgerboard/blob/main/SPEC.md); `scripts/ledgerboard.py` reads it.

IDs are `TD-` plus a zero-padded three-digit number, assigned in order and never reused. Priority is a field, never part of the ID.

An entry's fields are the `**Name:** value` lines right under its heading, up to the first blank line (cadence.md §2). To add this repo's own fields, declare their values on one line here, e.g. `Fields: Owner = grinder | designer; Kind = build | design-first` — `scripts/ledger.py --list --owner grinder` and `--fields` then read them.

---

## Summary

| ID | Title | Priority | Status |
|----|-------|----------|--------|

---

<!-- Entry template:

## TD-001: What is wrong (or wanted), in plain words a reader who has not seen the code can follow — the behaviour, not the function (cadence.md §2.3)

**Priority:** High | Medium | Low
**Type:** (optional) debt | feature — omit for debt; within a Priority, debt is picked first (cadence.md §2)
**Added:** YYYY-MM-DD
**Status:** Open
**Blocked by:** (optional) TD-NNN or <repo>#TD-NNN, … then decision (<who>) and a pointer — omit when nothing blocks it; pickable is derived (cadence.md §2)
**Part of:** (optional) TD-NNN — the one parent in this ledger (a design, for its builds); the parent waits on its open parts, so it never lists them in its Blocked by (cadence.md §2.4)
**Location:** `path/to/file.py` (function/section)

**Why:** what's wrong, how it was found, and the reasoning — future sessions need the why, not just the symptom.

**Fix:** concrete direction(s), and what would count as done.

**Related:** other TDs, PRs, decision docs.
-->
