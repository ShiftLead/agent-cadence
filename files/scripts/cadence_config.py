#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/cadence_config.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""The cadence's settings: the one reader every tool, skill and script goes through (TD-096).

    cadence_config.py get <key>     print the value; exit 1 when it is unset and has no default
    cadence_config.py get review-model --first
                                    the first model of the review-model list: round one's reviewer (TD-203)
    cadence_config.py               every known key, its value and where the value came from
    cadence_config.py --json        the same as JSON: {key: {"value": …, "from": …}}
    cadence_config.py --check       name each key no tool reads and each value of the wrong type
                                    in the files below; exit 1 when there is one (the repo's [agent-cadence]
                                    pin, TD-129, is checked with the launcher's rules)

    cadence_config.py opt-outs --repo DIR
                                    the repo's opt-outs (`agent-cadence adopt`'s reader, cadence.md Adoption
                                    checklist step 9): one TSV line per declaration,
                                    kind, value, adr, source, as-written — split by \\x1f (not
                                    a tab: bash's read would merge an empty field) — and
                                    warn\\x1f<message> for what cannot be read — always exit 0
                                    for a readable DIR, so the payload ships whole

    --repo DIR  read DIR's settings instead of the current directory's repo

Where a value comes from, the first that has it (cadence.md §9.18):
    env      CADENCE_<KEY>, the key upper-cased with `-` as `_` (CADENCE_REVIEW_MODEL);
             an empty or all-blank value counts as unset
    repo     docs/cadence.toml at the repo root (SEED: the repo owns it, sync never rewrites it)
    machine  cadence.toml in the roster's directory — $AGENT_CADENCE_REG_DIR, else
             ${XDG_CONFIG_HOME:-~/.config}/agent-cadence (§9.2), so a test's override moves it too
    default  KEYS below
A repo key (REPO_KEYS below: precheck, ledger-ids-host, publish-gate) has the repo row only — no env, no machine file, no
default: it is a decision about that one repo; so are its tables — the opt-outs, the pin and
[precheck-paths] (TD-155, read by precheck_paths()). A machine key (MACHINE_KEYS below: layers) has the
machine row only — no env, no repo file, no default: it belongs to the person, and follows them
from repo to repo rather than travelling with any one (TD-126).

The files are TOML, read with `tomllib` (Python >= 3.11). **People write them; tools only
read them and never rewrite them** (cadence.md §9.18): a whole-file write drops the comments,
which are where a setting says why. Machine-written state goes to files the tools own (the
sync lock, the roster). On an older Python, a missing file is no problem, nor is one holding
only comments and blank lines (the SEED as synced); one with a setting in it is an error naming
the version — never a silent default standing in for what was written. Every file is read
before any key resolves, so an env value does not get past a file that cannot be read: fix
the file (or move it aside) rather than override around it.

Exit codes: 0 read; 1 `get` of an unset key with no default, or `--check` found something;
2 a file could not be read (bad TOML, Python too old, not a file) or an unknown key was asked
for — the message names the file or the key. Stdlib only.

Parity (cadence.md §7.9): KEYS is the reader's side; the seed `docs/cadence.toml` and §9.18
write the same keys and defaults — tests/test_cadence_config.sh holds them together.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

REPO_FILE = "docs/cadence.toml"
MACHINE_NAME = "cadence.toml"

# key -> (default, what it is). A key lands here with the first thing that reads it.
KEYS = {
    "review-model": ("sonnet", "the independent reviewers' models (§4.8), in round order, comma-separated: a cheaper model than the author's first, never the author's own (TD-203)"),
    # No default of its own: unset, it is the first review-model (resolve() says so in its source).
    "fact-check-model": (None, "the fact-checker's model, or <adapter>/<model> (§4.8, TD-203); unset, the first review-model"),
    "sweep-model": ("sonnet", "the model the deep sweep's agents run on (/stranded-work deep)"),
    "agents": ("claude", "the agent tools whose sessions the safety nets must see, comma-separated (TD-100); without claude, the memory guard skips its Claude checks (TD-095)"),
    "forge": ("auto", "where the PRs live: auto (from origin's host), github, gitlab or none (TD-103)"),
    "worktree-root": (".claude/worktrees", "where open_worktree.sh puts worktrees, a path relative to the clone root (TD-101)"),
    # The attention report's thresholds (TD-134): today's values are the defaults; a whole number
    # of days (or items), written as a TOML integer or a string.
    "sweep-every": ("10", "days after the last sweep before the attention report warns it is stale (§3.10)"),
    "deep-sweep-every": ("30", "days after the last deep sweep before the report asks for one (§3.10)"),
    "pr-stale-days": ("2", "days an open PR may sit before the SessionStart line names it (§3.9)"),
    "escalate-overdue-days": ("14", "days overdue before a board item is ledger material (§3.3)"),
    "board-size-warn": ("15", "open items on a board before the report warns it is too big (§3.3)"),
    "attention-scope": ("own", "the SessionStart attention line: own (this repo's items, a count of the rest) or machine (every repo's) (§3.9, TD-146)"),
    # The design review rounds' caps (TD-203, §4.8): a whole number of rounds, each one pass through review-model.
    "design-rounds": ("4", "the most review rounds for an in-repo design plan (§4.8)"),
    "design-rounds-wide": ("6", "the most review rounds for a wide design plan: another repo, the payload, a published format, the irreversible (§4.8)"),
    "review-outcomes": ("off", "on | off: whether filing an entry asks if a design missed the defect (Escaped from:, §2.13) and the backfill is suggested (TD-204)"),
}


def _count(v) -> int:
    """A threshold (TD-134): a whole number >= 1, as a TOML integer or a string of one."""
    if isinstance(v, bool) or not (isinstance(v, int) or (isinstance(v, str) and v.strip().isascii() and v.strip().isdigit())):
        raise ValueError(f"must be a whole number of 1 or more, not {v!r}")
    n = int(v)
    if n < 1:
        raise ValueError(f"must be a whole number of 1 or more, not {v!r}")
    return n


COUNT_KEYS = ("sweep-every", "deep-sweep-every", "pr-stale-days", "escalate-overdue-days", "board-size-warn",
              "design-rounds", "design-rounds-wide")


def _models(v: str) -> str:
    """review-model (TD-203): one model or an ordered, comma-separated list, as `sonnet, fable`.
    Each name is non-empty with no blank inside it; the value comes back as `a, b`."""
    names = [n.strip() for n in v.split(",")]
    if any(not n or any(c.isspace() for c in n) for n in names):
        raise ValueError(f"must be a model or a comma-separated list of models (\"sonnet, fable\"), not {v!r}")
    return ", ".join(names)


def _model(v: str) -> str:
    """fact-check-model (TD-203): one model, or <adapter>/<model> (gemini/gemini-2.5-flash)."""
    n = v.strip()
    parts = n.split("/")
    if "," in n or any(c.isspace() for c in n) or len(parts) > 2 or not all(parts):
        raise ValueError(f"must be one model or <adapter>/<model>, not {v!r}")
    return n


def _scope(v: str) -> str:
    """attention-scope (TD-146): own or machine."""
    n = v.strip().lower()
    if n not in ("own", "machine"):
        raise ValueError(f"must be own or machine, not {v!r}")
    return n


def _onoff(v: str) -> str:
    """review-outcomes (TD-204): on or off."""
    n = v.strip().lower()
    if n not in ("on", "off"):
        raise ValueError(f"must be on or off, not {v!r}")
    return n


def _rel_dir(v: str) -> str:
    """worktree-root: a directory inside the clone, so every reader can join it to the root."""
    n = os.path.normpath(v.strip())
    if os.path.isabs(n) or n == "." or n == ".." or n.startswith("../") or n.startswith("~"):
        raise ValueError(f"must be a path inside the clone, relative to its root, not {v!r}")
    parts = n.split("/")
    # .git is git's; .claude itself holds settings. Glob and gitignore metacharacters would
    # make find -path, the editor's exclude and sync's .gitignore line match more than the
    # root, so the value is kept to plain names.
    if parts[0] == ".git" or n == ".claude" or any(c in n for c in "*?[]\\") or any(p[:1] in ("#", "!") for p in parts):
        raise ValueError(f"must be a plain directory path (no .git, no bare .claude, no * ? [ ] \\, no leading # or !), not {v!r}")
    return n


# The repo's own keys (TD-113): read from the repo's file only — never env, never the machine's
# file, no default — because each is a decision about that one repo. An env precheck would let a
# session pick the check it is judged by.
REPO_KEYS = {
    "precheck": "the repo's own checks (lint, typecheck, tests) as one command; scripts/precheck.py runs it on a PR's head before the merge and records a cadence/precheck status (TD-117)",
    "ledger-ids-host": "on | off: whether a take from the ledger-id counter names this machine in its commit (TD-124); unset reads as on — off for a repo that is public, or about to be",
    "publish-gate": "required | off: whether `cadence_layer.py --publish-check` must have the machine's publish-names to run here (TD-189); required for a repo that is public, whose precheck runs the gate — unset reads as off",
}

# Keys a tool once read and nothing reads now: --check names each by what became of it, rather
# than as an unknown key a repo might think it mistyped.
RETIRED_KEYS = {
    "post-sync": "sync.sh ran it after it wrote the synced files, and nothing has run it since the copy was retired (TD-129, TD-169)",
}

# The person's own keys (TD-126): read from the machine's file only — never env, never a repo's
# file, no default. `layers` names the person's cadence layers (cadence.md §9.18), and a repo's
# file naming them would hand one person's rules to everyone who works in that repo.
MACHINE_KEYS = {
    "layers": "the person's cadence layers, in order (a later one wins): an array of tables, each a `path` "
              "to a file in a git clone (absolute or ~/) and, for a layer one does not own, the `ref` it is "
              "read at; scripts/cadence_layer.py prints them at session start (TD-126)",
    "publish-names": "names `cadence_layer.py --publish-check` flags in every file it reads — the person's own "
                     "name, a private org or repo the roster does not hold: an array of strings, kept here so "
                     "the list itself is never in a tree that goes public (TD-090)",
}


def _layers(v: object) -> list[dict]:
    """layers: [{path = "~/…/file.md"}, {path = "…", ref = "v1"}] — each a file by absolute or ~/ path."""
    if not isinstance(v, list) or not v:
        raise ValueError(f"must be a non-empty array of tables ([[layers]] or layers = [{{path = …}}]), not {v!r}")
    out = []
    for i, e in enumerate(v, 1):
        if not isinstance(e, dict):
            raise ValueError(f"entry {i} must be a table with a path, not {e!r}")
        extra = sorted(set(e) - {"path", "ref"})
        if extra:
            raise ValueError(f"entry {i}: unknown field {', '.join(extra)} (known: path, ref)")
        path, ref = e.get("path"), e.get("ref")
        if not isinstance(path, str) or not path.strip():
            raise ValueError(f"entry {i} needs a path, a non-empty string, not {path!r}")
        if not (os.path.isabs(path) or path.startswith("~/")):
            raise ValueError(f"entry {i}: path must be absolute or start with ~/, not {path!r}")
        if ref is not None and (not isinstance(ref, str) or not ref.strip() or ref.startswith("-")):
            raise ValueError(f"entry {i}: ref must be a git ref (a non-empty string, no leading -), not {ref!r}")
        out.append({"path": path, **({"ref": ref} if ref is not None else {})})
    return out


def _names(v: object) -> list[str]:
    """publish-names: ["Alice", "acme-corp"] — each a non-empty string."""
    if not isinstance(v, list) or not all(isinstance(x, str) and x.strip() for x in v):
        raise ValueError(f"must be an array of non-empty strings, not {v!r}")
    return [x.strip() for x in v]


# A repo key with a fixed vocabulary: the values check() accepts (resolve() still hands over the string).
REPO_CHOICES = {"ledger-ids-host": ("on", "off"), "publish-gate": ("required", "off")}


# key -> a function returning the value to use, or raising ValueError naming what is wrong.
# `get`, every importer through resolve(), and --check all go through it.
VALIDATE = {"worktree-root": _rel_dir, "attention-scope": _scope, "review-outcomes": _onoff, "review-model": _models, "fact-check-model": _model, "layers": _layers, "publish-names": _names, **{k: _count for k in COUNT_KEYS}}


# The opt-outs (TD-072, moved here by TD-096): tables in the repo's file, never the machine's —
# not adopting a rule is the repo's decision. Each maps a value to the ADR that decided it.
OPTOUT_TABLES = ("not-adopted", "skip-seed")
# The pin (TD-129): the [agent-cadence] table in the repo's file — `source`, a git URL, and `ref`, a
# full 40-hex commit — names the agent-cadence the repo runs through the launcher
# (launcher/agent_cadence.py, which reads it itself: it is installed apart from any repo, so it
# cannot import this file). Only --check reads it here, with the launcher's rules.
PIN_TABLE = "agent-cadence"
PIN_FIELDS = ("source", "ref")
PIN_SOURCE_RE = r"[A-Za-z][A-Za-z0-9+.-]*://\S+|[^/\s:]+:\S+|/\S*"   # the launcher's SOURCE_RE


def _pin_problems(label: str, v) -> list[str]:
    if label != REPO_FILE:
        return [f"{label}: [{PIN_TABLE}] is the repo's pin — put it in {REPO_FILE}; not read here"]
    if not isinstance(v, dict):
        return [f"{label}: {PIN_TABLE} must be a table ([{PIN_TABLE}]), not {v!r}"]
    out = [f"{label}: [{PIN_TABLE}] unknown field {k!r} (known: {', '.join(PIN_FIELDS)})"
           for k in v if k not in PIN_FIELDS]
    source, ref = v.get("source"), v.get("ref")
    if not isinstance(source, str) or not re.fullmatch(PIN_SOURCE_RE, source.strip()):
        out.append(f"{label}: [{PIN_TABLE}] source must be a git URL or an absolute path, not {source!r}")
    if not isinstance(ref, str) or len(ref) != 40 or any(c not in "0123456789abcdef" for c in ref):
        out.append(f"{label}: [{PIN_TABLE}] ref must be a full 40-hex commit (never a tag or branch), not {ref!r}")
    return out


# The narrow prechecks (TD-155): a table in the repo's file mapping a space-separated list of globs
# to a command. precheck.py --pr runs an entry's command instead of `precheck` when every file the
# PR changes matches one of that entry's globs (fnmatch on the repo-relative path; `*` crosses `/`).
PATHS_TABLE = "precheck-paths"


def precheck_paths(files: list[tuple[str, dict]]) -> list[tuple[list[str], str]]:
    """(globs, command) for each [precheck-paths] entry in the repo's file, in the file's order.
    Raises ConfigError on one --check would name."""
    for label, table in files:
        if label != REPO_FILE or PATHS_TABLE not in table:
            continue
        problems = _paths_problems(label, table[PATHS_TABLE])
        if problems:
            raise ConfigError(problems[0])
        return [(k.split(), v.strip()) for k, v in table[PATHS_TABLE].items()]
    return []


def _paths_problems(label: str, v) -> list[str]:
    if label != REPO_FILE:
        return [f"{label}: [{PATHS_TABLE}] is the repo's decision — put it in {REPO_FILE}; not read here"]
    if not isinstance(v, dict):
        return [f"{label}: {PATHS_TABLE} must be a table ([{PATHS_TABLE}]), not {v!r}"]
    return [f"{label}: [{PATHS_TABLE}] {k!r} must name globs and map them to a non-empty command string, not {c!r}"
            for k, c in v.items() if not k.split() or not isinstance(c, str) or not c.strip()]


LEGACY_FILE = "docs/cadence-local.conf"   # TD-072's line grammar, still read until each repo moves
SEP = "\x1f"   # opt-outs' field separator: non-whitespace, so an empty field survives `read`


ALL_KEYS = [*KEYS, *REPO_KEYS, *MACHINE_KEYS]


class ConfigError(Exception):
    pass


def env_name(key: str) -> str:
    return "CADENCE_" + key.upper().replace("-", "_")


def repo_root(start: str) -> str | None:
    try:
        p = subprocess.run(["git", "-C", start, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else None


def machine_path() -> str:
    reg = os.environ.get("AGENT_CADENCE_REG_DIR")
    if not reg:
        base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
        reg = os.path.join(base, "agent-cadence")
    return os.path.join(reg, MACHINE_NAME)


def load(path: str) -> dict | None:
    """The file's table, None when there is no file. Raises ConfigError when it cannot be read."""
    if not os.path.lexists(path):
        return None
    if not os.path.isfile(path):
        raise ConfigError(f"{path}: not a file")
    try:
        import tomllib
    except ImportError:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError as e:
            raise ConfigError(f"{path}: {e}") from None
        # the SEED as synced is comments alone: nothing written, so nothing to misread
        if all(not ln.strip() or ln.lstrip().startswith("#") for ln in text.splitlines()):
            return {}
        raise ConfigError(f"{path}: reading it needs Python >= 3.11 (tomllib); this is "
                          f"{sys.version.split()[0]}") from None
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except (OSError, ValueError) as e:  # tomllib.TOMLDecodeError is a ValueError
        raise ConfigError(f"{path}: {e}") from None


def sources(repo: str | None) -> list[tuple[str, dict]]:
    """(label, table) for each file that exists, highest precedence first."""
    out = []
    if repo:
        t = load(os.path.join(repo, REPO_FILE))
        if t is not None:
            out.append((REPO_FILE, t))
    mp = machine_path()
    t = load(mp)
    if t is not None:
        out.append((mp, t))
    return out


def resolve(key: str, files: list[tuple[str, dict]]) -> tuple[object, str]:
    if key in REPO_KEYS:
        for label, table in files:
            if label == REPO_FILE and key in table:
                v = table[key]
                if not isinstance(v, str) or not v.strip():
                    raise ConfigError(f"{label}: {key} must be a non-empty string, not {v!r}")
                return v, label
        return None, "unset"
    if key in MACHINE_KEYS:
        for label, table in files:
            if label != REPO_FILE and key in table:
                return _valid(key, table[key], label), label
        return None, "unset"
    v = (os.environ.get(env_name(key)) or "").strip()
    if v:
        return _valid(key, v, "env " + env_name(key)), "env " + env_name(key)
    for label, table in files:
        if key in table:
            v = table[key]
            if key in COUNT_KEYS:   # an integer is the natural way to write one
                return _valid(key, v, label), label
            if not isinstance(v, str) or not v:
                raise ConfigError(f"{label}: {key} must be a non-empty string, not {v!r}")
            return _valid(key, v, label), label
    if key == "fact-check-model":   # unset: round one's reviewer checks the facts too
        models, src = resolve("review-model", files)
        return first(models), f"first review-model, {src}"
    default = KEYS[key][0]
    if default is not None and key in VALIDATE:
        default = VALIDATE[key](default)
    return default, "default" if default is not None else "unset"


def first(models: str) -> str:
    """The head of a review-model value: round one's reviewer."""
    return models.split(",")[0].strip()


def _valid(key: str, v, label: str):
    if key not in VALIDATE:
        return v
    try:
        return VALIDATE[key](v)
    except ValueError as e:
        raise ConfigError(f"{label}: {key} {e}") from None


def check(files: list[tuple[str, dict]]) -> list[str]:
    problems = []
    for label, table in files:
        for k, v in table.items():
            if k in OPTOUT_TABLES:
                if label != REPO_FILE:
                    problems.append(f"{label}: [{k}] is the repo's decision — put it in {REPO_FILE}; not read here")
                elif not isinstance(v, dict):
                    problems.append(f"{label}: {k} must be a table ([{k}]), not {v!r}")
                else:
                    problems += [f"{label}: [{k}] {name!r} must name its ADR as a string, not {adr!r}"
                                 for name, adr in v.items() if not isinstance(adr, str)]
            elif k == PIN_TABLE:
                problems += _pin_problems(label, v)
            elif k == PATHS_TABLE:
                problems += _paths_problems(label, v)
            elif k in REPO_KEYS and label != REPO_FILE:
                problems.append(f"{label}: {k} is the repo's decision — put it in {REPO_FILE}; not read here")
            elif k in MACHINE_KEYS and label == REPO_FILE:
                problems.append(f"{label}: {k} is the person's, not the repo's — put it in the machine's "
                                f"{MACHINE_NAME} ({machine_path()}); not read here")
            elif k in MACHINE_KEYS:
                try:
                    VALIDATE[k](v)
                except ValueError as e:
                    problems.append(f"{label}: {k} {e}")
            elif k in REPO_KEYS:
                if not isinstance(v, str) or not v.strip():
                    problems.append(f"{label}: {k} must be a non-empty string, not {v!r}")
                elif k in REPO_CHOICES and v.strip().lower() not in REPO_CHOICES[k]:
                    problems.append(f"{label}: {k} must be one of {', '.join(REPO_CHOICES[k])}, not {v!r}")
            elif k in RETIRED_KEYS:
                problems.append(f"{label}: {k} is retired — {RETIRED_KEYS[k]}; delete the line")
            elif k not in KEYS:
                problems.append(f"{label}: unknown key '{k}' — nothing reads it (known: {', '.join(ALL_KEYS)})")
            elif k not in COUNT_KEYS and (not isinstance(v, str) or not v):
                problems.append(f"{label}: {k} must be a non-empty string, not {v!r}")
            elif k in VALIDATE:
                try:
                    VALIDATE[k](v)
                except ValueError as e:
                    problems.append(f"{label}: {k} {e}")
    return problems


def legacy_optouts(path: str) -> list[tuple]:
    """TD-072's `key: value — ADR` lines, read as sync.sh's bash parser read them before TD-096 (the same
    words in every WARN, in file order, so the move changes nothing a consumer sees): a list of
    ("opt", kind, value, why, line) and ("warn", message), in the order the file gives them."""
    if os.path.islink(path):
        return [("warn", "is a symlink — not read; nothing is opted out")]
    if not os.path.lexists(path) or os.path.isdir(path):
        return []
    try:
        with open(path, encoding="utf-8", errors="replace", newline="") as f:
            text = f.read()
    except OSError as e:  # bash died on it here; never let an opt-out drop in silence
        return [("warn", f"cannot read ({e.strerror or e}) — nothing is opted out from it")]
    out: list[tuple] = []
    for raw in text.split("\n"):   # bash's lines: \n only, never \v, \f or U+2028
        line = raw.removesuffix("\r").lstrip(" \t")
        if not line or line.startswith("#"):
            continue
        key, colon, rest = line.partition(":")
        if not colon:
            out.append(("warn", f"cannot read '{line}' — write not-adopted: §N or skip-seed: <path>"))
            continue
        if key not in OPTOUT_TABLES:
            out.append(("warn", f"cannot read '{line}' — unknown key '{key}' (not-adopted, skip-seed); ignored"))
            continue
        # `read -r val why`: split on blanks once, trim the rest's ends, keep its inner spacing
        rest = rest.strip(" \t")
        value, _, why = rest.replace("\t", " ").partition(" ")
        why = why.strip(" \t").removeprefix("—").removeprefix("-").lstrip(" \t")
        out.append(("opt", key, value, why, line))
    if any(e[0] == "opt" for e in out):
        out.append(("warn", f"is deprecated — move each line into {REPO_FILE} as a [not-adopted] or "
                            "[skip-seed] entry (cadence.md Adoption checklist step 9, TD-096); still read"))
    return out


def optouts(repo: str) -> list[str]:
    """The TSV `agent-cadence adopt` reads: the repo's [not-adopted]/[skip-seed] tables, then the legacy
    file's lines. A file that cannot be read is a warn line, never an exit: the caller adopts
    the whole payload rather than guess (cadence.md Adoption checklist step 9)."""
    out: list[str] = []

    def clean(s: str) -> str:
        # one field: no separator or line break from the file reaches bash; spacing otherwise kept
        return "".join(" " if ch in SEP + "\t\r\n\v\f" else ch for ch in str(s)).strip()

    path = os.path.join(repo, REPO_FILE)
    try:
        table = load(path) or {}
    except ConfigError as e:
        out.append(f"warn{SEP}{REPO_FILE}: cannot read ({clean(e)}) — nothing opted out from it")
        table = {}
    for kind in OPTOUT_TABLES:
        entries = table.get(kind, {})
        if not isinstance(entries, dict):
            out.append(f"warn{SEP}{REPO_FILE}: {kind} must be a table ([{kind}]) — ignored")
            continue
        for name, adr in entries.items():
            shown = f'[{kind}] "{clean(name)}"'
            if not isinstance(adr, str):
                out.append(f"warn{SEP}{REPO_FILE}: {shown} must name its ADR as a string — ignored")
                continue
            out.append(SEP.join((kind, clean(name), clean(adr), REPO_FILE, shown)))
    for e in legacy_optouts(os.path.join(repo, LEGACY_FILE)):
        if e[0] == "warn":
            out.append(f"warn{SEP}{LEGACY_FILE}: {clean(e[1])}")
        else:
            out.append(SEP.join((e[1], clean(e[2]), clean(e[3]), LEGACY_FILE, clean(e[4]))))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Read the cadence's settings (TD-096).")
    ap.add_argument("cmd", nargs="?", choices=["get", "opt-outs"])
    ap.add_argument("key", nargs="?")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--first", action="store_true", help="with get review-model: the first model only")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--repo")
    a = ap.parse_args(argv)
    if a.cmd == "get" and not a.key:
        ap.error("get needs a key")
    if a.first and (a.cmd != "get" or a.key != "review-model"):
        ap.error("--first goes with get review-model")
    if a.cmd == "opt-outs":
        if not a.repo or not os.path.isdir(a.repo):
            print("cadence_config: opt-outs needs --repo DIR, an existing directory", file=sys.stderr)
            return 2
        for ln in optouts(a.repo):
            print(ln)
        return 0
    if a.key and a.key not in ALL_KEYS:
        print(f"cadence_config: unknown key '{a.key}' (known: {', '.join(ALL_KEYS)})", file=sys.stderr)
        return 2
    try:
        root = repo_root(a.repo or ".")
        if a.repo and root is None:  # asked for by name: a wrong path is not "no settings"
            raise ConfigError(f"--repo {a.repo}: not a git repository")
        files = sources(root)
        if a.check:
            problems = check(files)
            for p in problems:
                print(p)
            return 1 if problems else 0
        if a.cmd == "get":
            value, _ = resolve(a.key, files)
            if value is None:
                return 1
            if a.first:
                value = first(value)
            print(value if isinstance(value, str) else json.dumps(value))
            return 0
        rows = {k: dict(zip(("value", "from"), resolve(k, files))) for k in ALL_KEYS}
    except ConfigError as e:
        print(f"cadence_config: {e}", file=sys.stderr)
        return 2
    if a.json:
        print(json.dumps(rows, indent=1))
    else:
        for k, r in rows.items():
            v = r["value"]
            shown = "-" if v is None else v if isinstance(v, str) else json.dumps(v)
            print(f"{k:<14} {shown:<12} ({r['from']})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
