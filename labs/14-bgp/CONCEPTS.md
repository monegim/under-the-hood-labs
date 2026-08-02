# Lab 14 — Concept: BGP (Border Gateway Protocol)

## What's actually going on

BGP is a path-vector routing protocol that runs over a plain TCP session on
port 179 — that alone explains a lot of its behavior. Because it rides on
TCP, BGP itself doesn't have to worry about retransmission, ordering, or
fragmentation; it just has to worry about what messages to send once the
connection exists. The four message types are OPEN (capabilities and AS
number exchange, sent once at the start), KEEPALIVE (a periodic heartbeat
with no payload), UPDATE (the actual route advertisements/withdrawals), and
NOTIFICATION (an error, which is also how a peer tells you *why* it's tearing
the session down). A BGP session moves through a well-defined finite state
machine — Idle, Connect, Active, OpenSent, OpenConfirm, Established — and
that FSM is exactly why "stuck in Active" and "Established" are diagnostically
different situations: Active means the TCP connection attempt is being
retried and no OPEN has ever been successfully exchanged; Established means
OPEN and KEEPALIVE both completed and UPDATEs can now flow. This is precisely
the distinction Challenge A puts in front of you — an AS number mismatch
causes r2 to reject r1's OPEN message outright (the AS in the OPEN doesn't
match the configured `remote-as`), so the FSM never leaves the
Active/Connect/OpenSent churn and Established never happens.

The second, separate mechanism is what actually goes *into* an UPDATE. BGP
does not walk the kernel routing table and advertise everything in it by
default — a route only gets into a router's BGP table (and thus becomes
advertisable) if it's explicitly injected, either via `redistribute connected`
(and other `redistribute` variants) or a `network` statement matching an
existing route. This is why Challenge B produces a completely different
failure signature than Challenge A: the session stays Established (the
transport and FSM are fine), but r1 never had `1.1.1.1/32` in its BGP table in
the first place, so there was nothing for r2 to relay onward to r3.
"Session Established" tells you the control-plane pipe works. "My prefix is
being advertised" is a completely independent fact about what you fed into
that pipe.

The third mechanism worth understanding is why r3 learns `1.1.1.1/32` at all,
despite never peering with r1 directly. eBGP (peering between different
Autonomous Systems, as here) has no split-horizon rule the way IGPs or
iBGP do — an eBGP speaker readvertises routes learned from one eBGP peer to
another eBGP peer without restriction (that's the entire point of BGP being
the protocol that stitches the internet's ASes together). Every UPDATE
carries an AS_PATH attribute that gets a hop's own AS prepended each time it's
readvertised, which is both the loop-prevention mechanism (a router refuses a
route whose AS_PATH already contains its own AS) and the reason `show bgp
ipv4 unicast` on r3 shows an AS_PATH like "65001 65002" rather than
"65001" — you can literally read the propagation history off the attribute.

BGP's other path attributes (LOCAL_PREF, MED, ORIGIN, NEXT_HOP, community
strings) exist to influence best-path selection when multiple paths to the
same prefix exist — irrelevant in this three-router chain where there's only
ever one path, but it's the mechanism that makes BGP a *policy* routing
protocol rather than a shortest-path one: an ISP doesn't route based on hop
count, it routes based on business relationships encoded in these attributes.

## Where this shows up in the real world

BGP is the single protocol holding the internet together — every AS-to-AS
relationship (transit, peering) is a BGP session, and the entire global
routing table is the emergent result of every AS's local UPDATE decisions
propagating outward. Inside a data center, BGP shows up in "underlay" roles
too: Kubernetes CNIs like Calico (in BGP mode) run BGP sessions between nodes
instead of building overlay tunnels, top-of-rack switches in a Clos/leaf-spine
fabric typically peer via eBGP per rack, and anycast VIPs (the mechanism
behind most global DNS resolvers and CDN edge IPs) work by advertising the
same prefix from many places and letting BGP route each client to the
topologically nearest one.

A realistic scenario where the Established-vs-advertised distinction saves
hours: an on-call engineer sees "the BGP session to the new peer/rack is up"
in monitoring and assumes routing is fine, then spends the rest of the
incident chasing a phantom "the network is dropping packets" theory — when
the real problem is that nobody added the new subnet to a `network` statement
or redistribution policy, so it was never in BGP to begin with. Knowing to
check `show bgp ipv4 unicast` (or the peer's, via `show bgp neighbor <ip>
advertised-routes`) rather than stopping at `show bgp summary` is what
separates minutes from hours here.

## Go deeper

- **Book:** *Network Warrior* — Gary A. Donahue — the BGP chapters are written around exactly this kind of practical session/route troubleshooting rather than protocol theory.
- **Website/docs:** ipSpace.net — https://ipspace.net — Ivan Pepelnjak's material is unusually deep on BGP path attributes, route propagation, and datacenter BGP designs (like Calico's).
- **Website/docs:** FRRouting docs — https://docs.frrouting.org — official docs for the `bgpd`/`vtysh` syntax and `show bgp` commands used directly in this lab.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — Rene Molenaar's tutorials are strong specifically on the BGP FSM and AS_PATH/attribute fundamentals.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — search his channel for BGP walkthroughs, including FRR-based labs similar to this one.
