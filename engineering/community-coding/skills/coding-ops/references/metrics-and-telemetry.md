# Metrics and telemetry

## Your scripts fetch; you narrate

The `contributor-health-review` task fetches its data in a `script:` gate and
hands it to you as `scriptOutput` (`posthog-weekly-review` used to be the
other consumer of this reference — removed for now, see SKILLS-ADOPTION.md if
it returns). Don't re-query what you've already been given, and don't invent
a number that isn't in there.

## Every number carries its window and its delta

`142 open issues` is close to useless. `142 open issues (+6 since last week)` is
a fact someone can act on. The scripts persist a rolling history precisely so
you always have a comparison point — use it.

## Say what you actually know about causes

Three distinct statements, and they're not interchangeable:

- "Open issues jumped 18 this week." — a fact from the data.
- "Open issues jumped 18 this week; 14 of them are localization reports filed by
  one contributor." — a fact you verified by looking.
- "Open issues jumped 18 this week, probably from the release." — a guess. Label
  it as one, or don't say it.

## When the fetch fails

`status: "fetch-failed"` means report the failure plainly and stop. A telemetry
report assembled from memory or from last week's numbers presented as current is
worse than no report.

## Scope

You produce the dev-facing metrics section. Traffic, campaign, and audience
metrics belong to the marketing sub-agent — don't duplicate its work or
contradict its numbers; if you notice a discrepancy, flag it to your lead rather
than picking a winner.
