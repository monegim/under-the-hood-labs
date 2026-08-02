# Lab 11 — Concept: PMTUD, the DF Bit, and Why Its Feedback Loop Can Silently Break

## What's actually going on

Every IP link has a maximum transmission unit — the largest frame it can
carry — and a path between two hosts is only as big as its smallest-MTU
hop. Path MTU Discovery (PMTUD) is the mechanism that lets a sender figure
out that ceiling *without* the network silently fragmenting packets for
it. The sender sets the **DF (Don't Fragment) bit** in the IP header; when
a router along the path needs to forward that packet onto a link whose
MTU is smaller than the packet, and DF is set, the router is required to
drop the packet and send back an ICMP "Destination Unreachable,
Fragmentation Needed" message (type 3, code 4) that includes the actual
MTU of the link that couldn't take it. The sender receives that ICMP
message, learns the real ceiling, and resends at (or below) that size —
this is exactly what you watched happen cleanly in Step 4: a 1449-byte
DF-set ping got an explicit `Frag needed and DF set (mtu = 1476)` back
from `ping` itself, in real time.

A GRE tunnel's MTU is not arbitrary — it's the underlay MTU minus GRE's
own encapsulation overhead: a 20-byte outer IPv4 header plus a 4-byte GRE
header, 24 bytes total, which is exactly why a 1500-byte underlay produces
a 1476-byte `gre1` interface. The kernel computes this once, at tunnel
creation time, based on the underlay's MTU as it existed *at that moment*
— it is not a live, continuously recalculated value. That single fact
drives Challenge B: shrinking the physical underlay's MTU afterward (a
provider migrating you onto a lower-MTU transit link is a completely
realistic real-world trigger) does not retroactively recompute `gre1`'s
advertised MTU. The tunnel interface keeps telling the routing stack "I
can carry 1476 bytes" when the real ceiling underneath it just dropped to
1376 — nothing in the kernel watches the underlying interface and fixes
this up automatically, on either end, ever.

The entire PMTUD mechanism depends on one thing: that the ICMP
fragmentation-needed message can actually get back to the original
sender. Challenge A breaks exactly that assumption. Blocking ICMP
"fragmentation-needed" on r1's `OUTPUT` chain doesn't change r1's internal
behavior at all — it still correctly refuses to forward the oversized
DF-set packet into the tunnel, and it still generates the ICMP message
telling the sender what's wrong. But that reply is discarded by the
firewall before it ever leaves r1. hostA never learns anything is wrong;
it just keeps retransmitting the same oversized packet, which keeps
silently vanishing, forever — indistinguishable, from the client's side,
from a network that's simply dropping large packets for no discoverable
reason. This is the textbook "PMTUD black hole," and it's specifically
caused by treating ICMP as generically "unnecessary" traffic to filter,
without realizing one specific message type is load-bearing for TCP/UDP
sessions that otherwise work fine at small sizes.

## Where this shows up in the real world

"Small packets work, large packets just vanish or hang" is one of the most
common and most misdiagnosed production networking symptoms, because it
looks intermittent and size-dependent rather than obviously broken — SSH
sessions that work until you `cat` a big file, HTTPS connections that hang
on large responses but ping fine, VPN tunnels that are "up" but unusable.
It shows up behind GRE/VXLAN/IPsec tunnels, cloud provider overlay
networks, MPLS transit, and DSL/PPPoE links (which typically have MTU
below 1500 due to PPPoE's own 8-byte overhead) — anywhere a hop in the
middle has a lower MTU than the endpoints assume. A large fraction of
"hardened" firewalls block ICMP by default as a blanket security measure,
without carving out an exception for type 3/code 4, which is precisely
what silently breaks PMTUD for every tunnel or VPN sitting behind them.
Knowing to check both the ICMP path (is fragmentation-needed actually
getting through) and the tunnel's own stale MTU (does it match current
underlay reality) is what separates a two-minute fix from hours of staring
at TCP retransmits.

## Go deeper

- **Book:** *TCP/IP Illustrated, Volume 1* — W. Richard Stevens (updated by Kevin Fall) — the canonical deep-dive on PMTUD mechanics and the DF bit.
- **Book:** *Computer Networking: A Top-Down Approach* — Jim Kurose & Keith Ross — solid foundational treatment of fragmentation and MTU at the network layer.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/icmp.7.html — plus the `ip(7)`/tunneling docs for how Linux computes and exposes tunnel MTU.
- **Website:** Wireshark wiki — https://wiki.wireshark.org — good reference material for recognizing ICMP fragmentation-needed and DF-bit behavior in captures.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck — accessible explainer content on MTU/PMTUD problems in real networks.
