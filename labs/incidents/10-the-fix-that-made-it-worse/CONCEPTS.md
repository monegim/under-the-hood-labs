# Incident 10 — Concept: Retries Are a Load Multiplier, Not Just a Safety Net

## What's actually going on

Two mechanisms combine here: a system operating right at the edge of
its own finite capacity, and a client-side recovery mechanism that
looks purely beneficial from any single request's point of view but
isn't neutral from the *system's* point of view.

A backend sized for average load, not peak load, isn't broken when it
fails some requests during a burst — that's the deliberate, accepted
tradeoff of not over-provisioning for traffic that only shows up
occasionally. What matters for that tradeoff to hold is that the
failure rate stays bounded and the system actually drains back to
idle between bursts, ready for the next one. A retry policy changes
the arithmetic of that drain. Without retries, a failed request is one
unit of load, once — the backend only ever has to absorb exactly the
traffic that was actually offered to it. With retries and no backoff,
every failed request can become up to `1 + RETRIES` units of load, all
generated immediately, specifically *because* the backend was already
too loaded to serve the first attempt. The retries aren't spread out
over time or throttled based on how the backend is actually doing —
they fire at the same moment as the failure that triggered them,
directly into the same congested backend, adding to the exact
condition that caused them to be needed at all.

This is a positive feedback loop, not just "more load" — a bigger
backlog means more requests time out, which means more retries, which
means an even bigger backlog. Whether that loop is stable (settles at
some elevated-but-bounded failure rate) or runs away entirely (climbs
toward serving nothing at all) depends on how much headroom exists
between offered load and capacity, and on how aggressively retries add
to that load — a small excess with modest retries can still find a new
equilibrium; a large enough excess, or aggressive enough retries, has
no equilibrium below total saturation. Nothing about a retry policy
that looks reasonable in isolation — "retry up to 3 times" sounds
modest — reveals which regime it's actually in until it's tested
against a backend that's genuinely, sustainedly at capacity, which is
specifically the condition a quick functional test against an
otherwise-idle system will never reproduce.

## Where this shows up in the real world

Retry-related outage amplification is one of the most well-documented
distributed-systems failure patterns precisely because the fix that
causes it is almost always well-intentioned and locally correct — a
developer adding retry logic to reduce user-visible errors is solving
a real problem, correctly, from the perspective of any one request.
It becomes a systemic problem only in aggregate, under real load,
against a backend that's already struggling — exactly the condition
least likely to be present during code review or a pre-production
test. The standard mitigations (exponential backoff, jitter to
de-synchronize retries across many clients, retry budgets, circuit
breakers that stop sending traffic entirely once a backend's error
rate crosses a threshold) all exist specifically because "just retry
on failure" is a mechanism whose safety depends entirely on the state
of the system it's retrying against, not on the retry logic itself
being written correctly.

## Go deeper

- **Website/docs:** Google Cloud, "Implementing exponential backoff" — https://cloud.google.com/storage/docs/retry-strategy — a widely-referenced, practically-oriented explanation of backoff and jitter and exactly why naive immediate retries are dangerous at scale.
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et al. (free at https://sre.google/books/) — the chapter on addressing cascading failures covers retry storms and retry budgets directly.
- **Book:** *Release It!* — Michael T. Nygard (Pragmatic Bookshelf) — the circuit breaker pattern originates from this book and is the standard architectural answer to exactly this failure mode.
- **Related lab:** [`labs/incidents/09-the-shared-proxy-meltdown`](../09-the-shared-proxy-meltdown) — the same "finite shared capacity, overwhelmed by more demand than it was sized for" mechanism, without the retry-driven feedback loop — a useful side-by-side contrast for exactly what retries add on top.
- **Talk:** Marc Brooker, "Reliable Distributed Systems: Retries" (search the exact title — an AWS Builders' Library / re:Invent talk) — a deep, practitioner-level treatment of when retries help versus when they make cascading failures worse.
