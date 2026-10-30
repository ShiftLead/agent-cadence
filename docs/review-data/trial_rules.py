#!/usr/bin/env python3
"""Trial of the TD-203 rounds rules (plan revision 18, rules 1, 7, 8, 9) against design-rounds.json.

Stdlib only. Rerun:  python3 trial_rules.py   (writes trial-rev18.md beside it)

Rules simulated
  round   = one pass through the design's own model list (consecutive reviews paired; a trailing
            partial pass counts as a round).
  stop    = stop after a round in which no review raises a build-changing finding (cap round included).
  cap     = in-repo 4 rounds, wide 6. If the cap round still raised one, the rounds end there and the
            person gets a board item ("asked").
  recurring topics: NOT simulated. Topics are not recorded in the data and are not guessed.

Proxy for "raises a build-changing finding" (only the ledger-writer design has real counts; there
build_changing >= 1 is used under both variants):
  primary: verdict is not READY (NOT READY, REVISE, ...), or total_findings >= 3.
  strict : primary, or (verdict not READY and total_findings >= 1).  Strict is a superset of primary.
  Unknown review (no verdict, no count): primary = no raise; strict = raise (upper bound).
  Verdict None with a count: primary uses the count only (>=3); strict raises on >= 1.
"""

import json
import os
import statistics
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "design-rounds.json")
OUT = os.path.join(HERE, "trial-rev18.md")
VARIANTS = ("primary", "strict")
CAPS = {"in-repo": 4, "wide": 6}

# Hand judgement per defect design (ShiftLead's described generically; the detail is in its ledger) (keyed by plan prefix): can a cap item that shows the open
# findings plausibly have surfaced the defect?  Based only on the defect descriptions in the json;
# the open findings themselves are not in the data, so every confidence is low-to-moderate.
JUDGE = {
    "TD-947": ("low-moderate", "a stray event the design did not enumerate. Detail: ShiftLead's ledger."),
    "TD-931": ("n/a", "a stale doc sentence after the build; not a design-review matter. Detail: ShiftLead's ledger."),
    "TD-909": ("low", "a later model change driven by use; not catchable by open findings. Detail: ShiftLead's ledger."),
    "TD-1051": ("low-moderate", "an unenumerated peer state. Detail: ShiftLead's ledger."),
    "TD-995": ("moderate", "an internal contradiction, the kind consistency reviews raise; an open finding at the cap could plausibly show it. Detail: ShiftLead's ledger."),
    "TD-804": ("low-moderate", "an ordering case. Detail: ShiftLead's ledger."),
    "TD-820": ("low", "case enumeration in a 1-round design; the rules end it at round 1 with no item. Detail: ShiftLead's ledger."),
    "2026-10-22-ledger-ids": ("low", "later redesign driven by use (Taken by overloaded); not catchable by open findings."),
}


def load():
    with open(DATA) as f:
        data = json.load(f)
    kept, skipped = [], Counter()
    for d in data:
        if d.get("mode") == "parallel":
            skipped["parallel"] += 1
        elif not d.get("reviews_detail"):
            skipped["no per-review detail"] += 1
        else:
            kept.append(d)
    return kept, skipped


def is_ready(v):
    return v is not None and v.strip().lower() in ("ready", "no findings")


def raises(r, variant):
    bc = r.get("build_changing")
    if bc is not None:
        return bc >= 1
    v, tf = r.get("verdict"), r.get("total_findings")
    ready = is_ready(v)
    primary = (v is not None and not ready) or (tf is not None and tf >= 3)
    if variant == "primary":
        return primary
    if primary:
        return True
    if ready:
        return False
    return tf is None or tf >= 1 or False


def is_unknown(r):
    return r.get("build_changing") is None and r.get("verdict") is None and r.get("total_findings") is None


def size_of(d):
    models = d.get("models") or []
    det = {r["model"] for r in d["reviews_detail"]}
    return max(len(models), len(det), 1)


def simulate(d, cap, variant):
    rv = d["reviews_detail"]
    size = size_of(d)
    n = len(rv)
    chunks = [rv[i : i + size] for i in range(0, n, size)]
    for i, ch in enumerate(chunks, 1):
        raised = any(raises(r, variant) for r in ch)
        if not raised:
            return dict(end="stop", round=i, sim=min(n, i * size), n=n, size=size)
        if i == cap:
            return dict(end="cap", round=i, sim=min(n, i * size), n=n, size=size)
    # history ended (person/override) on a round that still raised, below the cap
    return dict(end="open", round=len(chunks), sim=n, n=n, size=size)


def real_defects(d):
    return [x for x in d.get("post_build_defects") or [] if not x["what"].startswith("(questionable)")]


def judge_key(d):
    for k in JUDGE:
        if k in d["plan"]:
            return k
    return None


def pct(a, b):
    return "%d/%d (%d%%)" % (a, b, round(100 * a / b)) if b else "0/0"


def med(xs):
    return statistics.median(xs) if xs else float("nan")


def aggregate(designs, caps, variant):
    out = {}
    for cls in ("in-repo", "wide"):
        ds = [d for d in designs if d["class"] == cls]
        res = [(d, simulate(d, caps[cls], variant)) for d in ds]
        saved = [r["n"] - r["sim"] for _, r in res]
        out[cls] = dict(
            n=len(ds),
            res=res,
            saved=saved,
            stop=sum(r["end"] == "stop" for _, r in res),
            cap=sum(r["end"] == "cap" for _, r in res),
            open=sum(r["end"] == "open" for _, r in res),
            actual=sum(r["n"] for _, r in res),
        )
    return out


def main():
    designs, skipped = load()
    L = []
    w = L.append
    w("# Trial of the rounds rules (plan revision 18) against design-rounds.json\n")
    w(
        "Generated by `trial_rules.py` (stdlib, rerunnable). Rules: round = one pass through the design's own model list; stop after a round with no build-changing finding (cap round included); cap 4 in-repo / 6 wide; a cap that still raised ends the rounds and a board item goes to the person. Recurring topics are **not simulated**: topics are not recorded in the data and are not guessed, so the item rate below is the **at-cap rate only** (a lower bound on the real rate once the layer rule and recurring topics exist).\n"
    )
    w(
        "Skipped: %s. Designs simulated: %d (in-repo %d, wide %d)."
        % (", ".join("%d %s" % (v, k) for k, v in skipped.items()), len(designs), sum(d["class"] == "in-repo" for d in designs), sum(d["class"] == "wide" for d in designs))
    )
    w("")
    w("## The proxy, and its weakness (read this first)\n")
    w('Only the ledger-writer design has real `build_changing` counts (used as is: >= 1 raises, under both variants). Everywhere else a review "raises a build-changing finding" by proxy:\n')
    w(
        "- **Primary:** verdict is not READY (NOT READY, REVISE, ...), or total_findings >= 3. READY with <= 2 findings raises none. A review with no verdict, only a count, raises when the count is >= 3. A review with neither verdict nor count (%d of %d reviews) raises nothing."
        % (sum(is_unknown(r) for d in designs for r in d["reviews_detail"]), sum(len(d["reviews_detail"]) for d in designs))
    )
    w("- **Strict:** primary, plus any not-READY review with >= 1 finding; a review with neither verdict nor count raises (upper bound).\n")
    w(
        "Weaknesses: total findings are not build-changing findings. Late reviews in these loops are mostly minor follow-ons (wording, a missed consistency edit, a miscount) that the proxy counts, and a not-READY verdict is given for any open finding however small. Both push the proxy toward **raising too often**: it overstates how long a loop runs, understates stops, and overstates cap items. Under the primary proxy the verdict rule dominates (the 3-finding rule only adds verdictless counts); where a review has a verdict null and a count of 1-2 the primary proxy lets it stop, which is the other, smaller, error direction. The ledger-writer design shows the gap: its reviews 7-10 carry 1-1.5 build-changing findings out of far more total findings, and review 11 reports none. Treat the cap-item rates as an upper-leaning estimate and the saved-review counts as a lower-leaning estimate.\n"
    )

    # per design table
    w("## Per design (cap 4 in-repo / 6 wide)\n")
    w(
        "`size` = models per round. `rounds` = reviews/size. `end` = how the rules end it: stop, cap, or open (history ended on a raising round before the cap, by override or fatigue: no rule fires, no item). `saved` = actual reviews minus simulated reviews. `asked` = cap item raised (no layer rule, no recurring topics).\n"
    )
    w("| class | plan | reviews | size | rounds | P end | P round | P saved | P asked | S end | S round | S saved | S asked |")
    w("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for d in sorted(designs, key=lambda d: (d["class"], d["date"], d["plan"])):
        p = simulate(d, CAPS[d["class"]], "primary")
        s = simulate(d, CAPS[d["class"]], "strict")
        w(
            "| %s | %s | %d | %d | %s | %s | %d | %d | %s | %s | %d | %d | %s |"
            % (
                d["class"],
                d["plan"][:48].replace("|", "/"),
                p["n"],
                p["size"],
                "%g" % (p["n"] / p["size"]),
                p["end"],
                p["round"],
                p["n"] - p["sim"],
                "yes" if p["end"] == "cap" else "no",
                s["end"],
                s["round"],
                s["n"] - s["sim"],
                "yes" if s["end"] == "cap" else "no",
            )
        )
    w("")

    # aggregates
    base = {v: aggregate(designs, CAPS, v) for v in VARIANTS}
    w("## Aggregate at the defaults (in-repo 4, wide 6)\n")
    w(
        "| class | proxy | designs | ends by stop rule | ends at cap (person asked) | open (history ended first, no rule fired) | reviews actual | reviews saved | saved per design (mean) | saved median | designs with 0 saved |"
    )
    w("|---|---|---|---|---|---|---|---|---|---|---|")
    for cls in ("in-repo", "wide"):
        for v in VARIANTS:
            a = base[v][cls]
            w(
                "| %s | %s | %d | %s | %s | %s | %d | %d (%d%%) | %.2f | %g | %d |"
                % (
                    cls,
                    v,
                    a["n"],
                    pct(a["stop"], a["n"]),
                    pct(a["cap"], a["n"]),
                    pct(a["open"], a["n"]),
                    a["actual"],
                    sum(a["saved"]),
                    round(100 * sum(a["saved"]) / a["actual"]),
                    sum(a["saved"]) / a["n"],
                    med(a["saved"]),
                    sum(x == 0 for x in a["saved"]),
                )
            )
    w("")
    w('The stop rule can also coincide with the actual end (saved 0): such a design ended by stop rule with nothing saved. The share "person asked" is the share ending at the cap.\n')

    # defects
    w("## Designs with a post-build defect (questionable-only defects excluded)\n")
    w(
        "Excluded as questionable-only: TD-1129, TD-1189, TD-734, TD-693, TD-307 (rework). Out of scope for no per-review detail: pinned-not-synced (4 defects, wide) and ledger-per-entry (no review count), which are the two best wide defect cases and cannot be tested. TD-931 is a stale-doc-sentence defect, kept for completeness.\n"
    )
    w("| class | design | reviews | defect(s) | P: sim end before actual end? | P: asked? | S: before actual end? | S: asked? | could a cap item have surfaced it? |")
    w("|---|---|---|---|---|---|---|---|---|")
    dd = [d for d in designs if real_defects(d)]
    tally = {v: Counter() for v in VARIANTS}
    for d in sorted(dd, key=lambda d: (d["class"], d["plan"])):
        cells = []
        for v in VARIANTS:
            r = simulate(d, CAPS[d["class"]], v)
            early = r["sim"] < r["n"]
            asked = r["end"] == "cap"
            cells += ["yes (%d of %d)" % (r["sim"], r["n"]) if early else "no", "yes" if asked else "no"]
            tally[v][(d["class"], asked)] += 1
        k = judge_key(d)
        conf = "%s: %s" % JUDGE[k] if k else "no judgement"
        w(
            "| %s | %s | %d | %s | %s | %s | %s | %s | %s |"
            % (d["class"], d["plan"][:40].replace("|", "/"), len(d["reviews_detail"]), "; ".join(x["where"].split(" (")[0] for x in real_defects(d))[:60], *cells, conf)
        )
    w("")
    for cls in ("in-repo", "wide"):
        for v in VARIANTS:
            a = tally[v][(cls, True)]
            b = tally[v][(cls, False)]
            if a + b:
                w("- %s, %s proxy: %d defect designs, asked %d, not asked %d." % (cls, v, a + b, a, b))
    w("")
    w(
        'Confidence is low throughout. The data holds the defect descriptions but not the open findings at the cap, so "a cap item showing the open findings could have surfaced it" is a judgement from the description alone. A design that the rules end early by stop rule is, by construction, one whose last simulated round raised nothing under the proxy: the rules would not have asked, and the later reviews that the history actually ran either found minor things or the defect later seen. Defects that were later redesigns driven by use (TD-909, ledger-ids, TD-931) were never catchable by any review rule.\n'
    )

    # sensitivity
    w("## Sensitivity to the cap\n")
    for cls, caps in (("in-repo", (3, 4, 5, 6)), ("wide", (5, 6, 7))):
        w("### %s (cap varied; item rate = share ending at cap)\n" % cls)
        w("| cap | proxy | designs | item rate (asked) | stop | open | reviews saved | of actual | saved median per design |")
        w("|---|---|---|---|---|---|---|---|---|")
        for cap in caps:
            for v in VARIANTS:
                a = aggregate(designs, {"in-repo": cap, "wide": cap}, v)[cls]
                w(
                    "| %d | %s | %d | %s | %d | %d | %d | %d (%d%%) | %g |"
                    % (cap, v, a["n"], pct(a["cap"], a["n"]), a["stop"], a["open"], sum(a["saved"]), a["actual"], round(100 * sum(a["saved"]) / a["actual"]), med(a["saved"]))
                )
        w("")
    w("Defect designs under each in-repo cap (primary proxy; asked count among the %d in-repo defect designs):\n" % sum(d["class"] == "in-repo" for d in dd))
    w("| in-repo cap | primary asked | strict asked |")
    w("|---|---|---|")
    for cap in (3, 4, 5, 6):
        c = []
        for v in VARIANTS:
            c.append(sum(simulate(d, cap, v)["end"] == "cap" for d in dd if d["class"] == "in-repo"))
        w("| %d | %d | %d |" % (cap, c[0], c[1]))
    w("")
    w("(Wide defect designs with detail: only ledger-ids; see the defect table.)\n")
    with open(OUT, "w") as f:
        f.write("\n".join(L) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
