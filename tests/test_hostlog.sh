#!/usr/bin/env bash
# TD-230 (slice 2): hostlog.py, the host-log check's reader (ShiftLead/ledgerboard docs/plans/TD-045-host-log.md,
# rules 8–13; its *The fixture cases* → *The reader's tests*). Every case builds a repo file, a host file and a
# tree of logs at run time under a temp dir (archives and compressed files made with the standard library,
# modification times set by the case), with dates derived from the run date (TD-24). Offline; HOME is temp.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$HOME"

python3 - "$S" "$TMP" "$DC" <<'PY'
import bz2, gzip, io, json, lzma, os, subprocess, sys, tarfile, time, zipfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

S, TMP, DC = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
sys.path.insert(0, S)
import hostlog as H  # noqa: E402

PASS = FAIL = 0
SINCE = date.today() - timedelta(days=10)
FIRST = datetime(SINCE.year, SINCE.month, SINCE.day, tzinfo=timezone.utc) + timedelta(days=1)
NOW = time.time()


def at(hours: float = 1.0) -> datetime:
    return FIRST + timedelta(hours=hours)


def z(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def tok(dt: datetime) -> str:
    return dt.strftime("%Y%m%dT%H%M%SZ")


def lines(*recs) -> bytes:
    """`lines` records: (hours, text) → `<iso Z> <text>`."""
    return "".join(f"{z(at(h))} {t}\n" for h, t in recs).encode()


def jl(*objs) -> bytes:
    return "".join(json.dumps(o) + "\n" for o in objs).encode()


def zip_bytes(members, date_time=None) -> bytes:
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in members:
            zi = zipfile.ZipInfo(name, date_time or datetime.now().timetuple()[:6])
            zi.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(zi, data)
    return b.getvalue()


def tar_bytes(members, comp="gz") -> bytes:
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode=f"w:{comp}" if comp else "w") as tf:
        for name, data in members:
            ti = tarfile.TarInfo(name)
            ti.size, ti.mtime = len(data), int(NOW)
            tf.addfile(ti, io.BytesIO(data))
    return b.getvalue()


N = [0]


def case(title, *, files=None, repo="", host=None, line='host-log s "boom"', since=SINCE.isoformat(),
         vis="private", profiles=None, mtimes=None, setup=None, repo_id="acme/app"):
    """Build one case's tree and run the check in-process. ``host`` None: a default host file allowing the
    logs dir privately with a [repos."*"] table; ``host`` False: no host file. ``{L}`` in either file is
    the logs dir, ``{T}`` the case's dir."""
    N[0] += 1
    d = TMP / f"c{N[0]}"
    L = d / "logs"
    L.mkdir(parents=True)
    for rel, data in (files or {}).items():
        p = L / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    for rel, mt in (mtimes or {}).items():
        os.utime(L / rel, (mt, mt))
    if setup:
        setup(d, L)
    hp = d / "host.toml"
    if host is None:
        host = '[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'
    if host is not False:
        hp.write_text(host.replace("{L}", str(L)).replace("{T}", str(d)))
    return H.run_check(line, repo_text=repo.replace("{L}", str(L)).replace("{T}", str(d)), host_path=str(hp),
                       repo=repo_id, visibility=vis, since=since, profiles=profiles)


def expect(title, got, **want):
    global PASS, FAIL
    bad = {k: (got.get(k), v) for k, v in want.items()
           if not (v(got.get(k)) if callable(v) else got.get(k) == v)}
    if bad:
        FAIL += 1
        print(f"FAIL: {title}: {bad} (got {got})")
    else:
        PASS += 1
        print(f"PASS: {title}")


def has(*words):
    return lambda v: isinstance(v, str) and all(w in v for w in words)


FILE = '[sources.s]\nshape = "file"\npath = "{L}/app.log"\nrecords = "lines"\nat = ["%Y-%m-%dT%H:%M:%SZ"]\n'
DIR = '[sources.s]\nshape = "directory"\npath = "{L}"\nrecords = "lines"\nat = ["%Y-%m-%dT%H:%M:%SZ"]\n'
JSONL = ('[sources.s]\nshape = "file"\npath = "{L}/ev.jsonl"\nrecords = "jsonl"\n'
         'fields = { at = "at", kind = "kind", text = "text", id = "id", repo = "repo" }\n')
ARCH = ('[sources.s]\nshape = "archives"\npath = "{L}"\nmatch = ["*.zip", "*.tar.gz"]\nmembers = ["**/*.log"]\n'
        'records = "lines"\nat = ["%Y-%m-%dT%H:%M:%SZ"]\n')

# --- shapes -----------------------------------------------------------------------------------------
expect("one file: passed, the evidence its record's time", case("file", files={"app.log": lines((1, "boom"))}, repo=FILE),
       outcome="passed", count=1, evidence=f"s@{tok(at(1))}")
expect("one file without the text: not yet",
       case("file2", files={"app.log": lines((1, "fine"))}, repo=FILE), outcome="not yet", count=0)
expect("a directory with match and exclude: only matching files count",
       case("dir", files={"a.log": lines((1, "boom")), "b.txt": lines((2, "boom")), "x/c.log": lines((3, "boom")),
                          "x/skip.log": lines((4, "boom"))},
            repo=DIR + 'match = ["**/*.log"]\nexclude = ["x/skip.log"]\n', line='host-log s times 9 "boom"'),
       outcome="not yet", count=2)
ROT = '[sources.s]\nshape = "rotated"\npath = "{L}/sys.log"\nrecords = "lines"\nat = ["%Y-%m-%dT%H:%M:%SZ"]\n'
expect("rotated, numbered: the base, .1 plain and .2.gz all read",
       case("rot", files={"sys.log": lines((3, "boom")), "sys.log.1": lines((2, "boom")),
                          "sys.log.2.gz": gzip.compress(lines((1, "boom"))), "other.log": lines((1, "boom"))},
            repo=ROT, line='host-log s times 9 "boom"'), outcome="not yet", count=3)
expect("rotated, dated (dateext, both formats): read",
       case("rotd", files={"sys.log-20260101": lines((1, "boom")), "sys.log-2026-01-02.gz": gzip.compress(lines((2, "boom"))),
                          "sys.logX": lines((3, "boom"))}, repo=ROT, line='host-log s times 9 "boom"'),
       outcome="not yet", count=2)
expect("rotation_name: numbered and dated yes, a lookalike no",
       {"ok": [H.rotation_name("a.log", n) for n in ("a.log.1", "a.log.12.gz", "a.log-20250101", "a.log.2025-01-01.xz",
                                                     "a.log", "a.logx", "a.log.x", "b.log.1", "a.log-2025")]},
       ok=[True, True, True, True, False, False, False, False, False])
expect("archives: a zip and a tar.gz, members by glob",
       case("arch", files={"a.zip": zip_bytes([("x/run.log", lines((1, "boom"))), ("x/run.txt", lines((2, "boom")))]),
                          "b.tar.gz": tar_bytes([("y/run.log", lines((3, "boom")))]), "c.log": lines((4, "boom"))},
            repo=ARCH, line='host-log s times 9 "boom"'), outcome="not yet", count=2)
expect("an archive member named ../../x is read, never written",
       case("trav", files={"a.zip": zip_bytes([("../../x.log", lines((1, "boom")))])},
            repo=ARCH.replace('members = ["**/*.log"]', 'members = ["**"]')),
       outcome="passed", count=1)
expect("... and nothing was written outside the case", {"x": (TMP / "x.log").exists() or (TMP / f"c{N[0]}" / "x.log").exists()}, x=False)

# --- compression by content ---------------------------------------------------------------------------
expect("a .log that is gzip is read as gzip", case("gzl", files={"a.log": gzip.compress(lines((1, "boom")))}, repo=DIR),
       outcome="passed")
expect("a .gz that is plain text is read as text", case("gzp", files={"a.gz": lines((1, "boom"))}, repo=DIR), outcome="passed")
expect("bzip2", case("bz", files={"a": bz2.compress(lines((1, "boom")))}, repo=DIR), outcome="passed")
expect("xz", case("xz", files={"a": lzma.compress(lines((1, "boom")))}, repo=DIR), outcome="passed")
expect("zstd: an error naming the format",
       case("zst", files={"a.zst": b"\x28\xb5\x2f\xfd" + b"\0" * 20}, repo=DIR), outcome="error", problem=has("zstd"))
expect("a zip in a directory source: an error",
       case("zipdir", files={"a.zip": zip_bytes([("r.log", lines((1, "boom")))])}, repo=DIR),
       outcome="error", problem=has("an archive in a directory source"))
expect("a tar.gz in a file source: an error",
       case("tgzfile", files={"app.log": tar_bytes([("r.log", lines((1, "boom")))])}, repo=FILE),
       outcome="error", problem=has("an archive in a file source"))
expect("a gzip inside a zip: read",
       case("gzinzip", files={"a.zip": zip_bytes([("r.log", gzip.compress(lines((1, "boom"))))])}, repo=ARCH), outcome="passed")
expect("a zip inside a zip: skipped and counted",
       case("zipzip", files={"a.zip": zip_bytes([("r.log", zip_bytes([("i.log", lines((1, "boom")))]))])}, repo=ARCH),
       outcome="not yet", skipped={"archive-in-archive": 1})
expect("a gzip of a gzip inside a zip: skipped (one layer only)",
       case("gzgz", files={"a.zip": zip_bytes([("r.log", gzip.compress(gzip.compress(lines((1, "boom")))))])}, repo=ARCH),
       outcome="not yet", skipped={"compressed-in-compressed": 1})

# --- opening -----------------------------------------------------------------------------------------
expect("a FIFO under a root: an error, never blocking",
       case("fifo", files={"a.log": lines((1, "fine"))}, repo=DIR, setup=lambda d, L: os.mkfifo(L / "p.log")),
       outcome="error", problem=has("not a regular file"))


def outside_link(d, L):
    (d / "out").mkdir()
    (d / "out" / "secret.log").write_bytes(lines((1, "boom")))
    os.symlink(d / "out" / "secret.log", L / "link.log")


expect("a symlink to a file outside every root: an error",
       case("symout", repo=DIR, setup=outside_link), outcome="error", problem=has("outside every allowed root"))


def linked_dir(d, L):
    (L / "real").mkdir()
    (L / "real" / "a.log").write_bytes(lines((1, "boom")))
    os.symlink(L / "real", L / "via")


expect("a symlinked directory is not followed (the file is read once, by its real path)",
       case("symdir", repo=DIR, setup=linked_dir, line='host-log s times 9 "boom"'), outcome="not yet", count=1)

_cand = H.Reader.candidates
H.Reader.candidates = lambda self: _cand(self) + [os.path.join(os.path.expanduser(self.src["path"]), "gone.log")]
expect("a file that vanishes between listing and opening: skipped",
       case("vanish", files={"a.log": lines((1, "boom"))}, repo=DIR), outcome="passed", skipped={"vanished": 1})
H.Reader.candidates = _cand

# --- lock-in and records --------------------------------------------------------------------------------
TWO = DIR.replace('at = ["%Y-%m-%dT%H:%M:%SZ"]', 'at = ["%Y-%m-%dT%H:%M:%SZ", "%b %d %H:%M:%S"]')
syslog_line = at(1).strftime("%b %d %H:%M:%S")
expect("lock-in: a continuation opening with the other listed format stays a continuation",
       case("lock", files={"a.log": f"{z(at(1))} first\n{syslog_line} quoted boom\n".encode()}, repo=TWO,
            line='host-log s times 2 "boom"'),
       outcome="not yet", count=1)
expect("mixed formats: the file is read with the first that matched",
       case("mixed", files={"a.log": f"{syslog_line} boom one\n{z(at(2))} boom two\n".encode()}, repo=TWO,
            line='host-log s times 2 "boom"'), outcome="not yet", count=1)
expect("lines before the first timestamp: skipped and counted",
       case("pre", files={"a.log": b"banner\n" + lines((1, "boom"))}, repo=DIR),
       outcome="passed", skipped={"before-first-timestamp": 1})
expect("jsonl: dotted fields, an id and a repo",
       case("jsonl", files={"ev.jsonl": jl({"e": {"at": z(at(1)), "k": "press"}, "msg": "Apply x", "rid": "r-1", "repo": "ACME/app"})},
            repo='[sources.s]\nshape = "file"\npath = "{L}/ev.jsonl"\nrecords = "jsonl"\n'
                 'fields = { at = "e.at", kind = "e.k", text = "msg", id = "rid", repo = "repo" }\n',
            line='host-log s kind press "Apply"'), outcome="passed", evidence="s/r-1")
expect("jsonl: an epoch at in milliseconds is skipped",
       case("ms", files={"ev.jsonl": jl({"at": at(1).timestamp() * 1000, "text": "boom"}, {"at": at(2).timestamp(), "text": "boom"})},
            repo=JSONL.replace(', repo = "repo"', "")), outcome="passed", count=1, skipped={"unreadable-time": 1})
expect("jsonl: a line that is not an object, skipped",
       case("notobj", files={"ev.jsonl": b"[1]\nnot json\n" + jl({"at": z(at(1)), "text": "boom"})},
            repo=JSONL.replace(', repo = "repo"', "")), outcome="passed", skipped={"not-a-json-object": 2})
expect("jsonl: an at outside the ISO subset (a basic +0100 offset) is skipped",
       case("iso", files={"ev.jsonl": jl({"at": at(1).strftime("%Y-%m-%dT%H:%M:%S+0100"), "text": "boom"})},
            repo=JSONL.replace(', repo = "repo"', "")), outcome="not yet", skipped={"unreadable-time": 1})
expect("parse_iso_time: Z, an offset, a fraction padded; month 13 refused",
       {"v": [str(H.parse_iso_time(x, timezone.utc)) for x in
              ("2026-01-02T03:04:05Z", "2026-01-02 03:04+02:00", "2026-01-02T03:04:05.5Z", "2026-13-02T03:04:05Z")]},
       v=["2026-01-02 03:04:05+00:00", "2026-01-02 01:04:00+00:00", "2026-01-02 03:04:05.500000+00:00", "None"])

# --- reading ---------------------------------------------------------------------------------------------
old = FIRST.timestamp() - 3600
expect("a file last written before the first instant is not read",
       case("old", files={"a.log": lines((1, "boom"))}, repo=DIR, mtimes={"a.log": old}), outcome="not yet", count=0)
expect("a zip member within its day of slack is read; one older is not",
       case("zipslack", files={"a.zip": zip_bytes([("r.log", lines((1, "boom")))],
                                                   date_time=(FIRST - timedelta(hours=12)).timetuple()[:6]),
                               "b.zip": zip_bytes([("r.log", lines((2, "boom")))],
                                                  date_time=(FIRST - timedelta(days=3)).timetuple()[:6])},
            repo=ARCH, line='host-log s times 9 "boom"'), outcome="not yet", count=1)
three = {"a.log": jl({"at": z(at(3)), "text": "boom", "id": "c"}), "b.log": jl({"at": z(at(1)), "text": "boom", "id": "a"}),
         "c.log": jl({"at": z(at(2)), "text": "boom", "id": "b"})}
JDIR = '[sources.s]\nshape = "directory"\npath = "{L}"\nrecords = "jsonl"\nfields = { id = "id" }\n'
e1 = case("order1", files=three, repo=JDIR, line='host-log s times 2 "boom"',
          mtimes={"a.log": NOW - 30, "b.log": NOW - 20, "c.log": NOW - 10})
e2 = case("order2", files=three, repo=JDIR, line='host-log s times 2 "boom"',
          mtimes={"a.log": NOW - 10, "b.log": NOW - 20, "c.log": NOW - 30})
expect("the evidence is the N-th oldest, whichever order the files are read in", {"e": [e1["evidence"], e2["evidence"]]},
       e=["s/b", "s/b"])

# --- resolution and declaration ----------------------------------------------------------------------------
F1 = {"app.log": lines((1, "boom"))}
expect("defaults only", case("def", files=F1, repo=FILE), outcome="passed")
PROF = FILE.replace('path = "{L}/app.log"', 'path = "{L}/none.log"') + \
    '[profiles.p1.sources.s]\npath = "{L}/app.log"\n[profiles.p2.sources.s]\npath = "{L}/other.log"\n'
expect("one profile merges over the default", case("p1", files=F1, repo=PROF,
       host='[repos."*"]\nprofiles = ["p1"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'), outcome="passed")
expect("two profiles in order: the later wins",
       case("p12", files={**F1, "other.log": lines((1, "nope"))}, repo=PROF,
            host='[repos."*"]\nprofiles = ["p1", "p2"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="not yet")
expect("--profiles replaces the host's list for one run",
       case("pflag", files=F1, repo=PROF, profiles=["p1"],
            host='[repos."*"]\nprofiles = ["p2"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'), outcome="passed")
expect("a selected profile the repo does not define: an error",
       case("pmiss", files=F1, repo=FILE, host='[repos."*"]\nprofiles = ["nope"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="error", problem=has("nope"))
expect("unset removes a key the layers below gave (kind: then no kind to match)",
       case("unset", files=F1, repo=FILE + 'kind = "k"\n[profiles.p.sources.s]\nunset = ["kind"]\n', line='host-log s kind k "boom"',
            host='[repos."*"]\nprofiles = ["p"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="error", problem=has("records no kind"))
expect("a host override (the host's path)",
       case("hover", files=F1, repo=FILE.replace("app.log", "none.log"),
            host='[repos."*".sources.s]\npath = "{L}/app.log"\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="passed")
expect("enabled = false: no outcome",
       case("off", files=F1, repo=FILE, host='[repos."*".sources.s]\nenabled = false\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="none")
expect("a source declared nowhere: no outcome", case("undecl", files=F1, repo=FILE, line='host-log t "boom"'), outcome="none")
expect("the host's table overrides but never declares: no outcome",
       case("hostdecl", files=F1, repo="", line='host-log s "boom"',
            host='[repos."*".sources.s]\nshape = "file"\npath = "{L}/app.log"\nrecords = "lines"\nat = ["%Y-%m-%dT%H:%M:%SZ"]\n'
                 '[[allow]]\nroot = "{L}"\nvisibility = "private"\n'), outcome="none")
expect("a source only an unselected profile declares: no outcome",
       case("onlyprof", files=F1, repo='[profiles.p.sources.s]\nshape = "file"\npath = "{L}/app.log"\nrecords = "lines"\n'
                                        'at = ["%Y-%m-%dT%H:%M:%SZ"]\n'), outcome="none")
expect("no host file: no outcome", case("nohost", files=F1, repo=FILE, host=False), outcome="none")
expect("no table for the repo: no outcome",
       case("notab", files=F1, repo=FILE, host='[repos."other/x"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="none")
expect('[repos."R"] matched without case, and [repos."*"] not merged into it',
       case("rstar", files=F1, repo=PROF, repo_id="Acme/App",
            host='[repos."acme/app"]\n[repos."*"]\nprofiles = ["p1"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="error", problem=has("does not exist"))
expect("the repo file unparseable: an error before the declaration is known",
       case("badtoml", files=F1, repo="[sources.s\n", line='host-log zzz "x"'), outcome="error", problem=has("does not parse"))
expect("the repo file refused by a table's check: an error for every check",
       case("refrepo", files=F1, repo=FILE + "[sources.t]\nshape = 3\n", line='host-log s "boom"'),
       outcome="error", problem=has("sources.t"))
expect("an empty repo file (none in the tree): no outcome", case("emptyrepo", files=F1, repo=""), outcome="none")
expect("a missing path: an error", case("nopath", files={}, repo=FILE), outcome="error", problem=has("does not exist"))
expect("an existing directory with no matching file: not yet", case("emptydir", files={}, repo=DIR), outcome="not yet")
expect("no since (no gate added line): an error", case("nosince", files=F1, repo=FILE, since=None),
       outcome="error", problem=has("since unknown"))
expect("... but a host that declares nothing still gives no outcome without since",
       case("nosince2", files=F1, repo=FILE, since=None, host=False), outcome="none")
expect("a check line that is not host-log: an error", case("notcheck", files=F1, repo=FILE, line="pr-merged a/b#1"),
       outcome="error")

# --- roots -----------------------------------------------------------------------------------------------
expect("a path outside every root: an error",
       case("outroot", files=F1, repo=FILE, host='[repos."*"]\n[[allow]]\nroot = "{T}/elsewhere"\nvisibility = "private"\n'),
       outcome="error", problem=has("outside every allowed root"))
expect("no roots at all: an error", case("noroots", files=F1, repo=FILE, host='[repos."*"]\n'),
       outcome="error", problem=has("outside every allowed root"))
expect("allow.repos excluding the repo: an error",
       case("arepos", files=F1, repo=FILE, host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\nrepos = ["x/y"]\n'),
       outcome="error", problem=has("does not serve this repo"))
expect("allow.repos naming the repo in another case: read",
       case("arepos2", files=F1, repo=FILE, host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\nrepos = ["ACME/APP"]\n'),
       outcome="passed")
expect("require_repo with a source that maps no repo: an error",
       case("reqrepo", files=F1, repo=FILE, host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\nrequire_repo = true\n'),
       outcome="error", problem=has("requires a source mapping fields.repo"))
expect("a public ledger on a private root: an error", case("pubpriv", files=F1, repo=FILE, vis="public"),
       outcome="error", problem=has("is private"))
expect("internal is read as public", case("internal", files=F1, repo=FILE, vis="internal"), outcome="error", problem=has("is private"))
PK = {"ev.jsonl": jl({"at": z(at(1)), "kind": "precheck-fail", "text": "boom", "repo": "acme/app"},
                    {"at": z(at(2)), "kind": "msg", "text": "boom", "repo": "acme/app"})}
pk_host = '[repos."*".sources.s]\npublic_kinds = ["precheck-fail"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'
expect("a public ledger counts the host's public_kinds only",
       case("pubkinds", files=PK, repo=JSONL, vis="public", host=pk_host, line='host-log s times 9 "boom"'),
       outcome="not yet", count=1)
expect("a public root: a public ledger counts every record",
       case("pubroot", files=PK, repo=JSONL, vis="public", line='host-log s times 9 "boom"',
            host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "public"\n'), outcome="not yet", count=2)
expect("nested roots: a public root inside a private one reads private",
       case("nest", files={"pub/app.log": lines((1, "boom"))}, repo=FILE.replace("app.log", "pub/app.log"), vis="public",
            host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n[[allow]]\nroot = "{L}/pub"\nvisibility = "public"\n'),
       outcome="error", problem=has("is private"))
expect("nested roots: an inner root whose repos excludes the repo refuses it",
       case("nest2", files={"in/app.log": lines((1, "boom"))}, repo=FILE.replace("app.log", "in/app.log"),
            host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n[[allow]]\nroot = "{L}/in"\n'
                 'visibility = "private"\nrepos = ["x/y"]\n'), outcome="error", problem=has("does not serve"))
expect("a root without visibility: the host file is unreadable",
       case("novis", files=F1, repo=FILE, host='[repos."*"]\n[[allow]]\nroot = "{L}"\n'), outcome="error", problem=has("visibility"))
expect("two [repos] keys equal without case: the host file is unreadable",
       case("dupkey", files=F1, repo=FILE, host='[repos."a/b"]\n[repos."A/B"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'),
       outcome="error", problem=has("one repo"))
expect("max_seconds above 90: the host file is unreadable",
       case("maxsec", files=F1, repo=FILE, host='[repos."*"]\n[limits]\nmax_seconds = 91\n'), outcome="error", problem=has("at most 90"))

# --- errors and duplicates ------------------------------------------------------------------------------
ZST = b"\x28\xb5\x2f\xfd" + b"\0" * 20
expect("a reading error in one file and N reached in another: passed",
       case("errpass", files={"a.zst": ZST, "b.log": lines((1, "boom"))}, repo=DIR), outcome="passed")
expect("a reading error and N not reached: an error",
       case("errfail", files={"a.zst": ZST, "b.log": lines((1, "fine"))}, repo=DIR), outcome="error", problem=has("zstd"))
expect("a duplicate file's records are dropped",
       case("dup", files={"a.log": lines((1, "boom")), "b.log": lines((1, "boom"))}, repo=DIR, line='host-log s times 2 "boom"'),
       outcome="not yet", count=1, skipped={"duplicate": 1})
expect("read once: two paths (a link) reaching one file",
       case("dupl", files={"a.log": lines((1, "boom"))}, repo=DIR, line='host-log s times 2 "boom"',
            setup=lambda d, L: os.symlink(L / "a.log", L / "b.log")), outcome="not yet", count=1, skipped={"duplicate": 1})
big = lines((1, "boom")) + lines(*[(2, "x" * 100)] * 200)
expect("a file cut short by max_bytes: its records read so far count",
       case("cut", files={"a.log": big}, repo=DIR, host='[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n'
                                                         '[limits]\nmax_bytes = 4000\n'), outcome="passed")

# --- limits -------------------------------------------------------------------------------------------------
LIM = '[repos."*"]\n[[allow]]\nroot = "{L}"\nvisibility = "private"\n[limits]\n'
expect("a zip bomb past max_bytes: an error",
       case("bomb", files={"a.zip": zip_bytes([("r.log", b"\0" * (8 * 1024 * 1024))])}, repo=ARCH.replace('["**/*.log"]', '["**"]'),
            host=LIM + "max_bytes = 1048576\n"), outcome="error", problem=has("max_bytes"))
expect("max_files: an error",
       case("maxf", files={f"{i}.log": lines((i, "boom")) for i in range(1, 4)}, repo=DIR, line='host-log s times 5 "boom"',
            host=LIM + "max_files = 2\n"), outcome="error", problem=has("max_files"))
expect("N counted before a limit: passed",
       case("maxf2", files={f"{i}.log": lines((i, "boom")) for i in range(1, 4)}, repo=DIR, line='host-log s times 2 "boom"',
            host=LIM + "max_files = 2\n"), outcome="passed")
_mono, _file = H.time.monotonic, H.Budget.file
state = {"n": 0}


def counting_file(self):
    _file(self)
    state["n"] += 1


H.Budget.file = counting_file
H.time.monotonic = lambda: 0.0 if state["n"] < 2 else 1e9
state["n"] = 0
expect("a read stopped by max_seconds: an error",
       case("maxs", files={"1.log": lines((1, "boom")), "2.log": lines((2, "boom"))}, repo=DIR, line='host-log s times 5 "boom"'),
       outcome="error", problem=has("max_seconds"))
state["n"] = 0
expect("N counted before max_seconds: passed",
       case("maxs2", files={"1.log": lines((1, "boom")), "2.log": lines((2, "boom"))}, repo=DIR, line='host-log s "boom"'),
       outcome="passed")
H.time.monotonic, H.Budget.file = _mono, _file
expect("an over-long line: skipped",
       case("longl", files={"a.log": lines((1, "boom" + "x" * 300), (2, "boom"))}, repo=DIR, host=LIM + "max_line = 100\n",
            line='host-log s times 2 "boom"'), outcome="not yet", count=1, skipped={"long-line": 1})
expect("an over-long record: skipped",
       case("longr", files={"a.log": lines((1, "boom")) + b"more\n" * 40 + lines((2, "boom"))}, repo=DIR,
            host=LIM + "max_record = 100\n", line='host-log s times 2 "boom"'), outcome="not yet", count=1, skipped={"long-record": 1})
trunc = gzip.compress(lines(*[(1, "boom")] * 50))[:-30]
expect("a young truncated .gz: skipped",
       case("young", files={"a.gz": trunc}, repo=DIR), outcome="not yet", skipped={"young-truncated": 1})
expect("an old truncated .gz: an error, its records so far counted",
       case("oldtr", files={"a.gz": trunc}, repo=DIR, mtimes={"a.gz": NOW - 3600}, line='host-log s times 999 "boom"'),
       outcome="error", problem=has("ends early"))

# --- hostile input (the security review of PR #135) ----------------------------------------------------------
gz_bomb = gzip.compress(b"\n" * (64 * 1024 * 1024))
t0 = time.monotonic()
expect("a gzip member inside a plain tar is charged: past max_bytes, an error, quickly",
       case("tarbomb", files={"a.tar.gz": tar_bytes([("a.log", gz_bomb)], comp="")}, repo=ARCH.replace('["**/*.log"]', '["**"]'),
            host=LIM + "max_bytes = 1048576\n"), outcome="error", problem=has("max_bytes"))
expect("... in well under its 30 s budget", {"s": time.monotonic() - t0}, s=lambda v: v < 20)
for title, poison in [("a JSON line nested past the recursion limit", b"[" * 200_000 + b"\n"),
                      ("a 400-digit epoch", jl({"at": 10 ** 400, "text": "boom"})),
                      ("a negative huge epoch", jl({"at": -10 ** 30, "text": "boom"}))]:
    expect(f"jsonl: {title} is skipped, and the three good records still pass",
           case("poison", files={"ev.jsonl": jl(*[{"at": z(at(h)), "text": "boom"} for h in (1, 2, 3)]) + poison},
                repo=JSONL.replace(', repo = "repo"', ""), line='host-log s times 3 "boom"'), outcome="passed", count=3)
expect("lines: a year-1 time with an offset (out of range in UTC) is no timestamp, and the good records pass",
       case("y1", files={"a.log": lines((1, "boom"), (2, "boom"), (3, "boom")) + b"0001-01-01T00:00:00+0100 x\n"},
            repo=DIR.replace('at = ["%Y-%m-%dT%H:%M:%SZ"]', 'at = ["%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S%z"]'),
            line='host-log s times 3 "boom"'), outcome="passed")


def encrypted_second(members):
    b = bytearray(zip_bytes(members))
    i = b.find(b"PK\x01\x02", b.find(b"PK\x01\x02") + 1)  # the second member's central directory entry
    b[i + 8] |= 1  # its general-purpose flag: encrypted
    return bytes(b)


expect("an encrypted zip member after a good one: its error does not abort, and the good records pass",
       case("enc", files={"a.zip": encrypted_second([("a.log", lines((1, "boom"), (2, "boom"), (3, "boom"))),
                                                     ("b.log", lines((4, "boom")))])},
            repo=ARCH, line='host-log s times 3 "boom"'), outcome="passed")
expect("... and with N not reached it is the error",
       case("enc2", files={"a.zip": encrypted_second([("a.log", lines((1, "boom"))), ("b.log", lines((4, "boom")))])},
            repo=ARCH, line='host-log s times 3 "boom"'), outcome="error", problem=has("b.log"))
t0 = time.monotonic()
deep = "/".join(f"d{i}" for i in range(30))
expect("a worst-case glob (many ** over a deep path) answers at once",
       case("glob", files={f"{deep}/a.log": lines((1, "boom"))}, repo=DIR + 'match = ["**/**/**/**/**/**/**/**/**/**/zzz"]\n'),
       outcome="not yet")
expect("... in well under a second", {"s": time.monotonic() - t0}, s=lambda v: v < 2)
expect("glob_match: ** spans zero or more segments; * never crosses /",
       {"v": [H.glob_match(p, r) for p, r in [("**/*.log", "a.log"), ("**/*.log", "x/y/a.log"), ("*.log", "x/a.log"),
                                               ("x/**", "x"), ("x/**/y", "x/y"), ("x/**/y", "x/a/b/y"), ("a?c", "abc")]]},
       v=[True, True, False, True, True, True, True])
padded = gzip.compress(lines((1, "boom"))) + b"\0" * 1024
expect("a settled gzip with NUL padding after its end reads clean",
       case("pad", files={"a.gz": padded}, repo=DIR, mtimes={"a.gz": NOW - 3600}), outcome="passed", problem=None)

# --- counting -------------------------------------------------------------------------------------------------
expect("times 3 met", case("t3", files={"a.log": lines((1, "boom"), (2, "boom"), (3, "boom"))}, repo=DIR,
       line='host-log s times 3 "boom"'), outcome="passed", count=3, evidence=f"s@{tok(at(3))}")
expect("times 3 not met", case("t3n", files={"a.log": lines((1, "boom"), (2, "boom"))}, repo=DIR,
       line='host-log s times 3 "boom"'), outcome="not yet", count=2)
expect("a record on the day of since is not counted; one at 00:00 UTC the day after is",
       case("edge", files={"a.log": lines((-1, "boom"), (0, "boom"))}, repo=DIR, line='host-log s times 9 "boom"'),
       outcome="not yet", count=1)
expect("a kind against a source with none: an error",
       case("nokind", files=F1, repo=FILE, line='host-log s kind k "boom"'), outcome="error", problem=has("records no kind"))
expect("a lines source's constant kind matches",
       case("ckind", files=F1, repo=FILE + 'kind = "k"\n', line='host-log s kind k "boom"'), outcome="passed")
expect("a source that began after the first instant, fewer than N: not yet",
       case("young-src", files={"a.log": lines((100, "boom"))}, repo=DIR, line='host-log s times 2 "boom"'), outcome="not yet")
expect("a record for another repo is not counted",
       case("orepo", files={"ev.jsonl": jl({"at": z(at(1)), "text": "boom", "repo": "other/x"},
                                           {"at": z(at(2)), "text": "boom"})}, repo=JSONL), outcome="not yet", count=0)
expect("a DST-ambiguous local time is read with fold=0",
       case("dst", files={"ev.jsonl": jl({"at": "2025-11-02T01:30:00", "text": "boom"})}, since="2025-11-01",
            repo=JSONL.replace(', repo = "repo"', "") + 'tz = "America/New_York"\n'),
       outcome="passed", evidence="s@20251102T053000Z")
expect("a syslog year-less time takes the year that does not pass the file's time",
       case("yearless", files={"a.log": f"{at(1).strftime('%b %d %H:%M:%S')} boom\n".encode()},
            repo=DIR.replace('at = ["%Y-%m-%dT%H:%M:%SZ"]', 'at = ["%b %d %H:%M:%S"]')), outcome="passed",
       evidence=f"s@{tok(at(1))}")

# --- validate ---------------------------------------------------------------------------------------------------
V = TMP / "v"
V.mkdir()


def val(text, ledger=None):
    (V / "ls.toml").write_text(text)
    return H.validate(str(V / "ls.toml"), ledger)


for title, text, word in [
        ("an unknown key", '[sources.s]\nshape = "file"\nwat = 1\n', "unknown key 'wat'"),
        ("a host-only key in the repo file", '[sources.s]\npublic_kinds = ["a"]\n', "host-only"),
        ("a host-only top-level table", '[[allow]]\nroot = "/x"\n', "host-only"),
        ("a shape outside its list", '[sources.s]\nshape = "pipe"\n', "shape"),
        ("records outside its list", '[sources.s]\nrecords = "csv"\n', "records"),
        ("a relative path", '[sources.s]\npath = "logs/x"\n', "neither absolute"),
        ("an empty match", '[sources.s]\nmatch = []\n', "match is empty"),
        ("an empty at", '[sources.s]\nat = []\n', "at is empty"),
        ("a list of the wrong type", '[sources.s]\nexclude = "x"\n', "list of strings"),
        ("fields with an unknown key", '[sources.s]\nfields = { when = "t" }\n', "fields.when"),
        ("enabled not a boolean", '[sources.s]\nenabled = "no"\n', "enabled"),
        ("unset naming no key", '[sources.s]\nunset = ["nope"]\n', "unset names"),
        ("a constant kind outside the kind form", '[sources.s]\nkind = "Bad"\n', "kind token"),
        ("a locale-dependent format", '[sources.s]\nat = ["%c"]\n', "locale"),
        ("a format with no date", '[sources.s]\nat = ["%H:%M:%S"]\n', "names no date"),
        ("%s", '[sources.s]\nat = ["%s"]\n', "strptime"),
        ("a bad source name", '[sources.Bad]\nshape = "file"\n', "a source's name"),
        ("a profile holding another key", '[profiles.p]\nx = 1\n', "sources only"),
        ("an unknown zone", '[sources.s]\ntz = "Mars/Base"\n', "tz")]:
    p, w = val(text)
    expect(f"validate refuses {title}", {"p": "; ".join(p)}, p=has(word))
p, w = val(FILE.replace("{L}", "/x") + 'match = ["*"]\n')
expect("validate warns on a key the shape does not use, without failing", {"p": p, "w": "; ".join(w)}, p=[], w=has("match"))
p, w = val(FILE.replace("{L}", "/x") + "enabled = false\n")
expect("validate warns on a source enabled nowhere", {"p": p, "w": "; ".join(w)}, p=[], w=has("enabled by no profile"))

LD = TMP / "ledger"
(LD / "archive").mkdir(parents=True)
(LD / "README.md").write_text((DC / "docs/ledger/README.md").read_text())
entry = ("## TD-001: waits on a host event\n\n**Priority:** Low\n**Added:** 2026-01-01\n**Status:** Open\n"
         "**Blocked by:** event (red)\n\n**Why:** w.\n\n**Event (red):** the precheck fails again\n"
         'check: host-log ci "boom"\n\n**Log:**\n- 2026-01-01: gate added: event (red)\n')
(LD / "TD-001.md").write_text(entry)
p, w = val(FILE.replace("{L}", "/x"), str(LD))
expect("validate --ledger fails a check whose source no default or profile declares", {"p": "; ".join(p)},
       p=has("TD-001", "source ci"))
p, w = val(FILE.replace("{L}", "/x").replace("[sources.s]", "[sources.ci]"), str(LD))
expect("validate --ledger passes a declared source", {"p": p}, p=[])
p, w = val('[profiles.p.sources.ci]\npath = "/x"\n', str(LD))
expect("validate --ledger: a profile's declaration counts", {"p": p}, p=[])

# --- the exit contract --------------------------------------------------------------------------------------
def cli(*args, stdin=""):
    return subprocess.run([sys.executable, f"{S}/hostlog.py", *args], input=stdin, capture_output=True, text=True, timeout=60)


d = TMP / "cli"
(d / "logs").mkdir(parents=True)
(d / "logs" / "app.log").write_bytes(lines((1, "boom")))
(d / "host.toml").write_text(f'[repos."*"]\n[[allow]]\nroot = "{d}/logs"\nvisibility = "private"\n')
base = ["check", "--repo-config", "-", "--host-config", str(d / "host.toml"), "--repo", "acme/app", "--visibility", "private",
        "--since", SINCE.isoformat()]
outs = []
for line, conf in [('host-log s "boom"', FILE), ('host-log s "nope"', FILE), ('host-log t "x"', FILE),
                   ('host-log s "boom"', "[bad"), ("host-log", FILE)]:
    r = cli(*base, line, stdin=conf.replace("{L}", str(d / "logs")))
    try:
        o = json.loads(r.stdout)
    except ValueError:
        o = {}
    outs.append((r.returncode, o.get("outcome"), len(r.stdout.strip().splitlines())))
expect("check: exit 0 and one JSON object for every outcome", {"o": outs},
       o=[(0, "passed", 1), (0, "not yet", 1), (0, "none", 1), (0, "error", 1), (0, "error", 1)])
r = cli("check", "--repo-config", "-", "--host-config", "x", "host-log s \"x\"")
expect("check: a usage error exits non-zero (the caller reads it as error)", {"rc": r.returncode, "json": r.stdout.strip()},
       rc=lambda v: v != 0, json="")
r = cli(*base[:-2], "--since", "2026-13-01", 'host-log s "boom"', stdin=FILE.replace("{L}", str(d / "logs")))
expect("check: a bad --since is an error outcome", {"o": json.loads(r.stdout)["outcome"], "rc": r.returncode}, o="error", rc=0)
r = cli("validate", "--repo-config", str(V / "ls.toml"))
expect("validate: exit 0 on a clean file", {"rc": r.returncode}, rc=0)
(V / "bad.toml").write_text('[sources.s]\nwat = 1\n')
r = cli("validate", "--repo-config", str(V / "bad.toml"))
expect("validate: exit 1 on a refusal", {"rc": r.returncode, "out": r.stdout}, rc=1, out=has("refused"))
r = subprocess.run([sys.executable, "-c", "import runpy, sys; sys.modules['tomllib'] = None; "
                    f"sys.argv = ['hostlog.py'] + {base + ['host-log s \"x\"']!r}; "
                    f"runpy.run_path('{S}/hostlog.py', run_name='__main__')"],
                   input="", capture_output=True, text=True, timeout=60)
expect("check on a Python without tomllib: outcome none, exit 0", {"o": json.loads(r.stdout or "{}").get("outcome"), "rc": r.returncode},
       o="none", rc=0)

print(f"{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
PY
