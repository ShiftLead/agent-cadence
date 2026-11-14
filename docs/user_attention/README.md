# User Attention Board — agent-cadence

Ledgerboard: 3
Swept: 2026-09-22 (kmaster, quick)

People: Paul

Items that need Paul to act or decide, plus in-flight work parked by a session. Sessions add
entries **the moment they arise** and close them when handled — never delete (see
[files/docs/cadence.md §3](../../files/docs/cadence.md#3-never-strand-work) — the system this
repo distributes, dogfooded here). Keep this board small — durable debt belongs in
[the ledger](../ledger/README.md).

This directory is the live board for this repo (ledgerboard v3.0, TD-263): one file per item, `<id>.md`, and
closed items under `archive/<YYYY-MM>/`. `files/docs/user_attention/README.md` is the *template* `adopt` seeds
into a new repo. The item file's form is ShiftLead/ledgerboard's `SPEC.md` (*The item file*); write and edit an
item only through `files/scripts/board_edit.py` (`add`, then `done`, `snooze`, `due`, `decide`, `reply` by
`--id`), never by hand (cadence.md §3.3–§3.5).

Kinds: `decide | act | look | watch | fyi` — `decide`/`act` (or no kind) are the person's to-do, and so is
`look`, a live look the person is asked to make; `watch` is a session's own re-check, its check-by date as
`Due:`; `fyi` carries no `Due:` and never reaches the SessionStart line. An item overdue 14 days or more
belongs in the ledger: ledger it and close it here (cadence.md §3).

A `decide` carries its `Answers:` (the recommended one marked `(default)`) and a detail block in plain English
for someone who has not read your session: **Context**, **Question**, **Caveats** (when there are any),
**Recommended** and **Otherwise**. The person's answer is recorded by `board_edit.py decide`, never by hand.
Closing an item (`board_edit.py done --why <why>`) moves its file into `archive/`; nothing is deleted.

`Due:` is optional but recommended — the SessionStart due-items line surfaces items whose date has arrived
(TD-7). **To snooze, hide the item until a date:** `board_edit.py snooze --to <date>` writes `Hide until:`,
and `Due:` stays the real deadline; `board_edit.py due --to <date>` moves the deadline itself. Undated items
surface in `/attention`'s full report.
