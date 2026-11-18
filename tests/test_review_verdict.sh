#!/usr/bin/env bash
# TD-288 (TD-281's design, docs/plans/2026-11-17-design-round-endings.md rules 1-9): review_stats.py
# --verdict and --after-round. The fixtures are the spec for the edges: one per row of rule 6's table,
# one per test of rule 9's *What --verdict prints at 3*, and the Consequences' list. Offline: one fixture
# repo in a temp dir; HOME/XDG_CONFIG_HOME/AGENT_CADENCE_REG_DIR are temp dirs.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$AGENT_CADENCE_REG_DIR"
unset CADENCE_DESIGN_ROUNDS CADENCE_DESIGN_ROUNDS_WIDE CADENCE_DESIGN_HOLD_ROUNDS

python3 - "$DC/files/scripts/review_stats.py" "$TMP" <<'PY'
import json, subprocess, sys
from pathlib import Path

RS, TMP = sys.argv[1], Path(sys.argv[2])
PASS = FAIL = 0
N = [0]


def ok(name):
    global PASS
    PASS += 1
    print("PASS: " + name)


def bad(name, why):
    global FAIL
    FAIL += 1
    print(f"FAIL: {name}: {why}")


class Rec:
    """A review record built row by row: each row is (round, role, findings); a finding is (class, status)."""

    def __init__(self, cls="in-repo"):
        self.cls, self.rows, self.head = cls, [], {}

    def row(self, rnd, role, *finds):
        self.rows.append((rnd, role, finds))
        return self

    def rounds(self, *counts, start=1, reopen=()):
        """One design review per round, raising that round's count of build-changing findings (applied);
        a round in ``reopen`` marks its first finding `reopens F1` inside an applied status."""
        for i, n in enumerate(counts, start):
            finds = [("build-changing", "applied: fixed (reopens F1)" if (i in reopen and k == 0) else "applied")
                     for k in range(n)]
            self.row(i, "design", *finds)
        return self

    def text(self, decided="pending"):
        h = {"Design": "docs/plans/x.md", "Class": self.cls, "Decided": decided, "Source": "rounds", **self.head}
        out = ["# Review record: x", ""] + [f"**{k}:** {v}" for k, v in h.items() if v is not None] + [""]
        out += ["| review | round | role | model | tokens | date |", "|---|---|---|---|---|---|"]
        fl, f = [], 0
        for i, (rnd, role, finds) in enumerate(self.rows, 1):
            out.append(f"| R{i} | {rnd} | {role} | m | 1 | x |")
            for cls, status in finds:
                f += 1
                by = "person" if cls.startswith("person:") else f"R{i}"
                fl.append(f"| F{f} | {rnd} | {by} | t | x | {cls.removeprefix('person:')} | {status} |")
        out += ["", "| id | round | by | topic | finding | class | status |", "|---|---|---|---|---|---|---|"] + fl
        return "\n".join(out) + "\n"


def run(rec, after=False, decided="pending", gate=False, toml="", entry=True, extra=()):
    """Write a fresh repo holding TD-1's record and entry; return (rc, stdout, stderr, json-or-None)."""
    N[0] += 1
    root = TMP / f"r{N[0]}"
    (root / "docs/reviews").mkdir(parents=True)
    (root / "docs/ledger").mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    if toml:
        (root / "docs/cadence.toml").write_text(toml)
    if entry:
        (root / "docs/ledger/TD-001.md").write_text(
            "## TD-001: a design\n\n**Priority:** Low\n**Type:** feature\n**Added:** 2026-01-01\n**Status:** Open\n"
            + ("**Blocked by:** decision (someone)\n" if gate else "") + "\n**Why:** y\n")
    (root / "docs/reviews/TD-001.md").write_text(rec if isinstance(rec, str) else rec.text(decided))
    args = ["python3", RS, "--verdict", "TD-1", "--repo", str(root)] + (["--after-round"] if after else []) + list(extra)
    p = subprocess.run(args, capture_output=True, text=True)
    pj = subprocess.run(args + ["--json"], capture_output=True, text=True)
    try:
        j = json.loads(pj.stdout)
    except ValueError:
        j = None
    return p.returncode, p.stdout, p.stderr, j


def expect(name, rec, want, **kw):
    rc, out, err, j = run(rec, **kw)
    last = out.strip().splitlines()[-1] if out.strip() else ""
    if rc == 0 and last == f"next: {want}" and j and j["next"] == want:
        ok(name)
        return j, err
    bad(name, f"rc={rc} last={last!r} err={err.strip()!r}")
    return j, err


def judged(rec, verdict="Go", outcome="CONFIRM", reach="routine", mark="routine"):
    """The rows' end: a closing fact-check (clean) and one judge row whose line is in Verdict:."""
    last = max(r[0] for r in rec.rows)
    rec.row(last, "fact-check")
    rec.row(last, "judge")
    rec.head["Verdict"] = f"{verdict} (R{len(rec.rows)}) · cadence-judge: {outcome} · reach {reach} · a reason"
    if mark is not None:
        rec.head["Reach"] = f"{mark} — a reason"
    return rec


# --- --after-round (rule 9 step 1)
expect("1 after-round: a round that raised a build-changing finding, within the cap: continue", Rec().rounds(2), "continue", after=True)
expect("1b after-round: a clean round (the stop rule): end", Rec().rounds(2, 0), "end", after=True)
expect("1c after-round: the cap's round, still raising: end", Rec().rounds(4, 3, 2, 1), "end", after=True)
expect("1d after-round: N reopen rounds: hold", Rec().rounds(4, 3, 2, start=1, reopen=(1, 2, 3)), "hold", after=True)
expect("1e after-round: the last N counts not falling: hold", Rec().rounds(1, 2, 2), "hold", after=True)
expect("1f after-round: fewer than N rounds is never not falling: continue", Rec().rounds(1, 2), "continue", after=True)
expect("1g after-round: hold over end on a clean round that trips the Hold rule",
       Rec().rounds(5, 4, 3, 2, 0, reopen=(2, 3, 4)), "hold", after=True)
expect("1h after-round: hold over end on a cap round that trips the Hold rule",
       Rec().rounds(4, 3, 2, 1, reopen=(2, 3, 4)), "hold", after=True)
r = Rec().rounds(1, 1, 2)
r.head["Holds"] = "1"
expect("1i after-round: no Hold check before the Nth round since the last Hold", r, "continue", after=True)
r = Rec().rounds(3, 2)
r.head["Bought"] = "1"
expect("1j after-round: the bought round ends the rounds: end", r, "end", after=True)
r = Rec().rounds(1, 2, 2)
r.head["Bought"] = "2"
expect("1k after-round: a bought round that also trips the Hold rule: end", r, "end", after=True)
expect("1l after-round: design-hold-rounds = 2 holds on two not-falling rounds", Rec().rounds(1, 1), "hold", after=True,
       toml="design-hold-rounds = 2\n")

# --- rule 2's verdict table, through --verdict
expect("2 a clean last round, nothing unread, no judge yet: judge", Rec().rounds(2, 0), "judge")
expect("2b a build-changing finding unread, no closing read: closing-read", Rec().rounds(2, 0).row(2, "fact-check", ("build-changing", "applied")), "closing-read")
r = Rec().rounds(2, 0).row(2, "fact-check", ("build-changing", "applied")).row(2, "closing-read", ("build-changing", "applied"))
j, _ = expect("2c a closing read raised one: One more round, within the cap: round", r, "round")
if j and j["verdict"] == "One more round" and j["unread_build_changing"] == ["F4"]:
    ok("2d the One more round names the closing read's finding as unread")
else:
    bad("2d", j)
r = Rec().rounds(4, 3, 2, 1).row(4, "fact-check").row(4, "closing-read", ("build-changing", "applied"))
expect("2e One more round past the cap: item", r, "item")
r = Rec().rounds(2, 0).row(2, "fact-check", ("build-changing", "applied")).row(2, "closing-read")
expect("2f the closing read reads the closing fact-check's fix: Go, judge", r, "judge")
r = Rec().rounds(2, 1)
r.rows[-1] = (2, "design", (("build-changing", "rejected: not so"),))
expect("2g a rejected build-changing finding is unread: closing-read", r, "closing-read")
r = Rec().rounds(2, 0).row(2, "fact-check", ("person:build-changing", "applied"))
expect("2h a finding the person raises is never unread: judge", r, "judge")
j, _ = expect("2i Hold: N reopen rounds (reopens inside an applied status): judge", Rec("wide").rounds(4, 3, 2, 1, reopen=(2, 3, 4)), "judge")
if j and j["verdict"] == "Hold" and j["reopen_rounds"] == [2, 3, 4]:
    ok("2j the reopen rounds are counted from the status's text")
else:
    bad("2j", j)

# --- rule 6's table, the judge's line applied
expect("6a CONFIRM, routine Go, no gate: go", judged(Rec().rounds(2, 0)), "go")
expect("6b CONFIRM, routine Go, the entry gated: item", judged(Rec().rounds(2, 0)), "item", gate=True)
expect("6c RAISE: item", judged(Rec().rounds(2, 0), outcome="RAISE"), "item")
expect("6d CONFIRM, far-reaching by the mark: item", judged(Rec().rounds(2, 0), mark="far-reaching"), "item")
expect("6e CONFIRM, far-reaching by the judge's reading: item", judged(Rec().rounds(2, 0), reach="far-reaching"), "item")
expect("6f CONFIRM on a first Hold, routine: revise",
       judged(Rec("wide").rounds(4, 3, 2, 1, reopen=(2, 3, 4)), verdict="Hold"), "revise")
r = judged(Rec("wide").rounds(9, 4, 3, 2, 1, reopen=(3, 4, 5)), verdict="Hold")
r.head["Holds"] = "1"
expect("6g CONFIRM on a second Hold (Holds names an earlier round): item", r, "item")
j, err = expect("6h no Reach: line — a routine CONFIRM of Go reads far-reaching: item", judged(Rec().rounds(2, 0), mark=None), "item")
if "no Reach: line" in err:
    ok("6i ... with a warning")
else:
    bad("6i", err)
expect("6j the judge's line judged another verdict: judge", judged(Rec().rounds(2, 0), verdict="Hold"), "judge")
r = judged(Rec().rounds(2, 0))
r.row(2, "fact-check")
expect("6k a row recorded after the judge's: its line no longer applies: judge", r, "judge")
r = judged(Rec().rounds(2, 0))
r.row(2, "judge")
expect("6l two judge rows on one verdict: item", r, "item")
r = Rec().rounds(2, 0).row(2, "fact-check").row(2, "judge")
r.head["Verdict"] = "none"
expect("6m a judge row with no valid line is a spent run: judge again", r, "judge")
r.row(2, "judge")
expect("6n ... and the next makes two: item", r, "item")
expect("6o a cap ending with a non-zero last round, counted Go: item, no judge", Rec().rounds(4, 3, 2, 1).row(4, "fact-check").row(4, "closing-read"), "item")
expect("6p ... and counted Hold: item", Rec().rounds(4, 3, 2, 1, reopen=(2, 3, 4)), "item")
r = Rec().rounds(2, 0, 0, 0)
r.head["Holds"] = "2"
judged(r)
expect("6q a routine Go after an item's Hold, the entry still gated: item", r, "item", gate=True)

# --- rule 9's guards
r = Rec().rounds(4, 3, 2, 0, reopen=(2, 3, 4))
r.head["Holds"] = "4"
expect("9a a rerun after step 8 (Holds names the last round): revise", r, "revise")
r.row(5, "fact-check")
expect("9b a Hold at 4 with only a round-5 fact-check row: revise", r, "revise")
r = Rec().rounds(3, 2, 1)
r.head["Bought"] = "3"
r.row(4, "fact-check")
expect("9c Bought: 3 with only a round-4 fact-check row: round", r, "round")
r = Rec().rounds(3, 2, 1, 0)
r.head["Bought"] = "3"
expect("9d the rounds ended after a bought round, counted Go: item (no closing read, no judge)", r, "item")
r = Rec().rounds(3, 2, 1, 1).row(4, "fact-check", ("build-changing", "applied"))
r.head["Bought"] = "3"
j, _ = expect("9e ... counted Closing read: item", r, "item")
if j and j["verdict"] == "Closing read":
    ok("9f ... the counted verdict is still Closing read")
else:
    bad("9f", j)
r = Rec().rounds(1, 2, 2)
r.head["Bought"] = "2"
j, _ = expect("9g ... counted Hold: item", r, "item")
r = Rec().rounds(5, 4, 3, 2, 1)
r.head["Bought"] = "2, 4"
expect("9h two bought rounds, the last one counts: item", r, "item")
r = Rec().rounds(5, 4, 3, 2)
r.head["Bought"] = "2, 4"
expect("9i ... while the last bought round has not run: round", r, "round")
r = Rec().rounds(3, 2, 1)
r.head.update(Bought="2", Holds="3")
expect("9j a person's Hold after a bought round: revise, not item", r, "revise")
r = Rec().rounds(3, 2, 1, 2)
r.head.update(Bought="2", Holds="3")
expect("9m a bought round before a later Hold no longer ends the revision's rounds: closing-read", r, "closing-read")
j, _ = expect("9n three clean rounds are not 'not falling' (the last count must be non-zero): Go, judge", Rec().rounds(0, 0, 0), "judge")
if j and j["verdict"] == "Go" and not j["not_falling"]:
    ok("9o ... the counted verdict is Go")
else:
    bad("9o", j)
r = Rec().rounds(3, 2)
r.head["Holds"] = "2"
expect("9p after-round, a Hold standing on the last round: revise, as --verdict", r, "revise", after=True)
r = Rec().rounds(2, 1)
r.head["Bought"] = "2"
expect("9q after-round, a bought round not yet run: round, as --verdict", r, "round", after=True)
r = Rec().rounds(2, 0)
r.head["Holds"] = "2025-11-01"
_, err = expect("9r a Holds: that is not a list of rounds is read by its numbers", r, "judge")
if "Holds: '2025-11-01' is neither none nor a list of rounds" in err:
    ok("9s ... with a warning")
else:
    bad("9s", err)
_, err = expect("9t a pending record with no Reach: warns on any step", Rec().rounds(2, 0), "judge")
if "no Reach: line" in err:
    ok("9u ... before any judge runs")
else:
    bad("9u", err)
expect("9k a record lacking Holds, Bought, Verdict, Go by: read as none, pending: judge", Rec().rounds(2, 0), "judge")
expect("9l Holds: none reads as no Hold", (lambda r: (r.head.update(Holds="none", Bought="none"), r)[1])(Rec().rounds(2, 0)), "judge")

# --- the cap
j, _ = expect("cap a wide design's 5th of 6 rounds, One more round: round",
              Rec("wide").rounds(6, 5, 4, 3, 2).row(5, "closing-read", ("build-changing", "applied")), "round")
expect("cap b ... its 6th: item", Rec("wide").rounds(7, 6, 5, 4, 3, 2).row(6, "closing-read", ("build-changing", "applied")), "item")
r = Rec().rounds(4, 3, 2, 1)
r.head["Bought"] = "3"
j, _ = expect("cap c a bought round counts toward the cap", r, "item")
if j and j["past_cap"]:
    ok("cap d ... past_cap is true at 4 rounds of 4, the bought one among them")
else:
    bad("cap d", j)
r = Rec("wide").rounds(9, 8, 7, 0, 6, 5, 4, 3, 2, 1)
r.head["Holds"] = "4"
_, _ = expect("cap e the cap counted from a Hold: round 10 of a Hold at 4 is past a cap of 6", r, "end", after=True)
r = Rec("wide").rounds(9, 8, 7, 0, 6, 5, 4, 3, 2)
r.head["Holds"] = "4"
expect("cap f ... round 9 is within it", r, "continue", after=True)

# --- decided, and what cannot be resolved
r = Rec().rounds(2, 0)
r.head["Go by"] = "someone"
expect("done a record decided by the person's Go: done", r, "done", decided="2026-01-02")
expect("done b ... from --after-round too", r, "done", decided="2026-01-02", after=True)
r = judged(Rec().rounds(2, 0))
r.head["Go by"] = "judge"
expect("done c a record decided by a routine Go: done", r, "done", decided="2026-01-02")
for name, kw, rec in (("exit an unknown entry", {"entry": False}, Rec().rounds(1)),
                      ("exit b a missing Class", {}, Rec().rounds(1).text().replace("**Class:** in-repo\n", "")),
                      ("exit c an unknown Class", {}, Rec().rounds(1).text().replace("**Class:** in-repo", "**Class:** big")),
                      ("exit d a Source: backfill record", {}, Rec().rounds(1).text().replace("**Source:** rounds", "**Source:** backfill"))):
    rc, out, err, _ = run(rec, **kw)
    if rc == 2 and "cannot count the verdict" in err and not out:
        ok(name + ": exit 2 naming the reason")
    else:
        bad(name, f"rc={rc} out={out!r} err={err!r}")

# --- what it reads
r = Rec().row(1, "design", ("build-changing", "applied")).row(1, "fact-check (closing)", ("build-changing", "applied")).row(2, "review")
j, err = expect("read a qualified fact-check is a fact-check, a free-form role a design review", r, "judge")
if j and j["fact_check_counts"] == {"1": 1, "2": 0} and j["counts"] == {"1": 1, "2": 0} and "'review' read as design" in err:
    ok("read b ... counted apart, and the free-form role warned")
else:
    bad("read b", (j, err))
r = Rec().rounds(2, 0)
r.head["Go by"] = "judge"
_, err = expect("read c Go by: judge with no judge row", r, "judge")
if "no judge row" in err:
    ok("read d ... warns")
else:
    bad("read d", err)

print(f"---- {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
PY
