# Lab 33 — Concept: A Fixed Value vs. a Live Lookup

## What's actually going on

`SNAT` and `MASQUERADE` are both `iptables`/`nftables` NAT targets
that rewrite a packet's source address as it leaves through a given
interface - the difference is entirely in *where the replacement
address comes from*. `SNAT --to-source <ip>` takes a literal value,
specified once, at the moment the rule is written, and uses exactly
that value for every matching packet forever - the rule itself
contains no logic to reconsider whether that value is still correct.
`MASQUERADE` takes no address argument at all; it asks the kernel for
the outgoing interface's current primary address at the moment each
new connection is established, and uses whatever that answer is, every
time. One is a constant baked into the ruleset; the other is a live
lookup performed on demand. Both produce the exact same observable
behavior for as long as the interface's real address never changes -
which is precisely why the distinction is easy to treat as
implementation trivia right up until an address change turns it into
an outage.

That queried lookup does have a real cost `SNAT` avoids -
`MASQUERADE` has to determine the interface's current address on
every new connection rather than reusing a cached constant, and it
also has documented behavior tied to interface state changes (a
`MASQUERADE`-tracked connection's translation is torn down if the
interface goes down, specifically to avoid continuing to use an
address that might no longer be valid). Neither of these makes `SNAT`
the wrong default in general - on an interface with a genuinely fixed
address (a real static public IP, a permanent internal gateway
address), that's exactly the situation `SNAT` is built for, and the
"live lookup" `MASQUERADE` performs is solving a problem that doesn't
exist yet. The failure mode this lab is built around only exists
specifically where that assumption - "this address is fixed" - turns
out to have been temporarily true rather than permanently true.

The delay between an address changing and that change actually
causing a failure is its own separate mechanism, and it's not
specific to NAT at all: ARP resolution (IPv4) and Neighbor Discovery
(IPv6) are both cached, because re-resolving a link-layer address for
every single packet would be wasteful. A neighboring host that already
resolved an address to a MAC address keeps using that cached mapping -
correctly, from its own point of view - until the cache entry expires
or gets explicitly invalidated, regardless of whether the IP address
in question still means what it used to mean on the other end. This is
precisely why a stale-`SNAT` misconfiguration can be introduced,
appear to work fine, and only actually break something significantly
later: the misconfiguration and its consequence are decoupled by a
caching layer that has nothing to do with NAT, sitting on a
completely different host.

## Where this shows up in the real world

Cloud environments make this failure mode common rather than rare:
DHCP-leased addresses on VMs, elastic/floating IPs that move between
hosts during failover, NAT gateway addresses that rotate on
maintenance - any of these paired with a `SNAT` rule someone wrote
once, when the address happened to be stable, reproduces this exact
incident shape. It's a particularly disruptive one operationally
specifically because of the caching delay: the address change itself
often isn't the thing anyone is watching for, and by the time the
actual outage surfaces - hours or days later, triggered by an
unrelated cache expiry somewhere else on the network - the actual root
cause (a config decision made well before the visible failure) is easy
to rule out purely because of how long ago it happened.

## Go deeper

- **Man page:** `iptables-extensions(8)` — `man iptables-extensions` (see the `SNAT` and `MASQUERADE` targets) — the authoritative, side-by-side specification of both targets' exact behavior.
- **Website/docs:** Netfilter/iptables documentation, "NAT HOWTO" — https://www.netfilter.org/documentation/HOWTO/NAT-HOWTO.html — background on source vs. destination NAT and when each NAT target is intended to be used.
- **RFC 826** (ARP) — https://www.rfc-editor.org/rfc/rfc826 — the original ARP specification; most production stacks' caching/expiry behavior descends from this and later refinements.
- **Man page:** `arp(7)` / `ip-neighbour(8)` — `man ip-neighbour` — the `REACHABLE`/`STALE`/`DELAY`/`PROBE` neighbor states referenced in this lab's Challenge A, and how Linux actually manages ARP cache lifetime.
- **Website/docs:** AWS documentation, "Elastic IP addresses" — https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html — a widely-encountered real-world example of an address that looks static but can reassign during failover, the exact scenario this lab is modeling.
