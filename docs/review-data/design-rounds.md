# Design-review rounds on this machine: data for the max-rounds defaults

Gathered 2026-10-30 (read-only research, session `sl-tds`). Private repos are named consumer-a to consumer-e, as elsewhere in this repo. Machine-readable twin: `design-rounds.json` (same records; `build_changing`, `minor` and `tokens` are null where unknown).

**What counts.** A design review is one model reviewing a plan or design before the build (the per-PR pre-merge review is not counted). A **round** is one pass through the models in use; with Sonnet and Fable that is 2 reviews, so alternating 11 reviews = 5.5 rounds. Where a source numbers single reviews as "rounds" (ShiftLead's design-history numbers alternating reviews 1..N), rounds here = reviews / 2. Where it numbers pairs (TD-941, TD-947, TD-966, TD-623), rounds = the pair count. **Wide** = costly to fix after shipping (another repo, a vendored/published format, an irreversible step); else **in-repo**.

**Corrected 2026-10-30** after PR #25's fact-check: a history line carrying two reviews ("round 5, …; round 6, …") had been counted once, so TD-926, TD-995 and TD-998 each gained a review. An independent parse agrees with the other 40 ShiftLead designs. The aggregates below are recomputed; the medians did not move.

**How to regenerate.** Sources: `~/shiftlead/docs/design-history.md` (lines `- DATE (TD-n's review, round k, Fable|Sonnet, ...)`, regex on TD id, round, model, "NOT READY"/"READY", "n findings"); ADR Status/Review sections in `~/dev-cadence/docs/plans/`, `~/agent-cadence/docs/plans/`, `~/shiftlead/docs/decisions/`; post-build defects by grepping every other ledger entry (`docs/ledger/`, `archive/`) that cites each design's TD id, then reading the ones that read as defects; tokens from `<subagent_tokens>` in transcript task notifications. The generator was a throwaway script (not kept); the JSON is the record.

## Aggregates

| | designs with a review count | reviews: median / max / min | rounds: median / max |
|---|---|---|---|
| in-repo | 39 (all ShiftLead, Oct 15-30) | 8 / 20 / 4 | 4.0 / 10 / 2 |
| wide | 9 (4 ShiftLead TDs, ledger-writer (rounds counted from reviews), pinned-not-synced, public-scrub, ledger-ids [rounds unknown], ledgerboard-split ADR) | 7 / 15 / 4 | 3.75 (8 values) / 7.5 / 2 |

- **Distribution of in-repo rounds** (39): 2.0 x4, 2.5 x4, 3.0 x4, 3.5 x5, 4.0 x3, 4.5 x3, 5.0 x2, 5.5 x5, 6.0 x3, 6.5, 7.0 x3, 9.5, 10. So 3 rounds or fewer: 12 of 39; 4 or fewer: 20 of 39; 6 or fewer: 33 of 39 (counting 6.5 as above 6).
- **When findings stopped (in-repo, ShiftLead).** Counts are *total findings per review*, not build-changing (not classified; every finding was "adopted"). Review index of the last review with 3+ findings: median 6 (reviews, = round 3), range 0-18. The designs end a median 2 reviews after their last 3+-finding review, i.e. the READY streak is short: the loop stopped when findings dropped to follow-ons. Reviews 1-2 usually carry 5-17 findings; reviews 7+ mostly carry 1-3, labelled "follow-ons of the last adoption".
- **Wide, build-changing counts exist for one design only** (ledger-writer, table in json): 0, ~6, 3, 3, 2, 2, 1-2, 1, 1, 1 (important), 0 -> last 2+ at review 6 (round 3), last 1+ at review 10 (round 5). ShiftLead's 4 wide TDs have only total findings: TD-1129 last 3+ at review 5 (of 7); TD-1009 at 10 (of 15); TD-966 at 1 (of 8); TD-1048 at 4 (of 7).
- **Post-build defects.** In-repo: 6 of 39 designs had a later ledger entry I judged to record a design-level gap or contradiction (TD-947, 1051, 995, 909, 1189, 931 [931 is a stale sentence, minor; 1189's TD-1240 is questionable, a new design request that cites it once]); the other 33 had no such entry found, but that search was by citation and not exhaustive. Of the 6, 3 (TD-947, 1051, 995) look like things a more careful enumeration might have caught (stray-event class, older-peer verdict, internal contradiction); none of the 6 is shown to be catchable by an extra round. Wide: of the 4 wide designs that were built and have a review count, dev-cadence's pinned-not-synced (4 reviews) is followed by 4-5 migration/adopt gaps within 3 days (TD-147, 149, 168, 174); ledger-ids (5 reviews) by a redesign (TD-188); ledger-per-entry (review count unknown) by 4 split defects in 1-2 days; ledger-writer and public-scrub/hard-rename are not yet assessable. So: wide designs built after few rounds (4-5 reviews) show visible follow-up defects; the one wide design that went to 11 reviews has no post-build data.

## Per-design table

Review column legend: letter = model (F Fable, S Sonnet), number = total findings that review reported (blank = READY/none stated), `*` = verdict READY. Findings are NOT build-changing counts. "Post-build" lists later ledger entries naming a design-level gap.

| repo | plan | date | class | reviews | rounds | stop | per-review (model+findings) | post-build defects |
|---|---|---|---|---|---|---|---|---|
| shiftlead | TD-909: The Queue card — three wants (Decide, Do, Read), three verbs ( | 2026-10-19 | in-repo | 14 (the history has no round 8) | 7 | other | F7 S5 F7 S6 F6 S6 F5 F4 S2 F2 S2 F1 S1 F2 | shiftlead TD-1129 |
| shiftlead | TD-927: Token counts on the Spend page, beside every figure — by team, | 2026-10-20 | in-repo | 11 | 5.5 | converged | F5* S5 F5* S4 F4* S2 F4* S* F1 S* F1* | - |
| shiftlead | TD-931: The top bar's pages look like three different kinds of control | 2026-10-20 | in-repo | 4 | 2 | converged | S17 F8 S8 F8* | shiftlead TD-935 |
| shiftlead | TD-926: Hovering a Queue card's header or row draws its ⋯ names inline | 2026-10-20 | in-repo | 7 | 3.5 | converged | F5 S5 F3 S2 F3* S0* F2* | - |
| shiftlead | TD-924: The Sessions page's Agents count leaves out every session of a | 2026-10-20 | in-repo | 7 | 3.5 | converged | F5 S8 F4 S4 F3* S1* F3* | - |
| shiftlead | TD-947: A background subagent's permission shows *Needs you* on a sess | 2026-10-21 | in-repo | 14 | 7 | converged | F8 S7 F7 S8 F3 S5 F4 S* F4 S4 F6 S5 F1 S* | shiftlead TD-960 |
| shiftlead | TD-941: A Gemini session at its own *Usage limit reached* dialog reads | 2026-10-21 | in-repo | 20 | 10 | converged | F7 S7 F3 S4 F4 S5 F5 S5 F3 S3 F3 S2 F3 S4 F3 S* F2 S4 F1 S* | - |
| shiftlead | TD-964: The end of a session on Focus, second round: the ending banner | 2026-10-21 | in-repo | 7 | 3.5 | converged | S16 F11 S7 F8 S5 F3* S1* | - |
| shiftlead | TD-623: No document says how a repo gets its first ShiftLead team | 2026-10-21 | in-repo | 8 | 4 | converged | F7 S6 F3 S6 F3 S5 F S* | - |
| shiftlead | TD-978: Closing a session leaves its worktree behind, though the desig | 2026-10-22 | in-repo | 19 | 9.5 | other | F10 S13 F10 S9 F8 S1 F7 S12 F5 S1 F1 S* F1 S1 F1 S3* F1 S2 F1 | - |
| shiftlead | TD-975: Focus has no list of the person's prompts: a Prompts card on t | 2026-10-22 | in-repo | 11 | 5.5 | converged | F9 S13 F8 S7 F5 S5 F6 S3* F2* S* F* | - |
| shiftlead | TD-986: On a phone the Focus terminal cannot be scrolled reliably, and | 2026-10-23 | in-repo | 12 | 6 | converged | F9 S10 F5 S7 F4 S8 F3 S4 F2 S1 S2 S* | - |
| shiftlead | TD-999: The wait guard in Gemini CLI: its `BeforeTool` hook refuses an | 2026-10-24 | in-repo | 8 | 4 | converged | F5 S5 F2* S5 F* S2 F* S* | - |
| shiftlead | TD-991: A member still waits on CI in its own turn — a foreground `tim | 2026-10-24 | in-repo | 6 | 3 | converged | F7 S* F S2 F S* | - |
| shiftlead | TD-998: `ao` is not on PATH inside a container node: sessions and shel | 2026-10-24 | in-repo | 6 | 3 | converged | F3 S7 F3 S4* F* S* | - |
| shiftlead | TD-993: **Told at start** leaves the Focus side panel: a row of the Se | 2026-10-24 | in-repo | 4 | 2 | converged | F S* F S* | - |
| shiftlead | TD-995: A session cannot address another repo or team: names resolve o | 2026-10-24 | in-repo | 9 | 4.5 | converged | F11 S6 F5 S5 F3 S5 F2* S0* F2 | shiftlead TD-1128 |
| shiftlead | TD-1022: ShiftLead's copy of dev-cadence's SessionStart line predates  | 2026-10-26 | in-repo | 11 | 5.5 | converged | F7 S7 F6 S5 F* S7 F* S5 F* S2 S0* | - |
| shiftlead | TD-1064: A session gets either the repo's tools or the org's reach, ne | 2026-10-26 | in-repo | 12 | 6 | converged | F9 S3 F4 S6 F4 S4 F5 S2 F3 S2 F* S* | - |
| shiftlead | TD-1061: Nothing runs the stranded-work sweep on a schedule, so attent | 2026-10-26 | in-repo | 11 | 5.5 | converged | F9 S9 F3 S4 F3 S2 F2 S1 F* S1 S* | - |
| shiftlead | TD-1051: A steer's answer is lost when the techlead that relayed it cl | 2026-10-26 | in-repo | 12 | 6 | converged | F8 S5 F6 S7 F5 S3 F6 S7 F5 S3 F* S* | shiftlead TD-1095 |
| shiftlead | TD-1042: Two of the person's own interactive sessions in different pro | 2026-10-26 | in-repo | 9 | 4.5 | converged | F6 S6 F6 S6 F3* S3 F3* S3* F2* | - |
| shiftlead | TD-1026: Two team lessons from the memory harvest are not in the role  | 2026-10-26 | in-repo | 6 | 3 | converged | F6 S5 F S4 F S0* | - |
| shiftlead | TD-1143: ShiftLead reads only a one-file ledger: before any repo it wa | 2026-10-27 | in-repo | 7 | 3.5 | converged | F8 S7 F4 S6 F2 S6 S* | - |
| shiftlead | TD-1150: A browser tab says nothing by its icon: no page has a favicon | 2026-10-27 | in-repo | 5 | 2.5 | converged | F7 S3 F1 S* F0* | - |
| shiftlead | TD-1108: A file path on the Queue page or in the Inbox is plain text:  | 2026-10-27 | in-repo | 13 | 6.5 | converged | F8 S6 F3 S4 F5 S9 F4 S2 F3 S* F3 S0* F* | - |
| shiftlead | TD-1117: A session the person started cannot hold or decide an entry,  | 2026-10-27 | in-repo | 14 | 7 | converged | F8 S6 F6 S3 F4 S5 F3 S6 F3 S4 S1 F3 S1 S0* | - |
| shiftlead | TD-1149: New session's Team and Role picks fill only the package prese | 2026-10-27 | in-repo | 11 | 5.5 | converged | F6 S5 F4 S6 F5 S4 F5 S1 F3 S* F* | - |
| shiftlead | TD-1116: A session the person started cannot steer another team's memb | 2026-10-27 | in-repo | 7 | 3.5 | converged | F4 S8 F3 S4 F2* S* F2* | - |
| shiftlead | TD-1203: The Sessions rollup sums the page into four facets, so how on | 2026-10-28 | in-repo | 5 | 2.5 | converged | S17 F8 S3 F* S* | - |
| shiftlead | TD-1187: The top bar scrolls away with the page: once scrolled down, t | 2026-10-28 | in-repo | 8 | 4 | converged | F6 S5 F3 S4 F2 S3 F S* | - |
| shiftlead | TD-1189: A team card shows the repo's Technical debt only on the repo' | 2026-10-28 | in-repo | 4 | 2 | converged | S7 F2 S* F* | shiftlead TD-1240 (questionable: a new design request that cites TD-1189 once) |
| shiftlead | TD-1200: `ao td next` reads like a question but takes and records an i | 2026-10-28 | in-repo | 4 | 2 | converged | F4 S6 F1 S* | - |
| shiftlead | TD-1222: *Working* and *waiting* overlap (a session with its own runni | 2026-10-29 | in-repo | 10 | 5 | converged | F7 S6 F6 S5 F4 S5 F4 S4 F3* S* | - |
| shiftlead | TD-1239: A push the forge refuses is reported as *origin could not be  | 2026-10-29 | in-repo | 5 | 2.5 | converged | F4 S* F2 S0* F* | - |
| shiftlead | TD-1119: The design, briefs and docs still describe lanes and a manage | 2026-10-29 | in-repo | 9 | 4.5 | converged | F7 S7 F5 S4 F4 S3 F3 S1* F0* | - |
| shiftlead | TD-857: Gemini's first job: the fact-check of a doc-only PR, read by a | 2026-10-29 | in-repo | 10 | 5 | converged | F5 S5 F2 S3 F5 S4 F4 S3 F3 S* | - |
| shiftlead | TD-1066: A Queue card's board item does not say what it asks: an `act` | 2026-10-30 | in-repo | 5 | 2.5 | converged | F3 S4 F2 S* F* | - |
| shiftlead | TD-1240: With every team card folded, the repo's line draws the whole  | 2026-10-30 | in-repo | 6 | 3 | converged | F3 S2 F2 S1 F* S* | - |
| agent-cadence | 2026-10-29-ledger-writer-in-ledgerboard (TD-173 writer in ledgerboard  | 2026-10-29 | wide | 11 | 5.5 | converged | see json (build-changing known) | - |
| agent-cadence | 2026-10-29-hard-rename | 2026-10-29 | wide | ? | ? | converged |  | - |
| dev-cadence | 2026-10-22-ledger-ids (TD-124) | 2026-10-22 | wide | 5 | ? | other |  | dev-cadence TD-145, TD-150, then TD-188 |
| dev-cadence | 2026-10-25-pinned-not-synced (TD-129; shiftlead ADR 2026-10-25-shiftle | 2026-10-25 | wide | 4 | 2 | converged |  | dev-cadence TD-147; dev-cadence TD-149; dev-cadence TD-168; dev-cadence TD-174; dev-cadence TD-164, TD-158 |
| dev-cadence | 2026-10-27-ledger-per-entry (TD-160) | 2026-10-27 | wide | ? | ? | None |  | dev-cadence TD-170, TD-176, TD-183, TD-185 |
| dev-cadence | 2026-10-26-public-scrub (amendment 2026-10-28: cut over to agent-caden | 2026-10-28 | wide | 5 | 2.5 | converged |  | - |
| shiftlead | decisions/2026-10-12-ledgerboard-dev-cadence-shiftlead (ledgerboard sp | 2026-10-12 | wide | 8 | 4 | converged |  | - |
| shiftlead | TD-966: `ao td next` and the home's `ids.json` become a front end over | 2026-10-22 | wide | 8 | 4 | converged | F6 S2 F2 S* F2 S2 F1 S* | - |
| shiftlead | TD-1009: ShiftLead requires dev-cadence, and the person's briefs, star | 2026-10-25 | wide | 15 | 7.5 | converged | F6 S6 F2 S7 F3 S3 F1 S2 F1 S4 F* S* F S1 S* | - |
| shiftlead | TD-1048: `ao td next` neither prints the `**Taken by:**` line a new en | 2026-10-26 | wide | 7 | 3.5 | converged | F6 S5 F* S4 F* S1 S* | - |
| shiftlead | TD-1129: A Queue card's tree joins `Blocked by:` edges in either direc | 2026-10-27 | wide | 7 | 3.5 | converged | F6 S8 F2 S4 F7 S* F1* | - |

Ledger-writer tokens per review (Sonnet 1, Fable 2, ...): 83k, 131k, 111k, 127k, 79k, 82k, 72k, 94k, 62k, 93k, 46k = about 980k total (Fable 5 reviews 527k, Sonnet 6 reviews 453k); about 89k per review average. No other design has token data (not mined).

## Caveats (where the data is thin)

- **ShiftLead's 43 designs (39 in-repo, 4 wide) were all made 2026-10-15 to 10-30 under one policy**: iterate until READY (cadence 4.8), with no cap. The counts show how long a loop runs when uncapped, not what a cap would have lost. Several loops ended by override or fatigue: TD-1022 (Fable half closed after Sonnet READY), TD-978 (19 reviews, ended with Fable still on a follow-on), TD-941 and TD-909 (14-20 reviews, last findings of 1-2 each). Stop reason "converged" is read from the final verdict, so 'converged' can include 'stopped on follow-ons'.
- **Wide is thin: 9 designs, of which only 1 (ledger-writer) has build-changing counts and tokens, and it is unbuilt.** The post-build comparison for wide rests on about 3 designs (pinned-not-synced, ledger-ids, ledger-per-entry), two of which have a coarse review count. Any wide median here rests on 8-9 values, mostly ShiftLead's.
- **Classification is mine and debatable.** TD-1022, 1143, 1200, 1026 are borderline (cross-repo parity but only ShiftLead edited) and counted in-repo. TD-1129 (new `Part of:` field in the vendored ledgerboard) counted wide. Reclassifying shifts the wide numbers by 1-4 designs.
- **Post-build search is by citation of the design's TD id in other ledger entries** plus reading the live-check/follow-on ones. It will miss defects fixed in a PR with no ledger entry, and it cannot tell design defects from build defects reliably (TD-172/983/1126-type test gaps were excluded). In-repo "no defect" counts are therefore lower bounds on defects.
- **No build-changing vs minor split for ShiftLead designs.** Counts are all findings. The proxy "last review with 3+ findings" overstates the stop point for wording-heavy UI designs and understates it for mechanism designs.
- **Excluded for unknown review count:** dev-cadence ledger-per-entry (kept in json for its defects), agentorc hard-rename ("four review rounds", 4 reviews or 4 pairs?), TD-722 (amendments, mixed format), TD-418, TD-900; Aug-Sep 2026 dev-cadence plans (automation-and-sharing: 2 parallel Sonnet reviews + confirm; machine-scope-attention: 2 parallel + 1 verification) are parallel-lens reviews, not rounds, and not included. ShiftLead's pre-October designs (e.g. settings-audit: 4 Sonnet rounds, in-repo; queue ADR: 4 Fable + 3 Sonnet) are recorded in decisions/ in prose and are not in the table. consumer-a, consumer-b, consumer-c, consumer-d, ledgerboard have no plans or round records beyond ledgerboard TD-005 (which cites the 11-review plan).
- Transcripts were mined only for the sl-tds session; other sessions (agentorc worktrees) were not searched for token counts.
