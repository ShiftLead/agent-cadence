#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/hostlog.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""hostlog.py — the `host-log` check's reader (TD-230; ShiftLead/ledgerboard docs/plans/TD-045-host-log.md, rules 8–13).

A ledger gate `event (<name>)` whose check is `host-log <source> [kind <k>] [times <N>] "<text>"` waits on an
event only the host witnesses, in logs on the host. ledgerboard (vendored, v2.5) owns the check line, `since`
(`gate_added()`), the record model and the count (`first_instant`, `count_host_log`); this file is the reader
half: where a source's files are, which may be opened, how they are decompressed, decoded and cut into
records. It opens files read-only, writes nothing and runs no command.

    hostlog.py check --repo-config <path|-> --host-config <path> --repo <owner/name>
                     --visibility public|internal|private [--since YYYY-MM-DD] [--profiles a,b] '<check line>'
    hostlog.py validate --repo-config <path> [--ledger <dir>]

`check` prints one JSON object and exits 0 for every outcome: `outcome` (passed | not yet | impossible |
error, or none: this host gives no outcome), `count`, `evidence`, `skipped` (counts by reason) and
`problem` (the host's own words, never for the board). `--repo-config -` reads the repo's
`docs/ledger/log-sources.toml` on stdin, which the caller takes from the tree it read the ledger from
(`git show origin/<default>:docs/ledger/log-sources.toml`); an empty text is a repo with none. Any other
result (a non-zero exit, output that is not one JSON object, no answer within the caller's 120 s) the
caller reads as error. On a Python without `tomllib` it prints outcome none: the host abstains.

`validate` runs every table's checks (rule 8) and exits 1 on any refusal; `--ledger` also fails each open
entry's `host-log` check whose source no default or profile declares. Warnings (a key the effective shape
does not use, a source enabled nowhere) print without failing.

The two files, in short (the design is the reference):
- the repo's `log-sources.toml`: `[sources.<name>]` defaults and `[profiles.<p>.sources.<name>]` layers,
  each a source table (shape, path, match, exclude, members, records, fields, at, tz, kind, enabled, unset);
- the host's file (outside every repo; the caller passes its path): `[repos."<repo>"]` / `[repos."*"]` with
  `profiles` and `sources` (the host's last word, which may add `public_kinds`), `[[allow]]` roots (root,
  visibility, optional repos and require_repo), and `[limits]`. No host file, or no table for the repo:
  no outcome. The default is no roots: nothing is read until the host's owner allows a folder.
"""
from __future__ import annotations

import argparse
import bz2
import fnmatch
import hashlib
import io
import json
import locale
import lzma
import os
import re
import stat
import sys
import tarfile
import time
import zipfile
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    import tomllib
except ImportError:  # Python < 3.11: the host abstains (rule 13)
    tomllib = None  # type: ignore[assignment]
try:
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
except ImportError:  # pragma: no cover — 3.9+ has it
    ZoneInfo = None  # type: ignore[assignment,misc]
    ZoneInfoNotFoundError = Exception  # type: ignore[assignment,misc]

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledgerboard as LB  # noqa: E402  # sibling SYNC package: the check line, since and the count, defined once

# ---------------------------------------------------------------------------------------------
# The configuration's vocabulary (rules 8, 9, 11)
# ---------------------------------------------------------------------------------------------

NAME_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,39}")          # a source's name, and a kind token (rule 1)
PROFILE_RE = re.compile(r"[A-Za-z0-9_.-]{1,64}")           # a profile's name (rule 8)
SHAPES = ("file", "directory", "rotated", "archives")
RECORDS = ("lines", "jsonl")
FIELD_KEYS = ("at", "kind", "text", "id", "repo")
SOURCE_KEYS = ("shape", "path", "match", "exclude", "members", "records", "fields", "at", "tz", "kind",
               "enabled", "unset")
HOST_ONLY_KEYS = ("public_kinds", "require_repo", "repos")
LIST_KEYS = ("match", "exclude", "members", "at")
# Which keys each shape and each record format reads (rule 10's *Keys*); a key outside them is ignored,
# and validate names it as a warning.
SHAPE_KEYS = {"file": set(), "directory": {"match", "exclude"}, "rotated": {"exclude"},
              "archives": {"match", "exclude", "members"}}
RECORD_KEYS = {"lines": {"at", "tz", "kind"}, "jsonl": {"fields", "tz"}}
ALWAYS_KEYS = {"shape", "path", "records", "enabled", "unset", "public_kinds"}
LIMITS = {"max_files": 10_000, "max_bytes": 64 * 1024 * 1024, "max_line": 1024 * 1024,
          "max_record": 1024 * 1024, "settle_seconds": 600, "max_seconds": 30}
MAX_SECONDS_CEILING = 90  # the caller's hard timeout is 120 s
XZ_MEMLIMIT = 256 * 1024 * 1024
CHUNK = 64 * 1024
OUTCOMES = LB.CHECK_OUTCOMES + ("none",)

ISO_RE = re.compile(r"(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:\d{2})?",
                    re.ASCII)
LOCALE_FORMATS = ("%c", "%x", "%X")


class ConfigError(Exception):
    """A configuration the reader refuses: the check's outcome is error, with this as its problem."""


# ---------------------------------------------------------------------------------------------
# Rule 8: one table's checks, alone
# ---------------------------------------------------------------------------------------------

def _is_path(v: object) -> bool:
    return isinstance(v, str) and (v.startswith("/") or v.startswith("~/"))


def format_problem(fmt: str) -> str | None:
    """Why a `lines` source's strftime format is refused, or None: a locale-dependent field (%c, %x, %X),
    %s (strptime has none), or no date (%d with %b/%B/%m, or %j)."""
    for bad in LOCALE_FORMATS + ("%s",):
        if bad in fmt.replace("%%", ""):
            return f"at format {fmt!r} uses {bad}" + (", whose fields depend on the locale" if bad != "%s"
                                                       else ", which strptime does not read")
    f = fmt.replace("%%", "")
    if not ("%j" in f or ("%d" in f and any(m in f for m in ("%b", "%B", "%m")))):
        return f"at format {fmt!r} names no date (%d with %b, %B or %m, or %j)"
    return None


def source_problems(table: object, where: str, *, host: bool = False) -> list[str]:
    """Every problem of one source table alone (rule 8): its keys, their types and forms. ``host`` is the
    host's own `[repos."R".sources.<name>]`, which may also hold `public_kinds`."""
    if not isinstance(table, dict):
        return [f"{where}: a source is a table"]
    out = []
    allowed = set(SOURCE_KEYS) | ({"public_kinds"} if host else set())
    for k, v in table.items():
        if k not in allowed:
            out.append(f"{where}: {k!r} is a host-only key" if k in HOST_ONLY_KEYS
                       else f"{where}: unknown key {k!r}")
            continue
        if k == "shape" and v not in SHAPES:
            out.append(f"{where}: shape {v!r} is not one of {', '.join(SHAPES)}")
        elif k == "records" and v not in RECORDS:
            out.append(f"{where}: records {v!r} is not one of {', '.join(RECORDS)}")
        elif k == "path" and not _is_path(v):
            out.append(f"{where}: path {v!r} is neither absolute nor ~/-relative")
        elif k in LIST_KEYS or k == "public_kinds":
            if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
                out.append(f"{where}: {k} is a list of strings")
            elif k in ("match", "at") and not v:
                out.append(f"{where}: {k} is empty")
            elif k == "at":
                out += [f"{where}: {p}" for p in (format_problem(x) for x in v) if p]
            elif k == "public_kinds":
                out += [f"{where}: public kind {x!r} is not a kind token" for x in v if not NAME_RE.fullmatch(x)]
        elif k == "fields":
            if not isinstance(v, dict) or not all(isinstance(x, str) and x for x in v.values()):
                out.append(f"{where}: fields is a table of strings")
            else:
                out += [f"{where}: fields.{x} is not one of {', '.join(FIELD_KEYS)}" for x in v
                        if x not in FIELD_KEYS]
        elif k == "enabled" and not isinstance(v, bool):
            out.append(f"{where}: enabled is true or false")
        elif k == "unset":
            names = set(SOURCE_KEYS) - {"unset"} | {f"fields.{f}" for f in FIELD_KEYS}
            if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
                out.append(f"{where}: unset is a list of key names")
            else:
                out += [f"{where}: unset names {x!r}, not a source key" for x in v if x not in names]
        elif k == "kind" and not (isinstance(v, str) and NAME_RE.fullmatch(v)):
            out.append(f"{where}: kind {v!r} is not a kind token (1 to 40 of [a-z0-9-], not starting with -)")
        elif k == "tz":
            if not isinstance(v, str):
                out.append(f"{where}: tz is an IANA zone name")
            elif ZoneInfo is not None:
                try:
                    ZoneInfo(v)
                except (ZoneInfoNotFoundError, ValueError):
                    out.append(f"{where}: tz {v!r} is not a zone this host knows")
    return out


def parse_toml(text: str, what: str) -> dict:
    try:
        return tomllib.loads(text)
    except (tomllib.TOMLDecodeError, UnicodeDecodeError) as e:
        raise ConfigError(f"{what} does not parse: {e}") from None


def repo_problems(conf: dict) -> list[str]:
    """Every per-table problem of the repo's file (rule 8): any one refuses the whole file."""
    out = []
    for k in conf:
        if k not in ("sources", "profiles"):
            out.append(f"log-sources.toml: {k!r} is a host-only key" if k in ("repos", "allow", "limits")
                       or k in HOST_ONLY_KEYS else f"log-sources.toml: unknown top-level key {k!r}")
    srcs = conf.get("sources", {})
    if not isinstance(srcs, dict):
        out.append("log-sources.toml: sources is a table of source tables")
        srcs = {}
    for name, t in srcs.items():
        if not NAME_RE.fullmatch(name):
            out.append(f"sources.{name}: a source's name is 1 to 40 of [a-z0-9-], not starting with -")
        out += source_problems(t, f"sources.{name}")
    profs = conf.get("profiles", {})
    if not isinstance(profs, dict):
        return out + ["log-sources.toml: profiles is a table of profiles"]
    for p, pt in profs.items():
        where = f"profiles.{p}"
        if not PROFILE_RE.fullmatch(p):
            out.append(f"{where}: a profile's name is 1 to 64 of [A-Za-z0-9_.-]")
        if not isinstance(pt, dict):
            out.append(f"{where}: a profile is a table holding sources")
            continue
        out += [f"{where}: a profile holds sources only, not {k!r}" for k in pt if k != "sources"]
        ps = pt.get("sources", {})
        if not isinstance(ps, dict):
            out.append(f"{where}.sources is a table of source tables")
            continue
        for name, t in ps.items():
            if not NAME_RE.fullmatch(name):
                out.append(f"{where}.sources.{name}: a source's name is 1 to 40 of [a-z0-9-], not starting with -")
            out += source_problems(t, f"{where}.sources.{name}")
    return out


def host_problems(conf: dict) -> list[str]:
    """Every problem of the host's file (rules 9, 11): any one makes it unreadable, an error for every repo."""
    out = []
    for k in conf:
        if k not in ("repos", "allow", "limits"):
            out.append(f"host file: unknown top-level key {k!r}")
    repos = conf.get("repos", {})
    if not isinstance(repos, dict):
        out.append("host file: repos is a table")
        repos = {}
    seen: dict[str, str] = {}
    for r, rt in repos.items():
        if r.casefold() in seen:
            out.append(f"host file: repos {seen[r.casefold()]!r} and {r!r} are one repo (compared without case)")
        seen[r.casefold()] = r
        if not isinstance(rt, dict):
            out.append(f"host file: repos.{r!r} is a table")
            continue
        for k, v in rt.items():
            if k == "profiles":
                if not isinstance(v, list) or not all(isinstance(x, str) and PROFILE_RE.fullmatch(x) for x in v):
                    out.append(f"host file: repos.{r!r}.profiles is a list of profile names")
            elif k == "sources":
                if not isinstance(v, dict):
                    out.append(f"host file: repos.{r!r}.sources is a table")
                    continue
                for name, t in v.items():
                    out += source_problems(t, f"host file: repos.{r!r}.sources.{name}", host=True)
            else:
                out.append(f"host file: repos.{r!r}: unknown key {k!r}")
    allow = conf.get("allow", [])
    if not isinstance(allow, list):
        out.append("host file: allow is an array of tables ([[allow]])")
        allow = []
    for i, a in enumerate(allow):
        where = f"host file: allow #{i + 1}"
        if not isinstance(a, dict):
            out.append(f"{where} is a table")
            continue
        for k in a:
            if k not in ("root", "visibility", "repos", "require_repo"):
                out.append(f"{where}: unknown key {k!r}")
        if not _is_path(a.get("root")):
            out.append(f"{where}: root is an absolute or ~/-relative path")
        if a.get("visibility") not in ("public", "private"):
            out.append(f"{where}: visibility is required, public or private")
        if "repos" in a and (not isinstance(a["repos"], list) or not all(isinstance(x, str) for x in a["repos"])):
            out.append(f"{where}: repos is a list of repo ids")
        if "require_repo" in a and not isinstance(a["require_repo"], bool):
            out.append(f"{where}: require_repo is true or false")
    lim = conf.get("limits", {})
    if not isinstance(lim, dict):
        out.append("host file: limits is a table")
        lim = {}
    for k, v in lim.items():
        if k not in LIMITS:
            out.append(f"host file: limits: unknown key {k!r}")
        elif not isinstance(v, int) or isinstance(v, bool) or v <= 0:
            out.append(f"host file: limits.{k} is a positive integer")
        elif k == "max_seconds" and v > MAX_SECONDS_CEILING:
            out.append(f"host file: limits.max_seconds is at most {MAX_SECONDS_CEILING}")
    return out


# ---------------------------------------------------------------------------------------------
# Rule 9: resolution — a source's effective table for repo R on this host
# ---------------------------------------------------------------------------------------------

def merge(base: dict, layer: dict) -> dict:
    """``layer`` over ``base`` key by key (``fields`` by its own keys), its ``unset`` applied first."""
    out = {k: (dict(v) if isinstance(v, dict) else v) for k, v in base.items()}
    for u in layer.get("unset", []):
        if u.startswith("fields."):
            out.get("fields", {}).pop(u[len("fields."):], None)
        else:
            out.pop(u, None)
    for k, v in layer.items():
        if k == "unset":
            continue
        if k == "fields" and isinstance(out.get("fields"), dict):
            out["fields"] = {**out["fields"], **v}
        else:
            out[k] = dict(v) if isinstance(v, dict) else v
    return out


def host_table(host: dict, repo: str) -> tuple[str, dict] | None:
    """The host's say for ``repo``: its own `[repos."R"]` (compared without case), else `[repos."*"]`,
    else None. R's table, once present, is the whole of it: `*` is not merged in."""
    repos = host.get("repos", {})
    for k, v in repos.items():
        if k != "*" and k.casefold() == repo.casefold():
            return k, v
    return ("*", repos["*"]) if "*" in repos else None


def effective(repo_conf: dict, htab: dict, name: str, profiles: list[str]) -> dict | None:
    """The source's effective table, lowest first: the repo's default, each selected profile in order, then
    the host's table for the repo. None when no default or selected profile declares it (the host's table
    overrides but never declares). A selected profile the repo does not define is a ConfigError."""
    defined = repo_conf.get("profiles", {})
    for p in profiles:
        if p not in defined:
            raise ConfigError(f"profile {p!r} is selected on this host but log-sources.toml defines none")
    layers = []
    if name in repo_conf.get("sources", {}):
        layers.append(repo_conf["sources"][name])
    layers += [defined[p]["sources"][name] for p in profiles if name in defined[p].get("sources", {})]
    if not layers:
        return None
    out: dict = {}
    for t in layers + [htab.get("sources", {}).get(name, {})]:
        out = merge(out, t)
    return out


def effective_problems(t: dict) -> list[str]:
    """What only the effective table can show (rule 8): shape, path and records present; at for lines."""
    out = [f"no {k}" for k in ("shape", "path", "records") if k not in t]
    if t.get("records") == "lines" and not t.get("at"):
        out.append("no at (records = \"lines\" needs its formats)")
    return out


def unused_keys(t: dict) -> list[str]:
    used = ALWAYS_KEYS | SHAPE_KEYS.get(t.get("shape"), set()) | RECORD_KEYS.get(t.get("records"), set())
    return sorted(k for k in t if k not in used)


# ---------------------------------------------------------------------------------------------
# Rule 10: globs, rotations, opening, decompression
# ---------------------------------------------------------------------------------------------

def glob_match(pattern: str, relpath: str) -> bool:
    """``pattern`` against a `/`-separated relative path, segment by segment: `*`, `?`, `[…]` as fnmatchcase
    reads them within a segment, and a segment exactly `**` matching zero or more whole segments."""
    pat, segs = [], relpath.split("/")
    for part in pattern.split("/"):
        if not (part == "**" and pat and pat[-1] == "**"):  # consecutive ** are one
            pat.append(part)
    memo: dict[tuple[int, int], bool] = {}

    def m(i: int, j: int) -> bool:  # memoised: at most len(pat) * len(segs) states, never exponential
        if (i, j) not in memo:
            if i == len(pat):
                memo[i, j] = j == len(segs)
            elif pat[i] == "**":
                memo[i, j] = m(i + 1, j) or (j < len(segs) and m(i, j + 1))
            else:
                memo[i, j] = j < len(segs) and fnmatch.fnmatchcase(segs[j], pat[i]) and m(i + 1, j + 1)
        return memo[i, j]
    return m(0, 0)


_ROT_RE_CACHE: dict[str, re.Pattern] = {}


def rotation_name(base: str, name: str) -> bool:
    """Whether ``name`` (a file beside ``base``) is one of base's rotations: `<base>.<N>[.<anything>]`
    (logrotate's numbered), or `<base>` then `-` or `.` then `YYYYMMDD` or `YYYY-MM-DD` then anything
    (dateext). `<anything>` holds no `/`. The base itself is not a rotation."""
    rx = _ROT_RE_CACHE.get(base)
    if rx is None:
        b = re.escape(base)
        rx = _ROT_RE_CACHE[base] = re.compile(
            rf"{b}\.[0-9]+(?:\.[^/]+)?|{b}[-.](?:[0-9]{{8}}|[0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})[^/]*")
    return bool(rx.fullmatch(name))


class Roots:
    """The host's `[[allow]]` roots, resolved (rule 11). A file's covering roots all apply, the strictest
    winning: the most private visibility, and each must serve the repo and have require_repo met."""

    def __init__(self, allow: list[dict], repo: str, maps_repo: bool) -> None:
        self.roots = [(os.path.realpath(os.path.expanduser(a["root"])), a) for a in allow]
        self.repo, self.maps_repo = repo.casefold(), maps_repo

    def covering(self, real: str) -> list[dict]:
        return [a for r, a in self.roots if real == r or real.startswith(r.rstrip("/") + "/")]

    def judge(self, real: str) -> tuple[str | None, str]:
        """(problem or None, visibility) for a resolved path."""
        cov = self.covering(real)
        if not cov:
            return f"{real} is outside every allowed root", "private"
        for a in cov:
            if "repos" in a and self.repo not in {x.casefold() for x in a["repos"]}:
                return f"{real} lies under the root {a['root']}, which does not serve this repo", "private"
            if a.get("require_repo") and not self.maps_repo:
                return (f"{real} lies under the root {a['root']}, which requires a source mapping fields.repo",
                        "private")
        return None, ("private" if any(a["visibility"] == "private" for a in cov) else "public")


class LimitHit(Exception):
    """A read past max_files, max_bytes or max_seconds: the read stops here."""


class Budget:
    def __init__(self, limits: dict, now: float) -> None:
        self.lim = limits
        self.files = self.bytes = 0
        self.deadline = time.monotonic() + limits["max_seconds"]
        self.now = now

    def file(self) -> None:
        if self.files >= self.lim["max_files"]:
            raise LimitHit(f"max_files ({self.lim['max_files']}) reached")
        self.files += 1

    def take(self, n: int) -> None:
        self.bytes += n
        if self.bytes > self.lim["max_bytes"]:
            raise LimitHit(f"max_bytes ({self.lim['max_bytes']}) reached")
        self.tick()

    def tick(self) -> None:
        if time.monotonic() > self.deadline:
            raise LimitHit(f"max_seconds ({self.lim['max_seconds']}) reached")


def zip_entries(raw, size: int) -> int | None:
    """A zip's entry count from its end-of-central-directory record, read before the directory is parsed
    (None when it cannot be found, or the zip64 marker stands in it: the size charge bounds those)."""
    tail = min(size, 22 + 65535)
    raw.seek(size - tail)
    data = raw.read(tail)
    i = data.rfind(b"PK\x05\x06")
    if i < 0 or len(data) < i + 12:
        return None
    n = int.from_bytes(data[i + 10:i + 12], "little")
    return None if n == 0xFFFF else n


class Truncated(Exception):
    """A compressed stream that ends early or is corrupt."""


MAGIC = ((b"\x1f\x8b", "gzip"), (b"BZh", "bzip2"), (b"\xfd7zXZ\x00", "xz"), (b"\x28\xb5\x2f\xfd", "zstd"),
         (b"PK\x03\x04", "zip"))


def sniff(head: bytes) -> str | None:
    for m, kind in MAGIC:
        if head.startswith(m):
            return kind
    if len(head) >= 262 and head[257:262] == b"ustar":
        return "tar"
    return None


def _decompressor(kind: str):
    if kind == "gzip":
        return zlib.decompressobj(16 + zlib.MAX_WBITS)
    if kind == "bzip2":
        return bz2.BZ2Decompressor()
    return lzma.LZMADecompressor(memlimit=XZ_MEMLIMIT)


class Stream(io.RawIOBase):
    """A byte stream through at most one decompression layer (each call's output bounded), every byte it
    yields charged to the budget and hashed as it is read. (A tar's member bytes are charged twice, once as
    the archive's and once as the member's: max_bytes then bounds half as much tar data, the safe side.)
    A compressed layer that ends early or is corrupt raises Truncated; NUL padding after a stream's end
    (a tar block's) is its end."""

    OUT = CHUNK * 4

    def __init__(self, raw, kind: str | None, budget: Budget, head: bytes = b"") -> None:
        self.raw, self.kind, self.budget = raw, kind, budget
        self.d = _decompressor(kind) if kind else None
        self.pending, self.tail, self.out = head, b"", b""
        self.eof = False
        self.sha = hashlib.sha256()

    def readable(self) -> bool:
        return True

    def _input(self) -> bytes:
        data = self.pending or self.raw.read(CHUNK)
        self.pending = b""
        return data

    def _more(self) -> bytes:
        if self.d is None:
            got = self._input()
            self.eof = not got
        else:
            if self.d.eof:  # a stream ended: the next member of a multi-member file, or the end
                data = (self.d.unused_data or b"") + self._input()
                while data and not data.strip(b"\0"):  # NUL padding: read on, and end if only NULs remain
                    self.budget.tick()
                    data = self._input()
                if not data:
                    self.eof = True
                    return b""
                data = data.lstrip(b"\0")
                self.d, self.tail = _decompressor(self.kind), b""
            elif (not self.tail) if self.kind == "gzip" else self.d.needs_input:
                data = self._input()
                if not data:
                    raise Truncated(f"the {self.kind} stream ends early")
            else:
                data = b""
            try:
                if self.kind == "gzip":
                    got = self.d.decompress(self.tail + data, self.OUT)
                    self.tail = self.d.unconsumed_tail
                else:
                    got = self.d.decompress(data, self.OUT)
            except (zlib.error, OSError, EOFError, lzma.LZMAError, ValueError) as e:
                raise Truncated(f"the {self.kind} stream is corrupt: {e}") from None
        self.budget.take(len(got))
        return got

    def readinto(self, b) -> int:
        while not self.out and not self.eof:
            self.out = self._more()
        n = min(len(b), len(self.out))
        b[:n] = self.out[:n]
        self.sha.update(self.out[:n])
        self.out = self.out[n:]
        return n


def read_n(s: Stream, n: int) -> bytes:
    """Up to ``n`` bytes from ``s``, fewer only at its end."""
    got = b""
    while len(got) < n:
        b = s.read(n - len(got))
        if not b:
            break
        got += b
    return got


# ---------------------------------------------------------------------------------------------
# Rule 12: records
# ---------------------------------------------------------------------------------------------

def parse_iso_time(value: str, tz) -> datetime | None:
    """jsonl's `at` string, in the design's ISO subset only (never fromisoformat): an aware UTC time, or
    None when the form or a value is out of range. A time with no zone is read in ``tz`` (fold=0)."""
    m = ISO_RE.fullmatch(value)
    if not m:
        return None
    y, mo, d, h, mi, s, frac, zone = m.groups()
    try:
        dt = datetime(int(y), int(mo), int(d), int(h), int(mi), int(s or 0),  # noqa: DTZ001  # zoned below
                      int((frac or "0").ljust(6, "0")))
        if zone is None:
            dt = dt.replace(tzinfo=tz)
        elif zone == "Z":
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            sign = 1 if zone[0] == "+" else -1
            hh, mm = int(zone[1:3]), int(zone[4:6])
            if hh > 23 or mm > 59:
                return None
            dt = dt.replace(tzinfo=timezone(sign * timedelta(hours=hh, minutes=mm)))
        return dt.astimezone(timezone.utc)
    except (ValueError, OverflowError):
        return None


def _epoch(v: float) -> datetime | None:
    try:
        dt = datetime.fromtimestamp(float(v), timezone.utc)
    except (ValueError, OverflowError, OSError):
        return None
    return dt


def _dotted(obj: object, key: str) -> object:
    for part in key.split("."):
        if not isinstance(obj, dict) or part not in obj:
            return None
        obj = obj[part]
    return obj


def _str(v: object) -> str | None:
    return v if isinstance(v, str) else None


class Lines:
    """`records = "lines"`: strftime formats tried in order, the first to match locking the file in; a line
    that matches no format (or another one, once locked) continues the record before it."""

    def __init__(self, src: dict, tz, mtime: float, skip) -> None:
        self.formats = [(f, len(f.split()), not re.search(r"%[Yy]", f.replace("%%", ""))) for f in src["at"]]
        self.tz, self.kind, self.skip = tz, src.get("kind"), skip
        try:
            self.mtime = datetime.fromtimestamp(mtime, timezone.utc)
        except (ValueError, OverflowError, OSError):
            self.mtime = datetime.now(timezone.utc)
        self.locked: tuple | None = None

    def _try(self, fmt: tuple, line: str) -> tuple[datetime, str] | None:
        f, n, yearless = fmt
        parts = line.lstrip().split(None, n)
        if len(parts) < n:
            return None
        head, rest = " ".join(parts[:n]), (parts[n] if len(parts) > n else "")
        years = [self.mtime.year - i for i in range(4)] if yearless else [None]
        for y in years:
            try:
                dt = (datetime.strptime(f"{y} {head}", f"%Y {f}") if y  # noqa: DTZ007  # zoned below: tz or %z
                      else datetime.strptime(head, f))  # noqa: DTZ007
                dt = (dt.replace(tzinfo=self.tz) if dt.tzinfo is None else dt).astimezone(timezone.utc)
            except (ValueError, OverflowError):
                continue
            if y is not None and dt > self.mtime:
                continue
            return dt, rest
        return None

    def records(self, lines, max_record: int):
        cur: dict | None = None
        size = 0
        for line in lines:
            hit = None
            for fmt in ([self.locked] if self.locked else self.formats):
                hit = self._try(fmt, line)
                if hit:
                    self.locked = fmt
                    break
            if hit:
                if cur is not None and not cur.get("over"):
                    yield cur
                cur, size = {"at": hit[0], "kind": self.kind, "text": hit[1], "id": None, "repo": None}, len(line)
            elif cur is None:
                self.skip("before-first-timestamp")
            elif cur.get("over"):
                continue
            else:
                size += len(line) + 1
                if size > max_record:
                    cur["over"] = True
                    self.skip("long-record")
                else:
                    cur["text"] += "\n" + line
        if cur is not None and not cur.get("over"):
            yield cur


def jsonl_records(lines, src: dict, tz, skip):
    fields = {"at": "at", **src.get("fields", {})}
    for line in lines:
        try:
            obj = json.loads(line)
        except (ValueError, RecursionError):
            obj = None
        if not isinstance(obj, dict):
            skip("not-a-json-object")
            continue
        v = _dotted(obj, fields["at"])
        at = (parse_iso_time(v, tz) if isinstance(v, str)
              else _epoch(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None)
        if at is None:
            skip("unreadable-time")
            continue
        yield {"at": at, "kind": _str(_dotted(obj, fields["kind"])) if "kind" in fields else None,
               "text": _str(_dotted(obj, fields["text"])) if "text" in fields else line,
               "id": _str(_dotted(obj, fields["id"])) if "id" in fields else None,
               "repo": _str(_dotted(obj, fields["repo"])) if "repo" in fields else None}


def split_lines(stream, max_line: int, skip):
    """Decoded lines (UTF-8, invalid bytes replaced), a line past ``max_line`` bytes skipped and counted."""
    buf = b""
    over = False
    while True:
        chunk = stream.read(CHUNK)
        if not chunk:
            break
        buf += chunk
        while True:
            i = buf.find(b"\n")
            if i < 0:
                if len(buf) > max_line:
                    if not over:
                        skip("long-line")
                    over, buf = True, b""
                break
            line, buf = buf[:i], buf[i + 1:]
            if over or len(line) > max_line:
                if not over:
                    skip("long-line")
                over = False
                continue
            yield line.rstrip(b"\r").decode("utf-8", "replace")
    if buf and not over:
        if len(buf) > max_line:
            skip("long-line")
        else:
            yield buf.rstrip(b"\r").decode("utf-8", "replace")


# ---------------------------------------------------------------------------------------------
# The read: rules 10–12 over one source
# ---------------------------------------------------------------------------------------------

class Reader:
    def __init__(self, src: dict, name: str, repo: str, roots: Roots, limits: dict, start: datetime,
                 public_kinds: set[str]) -> None:
        self.src, self.name, self.repo = src, name, repo
        self.roots, self.lim, self.start = roots, limits, start
        self.public_kinds = public_kinds
        self.tz = ZoneInfo(src["tz"]) if src.get("tz") and ZoneInfo else timezone.utc
        self.records: list[dict] = []
        self.errors: list[str] = []
        self.skipped: dict[str, int] = {}
        self.seen: set[str] = set()
        self.budget = Budget(limits, time.time())
        self.listing: list[str] | None = None
        self.keep = None  # run_check's: drops, as it reads, a record count_host_log would never count

    def skip(self, why: str, n: int = 1) -> None:
        self.skipped[why] = self.skipped.get(why, 0) + n

    # --- which files -------------------------------------------------------------------------
    def candidates(self) -> list[str]:
        shape, path = self.src["shape"], os.path.expanduser(self.src["path"])
        if shape == "file":
            if not os.path.lexists(path):
                raise ConfigError(f"source {self.name}: path {self.src['path']} does not exist")
            return [path]
        if shape == "rotated":
            d, base = os.path.split(path)
            try:
                names = os.listdir(d)
            except OSError:
                names = []
            found = [n for n in names if n == base or rotation_name(base, n)]
            if not found:
                raise ConfigError(f"source {self.name}: neither {self.src['path']} nor a rotation of it exists")
            ex = self.src.get("exclude", [])
            return [os.path.join(d, n) for n in sorted(found) if not any(glob_match(g, n) for g in ex)]
        if not os.path.isdir(path):
            raise ConfigError(f"source {self.name}: path {self.src['path']} is not a directory that exists")
        top = os.path.realpath(path)
        match, ex = self.src.get("match", ["**/*"]), self.src.get("exclude", [])
        out = []
        for d, dirs, files in os.walk(top, followlinks=False):
            self.budget.tick()
            dirs.sort()
            for f in sorted(files):
                self.budget.tick()
                rel = os.path.relpath(os.path.join(d, f), top).replace(os.sep, "/")
                if any(glob_match(g, rel) for g in match) and not any(glob_match(g, rel) for g in ex):
                    out.append(os.path.join(d, f))
        return out

    # --- the whole read ----------------------------------------------------------------------
    def run(self) -> None:
        listed = []
        for p in self.listing if self.listing is not None else self.candidates():
            self.budget.tick()
            real = os.path.realpath(p)
            try:
                st = os.stat(real)
            except FileNotFoundError:
                self.skip("vanished")
                continue
            except OSError as e:
                self.errors.append(f"{p}: cannot be read: {e.strerror}")
                continue
            listed.append((st.st_mtime, p, real))
        listed.sort(key=lambda x: (-x[0], x[1]))
        for mtime, p, real in listed:
            if mtime < self.start.timestamp():
                continue  # nothing in it can count (rule 10)
            try:
                self.one_file(p, real)
            except LimitHit as e:
                self.errors.append(str(e))
                return
            except Exception as e:  # noqa: BLE001 — one file's failure is its error; the read goes on (rule 10)
                self.errors.append(f"{p}: cannot be read: {type(e).__name__}: {e}")

    def one_file(self, p: str, real: str) -> None:
        problem, vis = self.roots.judge(real)
        if problem:
            self.errors.append(problem)
            return
        try:
            fd = os.open(real, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
        except FileNotFoundError:
            self.skip("vanished")
            return
        except OSError as e:
            self.errors.append(f"{p}: cannot be opened: {e.strerror}")
            return
        with os.fdopen(fd, "rb", buffering=0) as raw:
            fst = os.fstat(fd)
            if not stat.S_ISREG(fst.st_mode):
                self.errors.append(f"{p}: not a regular file")
                return
            try:
                st = os.stat(real)
            except OSError:
                self.skip("vanished")
                return
            if (st.st_dev, st.st_ino) != (fst.st_dev, fst.st_ino):
                self.errors.append(f"{p}: the file opened is not the one its path resolved to")
                return
            proc = f"/proc/self/fd/{fd}"
            if os.path.isdir("/proc/self/fd"):
                again, _ = self.roots.judge(os.path.realpath(proc))
                if again:
                    self.errors.append(again)
                    return
            self.budget.file()
            head = raw.read(512)
            kind = sniff(head)
            young = self.budget.now - fst.st_mtime < self.lim["settle_seconds"]
            if kind == "zstd":
                self.errors.append(f"{p}: zstd, which the standard library cannot read")
                return
            if self.src["shape"] == "archives":
                self.archive(p, raw, head, kind, young, vis)
                return
            if kind in ("zip", "tar"):
                self.errors.append(f"{p}: an archive in a {self.src['shape']} source: declare it as archives")
                return
            s = Stream(raw, kind if kind in ("gzip", "bzip2", "xz") else None, self.budget, head)
            if s.d is not None:
                try:
                    inner = read_n(s, 512)
                except Truncated as e:
                    self.cut(p, e, young)
                    return
                if sniff(inner) in ("zip", "tar"):
                    self.errors.append(f"{p}: an archive in a {self.src['shape']} source: declare it as archives")
                    return
                s.out = inner + s.out
                s.sha = hashlib.sha256()  # restart: the sniffed bytes are hashed again as they are read
            self.read_stream(p, s, fst.st_mtime, vis, young, compressed=s.d is not None)

    def cut(self, name: str, e: Exception, young: bool) -> None:
        """A compressed file or archive that ends early or is corrupt: skipped and counted while younger
        than settle_seconds (it may still be being written), else an error."""
        if young:
            self.skip("young-truncated")
        else:
            self.errors.append(f"{name}: {e}")

    def archive(self, p: str, raw, head: bytes, kind: str | None, young: bool, vis: str) -> None:
        outer = Stream(raw, kind if kind in ("gzip", "bzip2", "xz") else None, self.budget, head)
        members = self.src.get("members", ["**/*"])
        try:
            if outer.d is not None:
                inner = read_n(outer, 512)
                ik = sniff(inner)
                if ik == "zip":  # a compressed zip: held in memory (bounded by max_bytes), zip needs to seek
                    data = inner + outer.read()
                    self.zip_members(p, io.BytesIO(data), members, vis, young)
                    return
                if ik != "tar":
                    self.errors.append(f"{p}: not a zip or tar archive")
                    return
                outer.out = inner + outer.out
                self.tar_members(p, outer, members, vis, young)
            elif kind == "zip":
                size = os.fstat(raw.fileno()).st_size
                self.budget.take(size)  # the central directory is parsed whole: its file is charged first
                n = zip_entries(raw, size)
                if n is not None and n > self.lim["max_files"]:
                    raise LimitHit(f"max_files ({self.lim['max_files']}) reached: {p} holds {n} entries")
                raw.seek(0)
                self.zip_members(p, raw, members, vis, young)
            elif kind == "tar":
                self.tar_members(p, outer, members, vis, young)
            else:
                self.errors.append(f"{p}: not a zip or tar archive")
        except Truncated as e:
            if young:
                self.skip("young-truncated")
            else:
                self.errors.append(f"{p}: {e}")
        except (zipfile.BadZipFile, tarfile.TarError, EOFError) as e:
            if young:
                self.skip("young-truncated")
            else:
                self.errors.append(f"{p}: a corrupt archive: {e}")

    def zip_members(self, p: str, fobj, members: list[str], vis: str, young: bool) -> None:
        with zipfile.ZipFile(fobj) as zf:
            for info in zf.infolist():
                self.budget.tick()
                if info.is_dir() or not any(glob_match(g, info.filename) for g in members):
                    continue
                try:  # a zip member's time is local and zoneless: skipped only a day before the first instant
                    mt = datetime(*info.date_time, tzinfo=timezone.utc)
                except ValueError:
                    mt = None
                if mt is not None and mt < self.start - timedelta(days=1):
                    continue
                self.budget.file()
                try:
                    with zf.open(info) as m:
                        self.member(f"{p}!{info.filename}", m, (mt or self.start).timestamp() + 86400, vis, young)
                except LimitHit:
                    raise
                except Exception as e:  # noqa: BLE001 — encrypted, an unsupported method, a corrupt member
                    self.errors.append(f"{p}!{info.filename}: cannot be read: {type(e).__name__}: {e}")

    def tar_members(self, p: str, stream, members: list[str], vis: str, young: bool) -> None:
        with tarfile.open(fileobj=stream, mode="r|") as tf:
            for ti in tf:
                self.budget.tick()
                if not any(glob_match(g, ti.name) for g in members):
                    continue
                if not ti.isreg() or ti.issparse():  # a sparse member's holes are bytes nothing charged
                    self.skip("tar-member-not-regular")
                    continue
                if ti.mtime < self.start.timestamp():
                    continue
                self.budget.file()
                m = tf.extractfile(ti)
                if m is not None:
                    self.member(f"{p}!{ti.name}", m, ti.mtime, vis, young)

    def member(self, name: str, m, mtime: float, vis: str, young: bool) -> None:
        """An archive member, read in memory, never extracted: one layer of its own compression."""
        head = m.read(512)
        kind = sniff(head)
        if kind in ("zip", "tar"):
            self.skip("archive-in-archive")
            return
        if kind == "zstd":
            self.errors.append(f"{name}: zstd, which the standard library cannot read")
            return
        s = Stream(m, kind, self.budget, head)
        if s.d is not None:
            try:
                inner = read_n(s, 512)
            except Truncated as e:
                self.cut(name, e, young)
                return
            if sniff(inner) is not None:
                self.skip("archive-in-archive" if sniff(inner) in ("zip", "tar") else "compressed-in-compressed")
                return
            s.out = inner + s.out
            s.sha = hashlib.sha256()
        self.read_stream(name, s, mtime, vis, young, compressed=s.d is not None)

    def read_stream(self, name: str, s: Stream, mtime: float, vis: str, young: bool, *, compressed: bool) -> None:
        got: list[dict] = []
        whole = True
        recs = (Lines(self.src, self.tz, mtime, self.skip).records(split_lines(s, self.lim["max_line"], self.skip),
                                                                    self.lim["max_record"])
                if self.src["records"] == "lines" else
                jsonl_records(split_lines(s, self.lim["max_line"], self.skip), self.src, self.tz, self.skip))
        fields = self.src.get("fields", {}) if self.src["records"] == "jsonl" else {}
        try:
            for r in recs:
                if "repo" in fields and (r["repo"] is None or r["repo"].casefold() != self.repo.casefold()):
                    continue
                r["public"] = vis == "public" or (r["kind"] is not None and r["kind"] in self.public_kinds)
                if self.keep is None or self.keep(r):  # a record that cannot count is not held (memory)
                    got.append(r)
        except Truncated as e:
            whole = False
            if young and compressed:
                self.skip("young-truncated")
                return
            self.cut(name, e, young)
        except LimitHit:
            self.records += got  # cut short: what was read counts, and it has no whole hash
            raise
        if whole:
            h = s.sha.hexdigest()
            if h in self.seen:
                self.skip("duplicate")
                return
            self.seen.add(h)
        self.records += got


# ---------------------------------------------------------------------------------------------
# check and validate (rule 13)
# ---------------------------------------------------------------------------------------------

def result(outcome: str, *, count: int = 0, evidence: str | None = None, skipped: dict | None = None,
           problem: str | None = None) -> dict:
    return {"outcome": outcome, "count": count, "evidence": evidence, "skipped": dict(sorted((skipped or {}).items())),
            "problem": problem}


def run_check(line: str, *, repo_text: str, host_path: str, repo: str, visibility: str,
              since: str | None, profiles: list[str] | None = None) -> dict:
    """One `host-log` check's outcome on this host, by rule 2's order of tests."""
    chk = LB.parse_check(line)
    if chk.get("type") != "host-log":
        return result("error", problem=f"not a host-log check: {line!r}")
    if chk.get("problem"):
        return result("error", problem=f"the check is refused: {chk['problem']}")
    # (0) the host's own file
    if not os.path.exists(host_path):
        return result("none", problem="no host file")
    try:
        with open(host_path, "rb") as f:
            host = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError, UnicodeDecodeError) as e:
        return result("error", problem=f"the host file cannot be read: {e}")
    hp = host_problems(host)
    if hp:
        return result("error", problem="; ".join(hp))
    # (1) the host's table for this repo
    ht = host_table(host, repo)
    if ht is None:
        return result("none", problem=f"the host file has no table for {repo}")
    htab = ht[1]
    # (2) the repo's file, and the profiles selected
    try:
        rc = parse_toml(repo_text, "log-sources.toml")
    except ConfigError as e:
        return result("error", problem=str(e))
    rp = repo_problems(rc)
    if rp:
        return result("error", problem="; ".join(rp))
    sel = profiles if profiles is not None else list(htab.get("profiles", []))
    name = chk["source"]
    try:
        src = effective(rc, htab, name, sel)
    except ConfigError as e:
        return result("error", problem=str(e))
    # (3) declared, and enabled
    if src is None:
        return result("none", problem=f"source {name} is not declared for {repo} on this host")
    if src.get("enabled", True) is False:
        return result("none", problem=f"source {name} is disabled for {repo} on this host")
    # (4) the remaining configuration errors, before anything is read
    if not since:
        return result("error", problem="since unknown (the gate has no gate added line)")
    ep = effective_problems(src)
    if ep:
        return result("error", problem=f"source {name}: " + "; ".join(ep))
    maps_repo = src["records"] == "jsonl" and "repo" in src.get("fields", {})
    has_kind = (src["records"] == "jsonl" and "kind" in src.get("fields", {})) or \
               (src["records"] == "lines" and "kind" in src)
    if chk["kind"] is not None and not has_kind:
        return result("error", problem=f"source {name} records no kind")
    public_only = visibility != "private"
    roots = Roots(host.get("allow", []), repo, maps_repo)
    lim = {**LIMITS, **host.get("limits", {})}
    try:
        start = LB.first_instant(since)
        reader = Reader(src, name, repo, roots, lim, start, set(src.get("public_kinds", [])))
        reader.keep = lambda r: (r["at"] >= start and isinstance(r["text"], str) and chk["text"] in r["text"]
                                 and (chk["kind"] is None or r["kind"] == chk["kind"])
                                 and (not public_only or r["public"] is True))
        base = os.path.expanduser(src["path"])
        anchor = os.path.dirname(base) if src["shape"] == "rotated" and not os.path.lexists(base) else base
        reader.listing = reader.candidates()  # a missing path is a configuration error (rule 10)
        bad, vis = roots.judge(os.path.realpath(anchor))
        if bad:
            return result("error", problem=f"source {name}: {bad}")
        if public_only and vis == "private" and not reader.public_kinds:
            return result("error", problem=f"source {name} is private")
        # (5) reading
        reader.run()
    except ConfigError as e:
        return result("error", problem=str(e))
    except LimitHit as e:  # a limit met while listing, before any file was read
        return result("error", skipped=reader.skipped, problem=str(e))
    except (LB.Refused, ValueError) as e:
        return result("error", problem=str(e))
    counted = LB.count_host_log(reader.records, chk, since, public_only=public_only)
    if counted["outcome"] == "passed":
        return result("passed", count=counted["count"], evidence=counted["evidence"], skipped=reader.skipped)
    if reader.errors:
        return result("error", count=counted["count"], skipped=reader.skipped, problem="; ".join(reader.errors[:5]))
    return result("not yet", count=counted["count"], skipped=reader.skipped)


def validate(repo_path: str, ledger: str | None) -> tuple[list[str], list[str]]:
    """(problems, warnings) of the repo's file, and with ``ledger`` of its open entries' host-log checks."""
    try:
        text = Path(repo_path).read_text(encoding="utf-8") if os.path.exists(repo_path) else ""
    except (OSError, UnicodeDecodeError) as e:
        return [f"{repo_path}: {e}"], []
    led = None
    if ledger:
        try:
            import ledgerboard.ledger as LBL
            led = LBL.Ledger.open(ledger).texts()[0]
        except Exception as e:  # noqa: BLE001 — a ledger that cannot be read fails validate
            probs, warns = validate_text(text, repo_path, None)
            return probs + [f"{ledger}: not read — {e}"], warns
    return validate_text(text, repo_path, led)


def validate_text(text: str, where: str, ledger_text: str | None) -> tuple[list[str], list[str]]:
    """``validate()`` on texts: the repo file's ``text`` (``where`` names it in a problem) and, given, the
    ledger's open text — so the merge gate can judge a commit's files without a checkout (TD-230)."""
    try:
        rc = parse_toml(text, where)
    except ConfigError as e:
        return [str(e)], []
    probs, warns = repo_problems(rc), []
    if probs:
        return probs, warns
    profs = rc.get("profiles", {})
    declared = set(rc.get("sources", {}))
    for p in profs.values():
        declared |= set(p.get("sources", {}))
    for name in sorted(declared):
        views = ([("defaults", effective(rc, {}, name, []))] if name in rc.get("sources", {}) else []) + \
                [(f"profile {p}", effective(rc, {}, name, [p])) for p in profs if name in profs[p].get("sources", {})]
        for where, t in views:
            u = unused_keys(t)
            if u:
                warns.append(f"source {name} ({where}): {', '.join(u)} unused by its shape and records")
        if name in rc.get("sources", {}) and rc["sources"][name].get("enabled", True) is False \
                and not any(t.get("enabled", True) for w, t in views if w != "defaults"):
            warns.append(f"source {name} is enabled = false in the defaults and enabled by no profile")
    if ledger_text is not None:
        import event_checks as EC  # sibling SYNC script: the open entries' event gates, read once
        for g in EC.gates(ledger_text):
            c = g["check"]
            if c and c.get("type") == "host-log" and not c.get("problem") and c["source"] not in declared:
                probs.append(f"{g['id']}: event ({g['name']}) names source {c['source']}, "
                             "which no default or profile in log-sources.toml declares")
    return probs, warns


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="hostlog.py", description="the host-log check's reader (TD-230)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="one host-log check's outcome on this host, as one JSON object")
    c.add_argument("--repo-config", required=True, help="the repo's log-sources.toml, or - for stdin")
    c.add_argument("--host-config", required=True, help="this host's file (none there: no outcome)")
    c.add_argument("--repo", required=True, help="the ledger's <repo> id")
    c.add_argument("--visibility", required=True, choices=("public", "internal", "private"),
                   help="the ledger repo's visibility; internal is read as public")
    c.add_argument("--since", help="gate_added()'s date, YYYY-MM-DD (absent: error, since unknown)")
    c.add_argument("--profiles", help="a,b: replaces the host's profile list for this run")
    c.add_argument("line", help="the check line: host-log <source> [kind <k>] [times <N>] \"<text>\"")
    v = sub.add_parser("validate", help="the repo file's checks, and with --ledger its gates' sources")
    v.add_argument("--repo-config", required=True)
    v.add_argument("--ledger", help="a v2 ledger directory: fail a host-log check whose source is declared nowhere")
    a = ap.parse_args(argv)
    if tomllib is None:
        if a.cmd == "check":
            print(json.dumps(result("none", problem="this Python has no tomllib (3.11+)")))
            return 0
        print("hostlog.py validate: this Python has no tomllib (3.11+)", file=sys.stderr)
        return 2
    try:
        locale.setlocale(locale.LC_TIME, "C")  # %a %b %p in English, the same on every host
    except locale.Error:
        pass
    if a.cmd == "check":
        try:
            if a.repo_config == "-":
                repo_text = sys.stdin.buffer.read().decode("utf-8")
            else:
                p = Path(a.repo_config)
                repo_text = p.read_text(encoding="utf-8") if p.exists() else ""
        except (OSError, UnicodeDecodeError) as e:
            print(json.dumps(result("error", problem=f"log-sources.toml cannot be read: {e}")))
            return 0
        if a.since is not None:
            try:
                LB.utc_day(a.since, "--since")
            except (LB.Refused, ValueError) as e:
                print(json.dumps(result("error", problem=str(e))))
                return 0
        profiles = None if a.profiles is None else [x for x in a.profiles.split(",") if x]
        try:
            out = run_check(a.line, repo_text=repo_text, host_path=os.path.expanduser(a.host_config), repo=a.repo,
                            visibility=a.visibility, since=a.since, profiles=profiles)
        except Exception as e:  # noqa: BLE001 — every outcome is one JSON object; a crash is an error
            out = result("error", problem=f"the reader failed: {type(e).__name__}: {e}")
        print(json.dumps(out))
        return 0
    probs, warns = validate(a.repo_config, a.ledger)
    for w in warns:
        print(f"warning: {w}")
    for p in probs:
        print(f"refused: {p}")
    if not probs:
        print(f"hostlog.py validate: {a.repo_config} ok" + (f", every host-log gate in {a.ledger} declared"
                                                             if a.ledger else ""))
    return 1 if probs else 0


if __name__ == "__main__":
    sys.exit(main())
