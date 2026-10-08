# Pre-flight: create, audit, and rotate every credential

One document for three jobs: **create** each credential with the exact URL
(no guessing), **audit** what's actually connected against what should be
(don't trust the dashboard's word for it — check), and **rotate** safely when
a key needs to change. Everything below uses the real `onecli` CLI (verified
against [`onecli/onecli-cli`](https://github.com/onecli/onecli-cli)'s actual
command definitions, not guessed) — run it wherever the CLI reaches your
gateway: from the `nanoclaw` checkout directory on your host.

This exists because of a real failure mode: **v1 of this system started with
everything authenticated as the owner's own personal account, and had to be
painfully pulled back onto dedicated bot accounts later.** Every check below
is aimed at catching that mistake *before* it happens, not after.

---

## 1 · Create — exact URL per credential, nothing to guess

| Credential | Create it here | Notes |
|---|---|---|
| **Model access (what the agent thinks with)** | **Preferred: your Claude subscription.** The kit's first-boot wizard accepts *a subscription, an OAuth token, or an Anthropic API key* — pick subscription and there's no per-token bill. Alternative: `console.anthropic.com` → API Keys. Either way the credential lands in the OneCLI vault (**LLMs** tab), never in a file. | **Nothing works without this.** Symptom when missing, expired, or out of capacity: the manager simply never replies to your DM — no error surfaces anywhere you'd see it. **Read [OPERATIONS.md → Model budget — one shared window, and the trap in it](docs/OPERATIONS.md) before choosing**: a subscription shares one usage window with your own Claude Code sessions, which has a real failure mode attached. The one agent draws on this same window |
| GitHub bot account | github.com → sign in as the bot, or create a new account | **Do this first** (after the model key) — every token below is cut from this account, not the owner's. Make it unmistakably a bot: display name "<Name> (<Project> community bot)", a bio that says automated, never reviews or merges, run by @owner, a profile README repo (`<bot>/<bot>`) explaining what it does and how to reach a human, a distinct avatar marked BOT, public membership in the project org in a `bots` team, 2FA on with the owner holding recovery. The agent adds a disclosure footer to every GitHub comment on top of this |
| Manager GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Issues+PRs read/write and Contents read over `COMMUNITY_REPOS` plus `CONTEXT_REPOS`; Contents **write** on the docs repo only (`docs-gap-review` opens docs PRs). Not classic, not `read:org` |
| Discord bot | `discord.com/developers/applications` → New Application → Bot tab | Fresh application — never reuse a bot from a prior system |
| Tailscale (optional, for remote dashboard access) | `tailscale.com/download` | See docs/INSTALL.md §2 for the exact `serve` command |

**Never give any agent a key — everything goes through OneCLI.** Never paste
a raw value into a chat with an agent, a template file, an env var, or
anywhere but the vault (dashboard UI, or `onecli secrets create` below). The
agent runs with no credentials at all — the proxy injects auth outside its
container — and its persona instructs it to refuse and report if
anyone asks it to receive or reveal a key. An agent asking you for a key is
misbehaving; the answer is the vault dashboard URL, never the key.

## 1b · GitHub scopes — derived from the endpoints, not guessed

**Review this against the code, not against my word for it.** Every row below
maps to a call that exists in `scripts/tasks/` or an action a persona is
explicitly permitted to take. Regenerate the endpoint list any time with:

```bash
grep -rhoE 'https://api\.github\.com/[^"]*' scripts/tasks/*/*.sh */*/setup-check.sh | sort -u
```

**Use a fine-grained PAT.** A classic `repo` scope is
account-wide (every repo the bot can see, read *and* write); a fine-grained
token is an allowlist of named repos with per-category permissions. Nothing
here needs classic. Note that a fine-grained token's repo list gates
**everything** the token does — including reads of otherwise-public data — so
a repo left off the list fails silently rather than falling back to public
access. That's the single most common misconfiguration in this system.

**Every gate SCRIPT is a read.** Everything that writes does so in the
agent's live actions after a gate wakes it — Issues and PRs write, for its
own replies: filing a bug report from a Discord conversation, commenting,
labelling. No script pushes a branch, opens a PR, or sends a `POST`.

### Manager — `opensource/community-manager`

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | implied by everything; `GET /repos/{repo}` in setup-check |
| Issues | **Read + Write** | reads `GET /search/issues` and `GET /repos/{repo}/issues/comments` (`github-first-response`), `GET /repos/{repo}/milestones` (`project-context`), `GET /repos/{repo}/issues/{n}` and its `/comments` plus `search/issues … review:changes_requested` (`follow-up-nudge`); writes = one check-in comment per idle PR or silent issue (`follow-up-nudge`), = filing bug reports from Discord, commenting, labelling in its live replies (`github-bug-workflow.md`) |
| Pull requests | Read + Write | commenting on PRs in those same live replies; the issues endpoint also returns PRs |
| Contents | Read everywhere; **Write on the docs repo only** | `docs-gap-review`: `POST git/refs`, `PUT contents/{path}` on a `docs/*` branch, `POST pulls` — never the default branch. Reads: `GET /repos/{repo}/commits`, `GET /repos/{repo}/releases/latest`, `GET /repos/{repo}/compare/{a}...{b}`, and `GET /repos/{repo}/contents/{path}` for changed `.agents/skills/**` and docs files (`project-context`) — all on `api.github.com`, so a private repo needs only to be on the token's repo list; no second host |

Repo list: everything in `COMMUNITY_REPOS` and `CONTEXT_REPOS`. **Never** `admin:*`,
`delete_repo`, `read:org`, or workflow scopes — nothing reads org membership
(listing an org's repos during onboarding needs no such scope) and nothing
touches Actions.

One nuance on the Issues row worth knowing before you cut it smaller: the
read is the smaller justification of the two. Even with `github-first-response`
paused, the manager needs Issues and PRs write for its live replies.

Worth noticing what is *absent*: `unanswered-watch`, the task the
responsiveness guarantee rests on, has no network access and no credential —
it reads local session state only. A token problem cannot silence it,
because it never had a token.

Verify the endpoint list against `grep -l api.github.com
scripts/tasks/manager/*.sh` rather than trusting this section — it is the
kind of list that goes stale on every task change.

### Why PATs and not a GitHub App

A GitHub App would give better rate limits, installation-scoped access, and
no dependency on a user account — genuinely better at org scale. It also
needs JWT signing, installation-token exchange, and a webhook endpoint, none
of which the OneCLI vault-plus-proxy model handles today (it injects a static
header per host). For a single project with a dedicated bot account,
fine-grained PATs on that account are the right tradeoff. Revisit if you
outgrow the 5,000 req/hr primary limit — none of these tasks come close.

### Verify, don't assume

After creating the token, confirm what it actually resolves to *and* that it
can reach what it needs (§4 below, and the agent's `setup-check.sh`). The
identity check matters most: a token that works under the owner's own account
is worse than one that fails, because every action it takes looks like the
owner did it by hand.

## 2 · Register — dashboard UI or CLI, your choice

The dashboard (docs/INSTALL.md §2) is the visual path. The CLI is scriptable and
exactly as capable — real commands, not a paraphrase:

```bash
# A generic secret (GitHub PAT, Discord bot token, anything host+header shaped)
onecli secrets create --name "GitHub Bot PAT" --type generic \
  --value "<token>" --host-pattern "api.github.com" \
  --header-name "Authorization" --value-format "Bearer {value}"

# Dry-run first if you want to see the request without sending it
onecli secrets create --name "..." --type generic --value "..." \
  --host-pattern "..." --dry-run
```

`--type` is `anthropic`, `openai`, or `generic` — GitHub and Discord are
`generic` with a host-pattern match; only the model provider key itself uses
`anthropic`/`openai`.

## 3 · Audit — verify what's connected, don't trust the tab count

The dashboard's "Connected 11" is a count, not a guarantee any of the 11 are
the *right* 11. Run these and actually read the output:

```bash
# Every Custom-tab secret: name, host/path match, when created
onecli secrets list --fields name,hostPattern,pathPattern,createdAt

# Every Apps-tab OAuth connection (GitHub, ...), by provider
onecli apps connections list --fields provider,status,connectionId

# The one that actually answers "does an agent have more access than it needs":
# which agents can reach a given connection, and what each can do
onecli apps connections agent-access --provider github
```

Read the last one carefully — it's the direct, verifiable answer to "we want
security so that agents don't have too much access for things outside what
they need." If it shows an agent reaching a connection nothing in that
agent's config or tasks explains, that's a finding, not a formality.

**Diff its output against docs/INSTALL.md §2's "Per agent: the complete OneCLI
footprint" table** — that table *is* the expected state, one row per grant,
each tied to the task that uses it. Every connection `agent-access` reports
for an agent should match a row there exactly; a connection with no matching
row is either stale (remove it) or undocumented (find out why before trusting
it).

### Worked example: auditing a real vault (11 connections)

A real deployment's audit, applying the steps above:

| Found | Verdict |
|---|---|
| GitHub (Apps tab) | ✅ expected — confirm identity with the `GET /user` check below regardless |
| Gmail (Apps tab), Google Analytics (Apps tab) | 🚩 **finding**: nothing in this template set reads mail or analytics any more — metrics moved to GitHub Actions in the project repo. Live OAuth grants with no task consuming them are unused surface; remove them |
| GitHub App, GitLab, Google Drive, Google Calendar, Google Chat — all **not connected** | ✅ correct — nothing in this template set uses them; an unconnected integration sitting in the "Apps" list is not a requirement, don't connect it "just in case" |
| PostHog API Key (Custom, host `us.posthog.com`) | 🚩 **finding**: no task here reads telemetry. A live PostHog key with no task consuming it is unused surface; remove it |
| Discord Bot Token (Custom, host `discord.com`) | ✅ expected — `/add-discord`'s own registration, not a manual step |
| LinkedIn Access Token (Custom, host `api.linkedin.com`), 4× Twitter/X secrets (Custom, host `api.x.com`) | 🚩 **finding**: nothing in this template set posts or reads on either platform. Stale, unused-but-still-valid credentials are exactly what this audit exists to catch — remove them |
| Anthropic Token (LLMs tab, host `api.anthropic.com`) | ✅ the model provider key, not an identity/posting credential — no rotation needed as part of any bot-identity cleanup |

The flagged 🚩 rows are the actual value of running this audit: none is a
security hole, but each is unused surface — exactly what "nothing more than
what's needed" means in practice, not just in the abstract.

## 4 · Confirm identity — the check that catches "started as my own account"

A secret can be perfectly scoped and still belong to the *wrong account*. For
every GitHub credential:

```bash
curl -s -H "Authorization: Bearer <same-value-as-the-vault-entry>" https://api.github.com/user | jq -r .login
```

Compare the printed `login` against the dedicated bot account's username —
never the owner's own. This is exactly the check the welcome interview and
the agent's setup self-check now run automatically (see docs/INSTALL.md §2,
"Confirm identity, don't assume it") — running it yourself here is the
manual version, useful before you've even stamped an agent.

## 5 · Rotate — safely, with no downtime and no guessing whether it "took"

**In place, by ID — never delete-then-recreate** (that opens a window where
the credential is simply gone):

```bash
# Find the ID
onecli secrets list --fields name,id --quiet id

# Swap the value, same secret, same host/path binding
onecli secrets update --id <secret-id> --value "<new-value>"

# Optional: rehearse first
onecli secrets update --id <secret-id> --value "<new-value>" --dry-run
```

**Does the system pick it up automatically? Yes — no restart needed.** The
gateway looks up the vault value **per outbound request**, not once at
container boot (the same reason `set-secret-mode` changes need no restart,
per docs/INSTALL.md §2) — an updated value is live on the very next credentialed call
an agent makes. Confirm it rather than just trust it:

1. Run the update.
2. Re-run the identity check in step 4 with the *new* value — confirm it
   resolves to the account you meant.
3. Have the agent make one real read-only call (its own setup self-check
   does this) and confirm success.

**If you're specifically fixing a "this was authenticated as my own account"
mistake**: cut the new bot-account token first, verify its identity with step
4 *before* touching the vault, then `secrets update` the existing entry's
value in place — the host/path binding and everything wired to that secret ID
stays intact; only the account behind it changes.

**Never rotate by editing a template file or the agent's persona** — credentials
never lived there to begin with; this is entirely a vault operation, on the
existing secret ID, and it's exactly why the design keeps them separate.
