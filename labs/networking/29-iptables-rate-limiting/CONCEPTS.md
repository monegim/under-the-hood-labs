# Lab 29 — Concept: Token Buckets, and What "Per" Actually Means

## What's actually going on

Both `-m limit` and `-m hashlimit` implement rate limiting using a
**token bucket**: a bucket that holds up to some maximum number of
tokens (`--limit-burst`/`--hashlimit-burst`), refills at a steady rate
(`--limit`/`--hashlimit-upto`), and lets a packet through only if a
token is currently available, consuming one when it does. This is a
well-understood, standard rate-limiting algorithm — the entire question
this lab is actually about is *which bucket* a given packet draws from,
because that's the one thing the two modules genuinely differ on.

`-m limit` maintains exactly one bucket per rule, full stop — every
packet matching that rule's conditions competes for the same pool of
tokens, with zero awareness of where the packet came from. This makes it
a straightforward tool for capping the *aggregate* rate of something
(logging noise, ICMP floods where you don't care about attribution,
overall connection rate to a rule you've written narrowly enough that
"whoever's sending this" doesn't matter) — and a poor tool anywhere
fairness *between* distinct senders matters, because the module
literally has no concept of "distinct senders" to be fair between.

`-m hashlimit` generalizes this by maintaining a whole table of separate
buckets, keyed by whatever `--hashlimit-mode` you choose —
`srcip` (one bucket per source address, this lab's fix),
`dstip`, `srcport`, `dstport`, or combinations of them. Each key gets its
own independent token bucket, refilling and draining on its own
schedule, completely unaffected by any other key's bucket. This is what
makes "protect the service from a flood, without one flooding source
being able to starve every other legitimate source" possible at all —
it requires the scheduler to be able to tell sources apart in the first
place, which `-m limit` was never designed to do.

Burst sizing is a genuinely separate tuning question from which mode
you pick: too small a burst rejects legitimate, mildly-clustered traffic
that any real client naturally produces (a page load's handful of
near-simultaneous connections, a retry after a transient failure);
too large a burst lets a flood through in large enough chunks that the
steady-state rate limit barely matters in practice, since an attacker
can just wait for the bucket to refill and drain it in one burst
repeatedly. There's no universally correct burst value — it has to be
sized against what real, legitimate traffic to the specific
service actually looks like.

## Where this shows up in the real world

Rate limiting that "works" against a synthetic flood test but still
allows a self-inflicted outage the moment a real noisy client
(a misbehaving retry loop, a genuinely malicious single source, an
overly aggressive health check from monitoring infrastructure) shows up
is a common gap in production rate-limiting configuration — teams often
validate "does this throttle load" without validating "does this
continue to treat well-behaved clients fairly while it's actively
throttling something else," which is exactly the scenario a shared,
non-keyed limit fails at. This exact distinction (global vs. per-key
limiting) recurs identically at the application layer too — API
gateways, load balancers, and reverse proxies all have to make the same
choice between a global rate limit and a per-client one, for the same
underlying reasons.

## Go deeper

- **Website/docs:** `iptables-extensions(8)` man page — https://man7.org/linux/man-pages/man8/iptables-extensions.8.html — the authoritative reference for the `limit` and `hashlimit` match modules and every option each supports.
- **Website/docs:** Netfilter/iptables official documentation — https://www.netfilter.org/documentation/ — canonical source for netfilter match/target module behavior.
- **Website/docs:** Wikipedia — Token bucket — a clear, standard reference explanation of the token bucket algorithm both modules implement (search "token bucket algorithm" — this is a well-established, widely-documented CS concept, not tied to any one tool).
- **Book:** *Linux Firewalls* — Michael Rash (No Starch Press) — covers rate limiting and DoS mitigation with iptables as part of its broader practical treatment.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has networking security content covering rate limiting and DoS mitigation concepts alongside broader material.
