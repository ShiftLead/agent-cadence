# TD-206: every board write goes through the helpers — design

**Status:** converged, draft 18, 2026-11-03 (Fable round 17 and Sonnet round 18 both CONVERGED). Shape agreed with Paul in conversation on 2026-11-03; his go the same day. **Built** 2026-11-04 in three PRs: #75 (§1–§2), #76 (§3), #77 (§4–§6).
**Entry:** TD-206. **Builds on:** TD-213 (`board_edit.py` wraps ledgerboard v2.3's `board.py`), TD-202 and TD-173 (the same rule for the ledger). **ShiftLead's half:** shiftlead#TD-1286.

## The problem

Sessions still type board lines by hand. In agent-cadence nothing writes a new item: `board_edit.py` exposes only `snooze`, `due`, `done`, `decide` and `reply` (board_edit.py:88), though ledgerboard's `board.py` (v2.3) also has `add`, `list`, `archive` and `fmt` (ledgerboard/board.py:71). So a new `decide` item, with its kind, `Answers:`, `(default)` and detail block, is typed from §3.3's template, and the closed-items archive (§3.4) is a hand move. Nothing checks the result: the cadence check has no board row (check_cadence.py's rows are pr, review, ci, base, ledger, worktree, pushed, deploy); `row_board_edit_pr` only decides whether a tool-made board PR may skip review.

## Decisions (Paul, 2026-11-03)

1. **A hand edit is fine if it passes the gate.** The rule tells sessions to use the helpers; the gate judges the line, not who typed it. The person's own edits are judged the same way.
2. **The gate turns on per repo, with that repo's pin.** A repo gets the board row when it bumps its agent-cadence pin to this release, not when every board on the roster has had its `fmt` pass.
3. **One rule for both files, worded now** (the recommendation, accepted): name the commands sessions run, `agent-cadence run ledger.py` and `board_edit.py`. Those stay the commands when v2.4 makes `ledger.py` a wrapper over ledgerboard's, so the wording does not change then.
4. **Archiving is automatic.**
5. **The gate is a hard failure** from the start.

## The design

### 1. The wrapper exposes every board command

`board_edit.py` gains the commands ledgerboard's `board.py` has and it lacks, **passing their flags through unchanged** (board.py:456-520), so the wrapper never drifts from the writer:
- **`add`**: a new item of any kind, at the top of `## Needs the user` (or `--under`), through `item_line()`; flags as board.py has them (`--kind`, `--text`, `--context`, `--due`, `--answer` repeated, `--default`, `--lift`, `--detail` as a JSON object of the detail block's parts, `--hide-until`, `--session`, `--host`, `--said`/`--decided` with `--by`). It prints the line it wrote (`Plan.info["line"]`). No `--line`/`--expect`.
- **`archive`**: moves the closed items, with their detail blocks, to `docs/user_attention_archive.md` (`archive_closed()`), subject from `archive_subject()`.
- **`fmt`**: rewrites item lines into the canonical form under the key rule (only lines whose item key does not change), and lists what it refused.
- **`list`**: the open items, `--json` for a tool.

`--by` on `reply` stops defaulting to git's `user.name` (TD-213 kept it): it defaults to the board's one `People:` name, as `decide` does (the wrapper resolves it with `who_answered()`, since `plan_edit` requires `by` for `reply`), and is required otherwise. Git's name proves nothing (target design §6.2).

### 2. Archiving is automatic, and every tool-made board commit has a landing

**`done` archives in the same write** when, after closing, the board holds `ARCHIVE_AT` (10) or more closed items: one commit that changes the board and the archive. Its subject stays an edit subject, with `<n>` immediately before ` (session` so `EDIT_SUBJECT_RE` (ledgerboard :2203) still reads it: `board_edit: done <head>; archived <n> (session <s>)`. No scheduler and no extra PR. §3.4's "the next session to notice moves them, in a PR of its own" is replaced by this; `archive` stays for a board already over the threshold.

**One new class, `board-archive`**, in `classify_direct` (which both the direct-commit audit and `row_board_edit_pr` use), accepts a commit whose files are exactly the board and its archive (`docs/user_attention_archive.md`; the build adds an `ARCHIVE` constant beside `BOARD`, check_cadence.py:1542), **only at the threshold** (the base board for a standalone `archive`, or the board after the close for a `done`, that is the base holding `ARCHIVE_AT − 1` or more, holds `ARCHIVE_AT` or more closed items, so no session can remove a lone item without review), with `<n>` in its subject equal to `len(closed_items(that board))` (ledgerboard :1124; `archive_subject()`'s count, open twins moved but not counted), read, for a `done`, from the subject's last `; archived (\d+) (session` (so a head holding the words can't confuse it), and for a standalone `archive` from `ARCHIVE_SUBJECT_RE`'s count (ledgerboard :2206), when recomputing it from the base gives the head byte for byte:
- **a standalone `archive`** (subject kind `archive`): `archive_closed(base_board, base_archive)`;
- **a `done` that archived** (an edit subject whose action is `done`): the one item is found among the base's open item lines whose `item_key` appears in the head archive's appended lines; for each candidate, `edit_line(line, "done", why=…, today=…)` with `today` the head's `Closed:` date and `why` its text after ` — ` (less a final `.`, which `edit_line` strips), then `archive_closed()` on that board and the base archive. It passes if one candidate reproduces the head (`archive_closed` also moves an open twin sharing the key, and the recomputation includes that).

The plumbing widens to match: `classify_direct`'s `files != [BOARD]` refusal (check_cadence.py:1618) admits `[BOARD, ARCHIVE]` for this class only, and `row_board_edit_pr` (:1669-1685, its files check :1677) accepts the class for subject kinds `edit` and `archive`, by the PR path as well as the direct one. **If `archive_closed()` refuses** (a nested or broken detail block), `done` lands as a plain one-file `done` and warns that the board needs `archive` after a hand fix; the close never fails for the archive's sake.

**`fmt` lands by ordinary review** (it has no subject kind a carve-out reads; its one routine use is the pin-bump PR, §6), and **`add` rides the session's own PR**, which takes ordinary review: a new item is a session's words, not a person's click, so it gets no carve-out. A direct `add` keeps `classify_direct`'s existing `board-append` rule; an `fyi` (no `Due:`) or an item with a detail block is not a `board-append`, so it lands by PR.

ShiftLead's board writes go through ledgerboard's `board.py` in-process (shiftlead#TD-1330), not this wrapper, so shiftlead#TD-1286 does the same in its `done`. The threshold is the consumer's, so ledgerboard's `done` does not change.

### 3. The gate: a `board` row in the cadence check

A new row, **`board`**, on every PR that changes `docs/user_attention.md`. It judges **each item's net change** across the PR, by fixed rules, rather than replaying one edit: a session PR may snooze, reply and close the same item, and the gate must accept any result the writers could have produced.

**What changed.** On an open PR the row diffs the board at the PR's merge-base against its head (not one commit: `_board_diff` reads `sha^..sha`, check_cadence.py:1591, so the row gets a merge-base variant); on a merged PR, the merge commit against its parent, as the ledger row does (check_cadence.py:1041-1070). Item lines are those `ANY_ITEM_RE` matches (`- [ ]` or `- [x]` at any indent; detail sub-bullets like `  - **Context:**` don't match, and an indented item inside a block is judged as an item, as `board_problems` judges it). Added and removed item lines that are byte-equal cancel as a multiset, so a moved item or a reordered section judges nothing. Each remaining added line is paired with a removed line of the same `item_key`; where two base items share a key, the pairing tries each and the line passes if any pairing passes.

**The rules,** for each remaining added item line (failures name the command that writes the line):
1. **Shape.** **A new item** must pass `item_problem()` and equal `canonical_item()` of itself (`add`). **A paired item** must be what the writers could make of its base line: **replaying the net change of the fields `item_key` strips** (the tick, `Due:`, `Hide until:`, new replies, `Decided:`, `Closed:`) through `edit_line` on the base line, in the writers' order (`due`, `snooze`, each new `reply` oldest first, `decide`, `done`), with each action's values and dates read back from the added line, gives the added line byte for byte; **or** the same replay on `canonical_item(base line)` does (`fmt` first, then the edits, as §6's bump PR does). **The read-back** takes `Closed:` first (its date, and its why: the text after the first ` — ` following the date, less a final `.`), then cuts it with `item_key`'s own cut (ledgerboard :1113; reuse it, not a second regex) and reads `Due:`, `Hide until:`, the replies and `Decided:` from that open form, since `DECIDED_RE` is anchored at the line's end (:815-816). **On a line whose text doesn't end a sentence before its fields** (only an old line `fmt` refused; `item_problem` enforces the period on any canonical one), `decide` adds the period and a reply doesn't, so the replay also tries the new replies after `decide`; either order passing passes. Replay keeps the head verbatim (`edit_line`), so an old line `fmt` refused (an unbackticked `(session x on host)` head) still takes a writer's `snooze`, `reply` or `done`, while any hand change outside those fields can't reproduce and fails. Rule 1 doesn't catch a well-formed `Decided:` without `by` (`edit_line` accepts `by=None`); rule 3 does. No fault-message comparison is needed: `item_problem()` is used only on new lines. Failures name `fmt` for an open line and `done` for a closed one.
2. **A new item** (no pair) must be open (rule 4), and passes `board_problems(head, base)`'s checks for its line, so a `decide` whose gate person isn't on `People:` fails. **A new open `decide` has its detail block** (§3.3: *a `decide` always has the block*): `detail_block()` (ledgerboard :1129) of the item has a line matching `^- \*\*(Context|Question|Recommended):\*\* ` for each of `DECIDE_NEEDS` (:1509, written capitalised by `_detail_lines`, :1571) (`add`). A `decide` whose added line carries a `Decided:` that `parse_decided` reads is exempt (that is what `add --decided` writes, through `decided_line()`, with no block; a hand-typed decided line is exempt the same way, and rule 3 still holds it): the block is for an open question. Rule 2 uses `board_problems(head, base)` only for its gate-person check.
3. **A new or changed `Decided:`** carries `(by <person>)`, and on a board with `People:` the person is on it (`decide`). A `Decided:` without `by` stays valid where it already was (SPEC); only a new or changed one is held to the writer's form.
4. **A closed line** (`- [x]`) has a pair (a closed line with no twin fails, `done`) and a `Closed: <date> — <why>.` that `CLOSED_RE` reads, last on the line (`done`).
5. **A removed item line with no added pair** is a deleted item, which §3.4 forbids, unless the same PR archives it: the head archive gains an appended line with the same `item_key` (`done`, then `archive`). On an open PR, each of its commits that touches the archive must itself be a `board-archive` commit (§2, which includes a standalone `archive`), so a PR whose `snooze` commit is followed by a threshold `done` passes, and a hand move to the archive doesn't. A merged PR is squashed into one commit under its own title, and nothing forces the row to have run before the merge, so a merged PR gets a **net check** that needs no per-commit view: every item line the archive gains is a closed item whose `Closed:` `CLOSED_RE` reads (rule 4's test), or an open twin sharing a gained closed item's `item_key` (which `archive_closed` moves with it); the other lines it gains are blank (`archive_closed` adds a separator after an archive ending in prose, :2171-2173) or sit in those items' detail blocks; the board's removed item lines that rule 1 left unpaired are exactly those gained item lines or, paired by `item_key`, their open base forms; and the archive gains at least `ARCHIVE_AT` closed item lines (`archive_closed` moves every closed line, so a writer's archive never gains fewer; open twins don't count). A hand move of one open item into the archive fails it. Under decision 1, a hand close in the writer's form plus a hand move at the threshold passes, since it is what the writer would have written. **Most hand slips land here**, because `item_key` strips only well-formed fields: a `Due: nonsense`, a malformed reply or a `Decided:` with no date changes the key, so the line is unpaired. When a removed line that fails this rule shares its `<kind> <date> (<head>) —` prefix with an unpaired added line, the message reports them together as *a line changed outside the writer's fields* (`fmt`, or the command for the field). The pairing is for the message only: the verdict is the same, and both lines' failures are still listed.
6. **Preamble:** `board_problems`' `People:` checks fail only when the diff touches the `People:` line; a fault on an untouched one, or a missing one, is ℹ.

**What the gate cannot know** is who typed a line: a `Decided: Go (by alex)` in the writer's form passes whoever wrote it. Proving who answered is review's job and, for lifts, ledgerboard v2.4's (`lift_pr_verdict`). The gate holds the form.

**Not judged:** detail-block text (beyond rule 2's three leads on a new `decide`), lines the diff leaves alone (so a board that never had its `fmt` pass still accepts an unrelated edit), the archive file's own lines (the `board-archive` class checks a tool's move), and other preamble lines (the sweep's stamps, already a `classify_direct` class).

The row is `na` on a PR that doesn't touch the board. The direct-commit audit applies the same rules to a direct board commit (its diff is the commit's).

### 4. The rule, in cadence.md

- **§2.12** keeps the ledger's rule. **§3.4** gains its board twin, and a sentence beside both says it once for the two files: *in every repo that uses ledgerboard, a session writes the ledger through `ledger.py` and the board through `board_edit.py`, and a consumer's code writes through ledgerboard's writers (reading and checking may call the module's pure functions, as this row does); a hand edit is accepted only if the gate would accept the writer's output.*
- **§3.3**'s entry format becomes a pointer: the line's shape is ledgerboard's (SPEC *The board*), written by `board_edit.py add`; the template block stays as an illustration of the detail block.
- **§3.4**: the archive paragraph is replaced by §2 above, and its sentence on a merge that leaves two open copies of one item changes from the session *dropping* the wrong one to *closing* it (`board_edit.py done --why "duplicate of …"`), which rule 4 accepts and the next archive removes; a dropped line would fail rule 5. `cadence-rationale.md:138`'s archive paragraph is a dated rationale and stays, with one sentence pointing at §2.
- **§3.5**: `decide`, `reply`, `snooze` and `done` are already `board_edit.py` commands; it gains `add`.
- **The nudge's own advice** (`files/scripts/nudge_user_attention.py`) changes with the rule: `twin_note` (:287-289, "keep the right one, drop the other") points at `board_edit.py done --why "duplicate of …"`, and `archive_note` (:271-272, "in a PR of its own") at `board_edit.py archive` (or the next `done`, which archives at the threshold), so a session following the board's own nudge never lands in a gate failure. The same holds for `item_tag`'s report advice (:336, :339): an unparseable `Due:` ("write Due: YYYY-MM-DD"; the bad field is in the key, and `due` appends a second `Due:` rather than repairing it) and an `fyi` carrying a `Due:` ("drop it"; no writer removes one) both point at the `done`-plus-`add` pair below. The nudge's other item advice names its commands too: an escalated item's "ledger it and close it here" (:348) and the session-start text's "ledger each as a TD and close it on the board" (:1749-1750) become `ledger.py new` then `board_edit.py done`, and "triage or ledger them" on an oversized board (:296, :1752) names `board_edit.py done` (and `ledger.py new` for what moves to the ledger). **The general rule:** every piece of advice a script prints that would change an **item line** (`- [ ]` or `- [x]`) names a writer command or the `done`-plus-`add` pair, never a hand edit; preamble stamps (`Swept:`, `Swept-deep:`, `Harvested:`, whose "fix the date" advice is at :708-741) stay hand edits, as §3 leaves them. Only the nudge prints item advice today (the other scripts' "by hand" messages are about other files). **The test enforces it:** it runs the nudge's `--report` and its session-start text on a fixture board that triggers every condition (a twin, the archive threshold, an oversized board, an escalated item, an unparseable `Due:`, an fyi with a `Due:`) and asserts each item-advice line names `board_edit.py` or `ledger.py`. The build also greps `files/scripts/` for printed strings holding `Due:`, `drop`, `move`, `keep` or `write` without either command, as a prompt for the builder, not as the check.
- **§4.4** (service-account appends): "in the documented `Format:` shape" becomes "a line ledgerboard's `item_line()` would write" (SPEC *The board*); such an append is a new item and meets rules 1–2 like any other.
- **Correcting an item's text** (§3.11, TD-138: the sweep fixes a wrong cause or diagnosis "on the line") has no writer, since a changed text is a changed key. It becomes a pair: `board_edit.py done --why "superseded by a corrected item"` on the old line and `add` of the corrected one, in the same PR. §3.11 says so. No text-edit command is added: the closed line keeps what was said, which the person may have read.
- **The seed board** (`files/docs/user_attention.md`, copied into every adopted repo): its `Format:` template line becomes the same pointer as §3.3 (written by `board_edit.py add`), and its closing sentence on archiving "in a PR of their own" becomes §2's rule.
- `cadence-changes.md`: one entry.

### 5. Procedures

The steps that type a board line become commands: cadence.md's TD-084 example (the `decide` with a detail block, at :61ff) becomes the `board_edit.py add` call that writes it, followed by the line it writes. The procedures were searched for steps that type an item line: `stranded-work.md`'s step 1 (:21) hand-archives closed items "in a PR of its own" and corrects a wrong item "on the line": both become commands (`board_edit.py archive`, and the `done`-plus-`add` pair above); its preamble stamps stay hand edits (§3 leaves them alone); `attention.md` already uses `board_edit.py` (:72), and its list gains `reply` and `add`; `memory-harvest.md` reads the board only. Any step found in review is converted the same way.

### 6. Rollout

- Each repo gets the row when it bumps its agent-cadence pin to this release (decision 2). The bump PR runs `board_edit.py fmt` on its board once, so later PRs start from a canonical board; `fmt` refuses lines whose key would change, and those stay as they are (the gate does not judge untouched lines).
- agent-cadence, ShiftLead and ledgerboard bump first; the roster repos with their remodels.
- The build PR rewrites TD-206's Done when (which still waits on every roster board's `fmt` pass) to this.
- **Done when** (replacing TD-206's): `board_edit.py` exposes `add`, `archive`, `fmt` and `list`; `done` archives at the threshold; the `board` row fails a hand-typed item line the writer would not write; cadence.md states the rule for both files; and agent-cadence's own board has had its `fmt` pass.

## Tests

- `add` for each kind, with answers, a default and a detail block, round-tripping through `item_problem()`; the wrapper's flags equal board.py's.
- `done` on the tenth closed item: one commit, board and archive, subject `… done <head>; archived <n> (session s)`; `classify_direct` returns `board-archive`, by the direct path and by the PR path (`row_board_edit_pr`, two files); with any extra change, it fails. `done` at nine closed: the plain `board-edit` class. `done` when `archive_closed` refuses: a plain `done` and a warning.
- A standalone `archive` commit passes the class; one that alters a moved line fails. A `Closed:` dated a day before the check still recomputes.
- The `board` row, each failing case naming its command: a new malformed line (`add`); a same-key reshaped line, e.g. `Due:` moved before `Context:` (`fmt`); a hand close with no `CLOSED_RE` field (`done`); a hand `Decided:` without `(by …)`, and one by someone not on `People:` (`decide`); a new open `decide` with no detail block (`add`); an indented item inside a detail block (`add`: `item_problem` wants column 0); a deleted open item (`done`).
- The nudge's `--report` and session-start text (`--report --due-only --board <fixture>`, so no roster is read), on a fixture board that triggers every condition, print item advice that names `board_edit.py` or `ledger.py` on every line (`archive_note`, `twin_note`, `item_tag`'s two, the escalation in both texts, and the oversized board); stamp advice is exempt.
- Replay: every order of `due`, `snooze`, `reply`, `decide` and `done` on a canonical line, an old head, a decide with Answers and an fyi reproduces, including `decide` then `done` (the read-back cuts `Closed:` first); `decide` then `reply` on a line `fmt` refused passes (the second order); a PR that hand-types `Due: nonsense` onto an old line fails as *changed outside the writer's fields*; the same line plus a writer `snooze` passes; a canonical line plus `fmt`'s rewrite and a `reply` passes; a hand-typed second `Due:` fails.
- A merged PR that hand-moved one open item into the archive fails the net check, as does a closed line moved with no `Closed:`; a merged PR with a `snooze` and a threshold `done` passes it, including into an archive ending in prose.
- The class refuses `done <x>; archived 1` on a board below `ARCHIVE_AT`, and a subject whose `<n>` differs from `archive_subject()`'s count.
- Passing cases: a PR whose `snooze` commit is followed by a threshold `done` that archives, open and after its squash merge; a hand-typed line the writer would write; `snooze`, `reply` and `done` on an old line `fmt` refused; `add --decided` (no block); a PR that replies, decides and then closes one item; a moved item; a reordered section; two open items sharing a key, one closed; an untouched malformed line beside an unrelated edit; a detail-block edit; a faulty `People:` line the PR doesn't touch (ℹ); a multi-commit PR judged on its merge-base diff.
- `classify_direct` on a direct `add` with a detail block, and on an `fyi`: `fail` (they land by PR).
- `reply` without `--by` on a multi-person board is refused; on a one-person board it defaults to that person. `fmt` refuses a key-changing line and lists it; `list --json` gives the open items.
- Rule 2: a new `decide` whose gate person is not on `People:` fails. Rule 3: an untouched old `Decided:` without `by` passes; the same line changed fails. Rule 4: a closed line with no pair fails. Rule 5, open PR: a hand-appended archive commit fails the per-commit class check. Rule 6: a PR that touches `People:` and leaves a fault fails.
- The row's failure is `fail`, not ℹ (decision 5); the direct-commit audit applies the same rules to a direct board commit.
- §2: a standalone `archive` on a base below `ARCHIVE_AT` fails the class; the merged net check fails a hand move of a lone closed item below the threshold, and a hand close from a base of eight closed (nine, plus an open twin) followed by a hand move (nine closed lines gained); a threshold `done` whose archive also moves an open twin passes.
- Two open copies after a merge: closing one as a duplicate passes; deleting one fails (rule 5).
- A corrected item: `done` on the old line plus `add` of the new one in one PR passes; editing the old line's text in place fails as *changed outside the writer's fields*.

## Not in this design

- ShiftLead's sessions and code (shiftlead#TD-1286).
- The two-file decide lift (ledgerboard v2.4, TD-034) and `lift_pr_verdict`: v2.4's vendor PR widens the carve-out.
- A `board.py stamp` command for the sweep's stamp lines: they stay hand edits, outside the gate.

## Review rounds

| Round | Reviewer | Blockers | Should-fix | Nits | Verdict |
|---|---|---|---|---|---|
| 1 | Fable | 1 | 4 | 3 | NOT CONVERGED |
| 2 | Sonnet | 1 | 10 | 4 | NOT CONVERGED |
| 3 | Fable | 1 | 2 | 5 | NOT CONVERGED |
| 4 | Sonnet | 0 | 3 | 3 | NOT CONVERGED |
| 5 | Fable | 1 | 2 | 4 | NOT CONVERGED |
| 6 | Sonnet | 0 | 1 | 4 | NOT CONVERGED |
| 7 | Fable | 0 | 2 | 3 | NOT CONVERGED |
| 8 | Sonnet | 0 | 1 | 5 | NOT CONVERGED |
| 9 | Fable | 0 | 2 | 2 | NOT CONVERGED |
| 10 | Sonnet | 0 | 1 | 3 | NOT CONVERGED |
| 11 | Fable | 0 | 2 | 3 | NOT CONVERGED |
| 12 | Sonnet | 0 | 0 | 3 | CONVERGED |
| 13 | Fable | 0 | 1 | 2 | NOT CONVERGED |
| 14 | Sonnet | 0 | 2 | 1 | NOT CONVERGED |
| 15 | Fable | 0 | 1 | 2 | NOT CONVERGED |
| 16 | Sonnet | 0 | 3 | 0 | NOT CONVERGED |
| 17 | Fable | 0 | 0 | 2 | CONVERGED |
| 18 | Sonnet | 0 | 0 | 0 | CONVERGED |

**Round 1 (Fable), all taken in draft 2:**
- *Blocker:* the gate judged only new item keys, so same-key hand slips (a `Decided:` without `by`, a moved `Due:`, a hand close) passed. Now it judges the diff's added lines (§3).
- *Should-fix:* the auto-archive commit had no path through the audit (subject, `classify_direct`, the recomputation was on the wrong board); now one `board-archive` class (named `board-done-archive` in draft 2) (§2). Standalone `archive` and `add` had no stated landing (§2). An untouched faulty `People:` line would have failed every PR (§3). `add`'s flags didn't match board.py (§1).
- *Nits:* the example's line number; `attention.md`'s list; three more tests.

**Round 2 (Sonnet), all taken in draft 3:**
- *Blocker:* round 1's fix still passed a hand `Decided:` without `by` on an open line, because the shape check can't see it. §3 now judges each item's net change by fixed rules, including rule 3 for `Decided:`, and says plainly that who typed a line is beyond the gate.
- *Should-fix:* the closed-line recomputation ignored `today` and failed a multi-edit PR (the rules judge the net result instead); the diff was one commit (merge-base now); moved lines and reorders (byte-equal lines cancel); item vs detail lines (`ANY_ITEM_RE`); the detail block of a new `decide` (rule 2); `board_problems`' gate-person rule (rule 2); how the archive class finds its item, with `today` and `why` read back (§2); the plumbing (§2); `archive_closed` refusing (§2).
- *Nits:* the rule's wording on module functions (§4); deleted items (rule 5); test gaps (all added). `_board_diff`'s `---` skip doesn't touch item lines.

**Round 3 (Fable), all taken in draft 4.** It confirmed rounds 1 and 2 closed: rule 1 passes every writer output it generated (each kind, stacked edits, `Lifts:`, `Hide until:`), no writer changes an item's key, and the archive recomputation is exact.
- *Blocker:* rule 1 failed a writer's edit on an old line `fmt` refused, leaving it unclosable. A paired line is now judged "no worse than its base line".
- *Should-fix:* `add --decided` writes a `decide` with no block, which rule 2 failed (exempt now); rule 2's detail check is now exact (`detail_block()` and the three leads).
- *Nits:* an indented item is a failing case; `done`, not `fmt`, for a closed line; the archive class no longer excludes a key already closed; citations; `reply --by`'s resolution.

**Round 4 (Sonnet), all taken in draft 5.** It confirmed round 3's answers on paper, and that a canonical base forces a canonical result.
- *Should-fix:* "faults are a subset" was ill defined (`item_problem` returns one string, some messages hold `; `); and a hand slip could hide behind an existing fault, since `item_problem` returns early on a head with no ` — ` (:1796-1798). Rule 1 for a paired item is now a replay of the net field changes through `edit_line`, byte for byte, on the base line or on its `fmt` form; no fault comparison remains. The `add --decided` exemption is keyed on a parseable `Decided:`, not on the head.
- *Nits:* citations; rule 2 uses `board_problems` only for the gate person; the replay tests.

**Round 5 (Fable), all taken in draft 6.** It ran the replay over 309 orderings of up to three writer edits on five base lines, plus hand slips.
- *Blocker:* the read-back couldn't see `Decided:` or replies on a closed line (`DECIDED_RE` is end-anchored), so `decide` then `done` failed. It now reads and cuts `Closed:` first; with that, 309 of 309 pass on every base.
- *Should-fix:* on an old line whose text lacks a closing period, `decide` and `reply` give different text by order; the replay tries both. Most hand slips change the key and so surfaced as a deletion; rule 5 now reports them as a line changed outside the writer's fields.
- *Nits:* rule 3 named as what catches a `by`-less `Decided:`; "`fmt` first, then the edits"; how `why` is read; confirmations recorded in the tests.

**Round 6 (Sonnet), all taken in draft 7.** It ran rule 1 over 309 sequences on each of five bases and 193 on an fyi: 0 failures; every hand slip it tried fails; rule 5's prefix pairing can swap two same-day items but changes only the message.
- *Should-fix:* a multi-commit PR with a `snooze` and then a threshold `done` would show the archived item as deleted, since the archive gains the closed form, not the base line. Rule 5 now exempts a removed line whose `item_key` the head archive gains, and requires every commit touching the archive to be a `board-archive` or `archive` commit.
- *Nits:* the message pairing is for failing lines only; rule 2's closed-line clause merged into rule 4; the class's old name; reuse `item_key`'s `Closed:` cut.

**Round 7 (Fable), all taken in draft 8.** It confirmed rule 5's answer on an open PR: a hand deletion can't pass by hand-appending to the archive (that commit fails the class), and every function the class needs exists.
- *Should-fix:* after a squash merge the PR is one commit under its own title, so the per-commit requirement failed it in the weekly check; the per-commit check now applies to an open PR, and a merged one rests on the archive gaining the key, with the merged diff stated (§3). The class ignored `ARCHIVE_AT`, so `done <x>; archived 1` would skip review; it now requires the threshold and `<n>` to match (§2).
- *Nits:* `<n>` is `archive_subject()`'s count; the example's citation; the build PR rewrites TD-206's Done when.

**Round 8 (Sonnet), all taken in draft 9.** It confirmed the threshold and count (b), and that the merged diff matches the ledger row.
- *Should-fix:* nothing forces the row to run before a merge, so a hand move into the archive in a PR nobody checked would pass the post-merge sweep on "the archive gains the key". A merged PR now gets a net check: gained archive lines are closed items, the board lost exactly those (or their open base forms), and the base was at the threshold less one.
- *Nits:* `<n>` is `len(closed_items(...))` of the right board; the `ARCHIVE` path is named; `<n>` is read from the subject's last `; archived N (session`; the `done` threshold restated as the base holding `ARCHIVE_AT − 1`; tests updated.

**Round 9 (Fable), all taken in draft 10.** It ran 16 scenarios over the vendored module: the net check passes real squashed writer archives and fails a hand move of an open item, a fabricated archive line and a close that also edits the text.
- *Should-fix:* `archive_closed` adds a blank separator after an archive ending in prose, which the net check rejected; blank gained lines are now allowed. "The board's lost item lines are exactly …" read universally would fail a squashed snooze + `done`; it now says the removed lines rule 1 left unpaired.
- *Nits:* a moved closed line must carry a `Closed:` `CLOSED_RE` reads; a hand close and move at the threshold in the writer's form passes, under decision 1; one citation.

**Round 10 (Sonnet), all taken in draft 11.** It confirmed round 9's fixes with its own harness, and found no contradiction or stale text.
- *Should-fix:* rules and behaviours without a test (rule 2's gate person, rule 3's untouched old `Decided:`, rule 4's twinless closed line, rule 5's open-PR half, rule 6's touched `People:`, the hard-fail status, the direct audit, `fmt`'s refusals, `list --json`, `reply`'s one-person default, a below-threshold `archive`); each now has one.
- *Nits:* `fmt` lands by ordinary review; the net check's threshold was tightened to match the class's (refined in round 11); `<n>`'s place in the subject.

**Round 11 (Fable), all taken in draft 12.** Every genuine writer output passed both readings of the new threshold over nine scenarios.
- *Should-fix:* the threshold counted open twins, so a hand close and move at nine closed passed; it is now "the archive gains at least `ARCHIVE_AT` closed item lines". cadence.md §3.4 told a session to *drop* a duplicate open copy after a merge, which rule 5 fails; §4 now changes it to *closing* it.
- *Nits:* the open-PR wording; `cadence-rationale.md:138` stays as rationale with a pointer; round 10's note reworded.

**Round 12 (Sonnet): CONVERGED.** Its harness confirmed the new threshold (every writer archive passes; a lone closed move at nine, and a hand close plus move from eight with an open twin, fail), and that closing one of two duplicate copies passes rules 1, 4 and 5. Its three nits (a test's wording, a repeated sentence on `<n>`, "no pair") are taken in draft 13.

**Round 13 (Fable), taken in draft 14.** Round 11's fixes confirmed closed.
- *Should-fix:* the nudge's `twin_note` and `archive_note` still told a session to drop a duplicate and to archive in a PR of its own, both of which the gate now fails; §4 changes them.
- *Nits:* `<n>` for a standalone `archive` is read from `ARCHIVE_SUBJECT_RE`; round 8's note is history.

**Round 14 (Sonnet), taken in draft 15.** It confirmed round 13's answers against the code and swept the repo for other text that steers a session into a gate failure.
- *Should-fix:* `stranded-work.md:21` hand-archives closed items, and §5 wrongly said it writes only stamps; the seed board repeats the hand-archive advice and keeps a typed-line template. §4 and §5 now list all three.
- *Should-fix (design gap):* §3.11 and the sweep correct an item's text in place, which changes its key and fails rules 1 and 5, and no writer does it. It is now a `done` plus `add` pair, stated in §3.11, with a test.
- *Nit:* dated records (cadence.md §4.5's history, cadence-changes, the rationale) stay.

**Round 15 (Fable), taken in draft 16.** Round 14's answers confirmed against the files, and the `done`-plus-`add` pair shown to pass rules 1–5.
- *Should-fix:* `item_tag`'s report advice told a session to fix an unparseable `Due:` and to drop an fyi's `Due:` by hand, neither of which a writer can do or the gate accepts; both now point at the pair, and §4 states a general rule (a script's advice names a command, with a grep in the build and a test) so this class is closed rather than chased.
- *Nits:* §4.4's "documented `Format:` shape" follows the seed's pointer; a test's wording.

**Round 16 (Sonnet), taken in draft 17.** It confirmed round 15's answers and judged the general rule.
- *Should-fix:* the rule's scope was undefined and, read literally, caught the stamps §3 leaves as hand edits; it now covers item lines only. Three more item messages named no command (an escalation's "ledger it and close it here", "triage or ledger them" twice); they now do. The test was narrower than the rule; it now runs the nudge's whole report and session-start text on a fixture board with every condition, and the grep is a prompt for the builder, not the check.

**Round 17 (Fable): CONVERGED.** The general rule is precise (item lines only, stamps exempt), the report-level test is wider than the list so a new hand-edit message fails at build time, and no contradiction or open decision remains. Its two nits are taken in draft 18: the session-start escalation message (:1749-1750), and the test's command (`--report --due-only --board <fixture>`).

**Round 18 (Sonnet): CONVERGED**, no findings: round 16's three should-fixes confirmed closed against the nudge, every cited line matches, and §1–§6, the tests and this record agree.
