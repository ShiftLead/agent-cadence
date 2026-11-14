# User Attention Board

Ledgerboard: 3

Items that need the user to act or decide, plus in-flight work parked by a session. Sessions add items **the moment they arise** and close them when handled (never delete — closing moves an item's file into `archive/`). Keep this board small — durable debt belongs in the ledger; this board is only "a human must act or decide."

This directory is the board (ledgerboard v3.0): one file per item, `<id>.md`, written and edited only through `scripts/board_edit.py` (`add`, then `done`, `snooze`, `due`, `decide`, `reply` by `--id`), never by hand. Closed items live under `archive/<YYYY-MM>/`. `docs/user_attention.md` beside it is a fixed stub that names this directory. The item file's form is defined once in ShiftLead/ledgerboard's [`SPEC.md`](https://github.com/ShiftLead/ledgerboard/blob/main/SPEC.md) (*The item file*); the `scripts/ledgerboard/` package reads it.

All conventions — the item's fields, `Due:` dates and snoozing, answers and decisions, the `Swept:`/`Swept-deep:` sweep stamps (lines of this file) — live in [docs/cadence.md §3](../cadence.md#3-never-strand-work). That file is SYNC (it reaches every consumer by its pin); this skeleton is SEED (yours, never overwritten), which is why the explanations do not live here (agent-cadence TD-17).

Kinds: `decide | act | look | watch | fyi` — `decide`/`act` (or no kind) are the person's to-do, and so is `look`, a live look the person is asked to make; `watch` is a session's own re-check, its check-by date as `Due:`; `fyi` carries no `Due:` and never reaches the SessionStart line. An item overdue too long (see cadence.md §3) belongs in the ledger: ledger it and close it here. A `look` carries the fixed pair `Answers: Works | Not right: <what>`; a `watch`, an `act` and an `fyi` carry none (cadence.md §3.5).

Put a `People:` line in this file naming whose board it is — `People: alex`, or several separated by `, ` — so `scripts/board_edit.py decide` knows who answers (with one name it is the default; without the line every answer needs `--by`).
