# Design-review rounds on this machine: data for the max-rounds defaults

Extended 2026-10-30 from 50 to 97 designs (read-only research; machine-readable twin `design-rounds.json`; aggregates recomputed by `aggregate.py` in this folder, rerun it after any edit to the json).

**What counts.** A design review is one model reviewing a plan or design before the build (the per-PR pre-merge review is not counted). A **round** is one pass through the models in use, so rounds = reviews / number of distinct models (Sonnet+Fable alternating: 11 reviews = 5.5 rounds; Sonnet alone: rounds = reviews). **Wide** = costly to fix after shipping (another repo, a vendored or published format, an irreversible step); else **in-repo**. A **build-changing** finding is recorded only where the source says it (still only the ledger-writer plan).

**Records by source kind:** adr 10, design-history 49, ledger 1, other 2, transcript 35. Records in the aggregates (mode `rounds`, review count known): 94; kept out: 2 parallel-lens plans (`mode: parallel`, not rounds), 1 designs with no review count (listed in the table, no aggregate).

## Aggregates (recomputed by aggregate.py)

| | designs | reviews: median / max / min | rounds: median / max / min |
|---|---|---|---|
| in-repo | 83 | 7 / 30 / 1 | 4 / 15 / 1 |
| wide | 11 | 7 / 15 / 2 | 3.5 / 7.5 / 1 |

- **Distribution of in-repo rounds** (83): 1 x9, 1.5, 2 x8, 2.5 x6, 3 x7, 3.5 x9, 4 x14, 4.5 x5, 5 x4, 5.5 x5, 6 x6, 6.5, 7 x4, 8.5, 9.5, 10, 15.
- **Distribution of wide rounds** (11): 1, 2 x2, 2.5 x2, 3.5 x2, 4 x2, 5.5, 7.5.
- **In-repo rounds within 3 / 4 / 6:** 31 of 83 (37%) within 3, 54 of 83 (65%) within 4, 74 of 83 (89%) within 6.
- **Wide rounds within 3 / 4 / 6:** 5 of 11 within 3, 9 of 11 within 4, 10 of 11 within 6.
- **Median last review with 3+ findings** (designs with finding counts for at least half their reviews; counts are totals per review, parsed from the hand-backs where no history line gave them, so notes can inflate them): in-repo 67 designs, median review index 5 (= round 3), range 0-26; wide 4 designs, median index 4.5 (= round 2.25).
- **Post-build defects** (designs reviewed before 2026-10-27, so built and aged at least 4 days; a lower bound, found by citation in later ledger entries): in-repo 7 of 67 with a defect read as a design gap, plus 3 with only a "(questionable)" one; wide 2 of 6, plus 0 questionable. In-repo by rounds: <=3 rounds 2 of 24, >3 rounds 5 of 43.
- **Models in the in-repo set:** 71 designs reviewed by two or more models (median rounds 4), 12 by one model (median rounds 4; Sonnet-only plans of 10-09 to 10-15, a Fable-only first draft, and single reviews).
- **Tokens:** 278 reviews carry `<subagent_tokens>`, 25395439 tokens in all (mean 91350 per review where known); the ledger-writer table is in the json.

### First pass versus extension (does the new data move the picture?)

| batch | class | designs | rounds median | rounds max | within 3 | within 4 | within 6 | last 3+ finding: median index (round) | post-build with defect / aged |
|---|---|---|---|---|---|---|---|---|---|
| first pass | in-repo | 39 | 4 | 10 | 12 | 20 | 33 | 6 (3), n=37 | 5 / 23 |
| first pass | wide | 10 | 3.5 | 7.5 | 4 | 8 | 9 | 4.5 (2.25), n=4 | 2 / 6 |
| 2026-10-30 extension | in-repo | 44 | 3.5 | 15 | 19 | 34 | 41 | 4 (2.25), n=30 | 2 / 44 |
| 2026-10-30 extension | wide | 1 | 1 | 1 | 1 | 1 | 1 | n/a (n/a), n=0 | 0 / 0 |

## Per-design table

Review column legend: letter = model (F Fable, S Sonnet, O Opus), number = total findings that review reported (blank = not stated), `*` = verdict READY. Findings are NOT build-changing counts. For the history-sourced designs the numbers come from design-history; for transcript-sourced ones they are parsed from the hand-back text (blank where the hand-back came by message and is not in the transcript). Order: original 50 first, then the added records.

| repo | plan | date | class | source | reviews | rounds | stop | per-review | post-build defects |
|---|---|---|---|---|---|---|---|---|---|
| agent-cadence | 2026-10-29-ledger-writer-in-ledgerboard (TD-173 writer in ledgerboard  | 2026-10-29 | wide | adr | 11 | 5.5 | converged | S F S F S F S F S F S | - |
| dev-cadence | 2026-10-25-pinned-not-synced (TD-129; shiftlead ADR 2026-10-25-shiftle | 2026-10-25 | wide | adr | 4 | 2 | converged |  | dev-cadence TD-147 (2026-10-26); dev-cadence TD-149 (2026-10-26); dev-cadence TD-168 (2026-10-28); dev-cadence TD-174 (2026-10-28); dev-cadence TD-164, TD-158 (2026-10-26/27) |
| dev-cadence | 2026-10-26-public-scrub (amendment 2026-10-28: cut over to agent-caden | 2026-10-28 | wide | adr | 5 | 2.5 | converged |  | - |
| dev-cadence | 2026-10-22-ledger-ids (TD-124) | 2026-10-22 | wide | adr | 5 | 2.5 | converged | S F S F S | dev-cadence TD-145, TD-150, then TD-188 (2026-10-26..28) |
| agent-cadence | 2026-10-29-hard-rename | 2026-10-29 | wide | adr | 4 | 2 | converged | F S F S | - |
| shiftlead | ShiftLead ADR 2026-10-12 | 2026-10-12 | wide | adr | 8 | 4 | converged |  | - |
| dev-cadence | 2026-10-27-ledger-per-entry (TD-160) | 2026-10-27 | wide | adr | n/a | n/a | ? |  | dev-cadence TD-170, TD-176, TD-183, TD-185 (2026-10-28) |
| shiftlead | TD-978 | 2026-10-22 | in-repo | design-history | 19 | 9.5 | other | F10 S13 F10 S9 F8 S1 F7 S12 F5 S1 F1 S* F1 S1 F1 S3* F1 S2 F1 | - |
| shiftlead | TD-1222 | 2026-10-29 | in-repo | design-history | 10 | 5 | converged | F7 S6 F6 S5 F4 S5 F4 S4 F3* S* | - |
| shiftlead | TD-1022 | 2026-10-26 | in-repo | design-history | 11 | 5.5 | converged | F7 S7 F6 S5 F* S7 F* S5 F* S2 S0* | - |
| shiftlead | TD-947 | 2026-10-21 | in-repo | design-history | 14 | 7 | converged | F8 S7 F7 S8 F3 S5 F4 S* F4 S4 F6 S5 F1 S* | shiftlead TD-960 (found by TD-950 live check, 2026-10-22) |
| shiftlead | TD-999 | 2026-10-24 | in-repo | design-history | 8 | 4 | converged | F5 S5 F2* S5 F* S2 F* S* | - |
| shiftlead | TD-991 | 2026-10-24 | in-repo | design-history | 6 | 3 | converged | F7 S* F S2 F S* | - |
| shiftlead | TD-941 | 2026-10-21 | in-repo | design-history | 20 | 10 | converged | F7 S7 F3 S4 F4 S5 F5 S5 F3 S3 F3 S2 F3 S4 F3 S* F2 S4 F1 S* | - |
| shiftlead | TD-1239 | 2026-10-29 | in-repo | design-history | 5 | 2.5 | converged | F4 S* F2 S0* F* | - |
| shiftlead | TD-1143 | 2026-10-27 | in-repo | design-history | 7 | 3.5 | converged | F8 S7 F4 S6 F2 S6 S* | - |
| shiftlead | TD-1129 | 2026-10-27 | wide | design-history | 7 | 3.5 | converged | F6 S8 F2 S4 F7 S* F1* | shiftlead TD-871, TD-959 (2026-10-17..22) |
| shiftlead | TD-1048 | 2026-10-26 | wide | design-history | 7 | 3.5 | converged | F6 S5 F* S4 F* S1 S* | - |
| shiftlead | TD-966 | 2026-10-22 | wide | design-history | 8 | 4 | converged | F6 S2 F2 S* F2 S2 F1 S* | - |
| shiftlead | TD-998 | 2026-10-24 | in-repo | design-history | 6 | 3 | converged | F3 S7 F3 S4* F* S* | - |
| shiftlead | TD-1066 | 2026-10-30 | in-repo | design-history | 5 | 2.5 | converged | F3 S4 F2 S* F* | - |
| shiftlead | TD-1203 | 2026-10-28 | in-repo | design-history | 5 | 2.5 | converged | S17 F8 S3 F* S* | - |
| shiftlead | TD-1187 | 2026-10-28 | in-repo | design-history | 8 | 4 | converged | F6 S5 F3 S4 F2 S3 F S* | - |
| shiftlead | TD-1150 | 2026-10-27 | in-repo | design-history | 5 | 2.5 | converged | F7 S3 F1 S* F0* | - |
| shiftlead | TD-975 | 2026-10-22 | in-repo | design-history | 11 | 5.5 | converged | F9 S13 F8 S7 F5 S5 F6 S3* F2* S* F* | - |
| shiftlead | TD-964 | 2026-10-21 | in-repo | design-history | 7 | 3.5 | converged | S16 F11 S7 F8 S5 F3* S1* | - |
| shiftlead | TD-927 | 2026-10-20 | in-repo | design-history | 11 | 5.5 | converged | F5* S5 F5* S4 F4* S2 F4* S* F1 S* F1* | - |
| shiftlead | TD-931 | 2026-10-20 | in-repo | design-history | 4 | 2 | converged | S17 F8 S8 F8* | shiftlead TD-935 (2026-10-21) |
| shiftlead | TD-926 | 2026-10-20 | in-repo | design-history | 7 | 3.5 | converged | F5 S5 F3 S2 F3* S0* F2* | - |
| shiftlead | TD-924 | 2026-10-20 | in-repo | design-history | 7 | 3.5 | converged | F5 S8 F4 S4 F3* S1* F3* | - |
| shiftlead | TD-909 | 2026-10-19 | in-repo | design-history | 14 | 7 | other | F7 S5 F7 S6 F6 S6 F5 F4 S2 F2 S2 F1 S1 F2 | shiftlead TD-1129 (2026-10-27) |
| shiftlead | TD-1189 | 2026-10-28 | in-repo | design-history | 4 | 2 | converged | S7 F2 S* F* | shiftlead TD-1240 (2026-10-29) |
| shiftlead | TD-993 | 2026-10-24 | in-repo | design-history | 4 | 2 | converged | F S* F S* | - |
| shiftlead | TD-1108 | 2026-10-27 | in-repo | design-history | 13 | 6.5 | converged | F8 S6 F3 S4 F5 S9 F4 S2 F3 S* F3 S0* F* | - |
| shiftlead | TD-986 | 2026-10-23 | in-repo | design-history | 12 | 6 | converged | F9 S10 F5 S7 F4 S8 F3 S4 F2 S1 S2 S* | - |
| shiftlead | TD-1200 | 2026-10-28 | in-repo | design-history | 4 | 2 | converged | F4 S6 F1 S* | - |
| shiftlead | TD-623 | 2026-10-21 | in-repo | design-history | 8 | 4 | converged | F7 S6 F3 S6 F3 S5 F S* | - |
| shiftlead | TD-1119 | 2026-10-29 | in-repo | design-history | 9 | 4.5 | converged | F7 S7 F5 S4 F4 S3 F3 S1* F0* | - |
| shiftlead | TD-1117 | 2026-10-27 | in-repo | design-history | 14 | 7 | converged | F8 S6 F6 S3 F4 S5 F3 S6 F3 S4 S1 F3 S1 S0* | - |
| shiftlead | TD-1240 | 2026-10-30 | in-repo | design-history | 6 | 3 | converged | F3 S2 F2 S1 F* S* | - |
| shiftlead | TD-1149 | 2026-10-27 | in-repo | design-history | 11 | 5.5 | converged | F6 S5 F4 S6 F5 S4 F5 S1 F3 S* F* | - |
| shiftlead | TD-1064 | 2026-10-26 | in-repo | design-history | 12 | 6 | converged | F9 S3 F4 S6 F4 S4 F5 S2 F3 S2 F* S* | - |
| shiftlead | TD-857 | 2026-10-29 | in-repo | design-history | 10 | 5 | converged | F5 S5 F2 S3 F5 S4 F4 S3 F3 S* | - |
| shiftlead | TD-1061 | 2026-10-26 | in-repo | design-history | 11 | 5.5 | converged | F9 S9 F3 S4 F3 S2 F2 S1 F* S1 S* | - |
| shiftlead | TD-1051 | 2026-10-26 | in-repo | design-history | 12 | 6 | converged | F8 S5 F6 S7 F5 S3 F6 S7 F5 S3 F* S* | shiftlead TD-1095 (TD-1079 live check, 2026-10-27) |
| shiftlead | TD-1116 | 2026-10-27 | in-repo | design-history | 7 | 3.5 | converged | F4 S8 F3 S4 F2* S* F2* | - |
| shiftlead | TD-1042 | 2026-10-26 | in-repo | design-history | 9 | 4.5 | converged | F6 S6 F6 S6 F3* S3 F3* S3* F2* | - |
| shiftlead | TD-995 | 2026-10-24 | in-repo | design-history | 9 | 4.5 | converged | F11 S6 F5 S5 F3 S5 F2* S0* F2 | shiftlead TD-1128 (2026-10-26/27) |
| shiftlead | TD-1026 | 2026-10-26 | in-repo | design-history | 6 | 3 | converged | F6 S5 F S4 F S0* | - |
| shiftlead | TD-1009 | 2026-10-25 | wide | design-history | 15 | 7.5 | converged | F6 S6 F2 S7 F3 S3 F1 S2 F1 S4 F* S* F S1 S* | - |
| shiftlead | TD-112 | 2026-10-16 | in-repo | transcript | 14 | 7 | converged | F17 S12 F6 S8 F2 S4 F4 S3 F3 S1 F1 S2 F* S* | - |
| shiftlead | TD-781 | 2026-10-16 | in-repo | transcript | 12 | 6 | converged | F10 S4 F5 S4 F2 S2 F3 S2 F1 S2 F* S0* | - |
| shiftlead | TD-748 | 2026-10-16 | in-repo | transcript | 9 | 4.5 | other | F15 S13 F12 S10 F5 S8 F2 S8 S2 | - |
| shiftlead | TD-730 | 2026-10-16 | in-repo | transcript | 8 | 4 | other | F10 F7 S10 F5 S2 F2 S2 S4 | - |
| shiftlead | TD-801 | 2026-10-17 | in-repo | transcript | 8 | 4 | other | F6 S4 F4 S0 F1 S7 F S3 | - |
| shiftlead | TD-804 | 2026-10-17 | in-repo | transcript | 8 | 4 | other | F10 S3 F2 S8 F4 F4 S2 F | shiftlead TD-1031 (2026-10-26) |
| shiftlead | TD-783 | 2026-10-16 | in-repo | transcript | 7 | 3.5 | ? | F F S F S S F | - |
| shiftlead | TD-806 | 2026-10-17 | in-repo | transcript | 7 | 3.5 | ? | F12 S1 F6 S2 F4 F1 F | - |
| shiftlead | TD-734 | 2026-10-15 | in-repo | transcript | 7 | 3.5 | converged | F6 S8 F1 S2 F6 S5 S0* | shiftlead TD-761 (2026-10-15); shiftlead TD-1222 (2026-10-29) |
| shiftlead | TD-693 | 2026-10-15 | in-repo | transcript | 6 | 6 | converged | S7 S5 S3 S3 S0* S6 | shiftlead TD-966 (2026-10-22) |
| shiftlead | TD-761 | 2026-10-16 | in-repo | transcript | 5 | 2.5 | other | F9 S4 F4* S7 S3 | - |
| shiftlead | TD-702 | 2026-10-15 | in-repo | transcript | 5 | 5 | converged | S3 S3 S2 S0* S5 | - |
| shiftlead | TD-810 | 2026-10-17 | in-repo | transcript | 5 | 2.5 | other | F5 S0 F2 F3 S0 | - |
| shiftlead | TD-681 | 2026-10-14 | in-repo | transcript | 4 | 4 | converged | S9 S5 S1 S8* | - |
| shiftlead | TD-692 | 2026-10-15 | in-repo | transcript | 4 | 4 | converged | S5 S5 S0* S2 | - |
| shiftlead | TD-731 | 2026-10-15 | in-repo | transcript | 4 | 2 | converged | F9 S8* F1 S6* | - |
| shiftlead | TD-745 | 2026-10-16 | in-repo | transcript | 4 | 2 | converged | F6 S5 F5 S* | - |
| shiftlead | TD-845 | 2026-10-17 | in-repo | transcript | 4 | 2 | other | F9 S4 F5 S0 | - |
| shiftlead | TD-682 | 2026-10-14 | in-repo | transcript | 3 | 3 | converged | S9 S5 S2* | - |
| shiftlead | TD-688 | 2026-10-14 | in-repo | transcript | 3 | 3 | converged | S6 S3 S2* | - |
| shiftlead | TD-814 | 2026-10-17 | in-repo | transcript | 3 | 1.5 | ? | F4 S3 F | - |
| shiftlead | TD-819 | 2026-10-17 | in-repo | transcript | 2 | 1 | converged | F3* S0* | - |
| shiftlead | TD-820 | 2026-10-17 | in-repo | transcript | 2 | 1 | converged | F1* S3* | shiftlead TD-854 (2026-10-17) |
| shiftlead | TD-821 | 2026-10-17 | in-repo | transcript | 2 | 1 | other | F2 S2 | - |
| shiftlead | TD-823 | 2026-10-17 | in-repo | transcript | 2 | 1 | converged | F1* S2 | - |
| shiftlead | TD-816 | 2026-10-17 | in-repo | transcript | 2 | 1 | other | F1 S7 | - |
| shiftlead | TD-818 | 2026-10-17 | in-repo | transcript | 2 | 1 | converged | F1* S2* | - |
| shiftlead | TD-818 (amendment) | 2026-10-17 | in-repo | transcript | 6 | 3 | ? | S4 F15 F14 S2 F2 S1 | - |
| shiftlead | TD-900 | 2026-10-19 | in-repo | transcript | 2 | 1 | ? | S O | - |
| shiftlead | TD-1025 | 2026-10-26 | in-repo | design-history | 30 | 15 | converged | F5 S7 F4 S6 F5 S4 F3 S4 F4 S4 F3 S3 F3 S5 F3 S4 F3 S3 F3 S5 F2 S2 F1 S2* F1 S3 F S1 S1 S* | - |
| shiftlead | TD-1031 | 2026-10-26 | in-repo | design-history | 8 | 4 | converged | F5 S6 F5 S3 F4 S2 F2 S* | - |
| shiftlead | TD-1033 | 2026-10-26 | in-repo | design-history | 8 | 4 | converged | F9 S9 F7 S5 F6* S5 F5 S* | - |
| shiftlead | TD-418 | 2026-10-09 | in-repo | transcript | 4 | 4 | ? | S S S S | - |
| shiftlead | TD-646 | 2026-10-14 | in-repo | transcript | 12 | 6 | ? | S S S S F S S S F S F F | - |
| shiftlead | TD-722 (amendment PR #1850) | 2026-10-15 | in-repo | transcript | 8 | 4 | ? | F F S F S F F S | - |
| shiftlead | ShiftLead ADR 2026-10-15 | 2026-10-15 | in-repo | adr | 8 | 4 | ? | F F F F S S S F | - |
| shiftlead | ShiftLead ADR 2026-10-19 | 2026-10-19 | in-repo | adr | 7 | 3.5 | ? | F S S F S F S | - |
| shiftlead | TD-307 | 2026-10-04 | in-repo | transcript | 5 | 5 | ? | F F F F F | - |
| shiftlead | TD-307 | 2026-10-04 | in-repo | transcript | 17 | 8.5 | ? | F F F F F F F F F F S S S F F F F | shiftlead TD-356 (2026-10-06) |
| dev-cadence | 2026-10-28-ledger-id-provenance (formal Id take field; redesign of TD- | 2026-10-29 | wide | transcript | 2 | 1 | ? | F S | - |
| shiftlead | TD-100 | 2026-09-25 | in-repo | adr | 4 | 4 | converged |  | - |
| shiftlead | TD-103 | 2026-09-22 | in-repo | ledger | 9 | 4.5 | converged |  | - |
| shiftlead | TD-057 | 2026-09-17 | in-repo | design-history | 2 | 2 | converged |  | - |
| shiftlead | TD-069 | 2026-09-19 | in-repo | design-history | 1 | 1 | converged |  | - |
| shiftlead | TD-070 | 2026-09-20 | in-repo | design-history | 1 | 1 | converged |  | - |
| dev-cadence | 2026-08-08-automation-and-sharing (dev-cadence P1-P5) | 2026-08-08 | wide (parallel) | other | 3 | n/a | converged | S S S | - |
| dev-cadence | 2026-08-10-machine-scope-attention (dev-cadence P1-P3) | 2026-08-10 | wide (parallel) | other | 3 | n/a | converged | S S S | - |

## Caveats (where the data is thin)

- **The regime is one policy, almost entirely.** 88 of the 97 designs are ShiftLead's, nearly all from 2026-10-04 to 10-30, under the rule "iterate until READY" with no cap (and, from 10-15, a Sonnet and a Fable review on every round). The counts show how long an uncapped loop runs, not what a cap would have lost. Several loops stopped by override or fatigue (TD-1022, TD-978, TD-941, TD-909) and TD-1025 ran 30 reviews (15 rounds); "converged" is read from the final verdict, so it includes "stopped on follow-ons".
- **Wide is still thin: 11 designs in the aggregates**, 4 of them ShiftLead TDs with only total findings, 1 (ledger-writer) with build-changing counts and tokens and still unbuilt, and one (id-provenance) decided 10-28. Post-build evidence for wide rests on about 3 designs (pinned-not-synced, ledger-ids, ledger-per-entry). The extension added one wide record, and settled counts for two (hard-rename 4 reviews, ledger-ids 5 reviews of Sonnet 1,3,5 and Fable 2,4).
- **Findings are not build-changing counts.** Only the ledger-writer plan has a build-changing split. The "last review with 3+ findings" statistic uses total findings per review: from design-history lines for ShiftLead TDs, and, for the 35 transcript-sourced designs, parsed from the first lines of each hand-back (an explicit "N findings", else the highest numbered item). Where the hand-back came by message and is not in the transcript the count is blank, and a design needs counts for at least half its reviews to enter that statistic. Parsed counts can include nits and notes.
- **Post-build defects are a lower bound, and the two batches were found differently.** The first pass read the ledger entries citing each TD. The extension listed every ledger entry citing each added TD (after the design date, builds and backfills excluded) and judged each by its title and the citing sentence; a pure regex over the citing sentences found only 1 of the first pass's 5 known defects, so it was not used. Even so the 44 added in-repo designs show 2 clear and 3 questionable defects against 5 clear in the first pass; most of that gap is how hard each batch was searched and how recent the designs are (only 3 of the 44 are dated 10-26, but the first-pass set carries 10-27..10-30 designs that are not aged), not evidence that the added designs are cleaner. Test-gap entries (the test-audit TDs) are excluded in both batches as not design gaps.
- **Transcript counts.** Each review is one Agent call (de-duplicated by model and round number, or by prompt text for the non-TD plans); async launches are matched to their `<task-notification>` for tokens and the hand-back text. Where a plan numbers single reviews (ShiftLead history, hard-rename) rounds = reviews / models; where it numbers pairs (the 10-15..10-17 designer runs) the pairs were launched together, so rounds = pairs, the same arithmetic. A round in which only one of Fable and Sonnet was launched counts as half. The Sonnet-only designs of 10-09..10-15 (TD-418, 681, 682, 688, 692, 693, 702) have rounds = reviews.
- **One-round designs.** Seven added designs (TD-816, 818, 819, 820, 821, 823 of 10-17 and TD-900 of 10-19) are one Fable design review plus one Sonnet fact-check (TD-900: Opus plus Sonnet) of a design PR, counted as 1 round; whether that is a design round or the pre-merge PR review is a judgement call. Without them in-repo is 76 designs: 24 within 3 rounds (32%), 47 within 4 (62%), 67 within 6 (88%), median rounds still 4.
- **Classification is mine and debatable**, as before. Every added design except id-provenance is classed in-repo ("changes only ShiftLead"); TD-1033 and TD-1025 touch dev-cadence's mechanics but edit only ShiftLead. Reclassifying shifts the wide numbers by 1-4 designs.
- **Long-lived designs were split or lumped by judgement.** TD-307's flows section was reworked by Paul after a READY and is recorded as two records (first draft: 5 Fable reviews; rework to v3: 17 reviews incl. confirms); TD-818 and TD-722 amendments are separate from the original design; the two Queue ADRs are separate records from TD-748 and TD-909, which sit downstream of them. If a lineage is counted as one design its round count is the sum.
- **Prose-sourced records** (TD-100 four Sonnet rounds, TD-103 eight Sonnet plus a closing Fable, TD-057 step 3c two Fable reviews, TD-069 and TD-070 one Sonnet review each) carry no per-review detail. The two dev-cadence plans of 2026-08 are parallel-lens reviews (two Sonnet lenses plus a verification), recorded with `mode: "parallel"` and kept out of every aggregate.

### Skipped, and why

- **TD-1190**: reviews launched 10-30 and the hand-backs are not in the transcript; may still be in progress.
- **agent-cadence TD-203** (this rounds plan): its own review loop is still running.
- **TD-787**: the ledger entry lists Fable rounds 1-3 and Sonnet rounds 1-2, design-history says "Fable rounds 1-4 and Sonnet rounds 1-3"; 5 or 7 reviews, unresolved.
- **TD-158** (dev-cadence plan, one Fable review) and **TD-345** (a scoped Fable review): one review each with no hand-back text; **TD-052 section 4.10** (four Fable reviews and an unstated number of Sonnet ones).
- **TD-964's first round** (reviewed under an earlier id) is already in the set as TD-964; **TD-1119, TD-975** have history lines but no transcript, and kept their history counts.
- **ledger-per-entry** stays in the table with its defects but has no review count, so it is outside the aggregates.
- **Single design-PR fact-checks** of 09-22..10-12 (TD-177, 208, 240, 245, 246, 254, 351) were read as the per-PR review, not a design review. ShiftLead's research ADRs have no review record.
- **Codex and Gemini CLI stores** on this machine hold no design review.
- Transcripts reached through more than one project directory were read once.

