#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/forge.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""The forge adapter (TD-103, the decision in TD-097): every question the PR tooling asks a
forge goes through here, in one neutral shape, so a second forge is one more backend and
never a branch in each caller.

Callers: check_cadence.py (the rows), nudge_user_attention.py (the open-PR line, the settings
line, the remote tier), adopt_repo_settings.sh (through the CLI below), the
stranded-work sweep (`nothing-left`), a session picking a TD (`in-flight`, cadence.md §2.9). No
other script runs the forge's CLI (`gh`, `glab`): a new question is an operation here first.

Which forge (cadence.md §9.18, the `forge` key): `auto` (the default) reads origin's host —
github.com is GitHub, gitlab.com or a host whose first label is `gitlab` is GitLab (TD-104),
anything else is a forge the cadence cannot read yet, never GitHub by default; `github` says
a host under another name (GitHub Enterprise) is GitHub, `gitlab` the same for GitLab;
`none` says there is no PR API at all (TD-105): check_cadence.py --since reads the review
line from each commit's body (NoForge), and every other caller says "no forge" once. An origin that names no host (a local path, file://) is read with the
GitHub backend, as before TD-103: `gh` then answers or fails on its own.

Every operation raises ForgeUnreadable(reason) when it cannot ask — no CLI, not
authenticated, offline, an unsupported forge — and a caller turns that into "cannot see",
never into an empty answer (cadence.md §7). The backend shells out to the forge's own CLI
and never holds a credential: `gh` for GitHub, `glab` for GitLab (whose facts were read
from a real project with glab 1.123.0 — docs/plans/2026-10-12-forge-adapter.md, *GitLab, as
read*).

    forge.py check                     exit 0 when the forge here can be read (its CLI present
                                       and authenticated), else the reason, exit 2
    forge.py has-cli [SLUG]            exit 0 when the forge's CLI is installed, else the reason, exit 2
    forge.py origin-slug               the SLUG of the repo in the current directory, from origin
    forge.py wanted SLUG [--no-auto-delete]
                                       one "name=value" line per merge setting the cadence wants
    forge.py repo-settings SLUG        the same lines with the repo's values (null: unreadable)
    forge.py patch-settings SLUG name=value…
                                       write those settings
    forge.py nothing-left N            exit 0 when PR N has nothing left to merge (every file it
                                       changes is already the same on origin/<base>: its changes
                                       landed by another PR — TD-114), 1 when it has or is not
                                       open (merged, closed), 2 when git
                                       here cannot tell (its head not fetched, no origin/<base>)

    forge.py in-flight TD-NNN          is the entry already being worked (cadence.md §2.9): the PRs
                                       naming it in any state, origin's branches naming it, and its
                                       Status on origin/<default> (fetched); exit 1 when an open or
                                       merged PR (not the one that filed it) or a branch names it,
                                       or it is archived; 0 when nothing does; 2 when a lookup
                                       could not be made or the id is in neither file

SLUG is `owner/repo` (github.com) or `host/owner/repo` (`host/group/sub/repo` on GitLab), and
picks the forge itself; the other commands read the forge of the repo in the current
directory. A value with a newline or a quote in it (GitLab's squash template) is printed as
a JSON string, on both sides of the comparison, and patch-settings reads it back.

Stdlib only.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote, urlencode

KNOWN = ("auto", "github", "gitlab", "none")
NOT_FOUND = -4   # a remote-tier probe's rc for "the forge says there is no such file"
# How GitHub Actions begins the annotation on a job it refused to start (billing, spending limit) — TD-115
_NOT_STARTED = "The job was not started because"


class ForgeUnreadable(Exception):
    pass


class ChecksForbidden(ForgeUnreadable):
    """GitHub answered 403 on a commit's check runs while its commit statuses read (TD-156):
    a fine-grained token can hold Commit statuses but no Checks permission exists for one.
    `statuses` holds what was read. A caller that does not know this case reads it as any
    ForgeUnreadable — no evidence — so only the ci row decides what the statuses may prove."""

    def __init__(self, reason: str, statuses: list[dict]):
        super().__init__(reason)
        self.statuses = statuses


def setting(root: "Path | str | None") -> str:
    """The `forge` key for the repo at root (default "auto"). An unreadable settings file
    still lets CADENCE_FORGE count, then falls back to auto — the classifier below is
    loud about any host it does not know, so auto never reads a stranger as GitHub."""
    try:
        here = str(Path(__file__).resolve().parent)
        if here not in sys.path:
            sys.path.insert(0, here)
        import cadence_config as C
        top = C.repo_root(str(root or "."))
        raw, _ = C.resolve("forge", C.sources(top))
    except Exception:  # noqa: BLE001 — no helper, or an unreadable file
        raw = os.environ.get("CADENCE_FORGE", "").strip() or "auto"
    return str(raw).strip().lower() or "auto"


def _origin(root: Path) -> tuple[str | None, str]:
    """(host, path) of origin's URL; host None when origin names none (no origin, a local
    path, file://)."""
    try:
        r = subprocess.run(["git", "-C", str(root), "remote", "get-url", "origin"],
                           check=False, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None, ""
    raw = r.stdout.strip() if r.returncode == 0 else ""
    # The host is read from the URL's own shape, not through a normalizer, so any scheme
    # (ssh://, git://, HTTPS://) and any user (deploy@host:a/b) names its forge.
    m = re.fullmatch(r"([A-Za-z][A-Za-z0-9+.-]*)://(?:[^@/]*@)?([^/:]*)(?::\d*)?(/.*)?", raw)
    if m:
        if m.group(1).lower() == "file":
            return None, ""
        host, path = m.group(2).lower(), m.group(3) or ""
    else:
        # scp-like user@host:path; a bare owner/repo (a legacy *lock* form) or a local path
        # has no host — it would read as github.com through the lock normalizer, so never here
        m = re.fullmatch(r"[^/@:]+@([^/:]+):(.*)", raw)
        if not m:
            return None, ""
        host, path = m.group(1).lower(), m.group(2)
    return (host or None), path


def _slug(path: str, deep: bool = False) -> str | None:
    """owner/repo from origin's path; deep allows GitLab's group/sub/repo."""
    slug = re.sub(r"\.git$", "", path.strip("/")).lower()
    return slug if re.fullmatch(r"[^/]+(/[^/]+)+" if deep else r"[^/]+/[^/]+", slug) else None


def is_gitlab_host(host: str) -> bool:
    """`auto`'s GitLab: gitlab.com, or a host whose first label is gitlab (gitlab.corp.example)."""
    return host == "gitlab.com" or host.split(".", 1)[0] == "gitlab"


def origin_forge(root: Path) -> tuple[str, str | None]:
    """Classify a repo's origin once (TD-098, moved here by TD-103): ("github", "owner/repo")
    for GitHub; ("gitlab", "host/group/repo") for GitLab (TD-104; None in place of the slug
    when origin names no project to ask about); ("other", host) for a forge the cadence
    cannot read yet (Gitea, a GitHub Enterprise host not named by `forge = "github"`), or
    ("other", "none") for `forge = "none"` (TD-105); ("none", None) for no origin, or one that
    names no host (a local path, a bare file:// clone: what every test fixture uses) — there
    the caller behaves as before. A detector told "other" says it could not look, never stays
    quiet: an empty answer must mean nothing there (cadence.md §7)."""
    want = setting(root)
    host, path = _origin(Path(root))
    if want == "none":
        return "other", "none"
    if want not in KNOWN:
        return "other", f"!{want}"
    if want == "gitlab" or (want == "auto" and host and is_gitlab_host(host)):
        slug = _slug(path, deep=True) if host else None
        return "gitlab", f"{host}/{slug}" if slug else None
    if not host:
        return ("github", None) if want == "github" else ("none", None)
    if host == "github.com" or want == "github":
        slug = _slug(path)
        if host == "github.com":
            return ("github", slug) if slug else ("none", None)
        return "github", slug
    return "other", host


def forge_unread_line(host: str) -> str:
    """The one wording every detector uses for an origin it cannot read (TD-098)."""
    if host.startswith("!"):
        return (f"PRs not checked: the forge setting {host[1:]!r} is not one of "
                f"{', '.join(KNOWN)} (docs/cadence.toml or CADENCE_FORGE)")
    if host == "none":
        return ('no forge (forge = "none" in docs/cadence.toml): PR checks read the commit log only '
                "— check_cadence.py --since reads each commit's cadence-review: line (TD-105)")
    return f"PRs not checked: origin is {host}, which the cadence cannot read yet (TD-097)"


GITLAB_NO_PROJECT = ('PRs not checked: the forge is GitLab, but origin names no project to ask '
                     "about (forge = \"gitlab\" needs an origin like gitlab.example/group/repo)")


def backend(root: "Path | str | None" = None, **kw) -> "GitHub | GitLab":
    """The backend for the repo at root (default: the current directory's). Raises
    ForgeUnreadable with the "PRs not checked" line for a forge with no backend."""
    kind, host = origin_forge(Path(root or "."))
    if kind == "other":
        raise ForgeUnreadable(forge_unread_line(host or "?"))
    if kind == "gitlab":
        if not host:
            raise ForgeUnreadable(GITLAB_NO_PROJECT)
        return GitLab(slug=host, **kw)
    return GitHub(slug=host, **kw)


class NoForge:
    """`forge = "none"` (TD-105): a repo with no PR API, such as a bare repo over ssh. There
    are no PRs, so the §4.9 review line goes in the squash commit's body, and
    check_cadence.py --since reads every commit on the default branch from git (its direct
    audit). Only what that needs is here: a PR question raises ForgeUnreadable with the
    "no forge" line, and the other callers never get this backend (backend() raises the same
    line for them)."""

    name = "none"
    cli = "git"
    subject_re = re.compile(r"(?!)")   # no PR marks a subject: every commit is read

    @staticmethod
    def missing() -> None:
        return None

    @staticmethod
    def merged_since(when: str, limit: int) -> list[dict]:
        return []

    @staticmethod
    def pr(n) -> dict:
        raise ForgeUnreadable(forge_unread_line("none"))

    @staticmethod
    def prs_for_branch(branch: str, limit: int = 5) -> list[dict]:
        raise ForgeUnreadable(forge_unread_line("none"))

    @staticmethod
    def prs_naming(text: str, limit: int = 50) -> list[dict]:
        raise ForgeUnreadable(forge_unread_line("none"))


# --- GitHub -----------------------------------------------------------------------------


# The fields check_cadence.py's rows read, in gh's names (the neutral record below maps them).
PR_FIELDS = (
    "number,url,state,title,body,baseRefName,headRefName,headRefOid,mergedAt,mergeCommit,files,updatedAt,"
    "isCrossRepository"
)
# What every gh-driven caller's env adds: a call from a hook or a sweep must never prompt.
_QUIET = {"GH_PROMPT_DISABLED": "1"}


class _CLI:
    """What every backend shares: the one place its CLI runs, under the remote tier's budget,
    and the errors turned into ForgeUnreadable."""

    cli = ""

    def __init__(self, slug: str | None = None, cwd: "Path | str | None" = None,
                 spent: dict | None = None, per_call: float = 60.0, total: float | None = None):
        self.slug, self.cwd = slug, cwd
        # The remote tier's budget (nudge_user_attention.py): elapsed time is booked into
        # spent["t"]; a call past `total` is not made, and spent["hit"] says so.
        self.spent, self.per_call, self.total = spent, per_call, total

    # -- the one place the CLI runs --------------------------------------------------------

    def call(self, args: list[str], timeout: float | None = None,
             env: dict | None = None) -> tuple[int, str, str]:
        """(rc, stdout, stderr) of one CLI call; rc -1 timeout, -2 budget exhausted (not
        attempted), -3 the CLI not installed."""
        cap = timeout if timeout is not None else self.per_call
        if self.spent is not None and self.total is not None:
            remaining = self.total - self.spent["t"]
            if remaining <= 0:
                self.spent["hit"] = True
                return -2, "", "remote-tier budget exhausted"
            cap = min(cap, remaining)   # the budget may truncate below the per-call cap
        t0 = time.monotonic()
        try:
            r = subprocess.run([self.cli, *args], cwd=self.cwd, check=False, capture_output=True,
                               text=True, timeout=cap,
                               env=None if env is None else {**os.environ, **env})
            return r.returncode, r.stdout, r.stderr
        except FileNotFoundError:
            return -3, "", f"{self.cli} not installed"
        except subprocess.TimeoutExpired:
            return -1, "", f"timeout after {cap:g}s" if self.spent is not None else f"{self.cli} timed out"
        finally:
            if self.spent is not None:
                self.spent["t"] += time.monotonic() - t0

    def _run(self, args: list[str], timeout: float | None = None, env: dict | None = None) -> str:
        rc, out, err = self.call(args, timeout, env)
        if rc == 0:
            return out
        if rc == -3:
            raise ForgeUnreadable(err)
        msg = (err or out).strip()
        raise ForgeUnreadable(msg.splitlines()[-1] if msg else f"{self.cli} failed")

    def _json(self, args: list[str]):
        try:
            return json.loads(self._run(args))
        except ValueError as e:
            raise ForgeUnreadable(f"{self.cli} gave unparseable JSON ({e})") from None

    def _lines(self, args: list[str]) -> list[dict]:
        try:
            return [json.loads(ln) for ln in self._run(args).splitlines() if ln.strip()]
        except ValueError as e:
            raise ForgeUnreadable(f"{self.cli} gave unparseable JSON ({e})") from None

    def auth_scope(self) -> list[str]:
        return []

    def required_checks(self, branch: str) -> list[str] | None:
        """The check names the forge requires on `branch` before a merge (TD-178); None when
        this forge has no such read (GitLab), so the ci row judges every run as before."""
        return None

    def missing(self) -> str | None:
        """Why the CLI cannot be run at all, or None."""
        from shutil import which
        return None if which(self.cli) else f"{self.cli} is not installed"

    def check(self) -> str | None:
        """Why this forge cannot be asked at all (no CLI, not authenticated), or None."""
        gone = self.missing()
        if gone:
            return gone
        rc, _, _ = self.call(["auth", "status", *self.auth_scope()], timeout=30)
        return None if rc == 0 else f"{self.cli} is not authenticated ({self.cli} auth login)"


class GitHub(_CLI):
    """Today's `gh` calls, moved (TD-103) — the argv of each is what the caller ran before,
    so the suites' `gh` shims answer them unchanged."""

    name = "github"
    cli = "gh"
    # A squash's subject ends "(#N)"; a merge commit's starts "Merge pull request #N".
    # The §4.6 audit's fallback when the merged list is unreadable; the list is the source.
    subject_re = re.compile(r"\(#\d+\)$|^Merge pull request #\d+ ")
    # cadence.md §4's merge settings, in the API's names: the settings line and
    # adopt_repo_settings.sh both read this one copy.
    settings_wanted = {"allow_squash_merge": True, "allow_merge_commit": False,
                       "allow_rebase_merge": False, "delete_branch_on_merge": True}
    auto_delete = "delete_branch_on_merge"

    @staticmethod
    def ref(n) -> str:
        return f"#{n}"

    @staticmethod
    def retarget_hint(n, base: str) -> str:
        # Not `gh pr edit --base` (TD-143): on gh 2.46 it fails on the retired Projects
        # (classic) GraphQL field and leaves the base as it was. gh fills {owner}/{repo}.
        return f"`gh api -X PATCH repos/{{owner}}/{{repo}}/pulls/{n} -f base={base}`, before deleting the old base"

    @staticmethod
    def landed_pr_hint(branch: str) -> str:
        return f"gh pr list --head {branch} --state merged"

    # -- PRs ---------------------------------------------------------------------------------

    @classmethod
    def record(cls, p: dict) -> dict:
        """gh's PR JSON as the neutral record (only the fields gh was asked for are filled)."""
        n = p.get("number")
        return {
            "number": n,
            "ref": cls.ref(n),
            "url": p.get("url"),
            "state": str(p.get("state") or "").lower(),   # open | merged | closed
            "title": p.get("title"),
            "body": p.get("body"),
            "base": p.get("baseRefName"),
            "head": p.get("headRefName"),
            "head_sha": p.get("headRefOid"),
            "cross_repo": p.get("isCrossRepository"),   # a fork's head (TD-186); None when not asked
            "merged_at": p.get("mergedAt"),
            "merge_sha": (p.get("mergeCommit") or {}).get("oid"),
            "files": [f.get("path") for f in p.get("files") or []],
            "updated_at": p.get("updatedAt"),
        }

    def pr(self, n) -> dict:
        return self.record(self._json(["pr", "view", str(n), "--json", PR_FIELDS]))

    def prs_for_branch(self, branch: str, limit: int = 5) -> list[dict]:
        prs = self._json(["pr", "list", "--head", branch, "--state", "all", "--limit", str(limit),
                          "--json", "number,state"])
        return [self.record(p) for p in prs]

    def prs_naming(self, text: str, limit: int = 50) -> list[dict]:
        """PRs in any state whose title or body the forge's search matches `text`: a superset
        (the search splits words), so the caller filters on what it wants exactly."""
        prs = self._json(["pr", "list", "--state", "all", "--search", f'"{text}" in:title,body',
                          "--limit", str(limit), "--json", "number,state,title,body,headRefName,url,mergeCommit"])
        return [self.record(p) for p in prs]

    def merged_since(self, when: str, limit: int) -> list[dict]:
        prs = self._json(["pr", "list", "--state", "merged", "--search", f"merged:>={when}",
                          "--limit", str(limit), "--json", "number,mergeCommit"])
        return [self.record(p) for p in prs]

    def open_prs(self, limit: int, timeout: float) -> list[dict]:
        """Open PRs, oldest first (so a limit can never drop the stalest), each with
        created_at, draft and its comments as {trusted, body} — trusted when the author has
        a say in the repo."""
        # oldest first, so the limit can never drop the stalest PR — the one TD-052 is for
        prs = json.loads(self._run(["pr", "list", "--state", "open", "--limit", str(limit),
                                    "--search", "sort:created-asc",
                                    "--json", "number,title,createdAt,isDraft,comments,"
                                    "baseRefName,headRefOid"],
                                   timeout=timeout, env=_QUIET) or "[]")
        out = []
        for p in prs:
            rec = self.record(p)
            rec["created_at"] = p.get("createdAt")
            rec["draft"] = bool(p.get("isDraft"))
            rec["comments"] = [
                {"trusted": c.get("authorAssociation") in ("OWNER", "MEMBER", "COLLABORATOR"),
                 "body": c.get("body")}
                for c in p.get("comments") or []]
            out.append(rec)
        return out

    def comments(self, n) -> list[dict]:
        """[{author, created_at, updated_at, body}], oldest first as the forge lists them."""
        raw = self._json(["api", "--paginate", f"repos/{{owner}}/{{repo}}/issues/{n}/comments"])
        return [{"author": (c.get("user") or {}).get("login"), "created_at": c.get("created_at"),
                 "updated_at": c.get("updated_at"), "body": c.get("body")} for c in raw]

    def commit_parents(self, sha: str) -> int:
        return len(self._json(["api", f"repos/{{owner}}/{{repo}}/commits/{sha}"]).get("parents", []))

    # -- CI ----------------------------------------------------------------------------------

    def check_runs(self, sha: str) -> list[dict]:
        """[{name, status, conclusion}] for every check run on sha. A job Actions refused to
        start (the account's billing or spending limit, TD-115) is
        reported as conclusion "failure" with no steps; only its annotation says why. Such a
        run's conclusion is "not_run" and its "why" is that annotation, which the ci row names
        as no evidence, never as a red build — GitLab's no-jobs pipeline, read the same way."""
        # object-shaped endpoint: --paginate walks the pages, --jq flattens each page's runs to one object per line
        try:
            runs = self._lines(["api", "--paginate",
                                f"repos/{{owner}}/{{repo}}/commits/{sha}/check-runs?per_page=100",
                                "--jq", ".check_runs[]"])
        except ForgeUnreadable as e:
            # 403 is the token's permission (TD-156); a rate limit answers 403 too and is not.
            # 404 and 422 (no such commit) stay unreadable, as does a statuses read that fails.
            if "HTTP 403" not in str(e) or "rate limit" in str(e).lower():
                raise
            raise ChecksForbidden(str(e), self.statuses(sha)) from None
        for r in runs:
            if r.get("conclusion") == "failure" and (r.get("output") or {}).get("annotations_count"):
                why = self._not_started(r.get("id"))
                if why:
                    r["conclusion"], r["why"] = "not_run", why
        # A commit status (precheck's cadence/precheck, TD-117, or any integration's) is not a
        # check run on GitHub: read beside them, so the ci row sees every verdict on the head.
        return runs + self.statuses(sha)

    def statuses(self, sha: str) -> list[dict]:
        """[{name, status, conclusion, kind}] — the latest commit status per context on sha
        (GitHub's combined status), in check-run shape: success is success, failure and
        error are failure, pending is still running."""
        out = []
        for st in self._lines(["api", f"repos/{{owner}}/{{repo}}/commits/{sha}/status?per_page=100",
                               "--jq", ".statuses[]"]):
            state = st.get("state")
            out.append({"name": st.get("context"), "kind": "status",
                        "status": "completed" if state in ("success", "failure", "error") else "in_progress",
                        "conclusion": {"success": "success", "failure": "failure", "error": "failure"}.get(state),
                        "description": st.get("description")})
        return out

    # A private repo on a plan with neither branch protection nor rulesets answers this 403 to the
    # rulesets read and to /protection (read live 2026-10-28, ShiftLead/agent-cadence; the branch
    # itself reads 200, protection disabled): nothing can be required there.
    PLAN_LACKS = "Upgrade to GitHub Pro"

    def required_checks(self, branch: str) -> list[str]:
        """The check names GitHub requires on `branch` before a merge (TD-178): branch
        protection's required status checks, read from the branch itself (which needs no admin,
        where /protection does), and each ruleset's `required_status_checks` rule. [] is nothing
        required, and so is the plan's 403 (PLAN_LACKS); any other failure raises."""
        b = quote(branch, safe="/")
        names: set[str] = set()
        try:
            br = self._json(["api", f"repos/{{owner}}/{{repo}}/branches/{b}"])
        except ForgeUnreadable as e:
            if self.PLAN_LACKS not in str(e):
                raise
            br = {}
        prot = (br or {}).get("protection") or {}
        if prot.get("enabled"):
            rsc = prot.get("required_status_checks") or {}
            names.update(c for c in rsc.get("contexts") or [] if c)
            names.update(c.get("context") for c in rsc.get("checks") or [] if c.get("context"))
        try:
            rules = self._lines(["api", "--paginate", f"repos/{{owner}}/{{repo}}/rules/branches/{b}?per_page=100",
                                 "--jq", ".[]"])
        except ForgeUnreadable as e:
            if self.PLAN_LACKS not in str(e):
                raise
            rules = []
        for r in rules:
            if r.get("type") == "required_status_checks":
                names.update(c.get("context") for c in (r.get("parameters") or {}).get("required_status_checks") or []
                             if c.get("context"))
        return sorted(names)

    def named_status(self, sha: str, name: str) -> list[dict]:
        """The latest status called `name` on sha — on GitHub check_runs already lists every
        status, so this only re-reads them (TD-118's GitLab needs the call)."""
        return [st for st in self.statuses(sha) if st.get("name") == name]

    def set_status(self, sha: str, ok: bool, context: str, description: str) -> None:
        """Record a commit status on sha (TD-117): no Actions minutes, and it stays on the
        commit after the session ends. GitHub caps the description at 140 characters."""
        self._run(["api", "-X", "POST", f"repos/{{owner}}/{{repo}}/statuses/{sha}",
                   "-f", f"state={'success' if ok else 'failure'}", "-f", f"context={context}",
                   "-f", f"description={description[:140]}"], env=_QUIET)

    @staticmethod
    def head_ref(n) -> str:
        """The ref origin serves a PR's head under — a fork's head included."""
        return f"refs/pull/{int(n)}/head"

    def _not_started(self, run_id) -> str | None:
        """The annotation saying Actions never started this check run's job, or None. An
        unreadable answer is None: the run stays red, as it read before."""
        try:
            notes = self._json(["api", f"repos/{{owner}}/{{repo}}/check-runs/{int(run_id)}/annotations"])
        except (ForgeUnreadable, ValueError, TypeError):
            return None
        for a in notes if isinstance(notes, list) else []:
            msg = (a.get("message") or "").strip() if isinstance(a, dict) else ""
            if msg.startswith(_NOT_STARTED):
                return msg
        return None

    def ci_runs_registered(self, sha: str) -> list[dict]:
        """[{status, conclusion}] of the workflow runs registered for sha — a run may exist
        before its check runs do (TD-079)."""
        return self._lines(["api", f"repos/{{owner}}/{{repo}}/actions/runs?head_sha={sha}&per_page=20",
                            "--jq", ".workflow_runs[] | {status, conclusion}"])

    def ci_active_workflows(self) -> int:
        return int(self._run(["api", "repos/{owner}/{repo}/actions/workflows", "--jq",
                              '[.workflows[] | select(.state == "active")] | length']).strip() or 0)

    # -- settings ----------------------------------------------------------------------------

    def repo_settings(self, slug: str) -> tuple[int, str, str]:
        """(rc, the repo's JSON, stderr) — the settings line reads the fields it wants."""
        return self.call(["api", f"repos/{slug}"])

    def settings_lines(self, slug: str) -> str:
        """One "name=value" line per wanted setting, as the API gives it (null unreadable)."""
        jq = ",\n".join(f'        "{k}=\\(.{k})"' for k in self.settings_wanted)
        return self._run(["api", f"repos/{slug}", "--jq", "\n" + jq])

    def patch_settings(self, slug: str, pairs: list[str]) -> None:
        args = ["api", "-X", "PATCH", f"repos/{slug}"]
        for p in pairs:
            args += ["-F", p]
        self._run(args)

    # -- the remote tier (budgeted; each returns (rc, out, err) as the tier reads it) --------

    def whoami(self) -> tuple[int, str, str]:
        return self.call(["api", "user", "--jq", ".login"])

    def owners(self) -> tuple[int, str, str]:
        return self.call(["api", "user/orgs", "--jq", ".[].login"])

    def list_repos(self, owner: str, limit: int) -> tuple[int, str, str]:
        """JSON [{name, archived}] on rc 0."""
        rc, out, err = self.call(["repo", "list", owner, "--json", "nameWithOwner,isArchived",
                                  "--limit", str(limit)])
        if rc == 0:
            try:
                out = json.dumps([{"name": r["nameWithOwner"], "archived": bool(r.get("isArchived"))}
                                  for r in json.loads(out)])
            except (ValueError, KeyError, TypeError):
                pass   # the caller reports it unparseable
        return rc, out, err

    def read_file(self, repo: str, path: str) -> tuple[int, str, str]:
        """The file's text on rc 0; rc NOT_FOUND when the forge says there is none."""
        rc, out, err = self.call(["api", f"repos/{repo}/contents/{path}",
                                  "-H", "Accept: application/vnd.github.raw"])
        return (NOT_FOUND if rc > 0 and "HTTP 404" in err else rc), out, err


# --- GitLab -----------------------------------------------------------------------------


# The squash template the cadence wants (cadence.md §4.2, read 2026-10-13): the subject ends
# "(!N)", the body carries every commit's message, trailers included. `%{co_authored_by}`
# would name the commits' authors, not their Co-Authored-By: lines, so it is not used.
GITLAB_SQUASH_TEMPLATE = "%{title} (%{local_reference})\n\n%{all_commits}"
# A pipeline's status, as a check run's (status, conclusion).
_PIPELINE = {"success": ("completed", "success"), "failed": ("completed", "failure"),
             "canceled": ("completed", "cancelled"), "skipped": ("completed", "skipped"),
             "manual": ("completed", "action_required")}


# A GitLab commit status's state in check-run shape (TD-118); pending, running and created
# are still running.
_STATUS = {"success": ("completed", "success"), "failed": ("completed", "failure"),
           "canceled": ("completed", "cancelled"), "skipped": ("completed", "skipped"),
           "manual": ("completed", "action_required")}   # as _PIPELINE reads a manual one


class GitLab(_CLI):
    """`glab` against GitLab (TD-104), built on what a real project returned (glab 1.123.0,
    gitlab.com, 2026-10-13: the plan's *GitLab, as read*). Every call is `glab api` against
    the REST endpoints with the project named outright (`projects/<group%2Frepo>`, on
    `--hostname`), never glab's cwd placeholders, so a call answers for the repo the slug
    names wherever it runs."""

    name = "gitlab"
    cli = "glab"
    # The cadence's template marks a squash "(!N)"; a merge_method=merge project's merge
    # commit is "Merge branch '…' into '…'", which a local merge also writes, so it is not
    # matched here — it is in the merged list whenever the forge can be read.
    subject_re = re.compile(r"\(!\d+\)$")
    settings_wanted = {"merge_method": "ff", "squash_option": "always",
                       "remove_source_branch_after_merge": True,
                       "squash_commit_template": GITLAB_SQUASH_TEMPLATE}
    auto_delete = "remove_source_branch_after_merge"
    not_squash_hint = (" — a merge_method = merge project lands a merge commit around the squash; "
                       "the cadence wants merge_method ff with squash_option always "
                       + ("(agent-cadence run adopt_repo_settings.sh)" if os.environ.get("CADENCE_REPO_ROOT", "").strip()
                          else "(scripts/adopt_repo_settings.sh)"))   # TD-164: a pinned repo has no scripts/

    def __init__(self, slug: str | None = None, **kw):
        super().__init__(slug=slug, **kw)
        host, _, path = (slug or "").partition("/")
        self.host, self.path = host or "gitlab.com", path
        self.project = f"projects/{quote(path, safe='')}"

    @staticmethod
    def ref(n) -> str:
        return f"!{n}"

    @staticmethod
    def retarget_hint(n, base: str) -> str:
        return f"`glab mr update {n} --target-branch {base}`"

    @staticmethod
    def landed_pr_hint(branch: str) -> str:
        return f"glab mr list --source-branch {branch} --merged"

    def auth_scope(self) -> list[str]:
        return ["--hostname", self.host]

    def _api(self, endpoint: str, *extra: str) -> list[str]:
        return ["api", "--hostname", self.host, endpoint, *extra]

    def _get(self, endpoint: str, paginate: bool = False):
        if not paginate:
            return self._json(self._api(endpoint))
        try:
            return _pages(self._run(self._api(endpoint, "--paginate")))
        except ValueError as e:
            raise ForgeUnreadable(f"{self.cli} gave unparseable JSON ({e})") from None

    # -- MRs ---------------------------------------------------------------------------------

    @classmethod
    def record(cls, m: dict) -> dict:
        """GitLab's MR JSON as the neutral record. Under ff + always-squash the landed commit
        is squash_commit_sha and merge_commit_sha is empty ("" from one MR, null in a list)."""
        n = m.get("iid")
        state = str(m.get("state") or "")
        return {
            "number": n,
            "ref": cls.ref(n),
            "url": m.get("web_url"),
            "state": {"opened": "open", "locked": "open"}.get(state, state),  # merged | closed
            "title": m.get("title"),
            "body": m.get("description"),
            "base": m.get("target_branch"),
            "head": m.get("source_branch"),
            "head_sha": m.get("sha"),
            "cross_repo": (m["source_project_id"] != m["target_project_id"]
                           if m.get("source_project_id") and m.get("target_project_id") else None),
            "merged_at": m.get("merged_at"),
            "merge_sha": m.get("merge_commit_sha") or m.get("squash_commit_sha") or None,
            "files": [],
            "updated_at": m.get("updated_at"),
            "created_at": m.get("created_at"),
            "draft": bool(m.get("draft")),
        }

    def pr(self, n) -> dict:
        rec = self.record(self._get(f"{self.project}/merge_requests/{int(n)}"))
        diffs = self._get(f"{self.project}/merge_requests/{int(n)}/diffs?per_page=100", paginate=True)
        rec["files"] = [d.get("new_path") for d in diffs or []]
        return rec

    def prs_for_branch(self, branch: str, limit: int = 5) -> list[dict]:
        q = urlencode({"source_branch": branch, "state": "all", "order_by": "created_at",
                       "sort": "desc", "per_page": limit})
        return [self.record(m) for m in self._get(f"{self.project}/merge_requests?{q}")]

    def prs_naming(self, text: str, limit: int = 50) -> list[dict]:
        """MRs in any state whose title or description the search matches `text` (a superset:
        the caller filters)."""
        q = urlencode({"search": text, "in": "title,description", "state": "all",
                       "order_by": "created_at", "sort": "desc", "per_page": limit})
        return [self.record(m) for m in self._get(f"{self.project}/merge_requests?{q}")]

    def merged_since(self, when: str, limit: int) -> list[dict]:
        """The MRs merged at or after `when`. The API filters on updated_after (a merge updates
        the MR, so nothing merged in the window is missed); merged_at is filtered here."""
        q = urlencode({"state": "merged", "updated_after": when, "order_by": "updated_at",
                       "sort": "desc", "per_page": 100})
        cut = _ts(when)
        got = [self.record(m) for m in self._get(f"{self.project}/merge_requests?{q}", paginate=True)]
        return [r for r in got if cut is None or (_ts(r["merged_at"]) or cut) >= cut][:limit]

    def open_prs(self, limit: int, timeout: float) -> list[dict]:
        """Open MRs, oldest first, each with created_at, draft and its notes as {trusted, body}
        — trusted when the author is a Developer or above on the project. The notes cost a
        call per MR that has any, so they are read only while the timeout lasts; an MR past
        it keeps an empty list (no "reviewed" mark, never a wrong one)."""
        end = time.monotonic() + timeout
        q = urlencode({"state": "opened", "order_by": "created_at", "sort": "asc", "per_page": limit})
        mrs = json.loads(self._run(self._api(f"{self.project}/merge_requests?{q}"), timeout=timeout,
                                   env=_QUIET_GLAB) or "[]")
        out, members = [], None
        for m in mrs:
            rec = self.record(m)
            rec["comments"] = []
            left = end - time.monotonic()
            if m.get("user_notes_count") and left > 0.5:
                try:
                    if members is None:  # the first 100 only: anyone past them reads as untrusted
                        members = {u.get("username"): u.get("access_level") or 0 for u in json.loads(
                            self._run(self._api(f"{self.project}/members/all?per_page=100"),
                                      timeout=left, env=_QUIET_GLAB) or "[]")}
                    rec["comments"] = [
                        {"trusted": members.get(c["author"], 0) >= 30, "body": c["body"]}
                        for c in self.comments(m.get("iid"), timeout=end - time.monotonic())]
                except (ForgeUnreadable, ValueError, TypeError, AttributeError):
                    pass
            out.append(rec)
        return out

    def comments(self, n, timeout: float | None = None) -> list[dict]:
        """[{author, created_at, updated_at, body}] of the MR's notes, oldest first, GitLab's
        own events (system notes) left out. A token that cannot read notes gets 403 here —
        "cannot read", never "no review" (…/discussions would answer [] instead)."""
        if timeout is not None and timeout <= 0:
            raise ForgeUnreadable("out of time before the notes were read")
        try:
            raw = _pages(self._run(self._api(
                f"{self.project}/merge_requests/{int(n)}/notes?sort=asc&order_by=created_at&per_page=100",
                "--paginate"), timeout=timeout))
        except ValueError as e:
            raise ForgeUnreadable(f"{self.cli} gave unparseable JSON ({e})") from None
        return [{"author": (c.get("author") or {}).get("username"), "created_at": c.get("created_at"),
                 "updated_at": c.get("updated_at"), "body": c.get("body")}
                for c in raw if not c.get("system")]

    def commit_parents(self, sha: str) -> int:
        return len(self._get(f"{self.project}/repository/commits/{sha}").get("parent_ids") or [])

    # -- CI: pipelines -------------------------------------------------------------------

    def check_runs(self, sha: str) -> list[dict]:
        """[{name, status, conclusion}], one per pipeline on sha (the push's and the MR's).
        A pipeline that failed with no jobs never ran (a new gitlab.com account's runner
        verification read this way, 2026-10-13): its conclusion is "not_run", which the ci
        row names as no evidence, never as a red build. A broken .gitlab-ci.yml also fails
        with no jobs, so the pipeline's own yaml_errors is read first: set, it stays red."""
        out, external = [], {}
        for p in self._get(f"{self.project}/pipelines?sha={sha}&per_page=100"):
            if p.get("source") == "external":
                # opened by a commit status posted from outside CI (precheck's cadence/precheck,
                # TD-118) and holding only such statuses: read as them, by name, never as an
                # anonymous pipeline beside them
                external[p.get("id")] = p
                continue
            status, conclusion = _PIPELINE.get(p.get("status"), (p.get("status"), None))
            if p.get("status") == "failed" and not self._get(
                    f"{self.project}/pipelines/{p.get('id')}/jobs?include_retried=true&per_page=1"):
                try:
                    broken = self._get(f"{self.project}/pipelines/{p.get('id')}").get("yaml_errors")
                except (ForgeUnreadable, AttributeError):
                    broken = None
                conclusion = "failure" if broken else "not_run"
            out.append({"name": f"pipeline {p.get('id')} ({p.get('source')})",
                        "status": status, "conclusion": conclusion})
        if external:
            held = [st for st in self.statuses(sha) if st.get("pipeline_id") in external]
            out += held
            # one whose statuses did not come back (a race, a page past the first) is kept as a
            # pipeline: its verdict is never dropped
            for pid, p in external.items():
                if not any(st.get("pipeline_id") == pid for st in held):
                    status, conclusion = _PIPELINE.get(p.get("status"), (p.get("status"), None))
                    out.append({"name": f"pipeline {pid} (external)", "status": status,
                                "conclusion": conclusion})
        return out

    @staticmethod
    def head_ref(n) -> str:
        return f"refs/merge-requests/{int(n)}/head"

    def statuses(self, sha: str, name: str | None = None) -> list[dict]:
        """[{name, status, conclusion, kind, pipeline_id}] — the latest commit status per name on
        sha (GitLab's default; `all=true` would list each post), only `name`'s when given, in
        check-run shape (TD-118). Read on the probe project, 2026-10-15: a status posted to a
        commit with no pipeline opens one of `source: external` holding it; posted to a commit
        whose ref already has a pipeline, it joins that pipeline (whose status then follows it)
        and is listed by neither pipeline's jobs."""
        q = f"&name={quote(name, safe='')}" if name else ""
        out = []
        for st in self._get(f"{self.project}/repository/commits/{sha}/statuses?per_page=100{q}", paginate=True):
            status, conclusion = _STATUS.get(st.get("status"), ("in_progress", None))
            if conclusion == "failure" and st.get("allow_failure"):
                conclusion = "neutral"
            out.append({"name": st.get("name"), "kind": "status", "status": status,
                        "conclusion": conclusion, "description": st.get("description"),
                        "pipeline_id": st.get("pipeline_id")})
        return out

    def named_status(self, sha: str, name: str) -> list[dict]:
        """The latest status called `name` on sha — one check_runs misses when it joined a CI
        pipeline rather than opening an external one (TD-118)."""
        return self.statuses(sha, name)

    def set_status(self, sha: str, ok: bool, context: str, description: str) -> None:
        """Record a commit status on sha (TD-118): `failed` is GitLab's word for failure (any
        other state is a 400), and the description is capped at 255 characters (a longer
        one is refused, read 2026-10-15)."""
        self._run(self._api(f"{self.project}/statuses/{sha}", "-X", "POST",
                            "-f", f"state={'success' if ok else 'failed'}", "-f", f"name={context}",
                            "-f", f"description={description[:255]}"), env=_QUIET_GLAB)

    @staticmethod
    def ci_runs_registered(sha: str) -> list[dict]:
        """GitLab creates the pipeline with the push (both were there when the MR was read), so
        there is no registered-but-not-listed run to wait for: check_runs lists it, pending."""
        return []

    @staticmethod
    def ci_active_workflows() -> int:
        return 0

    # -- settings ----------------------------------------------------------------------------

    def _project_for(self, slug: str) -> "GitLab":
        return self if slug.lower() == f"{self.host}/{self.path}".lower() else GitLab(
            slug=slug, cwd=self.cwd, spent=self.spent, per_call=self.per_call, total=self.total)

    def repo_settings(self, slug: str) -> tuple[int, str, str]:
        """(rc, the project's JSON, stderr). A key the JSON lacks is one this token cannot see."""
        g = self._project_for(slug)
        return g.call(g._api(g.project))

    def settings_lines(self, slug: str) -> str:
        rc, out, err = self.repo_settings(slug)
        if rc != 0:
            msg = (err or out).strip()
            raise ForgeUnreadable(msg.splitlines()[-1] if msg else f"{self.cli} failed")
        try:
            got = json.loads(out)
        except ValueError as e:
            raise ForgeUnreadable(f"{self.cli} gave unparseable JSON ({e})") from None
        # null is "this token cannot see it" (adopt_repo_settings.sh's word); a key that is
        # there but null (the squash template, until set) is "unset": drift, not unreadable
        return "".join(f"{k}={'null' if k not in got else 'unset' if got[k] is None else show(got[k])}\n"
                       for k in self.settings_wanted)

    def patch_settings(self, slug: str, pairs: list[str]) -> None:
        g = self._project_for(slug)
        args = g._api(g.project, "-X", "PUT")
        for p in pairs:
            k, _, v = p.partition("=")
            v = unshow(v)
            args += ["-F", f"{k}={str(v).lower()}"] if isinstance(v, bool) else ["-f", f"{k}={v}"]
        g._run(args)

    # -- the remote tier (TD-110; read off gitlab.com with glab 1.123.0, 2026-10-14) ------------
    # Each returns (rc, out, err) as GitHub's do. Repos are `group/sub/repo` on this backend's
    # host; the tier puts the host in front.

    def _call_json(self, endpoint: str, paginate: bool = False) -> tuple[int, object, str]:
        rc, out, err = self.call(self._api(endpoint, *(["--paginate"] if paginate else [])))
        if rc != 0:
            # glab prints only "glab: HTTP 403" for some refusals; GitLab's own words are on stdout
            try:
                body = json.loads(out)
                why = body.get("error_description") or body.get("message") if isinstance(body, dict) else None
            except ValueError:
                why = None
            err = (err or out).strip()
            return rc, None, f"{err} ({why})" if why and str(why) not in err else err
        try:
            return 0, _pages(out) if paginate else json.loads(out), ""
        except ValueError as e:
            return 1, None, f"{self.cli} gave unparseable JSON ({e})"

    def whoami(self) -> tuple[int, str, str]:
        rc, got, err = self._call_json("user")
        if rc == 0 and not (isinstance(got, dict) and got.get("username")):
            return 1, "", f"{self.cli} could not name the user"
        return rc, got["username"] if rc == 0 else "", err

    def owners(self) -> tuple[int, str, str]:
        """The groups the user is a member of, one full_path a line, a subgroup left out when
        its parent is listed (the parent's listing includes it). A fine-grained token without
        Group: Read answers 403 here, read 2026-10-14: the caller says so."""
        rc, got, err = self._call_json("groups?min_access_level=10&per_page=100", paginate=True)
        if rc != 0:
            return rc, "", err
        paths = [g["full_path"] for g in got if isinstance(g, dict) and g.get("full_path")]
        return 0, "\n".join(p for p in paths
                            if not any(p.startswith(q + "/") for q in paths)), ""

    def list_repos(self, owner: str, limit: int) -> tuple[int, str, str]:
        """JSON [{name, archived}] on rc 0. A group's projects with its subgroups'; a name that
        is no group (404) is read as a user's namespace."""
        q = "per_page=100"
        rc, got, err = self._call_json(f"groups/{quote(owner, safe='')}/projects?include_subgroups=true&{q}",
                                       paginate=True)
        if rc > 0 and "(HTTP 404)" in err:
            rc, got, err = self._call_json(f"users/{quote(owner, safe='')}/projects?{q}", paginate=True)
        if rc != 0:
            return rc, "", err
        try:
            return 0, json.dumps([{"name": p["path_with_namespace"], "archived": bool(p.get("archived"))}
                                  for p in got][:limit]), ""
        except (KeyError, TypeError):
            return 0, "not a project list", ""   # the caller reports it unparseable

    def read_file(self, repo: str, path: str) -> tuple[int, str, str]:
        """The file's text on rc 0; rc NOT_FOUND when the project has no such file, or no
        commit at all (an empty project: "404 Commit Not Found"). A missing project — or one
        this token cannot see, which GitLab answers the same — is an error, not NOT_FOUND."""
        rc, out, err = self.call(self._api(f"projects/{quote(repo, safe='')}/repository/files/"
                                           f"{quote(path, safe='')}/raw?ref=HEAD"))
        if rc > 0 and "(HTTP 404)" in err and "Project Not Found" not in err:
            return NOT_FOUND, out, err
        return rc, out, err


# GitLab's notes call runs from the SessionStart hook too: glab must never prompt there.
_QUIET_GLAB = {"NO_PROMPT": "true"}


def nothing_left(root: "Path | str", base: str | None, head_sha: str | None,
                 timeout: float = 5.0) -> bool | None:
    """True when a PR has nothing left to merge: every file its head changed since its
    merge-base with origin/<base> is already the same on origin/<base> — its changes landed by
    another PR (one stacked on it and squash-merged first: shiftlead#1728, TD-114). False when
    one still differs. None when git here cannot tell: the head commit not fetched (a fork's),
    no origin/<base>, a git error or the timeout. Local git only — no forge call; a stale
    origin/<base> mostly reads a superseded PR as False, but a file the base changed back since
    the last fetch can read a live one as True — fetch first (the sweep does)."""
    if not base or base.startswith("-") or not re.fullmatch(r"[0-9a-fA-F]{7,64}", head_sha or ""):
        return None
    end = time.monotonic() + timeout

    def git(*args: str) -> str | None:
        left = end - time.monotonic()
        if left <= 0:
            return None
        try:
            r = subprocess.run(["git", "-C", str(root), *args], check=False, capture_output=True,
                               text=True, timeout=left)
        except (OSError, subprocess.SubprocessError):
            return None
        return r.stdout if r.returncode == 0 else None

    ref = f"refs/remotes/origin/{base}"
    mb = git("merge-base", ref, head_sha)
    if not mb:
        return None
    mine = git("diff", "--no-renames", "--name-only", "-z", mb.strip(), head_sha)
    differ = git("diff", "--no-renames", "--name-only", "-z", ref, head_sha)
    if mine is None or differ is None:
        return None
    return not ({f for f in mine.split("\0") if f} & {f for f in differ.split("\0") if f})


def unseen_push(root: "Path | str", branch: str | None, head_sha: str | None,
                timeout: float = 5.0) -> str | None:
    """TD-186: this checkout's tip (full sha) when it has a PR's head ``branch`` checked out and
    holds a commit the forge's ``head_sha`` lacks — a push the PR API has not caught up on yet, or
    one never pushed. None when another branch (or none) is checked out, the tip is ``head_sha``
    or behind it (someone else pushed), ``head_sha`` is not here, or git cannot tell. Local git
    only, no fetch: a session runs its gate from the worktree it pushed from."""
    if not branch or not re.fullmatch(r"[0-9a-fA-F]{7,64}", head_sha or ""):
        return None

    def git(*args: str) -> subprocess.CompletedProcess | None:
        try:
            return subprocess.run(["git", "-C", str(root), *args], check=False, capture_output=True,
                                  text=True, timeout=timeout)
        except (OSError, subprocess.SubprocessError):
            return None

    on = git("symbolic-ref", "-q", "--short", "HEAD")
    tip = git("rev-parse", "-q", "--verify", "HEAD^{commit}")
    if not on or on.returncode != 0 or on.stdout.strip() != branch or not tip or tip.returncode != 0:
        return None
    tip_sha = tip.stdout.strip()
    if tip_sha.lower().startswith(head_sha.lower()):
        return None
    anc = git("merge-base", "--is-ancestor", tip_sha, head_sha)
    # 0: the tip is in the head's history (the forge has more); 1: it is not; else head_sha is unknown here
    return tip_sha if anc is not None and anc.returncode == 1 else None


def head_lag(root: "Path | str", pr: dict, timeout: float = 10.0) -> tuple[str, str] | None:
    """TD-186: (where, sha) when the head the forge's PR API names is not its branch's newest
    commit — the API lags a push by seconds. ``where`` is origin's branch when ``git ls-remote``
    reads it at another commit (git sees a push at once, from any checkout), else this checkout's
    branch when ``unseen_push`` finds a commit the head lacks. None for a fork's PR (its branch is
    neither origin's nor this checkout's), a branch origin does not hold, or when git cannot tell."""
    head, sha = pr.get("head"), pr.get("head_sha")
    if pr.get("cross_repo") or not head or head.startswith("-") \
            or not re.fullmatch(r"[0-9a-fA-F]{7,64}", sha or ""):
        return None
    try:
        r = subprocess.run(["git", "-C", str(root), "ls-remote", "origin", f"refs/heads/{head}"],
                           check=False, capture_output=True, text=True, timeout=timeout)
        tip = (r.stdout.split() or [""])[0] if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        tip = ""
    if re.fullmatch(r"[0-9a-f]{40,64}", tip) and not tip.startswith(sha.lower()):
        return f"origin's {head}", tip
    local = unseen_push(root, head, sha)
    return (f"this checkout's {head}", local) if local else None


PR_SEARCH_LIMIT = 100   # in_flight's page per search; a full one reads as "cannot see all"


def in_flight(root: "Path | str", tid: str, f=None, timeout: float = 30.0) -> tuple[list[str], int]:
    """Is ledger entry `tid` (TD-NNN) already being worked — cadence.md §2.9's check before a TD,
    or one step of one, and again right before the work starts. Three lookups, one line each:
    the PRs naming the id in any state, origin's branches naming it (`td137-…`, `TD-137-…`), and
    the entry's Status on origin/<default> after a fetch of it. (lines, rc): rc 1 when an open
    or merged PR (other than the one that filed the entry) or a branch names it, or the entry is
    archived there; 0 when nothing does; 2 when a lookup could not be made or the id is in
    neither file — a "cannot see" is never "none". The filing PR is known by its squash commit,
    so in a repo that merges with merge commits it is counted (the safe direction); a merged PR
    naming the id only in its since-deleted head branch is not found (the search reads titles
    and bodies)."""
    root = Path(root)
    m = re.fullmatch(r"(?i)TD-?0*(\d+)", tid.strip())
    if not m:
        return [f"{tid!r} is not a ledger id (TD-NNN)"], 2
    n = int(m.group(1))
    tid = f"TD-{n:03d}"
    names = re.compile(rf"(?i)(?<![A-Za-z0-9#])TD-?0*{n}(?!\d)")   # `<repo>#TD-NNN` is another repo's (§2.2)
    pr_lines, branch_lines, status_lines = [], [], []
    found, blind, filer = 0, False, None

    def git(*args: str) -> str | None:
        try:
            r = subprocess.run(["git", "-C", str(root), *args], check=False, capture_output=True,
                               text=True, timeout=timeout, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
        except (OSError, subprocess.SubprocessError):
            return None
        return r.stdout if r.returncode == 0 else None

    # the entry's Status on origin/<default>, fetched first, and the commit that filed it
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import ledgerboard as LB  # sibling SYNC file: the ledger's format, read once
    import nudge_user_attention as N  # sibling SYNC script: the default-branch rule (§9)
    base = N.default_branch(root)
    stale = ""
    if git("fetch", "--quiet", "origin", base) is None:
        stale, blind = " (not fetched: as last fetched)", True
    import ledger as L  # sibling SYNC script: the ledger in either layout, read at a ref (TD-160)
    io = L.git_io(root, f"refs/remotes/origin/{base}", "docs")
    rel = L.ledger_at(root, io) if io else L.LEDGER_REL
    text, arch = L.read_pair(rel, None, io) if io else (None, "")
    ent = None
    why_not = text is not None and (LB.version_problem(text) or L.v2_unread(rel, io))
    if why_not:
        status_lines.append(f"Status: cannot read {rel} on origin/{base} — {why_not}")
        blind = True
    elif text is None:
        status_lines.append(f"Status: cannot see — no {L.LEDGER_REL} on origin/{base} (nor a {L.LEDGER_DIR_REL}/)")
        blind = True
    else:
        ent = next((e for e in LB.entries(text) if LB._num(e["id"]) == n), None)
        if ent is None:
            if LB.version_problem(arch):
                blind = True
                status_lines.append(f"Status: {tid} is not in the ledger, and the archive cannot be read — {LB.version_problem(arch)}")
            elif any(LB._num(e["id"]) == n for e in LB.entries(arch)):
                found += 1
                status_lines.append(f"Status: {tid} is archived on origin/{base}{stale} — resolved")
            else:
                blind = True
                status_lines.append(f"Status: {tid} is in neither the ledger nor the archive on origin/{base}{stale}")
        else:
            status = (ent["fields"].get("status") or "(no Status)").strip()
            status_lines.append(f"Status on origin/{base}{stale}: "
                                + (status if len(status) <= 200 else status[:199] + "…"))
            # the oldest commit that wrote the heading is the squash of the PR that filed the entry
            # (a line-anchored -G, never -S: the seed's template comment holds `## TD-001:` too);
            # an entry filed after a split (v2) has no such commit: the one that added its file
            added = git("log", "--reverse", "--format=%H", "-G", f"^## {re.escape(ent['id'])}:",
                        f"refs/remotes/origin/{base}", "--", L.LEDGER_REL)
            efile = LB.entry_path(rel, ent["id"], io[0]) if io and io[0](rel) is not None else None
            if not (added or "").strip() and efile:
                added = git("log", "--reverse", "--format=%H", "--diff-filter=A",
                            f"refs/remotes/origin/{base}", "--", efile)
            filer = (added or "").split("\n")[0] or None
    # the forge: a PR whose title, body or head branch names the id
    try:
        f = f or backend(root)
        got, full = {}, False
        for q in dict.fromkeys((f"TD-{n}", tid)):   # a ledger writes TD-24 or TD-024: ask for both
            page = f.prs_naming(q, PR_SEARCH_LIMIT)
            full = full or len(page) >= PR_SEARCH_LIMIT
            for p in page:
                got.setdefault(p.get("number"), p)
        if full:   # the search is a superset: a full page may have dropped the PR that names it
            pr_lines.append(f"PRs: cannot see all — the search filled its page of {PR_SEARCH_LIMIT}")
            blind = True
        prs = [p for p in got.values()
               if any(names.search(p.get(k) or "") for k in ("title", "body", "head"))]
    except ForgeUnreadable as e:
        pr_lines.append(f"PRs: cannot see — {e}")
        blind, prs = True, []
    for p in sorted(prs, key=lambda p: p.get("number") or 0):
        why = ("  (filed the entry: not in flight)" if filer and p.get("merge_sha") == filer
               else "" if p.get("state") in ("open", "merged") else "  (closed unmerged: not in flight)")
        found += not why
        pr_lines.append(f"PR {p.get('ref')} {p.get('state')}  {p.get('head') or '?'}  {p.get('title') or ''}{why}")
    # origin's branches, asked live
    heads = git("ls-remote", "--heads", "origin")
    if heads is None:
        branch_lines.append("branches: cannot see — `git ls-remote origin` failed")
        blind = True
    else:
        for ln in heads.splitlines():
            ref = ln.split("\t", 1)[-1].removeprefix("refs/heads/")
            if names.search(ref):
                found += 1
                branch_lines.append(f"branch origin/{ref}")
    lines = pr_lines + branch_lines + status_lines
    if found:
        lines.append(f"{tid}: in flight — an open PR or a branch: reconcile with it; merged or archived: verify on {base}")
        return lines, 1
    if blind:
        lines.append(f"{tid}: cannot tell — see the line above that could not be read")
        return lines, 2
    lines.append(f"{tid}: nothing in flight")
    return lines, 0


def _ts(s):
    """An ISO time as an aware datetime; a bare date or a zoneless time reads as UTC, so
    `--since 2026-10-01` compares with GitLab's zoned merged_at instead of raising."""
    from datetime import datetime, timezone
    try:
        t = datetime.fromisoformat(str(s).replace("Z", "+00:00")) if s else None
    except ValueError:
        return None
    return t.replace(tzinfo=timezone.utc) if t and t.tzinfo is None else t


def _pages(text: str) -> list:
    """`glab api --paginate` output as one list. How glab 1.123 joins pages was not read
    (TD-104's facts came from one-page answers); gh writes them back to back (`[..][..]`),
    so each JSON value is decoded in turn and the lists are joined either way."""
    out, dec, i, text = [], json.JSONDecoder(), 0, text.strip()
    while i < len(text):
        v, i = dec.raw_decode(text, i)
        out += v if isinstance(v, list) else [v]
        while i < len(text) and text[i].isspace():
            i += 1
    return out


def show(v) -> str:
    """A setting's value as one `name=value` line carries it: true/false/null, a plain word
    as is, anything with a newline, a quote or a space as a JSON string (GitLab's template)."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    v = str(v)
    return v if re.fullmatch(r"[A-Za-z0-9_.:-]+", v) else json.dumps(v)


def unshow(v: str):
    """show()'s inverse: true/false as booleans, a JSON string as its text, else the word."""
    if v in ("true", "false"):
        return v == "true"
    if v.startswith('"'):
        try:
            return json.loads(v)
        except ValueError:
            pass
    return v


def repo_key(line: str) -> tuple[str, str] | None:
    """(host, owner/repo) of a machine-scope list line (remote_repos.txt, no_auto_delete.txt):
    `host/owner/repo` (`host/group/sub/repo` on GitLab), or the older `owner/repo`, which
    reads as github.com. None when the line is neither."""
    parts = line.strip().strip("/").split("/")
    if len(parts) == 2 and all(parts):
        return "github.com", "/".join(parts).lower()
    if len(parts) >= 3 and all(parts) and "." in parts[0]:
        return parts[0].lower(), "/".join(parts[1:]).lower()
    return None


# --- CLI (adopt_repo_settings.sh) -------------------------------------------


def _for_slug(slug: str) -> "GitHub | GitLab":
    key = repo_key(slug)
    if key is None:
        raise ForgeUnreadable(f"{slug!r} is neither owner/repo nor host/owner/repo")
    # the checkout's own origin is classified with its forge setting, so a GitLab host not
    # named gitlab.* (forge = "gitlab") is still GitLab to adopt_repo_settings.sh
    kind, here = origin_forge(Path("."))
    if is_gitlab_host(key[0]) or (kind == "gitlab" and here and here.lower() == f"{key[0]}/{key[1]}"):
        return GitLab(slug=f"{key[0]}/{key[1]}")
    if key[0] != "github.com" or key[1].count("/") != 1:
        raise ForgeUnreadable(forge_unread_line(key[0]))
    return GitHub(slug=key[1])


def origin_slug(root: "Path | str") -> str:
    """The SLUG of the repo at root, from origin (never `gh repo view`, which prefers an
    upstream remote, TD-058): owner/repo on github.com, host/path on GitLab."""
    kind, slug = origin_forge(Path(root))
    if kind == "github" and slug:
        host, _ = _origin(Path(root))
        return slug if host in (None, "github.com") else f"{host}/{slug}"
    if kind == "gitlab" and slug:
        return slug
    if kind == "other":
        raise ForgeUnreadable(forge_unread_line(slug or "?"))
    raise ForgeUnreadable("origin names no repo the forge can be asked about")


def main(argv: list[str] | None = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="the forge adapter (TD-103)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    h = sub.add_parser("has-cli")
    h.add_argument("slug", nargs="?")
    sub.add_parser("origin-slug")
    w = sub.add_parser("wanted")
    w.add_argument("slug")
    w.add_argument("--no-auto-delete", action="store_true")
    s = sub.add_parser("repo-settings")
    s.add_argument("slug")
    p = sub.add_parser("patch-settings")
    p.add_argument("slug")
    p.add_argument("pairs", nargs="+")
    n = sub.add_parser("nothing-left")
    n.add_argument("number", type=int)
    i = sub.add_parser("in-flight")
    i.add_argument("id")
    a = ap.parse_args(argv)
    if a.cmd == "in-flight":
        try:
            out, rc = in_flight(".", a.id)
        except Exception as e:   # noqa: BLE001 — a crash is "cannot tell" (2), never "in flight" (1)
            print(f"{a.id}: cannot tell — in-flight failed: {type(e).__name__}: {e}", file=sys.stderr)
            return 2
        print("\n".join(out))
        return rc
    if a.cmd == "origin-slug":
        try:
            print(origin_slug("."))
        except ForgeUnreadable as e:
            print(e, file=sys.stderr)
            return 2
        return 0
    try:
        f = backend(".") if not getattr(a, "slug", None) else _for_slug(a.slug)
    except ForgeUnreadable as e:
        print(e, file=sys.stderr)
        return 2
    if a.cmd == "has-cli":
        gone = f.missing()
        if gone:
            print(gone, file=sys.stderr)
            return 2
        return 0
    if a.cmd == "check":
        why = f.check()
        if why:
            print(why, file=sys.stderr)
            return 2
        return 0
    if a.cmd == "nothing-left":
        try:
            pr = f.pr(a.number)
        except ForgeUnreadable as e:
            print(e, file=sys.stderr)
            return 2
        if pr.get("state") != "open":
            print(f"{f.ref(a.number)} is {pr.get('state') or 'not open'}, not open — nothing to close")
            return 1
        left = nothing_left(".", pr.get("base"), pr.get("head_sha"))
        if left is None:
            print(f"cannot tell: {f.ref(a.number)}'s head {pr.get('head_sha') or '?'} or "
                  f"origin/{pr.get('base') or '?'} is not here (git fetch origin)", file=sys.stderr)
            return 2
        print(f"{f.ref(a.number)} nothing left to merge — close it as superseded" if left
              else f"{f.ref(a.number)} has changes left to merge")
        return 0 if left else 1
    if a.cmd == "wanted":
        sys.stdout.write("".join(f"{k}={show(v)}\n" for k, v in f.settings_wanted.items()
                                 if not (a.no_auto_delete and k == f.auto_delete)))
        return 0
    key = repo_key(a.slug)   # _for_slug has read it
    slug = f"{key[0]}/{key[1]}" if isinstance(f, GitLab) else key[1]
    try:
        if a.cmd == "repo-settings":
            sys.stdout.write(f.settings_lines(slug))
        else:
            f.patch_settings(slug, a.pairs)
    except ForgeUnreadable as e:
        print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
