#!/usr/bin/env python3
"""Recompute the aggregates and write design-rounds.md from design-rounds.json.

Usage: python3 aggregate.py            (run in this directory; reads design-rounds.json,
                                        rewrites design-rounds.md; stdlib only)
Everything in the md except the hand-written prose in PROSE_* below is computed here.
"""

import json
import os
import statistics as st
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, "design-rounds.json")))
AGED_BEFORE = "2026-10-27"  # a design counts as "aged" for post-build purposes if reviewed before this date


def med(xs):
    return st.median(xs) if xs else None


def fmt(x):
    if x is None:
        return "n/a"
    return ("%g" % x) if isinstance(x, float) else str(x)


rounds_recs = [r for r in D if r.get("mode", "rounds") == "rounds" and r.get("reviews") and r.get("rounds")]
parallel = [r for r in D if r.get("mode") == "parallel"]
no_count = [r for r in D if r.get("mode", "rounds") == "rounds" and not (r.get("reviews") and r.get("rounds"))]


def by(cls, recs=None):
    return [r for r in (recs if recs is not None else rounds_recs) if r["class"] == cls]


def last3(r):
    """Index (1-based) of the last review with >=3 findings; None if findings are not known for at least half the reviews."""
    d = r.get("reviews_detail") or []
    if not d:
        return None
    known = [x for x in d if x.get("total_findings") is not None]
    if len(known) * 2 < len(d):
        return None
    idx = [x["n"] for x in known if x["total_findings"] >= 3]
    return max(idx) if idx else 0


def block(recs, label):
    rv = [r["reviews"] for r in recs]
    rd = [r["rounds"] for r in recs]
    cnt = Counter(rd)
    dist = ", ".join("%s x%d" % (fmt(k), v) if v > 1 else fmt(k) for k, v in sorted(cnt.items()))
    out = {}
    for lim in (3, 4, 6):
        k = sum(1 for x in rd if x <= lim)
        out[lim] = (k, len(rd))
    return dict(n=len(recs), rv=(med(rv), max(rv) if rv else None, min(rv) if rv else None), rd=(med(rd), max(rd) if rd else None, min(rd) if rd else None), dist=dist, within=out)


def l3(recs):
    vals = [(r, last3(r)) for r in recs]
    vals = [(r, v) for r, v in vals if v is not None]
    idx = [v for r, v in vals]
    rds = [v / len(r["models"]) for r, v in vals]
    return dict(n=len(vals), med_idx=med(idx), min=min(idx) if idx else None, max=max(idx) if idx else None, med_rounds=med(rds))


def pb(recs):
    aged = [r for r in recs if r["date"] < AGED_BEFORE]
    hard = [r for r in aged if any(not d["what"].startswith("(questionable)") for d in r["post_build_defects"])]
    soft = [r for r in aged if r["post_build_defects"] and r not in hard]
    return dict(all=len(recs), aged=len(aged), hard=len(hard), soft=len(soft))


inrepo, wide = by("in-repo"), by("wide")
B_in, B_wide = block(inrepo, "in-repo"), block(wide, "wide")
L_in, L_wide = l3(inrepo), l3(wide)
P_in, P_wide = pb(inrepo), pb(wide)


# a split by source kind and by era, for context
def era(r):
    return "to 10-17" if r["date"] <= "2026-10-17" else "from 10-18"


low = [r for r in inrepo if r["rounds"] <= 3]
high = [r for r in inrepo if r["rounds"] > 3]
P_low, P_high = pb(low), pb(high)
kinds = Counter(r.get("source_kind") for r in D)
onemodel = [r for r in inrepo if len(r["models"]) == 1]
twomodel = [r for r in inrepo if len(r["models"]) >= 2]
tok = sum(x["tokens"] for r in D for x in (r.get("reviews_detail") or []) if x.get("tokens"))
ntok = sum(1 for r in D for x in (r.get("reviews_detail") or []) if x.get("tokens"))
nrev = sum(r["reviews"] or 0 for r in D)


def per_review(r):
    d = r.get("reviews_detail")
    if not d:
        return ""
    s = []
    for x in d:
        f = x.get("total_findings")
        s.append((x["model"][:1].upper()) + ("" if f is None else str(f)) + ("*" if x.get("verdict") == "READY" else ""))
    return " ".join(s)


def pbtxt(r):
    return "; ".join(d["where"] for d in r["post_build_defects"]) or "-"


def row(r):
    return "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
        r["repo"],
        r["plan"][:70].replace("|", "/"),
        r["date"],
        r["class"] + ("" if r.get("mode", "rounds") == "rounds" else " (parallel)"),
        r.get("source_kind"),
        fmt(r["reviews"]),
        fmt(r["rounds"]),
        r.get("stop") or "?",
        per_review(r),
        pbtxt(r),
    )


CAVEATS = """## Caveats (where the data is thin)

- **The regime is one policy, almost entirely.** %(n_sl)d of the %(n_all)d designs are ShiftLead's, nearly all from 2026-10-04 to 10-30, under the rule "iterate until READY" with no cap (and, from 10-15, a Sonnet and a Fable review on every round). The counts show how long an uncapped loop runs, not what a cap would have lost. Several loops stopped by override or fatigue (TD-1022, TD-978, TD-941, TD-909) and TD-1025 ran 30 reviews (15 rounds); "converged" is read from the final verdict, so it includes "stopped on follow-ons".
- **Wide is still thin: %(n_wide)d designs in the aggregates**, 4 of them ShiftLead TDs with only total findings, 1 (ledger-writer) with build-changing counts and tokens and still unbuilt, and one (id-provenance) decided 10-28. Post-build evidence for wide rests on about 3 designs (pinned-not-synced, ledger-ids, ledger-per-entry). The extension added one wide record, and settled counts for two (hard-rename 4 reviews, ledger-ids 5 reviews of Sonnet 1,3,5 and Fable 2,4).
- **Findings are not build-changing counts.** Only the ledger-writer plan has a build-changing split. The "last review with 3+ findings" statistic uses total findings per review: from design-history lines for ShiftLead TDs, and, for the %(n_tr)d transcript-sourced designs, parsed from the first lines of each hand-back (an explicit "N findings", else the highest numbered item). Where the hand-back came by message and is not in the transcript the count is blank, and a design needs counts for at least half its reviews to enter that statistic. Parsed counts can include nits and notes.
- **Post-build defects are a lower bound, and the two batches were found differently.** The first pass read the ledger entries citing each TD. The extension listed every ledger entry citing each added TD (after the design date, builds and backfills excluded) and judged each by its title and the citing sentence; a pure regex over the citing sentences found only 1 of the first pass's 5 known defects, so it was not used. Even so the 44 added in-repo designs show %(ext_hard)d clear and %(ext_soft)d questionable defects against %(first_hard)d clear in the first pass; most of that gap is how hard each batch was searched and how recent the designs are (only 3 of the 44 are dated 10-26, but the first-pass set carries 10-27..10-30 designs that are not aged), not evidence that the added designs are cleaner. Test-gap entries (the test-audit TDs) are excluded in both batches as not design gaps.
- **Transcript counts.** Each review is one Agent call (de-duplicated by model and round number, or by prompt text for the non-TD plans); async launches are matched to their `<task-notification>` for tokens and the hand-back text. Where a plan numbers single reviews (ShiftLead history, hard-rename) rounds = reviews / models; where it numbers pairs (the 10-15..10-17 designer runs) the pairs were launched together, so rounds = pairs, the same arithmetic. A round in which only one of Fable and Sonnet was launched counts as half. The Sonnet-only designs of 10-09..10-15 (TD-418, 681, 682, 688, 692, 693, 702) have rounds = reviews.
- **One-round designs.** Seven added designs (TD-816, 818, 819, 820, 821, 823 of 10-17 and TD-900 of 10-19) are one Fable design review plus one Sonnet fact-check (TD-900: Opus plus Sonnet) of a design PR, counted as 1 round; whether that is a design round or the pre-merge PR review is a judgement call. Without them in-repo is 76 designs: 24 within 3 rounds (32%%), 47 within 4 (62%%), 67 within 6 (88%%), median rounds still 4.\n- **Classification is mine and debatable**, as before. Every added design except id-provenance is classed in-repo ("changes only ShiftLead"); TD-1033 (the repo's gate moves to a local precheck) and TD-1025 (rule 12 for pinned repos) touch dev-cadence's mechanics but edit only ShiftLead. Reclassifying shifts the wide numbers by 1-4 designs.
- **Long-lived designs were split or lumped by judgement.** TD-307's flows section was reworked by Paul after a READY and is recorded as two records (first draft: 5 Fable reviews; rework to v3: 17 reviews incl. confirms); TD-818 and TD-722 amendments are separate from the original design; the two Queue ADRs are separate records from TD-748 and TD-909, which sit downstream of them. If a lineage is counted as one design its round count is the sum.
- **Prose-sourced records** (TD-100 four Sonnet rounds, TD-103 eight Sonnet plus a closing Fable, TD-057 step 3c two Fable reviews, TD-069 and TD-070 one Sonnet review each) carry no per-review detail. The two dev-cadence plans of 2026-08 are parallel-lens reviews (two Sonnet lenses plus a verification), recorded with `mode: "parallel"` and kept out of every aggregate.

### Skipped, and why

- **TD-1190** (Add entry form lines): reviews launched 10-30 and the hand-backs are not in the transcript; may still be in progress.
- **agent-cadence TD-203** (this rounds plan): its own review loop is still running.
- **TD-787** (held-PR mark): the ledger entry lists Fable rounds 1-3 and Sonnet rounds 1-2, design-history says "Fable rounds 1-4 and Sonnet rounds 1-3"; 5 or 7 reviews, unresolved.
- **TD-158** (dev-cadence plan, one Fable review) and **TD-345** (a scoped Fable review): one review each with no hand-back text; **TD-052 section 4.10** (four Fable reviews and an unstated number of Sonnet ones).
- **TD-964's first round** (the td-156 session, TD-942 in the review prompts) is already in the set as TD-964; **TD-1119, TD-975** have history lines but no transcript, and kept their history counts.
- **ledger-per-entry** stays in the table with its defects but has no review count, so it is outside the aggregates.
- **Single design-PR fact-checks** of 09-22..10-12 (TD-177, 208, 240, 245, 246, 254, 351) were read as the per-PR review, not a design review. Research ADRs (herdr, paperclip, hermes, muse, grok bot, monetisation, prior art, cloud sessions) have no review record.
- **Codex and Gemini CLI stores:** ~/.codex has empty goals, memories and logs tables and ~/.gemini holds only credentials and project markers; neither holds a design review.
- Transcripts of the symlinked `agentorc` project directories duplicate the `shiftlead` ones and were read once (the Claude project store has 2,889 session files).
"""


def w(s=""):
    lines.append(s)


lines = []
w("# Design-review rounds on this machine: data for the max-rounds defaults")
w()
w(
    "Extended 2026-10-30 from 50 to %d designs (read-only research; machine-readable twin `design-rounds.json`; aggregates recomputed by `aggregate.py` in this folder, rerun it after any edit to the json)."
    % len(D)
)
w()
w(
    "**What counts.** A design review is one model reviewing a plan or design before the build (the per-PR pre-merge review is not counted). A **round** is one pass through the models in use, so rounds = reviews / number of distinct models (Sonnet+Fable alternating: 11 reviews = 5.5 rounds; Sonnet alone: rounds = reviews). **Wide** = costly to fix after shipping (another repo, a vendored or published format, an irreversible step); else **in-repo**. A **build-changing** finding is recorded only where the source says it (still only the ledger-writer plan)."
)
w()
w(
    "**Records by source kind:** "
    + ", ".join("%s %d" % (k, v) for k, v in sorted(kinds.items()))
    + ". Records in the aggregates (mode `rounds`, review count known): %d; kept out: %d parallel-lens plans (`mode: parallel`, not rounds), %d designs with no review count (listed in the table, no aggregate)."
    % (len(rounds_recs), len(parallel), len(no_count))
)
w()
w("## Aggregates (recomputed by aggregate.py)")
w()
w("| | designs | reviews: median / max / min | rounds: median / max / min |")
w("|---|---|---|---|")
for lab, B in (("in-repo", B_in), ("wide", B_wide)):
    w("| %s | %d | %s / %s / %s | %s / %s / %s |" % (lab, B["n"], *map(fmt, B["rv"]), *map(fmt, B["rd"])))
w()
w("- **Distribution of in-repo rounds** (%d): %s." % (B_in["n"], B_in["dist"]))
w("- **Distribution of wide rounds** (%d): %s." % (B_wide["n"], B_wide["dist"]))
w(
    "- **In-repo rounds within 3 / 4 / 6:** "
    + ", ".join("%d of %d (%.0f%%) within %d" % (B_in["within"][k][0], B_in["within"][k][1], 100.0 * B_in["within"][k][0] / B_in["within"][k][1], k) for k in (3, 4, 6))
    + "."
)
w("- **Wide rounds within 3 / 4 / 6:** " + ", ".join("%d of %d within %d" % (B_wide["within"][k][0], B_wide["within"][k][1], k) for k in (3, 4, 6)) + ".")
w(
    "- **Median last review with 3+ findings** (designs with finding counts for at least half their reviews; counts are totals per review, parsed from the hand-backs where no history line gave them, so notes can inflate them): in-repo %d designs, median review index %s (= round %s), range %s-%s; wide %d designs, median index %s (= round %s)."
    % (L_in["n"], fmt(L_in["med_idx"]), fmt(L_in["med_rounds"]), fmt(L_in["min"]), fmt(L_in["max"]), L_wide["n"], fmt(L_wide["med_idx"]), fmt(L_wide["med_rounds"]))
)
w(
    '- **Post-build defects** (designs reviewed before %s, so built and aged at least 4 days; a lower bound, found by citation in later ledger entries): in-repo %d of %d with a defect read as a design gap, plus %d with only a "(questionable)" one; wide %d of %d, plus %d questionable. In-repo by rounds: <=3 rounds %d of %d, >3 rounds %d of %d.'
    % (AGED_BEFORE, P_in["hard"], P_in["aged"], P_in["soft"], P_wide["hard"], P_wide["aged"], P_wide["soft"], P_low["hard"], P_low["aged"], P_high["hard"], P_high["aged"])
)
w(
    "- **Models in the in-repo set:** %d designs reviewed by two or more models (median rounds %s), %d by one model (median rounds %s; Sonnet-only plans of 10-09 to 10-15, a Fable-only first draft, and single reviews)."
    % (len(twomodel), fmt(med([r["rounds"] for r in twomodel])), len(onemodel), fmt(med([r["rounds"] for r in onemodel])))
)
w("- **Tokens:** %d reviews carry `<subagent_tokens>`, %d tokens in all (mean %d per review where known); the ledger-writer table is in the json." % (ntok, tok, tok // max(ntok, 1)))
w()
w("### First pass versus extension (does the new data move the picture?)")
w()
w("| batch | class | designs | rounds median | rounds max | within 3 | within 4 | within 6 | last 3+ finding: median index (round) | post-build with defect / aged |")
w("|---|---|---|---|---|---|---|---|---|---|")
for bt in ("first pass", "2026-10-30 extension"):
    for cl in ("in-repo", "wide"):
        rs = [r for r in rounds_recs if r.get("batch") == bt and r["class"] == cl]
        if not rs:
            continue
        rd = [r["rounds"] for r in rs]
        L = l3(rs)
        P = pb(rs)
        w(
            "| %s | %s | %d | %s | %s | %d | %d | %d | %s (%s), n=%d | %d / %d |"
            % (
                bt,
                cl,
                len(rs),
                fmt(med(rd)),
                fmt(max(rd)),
                sum(x <= 3 for x in rd),
                sum(x <= 4 for x in rd),
                sum(x <= 6 for x in rd),
                fmt(L["med_idx"]),
                fmt(L["med_rounds"]),
                L["n"],
                P["hard"],
                P["aged"],
            )
        )
w()
w("## Per-design table")
w()
w(
    "Review column legend: letter = model (F Fable, S Sonnet, O Opus), number = total findings that review reported (blank = not stated), `*` = verdict READY. Findings are NOT build-changing counts. For the history-sourced designs the numbers come from design-history; for transcript-sourced ones they are parsed from the hand-back text (blank where the hand-back came by message and is not in the transcript). Order: original 50 first, then the added records."
)
w()
w("| repo | plan | date | class | source | reviews | rounds | stop | per-review | post-build defects |")
w("|---|---|---|---|---|---|---|---|---|---|")
for r in D:
    w(row(r))
w()
n_sl = sum(1 for r in D if r["repo"] == "shiftlead")
ext_in = [r for r in rounds_recs if r.get("batch") != "first pass" and r["class"] == "in-repo"]
first_in = [r for r in rounds_recs if r.get("batch") == "first pass" and r["class"] == "in-repo"]
pe, pf = pb(ext_in), pb(first_in)
w(CAVEATS % dict(n_sl=n_sl, n_all=len(D), n_wide=len(wide), n_tr=kinds.get("transcript", 0), ext_hard=pe["hard"], ext_soft=pe["soft"], first_hard=pf["hard"]))
open(os.path.join(HERE, "design-rounds.md"), "w").write("\n".join(lines) + "\n")
print("wrote design-rounds.md;", len(D), "records;", len(rounds_recs), "in aggregates")
print("in-repo", B_in["n"], B_in["rv"], B_in["rd"], B_in["within"])
print("wide", B_wide["n"], B_wide["rv"], B_wide["rd"], B_wide["within"])
print("last3", L_in, L_wide)
print("pb", P_in, P_wide, "low", P_low, "high", P_high)
