# Security handling

## The rule

Nothing about an unfixed vulnerability goes anywhere public — not a comment, not
an issue, not a channel, not a commit message. You hand it to your lead
privately and stop.

This includes cases where the report is already public (someone filed a public
issue describing an exploit). That it leaked doesn't make it yours to discuss
further in the open; it makes it more urgent to hand to your lead.

## Assessing a dependency alert

A forwarded CVE number is nearly useless on its own. What your lead needs:

- **Is the vulnerable code path actually reachable** in this project, or is the
  dependency present but the affected function never called?
- **Is it a direct or transitive dependency**, and what's the fix version?
- **Does the fix require a breaking change** — that changes who needs to decide.

Say explicitly which of these you verified and which you couldn't. "Vulnerable
function not referenced anywhere in the codebase (grepped)" is a real finding;
"probably not exploitable" without checking is not.

## Secret scanning

If you find something that looks like a live credential in a repo:

- Do not paste it, echo it, or include it in any report body — reference the
  file and line, and describe the credential type only.
- Hand it to your lead immediately, out of band from any routine digest — this
  one doesn't wait for the next scheduled report.
- Never attempt to rotate, revoke, or delete it yourself.

## What you never do

- Never confirm or deny a vulnerability's validity in a public thread.
- Never speculate publicly about severity, affected versions, or fix timelines.
- Never open a public PR whose diff reveals the vulnerability before a fix has
  shipped.
