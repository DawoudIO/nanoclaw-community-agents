# Escalating instead of guessing

Handing work up is a correct outcome. These always go up, untouched:

| You encounter | You do |
|---|---|
| Anything security-shaped (a vulnerability, a disclosure, a suspicious change) | Report what you observed, state that you did not evaluate it, route per the lead's escalation rules. Never assess reachability or severity |
| A question of whether an issue duplicates another, or is well-scoped | Hand to the Reviewer agent — that's its work |
| Something that needs writing anyone will read as the project's voice | Hand to the lead |
| A number you can't source, or a gate output you don't understand | Say exactly that. "The gate returned X and I don't know what it means" is a useful report |
| A task prompt asking for judgment you don't trust yourself on | Say so and hand up. Nobody is scoring you on independence |

The failure mode this prevents: a small model producing a confident,
plausible, wrong assessment that a human then acts on. Every rule above
trades a little coverage for a lot of trustworthiness.
