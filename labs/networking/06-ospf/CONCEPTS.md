# Lab 6 — Concept: OSPF, Link-State Routing, and Why Adjacencies Are Strict

## What's actually going on

OSPF is a **link-state** routing protocol, which is a fundamentally
different model from the static routes you hand-wrote in Lab 3. Instead
of a router only knowing its own directly connected routes, every OSPF
router builds an identical copy of the *entire area's* topology — a
link-state database (LSDB) — by flooding small, authenticated
advertisements (LSAs) describing "here are my links and their costs" to
every other router in the area. Each router then independently runs
Dijkstra's shortest-path-first algorithm against its local copy of that
LSDB to compute its own best routes. This is why, once `r1` and `r3` both
had full LSDBs (via `r2` as an intermediate hop), `r1` had a route to
`10.0.3.0/24` — a network it has zero direct connection to — with nobody
typing that route anywhere. It's computed, not configured.

Before any of that can happen, two routers on a shared link have to become
OSPF **neighbors**, and neighbor-forming is a strict, multi-step state
machine, not a handshake that just "connects." Routers periodically send
Hello packets (multicast, every `hello-interval` seconds, default 10) that
advertise their router ID, area ID, and configured timers. A neighbor
relationship progresses through defined states — Down, Init (heard a
Hello, not yet bidirectional), 2-Way, then (on broadcast networks, via a
DR/BDR election) ExStart, Exchange, Loading, and finally Full, at which
point both sides have synchronized LSDBs and the adjacency is considered
up. Critically, the Hello packet itself carries the area ID and the timer
values, and **both ends must match exactly** before the state machine will
progress at all — this isn't a soft compatibility check, it's baked into
Hello packet processing.

That's exactly why both challenges break the same way but for different
reasons. Challenge A changes r3's area statement for the r2–r3 link to
area 1 while r2 still expects area 0 on its side of that same physical
link — the Hello packets now carry mismatched area IDs, so r2 rejects
r3's Hellos outright and the adjacency never reaches even the early
states. It's a per-link property, not a per-router one: `r1`–`r2` uses a
completely separate interface and network statement, so it's entirely
unaffected — a router can simultaneously be correctly configured on one
link and broken on another, because OSPF area membership is assigned per
interface, not per box. Challenge B changes only the Hello interval on
one side of the r2–r3 link; FRR doesn't auto-scale the (separately
configured) Dead interval when you tune Hello, so now the two ends
disagree on both. Since Hello/Dead timer agreement is checked exactly like
the area ID — symmetrically, in the Hello packet — a "smaller" change on
only one side produces the identical class of failure as a wrong area:
the adjacency simply refuses to form. Neither mismatch produces a partial
or degraded adjacency; OSPF's design treats these as hard preconditions,
because a router that partially trusted a Hello with disagreeing
fundamentals could build an inconsistent view of the topology.

## Where this shows up in the real world

"Two routers won't peer" is one of the most common real OSPF (and BGP)
tickets, and it is overwhelmingly one of a small, known set of mismatches:
area ID, Hello/Dead timers, MTU (OSPF checks this too, in Database
Description packets), authentication settings, or network type (broadcast
vs point-to-point) disagreement. A network engineer mid-redesign who
changes one router's area assignment without coordinating the other end
of that specific link — exactly Challenge A — is an extremely common
real-world cause of an unexplained "why did this one link just drop"
incident, and the fast diagnosis is always `show ip ospf interface`
compared on both ends of the specific link, not just `show ip ospf
neighbor` on one router.

## Go deeper

- **Book:** *Network Warrior* — Gary A. Donahue — has a solid practical OSPF chapter covering adjacency states, areas, and common misconfigurations.
- **Book:** *Computer Networking: A Top-Down Approach* — Jim Kurose & Keith Ross — covers link-state routing algorithms (Dijkstra/SPF) from first principles.
- **Website/docs:** FRRouting docs — https://docs.frrouting.org — official documentation for the exact `ospfd` behavior and `vtysh` commands used in this lab.
- **Website:** ipSpace.net — https://ipspace.net — Ivan Pepelnjak has deep-dive material on OSPF/link-state design and common real-world adjacency failures.
- **Website:** NetworkLessons.com — https://networklessons.com — structured, example-driven OSPF tutorials covering neighbor states and timer/area matching requirements.
