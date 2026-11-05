#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/event_checks.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""What each open ``event (<name>)`` gate's check says now (TD-219; ledgerboard's target design §4).

    event_checks.py [--ledger DIR] [--json] [--timeout S]

An entry waiting on something outside the ledger carries ``**Blocked by:** event (<name>)`` and an
``**Event (<name>):**`` section whose ``check:`` line names one of ledgerboard's typed checks. For every
open entry's event gate this asks the forge the one fact its check needs and prints one line:

    TD-14 event (ac-vendors-v2-4): passed — ShiftLead/agent-cadence@<sha>

Each check has four outcomes (§4.2): **passed** (the gate may be lifted; the evidence is what a reviewer
re-runs: ``<repo>#<n>`` for ``pr-merged``, ``<repo>@<sha>`` for the others), **not yet**, **impossible**
(only a PR closed unmerged) and **error** (the check could not run: never read as not yet). By type:

- ``pr-merged <repo>#<n>``: merged is passed, closed unmerged impossible, open not yet; a PR the forge does
  not show is an error (a forge answers 404 for missing and for forbidden alike).
- ``file-contains <repo>[@<ref>] <path> "<text>"``: the file at the ref (default: the repo's default
  branch) holds the text, matched literally; a ref or file not there yet is not yet.
- ``ref-includes <repo>@<ref> <commit>``: the commit is the ref's or an ancestor of it; a ref or commit
  the forge does not know yet is not yet.

**The host's rules** (§4.4): a check reaches a repo only when it is on this machine's roster
(``$AGENT_CADENCE_REG_DIR`` honoured) *and* at least as visible as this ledger's own repo — a public
ledger's checks reach only public repos, since a public lift PR would leak one bit of a private one per
sweep. Anything either rule refuses, or a forge this cannot ask yet (only github.com is built), is an
error. Each forge call is bounded by ``--timeout`` (default 30s), and a call past it is an error.

This is read-only: it lifts nothing and files nothing. It is the event runner the gate sweep feeds to
ledgerboard's ``sweep()`` (``results()`` gives the ``{(TD-n, name): (outcome, evidence)}`` it takes); the
sweep's own I/O, which writes the lifts and the board items, is TD-219's next slice.

Exit 0 when every check ran (whatever it said), 1 when any is an error, 2 when the ledger cannot be read.
Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forge as F  # noqa: E402  # sibling SYNC script: the one place a forge's CLI runs
import ledger as L  # noqa: E402  # sibling SYNC script: the ledger's readers and the roster resolver
import ledgerboard as LB  # noqa: E402  # sibling SYNC file: the ledger format, defined once

TIMEOUT = 30.0  # s per forge call: a check past it is an error (§4.2)
# How visible a repo is, least first: a check reaches a repo ranked at least as high as the ledger's own.
VISIBILITY = {"private": 0, "internal": 1, "public": 2}


def gates(text: str) -> list[dict]:
    """Every open entry's event gate, in ledger order: ``{id, name, check, problem}``, ``check`` the
    section's ``parse_check()`` reading (None when the section is missing or unreadable) and ``problem``
    why the check cannot run as written (no section, two of one name, a bad ``check:`` line), else None."""
    out = []
    for tid, body in LB._entry_texts(text).items():
        found = LB.entries(body)
        if not found or LB.first_word(found[0]["fields"].get("status")) in LB.ARCHIVED_WORDS:
            continue
        secs = LB.event_sections(body)
        for name in dict.fromkeys(LB.parse_gates(found[0]["blocked_raw"])["events"]):
            mine = [s for s in secs if s["name"] == name]
            rec = {"id": tid, "name": name, "check": None, "problem": None}
            if not mine:
                rec["problem"] = f"no **Event ({name}):** section"
            elif len(mine) > 1:
                rec["problem"] = f"{len(mine)} **Event ({name}):** sections"
            elif mine[0]["problem"]:
                rec["problem"] = mine[0]["problem"]
            else:
                rec["check"] = mine[0]["check"]
            out.append(rec)
    return out


class Runner:
    """Runs checks from one ledger's repo (``own``), through this machine's roster; each repo's forge
    and facts are read once a run."""

    def __init__(self, own: Path, roster: L.Roster | None = None, timeout: float = TIMEOUT) -> None:
        self.own, self.roster, self.timeout = own, roster or L.Roster(), timeout
        self._own_vis: tuple[int | None, str] | None = None
        self._targets: dict[Path, tuple] = {}

    def _backend(self, root: Path) -> tuple[F.GitHub | F.GitLab, str]:
        """(backend, slug) of the repo at ``root``, from its origin; ForgeUnreadable when the forge has
        no backend or is a host's this does not ask yet."""
        kind, slug = F.origin_forge(root)
        host, _ = F._origin(root)
        if kind == "gitlab" and slug:
            return F.GitLab(slug=slug, per_call=self.timeout), slug
        if kind != "github" or not slug:
            raise F.ForgeUnreadable(f"{root.name}: origin names no repo a forge can be asked about")
        if host not in (None, "github.com"):
            raise F.ForgeUnreadable(f"{root.name}: event checks read github.com repos only, not {host}")
        return F.GitHub(slug=slug, per_call=self.timeout), slug

    def own_visibility(self) -> tuple[int | None, str]:
        """(rank in VISIBILITY, why) of this ledger's own repo; None when it cannot be read."""
        if self._own_vis is None:
            try:
                be, slug = self._backend(self.own)
                self._own_vis = (VISIBILITY[be.repo_info(slug)["visibility"]], "")
            except F.ForgeUnreadable as e:
                self._own_vis = (None, f"this ledger's own repo: {e}")
        return self._own_vis

    def target(self, repo: str) -> tuple:
        """(backend, slug, info) of a check's ``<repo>``, or raises ForgeUnreadable naming the rule that
        refused it: not on the roster, or less visible than this ledger's own repo."""
        root, why = self.roster.root(repo)
        if root is None:
            raise F.ForgeUnreadable(f"{repo}: {why} (a check reaches only a roster repo)")
        if root not in self._targets:   # by clone, so `tgt` and `o/tgt` read its facts once
            try:
                be, slug = self._backend(root)
                info = be.repo_info(slug)
                mine, why = self.own_visibility()
                if mine is None:
                    raise F.ForgeUnreadable(why)
                if VISIBILITY[info["visibility"]] < mine:
                    raise F.ForgeUnreadable(f"{slug} is {info['visibility']}, less visible than this ledger's own "
                                            "repo — a check reaches only a repo at least as visible")
                self._targets[root] = (be, slug, info, None)
            except F.ForgeUnreadable as e:
                self._targets[root] = (None, None, None, str(e))
        be, slug, info, err = self._targets[root]
        if err is not None:
            raise F.ForgeUnreadable(err)
        return be, slug, info

    def run(self, gate: dict) -> dict:
        """One gate's ``{outcome, evidence, why}``: evidence only on passed, why on every other outcome."""
        if gate["problem"] or gate["check"] is None:
            return {"outcome": "error", "evidence": None, "why": gate["problem"] or "no check"}
        c = gate["check"]
        try:
            be, slug, info = self.target(c["repo"])
            if c["type"] == "pr-merged":
                state = be.pr_state_of(slug, c["n"])
                if state == "merged":
                    return {"outcome": "passed", "evidence": f"{c['repo']}#{c['n']}", "why": None}
                if state == "closed":
                    return {"outcome": "impossible", "evidence": None, "why": f"{c['repo']}#{c['n']} closed unmerged"}
                return {"outcome": "not yet", "evidence": None, "why": f"{c['repo']}#{c['n']} is open"}
            ref = c["ref"] or info["default_branch"]
            sha = be.ref_sha(slug, ref)
            if sha is None:
                return {"outcome": "not yet", "evidence": None, "why": f"{c['repo']} has no {ref} yet"}
            if c["type"] == "file-contains":
                text = be.file_at(slug, c["path"], sha)
                if text is not None and c["text"] in text:
                    return {"outcome": "passed", "evidence": f"{c['repo']}@{sha}", "why": None}
                said = "has no such file" if text is None else "does not hold the text"
                return {"outcome": "not yet", "evidence": None, "why": f"{c['path']} at {ref} ({sha[:12]}) {said}"}
            inc = be.includes(slug, sha, c["commit"])
            if inc:
                return {"outcome": "passed", "evidence": f"{c['repo']}@{sha}", "why": None}
            said = "does not know the commit yet" if inc is None else f"{ref} ({sha[:12]}) does not include it"
            return {"outcome": "not yet", "evidence": None, "why": f"{c['commit']}: {c['repo']} {said}"}
        except F.ForgeUnreadable as e:
            return {"outcome": "error", "evidence": None, "why": str(e)}


def results(text: str, runner: Runner) -> dict:
    """``{(TD-n, event name): (outcome, evidence)}`` for every open event gate of ``text``, as ledgerboard's
    ``sweep()`` takes its ``results``."""
    return {(g["id"], g["name"]): (r["outcome"], r["evidence"]) for g in gates(text) for r in [runner.run(g)]}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--ledger", help="a v1 file or a v2 directory; default: this work tree's docs/ledger/, "
                                     "else docs/technical_debt.md")
    ap.add_argument("--timeout", type=float, default=TIMEOUT, help=f"seconds per forge call (default {TIMEOUT:g})")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    top = L._toplevel()
    io = L.fs_io()
    ledger = Path(a.ledger) if a.ledger else top / L.ledger_at(top, (lambda p: io[0](str(top / p)), io[1]))
    text, _ = L.read_pair(str(ledger), None, io)
    if text is None:
        print(f"event_checks: cannot read {ledger}", file=sys.stderr)
        return 2
    runner = Runner(top, timeout=a.timeout)
    rows = [{**g, **runner.run(g)} for g in gates(text)]
    if a.json:
        print(json.dumps({"checks": [{k: r[k] for k in ("id", "name", "check", "outcome", "evidence", "why")}
                                     for r in rows]}, indent=2, ensure_ascii=False))
    elif not rows:
        print(f"no open event gates in {ledger}")
    for r in rows if not a.json else []:
        print(f"{r['id']} event ({r['name']}): {r['outcome']} — {r['evidence'] or r['why']}")
    return 1 if any(r["outcome"] == "error" for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
