# Incident 08 — Concept: Half-Broken Dual-Stack, and Clients That Don't Race

## What's actually going on

Two mechanisms combine here: how a client picks between multiple
addresses for one hostname, and what "reachable" actually means at
different layers of the network stack.

A dual-stack hostname resolves to more than one address -
`getaddrinfo()` (or Docker's embedded DNS, doing the same job) hands
back both an AAAA (IPv6) and an A (IPv4) record. What a client *does*
with two candidate addresses varies enormously by implementation.
Happy Eyeballs (RFC 8305) is the well-behaved answer: start a
connection attempt on one address family, and if it hasn't succeeded
within a short interval (RFC 8305 recommends 250ms), start a second
attempt on the other family *in parallel*, using whichever connects
first and cancelling the loser. Browsers implement this carefully,
specifically because they learned this exact lesson at internet scale.
A huge share of other HTTP clients, language standard libraries, and
database drivers do not - they resolve once, then try each returned
address *sequentially*, waiting for one attempt to fail or time out
before starting the next. That difference is invisible when every
candidate address either works instantly or fails instantly. It stops
being invisible the moment one candidate address hangs.

That's the second mechanism: a network path can be "reachable" at one
layer and not another, and the tools that check each layer test
completely different things. ICMP echo (`ping`/`ping6`) is handled
entirely in the kernel, is stateless, and doesn't care whether any
application is even listening on any port - it only confirms basic
routing works. A TCP connection to a specific port depends on that
port being both open *and* actually reaching a listening socket, which
a stateful firewall rule can interrupt independently of routing. A rule
that `REJECT`s a connection sends back an immediate, explicit "no" (a
TCP RST) - a sequential-fallback client absorbs that quickly and moves
on to the next address with barely any cost. A rule that `DROP`s a
connection sends back nothing at all, silently discarding the SYN -
the connecting side has no way to distinguish "nobody's there yet" from
"actively broken," and has no choice but to wait out its own configured
timeout before giving up and trying anything else. A silently dropped
path is strictly worse for a sequential client than that path not
existing at all: a fully absent address is never offered as a
candidate to begin with, while a silently-broken one gets offered, and
paid for, on every single connection attempt, forever, for as long as
DNS keeps advertising it.

## Where this shows up in the real world

IPv6 adoption inside internal infrastructure (as opposed to
public-facing endpoints, where it's usually more mature) tends to be
incremental and uneven - a network gets dual-stacked, security
groups/firewalls get updated for IPv4 first "because that's what
already works," and IPv6 rules lag behind, sometimes by months. The
gap is invisible to anyone testing with `ping6` or checking basic
connectivity, and invisible to any monitoring that only checks whether
a request *eventually* succeeds rather than how long it took. It
surfaces as a business-facing latency regression with no error rate to
match, on services that made no code change at all - the actual change
was somewhere in DNS or firewall configuration, several layers removed
from the application, which is exactly what makes "nothing we deployed
correlates with this" a true statement and a red herring at the same
time.

## Go deeper

- **RFC 8305** — Happy Eyeballs Version 2 — https://www.rfc-editor.org/rfc/rfc8305 — the actual specification for racing IPv4/IPv6 connection attempts, including why it needs to be an interval-based race rather than a simple parallel start.
- **RFC 6724** — Default Address Selection for Internet Protocol Version 6 — https://www.rfc-editor.org/rfc/rfc6724 — governs the order `getaddrinfo()` returns candidate addresses in, including the common IPv6-preferred default.
- **Man page:** `iptables(8)`/`ip6tables(8)` — `man iptables` — the `-j DROP` vs `-j REJECT` distinction this entire incident hinges on.
- **Related lab:** [`labs/networking/24-ipv6-dual-stack-issues`](../../networking/24-ipv6-dual-stack-issues) — the "half-broken IPv6 is worse than fully absent" mechanism in isolation, with a from-scratch Happy Eyeballs explanation.
- **Related lab:** [`labs/networking/28-iptables-ipv6-gap`](../../networking/28-iptables-ipv6-gap) — the "`iptables` and `ip6tables` are two independently-maintained rule sets" mechanism in isolation; this incident is what it looks like when both mechanisms land on the same service at once.
