# Gate script conventions

## State files are CSV, never JSON/JSONL

Any file a gate script or the agent writes and later reads back — a seen-list,
a history series, a cache — is CSV with a header row, not JSON or JSONL.

**Why:** JSON/JSONL repeats its field names on every line, which is pure
token cost for an agent reading its own history back. CSV pays for the
schema once, in the header.

**How:**
- Fixed columns, header row written once at file creation.
- Read with `awk`/`grep` (`grep '^<key>,'`, `tail -1`, an `awk -F,` pass) —
  no JSON parser needed on our own state.
- Blank field = not measured; never write `null`, `"null"`, or a `0` standing
  in for missing data.
- No commas inside any field's content (slugs, ids — pick formats that don't
  need one; never comma-bearing free text in a CSV file).

**Exception:** `jq` is still the right tool for parsing an external API
response (GitHub, GA4, `ncl --json`) — that input isn't ours to reshape.
The rule is about files *we* write and read back, not about the world.

Applies to every new gate script and task. Existing files get converted
opportunistically when touched for another reason — not as a standalone
sweep.
