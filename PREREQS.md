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
| **Model access (what the agents think with)** | **Preferred: your Claude subscription.** The kit's first-boot wizard accepts *a subscription, an OAuth token, or an Anthropic API key* — pick subscription and there's no per-token bill. Alternative: `console.anthropic.com` → API Keys. Either way the credential lands in the OneCLI vault (**LLMs** tab), never in a file. | **Nothing works without this.** Symptom when missing, expired, or out of capacity: the lead simply never replies to your DM — no error surfaces anywhere you'd see it. **Read [OPERATIONS.md → Model budget — one shared window, and the trap in it](docs/OPERATIONS.md) before choosing**: a subscription shares one usage window with your own Claude Code sessions, which has a real failure mode attached. All four agents, including local ops, draw on this same window — a local (Ollama) model for the local agent was tried and set aside for now (too much setup friction to get end-to-end working); see [SKILLS-ADOPTION.md](SKILLS-ADOPTION.md) for that history if you want to revisit it later |
| GitHub bot account | github.com → sign in as the bot, or create a new account | **Do this first** (after the model key) — every token below is cut from this account, not the owner's |
| Lead GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Issues+PRs read/write, Contents read, over `COMMUNITY_REPOS`. Not classic, not `read:org` |
| Local GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Read-only over `COMMUNITY_REPOS` + `MIRROR_REPOS`; plus Contents **write on the backup repo only** |
| Coding GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Read-only: Issues+PRs; + Dependabot alerts if enabling the sweep. `COMMUNITY_REPOS` only |
| Marketing GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Content repo only, Contents+PRs read/write |
| Discord bot | `discord.com/developers/applications` → New Application → Bot tab | Fresh application — never reuse a bot from a prior system |
| GA4 OAuth | `console.cloud.google.com` → enable "Google Analytics Data API"; GA4 Admin → grant Viewer | Not the Admin API. **Belongs to the Local ops agent (`local/community-local`)** (`weekly-analytics-report`) — marketing does not get analytics access; it writes drafts, it doesn't read numbers |
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

**Use fine-grained PATs for all four agents.** A classic `repo` scope is
account-wide (every repo the bot can see, read *and* write); a fine-grained
token is an allowlist of named repos with per-category permissions. Nothing
here needs classic. Note that a fine-grained token's repo list gates
**everything** the token does — including reads of otherwise-public data — so
a repo left off the list fails silently rather than falling back to public
access. That's the single most common misconfiguration in this system.

**Every gate SCRIPT is a read.** Writes happen exclusively in the agents' live
actions after a gate wakes them — which is why, of the four tokens, write is
narrow and unevenly distributed:

- **Lead** — Issues and PRs write, for its own live replies: filing a bug
  report from a Discord conversation, commenting, labelling.
- **Marketing** — Contents and PRs write, on the content repo only, to commit
  a draft and open its PR.
- **Local** — Contents write on the **backup repo only**, for
  `workspace-backup`'s git push. Everything else it does is a read.
- **Coding (the Reviewer)** — Contents and PRs write, but only to open a
  **draft** PR: a security-patch branch (`security-advisory-sweep`, confirmed
  advisories only) or a version-tagged docs branch (`docs-currency-watch`).
  It never marks a PR ready, never merges, and never pushes to a default
  branch — see §1b's least-privilege table for the branch-protection
  requirement this write scope depends on.

So all four hold some write, but only two hold write on a repo anyone reads
day to day (the lead on the community repos, marketing on the content repo).
Local's write reaches exactly one private backup repo; the Reviewer's reaches
only its own draft branches, never anything mergeable without a human.

There is exactly one `POST` in the whole system, it belongs to the **local**
agent (`weekly-analytics-report`), and it is **not** a write:
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
| Issues | **Read + Write** | reads `GET /repos/{repo}/issues` (`daily-github-triage`); writes = filing bug reports from Discord, commenting, labelling in its live replies (`github-bug-workflow.md`) |
| Pull requests | Read + Write | commenting on PRs in those same live replies; the issues endpoint also returns PRs |
| Contents | Read | `GET /repos/{repo}/releases/latest` (`release-announcement-watch`) |

Repo list: everything in `COMMUNITY_REPOS`. **Never** `admin:*`,
`delete_repo`, `read:org`, or workflow scopes — nothing reads org membership
(listing an org's repos during onboarding needs no such scope) and nothing
touches Actions.

One nuance on the Issues row worth knowing before you cut it smaller:
`daily-github-triage` is the lead's **standalone-mode fallback** and is
normally left paused when the Reviewer is stamped, because `github-ops-triage`
covers the same ground at higher cadence. Pausing that task does *not* let you
drop the write permission — the lead needs Issues and PRs write for its live
replies regardless, which is the larger justification of the two.

### Local — `local/community-local`

Eleven of the nineteen tasks, and the only agent holding credentials that
aren't GitHub at all. Almost entirely read-only: its single write is a git
push to one private repo.

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | implied by everything; `GET /repos/{repo}` in setup-check, `/community/profile` (`repo-hygiene-audit`), `/contributors` (`dev-metrics-report`) |
| Issues | Read | `GET /repos/{repo}/issues` and `GET /search/issues` (`good-first-issue-health`, `dev-metrics-report`, `repo-hygiene-audit`) |
| Contents | Read | `GET /repos/{repo}/releases` (download counts), plus `git clone/fetch` over `github.com` for `repo-mirror-sync` |
| Pull requests | Read | `GET /repos/{repo}/pulls` (`draft-cleanup`) |
| Contents (**backup repo only**) | **Write** | `workspace-backup` pushes over `github.com` git — a *separate vault entry* from `api.github.com`, and ideally a separate token scoped to just that repo |

One non-GitHub host lives on this agent and nowhere else: the GA4 OAuth connection
(`analyticsdata.googleapis.com`, `weekly-analytics-report`). If
`agent-access` reports either of them reachable by the lead, the Reviewer, or
marketing, that's a finding — see §3.

Repo list: the union of `COMMUNITY_REPOS` and `MIRROR_REPOS` (the mirror set is
usually the larger — it covers docs/site/wiki even when those aren't triaged),
plus the backup repo if enabled. Public repos need no credential at all for the
git clone.

Worth noticing what is *absent* from every row above: `unanswered-watch`, the
task the whole responsiveness guarantee rests on. It has no network access and
no credential — it reads local message state only. That is exactly why it keeps
working during the outage it exists to cover; a token problem cannot silence it,
because it never had a token.

### Coding — `engineering/community-coding`

**Read everywhere; write in exactly one place — security patch PRs.** This
agent drafts a dependency-bump PR when it confirms an advisory genuinely
affects the project, so it needs enough write to create a branch and open a
draft PR, and nothing beyond that.

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | implied by everything; `GET /repos/{repo}` in setup-check |
| Issues | Read | `GET /repos/{repo}/issues` (`github-ops-triage`) |
| Dependabot alerts | Read | `GET /repos/{repo}/dependabot/alerts` (`security-advisory-sweep`) — **omit this and the sweep 403s**; it's the one permission people forget |
| Contents | **Write** | create the `security/<ghsa-id>` branch and commit the manifest/lockfile version bump (`security-advisory-sweep`); create the docs branch (`docs-currency-watch`) |
| Pull requests | **Write** | `POST /repos/{repo}/pulls` with `draft: true` — the security patch, and the version-tagged docs PR |
| Issues | Read → **also needed on `DOCS_REPO`** | `docs-currency-watch` reads merged PRs on the product repo and opens a PR on the docs repo |

**Why this is still least-privilege.** Contents write is the permission that
lets an agent change a repo, so it deserves the scrutiny: it is here because
"you should upgrade lodash" is strictly less useful than a branch that already
does it, and no smaller permission creates a branch. What bounds it is not the
token but the combination of the token and **branch protection** — which is why
the next paragraph is a requirement, not a suggestion.

**Require branch protection on the default branch of every repo on this
token.** The agent is instructed never to push to the default branch and never
to mark a PR ready or merge it, but instructions are not a control. Protection
is: require a PR and at least one approving review, and the agent physically
cannot land anything on its own even if a prompt injection convinces it to try.
If a repo on this token has no branch protection, this token should not have
Contents write on it — drop to read there and accept that advisories on that
repo get a report instead of a patch.

**Note what it still cannot do**, and check these on the fine-grained form:
no Administration, no Actions, no Secrets, no Workflows (a workflow-file write
is remote code execution on your CI), no Issues *write* — it drafts issue text
for the lead rather than opening issues itself.

**Repo list: `COMMUNITY_REPOS` plus `DOCS_REPO`.** This is the one place the
Reviewer's token reaches outside the triaged set, and it is easy to miss:
fine-grained PATs are per-repository even for public data, so if the docs live
in their own repo and it is not on this token's access list,
`docs-currency-watch` fails to open its PR with a 403 and the whole
docs-follows-release loop silently never runs. If the docs are a subdirectory
of the product repo instead, no extra repo is needed — set `DOCS_PATH`.

Still **not** `MIRROR_REPOS`. Mirroring is the
local agent's job, so a mirror-only repo on this token is access nothing here
uses, and unused access is exactly what §3's audit exists to catch.

All of this agent's current tasks call `api.github.com` and so depend on this
token: `github-ops-triage`, `security-advisory-sweep`,
`contributor-health-review`, `dependabot-pr-review` and `docs-currency-watch`
(`posthog-weekly-review` is removed for now — see SKILLS-ADOPTION.md if it
comes back; it would run on its own PostHog credential, needing nothing
here). Verify the list against
`grep -l api.github.com scripts/tasks/engineering/*.sh` rather than trusting
this paragraph — it is the kind of list that goes stale on every split.

If you are re-cutting this token against an older copy of this doc that said
"read-only, no write of any kind", that changed deliberately: the Reviewer
drafts security patches now.

### Marketing — `marketing/community-marketing`

This agent holds exactly **one** task, `content-draft-cycle`, and every
permission below traces to it.

| Permission | Level | Justified by |
|---|---|---|
| Metadata | Read | setup-check reachability probes |
| Contents | **Read + Write** on `CONTENT_REPO` | commits drafts to a branch (`content-workflow.md` step 2) |
| Pull requests | **Read + Write** on `CONTENT_REPO` | opens the draft PR (step 3) |
| Contents | Read on `BRAND_SOURCE_REPO` | reads brand voice / pillars / calendar, if a different repo |
| Contents | Read on `RELEASE_WATCH_REPO` | `GET /releases/latest` for the content trigger, if a different repo |

The PR write used to carry a second justification, `draft-cleanup`'s
`GET /repos/{repo}/pulls`. That task is the local agent's now — and it only
ever needed *read*, so this is one fewer reason for the write, not one fewer
permission. The write still stands on step 3 alone: marketing has to open the
draft PR it just committed.

Repo list: `CONTENT_REPO` (write) plus `BRAND_SOURCE_REPO` and
`RELEASE_WATCH_REPO` (read) **when those differ** — the most common silent
failure in this system is leaving one of the latter two off the list. Note
`CONTENT_REPO` is set on **both** marketing and local, for different reasons
and at different levels: marketing writes drafts there, local only reads PRs
there to find stale ones.

No social-platform credential is wired to this agent in any configuration, and
no analytics credential either — GA4 belongs to the local agent. Marketing
writes the drafts; it does not read the numbers.

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
| PostHog API Key (Custom, host `us.posthog.com`) | 🚩 **finding**: `posthog-weekly-review` (the Reviewer's telemetry task) is removed for now — never got working end to end. A live PostHog key with no task consuming it is unused surface; remove it, or leave it if you plan to re-add the task soon |
| Discord Bot Token (Custom, host `discord.com`) | ✅ expected — `/add-discord`'s own registration, not a manual step |
| LinkedIn Access Token (Custom, host `api.linkedin.com`) | 🚩 **finding**: this template's default LinkedIn posting is the free intent-URL flow, which needs no API credential at all. A live token here with nothing in the current design that calls it is exactly the kind of stale, unused-but-still-valid credential this audit exists to catch — confirm it's actually in use before carrying it forward; if not, remove it |
| 4× Twitter/X secrets (`TWITTER_API_KEY`/`_SECRET`, `TWITTER_ACCESS_TOKEN`/`_SECRET`, all Custom, host `api.x.com`, OAuth 1.0a headers) | 🚩 **verify before reuse**: this is the legacy OAuth 1.0a posting flow. X's pricing changed in Feb 2026 to pay-per-use — confirm whether the *new* API uses this same auth scheme before assuming these four secrets still work; only relevant at all if the owner opts into paid X posting (default is free intent-URL, needing none of this) |
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
