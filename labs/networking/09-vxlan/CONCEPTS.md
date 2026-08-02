# Lab 9 — Concept: VXLAN

## What's actually going on

VXLAN's job is to make L2 frames routable across an L3 underlay, so two
hosts that have no business being on the same broadcast domain (different
racks, different physical segments, potentially different data centers) can
behave as if they are. It does this by wrapping an entire Ethernet frame
(source/dest MAC, the works) inside a VXLAN header, inside a UDP datagram,
inside an outer IP packet — MAC-in-UDP-in-IP. The VXLAN header itself is
small (8 bytes) and its most important field is the 24-bit VNI (VXLAN Network
Identifier) — this is what gives VXLAN room for roughly 16 million distinct
logical L2 segments, versus the 4096 ceiling of a classic 802.1Q VLAN tag,
which is the entire reason VXLAN exists: multi-tenant clouds and large
data centers ran out of VLAN IDs. The devices that do the encapsulating and
decapsulating are called VTEPs (VXLAN Tunnel Endpoints) — in this lab, r1 and
r2 are acting as VTEPs, each wrapping/unwrapping frames on behalf of the host
behind it. The choice of UDP (destination port 4789, IANA-assigned) over
something like raw GRE is deliberate: the kernel varies the UDP *source*
port per-flow (typically a hash of the inner frame's headers), which gives
underlay ECMP/LACP hashing something to key off of — plain GRE-in-IP tends to
hash all traffic between the same two endpoints onto one path, VXLAN's
varying source port spreads it across multiple underlay paths.

The mechanism this lab deliberately exposes is BUM handling — how VXLAN
deals with Broadcast, Unknown-unicast, and Multicast traffic, which every L2
segment needs (ARP requests are broadcast, for instance) but which has no
natural "route to a specific place" answer in an L3 underlay. There are two
real approaches: multicast-mode VXLAN (the VTEP joins a multicast group and
BUM traffic gets replicated by the underlay's multicast tree) or
static/unicast-mode with explicit FDB (Forwarding Database) entries — this
lab uses the latter, which is also what flannel's `vxlan` backend actually
does in production. The all-zeros MAC FDB entry (`bridge fdb append
00:00:00:00:00:00 dev vxlan10 dst <peer>`) is the wildcard: "anything without
a specific learned MAC entry — including every ARP broadcast — gets unicast
to this VTEP." Without `remote` set on the VXLAN device and without that
wildcard entry, the kernel has no rule at all for where to send BUM traffic,
which is exactly Challenge B: delete the wildcard FDB entry and the frame
dies locally on r1 before it ever reaches the underlay, because there's
nothing telling the kernel where flooded traffic should go.

Challenge A shows the other place a VXLAN overlay can silently break: after
the frame is correctly encapsulated and has visibly crossed the underlay
(visible in a capture on the physical interface, right UDP port and
destination IP), the receiving VTEP's kernel still has to match the VNI in
the VXLAN header against a *local* VXLAN device configured with that same
VNI in order to decapsulate it. A VNI mismatch means the frame is dropped
*after* the physical NIC has already received it — which is precisely why it
shows up in a capture on the wire but never shows up as decapsulated traffic
or in the vxlan device's RX counters. This is the core diagnostic lesson of
the whole lab: "I can see it crossing the underlay" and "it made it into the
overlay" are two separate, independently-checkable facts, and the gap
between them is exactly where VNI mismatches and stale FDB state hide.

## Where this shows up in the real world

VXLAN is the overlay mechanism behind flannel's `vxlan` backend, Calico's
VXLAN mode, Open vSwitch-based SDN, and most cloud/data-center overlay
networking designs (frequently paired with BGP EVPN as the control plane that
distributes MAC/IP-to-VTEP mappings automatically, instead of the static FDB
this lab builds by hand). The exact bug class this lab reproduces — a
node restarts or a daemon crashes before it reconciles its FDB/neighbor
state, and that one node's overlay silently stops working while everything
else looks fine — is a genuinely common CNI-layer incident. Knowing to
compare a physical-interface capture against the VXLAN device's own RX
counters (not just "does ping work") is what turns "the overlay network is
broken" into "node X's vxlan0 has a stale FDB entry" in minutes instead of
escalating a networking ticket that turns out to be a controller reconciliation bug.

## Go deeper

- **Website/docs:** ipSpace.net — https://ipspace.net — Ivan Pepelnjak has extensive deep-dive material specifically on VXLAN, EVPN, and overlay network design, more thorough than most vendor docs.
- **Book:** *Computer Networking: A Top-Down Approach* — Jim Kurose & Keith Ross — for the layered/encapsulation fundamentals that make sense of "Ethernet frame inside UDP inside IP."
- **Website/docs:** containerlab docs — https://containerlab.dev — the lab tooling; useful for extending this topology to a third VTEP or a BGP EVPN control plane.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — search his channel for VXLAN and data-center overlay content.
