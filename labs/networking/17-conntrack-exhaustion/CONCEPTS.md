# Lab 17 — Concept: Connection Tracking and Its Limits

## What's actually going on

Any router doing NAT, stateful filtering, or anything that needs to
recognize "this packet belongs to a connection I've already seen" has to
keep a record of every active flow somewhere. In Linux, that's
`nf_conntrack` — a hash table living in kernel memory, one entry per
tracked flow (a 5-tuple: protocol, source/dest IP, source/dest port, plus
some protocol-specific state like TCP's connection state machine).
`iptables -m conntrack --ctstate NEW,ESTABLISHED,RELATED` doesn't just
match against this table, it's frequently what causes netfilter to start
populating it in the first place for a given chain — this lab's Step 2
rule exists specifically to guarantee `r1` is actually tracking forwarded
connections rather than just blindly forwarding packets with no state
kept at all.

`nf_conntrack_max` is the table's hard ceiling, and Linux's behavior when
it's reached is deliberately fail-closed, not fail-open: a packet that
would need to create a new entry and finds the table full gets dropped
right there, before it's forwarded anywhere. This is a correctness
decision, not a bug — silently forwarding untracked traffic once the
table is full would mean a stateful firewall stops actually being
stateful exactly when it's under the most load, which is a worse failure
mode than dropping some new connections. The cost of that choice is
exactly what this lab demonstrates: the drop is completely silent from
outside the box doing the tracking. No RST, no ICMP unreachable, nothing
in either endpoint's own logs — just a connection attempt that quietly
never completes, which is why this incident class gets misdiagnosed as
"the network" or "the server" so often.

`conntrack -S` (statistics) and `conntrack -C` (a plain count) are the
tools that make this failure legible instead of invisible.
`nf_conntrack_count` (current entries) versus `nf_conntrack_max`
(the ceiling) tells you immediately whether you're at capacity at all;
`conntrack -S`'s `insert_failed` and `drop` counters tell you whether
attempts are actively being rejected right now. `conntrack -L` lists the
table's actual contents, and this lab's two challenges are built
specifically to show that *the count alone doesn't tell you the root
cause* — a table pinned at its maximum could mean a genuine traffic
burst (Challenge A: lots of `NEW` entries created recently, in a short
window) or a slow accumulation of connections nobody ever closed
(Challenge B: entries that have clearly been sitting there a while, with
no recent creation burst at all). Distinguishing "too much legitimate
concurrent load" from "a leak" changes what you actually go fix — rate
limiting or capacity planning for one, an application bug for the other.

`nf_conntrack_buckets` (the underlying hash table's size, distinct from
`nf_conntrack_max`, the number of entries the table is *allowed* to hold)
is a second, related tuning knob worth knowing exists: a `max` set much
higher than what `buckets` can hash efficiently leads to long hash chains
and real per-packet lookup cost, even before the table is technically
full. This lab doesn't exercise that specific failure mode, but it's the
natural next thing to reach for once you understand why `nf_conntrack_max`
alone isn't the whole story.

## Where this shows up in the real world

- Any NAT gateway, load balancer, or stateful firewall handling many
  short-lived connections (a busy API gateway, a proxy in front of a
  microservices mesh) can hit `nf_conntrack_max` under real production
  load if it was never sized for actual peak concurrency — a classic
  "worked fine in staging, fell over under Black Friday traffic" bug.
- Connection-pool or retry-loop bugs in client applications (never
  closing sockets, reconnecting without cleaning up) are one of the most
  common real causes of Challenge B's slow-leak pattern, often going
  unnoticed for days before the table finally fills.
- **Diagnosis scenario:** "some fraction of requests through our NAT
  gateway just fail, and it doesn't correlate with CPU, memory, or
  bandwidth on the box" is this lab's exact production shape — conntrack
  exhaustion doesn't show up in the metrics people check first, because
  it isn't a resource those dashboards typically track at all.

## Go deeper
- **Website/docs:** man7.org, `conntrack(8)` —
  https://man7.org/linux/man-pages/man8/conntrack.8.html — the canonical
  reference for the `conntrack` CLI's `-L`/`-S`/`-C`/`-F` and the
  statistics fields this lab reads directly.
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — background on TCP connection state
  that conntrack's own state machine mirrors.
- **Website/docs:** Cloudflare's engineering blog —
  https://blog.cloudflare.com — has published deep-dives on connection
  tracking and stateful firewall behavior at scale.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on stateful firewall/NAT connection tracking.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck —
  accessible walkthroughs of iptables/netfilter concepts including
  connection tracking.
