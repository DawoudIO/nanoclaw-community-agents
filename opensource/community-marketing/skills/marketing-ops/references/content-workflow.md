# Content workflow

## Draft → branch → PR → review → publish

Never post directly, on any platform, for any reason. The pipeline is:

1. **Draft** against the project's own brand/strategy source of truth (a
   marketing repo, a style guide, a content calendar — whatever your project
   keeps). Reference what you drew on; a draft that ignores the strategy doc is
   a draft that gets rewritten. **Before drafting, check whether the project's
   own repos already document their voice**: most repos ship a `skills/`
   directory, `.claude/skills/`, `AGENTS.md`, or `CLAUDE.md` now — grep the
   product and brand-source repos (via the coding agent's `repo-mirror-sync`
   checkout if mirrored, or a live read otherwise) for anything that reads
   like house style, terminology, or a documented tone. Treat what you find
   as authoritative alongside the brand/strategy source, not a nice-to-have —
   a project that already wrote down "never call it X, always Y" has done
   your research for you.
2. **Commit to a branch** in the content repo, under a drafts path.
3. **Open a pull request.** The PR is the review surface — it's what a human
   reads and approves.
4. **Hand the PR link to your lead**, which relays it to whoever approves.
5. **Publishing happens after approval, and never by you.** A human with the
   platform credential does it — you have none, by design. If you're asked to
   publish, that's a request you decline and route: say you can't post
   anywhere, and hand back whatever makes the human's click trivial (the
   intent URL, or the copy-pasteable text). Publishing exactly-what-was-
   approved is the *human's* rule, not a task you carry out.

## Publishing mechanics — decided per platform at onboarding

Which platforms exist, which ones the project actually posts to, and HOW each
one publishes is config, not improvisation — it's collected at onboarding
(ask your lead if it's missing from your project-config) and recorded per
platform as one of:

- **Intent URL (free, no API key, recommended default).** Draft the text, URL-
  encode it into the platform's compose link, and hand the link to the
  approver — one click opens a pre-filled composer under THEIR account.
  X: `https://x.com/intent/post?text=<encoded>` · LinkedIn:
  `https://www.linkedin.com/feed/?shareActive=true&text=<encoded>`.
  Human clicks Post; nothing automated touches the platform.
- **Manual copy-paste.** The approved PR's markdown IS the deliverable (that's
  why drafts must be copy-pasteable); the approver pastes into the composer.
  Always works, zero setup — the fallback for platforms with no intent URL
  (e.g. Facebook pages, Instagram).
- **Paid API posting (optional, costs real money).** As of Feb 2026, X has NO
  free API tier: new developers get pay-per-use (~$0.015/post, ~$0.20 per post
  containing a link; legacy Basic $200/mo is closed to new signups). At one
  link-post per day that's roughly $6/month — cheap, but a choice the owner
  makes explicitly, never a default. **Even when enabled, the API call is not
  yours to make**: you hold no posting credential in any configuration, and
  the install runbook puts an OneCLI request-hold on that host so the post
  still waits on a human button-press. Your output is the approved text,
  identically to the other two mechanisms — what changes is only who clicks
  and where, never that you gain a publish path.

If the owner doesn't want to pay for X: intent URLs give the identical
after-approval flow at zero cost, with the approver's click as the final gate —
which also happens to be the strongest version of the approval discipline.

**Approval mechanics and post-publish hygiene**: intent-URL and copy-paste
need no separate approval step — the owner's click or paste already is the
decision. For the paid-API path, the approval is a real OneCLI request-hold
button (set up once as a host+method+path rule), not a chat reply — see the
lead skill's `discord-mechanics.md`. After everything is published: delete
the consumed draft, push the deletion, close the PR, and confirm with the
published URLs. A drafts folder full of already-published content is how
duplicates get posted.
Never work around a missing API with browser automation against the platform's
own web app; that violates platform terms and gets accounts suspended.

## Say which goal, audience, and pillar it serves

Every draft names, in the PR body: the growth goal it serves (from the owner's
chosen goals in project-config — see `growth-playbook.md`), the audience
(users vs contributors), the platform it's shaped for, and the content pillar
or calendar slot. A reviewer's first question is "why this, now, for whom" —
answer it so they don't have to ask. If the owner declined a growth goal at
onboarding, don't draft for it.

## Format drafts to be copy-pasteable

Write drafts in markdown, so formatting survives being copied into whatever
composer actually publishes it. Where a platform needs something specific (a
character limit, no links in the body, hashtags separated), note that constraint
in the PR body rather than silently truncating.

## Official brand assets only

Any visual (social image, card, banner) uses the project's official logo and
brand assets from the brand source — **never a generated, placeholder, or
"close enough" logo**, ever. Respect the assets' usage notes (e.g. a
dark-background logo needs a light container on light backgrounds). If the
official asset isn't available where you're working, ask for it rather than
substituting.

## Don't promote what isn't shipped

The most damaging thing you can produce is a polished post about a feature that
doesn't exist yet. If you cannot confirm from the repo or a release that
something has shipped, ask before drafting — don't hedge the language and hope.

## One draft per cycle

A single reviewable item per cycle beats a batch. Batches get skimmed and
approved wholesale, which defeats the review.
