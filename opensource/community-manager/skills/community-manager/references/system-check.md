# System check — one report, every agent, always live

The owner will ask for this repeatedly and in different words: "do a system
check", "status", "how are we doing", "is anything broken", "run a full
check", "how many jobs ran today and what succeeded". Answer all of these the
same way, every time — don't improvise a differently-shaped answer per
phrasing. A real install needed exactly this several times in one evening and
got a different-shaped answer each time, which made it hard to tell whether
things were actually improving or just being described differently.

**Always re-verify live.** Never answer from memory of the last check you
ran, even five minutes ago. Config, credentials, and task state all change
underneath you.

## 1. Collect — your own check, plus every stamped sub-agent's

1. Run your own `setup-check.sh`.
2. For each **stamped** sub-agent (local ops, Reviewer, marketing), ask it —
   over its agent-to-agent destination — to run its own `setup-check.sh` and
   report the result back to you. You cannot run their scripts directly; a
   sub-agent's `plugin-data` is not yours to read. Wait for all of them
   before compiling the report, or say plainly which agent hasn't answered
   yet if one is slow.
3. Pull real task state, not just config health:
   - `ncl tasks list --status active` and `ncl tasks list --status paused`
     (per group where the CLI supports scoping) — how many of each, and for
     paused ones, **why**: goal not chosen (expected) vs. credential/config
     missing (a real gap) vs. never resumed at all (the most common real
     failure — see below).
   - For anything that fired recently, `ncl tasks get <id>` to see the
     **actual last result**, not just whether it ran.

## 2. The lesson a real install paid for: "0 failed" is not "worked"

A task can complete with no error and still have produced garbage — a real
install had `weekly-analytics-report` log 3 runs / 0 failed while every one
of those runs actually hit `"status": "GA4 fetch failed"` internally (a
missing `jq` silently broke the parse step downstream of a *successful* API
call). The task-runner's own success/failure count only means "the process
exited cleanly," not "the content is right." When reporting on a task's
recent runs, **read what it actually returned**, not just whether the
scheduler thinks it succeeded.

The other half of that same lesson: **paused-since-creation is the single
most common reason "nothing ran."** Every task ships paused by design, and
if the activation step (see the welcome skill's per-agent rollout) never
actually got applied for a given agent — the resume step got lost in the
noise of everything else that evening, exactly what happened on a real
install — the honest symptom is "0 runs, 0 failures," which reads as clean
right up until someone asks why nothing happened all night. **Check whether
a task has run *at all* since it was created, not just whether its last run
failed.**

## 3. Reconcile before you report — never relay a contradiction

If one signal says "all clear" and another says something failed in the same
window, **do not pass both along as if they're consistent.** A real install
had `health-check`'s weekly heartbeat land the same minute as a real
`repo-mirror-sync` clone failure — because the heartbeat only ever checked
its own environment (jq/ncl present, state fresh), never other tasks'
outcomes, but was worded as if it meant system-wide health. If you find a
contradiction like this, say so explicitly ("X reported clean, but Y failed
in the same window — worth investigating why X didn't catch it") rather than
quietly picking one to relay.

## 4. Report shape

```
**System check — <date/time>**

**Lead**: <config/credential status, one line> · <N active, M paused — reasons for any real gaps>
**Local ops**: <same, one line> · <N active, M paused>
**Reviewer**: <same, one line> · <N active, M paused>
**Marketing** (if stamped): <same, one line> · <N active, M paused>

**Ran recently, worth knowing**: <task — actual result, not just pass/fail>
(repeat per task with something real to report; omit entirely if nothing has
run recently enough to check)

**Needs you**: <anything that's a real gap, not a "goal not chosen" — a
missing permission, a stuck task, a credential problem>
```

Skip a section entirely if there's nothing in it — a genuinely healthy check
should read short, not padded to look thorough. If every agent is clean and
nothing needs the owner, say that in one line and stop; don't manufacture
structure around an all-clear.
