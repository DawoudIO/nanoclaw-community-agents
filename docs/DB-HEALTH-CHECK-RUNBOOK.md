# Task-DB corruption — what to do, step by step

Run this the moment `ncl tasks list` / `ncl tasks run` looks broken, **before**
trying anything else, restarting anything, or letting an agent attempt a fix.
Background: `UPSTREAM-ISSUES.md` #18.

## 1. Copy the script into the sandbox

From this repo, on your host machine:

```bash
tar -C scripts -cf - db-health-check.sh | sbx exec -i nanoclaw tar -C /home/agent/nanoclaw -xf -
```

## 2. Open a break-glass shell

```bash
sbx exec -it -w /home/agent/nanoclaw nanoclaw bash
```

## 3. Find NanoClaw's actual data directory

The central DB lives at `<PROJECT_ROOT>/data` (confirmed from `nanocoai/nanoclaw`
source, `src/config.ts`), but `PROJECT_ROOT` depends on your install layout —
find it rather than assume:

```bash
find / -maxdepth 6 -iname "*.db" 2>/dev/null
```

Note the directory that contains the `.db` files — that's what you pass to
the script in step 5.

## 4. Confirm `sqlite3` is available in this shell

```bash
command -v sqlite3 || echo "missing"
```

If missing: this is a plain CLI tool, not an agent-container package — try
`apt-get install -y sqlite3` (or whatever package manager this control shell
has) directly, rather than the agent `install_packages` self-mod flow (that's
for agent containers, not this shell).

## 5. Run the health check

```bash
bash db-health-check.sh <the-directory-you-found-in-step-3>
```

Diagnose only (safe, read-only):
```bash
bash db-health-check.sh <path>
```

Diagnose + safe checkpoint on anything healthy:
```bash
bash db-health-check.sh <path> --checkpoint
```

**Read the output.** Every `.db` file gets one of two verdicts:
- `integrity_check: OK` — not actually corrupted. If `ncl` still fails
  against it, that's contention or something else, not corruption — don't
  run any recovery step below.
- `integrity_check: FAILED` — genuinely corrupted. The script prints the
  exact recovery command; **do not run it automatically**, and back up first
  (the script's own printed command does this for you).

## 6. Capture a bundle for the team, whichever verdict you got

Save all of this together, with a timestamp:

- The full output of `db-health-check.sh` from step 5.
- `docker --version` and `docker info` (storage driver — also relevant to
  UPSTREAM-ISSUES.md #15/#16).
- This repo's `platform-baseline.json` (image digest, `kit_commit`).
- The **literal** `ncl` error text that made you run this in the first
  place — copy-paste, not a paraphrase.
- Whether the NanoClaw process was recently killed, restarted, or the host
  went to sleep around the time of the failure.

Send that bundle back so it can go into `UPSTREAM-ISSUES.md` #18 and, once
there's enough to file, upstream to `nanocoai/nanoclaw`.

## What NOT to do

- Don't run `.recover` or delete any file before step 5's `integrity_check`
  result comes back OK/FAILED — you need to know which one you're dealing
  with first.
- Don't let an agent (inside its own container) attempt a repair — it can't
  reach this database from inside its own sandbox in the first place, and
  guessing at a fix here risks losing task/schedule state that isn't
  recoverable.
- Don't skip the bundle in step 6 even if you fix it yourself — an
  unrepeated one-off fix teaches the team nothing about the actual bug.
