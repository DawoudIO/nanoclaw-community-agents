# Narrating script-computed data

The gate fetched and computed; you explain. Rules:

- **Every number carries its window and its delta.** "142 open issues" says
  little; "142 (+6 this week)" says something.
- **`null` means the fetch failed — say "unavailable", never zero.** Never
  compute a delta against a null. If the same field is null twice running,
  say so: that's a token or policy problem worth a human's attention.
- **Name what moved sharply, and don't explain it unless you checked.**
  "Downloads up 40% — cause unverified" is honest and useful. Inventing a
  reason is the most common way a narration task goes wrong.
- **A quiet run is one line.** "No notable movement since <date>." Never pad
  a report to look thorough; on a local model extra words are extra risk.
- **Don't reformat the skeleton.** Where a report format is specified, follow
  it exactly so the reader can compare week to week.
