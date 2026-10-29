# Technical Debt — agent-cadence

Ledgerboard: 2

Known issues, compromises, and deferred work for the agent-cadence repo itself (dogfooding the
system this repo distributes — decided by Paul 2026-08-08, plan doc
dev-cadence's private plan *2026-08-08-automation-and-sharing*).
Add an entry any time a problem is identified but not immediately fixed. See
[`files/docs/cadence.md`](../../files/docs/cadence.md) §2 for the ledger rules this directory follows.

**One file per entry (TD-160, ledgerboard v2):** an open entry is `TD-NNN.md` here; a fully
resolved one moves, by `git mv`, to [`archive/`](archive/). A partly resolved one stays, with
what shipped and what remains in its **Status**. There is no stored summary table:
`python3 files/scripts/ledger.py --summary` prints it, and `--pickable` the pick order. The
rank file (`rank.yml`) is the person's order of the cards.

Note: `files/docs/technical_debt.md` is the *template* seeded into consumer repos; THIS
directory is the live ledger for this repo. It was split from `docs/technical_debt.md` and
`docs/technical_debt_archive.md` on 2026-10-28 (`ledger.py --split`, TD-160 step 5); each
entry's history before then is in those two files' logs.

*(Numbering: entries TD-1…TD-28 predate the zero-padded `TD-NNN` convention and keep their
original spelling — 70 references to them are embedded in the shipped `files/**` payload
and its tests (174 repo-wide), and renumbering would push a cosmetic diff to every
consumer. Entries from TD-029 on are padded.)*

## History

- TD-22 and TD-23 were assigned during the 2026-08-12 review of PRs #41/#44 in the private dev-cadence repo, but both were
  fixed in those PRs before this ledger landed — the numbers are retired unused; the audit
  trail lives in the PR comment threads.
- TD-037 was filed by PR #89 in the private dev-cadence repo (written as TD-036 before its #93 took that number). TD-038…TD-058
  were filed by the 2026-09-22 design review.
- **Design review 2026-09-22 — entries TD-038 to TD-058** (a block of the old archive,
  moved here at the split): filed from a full design review (docs read by the session;
  scripts, bash tooling and tests audited by three Opus agents, high-severity findings
  reproduced by hand). Grouped: dogfooding gaps (038, 047), board scale (039), audit gaps
  (040, 052), check_cadence (041), portability and silence (042, 043, 044, 050, 058), parity
  and tests (045, 046), distribution (048, 056, 057), docs (049, 051, 053), data loss (054,
  055). TD-046 was the one entry still in the live ledger when this note moved to the archive
  (2026-10-01), the other twenty archived by then.
