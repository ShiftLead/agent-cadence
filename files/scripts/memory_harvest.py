#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/memory_harvest.py
# Edit it there: a repo runs it from its pinned dev-cadence (`dev-cadence path`), and a fix reaches it by a bump PR.
"""The memory harvest's inventory and its record (TD-125, docs/plans/2026-10-23-memory-harvest.md).

    memory_harvest.py inventory [--json]
                    read-only: every memory in every roster repo's memory directory — repo,
                    file, name, description, type, a sha256 of the text, where it was found,
                    and what the record already says of it
    memory_harvest.py record <repo> <file> <verdict> [--where REF]   (--ref is the same flag)
                    write one judgement to the record; the only writer of the record
    memory_harvest.py record --stdin
                    a batch (TD-141): one judgement a line, `<repo> <file> <verdict> [<where>]`
                    (the rest of the line is the where, else --where's; blank and `#` lines skipped), the roster
                    read once; every line is checked before any is written, so a bad line
                    writes none
    memory_harvest.py stamp
                    end of a run: `Harvested: YYYY-MM-DD (<host>, <n> repos)` as a header line of
                    the own layer file, in place of the last one; the only writer of the stamp
    memory_harvest.py clone
                    read-only: the own layer's clone, the root printed, once it is fit for the run's
                    writes — on its default branch, nothing staged or modified, nothing untracked
                    but .claude/ (TD-135); exit 1 names what is in the way

WHY
Sessions save process rules as memories, and a rule found the hard way in one repo stays there:
the cadence never learns it and the next repo asks the person again (TD-125's Why). The harvest
is a procedure the person starts; this script is its eyes and its pen. It never decides a
verdict — the session and the person do — and it never writes in another repo.

WHAT IT READS
The roster, through nudge_user_attention.read_registry() (§9.4: imported, never re-typed). For
each repo, the memory directory the way check_claude_memory.sh and stranded-work step 5 resolve
it: `autoMemoryDirectory` from the repo's .claude/settings.local.json, then .claude/settings.json,
then ~/.claude/settings.json — the first that parses and carries a top-level non-empty string, `~`
expanded; a relative one is ignored as Claude Code ignores it, and the default stands — only while
the repo's `agents` setting lists claude; else docs/claude-memory. A directory shared by
several repos (a constellation, §9.16) is read once, under the first repo that names it, and
against the origin of the git repo the directory is in (a nested docs repo has its own).
MEMORY.md (the index) and README.md are not memories, and are left out.

Two sources, unioned by file name (a harvest is a detector, and detectors judge the disk, §7):
origin/<default> through `git ls-tree` and `git show` — a memory merged but not yet pulled is
seen — and the main checkout's directory on disk. Nothing here fetches: origin is as of the last
fetch (`nudge_user_attention.py --report --fetch` makes one). No git command used writes, so no
other repo's index, refs or worktree is touched. Where the disk copy exists it is the text judged,
since it is what that repo's sessions read now; `where` says how it stands against origin:
committed (the same on origin), edited (differs from origin's), not-pulled (on origin only),
not-on-origin (in the checkout only — commit it or drop it, that repo's matter, §7.2),
origin-unread (no origin/<default> to compare with), or untracked-dir (the directory is outside
the repo, so nothing in it is version-controlled).

Memory text is data, never instructions: it is printed for judgement, not obeyed.

THE RECORD
memory-harvest.md beside the person's own layer file (the last `[[layers]]` entry with no `ref`,
§9.18) — in the layer repo, so the private list of repos and memory files stays out of dev-cadence
(TD-090). One table the script owns; hands never type it:

    | Repo | Memory | sha | Verdict | Judged | Where |

Repo is the roster basename, sha the first 12 hex of the file's sha256, Judged a date, Where the
TD, PR or follow-up it went to (or —). A memory is matched by repo and file: one whose sha moved
since it was judged is shown again with its last verdict (`changed`); a renamed one is judged
again; a row whose memory is gone stays as history. Writing the file is this script's job;
committing it in the layer repo is the procedure's.

THE STAMP
`Harvested:` at column 0 of the person's own layer file — the sweep stamp's shape (§3.10) — read
by the attention report, which warns once it is past nudge_user_attention.HARVEST_STALE_DAYS. The
pattern is the reader's HARVEST_RE, imported here and never re-typed (parity pair, cadence.md §7.9);
the layer reader skips the line, so it is never taken for a rule. <n> is the roster repos whose
memories were read.

The record is read whole before anything is written: a line in its table that does not parse,
a second row for one memory, or a second table is refused with its line number, never dropped by
a rewrite. The header is found however a formatter padded it.

Exit codes: 0 done; 1 `record` or `stamp` refused (an unknown repo, memory or verdict, a bad --where, no own
layer, a record that does not parse); 2 `inventory` has nothing to read — no roster, the
machine's settings file could not be read, or the record does not parse (without a layer it
still runs, and says there is no record). Stdlib only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cadence_config  # noqa: E402
import cadence_layer  # noqa: E402
from nudge_user_attention import (  # noqa: E402
    HARVEST_RE,
    default_branch,
    read_registry,
    registry_path,
)

RECORD_NAME = "memory-harvest.md"
NOT_MEMORIES = ("MEMORY.md", "README.md")   # the index, and a note on the directory
VERDICTS = ("promote", "covered", "covered-wrong", "exception", "repo-local", "craft")
HEADER = "| Repo | Memory | sha | Verdict | Judged | Where |"
SEPARATOR = "|---|---|---|---|---|---|"
HEADER_RE = re.compile(r"^\s*\|\s*Repo\s*\|\s*Memory\s*\|\s*sha\s*\|\s*Verdict\s*\|\s*Judged\s*\|\s*Where\s*\|\s*$")
SEPARATOR_RE = re.compile(r"^\s*\|(?:\s*:?-+:?\s*\|){6}\s*$")
ROW_RE = re.compile(r"^\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*([0-9a-f]{12})\s*\|\s*([a-z-]+)\s*\|"
                    r"\s*(\d{4}-\d{2}-\d{2})\s*\|\s*([^|]*?)\s*\|\s*$")
PREAMBLE = """# Memory harvest record

Every memory the harvest has judged (dev-cadence `docs/procedures/memory-harvest.md`, TD-125):
the repo, the file, the first 12 hex of its sha256 when judged, the verdict, the date and where
it went. `memory_harvest.py record` writes this table and nothing else does — never edit it by
hand. A memory whose text changed since its row is shown again at the next run.
"""
GIT_TIMEOUT = 10
# never a GIT_DIR or index the calling session carries; and no optional lock or index refresh
GIT_ENV = {**{k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")},
           "GIT_OPTIONAL_LOCKS": "0"}
SETTINGS = (".claude/settings.local.json", ".claude/settings.json")


def git(root: Path, *args: str) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True, timeout=GIT_TIMEOUT,
                              check=False, env=GIT_ENV, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return None


# --- where a repo's memory is (parity: check_claude_memory.sh, stranded-work step 5) ---------

def claude_listed(root: Path) -> bool:
    try:
        from agent_sessions import wanted
    except ImportError:
        return True
    tools = wanted(root)
    return "claude" in tools or any(t.startswith("!") for t in tools)


def memory_dir(root: Path) -> tuple[Path, str]:
    """(the directory, where the answer came from)."""
    if claude_listed(root):
        for f in [root / s for s in SETTINGS] + [Path.home() / ".claude/settings.json"]:
            try:
                d = json.loads(f.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue   # missing or not JSON: Claude Code skips it too
            v = d.get("autoMemoryDirectory") if isinstance(d, dict) else None
            if not isinstance(v, str) or not v:
                continue
            if v == "~" or v.startswith("~/"):
                v = str(Path.home()) + v[1:]
            if not os.path.isabs(v):   # Claude Code ignores it, and the guard falls back, not on
                return root / "docs/claude-memory", f"default (the relative autoMemoryDirectory in {f} is ignored)"
            return Path(v), f"autoMemoryDirectory in {f}"
    return root / "docs/claude-memory", "default"


# --- frontmatter ---------------------------------------------------------------------------

def _unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = v[1:-1]
    return v


def frontmatter(text: str) -> dict:
    """name, description and type — type at the top level or under `metadata:`; absent keys are ""."""
    out = {"name": "", "description": "", "type": ""}
    lines = text.removeprefix("\ufeff").splitlines()
    if not lines or lines[0].strip() != "---":
        return out
    in_meta = False
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        m = re.match(r"^(\s*)([A-Za-z_][\w-]*):\s*(.*)$", ln)
        if not m:
            continue
        indent, key, val = m.groups()
        if not indent:
            in_meta = key == "metadata" and not val.strip()
            if key in out and not (key == "type" and out["type"]):
                out[key] = _unquote(val)
        elif in_meta and key == "type" and not out["type"]:
            out["type"] = _unquote(val)
    return out


# --- the record ----------------------------------------------------------------------------

def record_path() -> Path | None:
    layer = cadence_layer.own_layer()
    return layer.parent / RECORD_NAME if layer else None


class RecordError(Exception):
    """The record cannot be read safely: rewriting it would lose a line."""


def _table(lines: list[str], path: Path) -> tuple[int, int] | None:
    """[start, end) of the one table: its header (spacing as a formatter pads it), the separator,
    and every `|` line after them. None when the file has no table yet."""
    found = [i for i, ln in enumerate(lines) if HEADER_RE.match(ln)]
    if len(found) > 1:
        raise RecordError(f"{path} has {len(found)} record tables (lines {', '.join(str(i + 1) for i in found)}): "
                          "keep one by hand, then run again")
    if not found:
        return None
    start = end = found[0]
    if end + 1 >= len(lines) or not SEPARATOR_RE.match(lines[end + 1]):
        raise RecordError(f"{path}:{start + 2}: the record table's header has no |---| line under it")
    end += 2
    while end < len(lines) and lines[end].lstrip().startswith("|"):
        end += 1
    return start, end


def read_record(path: Path | None) -> dict[tuple[str, str], dict]:
    """The table's rows by (repo, memory). Raises RecordError on a table line that does not parse —
    a rewrite would drop it — or on a memory with two rows."""
    rows: dict[tuple[str, str], dict] = {}
    if path is None or not path.is_file():
        return rows
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise RecordError(f"{path} cannot be read ({e})") from e
    span = _table(lines, path)
    if span is None:
        return rows
    for i in range(span[0] + 2, span[1]):
        m = ROW_RE.match(lines[i])
        if not m or m.group(4) not in VERDICTS:
            raise RecordError(f"{path}:{i + 1}: not a record row ({lines[i].strip()[:80]}) — "
                              "fix or remove it by hand; the script never drops a line it cannot read")
        repo, mem, sha, verdict, judged, where = m.groups()
        if (repo, mem) in rows:
            raise RecordError(f"{path}:{i + 1}: a second row for {repo} {mem} — keep one by hand")
        rows[(repo, mem)] = {"sha": sha, "verdict": verdict, "judged": judged, "where": where}
    return rows


def write_record(path: Path, rows: dict[tuple[str, str], dict]) -> None:
    table = [HEADER, SEPARATOR] + [
        f"| {repo} | {mem} | {r['sha']} | {r['verdict']} | {r['judged']} | {r['where']} |"
        for (repo, mem), r in sorted(rows.items())]
    if path.is_file():
        lines = path.read_text(encoding="utf-8").splitlines()
        span = _table(lines, path)
        if span is None:   # a file the script did not make: the table goes at its end
            lines += [""] if lines and lines[-1].strip() else []
            span = (len(lines), len(lines))
        lines[span[0]:span[1]] = table
    else:
        lines = PREAMBLE.splitlines() + [""] + table
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def clone_problem(layer: Path) -> tuple[Path | None, str | None]:
    """(the layer clone's root, what keeps the run from writing there). The run starts in any
    cadence repo and commits the layer and the record with `git -C`, so a clone off its default
    branch would take them onto a branch no other machine pulls, and one holding someone's edits
    would mix them into the harvest's commit. Untracked `.claude/` is a session's own, and allowed."""
    r = git(layer.parent, "rev-parse", "--show-toplevel")
    if r is None or r.returncode != 0:
        return None, f"the own layer {layer} is not in a git clone — the run commits and pushes there"
    root = Path(r.stdout.decode().strip())
    want = default_branch(root)
    r = git(root, "symbolic-ref", "-q", "--short", "HEAD")
    on = r.stdout.decode().strip() if r is not None and r.returncode == 0 else ""
    if on != want:
        return root, f"{root} is {'on ' + on if on else 'detached'}, not its default branch {want} — " \
                     "the run commits there, and other machines pull the default branch"
    r = git(root, "status", "--porcelain", "--untracked-files=normal")
    if r is None or r.returncode != 0:
        return root, f"git status could not be read in {root}"
    in_way = [ln[3:] for ln in r.stdout.decode().splitlines()
              if ln and not (ln.startswith("?? ") and ln[3:].strip('"').startswith(".claude/"))]
    if in_way:
        shown = ", ".join(in_way[:5]) + (f" and {len(in_way) - 5} more" if len(in_way) > 5 else "")
        return root, f"{root} holds changes the run did not make: {shown} — commit or clear them first"
    return root, None


def stamp_line(today: str, host: str, n: int) -> str:
    return f"Harvested: {today} ({host}, {n} repo{'s' if n != 1 else ''})"


def write_stamp(layer: Path, line: str) -> None:
    """The stamp in place of the layer file's first one; else a header line under its title (or at
    its top), set off by blank lines so the layer reader never runs it into a rule."""
    if not HARVEST_RE.match(line):
        raise ValueError(f"not a stamp the reader reads: {line}")
    lines = layer.read_text(encoding="utf-8").splitlines()
    at, fence = None, ""
    for i, ln in enumerate(lines):   # an example inside a code fence is not the stamp
        f = cadence_layer.FENCE_RE.match(ln)
        if fence:
            fence = "" if f and f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence) and not f.group(2).strip() else fence
        elif f:
            fence = f.group(1)
        elif HARVEST_RE.match(ln):
            at = i
            break
    if at is not None:
        lines[at] = line
    else:
        i = 1 if lines and lines[0].startswith("# ") else 0
        head, rest = lines[:i], lines[i:]
        while rest and not rest[0].strip():
            rest.pop(0)
        lines = head + ([""] if head else []) + [line] + ([""] if rest else []) + rest
    tmp = layer.with_name(layer.name + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(tmp, layer)


# --- the inventory -------------------------------------------------------------------------

def origin_memories(root: Path, mdir: Path) -> tuple[bool, str | None, dict[str, bytes], str]:
    """(the directory is inside the repo, origin/<default> or None, file name -> bytes on it,
    a note when origin could not be read)."""
    if mdir.is_dir():   # the repo the directory is in: a nested docs repo has its own origin
        r = git(mdir, "rev-parse", "--show-toplevel")
        if r is None or r.returncode != 0:
            return False, None, {}, ""
        root = Path(r.stdout.decode("utf-8", errors="replace").strip())
    try:
        rel = mdir.resolve().relative_to(root.resolve())
    except ValueError:
        return False, None, {}, ""
    ref = f"origin/{default_branch(root)}"
    r = git(root, "rev-parse", "--verify", "-q", f"refs/remotes/{ref}")
    if r is None or r.returncode != 0:
        return True, None, {}, f"no {ref} in the clone: only the disk was read"
    r = git(root, "ls-tree", "-z", ref, "--", f"{rel.as_posix()}/")
    if r is None or r.returncode != 0:
        return True, None, {}, f"{ref} could not be listed: only the disk was read"
    out: dict[str, bytes] = {}
    for entry in r.stdout.split(b"\0"):
        if not entry:
            continue
        meta, _, path = entry.partition(b"\t")
        parts = meta.split()
        name = os.path.basename(path.decode("utf-8", errors="replace"))
        if len(parts) < 3 or parts[1] != b"blob" or not name.endswith(".md") or name in NOT_MEMORIES:
            continue
        s = git(root, "cat-file", "blob", parts[2].decode())
        if s is not None and s.returncode == 0:
            out[name] = s.stdout
    return True, ref, out, ""


def disk_memories(mdir: Path) -> dict[str, bytes]:
    out: dict[str, bytes] = {}
    try:
        names = sorted(os.listdir(mdir))
    except OSError:
        return out
    for name in names:
        p = mdir / name
        if name.endswith(".md") and name not in NOT_MEMORIES and p.is_file() and not p.is_symlink():
            try:
                out[name] = p.read_bytes()
            except OSError:
                continue
    return out


def inventory(record: dict[tuple[str, str], dict]) -> list[dict]:
    roster = read_registry()
    if roster is None:
        raise FileNotFoundError(f"no roster at {registry_path()}")
    repos: list[dict] = []
    seen: dict[str, str] = {}
    named: dict[str, Path] = {}
    for root in roster:
        name = root.name
        twin = named.setdefault(name, root)
        mdir, source = memory_dir(root)
        entry = {"repo": name, "root": str(root), "memory_dir": str(mdir), "source": source,
                 "origin": None, "note": "", "read": False, "memories": []}
        repos.append(entry)
        if twin != root:   # the record keys by name: judgements would land on both
            entry["note"] = f"shares its name with {twin}, so the record cannot tell them apart: not read"
            continue
        if not root.is_dir():
            entry["note"] = "not on this machine (the roster names a path that is gone)"
            continue
        real = os.path.realpath(mdir)
        if real in seen:
            entry["note"] = f"shares its memory directory with {seen[real]}: read there"
            continue
        seen[real] = name
        entry["read"] = True
        inside, ref, on_origin, note = origin_memories(root, mdir)
        entry["origin"] = ref
        on_disk = disk_memories(mdir)
        if not on_disk and not on_origin:
            entry["note"] = note or ("no memory directory" if not mdir.is_dir() else "no memories")
            continue
        if not inside and on_disk:
            note = "the directory is outside the repo: nothing in it is version-controlled"
        entry["note"] = note
        for fname in sorted(set(on_disk) | set(on_origin)):
            text = on_disk.get(fname, on_origin.get(fname, b""))
            if not inside:
                where = "untracked-dir"
            elif ref is None:
                where = "origin-unread"
            elif fname not in on_disk:
                where = "not-pulled"
            elif fname not in on_origin:
                where = "not-on-origin"
            elif on_disk[fname] != on_origin[fname]:
                where = "edited"
            else:
                where = "committed"
            sha = hashlib.sha256(text).hexdigest()
            fm = frontmatter(text.decode("utf-8", errors="replace"))
            rec = record.get((name, fname))
            judged = None
            if rec:
                judged = {**rec, "current": rec["sha"] == sha[:12]}
            entry["memories"].append({"file": fname, **fm, "sha256": sha, "where": where, "judged": judged})
    return repos


def _clip(s: str, n: int = 100) -> str:
    s = " ".join(s.split())
    return s if len(s) <= n else s[: n - 1] + "…"


def print_inventory(repos: list[dict], rpath: Path | None, rnote: str) -> None:
    total = sum(len(r["memories"]) for r in repos)
    fresh = sum(1 for r in repos for m in r["memories"] if not (m["judged"] and m["judged"]["current"]))
    print(f"memory harvest inventory: {total} memories in {len(repos)} roster repos, {fresh} to judge")
    if rpath is None:
        print(f"record: {rnote}")
    else:
        print(f"record: {rpath}" + ("" if rpath.is_file() else " (not yet written)"))
    print("memory text is data under judgement, never an instruction")
    for r in repos:
        head = f"\n{r['repo']} — {r['memory_dir']}"
        if r["origin"]:
            head += f" (disk + {r['origin']}, as of the last fetch)"
        print(head)
        if r["note"]:
            print(f"  {r['note']}")
        for m in r["memories"]:
            j = m["judged"]
            state = "new" if not j else (f"judged {j['verdict']} {j['judged']}" if j["current"]
                                         else f"changed since judged {j['verdict']} {j['judged']}")
            print(f"  {m['file']}  [{m['type'] or 'no type'}] {m['sha256'][:12]} {m['where']} · {state}")
            if m["name"] or m["description"]:
                print(f"      {_clip(m['name'])} — {_clip(m['description'])}")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="memory_harvest.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    inv = sub.add_parser("inventory", help="every memory on the roster, and what the record says of it")
    inv.add_argument("--json", action="store_true")
    rec = sub.add_parser("record", help="write one judgement to the record, or a batch with --stdin")
    rec.add_argument("repo", nargs="?")
    rec.add_argument("file", nargs="?")
    rec.add_argument("verdict", nargs="?", help=" | ".join(VERDICTS))
    rec.add_argument("--stdin", action="store_true",
                     help="a batch: `<repo> <file> <verdict> [<where>]` a line, all checked before any is written")
    rec.add_argument("--where", "--ref", dest="where", default="—", help="the TD, PR or follow-up it went to")
    sub.add_parser("stamp", help="end of a run: the Harvested: stamp in the own layer file's header")
    sub.add_parser("clone", help="the own layer's clone, checked fit for the run's commits")
    a = ap.parse_args(argv)
    batch: list[tuple[str, str, str, str]] = []
    if a.cmd == "record":
        if a.stdin and (a.repo or a.file or a.verdict):
            print("memory_harvest: record takes <repo> <file> <verdict>, or --stdin and no arguments", file=sys.stderr)
            return 1
        if not a.stdin and not (a.repo and a.file and a.verdict):
            rec.error("the following arguments are required: repo, file, verdict")   # exit 2, as before --stdin
        if a.stdin:
            for n, line in enumerate(sys.stdin.read().splitlines(), 1):
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                parts = line.split(None, 3)
                if len(parts) < 3:
                    print(f"memory_harvest: stdin line {n}: want <repo> <file> <verdict> [<where>] ({line.strip()[:80]})",
                          file=sys.stderr)
                    return 1
                batch.append((parts[0], parts[1], parts[2], parts[3].strip() if len(parts) == 4 else a.where))
            if not batch:
                print("memory_harvest: record --stdin read no judgements", file=sys.stderr)
                return 1
        else:
            batch = [(a.repo, a.file, a.verdict, a.where)]

    try:
        rpath, rnote = record_path(), ""
    except cadence_config.ConfigError as e:
        print(f"memory_harvest: the machine's settings file could not be read: {e}", file=sys.stderr)
        return 2
    if rpath is None:
        rnote = "no own layer in the machine's cadence.toml (§9.18), so there is no record to read or write"
    if a.cmd == "clone":   # needs no roster and no record
        if rpath is None:
            print(f"memory_harvest: {rnote}", file=sys.stderr)
            return 1
        root, problem = clone_problem(cadence_layer.own_layer())
        if problem:
            print(f"memory_harvest: {problem}", file=sys.stderr)
            return 1
        print(root)
        return 0
    try:
        record = read_record(rpath) if a.cmd != "stamp" else {}   # a stamp needs no record
    except RecordError as e:
        print(f"memory_harvest: {e}", file=sys.stderr)
        return 1 if a.cmd == "record" else 2
    try:
        repos = inventory(record)
    except FileNotFoundError as e:
        print(f"memory_harvest: {e}", file=sys.stderr)
        return 2

    if a.cmd == "inventory":
        if a.json:
            json.dump({"record": str(rpath) if rpath else None, "record_note": rnote, "repos": repos},
                      sys.stdout, indent=1)
            print()
        else:
            print_inventory(repos, rpath, rnote)
        return 0

    if a.cmd == "stamp":
        layer = cadence_layer.own_layer() if rpath else None
        if layer is None or not layer.is_file():
            print(f"memory_harvest: {rnote or f'the own layer file {layer} does not exist'}", file=sys.stderr)
            return 1
        n = sum(1 for r in repos if r["read"])
        today = date.today().isoformat()  # noqa: DTZ011  # a civil date, as the sweep stamp's
        line = stamp_line(today, socket.gethostname().split(".")[0], n)
        write_stamp(layer, line)
        print(f"stamped: {line} → {layer}")
        return 0
    if rpath is None:
        print(f"memory_harvest: {rnote}", file=sys.stderr)
        return 1
    if not rpath.parent.is_dir():
        print(f"memory_harvest: the own layer's directory {rpath.parent} does not exist", file=sys.stderr)
        return 1
    # every judgement checked against the one inventory before any is written: a batch is all or none
    judged = date.today().isoformat()  # noqa: DTZ011  # a civil date, as the board's are
    rows, seen, problems = {}, set(), []
    for repo, fname, verdict, where in batch:
        at = f"{repo} {fname}: " if len(batch) > 1 else ""
        if verdict not in VERDICTS:
            problems.append(f"{at}no verdict {verdict} (one of {', '.join(VERDICTS)})")
            continue
        if any(c in where for c in "|\n\r") or not where.strip():
            problems.append(f"{at}--where must be one line with no |")
            continue
        match = [r for r in repos if r["repo"] == repo]
        if not match:
            problems.append(f"{at}no roster repo named {repo}")
            continue
        if len(match) > 1:
            problems.append(f"{at}{len(match)} roster repos are named {repo} — the record keys a repo by its name, "
                            "so it cannot tell them apart")
            continue
        mem = next((m for r in match for m in r["memories"] if m["file"] == fname), None)
        if mem is None:
            problems.append(f"no memory {fname} in {repo}'s inventory")
            continue
        if (repo, fname) in seen:
            problems.append(f"{repo} {fname} is judged twice in this batch — keep one line")
            continue
        seen.add((repo, fname))
        rows[(repo, fname)] = {"sha": mem["sha256"][:12], "verdict": verdict, "judged": judged, "where": where.strip()}
    if problems:
        for p in problems:
            print(f"memory_harvest: {p}", file=sys.stderr)
        if len(batch) > 1:
            print(f"memory_harvest: nothing recorded — {len(problems)} of {len(batch)} lines refused", file=sys.stderr)
        return 1
    record.update(rows)
    write_record(rpath, record)
    for (repo, fname), r in rows.items():
        print(f"recorded: {repo} {fname} {r['sha']} {r['verdict']} → {rpath}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
