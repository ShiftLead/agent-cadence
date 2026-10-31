# User Attention Board — agent-cadence

Swept: 2026-09-22 (kmaster, quick)

Items that need Paul to act or decide, plus in-flight work parked by a session. Sessions add
entries **the moment they arise** and close them when handled — never delete (see
[files/docs/cadence.md §3](../files/docs/cadence.md#3-never-strand-work) — the system this
repo distributes, dogfooded here). Keep this file small — durable debt belongs in
[the ledger](ledger/README.md).

Note: `files/docs/user_attention.md` is the *template* synced into consumer repos; THIS file
is the live board for this repo.

Format: `- [ ] YYYY-MM-DD (session <first-8-of-session-uuid> on <host>, or n/a) — what's needed. Context: TD-N (another repo's: <repo>#TD-NNN) / PR #N / branch. Due: YYYY-MM-DD.`

Under the line, indented two spaces, a detail block of sub-bullets in plain English for someone who has not read your session: `**Context:**` (a few sentences; nested bullets where a list is clearer), `**Question:**`, `**Caveats:**` (when there are any), `**Recommended:** <the default> — why. **Otherwise:** <each other answer> — when.` Always on a `decide`; on an `act`/`look` whenever the line alone does not say what to do; fields stay on the line (files/docs/cadence.md §3.3, TD-084).

Kinds: `decide | act | look | watch | fyi` — optional, one word before the date: `- [ ] decide YYYY-MM-DD (…`. `decide`/`act` (or no word) are the person's to-do, and so is `look`, a live look the person is asked to make; `watch` is a session's own re-check, its check-by date as `Due:`; `fyi` carries no `Due:` and never reaches the SessionStart line. An item overdue 14 days or more belongs in the ledger: ledger it and close it here (cadence.md §3).

A question ends with its answers after `Due:` — `Answers: <answer> | <answer>.`, the one you recommend marked `Answers: <answer> (default) | <answer>.` The person's answer is appended by `scripts/board_edit.py decide`, never by hand: `Decided: <text> (YYYY-MM-DD).` A `look` (the person is asked to look at something live) ends with the fixed pair `Answers: Works | Not right: <what>.`; a `watch`, an `act` and an `fyi` carry none (cadence.md §3.5).

Closing an entry never deletes it: `files/scripts/board_edit.py done --why <why>` ticks it and appends `Closed: YYYY-MM-DD — <why>.` A merge conflict here is resolved by keeping both sides; 10 or more closed entries are archived to `user_attention_archive.md` in a PR of their own (TD-062).

`Due:` is optional but recommended — the SessionStart due-items line surfaces items whose
date has arrived (TD-7). **To snooze: just edit the Due date.** Undated items surface in
`/attention`'s full report.

## Needs Paul

- [ ] decide 2026-10-31 (session 750f7bdc on kmaster) — TD-177's merged-by design finished its review rounds: say Go to file its builds, or ask for one more round. Context: TD-177, docs/plans/2026-10-31-merged-by-trailer.md, docs/reviews/TD-177.md. Due: 2026-11-03. Answers: Go (default) | One more round | Hold: <note>.
  - **Context:** The design makes every cadence merge write its own squash message, ending in one trailer paragraph: `Co-Authored-By:`, `Agent-Model:`, `Review:` (the reviewer's model and verdict), `Precheck:` (the head the gate passed), and `Merged-by: <AGENT_NAME> (<model>)`. Then `git log` names who wrote, reviewed, checked and merged each change, and the weekly `check_cadence.py --since` lists any merge without `Merged-by:` as a bypass, the #429 event. `check_cadence.py --pr <n> --trailers` writes what the gate saw; `forge.py squash-message` composes; the merge itself stays a literal `gh pr merge` on the session's command line, so a guard keyed on that command (the one that holds merges for your word) still sees it. The rounds ended by the stop rule after round 5 of 6. Build-changing findings per round were 5, 3, 2, 2, 0 from design reviews and 4, 4, 4, 0, 0 from fact-checks, with a closing fact-check of 0. That was 11 Sonnet reviews, 766,285 tokens and 68 findings in all.
  - **Question:** Go to the builds, one more round, or hold?
  - **Caveats:** Two topics recurred, so the rounds ask *is this the wrong design?* (1) **The hook's model reading:** `forge.py` must read the model and name exactly as the bash hook does, which took eight findings to pin (strip set, locale, NUL, length). The design keeps them a tested parity pair and gives the hook an `LC_ALL=C` window. (2) **The merge command's shape:** round 3 found that a `forge.py merge` would hide the merge from that guard, so the merge moved back onto a visible `gh pr merge`; round 4 cleaned up what that left. The signed forge comments in the original Fix were deferred to TD-211. Whether GitHub appends anything to a given squash body is untested until the first merge after the build reads it back.
  - **Recommended:** Go — round 5 found nothing build-changing and both recurring topics are settled in the text. **Otherwise:** One more round if the parity pair looks too heavy, or Hold with what to change.
- [x] decide 2026-10-30 (person) — Agents type board lines by hand: every board write goes through `board.py`, and every repo that uses ledgerboard writes its ledger and board only through the helpers. Context: TD-206. Due: 2026-10-30. Decided: go ahead (2026-10-30). Closed: 2026-10-30 — Paul's go recorded on TD-206: his block is lifted; its design rounds run once TD-202 and ledgerboard#TD-008 land.
- [x] decide 2026-10-30 (person) — The squash commit names who wrote a change but not who merged it, so a bad merge can't be traced from git: a `Merged-by:` trailer, beside the `Co-Authored-By:` ones it keeps. Context: TD-177. Due: 2026-10-30. Decided: go ahead (2026-10-30). Closed: 2026-10-30 — Paul's go recorded on TD-177: his block is lifted, the Fix's shape stands; its design rounds run before the build.
- [x] decide 2026-10-29 (session 5634736a on kmaster) — Flip agent-cadence to public? Context: TD-191 step 4. Due: 2026-11-06. Answers: Flip (default) | Not yet: <what first>. Decided: Flip (2026-10-30). Closed: 2026-10-30 — flipped public 2026-10-30 (Paul); ruleset, fork check and v0.1.0 tag done.
  - **Context:** Everything before the flip is done. Two privacy reads ran: the second-model read over the seed, then a fragment grep over every commit through #18 and the tree at main. Both came back clean, except for what Paul accepted: the email on the first seven squash merges (#1–#7), one session id on the `cadence/ledger-ids` counter (`0640017`), and this board's `Swept:` host name. The README was rewritten for developers (#17) and the GitHub description matches it. Paul said "I think we are ready to flip but want to sleep on it" (2026-10-29).
  - **Question:** Make ShiftLead/agent-cadence public now?
  - **Caveats:** Irreversible in practice: forks and caches keep what they saw. ac-grind keeps merging, so rerun the fragment grep on anything merged after #18 first. After the flip: branch protection on main, check for forks, tag `v0.1.0`, and change the README's install line from `--branch main` to the tag.
  - **Recommended:** Flip — the reads are clean and every finding is decided. **Otherwise:** Not yet — say what has to happen first.


## In-flight (parked by a session)

- (none)

