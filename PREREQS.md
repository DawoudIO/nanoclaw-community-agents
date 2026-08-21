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
| GitHub bot account | github.com → sign in as the bot, or create a new account | **Do this first** — every token below is cut from this account, not the owner's |
| Lead GitHub PAT | `github.com/settings/tokens` (classic) | Scope `repo` (public-only: `public_repo`). Not `read:org` |
| Coding GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Read-only: Contents+Issues+PRs; + Dependabot alerts if enabling the sweep |
| Marketing GitHub PAT | `github.com/settings/personal-access-tokens/new` (fine-grained) | Content repo only, Contents+PRs read/write |
| Discord bot | `discord.com/developers/applications` → New Application → Bot tab | Fresh application — never reuse a bot from a prior system |
| PostHog key | `<region>.posthog.com` → Settings → Personal API Keys | Read-only on insights/query; note region (`us`/`eu`) |
| GA4 OAuth | `console.cloud.google.com` → enable "Google Analytics Data API"; GA4 Admin → grant Viewer | Not the Admin API |
| Gmail OAuth | `console.cloud.google.com` → Gmail API + OAuth consent | Scope `gmail.readonly` only |
| Tailscale (optional, for remote dashboard access) | `tailscale.com/download` | See README §4 for the exact `serve` command |

**Never paste a raw value into chat, a template file, or anywhere but the
vault** (dashboard UI, or `onecli secrets create` below).

## 2 · Register — dashboard UI or CLI, your choice

The dashboard (README §4) is the visual path. The CLI is scriptable and
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

**Diff its output against README §4's "Per agent: the complete OneCLI
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
every agent's setup self-check now run automatically (see README §4,
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
per README §4) — an updated value is live on the very next credentialed call
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
