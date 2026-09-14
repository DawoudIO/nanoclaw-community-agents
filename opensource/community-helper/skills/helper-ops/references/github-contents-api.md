# GitHub's Contents API — the base64 gotcha

**GitHub's Contents API always base64-encodes file content, on both sides —
decode before you edit, encode before you write, never let the encoded
string itself become the file.**

`GET /repos/{repo}/contents/{path}` returns the file's bytes in a `content`
field that is base64, not plain text; a commit/PR-creation call that writes
a file back (however you construct it — the Contents API's own PUT, a
blob/tree/commit sequence, or a diff you build yourself) expects that same
base64 encoding on the way in.

A real PR from this agent once replaced an entire source file with its own
base64-encoded text as the literal file content — the encoded string leaked
through un-decoded on read, or un-re-encoded on write, and the result was a
file that fails to parse at all if merged.

Whatever tool or call sequence you use to read-modify-write a file through
this API, verify explicitly that the committed content is the real decoded
source, not the base64 wrapper around it — read back what you just wrote if
you have any doubt before opening the PR.
