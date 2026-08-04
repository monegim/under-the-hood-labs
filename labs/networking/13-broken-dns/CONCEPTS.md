# Lab 13 — Concept: DNS Resolution, Forwarding, and Caching

## What's actually going on

DNS resolution is a chain of independent hops, and every hop can fail in
its own distinct way. A stub resolver (the C library code behind any
program that calls `getaddrinfo()`) reads `/etc/resolv.conf`, picks a
`nameserver` line, and sends it a UDP query on port 53. That's the entire
contract — the stub resolver doesn't know or care whether that IP is a
full recursive resolver, a caching forwarder, or nothing at all. This is
exactly why Challenge A produces total silence: the client isn't failing
to resolve a name, it's failing to reach *anything* at the IP it was told
to ask, which is a routing/reachability problem wearing a DNS costume.

A forwarding resolver like the one in this lab (`dnsmasq --no-resolv
--server=X`) is deliberately simple: it holds no authoritative data of its
own, and for anything not already cached, it opens its own upstream query
to `X` and relays the answer back once one arrives. This split matters
because it creates two genuinely different "resolver-side" failure modes.
If the forwarder itself is down or unreachable, you get exactly Challenge
A's silence, just one hop further in. If the forwarder is *up* but its
upstream is not, the forwarder still owes the client a reply — RFC 1035
requires responding to every query — so it sends back `SERVFAIL`, a real,
fast, structured "I tried and couldn't get you an answer" response. This
is Challenge B, and it's the response code that tells you the failure is
one hop past the resolver you're actually talking to, not at the resolver
itself.

Caching is the third piece, and it's the one that produces symptoms with
no error at all — just a wrong-looking answer. A resolver caches a record
for the TTL the authoritative side attached to it, and correctly serves
that same answer to every query until the TTL expires, decrementing the
reported TTL each time so `dig`'s output tells you exactly how much
cache lifetime is left. This is correct, intended behavior, not a bug —
but it means that changing a record at the authoritative source doesn't
propagate anywhere until every cache holding the old value expires. A
20-second TTL (like this lab uses) makes that window trivially observable;
a real-world record with an hours-long TTL makes "I already changed the
DNS record, why is it still resolving to the old IP" one of the single
most common (and most avoidable, with better TTL planning before a
migration) support tickets in existence.

`resolvectl` (systemd-resolved's control command, not used in this
container-based lab since these images don't run systemd) adds one more
layer worth knowing about on a real host: `resolvectl status` shows which
resolver is actually configured *per interface*, and `resolvectl` maintains
its own cache independent of any downstream resolver's. On a modern
desktop or a systemd-managed server, `/etc/resolv.conf` is frequently just
a symlink to a stub pointing at `127.0.0.53`, with the real per-interface
resolver configuration and caching happening inside `systemd-resolved`
itself — meaning a hand-edited `/etc/resolv.conf` can be silently
overwritten or simply not be the layer actually deciding what gets asked.
`dig +trace` is a different tool for a different problem: it walks the
real root → TLD → authoritative delegation chain for a genuinely
registered public domain, which is why it has nothing to do inside this
lab's fictional `app.internal` zone — it earns its keep in production when
you need to find exactly which delegation hop in a real public domain's
chain is broken.

## Where this shows up in the real world

- Kubernetes: CoreDNS is precisely this lab's `resolver` role for every pod
  in the cluster — a forwarder with local records for cluster services and
  a configured upstream for everything else. "Pods can't resolve external
  names but can resolve `*.svc.cluster.local`" is Challenge B's exact
  signature, just with CoreDNS's `forward` plugin instead of `dnsmasq
  --server`.
- Corporate/VPN split-DNS setups routinely have a resolver that's up and
  answering internal names fine while being unable to reach the public
  internet's DNS for external names — same SERVFAIL-for-a-subset-of-names
  signature.
- **Diagnosis scenario:** "we changed the load balancer's IP an hour ago
  and some users still hit the old one" is Challenge caching content
  (Step 5) wearing a production incident's clothes — the fix isn't
  touching DNS again, it's understanding that TTL-bound caches everywhere
  between the authoritative record and the affected users simply haven't
  expired yet.

## Go deeper
- **Website/docs:** man7.org, `resolver(5)` and `resolv.conf(5)` —
  https://man7.org/linux/man-pages/man5/resolv.conf.5.html — the canonical
  reference for exactly what the stub resolver does with `/etc/resolv.conf`.
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — covers the DNS query/response model and
  caching/TTL behavior this lab is built on.
- **Website/docs:** Cloudflare's engineering blog —
  https://blog.cloudflare.com — frequent deep-dives on DNS internals,
  caching, and resolver behavior at internet scale.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on DNS query types and resolution flow.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck —
  accessible walkthroughs of `dig`, resolvers, and DNS troubleshooting.
