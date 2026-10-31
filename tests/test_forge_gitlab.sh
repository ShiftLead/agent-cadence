#!/usr/bin/env bash
# TD-104: forge.py's GitLab backend. `glab` is a PATH shim answering from JSON fixtures in the
# shapes a real project returned (glab 1.123.0, gitlab.com, 2026-10-13 — the forge plan's
# *GitLab, as read*): the MR object, its diffs, its notes (system notes among them), the
# pipelines on a sha and their jobs, the project's settings. Covered: the classifier, every
# check_cadence.py row that reads the forge, the SessionStart open-MR line and settings line,
# forge.py check, adopt_repo_settings.sh's check and apply.
#
# Offline: origin names a GitLab host, but GIT_ALLOW_PROTOCOL=file stops any fetch before it
# leaves the machine; origin/main is made with update-ref. HOME, XDG_CONFIG_HOME,
# AGENT_CADENCE_REG_DIR and git config are temp. Timestamps derive from the run date (TD-24).
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_ALLOW_PROTOCOL=file
unset CADENCE_FORGE
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- the glab shim: `api --hostname H <endpoint> [flags]` answered from $FAKE/<file> ---------
FAKE="$TMP/fake"; BIN="$TMP/bin"; mkdir -p "$FAKE" "$BIN"
cat > "$BIN/glab" <<'SHIM'
#!/usr/bin/env python3
import os, re, sys
a = sys.argv[1:]
open(os.environ["GLAB_LOG"], "a").write(" ".join(a) + "\n")
F = os.environ["FAKE_DIR"]
if a[:2] == ["auth", "status"]:
    sys.exit(0 if os.path.exists(f"{F}/authed") else 1)
if a[:1] != ["api"]:
    print(f"glab-shim: unhandled: {a}", file=sys.stderr); sys.exit(64)
ep = next(x for x in a[1:] if x.startswith("projects/") or x == "user")
method = a[a.index("-X") + 1] if "-X" in a else "GET"
path = ep.split("?")[0]
name = {  # endpoint → fixture file
    r"projects/[^/]+$": "project.json",
    r"projects/[^/]+/merge_requests$": "mr_create.json" if method == "POST" else "mrlist.json",
    r"projects/[^/]+/merge_requests/(\d+)$": r"mr_\1.json",
    r"projects/[^/]+/merge_requests/(\d+)/diffs$": r"diffs_\1.json",
    r"projects/[^/]+/merge_requests/(\d+)/notes$": r"notes_\1.json",
    r"projects/[^/]+/members/all$": "members.json",
    r"projects/[^/]+/repository/commits/(\w+)$": r"commit_\1.json",
    r"projects/[^/]+/pipelines$": "pipelines.json",
    r"projects/[^/]+/pipelines/(\d+)$": r"pipeline_\1.json",
    r"projects/[^/]+/pipelines/(\d+)/jobs$": r"jobs_\1.json",
    r"projects/[^/]+/repository/commits/(\w+)/statuses$": r"statuses_\1.json",
    r"projects/[^/]+/statuses/(\w+)$": "status_post.json",
}
if method == "POST" and "/statuses/" in path:
    open(f"{F}/post.args", "w").write(__import__("json").dumps(a))
for pat, f in name.items():
    m = re.fullmatch(pat, path)
    if m:
        f = m.expand(f)
        if method == "PUT":
            open(f"{F}/put.args", "w").write(__import__("json").dumps(a))
        if os.path.exists(f"{F}/{f}.err"):
            print(open(f"{F}/{f}.err").read().strip(), file=sys.stderr); sys.exit(1)
        if os.path.exists(f"{F}/{f}"):
            body = open(f"{F}/{f}").read()
            q = dict(kv.split("=", 1) for kv in ep.partition("?")[2].split("&") if "=" in kv)
            if f.startswith("statuses_") and "name" in q:   # GitLab's ?name= filter
                from urllib.parse import unquote
                body = __import__("json").dumps([x for x in __import__("json").loads(body) if x["name"] == unquote(q["name"])])
            sys.stdout.write(body); sys.exit(0)
        print('{"message":"404 Not found"}glab: 404 Not found (HTTP 404)', file=sys.stderr); sys.exit(1)
print(f"glab-shim: unhandled api {ep}", file=sys.stderr); sys.exit(64)
SHIM
chmod +x "$BIN/glab"
export PATH="$BIN:$PATH" FAKE_DIR="$FAKE" GLAB_LOG="$TMP/glab.log"
touch "$FAKE/authed"

ts() { date -u -d "$1" +%Y-%m-%dT%H:%M:%S.000Z; }
MERGED=$(ts "2 hours ago"); BEFORE=$(ts "3 hours ago"); AFTER=$(ts "1 hour ago"); OLD=$(ts "5 days ago")

R="$TMP/repo"; git init -q -b main "$R"
mkdir -p "$R/docs"; echo base > "$R/base.txt"; printf '# ledger\n' > "$R/docs/technical_debt.md"
git -C "$R" add . && git -C "$R" commit -qm base
git -C "$R" remote add origin https://gitlab.example.com/grp/sub/thing.git
git -C "$R" update-ref refs/remotes/origin/main HEAD
classify() { (cd "$1" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import forge; print(*forge.origin_forge("."))' "$S"); }

# 1. the classifier: gitlab.com and a host whose first label is gitlab are GitLab under auto
C="$TMP/cls"; git init -q "$C"
while IFS='|' read -r url want; do
    git -C "$C" remote remove origin 2>/dev/null; git -C "$C" remote add origin "$url"
    [ "$(classify "$C")" = "$want" ] && ok "1 origin_forge: $url → $want" || bad "1 $url: got '$(classify "$C")', want '$want'"
done <<'T'
git@gitlab.com:Group/Thing.git|gitlab gitlab.com/group/thing
https://gitlab.com/group/sub/thing|gitlab gitlab.com/group/sub/thing
ssh://git@gitlab.corp.example:2222/a/b.git|gitlab gitlab.corp.example/a/b
https://code.corp.example/a/b.git|other code.corp.example
https://mygitlab.example/a/b.git|other mygitlab.example
T
git -C "$C" remote set-url origin https://code.corp.example/a/b.git
[ "$(cd "$C" && CADENCE_FORGE=gitlab classify .)" = "gitlab code.corp.example/a/b" ] && ok "1 forge=gitlab: a GitLab under any host" || bad "1 forge=gitlab: $(cd "$C" && CADENCE_FORGE=gitlab classify .)"
git -C "$C" remote set-url origin /srv/git/thing.git
out=$(cd "$C" && CADENCE_FORGE=gitlab python3 "$S/check_cadence.py" --pr 1 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "origin names no project" <<< "$out" && ok "1 forge=gitlab with a hostless origin: cannot check, saying why" || bad "1 hostless rc=$rc: $out"

# --- fixtures for check_cadence.py ---------------------------------------------------------
SQ=$(printf 'a%.0s' {1..40}); HEAD_SHA=$(printf 'b%.0s' {1..40}); MC=$(printf 'c%.0s' {1..40})
mr() {  # n state merge_commit_sha squash_commit_sha target merged_at
    cat > "$FAKE/mr_$1.json" <<J
{"iid": $1, "web_url": "https://gitlab.example.com/grp/sub/thing/-/merge_requests/$1", "state": "$2",
 "title": "topic $1", "description": "body", "source_branch": "topic$1", "target_branch": "$5",
 "sha": "$HEAD_SHA", "merged_at": $6, "merge_commit_sha": $3, "squash_commit_sha": $4,
 "updated_at": "$MERGED", "created_at": "$OLD", "draft": false, "user_notes_count": 2,
 "source_project_id": 9, "target_project_id": 9,
 "references": {"short": "!$1"}}
J
    echo '[{"old_path": "src/a.py", "new_path": "src/a.py"}]' > "$FAKE/diffs_$1.json"
}
notes() {  # n body-of-the-review created_at
    cat > "$FAKE/notes_$1.json" <<J
[{"id": 1, "body": "mentioned in commit $SQ", "author": {"username": "bot"}, "created_at": "$BEFORE", "updated_at": "$BEFORE", "system": true},
 {"id": 2, "body": "$2", "author": {"username": "rev"}, "created_at": "$3", "updated_at": "$3", "system": false}]
J
}
echo "{\"id\": \"$SQ\", \"parent_ids\": [\"$(printf 'd%.0s' {1..40})\"]}" > "$FAKE/commit_$SQ.json"
echo "{\"id\": \"$MC\", \"parent_ids\": [\"1111111111111111111111111111111111111111\", \"2222222222222222222222222222222222222222\"]}" > "$FAKE/commit_$MC.json"
pipelines() { echo "$1" > "$FAKE/pipelines.json"; }
rows() { (cd "$R" && python3 "$S/check_cadence.py" --pr "$1" --json 2>&1); }
get() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read())["prs"][0]; r={x["rule"]: x for x in d["rows"]}[sys.argv[1]]; print(r["status"], r["detail"])' "$1"; }

# 2. a merged ff + always-squash MR: merge_commit_sha "" and the squash sha is what landed
mr 3 merged '""' "\"$SQ\"" main "\"$MERGED\""
notes 3 "cadence-review: SHIP · sonnet · code · 0 findings" "$BEFORE"
pipelines "[{\"id\": 7, \"status\": \"success\", \"source\": \"merge_request_event\"}]"
out=$(rows 3)
[ "$(get pr <<< "$out")" = "pass merged ${SQ:0:7}, one parent (squash inferred)" ] && ok "2a pr row: the squash_commit_sha, one parent" || bad "2a: $(get pr <<< "$out")"
get review <<< "$out" | grep -q "^pass SHIP · sonnet · code · 0 findings · 60 min before merge" && ok "2b review row: the note, system notes ignored" || bad "2b: $(get review <<< "$out")"
[ "$(get ci <<< "$out")" = "pass 1 check run(s) green on ${HEAD_SHA:0:7}" ] && ok "2c ci row: a green pipeline" || bad "2c: $(get ci <<< "$out")"
[ "$(get base <<< "$out")" = "pass base is main" ] && ok "2d base row: target_branch" || bad "2d: $(get base <<< "$out")"
python3 -c 'import json,sys; d=json.loads(sys.stdin.read())["prs"][0]; sys.exit(d["state"] != "MERGED" or not d["url"].endswith("/merge_requests/3"))' <<< "$out" \
    && ok "2e the record: state MERGED, the MR's url" || bad "2e: $out"

# 3. merge_method = merge: a two-parent merge commit fails the pr row, which names the setting
mr 4 merged "\"$MC\"" "\"$SQ\"" main "\"$MERGED\""; notes 4 "cadence-review: SHIP · sonnet · code · 0 findings" "$BEFORE"
get pr <<< "$(rows 4)" | grep -q "^fail merge commit ${MC:0:7} has 2 parents — not a squash — a merge_method = merge project" \
    && ok "3 pr row: a merge-method MR fails, naming merge_method" || bad "3: $(get pr <<< "$(rows 4)")"

# 4. a pipeline that failed with no jobs never ran: unknown, not a red build; one with jobs is red
pipelines '[{"id": 8, "status": "failed", "source": "merge_request_event"}]'; echo '[]' > "$FAKE/jobs_8.json"
get ci <<< "$(rows 3)" | grep -q "^unknown pipeline 8 (merge_request_event) on ${HEAD_SHA:0:7} ended failed with no jobs" \
    && ok "4a ci row: failed with no jobs is unknown" || bad "4a: $(get ci <<< "$(rows 3)")"
echo '{"id": 8, "status": "failed", "yaml_errors": "jobs config should contain at least one visible job"}' > "$FAKE/pipeline_8.json"
[ "$(get ci <<< "$(rows 3)")" = "fail not green on ${HEAD_SHA:0:7}: pipeline 8 (merge_request_event)" ] && ok "4a' ci row: no jobs but yaml_errors (a broken .gitlab-ci.yml) is red" || bad "4a': $(get ci <<< "$(rows 3)")"
rm "$FAKE/pipeline_8.json"
echo '[{"id": 1, "status": "failed"}]' > "$FAKE/jobs_8.json"
[ "$(get ci <<< "$(rows 3)")" = "fail not green on ${HEAD_SHA:0:7}: pipeline 8 (merge_request_event)" ] && ok "4b ci row: failed with jobs is red" || bad "4b: $(get ci <<< "$(rows 3)")"
pipelines '[{"id": 9, "status": "running", "source": "push"}]'
get ci <<< "$(rows 3)" | grep -q "^unknown still running on ${HEAD_SHA:0:7}: pipeline 9 (push)" && ok "4c ci row: a running pipeline" || bad "4c: $(get ci <<< "$(rows 3)")"
pipelines '[]'
[ "$(get ci <<< "$(rows 3)")" = "na no check runs on the head commit" ] && ok "4d ci row: no pipeline is na" || bad "4d: $(get ci <<< "$(rows 3)")"

# 4e–4i. TD-118: precheck's cadence/precheck status, in the shapes the probe project returned
# (a scratch gitlab.com project, 2026-10-15). Posted to a commit with no pipeline it opens one
# of source "external"; posted where a pipeline ran it joins that one, whose status follows it.
st() {  # status pipeline_id → the statuses answer, the probe's fields (author left out)
    echo "[{\"id\": 17187434199, \"sha\": \"$HEAD_SHA\", \"ref\": \"main\", \"status\": \"$1\", \"name\": \"cadence/precheck\",
      \"target_url\": null, \"description\": \"passed in 3s: ./run_tests.sh\", \"allow_failure\": false, \"coverage\": null, \"pipeline_id\": $2}]" > "$FAKE/statuses_$HEAD_SHA.json"
}
mr 6 opened '""' '""' main null; notes 6 "cadence-review: SHIP · sonnet · code · 0 findings" "$BEFORE"
printf 'precheck = "./run_tests.sh"\n' > "$R/docs/cadence.toml"
pipelines '[{"id": 2948924545, "status": "success", "source": "external"}]'; st success 2948924545
[ "$(get ci <<< "$(rows 6)")" = "pass 1 check run(s) green on ${HEAD_SHA:0:7}" ] && ok "4e ci row: a precheck status in its external pipeline is read as the status, once" || bad "4e: $(get ci <<< "$(rows 6)")"
pipelines '[{"id": 2945092541, "status": "success", "source": "push"}]'; echo '[]' > "$FAKE/jobs_2945092541.json"
[ "$(get ci <<< "$(rows 6)")" = "pass 2 check run(s) green on ${HEAD_SHA:0:7}" ] && ok "4f ci row: a precheck status that joined a push pipeline is found by name" || bad "4f: $(get ci <<< "$(rows 6)")"
pipelines '[{"id": 2945092541, "status": "failed", "source": "push"}]'; st failed 2945092541
get ci <<< "$(rows 6)" | grep -q "^fail not green on ${HEAD_SHA:0:7}: cadence/precheck" && ok "4g ci row: a failed precheck is red, though its no-jobs pipeline reads never-ran" || bad "4g: $(get ci <<< "$(rows 6)")"
rm "$FAKE/statuses_$HEAD_SHA.json"; echo '[]' > "$FAKE/statuses_$HEAD_SHA.json"
get ci <<< "$(rows 6)" | grep -q "^unknown precheck is set (docs/cadence.toml) and ${HEAD_SHA:0:7} carries no cadence/precheck status" && ok "4h ci row: no precheck status is unknown" || bad "4h: $(get ci <<< "$(rows 6)")"
rm "$R/docs/cadence.toml"
pipelines '[{"id": 2948924546, "status": "failed", "source": "external"}]'
echo "[{\"id\": 2, \"status\": \"failed\", \"name\": \"other/scan\", \"allow_failure\": false, \"pipeline_id\": 2948924546}]" > "$FAKE/statuses_$HEAD_SHA.json"
[ "$(get ci <<< "$(rows 6)")" = "fail not green on ${HEAD_SHA:0:7}: other/scan; ⚠ no \`precheck\` in docs/cadence.toml — the merge gate is a CI run that spends the shared Actions minutes; set it (cadence §4.12)" ] && ok "4h' ci row: another integration's status is read by its name, with no precheck set" || bad "4h': $(get ci <<< "$(rows 6)")"
echo '[]' > "$FAKE/statuses_$HEAD_SHA.json"
[ "$(get ci <<< "$(rows 6)")" = "fail not green on ${HEAD_SHA:0:7}: pipeline 2948924546 (external); ⚠ no \`precheck\` in docs/cadence.toml — the merge gate is a CI run that spends the shared Actions minutes; set it (cadence §4.12)" ] && ok "4h'' an external pipeline whose statuses did not come back is kept, never dropped" || bad "4h'': $(get ci <<< "$(rows 6)")"
echo '{"id": 1, "status": "failed", "name": "cadence/precheck"}' > "$FAKE/status_post.json"
(cd "$R" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import forge; forge.backend(".").set_status(sys.argv[2], False, "cadence/precheck", "x" * 300)' "$S" "$HEAD_SHA") 2>&1
python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); assert "-X" in a and a[a.index("-X")+1]=="POST" and f"projects/grp%2Fsub%2Fthing/statuses/{sys.argv[2]}" in a and "state=failed" in a and "name=cadence/precheck" in a and ("description=" + "x"*255) in a, a' "$FAKE/post.args" "$HEAD_SHA" \
    && ok "4i set_status: POST statuses/<sha>, state=failed (GitLab's word), name, the description capped at 255" || bad "4i: $(cat "$FAKE/post.args" 2>&1)"

# 4j. TD-118's Done when: precheck.py --pr on a GitLab MR records cadence/precheck, and the ci
# row passes on it. A `git` shim answers only the head fetch (origin is a GitLab URL nobody
# serves here; the commit is already local) and passes everything else to git.
REAL_SHA=$(git -C "$R" rev-parse HEAD); GB="$TMP/gitbin"; mkdir -p "$GB"
printf '#!/usr/bin/env bash\nfor a; do [ "$a" = fetch ] && exit 0; done\nexec %s "$@"\n' "$(command -v git)" > "$GB/git"; chmod +x "$GB/git"
HEAD_SHA=$REAL_SHA mr 7 opened '""' '""' main null; notes 7 "cadence-review: SHIP · sonnet · code · 0 findings" "$BEFORE"
printf 'precheck = "true"\n' > "$R/docs/cadence.toml"; rm -f "$FAKE/post.args"
echo "{\"id\": 3, \"sha\": \"$REAL_SHA\", \"status\": \"success\", \"name\": \"cadence/precheck\", \"pipeline_id\": 2948924547}" > "$FAKE/status_post.json"
out=$(cd "$R" && PATH="$GB:$PATH" python3 "$S/precheck.py" --pr 7 2>&1); rc=$?
[ $rc = 0 ] && grep -q "recorded cadence/precheck = success on ${REAL_SHA:0:7}" <<< "$out" && grep -q "state=success" "$FAKE/post.args" && grep -q "statuses/$REAL_SHA" "$FAKE/post.args" \
    && ok "4j precheck.py on a GitLab MR: runs, records cadence/precheck on the head, exit 0" || bad "4j rc=$rc: $out / $(cat "$FAKE/post.args" 2>&1)"
pipelines '[{"id": 2948924547, "status": "success", "source": "external"}]'
echo "[{\"id\": 3, \"status\": \"success\", \"name\": \"cadence/precheck\", \"allow_failure\": false, \"pipeline_id\": 2948924547}]" > "$FAKE/statuses_$REAL_SHA.json"
[ "$(get ci <<< "$(rows 7)")" = "pass 1 check run(s) green on ${REAL_SHA:0:7}" ] && ok "4j' the ci row passes on the status it recorded" || bad "4j': $(get ci <<< "$(rows 7)")"
rm "$R/docs/cadence.toml"

# 5. notes a fine-grained token cannot read (403) are "unreadable", never "no review"
echo 'glab: 403 Forbidden - insufficient_granular_scope (HTTP 403)' > "$FAKE/notes_3.json.err"
get review <<< "$(rows 3)" | grep -q "^unknown comments unreadable: glab: 403" && ok "5 review row: a 403 on notes is unknown" || bad "5: $(get review <<< "$(rows 3)")"
rm "$FAKE/notes_3.json.err"

# 6. an open MR retargeted at another branch: the base row's advice is glab's
mr 5 opened '""' '""' topic3 null; notes 5 "lgtm" "$BEFORE"
get base <<< "$(rows 5)" | grep -q "glab mr update 5 --target-branch main" && ok "6 base row: the retarget hint is glab's" || bad "6: $(get base <<< "$(rows 5)")"

# 7. --branch and --since: MRs by source branch; merged_at filtered to the window
echo "[$(cat "$FAKE/mr_3.json")]" > "$FAKE/mrlist.json"
out=$(cd "$R" && python3 "$S/check_cadence.py" --branch topic3 --json 2>&1)
python3 -c 'import json,sys; sys.exit(json.loads(sys.stdin.read())["prs"][0]["pr"] != 3)' <<< "$out" && grep -q 'source_branch=topic3' "$GLAB_LOG" \
    && ok "7a --branch: the MR whose source branch it is" || bad "7a: $out"
python3 - "$FAKE/mrlist.json" "$(ts '30 days ago')" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))[0]
old = dict(m, iid=2, merged_at=sys.argv[2])     # updated in the window, merged before it
json.dump([m, old], open(sys.argv[1], "w"))
PY
out=$(cd "$R" && python3 "$S/check_cadence.py" --since 7d --json 2>&1)
python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit([r["pr"] for r in d["prs"]] != [3])' <<< "$out" \
    && ok "7b --since: an MR merged before the window is left out" || bad "7b: $out"
out=$(cd "$R" && python3 "$S/check_cadence.py" --since "$(date -u -d '7 days ago' +%F)" --json 2>&1)
python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit([r["pr"] for r in d["prs"]] != [3])' <<< "$out" \
    && ok "7c --since a bare date: compared as UTC, no traceback" || bad "7c: $out"
# glab's --paginate output joined back to back ([..][..]) still reads as one list
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); open(sys.argv[1],"w").write(json.dumps(m[:1]) + json.dumps(m[1:]))' "$FAKE/mrlist.json"
out=$(cd "$R" && python3 "$S/check_cadence.py" --since 7d --json 2>&1)
python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit([r["pr"] for r in d["prs"]] != [3])' <<< "$out" \
    && ok "7d --paginate pages back to back read as one list" || bad "7d: $out"

# 8. the nudge: the open-MR line names !N and a trusted review; the settings line
cat > "$FAKE/mrlist.json" <<J
[{"iid": 11, "title": "stale one", "state": "opened", "created_at": "$OLD", "draft": false, "user_notes_count": 1},
 {"iid": 12, "title": "fresh", "state": "opened", "created_at": "$AFTER", "draft": false, "user_notes_count": 0}]
J
notes 11 "cadence-review: FIXED · sonnet · code · 1 findings" "$BEFORE"
echo '[{"username": "rev", "access_level": 30}]' > "$FAKE/members.json"
nudge() { python3 - "$S" "$R" "$1" <<'PY'
import sys, pathlib, time
sys.path.insert(0, sys.argv[1]); import nudge_user_attention as N
root = pathlib.Path(sys.argv[2])
if sys.argv[3] == "prs":
    print("\n".join(N.open_pr_lines(root, time.monotonic() + 30)) or "NONE")
else:
    print(N.settings_line(root, {"t": 0.0, "hit": False}))
PY
}
out=$(nudge prs)
grep -q "^  • !11 stale one (5d open, reviewed FIXED — unmerged)$" <<< "$out" && ! grep -q '!12' <<< "$out" \
    && ok "8a open-MR line: !N, the trusted review marked" || bad "8a: $out"
echo '[{"username": "rev", "access_level": 20}]' > "$FAKE/members.json"
grep -q "^  • !11 stale one (5d open)$" <<< "$(nudge prs)" && ok "8b a Reporter's review line is not trusted" || bad "8b: $(nudge prs)"
want_tpl='%{title} (%{local_reference})\n\n%{all_commits}'
proj() { printf '{"path_with_namespace": "grp/sub/thing", "default_branch": "main", "merge_method": "%s", "squash_option": "%s", "remove_source_branch_after_merge": %s, "squash_commit_template": %s}\n' "$@" > "$FAKE/project.json"; }
proj ff always true "\"$want_tpl\""
[ "$(nudge settings)" = None ] && ok "8c settings line: the cadence's settings, no line" || bad "8c: $(nudge settings)"
proj merge default_off true null
out=$(nudge settings)
grep -q "merge_method merge, squash_option default_off, squash_commit_template unset" <<< "$out" && ok "8d settings line: a new project's defaults named" || bad "8d: $out"
grep -q 'projects/grp%2Fsub%2Fthing' "$GLAB_LOG" && grep -q -- '--hostname gitlab.example.com' "$GLAB_LOG" \
    && ok "8e the project is named outright on its host" || bad "8e: $(tail -3 "$GLAB_LOG")"

# 9. forge.py check
rm "$FAKE/authed"
out=$(cd "$R" && python3 "$S/forge.py" check 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "glab is not authenticated" <<< "$out" && grep -q 'auth status --hostname gitlab.example.com' "$GLAB_LOG" \
    && ok "9d check: glab unauthenticated on the origin's host" || bad "9d rc=$rc: $out"
touch "$FAKE/authed"

# 10. adopt_repo_settings.sh: check, apply (the template sent intact), and from origin
proj merge default_off false null
out=$(cd "$R" && bash "$S/adopt_repo_settings.sh" --check 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q "repo from this checkout's origin: gitlab.example.com/grp/sub/thing" <<< "$out" \
    && grep -q "DRIFT  squash_commit_template *unset" <<< "$out" && grep -q "DRIFT  merge_method *merge" <<< "$out" \
    && ok "10a --check from origin: GitLab's four settings, drift named" || bad "10a rc=$rc: $out"
out=$(cd "$R" && bash "$S/adopt_repo_settings.sh" --apply --yes 2>&1); rc=$?
python3 - "$FAKE/put.args" <<'PY' && ok "10b --apply: one PUT, booleans typed, the template's newlines intact" || bad "10b: $(cat "$FAKE/put.args")"
import json, sys
a = json.load(open(sys.argv[1]))
pairs = [a[i + 1] for i, x in enumerate(a) if x in ("-f", "-F")]
want = ["merge_method=ff", "squash_option=always", "remove_source_branch_after_merge=true",
        "squash_commit_template=%{title} (%{local_reference})\n\n%{all_commits}"]
sys.exit(not (pairs == want and a[a.index("-F") + 1] == "remove_source_branch_after_merge=true"))
PY
out=$(bash "$S/adopt_repo_settings.sh" --check --no-auto-delete gitlab.example.com/grp/sub/thing 2>&1)
! grep -q remove_source_branch <<< "$out" && ok "10c --no-auto-delete leaves the delete-source default out" || bad "10c: $out"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("merge_method"); json.dump(d, open(sys.argv[1],"w"))' "$FAKE/project.json"
out=$(bash "$S/adopt_repo_settings.sh" --check gitlab.example.com/grp/sub/thing 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q "merge_method as null" <<< "$out" && ok "10d a setting the token cannot see: cannot verify" || bad "10d rc=$rc: $out"

# 11. forge = "gitlab" on a host not named gitlab.*: the CLI's slug path agrees with origin
proj ff always true "\"$want_tpl\""
git -C "$R" remote set-url origin https://code.corp.example/grp/sub/thing.git
out=$(cd "$R" && CADENCE_FORGE=gitlab bash "$S/adopt_repo_settings.sh" --check 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "repo from this checkout's origin: code.corp.example/grp/sub/thing" <<< "$out" \
    && grep -q -- '--hostname code.corp.example' "$GLAB_LOG" && ok "11 forge=gitlab, any host: adopt_repo_settings.sh reads GitLab" || bad "11 rc=$rc: $out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
