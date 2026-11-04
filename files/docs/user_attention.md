# User Attention Board

Items that need the user to act or decide, plus in-flight work parked by a session. Sessions add entries **the moment they arise** and close them when handled (never delete — see below). Keep this file small — durable debt belongs in [technical_debt.md](technical_debt.md); this board is only "a human must act or decide."

All conventions — entry format and the `<host>` semantics, `Due:` dates and snoozing, the `Swept:`/`Swept-deep:` sweep stamps — live in [docs/cadence.md §3](cadence.md#3-never-strand-work). That file is SYNC (improvements reach every consumer on re-sync); this skeleton is SEED (yours, never overwritten), which is why the explanations do not live here (agent-cadence TD-17).

The format is defined once in ShiftLead/ledgerboard's [`SPEC.md`](https://github.com/ShiftLead/ledgerboard/blob/main/SPEC.md); the `scripts/ledgerboard/` package reads it.

Format: `- [ ] YYYY-MM-DD (session <first-8-of-session-uuid> on <host>, or n/a) — what's needed. Context: TD-NNN (another repo's: <repo>#TD-NNN) / PR #N / branch. Due: YYYY-MM-DD.` — ledgerboard's, in outline (cadence.md §3.3): write an entry with `scripts/board_edit.py add`, never by hand.

Under the line, indented two spaces, a detail block of sub-bullets in plain English for someone who has not read your session: `**Context:**` (a few sentences; nested bullets where a list is clearer), `**Question:**`, `**Caveats:**` (when there are any), `**Recommended:** <the default> — why. **Otherwise:** <each other answer> — when.` Always on a `decide`; on an `act`/`look` whenever the line alone does not say what to do; fields stay on the line (cadence.md §3.3, TD-084).

Kinds: `decide | act | look | watch | fyi` — optional, one word before the date: `- [ ] decide YYYY-MM-DD (…`. `decide`/`act` (or no word) are the person's to-do, and so is `look`, a live look the person is asked to make; `watch` is a session's own re-check, its check-by date as `Due:`; `fyi` carries no `Due:` and never reaches the SessionStart line. An item overdue too long (see cadence.md §3) belongs in the ledger: ledger it and close it here (cadence.md §3).

A question ends with its answers after `Due:` — `Answers: <answer> | <answer>.`, the one you recommend marked `Answers: <answer> (default) | <answer>.` The person's answer is appended by `scripts/board_edit.py decide`, never by hand: `Decided: <text> (by <person>) (YYYY-MM-DD).` — `<person>` is who answered, one of the `People:` line's names. A `look` (the person is asked to look at something live) ends with the fixed pair `Answers: Works | Not right: <what>.`; a `watch`, an `act` and an `fyi` carry none (cadence.md §3.5).

Closing an entry never deletes it: `scripts/board_edit.py done --why <why>` ticks it and appends `Closed: YYYY-MM-DD — <why>.` A merge conflict here is resolved by keeping both sides; the `done` that leaves 10 or more closed entries also moves them to `user_attention_archive.md`, in the same commit (`board_edit.py archive` does it for a board already over). A new entry is written by `scripts/board_edit.py add` (cadence.md §3.4–§3.5).

Put a `People:` line above the first entry naming whose board it is — `People: alex`, or several separated by `, ` — so `scripts/board_edit.py decide` knows who answers (with one name it is the default; without the line every answer needs `--by`). Snoozing hides an item until a date (`board_edit.py snooze` writes `Hide until:`) and leaves its `Due:` alone; `board_edit.py due` moves the `Due:` (cadence.md §3).

## Needs the user

- (none)

## In-flight (parked by a session)

- (none)
