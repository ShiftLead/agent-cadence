#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/review_stats.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""Design-review outcomes, rebuilt on demand (TD-204, ADR 2026-10-30-review-outcomes rule 4).

    review_stats.py [--repo PATH] [--aged DAYS] [--json]
                    rebuild the dataset from every roster repo's review records and ledgers, and
                    write it with its aggregates and the rounds trial to review-stats/ beside the roster
    review_stats.py --candidates [--since DATE] [--repo PATH] [--json]
                    the backfill's mechanical half: entries that cite a design and carry no
                    Escaped from:, and Escaped from: values naming a design with no record file

WHY
A design review's worth shows only later, in the defects it let through. The data for that
accumulates as a by-product (each design's record file, cadence.md §4.8; `**Escaped from:**` on a
defect, §2.13), and this turns it into numbers when someone asks — so a repo's round caps can be
tuned from evidence rather than guessed.

MECHANICAL, NO STATE
Every run rebuilds everything from the repos' files as they are on disk (working trees), with no
model, no agent and no judgement: an `Escaped from:` added since the last run is counted the next
time anyone runs it. Nothing is written into a repo. It is run by hand, never by a hook or a sweep.

WHAT IT READS
The roster (nudge_user_attention.read_registry(), §9.2; `$AGENT_CADENCE_REG_DIR` honoured), or the
one repo `--repo` names. In each repo: `docs/reviews/TD-*.md` (the header's Design, Class, Decided
and Source; the Reviews table; the findings table), its `design-rounds` and `design-rounds-wide`
(cadence_config.py), and the `**Escaped from:**` field of its live and archived ledger entries
(ledgerboard.entries() over both texts), its first word split and stripped as first_word() does
but not lower-cased. A value is `TD-NNN` (this repo) or `<repo>#TD-NNN` (ledger.py's Roster: a
roster basename, or owner/name; the basename compared case-insensitively and TD read upper-cased).
It is **resolved** (the design's record file exists), **out of scope** (its repo is off the roster,
the Roster cannot resolve it, or it is outside --repo) or **unresolved** (in scope, no record, or a
value neither form matches). Only resolved escapes count.

WHAT IT WRITES
`review-stats/` beside the roster (machine_dir()): `design-rounds.json` (one row per design, in the
shape of agent-cadence's published `docs/review-data/design-rounds.json`, plus the record's own
fields), `design-rounds.md` (the aggregates and the per-design table) and `trial.md` (the rounds
rules rerun over the rows against each repo's caps). The aggregates and the trial are ported from
that dataset's frozen `aggregate.py` and `trial_rules.py`, which reproduce over the same json;
`tests/test_review_stats.sh` holds the two to each other. Per class: the escape rate is aged
`rounds` designs with a resolved escape over aged `rounds` designs (`--aged`, default 14 days
since `Decided:`; a `pending` or younger design is listed apart, and a `backfill` record — written
only for a design with an escape — is listed, never rated); build-changing per round is the count
of findings so labelled in that round, reviews' and fact-checks' apart.

PROXY
A review "raises" a build-changing finding by its labelled rows; a review with `unlabelled` rows
(a backfill record's counted-only findings, or a malformed row in a rounds record) and none
labelled build-changing reads by the trial's total-findings proxy instead.

Exit: 0, or 2 on a usage error (no roster, a --repo that is not a directory).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cadence_config as C  # noqa: E402  # sibling SYNC script: the one settings reader (§9.18)
import ledger as L  # noqa: E402  # sibling SYNC script: the ledger reader and the Roster
import ledgerboard as LB  # noqa: E402  # sibling SYNC file: the ledger format
import nudge_user_attention as N  # noqa: E402  # sibling SYNC script: the roster and machine_dir (§9)

REVIEWS_DIR = "docs/reviews"
OUT_DIR = "review-stats"
RECORD_RE = re.compile(r"^TD-(\d+)\.md$")
HEADER_RE = re.compile(r"^\*\*(Design|Class|Decided|Source):\*\*[ \t]*(.*?)[ \t]*$", re.M)
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
BARE_RE = re.compile(r"^TD-(\d+)$", re.I)
XREPO_RE = re.compile(r"^([\w.-]+(?:/[\w.-]+)?)#TD-(\d+)$", re.I)
CITE_RE = re.compile(r"(?<![\w#/.-])(?:([\w.-]+(?:/[\w.-]+)?)#)?TD-(\d+)\b")
LABEL_RE = re.compile(r"^\*\*([A-Za-z][^*:\n]*?)(?::\*\*|\*\*)", re.M)  # **Why:** or **Done when**
CLASSES = ("in-repo", "wide")
FINDING_CLASSES = ("build-changing", "minor", "unlabelled")
VARIANTS = ("primary", "strict")
MAX_ROUND = 99  # a round cell past this is a typo (a date), not a round


# ---------------------------------------------------------------- reading


def table_rows(text: str, first: str) -> list[list[str]]:
    """The data rows of the Markdown table whose header's first cell is ``first``."""
    rows: list[list[str]] = []
    lines = LB.COMMENT_RE.sub("", text).split("\n")
    for i, line in enumerate(lines):
        cells = _cells(line)
        if cells and cells[0].lower() == first and i + 1 < len(lines) and set(lines[i + 1].replace("|", "").strip()) <= set("-: "):
            for nxt in lines[i + 2:]:
                c = _cells(nxt)
                if c is None:
                    break
                rows.append(c)
            break
    return rows


def _cells(line: str) -> list[str] | None:
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")) or len(s) < 2:
        return None
    return [c.strip() for c in s[1:-1].split("|")]


def read_record(path: Path, repo: str, td: int) -> tuple[dict | None, list[str]]:
    """(the record, its problems) of one ``docs/reviews/TD-NNN.md``; the record is None when it cannot be read at all."""
    probs: list[str] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return None, [f"{path}: {e}"]
    head = {m.group(1).lower(): m.group(2) for m in HEADER_RE.finditer(LB.COMMENT_RE.sub("", text))}
    cls = LB.first_word(head.get("class"))
    if cls not in CLASSES:
        return None, [f"{path}: Class {head.get('class')!r} is neither in-repo nor wide"]
    source = LB.first_word(head.get("source")) or "rounds"
    if source not in ("rounds", "backfill"):
        probs.append(f"{path}: Source {head.get('source')!r} read as rounds")
        source = "rounds"
    dm = DATE_RE.match(head.get("decided") or "")
    decided = dm.group(0) if dm else "pending"
    if dm:
        try:
            dt.date.fromisoformat(decided)
        except ValueError:
            probs.append(f"{path}: Decided {decided!r} is no date (read as pending)")
            decided = "pending"
    reviews: dict[str, dict] = {}
    for c in table_rows(text, "review"):
        if len(c) < 6 or not re.fullmatch(r"R\d+", c[0]) or not c[1].isdigit() or not 1 <= int(c[1]) <= MAX_ROUND:
            probs.append(f"{path}: Reviews row {' | '.join(c)!r} not read")
            continue
        if c[0] in reviews:
            probs.append(f"{path}: {c[0]} is in the Reviews table twice (the first row read)")
            continue
        role = c[2].lower()
        if role not in ("design", "fact-check"):
            probs.append(f"{path}: {c[0]} role {c[2]!r} read as design")
            role = "design"
        tok = int(c[4].replace(",", "")) if c[4].replace(",", "").isdigit() else None
        reviews[c[0]] = {"review": c[0], "round": int(c[1]), "role": role, "model": c[3] or "?", "tokens": tok,
                         "date": c[5], "build_changing": 0, "minor": 0, "unlabelled": 0}
    for c in table_rows(text, "id"):
        if len(c) < 7:
            probs.append(f"{path}: findings row {' | '.join(c)!r} not read")
            continue
        r = reviews.get(c[2])
        if r is None:
            probs.append(f"{path}: {c[0]} names review {c[2]!r}, which the Reviews table has not")
            continue
        k = c[5].lower()
        if k == "unlabelled" and source != "backfill":
            probs.append(f"{path}: {c[0]} is unlabelled in a rounds record (read as the proxy)")
        elif k not in FINDING_CLASSES:
            probs.append(f"{path}: {c[0]} class {c[5]!r} unknown (read as unlabelled)")
            k = "unlabelled"
        r[k.replace("-", "_")] += 1
    order = sorted(reviews.values(), key=lambda r: int(r["review"][1:]))
    return {"repo": repo, "td": td, "design": head.get("design") or "", "class": cls, "decided": decided,
            "source": source, "reviews": order}, probs


def ledger_entries(root: Path) -> list[dict]:
    """Every live and archived entry of ``root``'s ledger, read from its working tree, each with ``archived``."""
    io = L.fs_io()
    rio = (lambda p: io[0](str(root / p))), (lambda p: io[1](str(root / p)))
    rel = L.ledger_at(root, rio)
    led, arch = L.read_pair(rel, L.ARCHIVE_REL if rel == L.LEDGER_REL else None, rio)
    out = []
    for text, archived in ((led or "", False), (arch or "", True)):
        for e in LB.entries(text):
            e["archived"] = archived
            out.append(e)
    return out


def entry_bodies(root: Path) -> dict[str, str]:
    """Each entry's whole body text by id, live and archived, for the citation search."""
    io = L.fs_io()
    rio = (lambda p: io[0](str(root / p))), (lambda p: io[1](str(root / p)))
    rel = L.ledger_at(root, rio)
    led, arch = L.read_pair(rel, L.ARCHIVE_REL if rel == L.LEDGER_REL else None, rio)
    out: dict[str, str] = {}
    for text in (led or "", arch or ""):
        text = LB.COMMENT_RE.sub("", text)
        for m in LB.HEADING_RE.finditer(text):
            nxt = LB.SECTION_RE.search(text, m.end())
            out.setdefault(m.group(1), text[m.end(): nxt.start() if nxt else len(text)])
    return out


def raw_word(value: str | None) -> str:
    """A field's first word, split and stripped as ledgerboard's first_word() does, case kept."""
    m = LB.WORD_RE.search(value or "")
    return m.group(0).strip("*_`").rstrip(".:") if m else ""


class Scope:
    """The repos read, their records, and how a design reference resolves."""

    def __init__(self, roots: list[Path], only: Path | None):
        self.roots = roots
        self.only = only
        self.roster = L.Roster()
        self.records: dict[tuple[str, int], Path] = {}
        for root in roots:
            d = root / REVIEWS_DIR
            for p in sorted(d.iterdir()) if d.is_dir() else []:
                m = RECORD_RE.match(p.name)
                if m and p.is_file():
                    self.records[(str(root), int(m.group(1)))] = p

    def resolve(self, here: Path, value: str) -> tuple[str, Path | None, int | None, str]:
        """(state, design repo root, design TD number, why) of one design reference written in ``here``'s ledger."""
        m = BARE_RE.match(value)
        if m:
            root, n = here, int(m.group(1))
        else:
            x = XREPO_RE.match(value)
            if not x:
                return "unresolved", None, None, f"cannot read {value!r} — write TD-NNN or <repo>#TD-NNN"
            norm = f"{x.group(1)}#TD-{x.group(2)}"
            if not LB.XREPO_ITEM_RE.match(norm):
                return "unresolved", None, None, f"cannot read {value!r}"
            mine = [r for r in self.roots if r.name.lower() == x.group(1).lower()] if "/" not in x.group(1) else []
            found, why = (mine[0], "") if len(mine) == 1 else self.roster._find(x.group(1))
            if found is None:
                return "out of scope", None, int(x.group(2)), why
            root, n = found.resolve(), int(x.group(2))
        if str(root) not in {str(r) for r in self.roots}:
            return "out of scope", root, n, f"{root} is outside --repo {self.only}" if self.only else f"{root} is not read"
        if (str(root), n) in self.records:
            return "resolved", root, n, ""
        return "unresolved", root, n, f"no {REVIEWS_DIR}/TD-{n:03d}.md in {root}"


# ---------------------------------------------------------------- the rows


def build_rows(scope: Scope, aged_days: int, today: dt.date) -> tuple[list[dict], list[dict], list[str]]:
    """(one dataset row per readable record, every Escaped from: value with its state, problems)."""
    probs: list[str] = []
    rows: dict[tuple[str, int], dict] = {}
    for (root, n), path in sorted(scope.records.items()):
        rec, p = read_record(path, Path(root).name, n)
        probs += p
        if rec is None:
            continue
        rows[(root, n)] = to_row(rec, root, aged_days, today)
    escapes: list[dict] = []
    for root in scope.roots:
        for e in ledger_entries(root):
            raw = e["fields"].get("escaped from")
            if raw is None:
                continue
            value = raw_word(raw)
            state, droot, dn, why = scope.resolve(root, value)
            if state == "resolved" and (str(droot), dn) not in rows:
                state, why = "unresolved", f"its record {scope.records[(str(droot), dn)]} could not be read (see Not read as written)"
            esc = {"repo": root.name, "id": e["id"], "title": e["title"], "archived": e["archived"], "value": value,
                   "state": state, "why": why, "design": f"{Path(droot).name}#TD-{dn:03d}" if droot and dn is not None else None}
            escapes.append(esc)
            if state == "resolved" and (str(droot), dn) in rows:
                rows[(str(droot), dn)]["post_build_defects"].append({"where": f"{root.name}#{e['id']}", "what": e["title"]})
    return list(rows.values()), escapes, probs


def to_row(rec: dict, root: str, aged_days: int, today: dt.date) -> dict:
    design = [r for r in rec["reviews"] if r["role"] == "design"]
    facts = [r for r in rec["reviews"] if r["role"] == "fact-check"]
    models: list[str] = []
    for r in design:
        if r["model"] not in models:
            models.append(r["model"])
    detail = []
    for i, r in enumerate(design, 1):
        total = r["build_changing"] + r["minor"] + r["unlabelled"]
        bc = r["build_changing"] if (r["build_changing"] or not r["unlabelled"]) else None
        detail.append({"n": i, "review": r["review"], "round": r["round"], "model": r["model"], "verdict": None,
                       "build_changing": bc, "minor": r["minor"], "total_findings": total, "tokens": r["tokens"]})
    nrounds = max((r["round"] for r in rec["reviews"]), default=0)
    per = {"reviews": [0] * nrounds, "fact_checks": [0] * nrounds}
    for r in rec["reviews"]:
        per["reviews" if r["role"] == "design" else "fact_checks"][r["round"] - 1] += r["build_changing"]
    tokens: dict[str, int] = {}
    unknown = 0
    for r in rec["reviews"]:
        if r["tokens"] is None:
            unknown += 1
        else:
            tokens[r["model"]] = tokens.get(r["model"], 0) + r["tokens"]
    age = None if rec["decided"] == "pending" else (today - dt.date.fromisoformat(rec["decided"])).days
    caps = repo_caps(root)
    return {
        "repo": rec["repo"], "td": f"TD-{rec['td']:03d}", "plan": f"TD-{rec['td']:03d} {rec['design']}".strip(),
        "date": rec["decided"], "decided": rec["decided"], "class": rec["class"], "source": rec["source"],
        "mode": "rounds", "source_kind": "record", "batch": "review-stats", "stop": None,
        "models": models, "reviews": len(design), "rounds": len({r["round"] for r in design}),
        "fact_checks": len(facts), "reviews_detail": detail,
        "fact_checks_detail": [{"review": r["review"], "round": r["round"], "model": r["model"], "tokens": r["tokens"],
                                "build_changing": r["build_changing"], "minor": r["minor"]} for r in facts],
        "tokens_by_model": tokens, "tokens_unknown": unknown, "build_changing_per_round": per,
        "age_days": age, "aged": age is not None and age > aged_days, "caps": caps, "post_build_defects": [],
    }


_CAPS: dict[str, dict] = {}


def repo_caps(root: str) -> dict:
    """{in-repo: design-rounds, wide: design-rounds-wide} as cadence_config resolves them for ``root``."""
    if root not in _CAPS:
        files = C.sources(root)
        caps = {}
        for cls, key in (("in-repo", "design-rounds"), ("wide", "design-rounds-wide")):
            try:
                caps[cls] = int(C.resolve(key, files)[0])
            except (C.ConfigError, TypeError, ValueError):   # a bad value: that key's default, the other kept
                caps[cls] = int(C.KEYS[key][0])
        _CAPS[root] = caps
    return _CAPS[root]


# ---------------------------------------------------------------- the port: aggregate.py


def med(xs):
    return statistics.median(xs) if xs else None


def fmt(x):
    if x is None:
        return "n/a"
    return ("%g" % x) if isinstance(x, float) else str(x)


def in_aggregates(D):
    return [r for r in D if r.get("mode", "rounds") == "rounds" and r.get("reviews") and r.get("rounds")]


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


def block(recs):
    rv = [r["reviews"] for r in recs]
    rd = [r["rounds"] for r in recs]
    cnt = Counter(rd)
    dist = ", ".join("%s x%d" % (fmt(k), v) if v > 1 else fmt(k) for k, v in sorted(cnt.items()))
    within = {lim: (sum(1 for x in rd if x <= lim), len(rd)) for lim in (3, 4, 6)}
    return dict(n=len(recs), rv=(med(rv), max(rv) if rv else None, min(rv) if rv else None),
                rd=(med(rd), max(rd) if rd else None, min(rd) if rd else None), dist=dist, within=within)


def l3(recs):
    vals = [(r, last3(r)) for r in recs]
    vals = [(r, v) for r, v in vals if v is not None]
    idx = [v for r, v in vals]
    rds = [v / len(r["models"]) for r, v in vals]
    return dict(n=len(vals), med_idx=med(idx), min=min(idx) if idx else None, max=max(idx) if idx else None, med_rounds=med(rds))


def aggregate_lines(D) -> list[str]:
    """The aggregate.py lines this port reproduces, formatted as it formats them."""
    recs = in_aggregates(D)
    B = {c: block([r for r in recs if r["class"] == c]) for c in CLASSES}
    Lx = {c: l3([r for r in recs if r["class"] == c]) for c in CLASSES}
    out: list[str] = []
    w = out.append
    w("| | designs | reviews: median / max / min | rounds: median / max / min |")
    w("|---|---|---|---|")
    for c in CLASSES:
        w("| %s | %d | %s / %s / %s | %s / %s / %s |" % (c, B[c]["n"], *map(fmt, B[c]["rv"]), *map(fmt, B[c]["rd"])))
    w("")
    w("- **Distribution of in-repo rounds** (%d): %s." % (B["in-repo"]["n"], B["in-repo"]["dist"]))
    w("- **Distribution of wide rounds** (%d): %s." % (B["wide"]["n"], B["wide"]["dist"]))
    bi = B["in-repo"]["within"]
    if bi[3][1]:
        w("- **In-repo rounds within 3 / 4 / 6:** " + ", ".join("%d of %d (%.0f%%) within %d" % (bi[k][0], bi[k][1], 100.0 * bi[k][0] / bi[k][1], k) for k in (3, 4, 6)) + ".")
    bw = B["wide"]["within"]
    w("- **Wide rounds within 3 / 4 / 6:** " + ", ".join("%d of %d within %d" % (bw[k][0], bw[k][1], k) for k in (3, 4, 6)) + ".")
    a, b = Lx["in-repo"], Lx["wide"]
    w("- **Median last review with 3+ findings** (designs with finding counts for at least half their reviews): in-repo %d designs, median review index %s (= round %s), range %s-%s; wide %d designs, median index %s (= round %s)."
      % (a["n"], fmt(a["med_idx"]), fmt(a["med_rounds"]), fmt(a["min"]), fmt(a["max"]), b["n"], fmt(b["med_idx"]), fmt(b["med_rounds"])))
    return out


# ---------------------------------------------------------------- the port: trial_rules.py


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
    return tf is None or tf >= 1


def size_of(d):
    models = d.get("models") or []
    det = {r["model"] for r in d["reviews_detail"]}
    return max(len(models), len(det), 1)


def simulate(d, cap, variant):
    rv = d["reviews_detail"]
    size = size_of(d)
    n = len(rv)
    chunks = [rv[i: i + size] for i in range(0, n, size)]
    for i, ch in enumerate(chunks, 1):
        if not any(raises(r, variant) for r in ch):
            return dict(end="stop", round=i, sim=min(n, i * size), n=n, size=size)
        if i == cap:
            return dict(end="cap", round=i, sim=min(n, i * size), n=n, size=size)
    return dict(end="open", round=len(chunks), sim=n, n=n, size=size)


def cap_of(d, cap=None):
    """The design's cap: ``cap`` when the caller varies it, else its repo's for its class."""
    return cap if cap is not None else (d.get("caps") or {"in-repo": 4, "wide": 6})[d["class"]]


def pct(a, b):
    return "%d/%d (%d%%)" % (a, b, round(100 * a / b)) if b else "0/0"


def tmed(xs):
    return statistics.median(xs) if xs else float("nan")


def trial_aggregate(designs, variant, cap=None):
    out = {}
    for cls in CLASSES:
        ds = [d for d in designs if d["class"] == cls]
        res = [(d, simulate(d, cap_of(d, cap), variant)) for d in ds]
        saved = [r["n"] - r["sim"] for _, r in res]
        out[cls] = dict(n=len(ds), saved=saved, stop=sum(r["end"] == "stop" for _, r in res),
                        cap=sum(r["end"] == "cap" for _, r in res), open=sum(r["end"] == "open" for _, r in res),
                        actual=sum(r["n"] for _, r in res))
    return out


def trial_lines(D) -> list[str]:
    """The trial: trial_rules.py's per-design, aggregate and sensitivity tables, each design at its repo's caps."""
    designs = [d for d in D if d.get("mode") != "parallel" and d.get("reviews_detail")]
    out: list[str] = []
    w = out.append
    w("## Per design (each repo's caps)\n")
    w("| class | plan | reviews | size | rounds | P end | P round | P saved | P asked | S end | S round | S saved | S asked |")
    w("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for d in sorted(designs, key=lambda d: (d["class"], d["date"], d["plan"])):
        p = simulate(d, cap_of(d), "primary")
        s = simulate(d, cap_of(d), "strict")
        w("| %s | %s | %d | %d | %s | %s | %d | %d | %s | %s | %d | %d | %s |"
          % (d["class"], d["plan"][:48].replace("|", "/"), p["n"], p["size"], "%g" % (p["n"] / p["size"]),
             p["end"], p["round"], p["n"] - p["sim"], "yes" if p["end"] == "cap" else "no",
             s["end"], s["round"], s["n"] - s["sim"], "yes" if s["end"] == "cap" else "no"))
    w("")
    w("## Aggregate at each repo's caps\n")
    w("| class | proxy | designs | ends by stop rule | ends at cap (person asked) | open (history ended first, no rule fired) | reviews actual | reviews saved | saved per design (mean) | saved median | designs with 0 saved |")
    w("|---|---|---|---|---|---|---|---|---|---|---|")
    base = {v: trial_aggregate(designs, v) for v in VARIANTS}
    for cls in CLASSES:
        for v in VARIANTS:
            a = base[v][cls]
            if not a["n"]:
                continue
            w("| %s | %s | %d | %s | %s | %s | %d | %d (%d%%) | %.2f | %g | %d |"
              % (cls, v, a["n"], pct(a["stop"], a["n"]), pct(a["cap"], a["n"]), pct(a["open"], a["n"]), a["actual"],
                 sum(a["saved"]), round(100 * sum(a["saved"]) / a["actual"]) if a["actual"] else 0,
                 sum(a["saved"]) / a["n"], tmed(a["saved"]), sum(x == 0 for x in a["saved"])))
    w("")
    w("## Sensitivity to the cap\n")
    for cls, caps in (("in-repo", (3, 4, 5, 6)), ("wide", (5, 6, 7))):
        w("### %s (cap varied; item rate = share ending at cap)\n" % cls)
        w("| cap | proxy | designs | item rate (asked) | stop | open | reviews saved | of actual | saved median per design |")
        w("|---|---|---|---|---|---|---|---|---|")
        for cap in caps:
            for v in VARIANTS:
                a = trial_aggregate(designs, v, cap)[cls]
                if not a["actual"]:
                    continue
                w("| %d | %s | %d | %s | %d | %d | %d | %d (%d%%) | %g |"
                  % (cap, v, a["n"], pct(a["cap"], a["n"]), a["stop"], a["open"], sum(a["saved"]), a["actual"],
                     round(100 * sum(a["saved"]) / a["actual"]), tmed(a["saved"])))
        w("")
    return out


# ---------------------------------------------------------------- the outcomes


def outcome_lines(D, escapes: list[dict], aged_days: int) -> list[str]:
    """Escape rates per class, build-changing per round, tokens by model, and the escapes not counted."""
    out: list[str] = []
    w = out.append
    w("## Escapes (rounds designs Decided more than %d days ago)\n" % aged_days)
    w("| class | aged rounds designs | with a resolved escape | escape rate | young or pending (not rated) | backfill (listed, not rated) |")
    w("|---|---|---|---|---|---|")
    for c in CLASSES:
        rs = [r for r in D if r["class"] == c and r["source"] == "rounds"]
        aged = [r for r in rs if r["aged"]]
        hit = [r for r in aged if r["post_build_defects"]]
        bf = [r for r in D if r["class"] == c and r["source"] == "backfill"]
        w("| %s | %d | %d | %s | %d | %d |" % (c, len(aged), len(hit), pct(len(hit), len(aged)), len(rs) - len(aged), len(bf)))
    w("")
    w("## Build-changing findings per round (reviews / fact-checks)\n")
    for c in CLASSES:
        n = max((len(r["build_changing_per_round"]["reviews"]) for r in D if r["class"] == c), default=0)
        rv = [sum(r["build_changing_per_round"]["reviews"][i] for r in D if r["class"] == c and i < len(r["build_changing_per_round"]["reviews"])) for i in range(n)]
        fc = [sum(r["build_changing_per_round"]["fact_checks"][i] for r in D if r["class"] == c and i < len(r["build_changing_per_round"]["fact_checks"])) for i in range(n)]
        w("- **%s:** %s." % (c, ", ".join("round %d: %d / %d" % (i + 1, rv[i], fc[i]) for i in range(n)) or "no rounds"))
    w("")
    w("## Rounds and tokens\n")
    w("| class | designs | rounds: median / total | tokens: median per design / total | reviews with tokens unknown |")
    w("|---|---|---|---|---|")
    for c in CLASSES:
        rs = [r for r in D if r["class"] == c]
        rd = [r["rounds"] for r in rs]
        tk = [sum(r["tokens_by_model"].values()) for r in rs]
        w("| %s | %d | %s / %d | %s / %d | %d |" % (c, len(rs), fmt(med(rd)), sum(rd), fmt(med(tk)), sum(tk), sum(r["tokens_unknown"] for r in rs)))
    w("")
    by_model: dict[str, int] = {}
    for r in D:
        for m, t in r["tokens_by_model"].items():
            by_model[m] = by_model.get(m, 0) + t
    w("**Tokens by model:** " + (", ".join("%s %d" % (m, t) for m, t in sorted(by_model.items())) or "none recorded") + ".\n")
    w("## Every Escaped from: value\n")
    w("| defect | value | state | design | why |")
    w("|---|---|---|---|---|")
    for e in escapes:
        w("| %s#%s | `%s` | %s | %s | %s |" % (e["repo"], e["id"], e["value"], e["state"], e["design"] or "-", (e["why"] or "-").replace("|", "/")))
    w("")
    return out


def per_design_lines(D) -> list[str]:
    out = ["## Per design\n",
           "| repo | design | class | source | decided | age | reviews | fact-checks | rounds | build-changing per round (reviews / fact-checks) | tokens by model | escapes |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in D:
        per = r["build_changing_per_round"]
        out.append("| %s | %s | %s | %s | %s | %s | %d | %d | %d | %s | %s | %s |" % (
            r["repo"], r["plan"][:70].replace("|", "/"), r["class"], r["source"], r["decided"],
            "-" if r["age_days"] is None else "%dd" % r["age_days"], r["reviews"], r["fact_checks"], r["rounds"],
            " ".join("%d/%d" % x for x in zip(per["reviews"], per["fact_checks"])) or "-",
            ", ".join("%s %d" % kv for kv in sorted(r["tokens_by_model"].items())) or "-",
            "; ".join(d["where"] for d in r["post_build_defects"]) or "-"))
    out.append("")
    return out


def write_out(D, escapes, probs, aged_days, today) -> Path:
    d = N.machine_dir() / OUT_DIR
    d.mkdir(parents=True, exist_ok=True)
    (d / "design-rounds.json").write_text(json.dumps(D, indent=1) + "\n", encoding="utf-8")
    md = ["# Design-review outcomes on this machine", "",
          "Rebuilt %s by `review_stats.py` from %d review records (TD-204). Mechanical: rerun it after any record or `Escaped from:` changes." % (today, len(D)), "",
          "## Aggregates (ported from aggregate.py)", ""]
    md += aggregate_lines(D) + [""] + outcome_lines(D, escapes, aged_days) + per_design_lines(D)
    if probs:
        md += ["## Not read as written", ""] + ["- " + p for p in probs] + [""]
    (d / "design-rounds.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    trial = ["# Trial of the rounds rules against the rebuilt data", "",
             "Ported from `trial_rules.py`: round = one pass through the design's own models; stop after a round with no build-changing finding; cap = the design's repo's `design-rounds` / `design-rounds-wide`. Labelled findings where a record has them, the total-findings proxy for `unlabelled` ones; recurring topics are not simulated.", ""]
    (d / "trial.md").write_text("\n".join(trial + trial_lines(D)) + "\n", encoding="utf-8")
    return d


# ---------------------------------------------------------------- candidates


def where_cited(body: str, start: int) -> str:
    """The field or section a citation at ``start`` of an entry body sits in."""
    label = "body"
    for m in LABEL_RE.finditer(body, 0, start + 1):
        if m.start() <= start:
            label = m.group(1).strip()
    return label


def candidates(scope: Scope, since: str | None, escapes: list[dict]) -> dict:
    """{cites: [...], designs_without_record: [...]} — the backfill's mechanical half; judges nothing."""
    cites = []
    for root in scope.roots:
        ents = {e["id"]: e for e in ledger_entries(root)}
        bodies = entry_bodies(root)
        for eid, e in ents.items():
            if "escaped from" in e["fields"]:
                continue
            am = DATE_RE.search(e["fields"].get("added") or "")
            if since and (not am or am.group(0) < since):
                continue
            body = bodies.get(eid, "")
            seen = set()
            for m in CITE_RE.finditer(body):
                repo, n = m.group(1), int(m.group(2))
                ref = f"{repo}#TD-{m.group(2)}" if repo else f"TD-{m.group(2)}"
                if not repo and n == L._num(eid):
                    continue   # an entry naming itself
                where = where_cited(body, m.start())
                state, droot, dn, _ = scope.resolve(root, ref)
                hop = None
                tgt = next((v for k, v in ents.items() if L._num(k) == n), None) if not repo else None
                if state != "resolved" and tgt is not None:
                    parent, _bad = LB.parse_part_of(tgt.get("part_of_raw"))
                    if parent and L._num(parent) != L._num(eid):
                        st2, droot, dn, _ = scope.resolve(root, parent)
                        if st2 == "resolved":
                            state, hop = "resolved", f"{ref} (Part of: {parent})"
                if state != "resolved":
                    continue
                key = (str(droot), dn, where)
                if key in seen:
                    continue
                seen.add(key)
                cites.append({"repo": root.name, "id": eid, "title": e["title"], "archived": e["archived"],
                              "added": am.group(0) if am else None, "design": f"{Path(droot).name}#TD-{dn:03d}",
                              "where": where, "via": hop})
    missing = [e for e in escapes if e["state"] == "unresolved" and e["design"]]
    return {"cites": cites, "designs_without_record": missing}


# ---------------------------------------------------------------- main


def roots_for(repo: str | None) -> tuple[list[Path], Path | None, str]:
    if repo:
        p = Path(repo).resolve()
        return ([p], p, "") if p.is_dir() else ([], None, f"--repo {repo}: not a directory")
    reg = N.read_registry()
    if reg is None:
        return [], None, f"no roster at {N.registry_path()} (cadence.md §9.2); pass --repo PATH"
    return [p for p in reg if p.is_dir()], None, ""


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="review_stats.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", help="read this repo only, not the roster")
    ap.add_argument("--aged", type=int, default=14, metavar="DAYS", help="a design counts toward escape rates once Decided more than DAYS ago (14)")
    ap.add_argument("--candidates", action="store_true", help="list the backfill's candidates instead of rebuilding")
    ap.add_argument("--since", metavar="DATE", help="with --candidates: entries Added on or after DATE (YYYY-MM-DD)")
    ap.add_argument("--json", action="store_true", help="print JSON")
    a = ap.parse_args(argv)
    if a.since and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", a.since):
        print("review_stats.py: --since takes YYYY-MM-DD", file=sys.stderr)
        return 2
    if a.since and not a.candidates:
        print("review_stats.py: --since goes with --candidates", file=sys.stderr)
        return 2
    roots, only, err = roots_for(a.repo)
    if err:
        print("review_stats.py: " + err, file=sys.stderr)
        return 2
    scope = Scope(roots, only)
    today = dt.datetime.now().astimezone().date()
    D, escapes, probs = build_rows(scope, a.aged, today)
    if a.candidates:
        c = candidates(scope, a.since, escapes)
        if a.json:
            print(json.dumps(c, indent=1))
            return 0
        print("Entries citing a design, with no Escaped from: (%d) — judge each: did that design miss it?" % len(c["cites"]))
        for x in c["cites"]:
            print("  %s#%s  cites %s in %s%s%s  %s" % (x["repo"], x["id"], x["design"], x["where"],
                                                     " via " + x["via"] if x["via"] else "", " (archived)" if x["archived"] else "", x["title"][:80]))
        print("Escaped from: values naming a design with no record file (%d)" % len(c["designs_without_record"]))
        for e in c["designs_without_record"]:
            print("  %s#%s  -> %s  %s" % (e["repo"], e["id"], e["design"], e["why"]))
        return 0
    out = write_out(D, escapes, probs, a.aged, today)
    summary = {"out": str(out), "repos": len(roots), "designs": len(D), "escapes": Counter(e["state"] for e in escapes), "problems": probs}
    if a.json:
        print(json.dumps(summary, indent=1))
    else:
        print("wrote %s: %d designs from %d repos; escapes %s" % (out, len(D), len(roots), dict(summary["escapes"]) or "none"))
        for p in probs:
            print("  not read as written: " + p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
