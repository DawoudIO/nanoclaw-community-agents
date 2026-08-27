# Uninstall — and what "fully delete" actually means

NanoClaw ships its own uninstaller and it is the thing to use. This document
is about the gap between what it removes and what a *complete* teardown means,
because that gap is wider than it looks and includes at least one thing you
would not want left on disk.

## Run this

```bash
cd /path/to/nanoclaw
bash nanoclaw.sh --uninstall --dry-run   # preview, changes nothing
bash nanoclaw.sh --uninstall             # the real thing
```

`./uninstall.sh` also works — it is a two-line shim that translates `-n`/`-y`
and execs the same flow. There is no third path.

Everything is **prompted in four groups, each defaulting to No**, and nothing
is executed until every decision is collected — Ctrl-C at any prompt deletes
nothing. `--yes` accepts groups 1–3 and your own vault agents (never orphans,
see below). There are no scope flags: no `--keep-data`, no per-group
selection from the command line.

**Do it from the checkout, before deleting anything.** If `node_modules/` is
already gone the uninstaller cannot run at all — it prints manual cleanup
commands and exits 1, because it runs on `tsx` out of `node_modules`.

## What it removes

| Group | Contents |
|---|---|
| 1 · Service | launchd plist / systemd unit, the running process, all containers labelled with this install's slug, the per-install image `nanoclaw-agent-v2-<slug>:latest`, and `~/.local/bin/ncl` (only if it points at this checkout) |
| 2 · Data | `data/` (central DB, session DBs, install-id), `logs/`, `.env`, `start-nanoclaw.sh`, `nanoclaw.pid`, `../.nanoclaw-updates/<slug>/`, then `dist/` and `node_modules/` last |
| 3 · Your content | `groups/` and `store/` — the agents' workspaces and memory |
| 4 · Vault agents | The OneCLI vault agents belonging to *this* copy |

Order is load-bearing: service and containers first so the host can't respawn
anything mid-removal, vault deletions before the data group (which destroys
the DB the ownership check is computed from), and `node_modules/` dead last
because the uninstaller is running out of it.

## What survives — the part that matters

**Your `.env` is backed up to `.env.bak` in the checkout and left there.**
That file contains your Discord bot token and any other keys `.env` held, in
plaintext. Deleting the checkout removes it; keeping the checkout keeps your
credentials on disk. This is the single most important item on this page.

Also left behind, none of it inventoried by the uninstaller:

- **The checkout directory itself.** `src/`, `templates/`, `.git/`, and
  `.env.bak`. You delete this by hand — it's the last step, not the first.
- **`~/.config/nanoclaw/`, entirely** — including `registry-auth.json` and
  `account.json`, so the hardened-image registry token stays on disk, and
  `mount-allowlist.json`.
- **The hardened base image.** Only the derived per-install tag is removed;
  the base it was built `FROM` (a multi-GB pull) stays, as does any tag other
  than `:latest`.
- **Docker volumes, networks, and build cache** — no prune of any kind.
- **OneCLI itself** — the app, the gateway process, the vault, and every
  credential in it. Only this copy's *agents* are deleted. This is deliberate:
  OneCLI is shared, and other installs may depend on it.
- `~/.docker/` credential-helper config, and the PATH lines added to
  `~/.bashrc` / `~/.zshrc`.
- Other NanoClaw copies on the machine, untouched by design.

## Three ways it silently leaves things behind

**1. Moving or renaming the checkout orphans everything.** The install's
identity is `sha1(absolute path of the checkout)` — computed, never stored. If
the directory has moved since install, the uninstaller derives a different
slug, finds none of its own service, containers, or image, reports success,
and leaves all of it running. Uninstall *before* moving a checkout, or move it
back first.

**2. A missing `data/v2.db` orphans your vault agents.** Ownership of vault
agents is decided by reading agent-group ids out of that DB. If it's already
gone, every `ag-*` agent is classified an orphan — and orphans are never
deleted under `--yes`. Interactive mode warns; `--yes` does not. So don't
delete `data/` by hand first.

**3. Declining group 1 while accepting group 2 half-removes a running
system.** The service keeps running while its data directory and `dist/` are
deleted from under it. Nothing prevents the combination. Take group 1 whenever
you take group 2.

If Docker isn't running, containers and the image are skipped with a note
carrying the manual commands — nothing fails, they just survive. Every action
is individually caught, so re-running is safe and picks up what failed.

## Full teardown

```bash
cd /path/to/nanoclaw
bash nanoclaw.sh --uninstall --dry-run    # read it
bash nanoclaw.sh --uninstall              # accept all four groups

cd .. && rm -rf nanoclaw                  # includes .env.bak — check it first
rm -rf ~/.config/nanoclaw                 # registry token, mount allowlist

docker images | grep nanoclaw             # base image, if you want it gone
docker system prune                       # optional: dangling layers/cache
```

Only if you are done with NanoClaw entirely — these are shared:

```bash
onecli agents list                        # anything left from other copies?
rm -rf ~/.local/share/onecli ~/.local/bin/onecli
```

And drop the PATH lines from `~/.bashrc` / `~/.zshrc` if you added them.

### Running in a sandbox

If the install lives in an `sbx` VM, deleting the sandbox removes everything
inside it in one step, and the uninstaller is unnecessary:

```bash
sbx stop nanoclaw && sbx rm nanoclaw
```

Anything on the host — `~/.config/nanoclaw`, host Docker images, OneCLI if it
runs outside the VM — still needs the steps above.

## What no uninstaller can reach

These are accounts and grants on other people's servers. Revoke them yourself,
or they stay live:

| | Where |
|---|---|
| Discord application + bot token | Discord Developer Portal — delete the app |
| GitHub PATs (one per agent) | github.com → Settings → Developer settings |
| Anthropic / Claude credential | your Anthropic account |
| NanoClaw registry account | created for the hardened-image pull |
| GA4 / Google OAuth grant | Google account permissions, if you wired analytics |
| The workspace backup repo | it holds the agent's config and history |
| `tailscale serve` config | if you exposed the OneCLI dashboard over a tailnet |

The last three come from this template set rather than NanoClaw itself, so
they will not appear in any NanoClaw uninstall summary.

**Revoke the GitHub tokens even if you plan to reinstall.** They outlive the
install, they're scoped to a bot account you may not check often, and a
half-torn-down install is exactly when nobody is watching what uses them.
