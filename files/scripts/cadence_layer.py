#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/cadence_layer.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""The person's own cadence layers, read at session start (TD-126, cadence.md §9.18).

    cadence_layer.py --hook    SessionStart (cadence_hooks.sh): print every layer, in order;
                               nothing at all when no layer is set
    cadence_layer.py           one line per layer: where it is, the commit it is read at, and
                               whether it could be read
    cadence_layer.py --json    the same list for a tool (TD-132): each layer's path, file, repo root,
                               kind (own | followed), ref, commit, note and error — never fetched
    cadence_layer.py --effective
                               show effective: every rule keyed by a cadence.md § (`§4.8 override:`,
                               `§4.8 add:`), per §, with its layer and line (each layer listed with its
                               commit), and whether it
                               holds or which later override superseded it; then the unkeyed rules
    cadence_layer.py --publish-check [--accept FILE] [FILE…]
                               before a layer's repo is made public: every tracked file of each
                               of one's own layers' repos (or the FILEs named), each line naming
                               a machine path, this machine's name (and its short name, the part
                               before the first `-`), a repo on the roster, a name the machine's
                               `publish-names` lists, or an email address — the TD-090 scrub, for
                               one repo. Not a finding: the tool's own name, an email at a reserved
                               domain (example.com, .test, …) and a placeholder home (/home/someone).
                               With --accept FILE it is a gate (TD-189, a repo's precheck): a line
                               of FILE accepts a finding meant to be public, a relative markdown link
                               to a file not there is a finding too, and it ends `gate: …`. In a repo
                               whose docs/cadence.toml sets publish-gate = "required" the gate exits
                               2 on a machine with no publish-names, which would otherwise pass everything
    cadence_layer.py --follow <url-or-clone> --ref <tag|commit> [--file <path in repo>] [--dir <clone dir>]
                               follow someone else's layer (TD-130): clone it or reuse the clone,
                               fetch its tags, check the pin (it resolves, is a tag or a commit and
                               not a branch, the file is there at it, no layer names the path),
                               print the file at it and the --effective view with it, then insert
                               its [[layers]] table before one's own
    cadence_layer.py --update <n> [--ref <tag|commit>]
                               layer n's newer tags; with --ref, the same checks, a warning when it
                               does not descend from the pin, the diff, and the ref line moved

WHY A LAYER
agent-cadence has one central source, its owner's. A person's own rules — the ones that should
hold in all their repos, on all their machines — have no home in a repo (a repo two people
share would take one person's rules) and none in a synced file (a fork conflicts at every
upstream merge). So they live in a file in a git repo the person owns, cloned on each machine,
and the machine's `cadence.toml` (§9.18) names it:

    [[layers]]
    path = "~/src/alice-cadence-layer/cadence-personal.md"   # someone else's, followed
    ref = "v1.2"                                             # read at this ref, never pulled
    [[layers]]
    path = "~/cadence-layer/cadence-personal.md"             # one's own: the working tree

A layer with a `ref` is one the person does not own: it is read at that ref (`git show`) from
the clone, and moving the pin is the update and the review point, since that text steers the
person's sessions. A layer without one is the person's own, read from the working tree — its
edits are already theirs. The hook never clones or pulls, and never fetches a pinned layer. For
one's own it fetches its branch's upstream (no prune, no tags, no gc) and says when the clone is
behind — the session would read older rules — or holds commits not pushed, which no other machine
has; a detached HEAD, no upstream or a local-branch upstream is said as such. The whole run, every
git call and fetch included, keeps to RUN_BUDGET seconds, inside the runner's 10 s bound.

Precedence: the repo's own CLAUDE.md or AGENTS.md first, then the layers (a later one winning
over an earlier one), then cadence.md. A layer is prose: it cannot replace a shared script or
turn off a gate. A layer that cannot be read is a warning line, never a failure; --hook always
exits 0. The setting is read through cadence_config.py (MACHINE_KEYS), never a second parser,
from the machine's file only — a repo's own settings file that cannot be read does not cost the
person their layer.

Rules keyed by §: a layer line that starts `§4.8 override: …` or `§4.8 add: …` names the cadence.md
§ it changes, because prose has no keys to merge on and two layers could otherwise contradict each
other unnoticed. An override replaces that § and its sub-§s as the earlier layers left it; an add
stacks on what stands. Any other paragraph or list item is an unkeyed rule — it holds, and is
listed as such. The hook ends with a one-line summary of the by-§ view, and warns on a key naming a § that
cadence.md does not have, or one layer overriding the same § twice; --effective prints it whole
(it never fetches).

Exit codes (without --hook): 0 every layer read, or none set; 1 a layer could not be read (or,
with --effective, a warning: an unknown §, or a § one layer overrides twice); 2 the machine's
settings file could not be read. --publish-check: 0 nothing found, 1 a line to
look at (a finding is for the person to judge — a name may be meant to be public), 2 nothing to
check, a file that could not be read and nothing found, or the setting could not be read (or, with
publish-gate required, publish-names is unset; or the --accept file cannot be read). With --accept,
1 means a finding no accept line covers. It
reads the current tree only: what is in the repo's history goes public too, and is not read.
--json: 0 every layer read, or none set; 1 a layer carries an error; 2 the setting could not be read
(then {"error": …}). --follow / --update: 0 done (or, --update alone, the newer tags listed), 1 refused — the reason
printed and the settings file as it was — 2 a usage error. They are the one exception to §9.18's
*tools only read the settings files*: a text insert or one ref line's value, read back through
cadence_config and put back unless the whole file reads as before plus that change. Stdlib only.
"""

from __future__ import annotations

import fnmatch
import os
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cadence_config  # noqa: E402

MAX_BYTES = 64 * 1024   # one layer's ceiling in the session's context; the rest is cut, and said so
GIT_TIMEOUT = 5
# One deadline for the whole run, under the runner's 10 s bound for this child: a child cut at
# its bound prints nothing at all, so a dead remote or a wedged clone must cost the behind line,
# never the layers. Every git call is clipped to it; the fetches stop FETCH_RESERVE short of it.
RUN_BUDGET = 8.0
FETCH_TIMEOUT = 4.0
FETCH_RESERVE = 2.5    # run_graceful's SIGTERM grace, and the local calls left to make after a fetch
_deadline = time.monotonic() + RUN_BUDGET


# the layer's own clone decides, never a GIT_DIR or GIT_WORK_TREE the session happens to carry
GIT_ENV = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}


def git(cwd: str, *args: str) -> tuple[int, str]:
    timeout = min(GIT_TIMEOUT, _deadline - time.monotonic())
    if timeout <= 0.1:
        return 1, ""
    try:
        p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout, check=False, env=GIT_ENV)
    except (OSError, subprocess.SubprocessError):
        return 1, ""
    return p.returncode, p.stdout


def origin_state(d: str, fetch: bool = True) -> str:
    """One's own layer against its upstream (TD-126 (3)): fetch that one branch, bounded, with no
    prune, no tags and no gc, then say how far behind or ahead the clone is. "" when level.
    fetch=False compares with the last fetch and says nothing more when level."""
    rc, branch = git(d, "symbolic-ref", "--short", "-q", "HEAD")
    branch = branch.strip()
    if rc != 0 or not branch:
        return "a detached HEAD: not compared with any upstream"
    remote = git(d, "config", "--get", f"branch.{branch}.remote")[1].strip()
    merge = git(d, "config", "--get", f"branch.{branch}.merge")[1].strip()
    if not remote or not merge:
        return "its branch has no upstream: an edit here reaches no other machine"
    if remote == ".":
        return f"its upstream is the local branch {merge.removeprefix('refs/heads/')}: an edit here reaches no other machine"
    shown = f"{remote}/{merge.removeprefix('refs/heads/')}"
    timeout = min(FETCH_TIMEOUT, _deadline - time.monotonic() - FETCH_RESERVE)
    stale = None   # why origin was not fetched just now; the counts are then the last fetch's
    if not fetch:
        stale = "not fetched now"
    elif timeout <= 0.5:
        stale = "the hook's time budget was spent"
    else:
        env = {**GIT_ENV, "GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=3"}
        # the remote's own refspec maps the branch to its tracking ref (git updates it opportunistically)
        cmd = ["git", "-C", d, "-c", "gc.auto=0", "-c", "maintenance.auto=false", "-c", "fetch.writeCommitGraph=false",
               "fetch", "-q", "--no-prune", "--no-tags", "--no-recurse-submodules", remote, merge]
        try:
            try:  # the fetch that signals its whole process group at the bound (TD-044), never a copy
                from nudge_user_attention import run_graceful
            except ImportError:  # a partial install: a plain bounded run still holds the budget
                def run_graceful(cmd, timeout, env):
                    return subprocess.run(cmd, capture_output=True, timeout=timeout, env=env,
                                          stdin=subprocess.DEVNULL, check=False)
            r = run_graceful(cmd, timeout, env)
            if r.returncode != 0:
                err = [ln for ln in r.stderr.decode("utf-8", errors="replace").strip().splitlines() if ln.strip()]
                stale = f"the fetch failed: {err[0] if err else 'no message'}"
        except (OSError, subprocess.SubprocessError):
            stale = f"the fetch was stopped after {timeout:.0f}s"
    rc, counts = git(d, "rev-list", "--left-right", "--count", "HEAD...@{upstream}")
    if rc != 0 and stale is None:  # a tracking ref the remote's refspec does not keep: the fetch itself
        rc, counts = git(d, "rev-list", "--left-right", "--count", "HEAD...FETCH_HEAD")
    try:
        ahead, behind = (int(x) for x in counts.split())
    except ValueError:
        return f"not compared with {shown}" + (f" ({stale})" if stale else "")
    said = []
    if behind:
        said.append(f"{behind} commit{'s' if behind > 1 else ''} behind {shown} — pull it: this session reads the older rules")
    if ahead:
        said.append(f"{ahead} commit{'s' if ahead > 1 else ''} not pushed to {shown} — push it: your other machines do not have them")
    if stale and (said or fetch):
        said.append(f"{'as of' if said else f'level with {shown} as of'} the last fetch ({stale})")
    return "; ".join(said)


def setting() -> list[dict]:
    """The `layers` setting from the machine's file. Raises cadence_config.ConfigError."""
    path = cadence_config.machine_path()
    table = cadence_config.load(path)
    if not table or "layers" not in table:
        return []
    return cadence_config._valid("layers", table["layers"], path)


def own_layer():
    """The person's own layer file — the last layer with no `ref` — as a Path, or None. Where the
    memory harvest keeps its record and stamp (TD-125). Raises cadence_config.ConfigError."""
    from pathlib import Path
    own = [e for e in setting() if not e.get("ref")]
    return Path(os.path.expanduser(own[-1]["path"])) if own else None


def read(entry: dict, fetch: bool = True) -> dict:
    """One layer: {shown, kind, commit, note, text, error, origin}; text is None when it was not
    read. fetch=False leaves one's own layer's upstream alone (origin stays "")."""
    shown, ref = entry["path"], entry.get("ref")
    if _deadline - time.monotonic() <= 0.5:   # every git call would fail: say why, not a wrong reason
        return {"shown": shown, "kind": f"pinned {ref}" if ref else "own", "commit": None, "note": "",
                "text": None, "error": f"the hook's {RUN_BUDGET:.0f} s budget was spent before this layer", "origin": ""}
    path = os.path.expanduser(shown)
    d, name = os.path.dirname(path), os.path.basename(path)
    out = {"shown": shown, "kind": f"pinned {ref}" if ref else "own", "commit": None,
           "note": "", "text": None, "error": None, "origin": ""}
    if not name:
        out["error"] = "not a file (the path ends in /)"
        return out
    in_git = os.path.isdir(d) and git(d, "rev-parse", "--is-inside-work-tree")[1].strip() == "true"
    if ref:
        if not in_git:
            out["error"] = "not in a git clone, so its pinned ref cannot be read"
            return out
        rc, sha = git(d, "rev-parse", "--verify", "--quiet", "--short", f"{ref}^{{commit}}")
        if rc != 0:
            out["error"] = f"ref {ref} is not in the clone (a pinned layer is never fetched: fetch it, or move the pin)"
            return out
        out["commit"] = sha.strip()
        rc, prefix = git(d, "rev-parse", "--show-prefix")
        rc2, text = git(d, "show", f"{ref}:{prefix.strip()}{name}")
        if rc or rc2:
            out["error"] = f"no {name} at {ref}"
            return out
        out["text"] = text
        return out
    if not os.path.isfile(path):
        out["error"] = "not found" if not os.path.lexists(path) else "not a file"
        return out
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            out["text"] = f.read(MAX_BYTES + 1)
    except OSError as e:
        out["error"] = f"cannot read ({e.strerror or e})"
        return out
    if not in_git:
        out["note"] = "not in a git clone: it is on this machine alone"
        return out
    st = git(d, "status", "--porcelain", "--ignored", "--", name)[1]
    if st.startswith(("??", "!!")):
        out["note"] = "not committed: it is on this machine alone"
        return out
    rc, sha = git(d, "rev-parse", "--short", "HEAD")
    out["commit"] = sha.strip() if rc == 0 else None
    if st.strip():
        out["note"] = "with uncommitted edits"
    out["origin"] = origin_state(d, fetch)
    return out


def where(r: dict) -> str:
    at = f" @ {r['commit']}" if r["commit"] else ""
    note = f", {r['note']}" if r["note"] else ""
    return f"{r['shown']}{at} ({r['kind']}{note})"


# --- rules keyed by § (TD-126 (4a)/(4b)) ---------------------------------------------------
# Prose has no keys to merge on, so two layers can contradict each other with nobody noticing.
# A line that starts `§4.8 override: …` or `§4.8 add: …` (a list item's or a paragraph's, or
# one of its lines; the key optionally bold) names the cadence.md § it changes; an override replaces that § — and its
# sub-§s — as the earlier layers left it, an add stacks on what stands. Any other paragraph or
# list item is an unkeyed rule: it holds, and is listed as such, but no tool can say what it changes.
# Bounded § numbers (no int() of a 5000-digit key) and no two adjacent runs of the same
# whitespace (a line of spaces must not backtrack quadratically at session start).
RULE_RE = re.compile(r"^[ \t]*(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:\*\*)?§(\d{1,4}(?:\.\d{1,4}){0,4})(?:\*\*)?[ \t]+"
                     r"(override|add)(?:[ \t]*\*\*)?[ \t]*:(?:\*\*)?[ \t]*(.*)$", re.IGNORECASE)
ITEM_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\S")
FENCE_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
TEXT_SHOWN = 100
HOOK_SECTIONS = 30
HOOK_WARNINGS = 5   # the session's context is no place for a list: --effective has the rest


def known_sections() -> set[str] | None:
    """Every § cadence.md defines — its `## N.` sections and its `**§N.M**` rules — or None
    when there is no cadence.md beside this script to read."""
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "cadence.md")
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    return set(re.findall(r"(?m)^## (\d+)\. ", text)) | set(re.findall(r"\*\*§(\d+(?:\.\d+)+)\*\*", text))


def rules(text: str) -> list[dict]:
    """A layer's rules in order: {line, sec, verb, text} — sec and verb are None when unkeyed."""
    out, fence, comment, prev_blank = [], "", False, True
    try:   # the reader's own pattern, never re-typed (cadence.md §7.9)
        from nudge_user_attention import HARVEST_RE as harvest_re
    except ImportError:
        harvest_re = None
    for n, ln in enumerate(text.splitlines(), 1):
        f = FENCE_RE.match(ln)
        if fence:   # closed only by the same character, at least as long, and nothing after it
            if f and f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence) and not f.group(2).strip():
                fence = ""
            continue
        if f:
            fence = f.group(1)
            prev_blank = False
            continue
        if comment or ln.lstrip().startswith("<!--"):
            comment = "-->" not in ln
            continue
        if not ln.strip():
            prev_blank = True
            continue
        if ln.lstrip().startswith("#"):   # a heading groups rules; it is none itself
            prev_blank = True
            continue
        if harvest_re is not None and harvest_re.match(ln):   # the harvest's stamp (TD-125): no rule
            prev_blank = True
            continue
        m = RULE_RE.match(ln)
        if m or prev_blank or ITEM_RE.match(ln):
            said = (m.group(3) if m else ln.strip()).strip()
            said = said if len(said) <= TEXT_SHOWN else said[:TEXT_SHOWN - 1] + "…"
            out.append({"line": n, "sec": m.group(1) if m else None, "verb": m.group(2).lower() if m else None,
                        "text": said})
        prev_blank = False
    return out


def _within(sec: str, over: str) -> bool:
    return sec == over or sec.startswith(over + ".")


def effective(layers: list[tuple[int, str]]) -> dict:
    """layers: (number, text) for every layer read, in order. Returns {"rules": every keyed rule
    with the one that superseded it (or None: it holds), "unkeyed": [(layer, line)], "problems"}."""
    known = known_sections()
    keyed, unkeyed, problems = [], [], []
    if known is None:
        problems.append("no cadence.md beside this script: the § keys were not checked against it")
    for i, text in layers:
        for r in rules(text[:MAX_BYTES]):
            if r["sec"] is None:
                unkeyed.append((i, r["line"]))
                continue
            r = {**r, "layer": i, "superseded_by": None}
            if known is not None and r["sec"] not in known:
                problems.append(f"layer {i} line {r['line']}: §{r['sec']} names no rule in cadence.md, so what it changes is unknown")
            if r["verb"] == "override":
                for e in keyed:
                    if e["superseded_by"] is None and _within(e["sec"], r["sec"]):
                        e["superseded_by"] = r
                        if e["layer"] == i and e["verb"] == "override" and e["sec"] == r["sec"]:
                            problems.append(f"layer {i} overrides §{e['sec']} at line {e['line']} and again at line "
                                            f"{r['line']}: one layer, two overrides — keep one")
            keyed.append(r)
    return {"rules": keyed, "unkeyed": unkeyed, "problems": problems}


def _sec_key(sec: str) -> tuple[int, ...]:
    return tuple(int(x) for x in sec.split("."))


def superseder(r: dict) -> str:
    s = r["superseded_by"]
    return f"layer {s['layer']}'s §{s['sec']} override (line {s['line']})"


def summary(eff: dict) -> list[str]:
    """The hook's short form: one clause per §, what holds and what it superseded."""
    by_sec: dict[str, list[dict]] = {}
    for r in eff["rules"]:
        by_sec.setdefault(r["sec"], []).append(r)
    said = []
    for sec in sorted(by_sec, key=_sec_key):
        holds = [f"layer {r['layer']} {'overrides' if r['verb'] == 'override' else 'adds'}"
                 for r in by_sec[sec] if r["superseded_by"] is None]
        gone = [f"layer {r['layer']}'s {r['verb']} by {superseder(r)}" for r in by_sec[sec] if r["superseded_by"]]
        said.append(f"§{sec}: " + (", ".join(holds) if holds else "nothing holds")
                    + (f" (superseded: {', '.join(gone)})" if gone else ""))
    if len(said) > HOOK_SECTIONS:
        said[HOOK_SECTIONS:] = [f"{len(said) - HOOK_SECTIONS} more §s (--effective lists them)"]
    if eff["unkeyed"]:
        n = len(eff["unkeyed"])
        said.append(f"{n} unkeyed rule{'s' if n > 1 else ''} beside cadence.md")
    return said


def hook() -> int:
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        print(f"cadence layers: not read — {e} (cadence.md §9.18); this session runs without them")
        return 0
    if not layers:
        return 0
    n = len(layers)
    print(f"The person's own cadence rules: {n} layer{'s' if n > 1 else ''} named by this machine's "
          f"cadence.toml (cadence.md §9.18, TD-126). Precedence: this repo's CLAUDE.md / AGENTS.md first, "
          f"then these layers (a later one wins over an earlier one), then cadence.md. A layer is prose: it "
          f"cannot replace a shared script or turn off a gate.")
    seen = []
    for i, entry in enumerate(layers, 1):
        try:
            r = read(entry)
        except Exception as e:  # a detector never fails the session start (cadence §7)
            print(f"--- layer {i} of {n}: {entry['path']} — not read: {type(e).__name__}: {e}; this session runs without it")
            continue
        if r["text"] is None:
            print(f"--- layer {i} of {n}: {where(r)} — not read: {r['error']}; this session runs without it")
            continue
        text = r["text"]
        cut = len(text.encode("utf-8", errors="replace")) > MAX_BYTES
        if cut:
            text = text.encode("utf-8", errors="replace")[:MAX_BYTES].decode("utf-8", errors="ignore")
        print(f"--- layer {i} of {n}: {where(r)}")
        if r["origin"]:
            print(f"--- layer {i}: {r['origin']}")
        print(text.rstrip("\n"))
        if cut:
            print(f"--- layer {i} cut at {MAX_BYTES // 1024} KiB: read the rest from the file itself")
        print(f"--- end of layer {i}")
        seen.append((i, text))
    try:
        eff = effective(seen)
        said = "; ".join(summary(eff)) if eff["rules"] or eff["problems"] else ""
    except Exception as e:  # the rules above were printed whole; only the by-§ view is lost
        print(f"--- the layers' rules by §: not worked out ({type(e).__name__}: {e})")
        return 0
    if said:
        print("--- the layers' rules by § (cadence_layer.py --effective shows each): " + said)
        for p in eff["problems"][:HOOK_WARNINGS]:
            print(f"--- warning: {p}")
        if len(eff["problems"]) > HOOK_WARNINGS:
            print(f"--- and {len(eff['problems']) - HOOK_WARNINGS} more warnings: cadence_layer.py --effective lists them")
    return 0


def listing_json() -> int:
    """--json (TD-132): for a tool that keeps a directory of its own in a layer repo (shiftlead's
    `shiftlead/`), each layer in order as --hook reads it, never fetched: {path (as the setting
    writes it), file (expanded), root (its clone's top, null when not in one), kind (own |
    followed), ref (a followed layer's pin, else null), commit (the one it is read at), note (one's
    own read from a file not committed, or not in a clone, or with edits), error}.
    {"layers": []} when none is set; {"error": why} and exit 2 when the setting cannot be read."""
    import json
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 2
    out = []
    for entry in layers:
        r = read(entry, fetch=False)
        file = os.path.expanduser(entry["path"])
        d = os.path.dirname(file)
        rc, top = git(d, "rev-parse", "--show-toplevel") if os.path.isdir(d) else (1, "")
        out.append({"path": entry["path"], "file": file, "root": top.strip() if rc == 0 and top.strip() else None,
                    "kind": "followed" if entry.get("ref") else "own", "ref": entry.get("ref"),
                    "commit": r["commit"], "note": r["note"] or None, "error": r["error"]})
    print(json.dumps({"layers": out}, indent=2, ensure_ascii=False))
    return 1 if any(x["error"] for x in out) else 0


def listing() -> int:
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        print(f"cadence_layer: {e}", file=sys.stderr)
        return 2
    if not layers:
        print(f"no layers set (the layers key in {cadence_config.machine_path()}, cadence.md §9.18)")
        return 0
    rc = 0
    for i, entry in enumerate(layers, 1):
        r = read(entry)
        state = f"not read: {r['error']}" if r["text"] is None else "read"
        rc = rc or (1 if r["text"] is None else 0)
        print(f"{i}. {where(r)} — {state}" + (f"; {r['origin']}" if r["origin"] else ""))
    return rc


EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
# a home directory named in full: /home/<user>, /Users/<user>, C:\Users\<user>, /root
MACHINE_PATH_RE = re.compile(r"(?:(?<![\w.~/-])(?:/home/|/Users/|/mnt/[a-z]/Users/)|(?<![\w])[A-Za-z]:(?:\\{1,2}|/)Users(?:\\{1,2}|/))"
                             r"[^/\\\s`'\")]+|(?<![\w/])/root(?![\w-])")
# Not findings (TD-090): what a fixture or an example writes, so a test or a doc can show the shape —
# an address at a domain reserved for examples (RFC 2606/6761), a home directory with a stand-in name,
# and the tool's own name, which a public tree is about
RESERVED_EMAIL_RE = re.compile(r"@(?:[\w-]+\.)*(?:example\.(?:com|org|net)|example|test|invalid|localhost)$", re.I)
PLACEHOLDER_HOME_RE = re.compile(r"(?:/home/|/Users/|[\\/]Users[\\/]+)(?:someone|user|username|you|me|name|alice|bob|example"
                                 r"|\$\w+|\$\{\w+\}|<[^>]*>)$", re.I)
TOOL_NAMES = {"dev-cadence", "agent-cadence"}


def publish_targets(files: list[str]) -> tuple[list[str], list[str]]:
    """(files to scan, notes). Named files as given; else every tracked file of each own layer's repo."""
    if files:
        return [f for f in files], []
    notes, out = [], []
    for entry in setting():
        if entry.get("ref"):
            continue   # someone else's layer: theirs to publish
        path = os.path.expanduser(entry["path"])
        d = os.path.dirname(path)
        rc, top = git(d, "rev-parse", "--show-toplevel") if os.path.isdir(d) else (1, "")
        if rc != 0:
            notes.append(f"{entry['path']}: not in a git clone — only the file itself is checked")
            out.append(path)
            continue
        top = top.strip()
        rc, listed = git(top, "ls-files", "-z")
        if rc != 0:
            notes.append(f"{top}: git ls-files failed — only the layer file itself is checked, so this is no clean bill")
        out += [os.path.join(top, f) for f in listed.split("\0") if f]
        out.append(path)   # an untracked layer file still goes public the moment it is added
    return list(dict.fromkeys(os.path.realpath(f) for f in out)), notes


def read_accept(path: str) -> list[list]:
    """--accept's lines: `<path-glob> <finding-glob>[ :: <line-glob>]` (fnmatch, `#` to the end of a
    line is a comment, as is `#` after a blank). The third field is matched against the flagged line's own text, so one
    accepted use of a name does not accept every line of the file that holds it. Each rule is
    [line number, path glob, finding glob, line glob or None, times used]. Raises OSError."""
    rules = []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            # a comment is `#` at the line's start or after a blank, so `*#*` in a glob stays a glob
            # and cutting one can never widen a rule
            line = re.split(r"(?:^|\s)#", line.rstrip("\n"), maxsplit=1)[0].strip()
            if not line:
                continue
            path_glob, _, rest = line.partition(" ")
            what_glob, sep, text_glob = rest.partition(" :: ")
            if not sep and (rest.endswith(" ::") or rest == "::"):
                sep = " :: "
            if sep and not text_glob.strip():
                raise ValueError(f"line {n}: ` :: ` with no line glob after it")
            rules.append([n, path_glob, what_glob.strip() or "*", text_glob.strip() if sep else None, 0])
    return rules


def _parents(d: str) -> list[str]:
    out = []
    while True:
        up = os.path.dirname(d)
        if up == d:
            return out
        out.append(up)
        d = up


CODE_SPAN_RE = re.compile(r"(`+)(?!`).*?(?<!`)\1(?!`)")
DEAD_LINK_RE = re.compile(r"\]\((?!https?:|mailto:|#|/)([^)\s#]+)")


def publish_check(files: list[str], accept: str | None = None) -> int:
    try:
        targets, notes = publish_targets(files)
        repo = cadence_config.repo_root(os.getcwd())
        gate_key, _ = cadence_config.resolve("publish-gate", cadence_config.sources(repo))
    except cadence_config.ConfigError as e:
        print(f"cadence_layer: {e}", file=sys.stderr)
        return 2
    rules = None
    if accept is not None:
        try:
            rules = read_accept(accept)
        except (OSError, UnicodeError, ValueError) as e:
            print(f"cadence_layer: the accept list {accept} cannot be read ({getattr(e, 'strerror', None) or e})", file=sys.stderr)
            return 2
    for n in notes:
        print(f"note: {n}")
    if not targets:
        print("cadence_layer: nothing to check — no layer of your own is set, and no file was named", file=sys.stderr)
        return 2
    names: dict[str, str] = {}
    try:
        from nudge_user_attention import read_registry
        for repo_ in read_registry() or []:
            if len(repo_.name) >= 3 and repo_.name.lower() not in TOOL_NAMES:
                names[repo_.name] = "a repo on this machine's roster"
    except ImportError:
        print("note: the roster was not read (nudge_user_attention.py is not beside this script)")
    try:
        listed, _ = cadence_config.resolve("publish-names", cadence_config.sources(None))
    except cadence_config.ConfigError as e:
        print(f"cadence_layer: {e}", file=sys.stderr)
        return 2
    if gate_key == "required" and rules is not None and not listed:
        print(f"cadence_layer: this repo's docs/cadence.toml sets publish-gate = \"required\", and this machine "
              f"has no publish-names ({cadence_config.machine_path()}) — the gate cannot run here: it would "
              f"pass every name the list would flag (TD-189)", file=sys.stderr)
        return 2
    for n in listed or []:
        if n.lower() in TOOL_NAMES:
            print(f"note: publish-names lists {n}, the tool's own name — not flagged")
        else:
            names.setdefault(n, "a name your publish-names lists")
    host = socket.gethostname().split(".")[0]
    if len(host) >= 3:
        names[host] = "this machine's name"
    short = host.split("-")[0]
    if len(short) >= 3 and short != host:
        names.setdefault(short, "this machine's short name")
    home = os.path.expanduser("~")
    word = {n: re.compile(rf"(?<![\w-]){re.escape(n)}(?![\w-])", re.IGNORECASE) for n in names}
    found = read = 0
    findings: list[tuple[str, int, str, str]] = []   # (path, line, what, the line's text)
    # a link resolves when it names a file being checked (or a directory holding one): a gate judges
    # the files it was handed (the index, the snapshot), never whatever else is on disk
    named = {os.path.normpath(os.path.abspath(t)) for t in targets}
    named_dirs = {os.path.dirname(t) for t in named}
    named_dirs |= {d for t in named_dirs for d in _parents(t)}
    for f in targets:
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().splitlines()
        except (OSError, UnicodeError) as e:   # never a silent skip: an unread file is not a clean one
            print(f"note: {f}: not read ({getattr(e, 'strerror', None) or e}) — not checked")
            continue
        read += 1
        for i, line in enumerate(lines, 1):
            hits = [f"an email address ({m})" for m in EMAIL_RE.findall(line) if not RESERVED_EMAIL_RE.search(m)]
            # a stand-in name is no finding, except where it is this machine's own home (HOME=/home/user)
            paths = [m for m in MACHINE_PATH_RE.findall(line) if m == home or not PLACEHOLDER_HOME_RE.search(m)]
            hits += [f"a machine path ({m})" for m in paths]
            if home not in ("/", "") and home in line and home not in paths:
                hits.append(f"this machine's home directory ({home})")
            hits += [f"{why} ({n})" for n, why in names.items() if word[n].search(line)]
            if rules is not None and f.endswith(".md"):   # the gate: a link into what is not there goes dead
                base = os.path.dirname(f)
                for t in DEAD_LINK_RE.findall(CODE_SPAN_RE.sub("", line)):   # `](path)` in a code span is an example
                    at = os.path.normpath(os.path.abspath(os.path.join(base, t)))
                    if at not in named and at not in named_dirs:
                        hits.append(f"a link to a file the tree lacks ({t})")
            findings += [(f, i, h, line) for h in hits]
            found += len(hits)
    accepted = 0
    cwd = os.getcwd()
    for f, i, h, line in findings:
        # an accept glob is a path from where the check runs (the repo root, in a precheck)
        rel = os.path.relpath(f, cwd) if os.path.isabs(f) and os.path.abspath(f).startswith(cwd + os.sep) else f
        for r in rules or []:
            if fnmatch.fnmatchcase(rel, r[1]) and fnmatch.fnmatchcase(h, r[2]) and (r[3] is None or fnmatch.fnmatchcase(line, r[3])):
                r[4] += 1
                accepted += 1
                break
        else:
            print(f"{f}:{i}: {h}")
    print(f"{found} line{'s' if found != 1 else ''} to look at in {read} file{'s' if read != 1 else ''}"
          + (f" ({len(targets) - read} not read)" if read < len(targets) else "")
          + (" — each is yours to judge: scrub it, or keep it if it is meant to be public" if found - accepted else "")
          + " — the current tree only: git history goes public too, and is not read")
    partial = read < len(targets) or any("no clean bill" in n for n in notes)
    if rules is None:
        return 1 if found else (2 if partial else 0)
    for n, p, w, t, used in rules:
        if not used:
            print(f"note: accept line {n} ({p} {w}{' :: ' + t if t is not None else ''}) matched nothing — drop it if it is stale")
    left = found - accepted
    print(f"gate: {left} finding{'s' if left != 1 else ''} to judge, {accepted} accepted"
          + ("" if left else " — clean" if not partial else " — but not every file was read"))
    return 1 if left else (2 if partial else 0)


def show_effective() -> int:
    """*Show effective*, as `git config --show-origin` does: each keyed rule by §, with the layer and
    line it came from (each layer listed first with its commit) and whether it holds or what
    superseded it; then the unkeyed rules."""
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        print(f"cadence_layer: {e}", file=sys.stderr)
        return 2
    if not layers:
        print(f"no layers set (the layers key in {cadence_config.machine_path()}, cadence.md §9.18)")
        return 0
    return effective_view([read(entry, fetch=False) for entry in layers])


def effective_view(read_layers: list[dict]) -> int:
    """--effective's print of layers already read (read()'s dicts, in order); 1 on a layer not read
    or a warning. --follow shows the setting as it would be with the new layer through it."""
    seen, unread = [], 0
    for i, r in enumerate(read_layers, 1):
        if r["text"] is None:
            unread += 1
            print(f"layer {i}: {where(r)} — not read: {r['error']}")
            continue
        print(f"layer {i}: {where(r)}")
        seen.append((i, r["text"]))
    eff = effective(seen)
    by_sec: dict[str, list[dict]] = {}
    for r in eff["rules"]:
        by_sec.setdefault(r["sec"], []).append(r)
    for sec in sorted(by_sec, key=_sec_key):
        print(f"§{sec}")
        for r in by_sec[sec]:
            state = f"superseded by {superseder(r)}" if r["superseded_by"] else "holds"
            print(f"  layer {r['layer']} line {r['line']} {r['verb']}: {r['text']} — {state}")
    if eff["unkeyed"]:
        where_ = ", ".join(f"layer {i} line {n}" for i, n in eff["unkeyed"])
        print(f"unkeyed ({len(eff['unkeyed'])}): {where_} — they hold beside cadence.md, but no tool can say what they change")
    if not eff["rules"] and not eff["unkeyed"] and seen:
        print("no rules in the layers read")
    for p in eff["problems"]:
        print(f"warning: {p}")
    return 1 if unread or eff["problems"] else 0


# --- following someone else's layer (TD-130) ------------------------------------------------
# Following is five steps that can each go wrong unnoticed until a session starts: clone, pick a
# tag or commit, read the file at it, add a [[layers]] table *before* one's own, and later fetch,
# diff and move the pin. --follow and --update run them with the checks, after the person has
# decided to follow and read the text. They are the one exception to §9.18's *tools only read the
# settings files*: each edit is a text insert or one line's value, never a parse-and-rewrite, so
# every comment stays; the file is read back through cadence_config and put back when the result
# does not hold what was meant.
DEFAULT_FILE = "cadence-personal.md"
USAGE = ("usage: cadence_layer.py [--hook | --json | --effective | --publish-check [--accept FILE] [FILE…] |\n"
         "       --follow <url-or-clone> --ref <tag|commit> [--file <path in repo>] [--dir <clone dir>] |\n"
         "       --update <n> [--ref <tag|commit>]]")
NET_TIMEOUT = 300
LAYERS_HEADER_RE = re.compile(r"^[ \t]*\[\[[ \t]*layers[ \t]*\]\][ \t]*(?:#[^\r\n]*)?\r?$")
TABLE_HEADER_RE = re.compile(r"^[ \t]*\[")
REF_LINE_RE = re.compile(r"""^([ \t]*ref[ \t]*=[ \t]*)("(?:[^"\\\n]|\\.)*"|'[^'\n]*')(.*)$""")
SAFE_REF_RE = re.compile(r"^[^\s\"'\\\x00-\x1f\x7f-][^\s\"'\\\x00-\x1f\x7f]*$")


class Refused(Exception):
    """A check failed: the message is the reason, printed as is."""


def _toml_str(s: str) -> str:
    if any(ord(c) < 0x20 or ord(c) == 0x7f for c in s):
        raise Refused(f"{s!r} holds a control character: write it by hand")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _net(args: list[str], cwd: str | None = None) -> tuple[int, str]:
    """A clone or fetch: no prompt (an agent may be running this), bounded, its error kept."""
    env = {**GIT_ENV, "GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=10"}
    cmd = ["git", *(["-C", cwd] if cwd else []), *args]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=NET_TIMEOUT, check=False, env=env, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        return 1, str(e)
    err = [ln for ln in p.stderr.strip().splitlines() if ln.strip()]
    return p.returncode, err[-1] if err else ""


def _shown(path: str) -> str:
    """The setting's spelling of an absolute path: ~/ when it is under the home directory."""
    home = os.path.expanduser("~").rstrip("/")
    return "~/" + path[len(home) + 1:] if path.startswith(home + "/") else path


def check_ref(d: str, ref: str, file: str) -> str:
    """The checks a pin passes before it is written; returns the commit (short). Raises Refused."""
    if not SAFE_REF_RE.match(ref):
        raise Refused(f"ref {ref!r} is not a tag name or commit this tool writes (no spaces, quotes, backslashes or leading -)")
    moving = [r.strip() for r in git(d, "for-each-ref", "--format=%(refname)", f"refs/heads/{ref}",
                                     f"refs/remotes/*/{ref}", f"refs/remotes/{ref}")[1].splitlines() if r.strip()]
    rc, sha = git(d, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if rc != 0 and moving:
        sha = git(d, "rev-parse", f"{moving[0]}^{{commit}}")[1]
    elif rc != 0:
        raise Refused(f"ref {ref} does not resolve to a commit in {_shown(d)} (fetched its tags; is it pushed?)")
    full = sha.strip()
    is_tag = git(d, "show-ref", "--verify", "--quiet", f"refs/tags/{ref}")[0] == 0
    is_commit = bool(re.fullmatch(r"[0-9a-fA-F]{7,64}", ref)) and full.startswith(ref.lower())
    if moving and is_tag:
        raise Refused(f"ref {ref} names a tag and also {', '.join(moving)}: ambiguous — pin the tag's commit ({full[:12]})")
    if not (is_tag or is_commit):
        what = f"a branch ({', '.join(moving)})" if moving else "neither a tag nor a commit"
        raise Refused(f"ref {ref} is {what}: a pin must not move under you — pin a tag or a commit ({full[:12]})")
    rc, prefix = git(d, "rev-parse", "--show-prefix")
    rc2, kind = git(d, "cat-file", "-t", f"{full}:{prefix.strip()}{file}")
    if rc or rc2 or kind.strip() != "blob":
        raise Refused(f"no file {file} at {ref} in {_shown(d)}")
    return full[:12]


def _write_checked(path: str, before: bytes | None, after: str, want: dict, said: str) -> str | None:
    """Write `after` to the settings file, read it back through cadence_config, and put `before`
    back (or remove the file it created) unless the whole table reads as `want` and the layers
    setting is valid — so an insert that landed inside a multi-line string, say, never stays.
    None when it holds; else why (`said`: what it was meant to read as)."""
    path = os.path.realpath(path)   # a dotfiles-symlinked file is written through its link, never replaced
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(after)
    if before is not None:
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
    try:
        setting()
        why = None if cadence_config.load(path) == want else f"the file would not read as {said}"
    except cadence_config.ConfigError as e:
        why = f"the file would not read: {e}"
    if why:
        if before is None:
            os.remove(path)
        else:
            with open(path, "wb") as f:
                f.write(before)
        return why
    return None


def _headers(text: str) -> list[int]:
    return [i for i, ln in enumerate(text.splitlines(keepends=True)) if LAYERS_HEADER_RE.match(ln)]


def follow(source: str, ref: str, file: str | None, clone_dir: str | None) -> int:
    file = file or DEFAULT_FILE
    if os.path.isabs(file) or ".." in file.split("/"):
        raise Refused(f"--file is a path inside the layer's repo, not {file!r}")
    src = os.path.expanduser(source)
    if os.path.isdir(src) and git(src, "rev-parse", "--is-inside-work-tree")[1].strip() == "true":
        if clone_dir:
            raise Refused("--dir names where to clone a URL; this is already a clone")
        d = git(src, "rev-parse", "--show-toplevel")[1].strip()
        if git(d, "remote")[1].strip():
            rc, err = _net(["fetch", "-q", "--tags"], d)
            print(f"fetched {_shown(d)}'s tags" if rc == 0 else f"warning: fetching {_shown(d)}'s tags failed ({err}): checking what the clone has")
        else:
            print(f"{_shown(d)} has no remote: checking what the clone has")
    else:
        name = re.sub(r"\.git$", "", re.split(r"[/:]", source.rstrip("/"))[-1])
        if not clone_dir and not name:
            raise Refused(f"cannot name a clone directory from {source!r}: give --dir")
        d = os.path.abspath(os.path.expanduser(clone_dir or os.path.join("~", "src", name)))
        if os.path.lexists(d):
            if not (os.path.isdir(d) and git(d, "rev-parse", "--show-toplevel")[1].strip() == os.path.realpath(d)):
                raise Refused(f"{_shown(d)} exists and is not a clone's top: give another --dir")
            url = git(d, "remote", "get-url", "origin")[1].strip()
            if url != source:
                raise Refused(f"{_shown(d)} is a clone of {url or 'nothing (no origin)'}, not {source}: give another --dir")
            rc, err = _net(["fetch", "-q", "--tags", "origin"], d)
            print(f"reusing {_shown(d)}; fetched its tags" if rc == 0 else f"warning: fetching {_shown(d)}'s tags failed ({err}): checking what the clone has")
        else:
            rc, err = _net(["clone", "-q", "--", source, d])
            if rc != 0:
                raise Refused(f"cloning {source} failed: {err}")
            print(f"cloned {source} into {_shown(d)}")
    commit = check_ref(d, ref, file)
    path = os.path.join(d, file)
    shown = _shown(path)
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        raise Refused(f"the setting cannot be read: {e}") from None
    for i, e in enumerate(layers, 1):
        if os.path.realpath(os.path.expanduser(e["path"])) == os.path.realpath(path):
            raise Refused(f"layer {i} already names {e['path']}" + (f" (at {e['ref']})" if e.get("ref") else " (your own)")
                          + (": move its pin with --update" if e.get("ref") else ""))
    own = [i for i, e in enumerate(layers) if not e.get("ref")]
    pos = own[0] if own else len(layers)
    new = {"path": shown, "ref": ref}
    r = read(new, fetch=False)
    print(f"--- {file} at {ref} ({commit}): the text that will steer your sessions")
    print((r["text"] or "").rstrip("\n"))
    print(f"--- end of {file}")
    print("--- with it, --effective would say:")
    rs = [read(e, fetch=False) for e in layers]
    rs.insert(pos, r)
    effective_view(rs)
    block = f"[[layers]]\npath = {_toml_str(shown)}\nref = {_toml_str(ref)}\n"
    cfg = cadence_config.machine_path()
    before = open(cfg, "rb").read() if os.path.isfile(cfg) else None
    text = before.decode("utf-8") if before is not None else ""
    lines = text.splitlines(keepends=True)
    heads = _headers(text)
    if layers and len(heads) != len(layers):
        raise Refused(f"{cfg} writes its layers in a form this tool does not edit (not one [[layers]] table each): "
                      f"add this {'before your own' if own else 'after the others'} by hand —\n{block}")
    if own:
        at = heads[pos]
        while at > 0 and lines[at - 1].lstrip().startswith("#"):   # the comment over one's own stays with it
            at -= 1
        after = "".join(lines[:at]) + block + "\n" + "".join(lines[at:])
        where_ = f"before your own layer ({layers[pos]['path']})"
    else:
        sep = "" if not text else ("\n" if text.endswith("\n") else "\n\n")
        after = text + sep + block
        where_ = "at the end"
    table = cadence_config.load(cfg) or {}
    want = {**table, "layers": [*table.get("layers", [])[:pos], new, *table.get("layers", [])[pos:]]}
    why = _write_checked(cfg, before, after, want, f"the same settings with the new layer at {pos + 1}")
    if why:
        raise Refused(f"{cfg} not changed — {why}; add this by hand —\n{block}")
    print(f"added to {cfg} as layer {pos + 1}, {where_}:\n{block.rstrip()}")
    print(f"the next session start reads it at {ref}; move the pin with: cadence_layer.py --update {pos + 1}")
    return 0


def update(n_arg: str, ref: str | None) -> int:
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        raise Refused(f"the setting cannot be read: {e}") from None
    if not n_arg.isdigit() or not 1 <= int(n_arg) <= len(layers):
        raise Refused(f"--update takes a layer's number, 1 to {len(layers)} (cadence_layer.py lists them), not {n_arg!r}")
    n = int(n_arg)
    entry = layers[n - 1]
    old = entry.get("ref")
    if not old:
        raise Refused(f"layer {n} ({entry['path']}) is your own, read from its working tree: there is no pin to move")
    path = os.path.expanduser(entry["path"])
    d, file = os.path.dirname(path), os.path.basename(path)
    if not (os.path.isdir(d) and git(d, "rev-parse", "--is-inside-work-tree")[1].strip() == "true"):
        raise Refused(f"layer {n}'s directory {_shown(d)} is not a git clone")
    rc, err = _net(["fetch", "-q", "--tags"], d)
    print(f"fetched {_shown(d)}'s tags" if rc == 0 else f"warning: fetching {_shown(d)}'s tags failed ({err}): using what the clone has")
    rc, old_sha = git(d, "rev-parse", "--verify", "--quiet", f"{old}^{{commit}}")
    old_sha = old_sha.strip() if rc == 0 else ""
    if ref is None:
        if not old_sha:
            print(f"the pin {old} is not in the clone: nothing to compare with")
            return 1
        newer = [t for t in git(d, "tag", "--contains", old_sha, "--sort=-creatordate")[1].split()
                 if git(d, "rev-parse", f"{t}^{{commit}}")[1].strip() != old_sha]
        if not newer:
            print(f"layer {n} is pinned at {old}: no newer tag")
            return 0
        print(f"layer {n} is pinned at {old}; newer tags: {', '.join(newer)}")
        print(f"read one with: cadence_layer.py --update {n} --ref <tag>")
        return 0
    commit = check_ref(d, ref, file)
    if old_sha and git(d, "merge-base", "--is-ancestor", old_sha, f"{ref}^{{commit}}")[0] != 0:
        print(f"warning: {ref} does not descend from {old}: the layer's history was rewritten or this is another line — read the whole file, not just the diff")
    prefix = git(d, "rev-parse", "--show-prefix")[1].strip()
    if old_sha:
        diff = git(d, "diff", old_sha, f"{ref}^{{commit}}", "--", f":(top){prefix}{file}")[1]
        print(f"--- git diff {old} {ref} -- {prefix}{file}")
        print(diff.rstrip("\n") or "(no change to the file)")
        print("--- end of the diff")
    cfg = cadence_config.machine_path()
    before = open(cfg, "rb").read()
    text = before.decode("utf-8")
    lines = text.splitlines(keepends=True)
    heads = _headers(text)
    if len(heads) != len(layers):
        raise Refused(f"{cfg} writes its layers in a form this tool does not edit: move layer {n}'s ref to {ref!r} by hand")
    at = None
    for i in range(heads[n - 1] + 1, len(lines)):
        if TABLE_HEADER_RE.match(lines[i]):
            break
        if REF_LINE_RE.match(lines[i].rstrip("\r\n")):
            at = i
            break
    if at is None:
        raise Refused(f"{cfg}: layer {n}'s ref is not on a line of its own: move it to {ref!r} by hand")
    m = REF_LINE_RE.match(lines[at].rstrip("\r\n"))
    nl = lines[at][len(lines[at].rstrip("\r\n")):]
    lines[at] = m.group(1) + _toml_str(ref) + m.group(3) + nl
    table = cadence_config.load(cfg)
    want = {**table, "layers": [dict(e, ref=ref) if i == n - 1 else e for i, e in enumerate(table["layers"])]}
    why = _write_checked(cfg, before, "".join(lines), want, f"the same settings with layer {n} at {ref}")
    if why:
        raise Refused(f"{cfg} not changed — {why}")
    print(f"layer {n}: ref {old} -> {ref} ({commit}) in {cfg}")
    return 0

def report() -> dict:
    """For /cadence (check_cadence.py, TD-126 (4b)): the layers this machine's sessions start
    under, read as --effective reads them (never fetched), in one bounded run. {"layers": [{n,
    shown, kind, commit, error}], "by_section": the hook's clauses, "warnings": n}; {"layers": []}
    when none is set; {"error": why} when the setting cannot be read."""
    global _deadline
    _deadline = time.monotonic() + RUN_BUDGET
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        return {"error": str(e)}
    out, seen = [], []
    for i, entry in enumerate(layers, 1):
        r = read(entry, fetch=False)
        out.append({"n": i, "shown": r["shown"], "kind": r["kind"], "commit": r["commit"], "error": r["error"]})
        if r["text"] is not None:
            seen.append((i, r["text"]))
    eff = effective(seen) if layers else {"rules": [], "unkeyed": [], "problems": []}
    return {"layers": out, "by_section": summary(eff), "warnings": len(eff["problems"])}


def attention(fetch: bool = False) -> list[str]:
    """For the attention report (nudge_user_attention.py --report, TD-126 (3)): one line per own
    layer whose file holds edits no other machine has (uncommitted, never committed) or whose
    clone holds unpushed commits,
    has no upstream, is behind, or cannot be read. [] when every own layer is level, or none is set.
    The layers are read from the setting, never the roster: the roster lists cadence repos."""
    global _deadline
    _deadline = time.monotonic() + RUN_BUDGET
    try:
        layers = setting()
    except cadence_config.ConfigError as e:
        return [f"⚠ not read — {e} (cadence.md §9.18)"]
    out = []
    for i, entry in enumerate(layers, 1):
        if entry.get("ref"):
            continue   # someone else's, read at its pin: nothing of the person's can strand there
        r = read(entry, fetch=fetch)
        said = [x for x in (f"not read: {r['error']}" if r["error"] else "", r["origin"]) if x]
        if said or r["note"]:
            out.append(f"• layer {i}: {where(r)}" + (f" — {'; '.join(said)}" if said else ""))
    return out


def report_line(rep: dict) -> str:
    """report() as one line, or "" when no layer is set."""
    if "error" in rep:
        return f"layers: not read — {rep['error']} (cadence.md §9.18)"
    if not rep["layers"]:
        return ""
    n = len(rep["layers"])
    each = "; ".join(f"{x['n']}. {x['shown']}" + (f" @ {x['commit']}" if x["commit"] else "") + f" ({x['kind']})"
                     + (f" — not read: {x['error']}" if x["error"] else "") for x in rep["layers"])
    tail = f" — {'; '.join(rep['by_section'])}" if rep["by_section"] else ""
    warn = f" — {rep['warnings']} warning{'s' if rep['warnings'] > 1 else ''}" if rep["warnings"] else ""
    return (f"layers: {n} active on this machine (cadence.md §9.18; the session's rules beside cadence.md): "
            f"{each}{tail}{warn} — cadence_layer.py --effective shows each")


def main(argv: list[str]) -> int:
    global _deadline
    _deadline = time.monotonic() + RUN_BUDGET
    if argv and argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv == ["--hook"]:
        return hook()
    if argv == ["--effective"]:
        return show_effective()
    if argv == ["--json"]:
        return listing_json()
    if argv[:1] in (["--publish-check"], ["--follow"], ["--update"]):
        global GIT_TIMEOUT
        _deadline = time.monotonic() + 3600   # run by hand, never at session start: no 8 s budget
        GIT_TIMEOUT = 120
    if argv[:1] == ["--publish-check"]:
        rest = argv[1:]
        if rest[:1] == ["--accept"]:
            if len(rest) < 2:
                print(USAGE, file=sys.stderr)
                return 2
            return publish_check(rest[2:], accept=rest[1])
        return publish_check(rest)
    if argv[:1] in (["--follow"], ["--update"]):
        opts, rest = {}, argv[2:]
        while len(rest) >= 2 and rest[0] in ("--ref", "--file", "--dir") and rest[0] not in opts:
            opts[rest[0]], rest = rest[1], rest[2:]
        allowed = ("--ref", "--file", "--dir") if argv[0] == "--follow" else ("--ref",)
        if len(argv) < 2 or rest or set(opts) - set(allowed) or (argv[0] == "--follow" and "--ref" not in opts):
            print(USAGE, file=sys.stderr)
            return 2
        try:
            if argv[0] == "--follow":
                return follow(argv[1], opts["--ref"], opts.get("--file"), opts.get("--dir"))
            return update(argv[1], opts.get("--ref"))
        except Refused as e:
            print(f"cadence_layer: refused — {e}", file=sys.stderr)
            return 1
    if argv:
        print(USAGE, file=sys.stderr)
        return 2
    return listing()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
