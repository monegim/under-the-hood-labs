# Level 2 — Networking

33 labs on the mechanisms every SRE ends up debugging with `tcpdump`
in one hand and a routing table in the other: build a bridge, a VLAN,
a tunnel, a BGP session, or a NAT gateway by hand first, then break it
in a way that's specific and diagnosable, not a raw "the network is
down." A dedicated `iptables`/`ip6tables`/policy-routing thread (rule
order, persistence across reboot, the IPv4-only-firewall/IPv6-wide-open
gap, rate limiting, the `mangle` table) sits alongside the core L2-L7
mechanisms, plus a deeper pass on load balancing, TCP flow-control
analysis, and NAT internals.

Each lab follows the same format as every other level in this repo:
`README.md` (objective, why it matters, a numbered build, then 2
"break it" challenges with no answers given), `solution.md` (a
postmortem-style diagnosis per challenge), `CONCEPTS.md` (the
underlying mechanism explained properly, plus curated resources to go
deeper), `setup.sh` (builds the incident), and `check.sh`/`reset.sh`
(verify it's fixed / rebuild it from scratch). Most labs (03-20, 23,
25) build their topology with [containerlab](https://containerlab.dev)
+ FRR; the rest build directly with Linux network namespaces and
`iptables` on a plain VM, and one (31) uses `docker compose` for a
real HAProxy + backend stack.

## Labs

1. [`01-linux-bridge`](01-linux-bridge) — build a Linux bridge (a
   virtual switch) by hand and watch it forward traffic with real MAC
   learning.
2. [`02-vlans`](02-vlans) — two VLANs sharing one bridge, proven
   isolated, then a trunk port carrying real 802.1q tags.
3. [`03-static-routing`](03-static-routing) — two hosts wired through
   two FRR routers with static routes only, and exactly what breaks
   when a return route is missing.
4. [`04-nat`](04-nat) — MASQUERADE for outbound NAT and DNAT for an
   inbound port-forward, the two primitives behind every home router
   and cloud NAT gateway.
5. [`05-firewalls`](05-firewalls) — a default-DROP `FORWARD` policy,
   and two realistic ways a "correct-looking" firewall config still
   breaks connections.
6. [`06-ospf`](06-ospf) — OSPF across three routers, routes installed
   automatically, then one broken adjacency diagnosed from scratch.
7. [`07-bgp`](07-bgp) — three FRR routers in three ASes, eBGP peering,
   proving routes are actually learned via BGP, not just that the
   session is up.
8. [`08-gre-tunnels`](08-gre-tunnels) — a GRE tunnel over an underlay,
   routing two overlay LANs through it — the same mechanism behind
   site-to-site VPNs.
9. [`09-vxlan`](09-vxlan) — a VXLAN overlay between two VTEPs, the
   exact mechanism behind Kubernetes CNI overlay backends.
10. [`10-ipsec`](10-ipsec) — a site-to-site IPsec tunnel with
    strongSwan, with the encryption actually confirmed on the wire.
11. [`11-mtu-issues`](11-mtu-issues) — Path MTU Discovery working
    correctly, then the classic outage where it silently stops,
    because something drops the ICMP message PMTUD depends on.
12. [`12-packet-captures`](12-packet-captures) — `tcpdump`/`tshark`
    fundamentals: capture vs. display filters, reading a handshake,
    and three different "connection doesn't work" signatures.
13. [`13-broken-dns`](13-broken-dns) — a two-hop DNS path, and the two
    failures that get confused with each other in almost every
    incident: unreachable resolver vs. a reachable resolver answering
    badly.
14. [`14-tcp-retransmissions`](14-tcp-retransmissions) — retransmits
    from real packet loss vs. retransmits from an unresponsive
    receiver — identical symptom, told apart by capturing both ends.
15. [`15-syn-flood`](15-syn-flood) — a spoofed-source SYN flood
    filling the half-open queue, fixed the way production actually
    fixes it: SYN cookies, not a bigger queue.
16. [`16-asymmetric-routing`](16-asymmetric-routing) — forward and
    return paths forced onto two different routers, breaking a
    stateful firewall's TCP tracking while ICMP keeps working the
    whole time.
17. [`17-conntrack-exhaustion`](17-conntrack-exhaustion) — a full
    connection-tracking table silently dropping new connections, from
    both a traffic burst and connections that were never closed.
18. [`18-dhcp-failure`](18-dhcp-failure) — a real `dhclient` lease,
    then the two most common ways a host ends up with no usable IP: an
    exhausted pool and an unrenewable expired lease.
19. [`19-arp-issues`](19-arp-issues) — gratuitous ARP moving a virtual
    IP correctly, then two ways that safety mechanism fails: never
    firing, and the old owner never letting go.
20. [`20-nat-port-exhaustion`](20-nat-port-exhaustion) — a MASQUERADE
    router driven past its ephemeral port pool, and the only two
    fixes that actually work.
21. [`21-stp-loop`](21-stp-loop) — a genuine physical L2 loop between
    two bridges, what it does to broadcast traffic unprotected, and
    Spanning Tree blocking exactly the right port.
22. [`22-lacp-bonding-failure`](22-lacp-bonding-failure) — a real
    peer-to-peer LACP bond, and learning to read
    `/proc/net/bonding/bond0` well enough to tell degraded from down
    from connected-to-the-wrong-thing.
23. [`23-bgp-route-flapping`](23-bgp-route-flapping) — an unstable
    eBGP link propagating repeated withdrawals to a non-adjacent
    router, contained with route dampening — and dampening's real cost.
24. [`24-ipv6-dual-stack-issues`](24-ipv6-dual-stack-issues) — a
    silently half-broken IPv6 path to one port, and why that's worse
    for users than IPv6 being fully absent.
25. [`25-tls-handshake-failure`](25-tls-handshake-failure) — a
    protocol-version mismatch, a cipher-suite mismatch, and a
    successful handshake serving the wrong certificate — told apart
    from `openssl s_client` alone.
26. [`26-iptables-rule-order-chains`](26-iptables-rule-order-chains) —
    a correct allow-list rule inside a custom chain that never fires,
    because a catch-all rule earlier in the calling chain shadows it.
27. [`27-iptables-rules-lost-on-reboot`](27-iptables-rules-lost-on-reboot) —
    a working firewall rule that vanishes on reboot, fixed so it
    actually persists instead of being reapplied by hand every time.
28. [`28-iptables-ipv6-gap`](28-iptables-ipv6-gap) — a port locked down
    with `iptables` that's still wide open over IPv6, because
    `ip6tables` was never touched.
29. [`29-iptables-rate-limiting`](29-iptables-rate-limiting) — a naive
    `-m limit` rule sharing its budget across every client, so one
    noisy source can still lock out everyone else.
30. [`30-mangle-policy-routing`](30-mangle-policy-routing) — a
    `mangle` `MARK` that fires exactly as configured and still changes
    nothing, because marking a packet and routing by that mark are two
    separate, independently-configured steps.
31. [`31-load-balancer-health-check-blind-spot`](31-load-balancer-health-check-blind-spot) —
    a backend failing real traffic while HAProxy's own health check —
    and its own dashboard — insist it's perfectly healthy.
32. [`32-tcp-zero-window-analysis`](32-tcp-zero-window-analysis) — a
    receiver that can't keep up, diagnosed with `tshark`'s built-in
    TCP analysis instead of scrolling raw packets for a field you'd
    have to already know to look for.
33. [`33-snat-vs-masquerade`](33-snat-vs-masquerade) — static `SNAT`
    hardcoded to a gateway address that later changes, silently
    breaking every outbound connection, vs. `MASQUERADE`'s live lookup
    that just keeps working.

## Prerequisites

- A Linux VM, `sudo` access, `iproute2`, `iptables`/`ip6tables`,
  `netcat-openbsd`, `tcpdump`, `tshark`
- Docker + [containerlab](https://containerlab.dev) + FRR (labs
  03-20, 23, 25)
- Docker + the `docker compose` plugin (lab 31)
- `strongSwan` (lab 10), `dhclient`/`isc-dhcp-server` (lab 18),
  `openssl` (lab 25), `python3` (labs 30-33) — each lab's own README
  states exactly what it needs

Check first:
```bash
docker version
sudo ip netns list >/dev/null 2>&1 && echo "netns OK"
which iptables ip6tables tcpdump tshark
```
