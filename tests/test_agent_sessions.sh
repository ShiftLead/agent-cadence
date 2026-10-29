#!/usr/bin/env bash
# TD-100: the session adapter (files/scripts/agent_sessions.py). Every safety net that asks
# about sessions — the anchor guard, the reaper's idle gate, the session index, the sweep
# row — gets "cannot see <tool>" when a tool the repo lists (the `agents` setting) cannot be
# looked at, never "nobody here". Offline: HOME is a temp dir; no real registry is read.
set -u
DC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DC/files/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AGENT_CADENCE_REG_DIR="$TMP/reg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CADENCE_AGENTS CODEX_HOME
mkdir -p "$HOME" "$AGENT_CADENCE_REG_DIR"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

R="$TMP/repo"; git init -q -b main "$R"; git -C "$R" commit -q --allow-empty -m init
hook() { (cd "$R" && echo '{"session_id":"me","cwd":"'"$R"'"}' | python3 "$S/check_anchor.py" --hook 2>&1); }
seen() { (cd "$R" && PYTHONPATH="$S" python3 -c 'import agent_sessions as A; s = A.live(); print(len(s.items), "|", "; ".join(s.blind))' 2>&1); }

# --- 1) no Claude state at all, agents = claude (the default): cannot see, never "the anchor"
out=$(hook)
grep -q "anchor check: cannot see claude sessions: no .*/.claude/sessions" <<< "$out" \
    && ok "anchor guard, no registry: says it cannot see" || bad "no registry: '$out'"
out=$(cd "$R" && python3 "$S/check_anchor.py" 2>&1)
grep -q "cannot see claude sessions" <<< "$out" && ! grep -q "this session is the anchor" <<< "$out" \
    && ok "standalone, no registry: no 'you are the anchor'" || bad "standalone: '$out'"

# --- 2) an empty registry is a real answer: nobody else here, and the hook stays silent
mkdir -p "$HOME/.claude/sessions"
out=$(hook)
[ -z "$out" ] && ok "an empty registry: the hook is silent (seen, nobody here)" || bad "empty registry: '$out'"
[ "$(seen)" = "0 | " ] && ok "live(): empty and not blind" || bad "live empty: $(seen)"

# --- 3) a tool with no backend, listed in agents: blind, by name — env and the repo's file
out=$(cd "$R" && echo '{"session_id":"me","cwd":"'"$R"'"}' | CADENCE_AGENTS="claude, othertool" python3 "$S/check_anchor.py" --hook 2>&1)
grep -q "cannot see othertool sessions: no backend for othertool" <<< "$out" \
    && ok "agents names a tool with no backend: the guard names it" || bad "unknown tool: '$out'"
mkdir -p "$R/docs"; printf 'agents = "claude,othertool"\n' > "$R/docs/cadence.toml"
grep -q "othertool sessions: no backend" <<< "$(seen)" && ok "agents read from docs/cadence.toml" || bad "repo file: $(seen)"
rm "$R/docs/cadence.toml"

# --- 3b) an unreadable settings file is blind, not a quiet fallback to claude alone
printf 'agents = "claude, othertool\n' > "$R/docs/cadence.toml"
grep -q "the agents setting could not be read" <<< "$(seen)" && ok "a malformed docs/cadence.toml: named as blind" || bad "bad toml: $(seen)"
rm "$R/docs/cadence.toml"
# --- 3c) a partial sync (no agent_sessions.py beside the guard): one line, no traceback
P="$TMP/partial"; mkdir -p "$P"; cp "$S/check_anchor.py" "$P/"
out=$(cd "$R" && echo '{}' | python3 "$P/check_anchor.py" --hook 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "agent_sessions.py is missing" <<< "$out" && ! grep -q Traceback <<< "$out" \
    && ok "agent_sessions.py missing: one line, exit 0" || bad "partial: rc=$rc '$out'"

# --- 4) a tool not listed and absent is not required: no Claude state, agents = othertool only
rm -rf "$HOME/.claude"
out=$(cd "$R" && CADENCE_AGENTS=othertool PYTHONPATH="$S" python3 -c 'import agent_sessions as A; print("; ".join(A.live().blind))')
grep -q "othertool" <<< "$out" && ! grep -q "claude" <<< "$out" \
    && ok "claude unlisted and absent: not blind for claude, still blind for the listed tool" || bad "unlisted: '$out'"

# --- 5) an unreadable registry is blind, not empty (the reaper's old listdir lesson)
mkdir -p "$HOME/.claude/sessions"; echo '{"sessionId":"x","pid":1,"cwd":"/"}' > "$HOME/.claude/sessions/1.json"
chmod 000 "$HOME/.claude/sessions"
if [ -r "$HOME/.claude/sessions" ]; then
    ok "unreadable registry: skipped (running as root, chmod does not bite)"
else
    grep -q "unreadable" <<< "$(seen)" && ok "unreadable registry: blind, not empty" || bad "unreadable: $(seen)"
fi
chmod 755 "$HOME/.claude/sessions"; rm -rf "$HOME/.claude"

# --- 6) the session index says the same: a listed tool it cannot see is named, not skipped
mkdir -p "$HOME/.claude/projects"
out=$(cd "$R" && CADENCE_AGENTS="claude, othertool" python3 "$S/list_sessions.py" --repo "$R" 2>&1)
grep -q "cannot see othertool transcripts: no backend" <<< "$out" \
    && ok "list_sessions: a blind tool named" || bad "list_sessions: '$out'"

# --- 7) the reaper: a listed tool it cannot see reaps nothing, even a landed worktree
mkdir -p "$HOME/.claude/sessions"
W="$TMP/rr"; git init -q --bare -b main "$W.git"; git clone -q "$W.git" "$W" 2>/dev/null
( cd "$W" && git checkout -q -b main 2>/dev/null; mkdir -p scripts
  cp "$S/check_anchor.py" "$S/agent_sessions.py" "$S/cadence_config.py" "$S/reap_worktrees.sh" scripts/
  echo b > b.txt; git add .; git commit -qm b; git push -q -u origin main
  git worktree add -q -b wt .claude/worktrees/wt origin/main
  ( cd .claude/worktrees/wt && echo w >> b.txt && git commit -qam w )
  git merge -q --squash wt >/dev/null && git commit -qm "wt (#1)" && git push -q origin main && git fetch -q origin )
out=$(cd "$W" && CADENCE_AGENTS="claude, othertool" scripts/reap_worktrees.sh --reap 2>&1)
grep -q "could not read the live-session registry" <<< "$out" && [ -d "$W/.claude/worktrees/wt" ] \
    && ok "the reaper with an unseen tool: warns, reaps nothing" || bad "reaper unseen: $out"
out=$(cd "$W" && scripts/reap_worktrees.sh --reap 2>&1)
[ ! -d "$W/.claude/worktrees/wt" ] && ok "the same worktree with every listed tool seen: reaped" || bad "reaper seen: $out"
rm -rf "$HOME/.claude"

# --- 8) resume advice comes from the backend
[ "$(PYTHONPATH="$S" python3 -c 'import agent_sessions as A; print(A.resume_hint("abc"))')" = "claude --resume abc" ] \
    && ok "resume_hint: claude's" || bad "resume_hint"

# --- 9) the Gemini CLI backend (TD-109): a fixture ~/.gemini in the shapes read off 0.64.0
G="$HOME/.gemini"; NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z); SID=11111111-2222-4333-8444-555555555555
mkdir -p "$G/tmp/repo/chats" "$G/tmp/wt1/chats" "$G/tmp/other/chats" "$HOME/.claude/sessions" "$HOME/.claude/projects"
printf '{\n  "projects": {\n    "%s": "repo",\n    "%s/.claude/worktrees/wt1": "wt1",\n    "/elsewhere": "other"\n  }\n}' "$R" "$R" > "$G/projects.json"
printf '%s' "$R" > "$G/tmp/repo/.project_root"
gchat() {  # file sessionId first-user reply
    { printf '{"sessionId":"%s","projectHash":"x","startTime":"%s","lastUpdated":"%s","kind":"main"}\n' "$2" "$NOW" "$NOW"
      printf '{"id":"p","timestamp":"%s","type":"user","content":[{"text":"<session_context>\\nThis is the Gemini CLI."}]}\n' "$NOW"
      printf '{"$set":{"lastUpdated":"%s"}}\n' "$NOW"
      printf '{"id":"u","timestamp":"%s","type":"user","content":[{"text":"%s"}]}\n' "$NOW" "$3"
      printf '{"id":"g","timestamp":"%s","type":"gemini","content":"%s","model":"m"}\n' "$NOW" "$4"
      printf '{"$set":{"summary":"the summary"}}\n'; } > "$1"
}
gchat "$G/tmp/repo/chats/session-a-11111111.jsonl" "$SID" "fix the ledger" "done, PR open"
gchat "$G/tmp/wt1/chats/session-b-11111111.jsonl" 11111111-0000-0000-0000-000000000000 "in the worktree" "ok"
gchat "$G/tmp/other/chats/session-c-22222222.jsonl" 22222222-0000-0000-0000-000000000000 "elsewhere" "no"
out=$(cd "$R" && CADENCE_AGENTS="claude,gemini" python3 "$S/list_sessions.py" --repo "$R" 2>&1)
grep -q "^● $SID" <<< "$out" && grep -q "started: fix the ledger" <<< "$out" && grep -q "ended:   done, PR open" <<< "$out" \
    && grep -q "resume:  gemini --resume $SID" <<< "$out" && grep -q "summary: the summary" <<< "$out" \
    && ok "9a list_sessions: a Gemini session, its preamble skipped, its resume line" || bad "9a: $out"
grep -q "in the worktree" <<< "$out" && grep -qF "[$R/.claude/worktrees/wt1]" <<< "$out" && ! grep -q elsewhere <<< "$out" \
    && ok "9b list_sessions: the worktree's Gemini session, another project's left out" || bad "9b: $out"
[ "$(PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; print(A.ever_ran(sys.argv[1]))' "$R")" = True ] \
    && ok "9c ever_ran: a Gemini history counts" || bad "9c ever_ran"
rm "$G/projects.json"
grep -q "fix the ledger" <<< "$(cd "$R" && CADENCE_AGENTS=gemini python3 "$S/list_sessions.py" --repo "$R" 2>&1)" \
    && ok "9d without projects.json the slug is found by .project_root" || bad "9d"
echo '{"projects": []}' > "$G/projects.json"
grep -q "Gemini CLI's session files have moved on.*projects.json is not" <<< "$(hook)" \
    && ok "9e the canary names a projects.json of another shape" || bad "9e: $(hook)"
rm "$G/projects.json"
# live: a process named node running .../bin/gemini, which relaunches itself as a child (the npm
# shim's pair) — one session, cwd in the main checkout. node here is python3 under that name.
# /proc is the machine's: a real session elsewhere is in live() too, so only this run's cwds count.
NB="$TMP/npm/bin"; mkdir -p "$NB"; ln -s "$(command -v python3)" "$NB/node"
cat > "$NB/gemini" <<'PY'
import os, subprocess, sys, time
if len(sys.argv) < 2:
    subprocess.Popen([os.path.join(os.path.dirname(__file__), "node"), "-u", __file__, "child"])
time.sleep(30)
PY
(cd "$R" && exec timeout 20 "$NB/node" "$NB/gemini") & GP=$!
sleep 1
out=$(cd "$R" && CADENCE_AGENTS="claude,gemini" PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; s = A.live(); print([(x["tool"], x["cwd"]) for x in s.items if x["tool"] == "gemini" and x["cwd"].startswith(sys.argv[1])], "|", s.blind)' "$TMP")
[ "$out" = "[('gemini', '$R')] | []" ] && ok "9f live(): the node/gemini pair is one session, its cwd read" || bad "9f: $out"
out=$(cd "$R" && echo '{"session_id":"me","cwd":"'"$R"'"}' | CADENCE_AGENTS="claude,gemini" python3 "$S/check_anchor.py" --hook 2>&1)
grep -q "ANCHOR CONFLICT" <<< "$out" && grep -q "gemini session gemini:" <<< "$out" \
    && ok "9g the anchor guard reports a Gemini session in the main checkout" || bad "9g: $out"
kill "$GP" 2>/dev/null; wait "$GP" 2>/dev/null
# the reaper: a landed worktree with a Gemini session in it is not idle
( cd "$W" && git worktree add -q -b wt2 .claude/worktrees/wt2 origin/main
  ( cd .claude/worktrees/wt2 && echo x >> b.txt && git commit -qam x )
  git merge -q --squash wt2 >/dev/null && git commit -qm "wt2 (#2)" && git push -q origin main && git fetch -q origin )
(cd "$W/.claude/worktrees/wt2" && exec timeout 20 "$NB/node" "$NB/gemini") & GP=$!
sleep 1
out=$(cd "$W" && CADENCE_AGENTS="claude,gemini" scripts/reap_worktrees.sh --reap 2>&1)
[ -d "$W/.claude/worktrees/wt2" ] && grep -q "wt2.*idle=no" <<< "$out" \
    && ok "9g' the reaper holds off a worktree a Gemini session is in" || bad "9g': $out"
kill "$GP" 2>/dev/null; wait "$GP" 2>/dev/null
mv "$G" "$G.off"
grep -q "gemini sessions: no .*/.gemini" <<< "$(cd "$R" && CADENCE_AGENTS="claude,gemini" PYTHONPATH="$S" python3 -c 'import agent_sessions as A; print(A.live().blind)')" \
    && ok "9h agents lists gemini and there is no ~/.gemini: cannot see" || bad "9h: $(cd "$R" && CADENCE_AGENTS="claude,gemini" PYTHONPATH="$S" python3 -c "import agent_sessions as A; print(A.live().blind)" 2>&1)"
[ "$(PYTHONPATH="$S" python3 -c 'import agent_sessions as A; print(A.resume_hint("u", "gemini"))')" = "gemini --resume u" ] \
    && ok "9i resume_hint: gemini's" || bad "9i"
mv "$G.off" "$G"

# --- 10) the Codex backend (TD-102): a fixture CODEX_HOME in the shapes read off codex-cli 0.163.0
export CODEX_HOME="$TMP/codexhome"; DAY=$(date -u +%Y/%m/%d); STAMP=$(date -u +%Y-%m-%dT%H-%M-%S)
CS="$CODEX_HOME/sessions/$DAY"; mkdir -p "$CS"
CID=01111111-2222-7333-8444-666666666666
crollout() {  # uuid cwd first-user reply
    { printf '{"timestamp":"%s","ordinal":0,"type":"session_meta","payload":{"session_id":"%s","id":"%s","timestamp":"%s","cwd":"%s","originator":"codex_exec","cli_version":"0.163.0","git":{}}}\n' "$NOW" "$1" "$1" "$NOW" "$2"
      printf '{"timestamp":"%s","ordinal":1,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for %s\\n\\nRun the wake-up."},{"type":"input_text","text":"<environment_context>\\n  <cwd>%s</cwd>\\n</environment_context>"}]}}\n' "$NOW" "$2" "$2"
      printf '{"timestamp":"%s","ordinal":2,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\\n  <cwd>%s</cwd>\\n</environment_context>"}]}}\n' "$NOW" "$2"
      printf '{"timestamp":"%s","ordinal":3,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$NOW" "$3"
      printf '{"timestamp":"%s","ordinal":4,"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"%s"}]}}\n' "$NOW" "$4"
      printf '{"timestamp":"%s","ordinal":5,"type":"event_msg","payload":{"type":"task_complete","last_agent_message":null}}\n' "$NOW"
    } > "$CS/rollout-$STAMP-$1.jsonl"
}
crollout "$CID" "$R" "fix the ledger from codex" "done from codex"
crollout 33333333-0000-0000-0000-000000000000 "$R/.claude/worktrees/cw1/" "in a codex worktree" "ok"  # a trailing / still matches
crollout 44444444-0000-0000-0000-000000000000 /elsewhere "codex elsewhere" "no"
out=$(cd "$R" && CADENCE_AGENTS="claude,codex" python3 "$S/list_sessions.py" --repo "$R" 2>&1)
grep -q "^● $CID" <<< "$out" && grep -q "started: fix the ledger from codex" <<< "$out" \
    && grep -q "ended:   done from codex" <<< "$out" && grep -q "resume:  codex resume $CID" <<< "$out" \
    && ok "10a list_sessions: a Codex rollout found by its cwd, AGENTS.md and context skipped, its resume line" || bad "10a: $out"
grep -q "in a codex worktree" <<< "$out" && grep -qF "[$R/.claude/worktrees/cw1]" <<< "$out" && ! grep -q "codex elsewhere" <<< "$out" \
    && ok "10b list_sessions: the worktree's Codex session, another cwd's left out" || bad "10b: $out"
[ "$(PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; print(A.ever_ran(sys.argv[1]))' "$R")" = True ] \
    && ok "10c ever_ran: a Codex rollout counts" || bad "10c ever_ran"
R2="$TMP/repo2"; mkdir -p "$R2"; crollout 77777777-0000-0000-0000-000000000000 "$R2/sub" "in a subdir" "ok"
[ "$(cd "$R2" && CADENCE_AGENTS=codex PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; print(A.ever_ran(sys.argv[1]))' "$R2")" = True ] \
    && ok "10c' ever_ran: a rollout from a subdirectory of the repo counts" || bad "10c'"
FRESH="$CS/rollout-$STAMP-88888888-0000-0000-0000-000000000000.jsonl"
echo '{"timestamp":"x","type":"turn_context","payload":{}}' > "$FRESH"
! grep -q "Codex's session files have moved on" <<< "$(hook)" \
    && ok "10e' a rollout still being written is not judged by the canary" || bad "10e': $(hook)"
rm "$FRESH"
[ "$(PYTHONPATH="$S" python3 -c 'import agent_sessions as A; print(A.resume_hint("u", "codex"))')" = "codex resume u" ] \
    && ok "10d resume_hint: codex's" || bad "10d"
BAD="$CS/rollout-$STAMP-55555555-0000-0000-0000-000000000000.jsonl"
echo '{"timestamp":"x","type":"turn_context","payload":{}}' > "$BAD"; touch -d '1 minute ago' "$BAD"
grep -q "Codex's session files have moved on" <<< "$(hook)" \
    && ok "10e the canary names a rollout that does not open with session_meta" || bad "10e: $(hook)"
rm "$BAD"
# live: a process named codex (python3 under that name) holding its rollout open, and a codex
# child of it (folded in) — the native binary the npm shim starts. One session, its id the rollout's.
ln -s "$(command -v python3)" "$NB/codex"
cat > "$NB/codex-main.py" <<'PY'
import os, subprocess, sys, time
f = open(sys.argv[1])
g = [open(a) for a in sys.argv[2:] if a.endswith(".jsonl")]  # a later rollout too (a sub-agent's)
if "child" not in sys.argv:
    subprocess.Popen([os.path.join(os.path.dirname(__file__), "codex"), __file__, sys.argv[1], "child"])
time.sleep(30)
PY
LATER="$CS/rollout-9999-99-99T99-99-99-99999999-0000-0000-0000-000000000000.jsonl"; touch "$LATER"
(cd "$R" && exec timeout 20 "$NB/codex" "$NB/codex-main.py" "$CS/rollout-$STAMP-$CID.jsonl" "$LATER") & GP=$!
sleep 1
out=$(cd "$R" && CADENCE_AGENTS="claude,codex" PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; s = A.live(); print([(x["tool"], x["id"], x["cwd"]) for x in s.items if x["tool"] == "codex" and x["cwd"].startswith(sys.argv[1])], "|", s.blind)' "$TMP")
[ "$out" = "[('codex', '$CID', '$R')] | []" ] && ok "10f live(): one Codex session, its id the oldest rollout it holds open" || bad "10f: $out"
out=$(cd "$R" && echo '{"session_id":"me","cwd":"'"$R"'"}' | CADENCE_AGENTS="claude,codex" python3 "$S/check_anchor.py" --hook 2>&1)
grep -q "ANCHOR CONFLICT" <<< "$out" && grep -q "codex session ${CID:0:8}" <<< "$out" \
    && ok "10g the anchor guard reports a Codex session in the main checkout" || bad "10g: $out"
out=$(cd "$R" && CADENCE_AGENTS="claude,codex" python3 "$S/list_sessions.py" --repo "$R" 2>&1)
grep -A4 "^● $CID" <<< "$out" | grep -q "ACTIVE NOW" && ok "10h list_sessions marks the live Codex session ACTIVE NOW" || bad "10h: $out"
kill "$GP" 2>/dev/null; wait "$GP" 2>/dev/null; rm -f "$LATER"
# the self walk stops at our own codex: a Codex session (inner, in a subdir) started from
# another one's shell (outer, in the checkout) runs the hook — outer is another session
# in this checkout, not us, and inner is not folded into it (another cwd)
crollout 66666666-0000-0000-0000-000000000000 "$R/sub" "inner" "ok"
cat > "$NB/codex-nest.py" <<'PY'
import json, os, subprocess, sys, time
f = open(sys.argv[1])
if sys.argv[2] == "outer":
    os.makedirs(sys.argv[4], exist_ok=True)
    subprocess.Popen([os.path.join(os.path.dirname(__file__), "codex"), __file__, sys.argv[3], "inner"], cwd=sys.argv[4])
    time.sleep(30)
else:
    r = subprocess.run(["python3", os.environ["HOOK"], "--hook"], capture_output=True, text=True,
                       input=json.dumps({"session_id": "me", "cwd": os.getcwd()}))
    open(os.environ["HOOK_OUT"], "w").write(r.stdout + r.stderr)
    time.sleep(5)  # still live while the test reads live()
PY
(cd "$R" && HOOK="$S/check_anchor.py" HOOK_OUT="$TMP/nest.out" CADENCE_AGENTS="claude,codex" exec timeout 20 "$NB/codex" "$NB/codex-nest.py" \
    "$CS/rollout-$STAMP-$CID.jsonl" outer "$CS/rollout-$STAMP-66666666-0000-0000-0000-000000000000.jsonl" "$R/sub") & GP=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/nest.out" ] && break; sleep 0.5; done
out=$(cat "$TMP/nest.out" 2>/dev/null)
grep -q "ANCHOR CONFLICT" <<< "$out" && grep -q "codex session ${CID:0:8}" <<< "$out" && ! grep -q "codex session 66666666" <<< "$out" \
    && ok "10g' a Codex session's hook: its own codex is self, the codex it was started from is another session" || bad "10g': $out"
out=$(cd "$R" && CADENCE_AGENTS="claude,codex" PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; print(sorted(x["id"][:8] for x in A.live().items if x["tool"] == "codex" and x["cwd"].startswith(sys.argv[1])))' "$TMP")
[ "$out" = "['01111111', '66666666']" ] && ok "10g'' a codex started by a codex in another cwd is a session of its own" || bad "10g'': $out"
kill "$GP" 2>/dev/null; wait "$GP" 2>/dev/null
# the reaper: a landed worktree with a Codex session in it is not idle
( cd "$W" && git worktree add -q -b wt3 .claude/worktrees/wt3 origin/main
  ( cd .claude/worktrees/wt3 && echo y >> b.txt && git commit -qam y )
  git merge -q --squash wt3 >/dev/null && git commit -qm "wt3 (#3)" && git push -q origin main && git fetch -q origin )
(cd "$W/.claude/worktrees/wt3" && exec timeout 20 "$NB/codex" "$NB/codex-main.py" "$CS/rollout-$STAMP-$CID.jsonl") & GP=$!
sleep 1
out=$(cd "$W" && CADENCE_AGENTS="claude,codex" scripts/reap_worktrees.sh --reap 2>&1)
[ -d "$W/.claude/worktrees/wt3" ] && grep -q "wt3.*idle=no" <<< "$out" \
    && ok "10i the reaper holds off a worktree a Codex session is in" || bad "10i: $out"
kill "$GP" 2>/dev/null; wait "$GP" 2>/dev/null
mv "$CODEX_HOME" "$CODEX_HOME.off"
out=$(cd "$R" && CADENCE_AGENTS="claude,codex" PYTHONPATH="$S" python3 -c 'import agent_sessions as A; print(A.live().blind, A.history_dirs(".").blind)')
grep -q "codex sessions: no .*/codexhome" <<< "$out" && grep -q "codex transcripts: no .*/codexhome" <<< "$out" \
    && ok "10j agents lists codex and there is no CODEX_HOME: cannot see" || bad "10j: $out"
mkdir -p "$CODEX_HOME"
out=$(cd "$R" && CADENCE_AGENTS="claude,codex" PYTHONPATH="$S" python3 -c 'import agent_sessions as A; h = A.history_dirs("."); print(h.blind, [i for i in h.items if i[0] == "codex"])')
[ "$out" = "[] []" ] && ok "10k a CODEX_HOME with no sessions/ yet: empty, not blind" || bad "10k: $out"
rm -rf "$CODEX_HOME"; mv "$CODEX_HOME.off" "$CODEX_HOME"
# an unreadable day dir, sessions/ or rollout is blind, never "never ran" (glob() would swallow it)
for target in "$CS" "$CODEX_HOME/sessions" "$CS/rollout-$STAMP-$CID.jsonl"; do
    chmod 000 "$target"
    if [ -r "$target" ]; then
        ok "10l unreadable $(basename "$target"): skipped (running as root)"
    else
        out=$(cd "$R2" && CADENCE_AGENTS=codex PYTHONPATH="$S" python3 -c 'import sys, agent_sessions as A; print(A.ever_ran(sys.argv[1]), A.history_dirs(sys.argv[1]).blind)' "$R2")
        grep -q "^None .*codex transcripts: .*unreadable" <<< "$out" \
            && ok "10l unreadable $(basename "$target"): blind, not empty" || bad "10l $(basename "$target"): $out"
    fi
    chmod u+rwx "$target"
done
chmod 644 "$CS/rollout-$STAMP-$CID.jsonl"

echo "---- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
