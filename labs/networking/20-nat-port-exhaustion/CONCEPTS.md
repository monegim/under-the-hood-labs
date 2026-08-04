# Lab 20 — Concept: SNAT Port Exhaustion

## What's actually going on

Every connection MASQUERADE/SNAT translates needs a unique 5-tuple on the
way out: (protocol, external IP, external port, remote IP, remote port).
The external IP is usually fixed and the remote IP:port is whatever the
internal host is talking to, so the *only* variable netfilter has to work
with to keep two different internal hosts' flows distinguishable is the
external port it assigns each one. If host A and host B both happen to open
a connection from the same-looking flow to the same remote service, NAT
has to give them different external ports — there's no other field left to
disambiguate the return traffic. That's why the pool of available external
ports, not the number of internal hosts or the size of the conntrack table,
is the actual ceiling on simultaneous outbound connections through one NAT
IP. On a single IP that ceiling is fixed by the protocol itself: 65,535
possible ports, minus the 0–1023 well-known/reserved range, leaves roughly
64,511 usable — and that number does not move no matter how you tune
`sysctl` or the conntrack table size.

This is worth explicitly separating from conntrack *table* exhaustion,
which is a different lab in this series' territory. Conntrack table
exhaustion is about `nf_conntrack_max` — the kernel simply refuses to track
any more flows, of any kind, once the table is full, regardless of ports.
SNAT port exhaustion is about one specific IP's port pool running out,
which can happen with a conntrack table that has thousands of free slots
left. Both produce "new connections fail, old ones keep working," but the
fix and the diagnostic commands are completely different — `conntrack -L`
plus `iptables -t nat -L POSTROUTING -n -v` for port exhaustion,
`conntrack -S` / `sysctl net.netfilter.nf_conntrack_count` and
`nf_conntrack_max` for table exhaustion. If you've seen the other lab in
this series, don't let the similar symptom fool you into applying that
lab's fix here.

The failure signature is also worth understanding on its own: when
`--to-ports`/MASQUERADE has no free port left to hand out, there is no NAT
session to build for that SYN, so netfilter just drops the packet — there
is no RST, no ICMP unreachable, nothing. From the client's point of view
this is indistinguishable from a black-holed route or a silently dropped
firewall rule; it just has to wait out its own connect timeout before
giving up. This is exactly why the challenges in this lab feel like "the
network is being flaky" rather than "there's an explicit block" — because
structurally, there isn't one; there's an absence of available state.

Doubling the port pool by adding a second public IP (Step 7) works because
each IP gets its *own* independent port space — `.1:40000-40004` and
`.21:40000-40004` are two completely separate sets of 5-tuples, even though
the port numbers look identical on paper. This is precisely how carrier
NAT operators and cloud NAT gateways scale: they don't invent more ports
per IP, they add IPs and spread connections across them. It's also why
"reduce concurrent connections" is a legitimate fix and not a cop-out —
if the demand for simultaneous flows genuinely exceeds what any reasonable
number of IPs can support, no NAT topology change fixes that; the
connection count itself has to come down.

## Where this shows up in the real world

- **AWS/GCP NAT Gateways** allocate a fixed, documented number of ports per
  unique destination per client — a common production incident is "our
  app works fine most of the time but bursts of connections to one
  downstream service start timing out," which traces directly back to this
  exact port-pool ceiling, not to the NAT gateway being "down."
- **CGNAT (carrier-grade NAT)** ISPs put hundreds of residential customers
  behind one public IP; heavy simultaneous-connection applications
  (P2P clients, some game consoles, aggressive web apps opening many
  parallel requests) are the traffic pattern most likely to exhaust their
  slice of that IP's port pool first, well before the ISP's IP itself has
  any bandwidth problem.
- **Diagnosis scenario:** a Kubernetes cluster egresses all outbound
  traffic through one NAT gateway node, and under load, connections from
  pods to one specific external API start failing intermittently while
  everything else (and the API itself, confirmed via its own health
  dashboard) looks fine. `conntrack -L` filtered to that destination,
  counted and compared against the gateway's configured port range, is the
  fast path to "we're out of ports to that one destination," versus hours
  spent suspecting the external API or the pod's own networking.

## Go deeper
- **Book:** *Computer Networking: A Top-Down Approach* — Jim Kurose & Keith Ross — covers port-based multiplexing and NAT's interaction with the transport layer, the foundation this lab's ceiling comes from.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — clear structured material on NAT/PAT (port address translation) fundamentals that maps directly onto why ports, not addresses, are the scarce resource here.
- **Website/docs:** ipSpace.net — https://ipspace.net — Ivan Pepelnjak's datacenter networking material covers NAT scaling patterns (including the multi-IP approach used in Step 7) in real deployment contexts.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck — accessible explanations of CGNAT and consumer-facing NAT limitations, good real-world framing for why this ceiling matters outside the lab.
