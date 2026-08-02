# Lab 12 — Concept: Where tcpdump Actually Sits, and Why "Captured" Isn't "Delivered"

## What's actually going on

`tcpdump`/`tshark` work by attaching to a packet socket (`AF_PACKET` on
Linux) that gets handed a copy of frames as they pass through a network
interface, using the in-kernel **BPF (Berkeley Packet Filter)** to decide,
cheaply, which frames to hand up to userspace at all. That BPF filter is
what a **capture filter** compiles to (`-f` on tshark, or the trailing
expression on tcpdump, e.g. `tcp port 8080 and tcp[tcpflags] & tcp-syn !=
0`) — it runs at capture time, inside the kernel, before a packet is even
copied to userspace, which is why capture filter syntax is comparatively
primitive (raw byte offsets and bitmasks like `tcp[tcpflags]`) rather than
rich field names. A **display filter** (`-Y` on tshark, Wireshark's
familiar `tcp.flags.syn==1` syntax) instead runs entirely in userspace,
after full protocol dissection, against packets that were already
captured — which is why it can express much richer, protocol-aware
queries but can't reduce what actually gets captured. Mixing up `-f` and
`-Y` on the same tool (they're not interchangeable, and tcpdump doesn't
even have display-filter syntax at all) is one of the most common
practical mistakes with this tooling.

The TCP three-way handshake you read in Step 2 — `Flags [S]` (SYN),
`Flags [S.]` (SYN-ACK), `Flags [.]` (ACK) — is the connection-establishment
state machine at the wire level: SYN carries an initial sequence number,
SYN-ACK acknowledges it and carries the responder's own initial sequence
number, and the final ACK completes it before either side sends
application data. Once you can read this reliably, you can tell apart the
handful of genuinely different "doesn't connect" failure signatures that
all look identical from a single vantage point: nothing listening produces
an immediate kernel-generated `RST-ACK` (Step 4) because the kernel itself,
with no socket bound to that port, answers a SYN with a reset; a silently
dropped SYN produces *no* reply at all, just the sender's own exponential
SYN retransmission backoff (Linux's default pattern is roughly 1s, 2s, 4s
before giving up); and an actively rejected connection produces an
immediate RST, but potentially forged by something other than the real
destination.

This is exactly the distinction the two challenges are built to expose.
In Challenge A, the SYN genuinely reaches the server's NIC — a capture on
the server confirms this — but the server's own host firewall (`iptables
INPUT ... DROP`) discards it before the kernel ever hands it to the
listening socket. `tcpdump` captures at a point in the kernel's receive
path that sits largely upstream of netfilter's filtering decision, so "the
packet showed up in a capture on this host" and "this host's application
received it" are two different, independently verifiable facts — and only
checking the firewall's own rule counters (`iptables -L -v`) proves which
one actually happened. In Challenge B, the client sees an immediate RST
that looks exactly like "nothing listening," source address correctly
showing the server's IP — but a capture on the server itself shows *nothing
ever arrived there at all*. The RST was crafted by `r1`'s `REJECT
--reject-with tcp-reset` rule in its `FORWARD` chain, spoofing what looks
like a reply from the real destination. A single-vantage-point capture
(client only) would have led to the wrong conclusion — "the server
refused it" — when the actual answer is "a device in the middle answered
on the server's behalf."

## Where this shows up in the real world

"It doesn't connect" is one of the most common tickets in any networked
system, and the fast, provable diagnosis always comes from capturing at
more than one point along the path and comparing what each side actually
saw — client, any middleboxes/firewalls/load balancers, and the real
destination — rather than reasoning from a single capture and guessing.
Cloud security groups, on-host firewalls, and NAT/load-balancer devices
can all inject RSTs or silently drop packets in ways that are
indistinguishable from each other at a single vantage point; the
difference between "I think it's the firewall" and "I can prove exactly
which hop drops it" is entirely a matter of knowing to capture at both
ends (and ideally the middle) before drawing a conclusion.

## Go deeper

- **Book:** *Practical Packet Analysis* — Chris Sanders — a Wireshark-focused, example-driven guide to exactly this kind of multi-point capture diagnosis.
- **Book:** *TCP/IP Illustrated, Volume 1* — W. Richard Stevens (updated by Kevin Fall) — the canonical reference for the TCP handshake and flag semantics read in this lab.
- **Website:** Wireshark wiki — https://wiki.wireshark.org — capture filter vs display filter syntax references and protocol dissection guides.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man8/tcpdump.8.html — the canonical tcpdump reference, including BPF capture filter syntax.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has several practical tcpdump/Wireshark troubleshooting walkthroughs.
