# Lab 15 — Concept: GRE Tunnels

## What's actually going on

GRE (Generic Routing Encapsulation, IP protocol number 47) does exactly one
job: take an arbitrary payload packet, wrap it in a small GRE header, wrap
*that* in a new outer IP header, and hand it to the kernel's normal routing
path like any other packet. The GRE header itself is minimal — a few flag
bits, a protocol-type field (so the far end knows what's inside, usually
0x0800 for IPv4), and optionally a checksum, key, and sequence number if
those flags are set — which in this lab's config is 4 bytes. Combined with
the 20-byte outer IPv4 header, that's the 24 bytes of overhead you saw
directly when `ip link show gre1` reported MTU 1476 instead of 1500: the
kernel computed "underlay MTU minus GRE encapsulation overhead" at tunnel
creation time and set the tunnel interface's MTU accordingly. This overhead
accounting is also the setup for lab 18 — it's computed once, not
continuously, which is exactly what makes it go stale later.

The reason `ip tunnel add ... remote ... local ...` is enough to make a fully
functional interface, with no handshake step, is that GRE is fundamentally
stateless — there's no session establishment, no capability negotiation, no
keepalive by default (RFC 1701 defines an optional keepalive extension, but
Linux's default `ip tunnel` GRE doesn't use it). The tunnel interface is
really just a rule: "anything routed into this device, wrap in a GRE+IP
header addressed to `remote`, and send." That's why Challenge A is such a
sharp lesson — pointing `remote` at a nonexistent address doesn't produce any
error, timeout, or interface state change. The interface stays administratively
and operationally "up" (its `UNKNOWN` operstate for tunnel devices reflects
that the kernel doesn't have a real carrier-detection concept for a virtual
device like this) and it dutifully encapsulates and ships every packet toward
an address nothing owns. Nothing comes back, nothing complains — the
packets are gone. Compare that to Challenge B, where deleting the return
route produces an instant, local "network unreachable": that's the routing
table doing its job (failing a lookup immediately, before anything is even
built or sent), versus GRE encapsulation succeeding perfectly at a task with
nobody listening on the other end. Fast/loud vs. silent/slow is the signature
that tells you which layer actually broke.

It's worth being precise about what GRE is *not*: it provides no
confidentiality, no integrity checking, no authentication (the optional key
field is for demultiplexing multiple tunnels between the same endpoints, not
security) — anyone who can see the underlay traffic can see the encapsulated
payload in full. That's exactly why GRE is so often paired with IPsec in
production (lab 17): GRE gets you a routable, protocol-agnostic tunnel
interface that can carry things IPsec alone struggles with (multicast, IGP
routing protocol traffic, non-IP payloads), and IPsec wraps that in actual
encryption and authentication. Conceptually, GRE is also the direct ancestor
of every later overlay tunneling protocol you'll touch — VXLAN (lab 16) is
the same "encapsulate and route through the underlay" idea, just swapping
GRE's minimal header for a UDP/VXLAN header specifically so ECMP hashing on
the underlay works cleanly.

## Where this shows up in the real world

GRE is still the transport underneath a lot of legacy site-to-site VPN
configs, is the classic way to run a routing protocol (OSPF, BGP) across a
provider network that won't carry it natively, and shows up inside cloud
networking as one of the building blocks a VPC's virtual network stitches
together underneath its abstractions. The single most common production GRE
incident is exactly Challenge A's shape: someone fat-fingers or automates a
`remote` address change (a DR failover pointed at the wrong new IP, a config
management template with a stale variable), the tunnel interface reports
itself as perfectly healthy the entire time, and the only way to actually
diagnose it is a capture on both ends proving traffic leaves one side and
never arrives at the other — interface state alone will actively mislead you.

## Go deeper

- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard Stevens (updated by Kevin Fall) — the encapsulation/header-format chapters give you the same mental model GRE relies on, applied more broadly across IP-in-IP style tunneling.
- **Book:** *Computer Networking: A Top-Down Approach* — Jim Kurose & Keith Ross — solid grounding in the layered encapsulation model that explains why "wrap a packet in another packet" works at all.
- **Website/docs:** containerlab docs — https://containerlab.dev — the tool used to build this topology; useful if you want to extend the lab with more tunnel endpoints.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck — search his channel for GRE/tunneling and VPN videos; accessible walkthroughs of the same concepts.
