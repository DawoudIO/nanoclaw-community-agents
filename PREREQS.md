# Pre-flight: create, audit, and rotate every credential

One document for three jobs: **create** each credential with the exact URL
(no guessing), **audit** what's actually connected against what should be
(don't trust the dashboard's word for it — check), and **rotate** safely when
a key needs to change. Everything below uses the real `onecli` CLI (verified
against [`onecli/onecli-cli`](https://github.com/onecli/onecli-cli)'s actual
command definitions, not guessed) — run it wherever the CLI reaches your
gateway; for the sbx deployment that's inside the sandbox
(`sbx exec -it -w /home/agent/nanoclaw nanoclaw onecli ...`).

This exists because of a real failure mode: **v1 of this system started with
everything authenticated as the owner's own personal account, and had to be
painfully pulled back onto dedicated bot accounts later.** Every check below
is aimed at catching that mistake *before* it happens, not after.

---

## 1 · Create — exact URL per credential, nothing to guess

| Credential | Create it here | Notes |
|---|---|---|
| **Model access (what the agents think with)** | **Preferred: your Claude subscription.** The kit's first-boot wizard accepts *a subscription, an OAuth token, or an Anthropic API key* — pick subscription and there's no per-token bill. Alternative: `console.anthropic.com` → API Keys. Either way the credential lands in the OneCLI vault (**LLMs** tab), never in a file. | **Nothing works without this.** Symptom when missing, expired, or out of capacity: the lead simply never replies to your DM — no error surfaces anywhere you'd see it. **Read [OPERATIONS.md → Two separate budgets](docs/OPERATIONS.md) before choosing**: a subscription shares one usage window with your own Claude Code sessions, which has a real failure mode attached |
| GitHub bot account | github.com → sign in as the bot, or create a new account | **Do this first** (after the model key) — every token below is cut from this account, not the owner's |
| Lead GitHub PAT | `github.com/settings/tokens` (classic) | Scope `repo` (public-only: `public_repo`). Not `read:org` |
| Coding GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Read-only: Contents+Issues+PRs; + Dependabot alerts if enabling the sweep |
| Marketing GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Content repo only, Contents+PRs read/write |
| Discord bot | `discord.com/developers/applications` → New Application → Bot tab | Fresh application — never reuse a bot from a prior system |
| PostHog key | `<region>.posthog.com` → Settings → Personal API Keys | Read-only on insights/query; note region (`us`/`eu`) |
| GA4 OAuth | `console.cloud.google.com` → enable "Google Analytics Data API"; GA4 Admin → grant Viewer | Not the Admin API |
| Gmail OAuth | `console.cloud.google.com` → Gmail API + OAuth consent | Scope `gmail.readonly` only |
| Tailscale (optional, for remote dashboard access) | `tailscale.com/download` | See docs/INSTALL.md §4 for the exact `serve` command |

**Never give any agent a key — everything goes through OneCLI.** Never paste
a raw value into a chat with an agent, a template file, an env var, or
anywhere but the vault (dashboard UI, or `onecli secrets create` below). The
agents run with no credentials at all — the proxy injects auth outside their
containers — and every agent's persona instructs it to refuse and report if
anyone asks it to receive or reveal a key. An agent asking you for a key is
misbehaving; the answer is the vault dashboard URL, never the key.

## 1b · GitHub scopes — derived from the endpoints, not guessed

**Review this against the code, not against my word for it.** Every row below
maps to a call that exists in `scripts/tasks/` or an action a persona is
explicitly permitted to take. Regenerate the endpoint list any time with:

```bash
grep -rhoE 'https://api\.github\.com/[^"]*' scripts/tasks/*/*.sh */*/setup-check.sh | sort -u
```

**Use fine-grained PATs for all three agents.** A classic `repo` scope is
account-wide (every repo the bot can see, read *and* write); a fine-grained
token is an allowlist of named repos with per-category permissions. Nothing
here needs classic. Note that a fine-grained token's repo list gates
**everything** the token does — including reads of otherwise-public data — so
a repo left off the list fails silently rather than falling back to public
access. That's the single most common misconfiguration in this system.

**Every script call is a read.** Writes happen exclusively in the agents'
live actions, which is why only two of the three tokens need write at all.

There is exactly one `POST` in the whole system and it is **not** a write:
GA4's `analyticsdata.googleapis.com/v1beta/properties/{id}:runReport`. That
API takes its query (date range, which metrics) as a JSON body, so Google
made the query verb a POST — it returns rows and mutates nothing. The
required GA4 role is **Viewer**, which is itself the proof: a read-only role
can run it. The API that *can* change a property is
`analyticsadmin.googleapis.com`, which this system never calls — **do not
enable it in the Cloud project.** If you set up an OneCLI request-hold
anywhere, match on host+path rather than HTTP method, or this harmless report
gets gated.

### Lead — `support/community-support`

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | implied by everything; `GET /repos/{repo}` in setup-check |
| Issues | **Read + Write** | reads `GET /repos/{repo}/issues` (`daily-github-triage`); writes = filing bug reports from Discord, commenting, labelling (`github-bug-workflow.md`) |
| Pull requests | Read + Write | commenting on PRs; the issues endpoint also returns PRs |
| Contents | Read | `GET /repos/{repo}/releases/latest` (`release-announcement-watch`) |
| Contents (**backup repo only**) | Write | `workspace-backup` pushes over `github.com` git — a *separate vault entry* from `api.github.com`, and ideally a separate token scoped to just that repo |

Repo list: everything in `COMMUNITY_REPOS`, plus the backup repo if enabled.
**Never** `admin:*`, `delete_repo`, `read:org`, or workflow scopes — nothing
reads org membership (listing an org's repos during onboarding needs no such
scope) and nothing touches Actions.

### Coding — `engineering/community-coding`

**Read-only. No write permission of any kind, in any category.** This agent
is designed never to post, so its token should be incapable of it — that way
a prompt injection that slips past the persona still cannot act.

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | `GET /repos/{repo}`, `/community/profile` (`repo-hygiene-audit`), `/contributors` (`dev-metrics-report`) |
| Issues | Read | `GET /repos/{repo}/issues` (`github-ops-triage`), `GET /search/issues` (metrics, GFI health, ready-to-merge) |
| Pull requests | Read | the same search + issues endpoints return PRs |
| Contents | Read | `GET /repos/{repo}/releases` (download counts), and `git clone/fetch` over `github.com` for `repo-mirror-sync` |
| Dependabot alerts | Read | `GET /repos/{repo}/dependabot/alerts` (`security-advisory-sweep`) — **omit this and the sweep 403s**; it's the one permission people forget |

Repo list: the union of `COMMUNITY_REPOS` and `MIRROR_REPOS` (the mirror set
is usually the larger one — it covers docs/site/wiki even when those aren't
triaged). Public repos need no credential at all for the git clone.

### Marketing — `marketing/community-marketing`

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | setup-check reachability probes |
| Contents | **Read + Write** on `CONTENT_REPO` | commits drafts to a branch (`content-workflow.md` step 2) |
| Pull requests | **Read + Write** on `CONTENT_REPO` | opens the draft PR (step 3); `GET /repos/{repo}/pulls` for `draft-cleanup` |
| Contents | Read on `BRAND_SOURCE_REPO` | reads brand voice / pillars / calendar, if a different repo |
| Contents | Read on `RELEASE_WATCH_REPO` | `GET /releases/latest` for the content trigger, if a different repo |

Repo list: `CONTENT_REPO` (write) plus `BRAND_SOURCE_REPO` and
`RELEASE_WATCH_REPO` (read) **when those differ** — the most common silent
failure in this system is leaving one of the latter two off the list. No
social-platform credential is wired to this agent in any configuration.

### Why PATs and not a GitHub App

A GitHub App would give better rate limits, installation-scoped access, and
no dependency on a user account — genuinely better at org scale. It also
needs JWT signing, installation-token exchange, and a webhook endpoint, none
of which the OneCLI vault-plus-proxy model handles today (it injects a static
header per host). For a single project with a dedicated bot account,
fine-grained PATs on that account are the right tradeoff. Revisit if you
outgrow the 5,000 req/hr primary limit — none of these tasks come close.

### Verify, don't assume

After creating each token, confirm what it actually resolves to *and* that it
can reach what it needs (§4 below, and each agent's `setup-check.sh`). The
identity check matters most: a token that works under the owner's own account
is worse than one that fails, because every action it takes looks like the
owner did it by hand.

## 2 · Register — dashboard UI or CLI, your choice

The dashboard (docs/INSTALL.md §4) is the visual path. The CLI is scriptable and
exactly as capable — real commands, not a paraphrase:

```bash
# A generic secret (PostHog, LinkedIn, Discord bot token, anything host+header shaped)
onecli secrets create --name "PostHog API Key" --type generic \
  --value "<key>" --host-pattern "us.posthog.com" \
  --header-name "Authorization" --value-format "Bearer {value}"

# Dry-run first if you want to see the request without sending it
onecli secrets create --name "..." --type generic --value "..." \
  --host-pattern "..." --dry-run
```

`--type` is `anthropic`, `openai`, or `generic` — GitHub/PostHog/Discord/GA4/
Gmail are all `generic` with a host-pattern match; only the model provider key
itself uses `anthropic`/`openai`.

## 3 · Audit — verify what's connected, don't trust the tab count

The dashboard's "Connected 11" is a count, not a guarantee any of the 11 are
the *right* 11. Run these and actually read the output:

```bash
# Every Custom-tab secret: name, host/path match, when created
onecli secrets list --fields name,hostPattern,pathPattern,createdAt

# Every Apps-tab OAuth connection (Gmail, GitHub, GA4, ...), by provider
onecli apps connections list --fields provider,status,connectionId

# The one that actually answers "does an agent have more access than it needs":
# which agents can reach a given connection, and what each can do
onecli apps connections agent-access --provider github
```

Read the last one carefully — it's the direct, verifiable answer to "we want
security so that agents don't have too much access for things outside what
they need." If it shows an agent reaching a connection nothing in that
agent's config or tasks explains, that's a finding, not a formality.

**Diff its output against docs/INSTALL.md §4's "Per agent: the complete OneCLI
footprint" table** — that table *is* the expected state, one row per grant,
each tied to the task that uses it. Every connection `agent-access` reports
for an agent should match a row there exactly; a connection with no matching
row is either stale (remove it) or undocumented (find out why before trusting
it).

### Worked example: auditing a real vault (11 connections)

A real deployment's audit, applying the steps above:

| Found | Verdict |
|---|---|
| GitHub (Apps tab), Gmail (Apps tab), Google Analytics (Apps tab) | ✅ expected — confirm identity with the `GET /user` check below regardless |
| GitHub App, GitLab, Google Drive, Google Calendar, Google Chat — all **not connected** | ✅ correct — nothing in this template set uses them; an unconnected integration sitting in the "Apps" list is not a requirement, don't connect it "just in case" |
| PostHog API Key (Custom, host `us.posthog.com`) | ✅ matches the coding agent's telemetry row |
| Discord Bot Token (Custom, host `discord.com`) | ✅ expected — `/add-discord`'s own registration, not a manual step |
| LinkedIn Access Token (Custom, host `api.linkedin.com`) | 🚩 **finding**: this template's default LinkedIn posting is the free intent-URL flow, which needs no API credential at all. A live token here with nothing in the current design that calls it is exactly the kind of stale, unused-but-still-valid credential this audit exists to catch — confirm it's actually in use before carrying it forward; if not, remove it |
| 4× Twitter/X secrets (`TWITTER_API_KEY`/`_SECRET`, `TWITTER_ACCESS_TOKEN`/`_SECRET`, all Custom, host `api.x.com`, OAuth 1.0a headers) | 🚩 **verify before reuse**: this is the legacy OAuth 1.0a posting flow. X's pricing changed in Feb 2026 to pay-per-use — confirm whether the *new* API uses this same auth scheme before assuming these four secrets still work; only relevant at all if the owner opts into paid X posting (default is free intent-URL, needing none of this) |
| Anthropic Token (LLMs tab, host `api.anthropic.com`) | ✅ the model provider key, not an identity/posting credential — no rotation needed as part of any bot-identity cleanup |

The two 🚩 rows are the actual value of running this audit: neither is a
security hole, but both are unused surface — exactly what "nothing more than
what's needed" means in practice, not just in the abstract.

## 4 · Confirm identity — the check that catches "started as my own account"

A secret can be perfectly scoped and still belong to the *wrong account*. For
every GitHub credential:

```bash
curl -s -H "Authorization: Bearer <same-value-as-the-vault-entry>" https://api.github.com/user | jq -r .login
```

Compare the printed `login` against the dedicated bot account's username —
never the owner's own. This is exactly the check the welcome interview and
every agent's setup self-check now run automatically (see docs/INSTALL.md §4,
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
per docs/INSTALL.md §4) — an updated value is live on the very next credentialed call
an agent makes. Confirm it rather than just trust it:

1. Run the update.
2. Re-run the identity check in step 4 with the *new* value — confirm it
   resolves to the account you meant.
3. Have the relevant agent make one real read-only call (its own setup
   self-check does this) and confirm success.

**If you're specifically fixing a "this was authenticated as my own account"
mistake**: cut the new bot-account token first, verify its identity with step
4 *before* touching the vault, then `secrets update` the existing entry's
value in place — the host/path binding and everything wired to that secret ID
stays intact; only the account behind it changes.

**Never rotate by editing a template file or an agent's persona** — credentials
never lived there to begin with; this is entirely a vault operation, on the
existing secret ID, and it's exactly why the design keeps them separate.
