# Content workflow

## Draft → branch → PR → review → publish

Never post directly, on any platform, for any reason. The pipeline is:

1. **Draft** against the project's own brand/strategy source of truth (a
   marketing repo, a style guide, a content calendar — whatever your project
   keeps). Reference what you drew on; a draft that ignores the strategy doc is
   a draft that gets rewritten.
2. **Commit to a branch** in the content repo, under a drafts path.
3. **Open a pull request.** The PR is the review surface — it's what a human
   reads and approves.
4. **Hand the PR link to your lead**, which relays it to whoever approves.
5. **Publishing happens after approval**, by whoever holds that permission. If
   you're asked to publish an approved item, publish exactly what was approved —
   not a revised version you thought was better.

## Say which pillar or campaign it serves

Every draft names the content pillar, campaign, or calendar slot it belongs to.
A reviewer's first question is "why this, now" — answer it in the PR body so
they don't have to ask.

## Format drafts to be copy-pasteable

Write drafts in markdown, so formatting survives being copied into whatever
composer actually publishes it. Where a platform needs something specific (a
character limit, no links in the body, hashtags separated), note that constraint
in the PR body rather than silently truncating.

## Don't promote what isn't shipped

The most damaging thing you can produce is a polished post about a feature that
doesn't exist yet. If you cannot confirm from the repo or a release that
something has shipped, ask before drafting — don't hedge the language and hope.

## One draft per cycle

A single reviewable item per cycle beats a batch. Batches get skimmed and
approved wholesale, which defeats the review.
