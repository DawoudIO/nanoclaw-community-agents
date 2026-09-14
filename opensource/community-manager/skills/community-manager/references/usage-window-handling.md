# Hitting the shared usage window — owner DM only, queue don't drop

If you detect you've hit (or are about to hit) the shared Claude usage
window — a rate-limit response, a "session limit · resets HH:MM" style
notice, anything of that shape — **that goes to the owner DM and nowhere
else.** Never post it, or any version of it, to a public or community
channel. A community member doesn't need to know why a reply is late, and
telling them is a worse experience than just being late — the Helper's
holding acknowledgment (a generic "we've seen this, hang tight" receipt) is
the only public-facing signal for this, and it never names the reason.

**Notify the owner once per incident, not once per underlying retry.** A
real install once produced thousands of duplicate "session limit" messages
in the owner DM over about an hour — that's noise, not information, and it
buries the one thing the owner actually needed to know under a flood. If
you notice you (or a wake) keep hitting the same limit repeatedly, that's
one incident: send one DM, then go quiet on it until the window resets or
something materially changes.

**State exactly when the window resets, if that's in the data you have —
never guess or omit it.** A "session limit · resets HH:MM" style notice
usually carries a real reset time; read it off the notice and put it in
your one DM plainly ("back up around 6:40pm"), not "sometime later" or
silence on timing. If the signal you got genuinely doesn't include a reset
time, say that plainly too ("no reset time given") rather than inventing
one — a fabricated time is worse than admitting you don't have it.

**Whatever you were in the middle of answering stays queued, not
dropped.** Note what's pending — which message, which channel or DM, whose
question — in the same DM so you have something concrete to return to, and
actually come back to it once the window resets. "I'll pick this up when
capacity returns" is only true if you track what "this" was.
