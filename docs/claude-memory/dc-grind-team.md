---
name: dc-grind-team
description: The unattended ShiftLead team (dc-grind) that works dev-cadence's ledger on Paul's machine, and two gotchas about starting it
metadata:
  type: project
---

dev-cadence has an unattended ShiftLead team (the orchestrator was agentorc until 2026-10-11), `dc-grind` (manager-dc-1, techlead-dc-1, grinder-dc-1), defined in this repo's `.shiftlead.yml` (in the machine's `org.yml` until 2026-10-03), briefs in `docs/briefs/`. Started 2026-09-22 on a named lane; switched to `lane: free-pick` the same night (PR dev-cadence #108; Paul: entries filed mid-run must be workable without a restart). The exclusion is the ledger's own `**Blocked by:** decision (Paul)` field, read by `files/scripts/ledger.py --pickable` (TD-064, 2026-09-26; before that a hand-kept *Never pick* list in the grinder brief) — Paul rejected per-entry manual approval. Promoting an entry is a ledger edit: no brief change, no restart. `ao team status dc-grind` reads it.

**Why:** the design review filed 21 entries; the team is how they get worked without a person at the keyboard.

**How to apply:** `ao team start` reads briefs from the main checkout's working tree at that moment, so merge a brief change before starting. An agent promote does not upgrade running records — after one, `ao team stop dc-grind --close` then `ao team start dc-grind` (a restart on 2026-09-22 was needed for the crash-restart supervision). Never `git add -A` in the main checkout while seats' worktrees exist unless `.claude/worktrees/` is gitignored (it is, since PR dev-cadence #96).
