# Lab 16 — Concept: Asymmetric Routing and Stateful Devices

## What's actually going on

Nothing in IP routing requires a reply to retrace the exact path its
request took. Every router makes its own independent forwarding decision
based purely on its own routing table and the packet's destination
address — there is no protocol-level concept of "the path this
connection is using" at Layer 3. `client`'s route to `server` and
`server`'s route back to `client` are two completely separate pieces of
configuration, each evaluated independently, each capable of pointing at
a different next-hop. This lab's Step 4 proves the direct consequence of
that: sending a request through `r1` and its reply through `r2` produces
zero problems for stateless traffic. Ping works. A stateless router just
does layer-3 forwarding — it doesn't care, and has no way to know,
whether it's seeing "the whole conversation" or just one direction of it.

A *stateful* device breaks this assumption on purpose, because that's the
entire point of it. A stateful firewall's connection-tracking table
(conntrack, in Linux's netfilter stack) exists specifically to answer "is
this packet part of a connection I already decided to allow, or is it
new?" — which requires having actually seen that connection begin. Netfilter's
conntrack maintains a state machine per tracked flow (`NEW` → `ESTABLISHED`
once both directions have been observed, plus `RELATED` for
protocol-helper-spawned secondary flows and `INVALID` for anything that
doesn't fit any tracked flow's expected sequence). A rule like `-m
conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT` is an extremely common,
reasonable-looking piece of firewall hygiene — "only let return traffic
through automatically, everything else needs its own explicit rule" — and
it's exactly this rule that turns harmless asymmetry into an outage. When
`r2` (which never saw the SYN) receives the SYN-ACK, conntrack has no
existing entry to match it against. `nf_conntrack_tcp_loose` controls what
happens next: in "loose" mode conntrack will charitably start tracking a
connection it only picked up mid-stream (useful for surviving a firewall
restart without dropping existing connections); with it disabled, a
mid-stream packet with no matching prior state is marked `INVALID` — it
matches neither `ESTABLISHED` nor `RELATED`, falls through to the default
policy, and is gone. ICMP echo request/reply, meanwhile, isn't
conversation-state-tracked the same way in this lab's ruleset — it's
explicitly accepted regardless of any connection state — which is exactly
why it keeps working through the entire failure and is such a reliable
(and misleading) "the network is fine" signal during this specific class
of incident.

Challenge B's mirror-image scenario exists to head off a subtle
misdiagnosis: *where* in a multi-hop asymmetric path a stateful rule
lives determines *which packet* of the handshake it kills. A stateful
rule on the box that only ever sees return traffic drops the reply after
the request already reached the destination. The identical rule on the
box that sees the *forward* traffic drops the request outright, before
the destination ever hears about it — routing asymmetry is present in
both cases, but only matters mechanically to the first one, because the
second connection never survives long enough for the return leg to be
relevant at all. Reading captures at every hop, in both directions, is
the only way to know which of these two very differently-shaped failures
you're looking at.

## Where this shows up in the real world

- Any network with two active-active edge routers/firewalls doing ECMP or
  policy-based routing without synchronized connection state is a latent
  version of this lab — traffic engineering or a route change that used
  to send both directions through the same box can silently start
  splitting them, with zero alarms until the first stateful-anything
  (a NAT gateway, an IDS/IPS doing flow reassembly, a firewall) notices.
- Multi-homed data centers and cloud VPCs with more than one internet
  gateway/NAT gateway per subnet hit this constantly — a route table
  change on one side without a matching change on the other reintroduces
  asymmetry that was previously masked by both paths happening to agree.
- **Diagnosis scenario:** "customers can ping our new region but their
  connections time out, and nothing changed on our firewall" is this
  lab's exact shape in production — the firewall config is often
  genuinely unchanged; what changed is a routing decision somewhere else
  in the path that used to keep both directions on the same device and
  no longer does.

## Go deeper
- **Website/docs:** man7.org, `conntrack(8)` —
  https://man7.org/linux/man-pages/man8/conntrack.8.html — the canonical
  reference for inspecting and understanding Linux connection-tracking
  state, including the `INVALID`/`ESTABLISHED`/`RELATED` states this lab
  hinges on.
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — the routing-table/longest-prefix-match
  chapters explain why forward and return paths are computed completely
  independently by design.
- **Website/docs:** Cloudflare's engineering blog —
  https://blog.cloudflare.com — has published deep-dives touching on
  asymmetric routing and stateful-inspection edge cases at scale.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on routing table lookups and stateful firewall
  behavior.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal —
  practical routing and firewall walkthroughs, including multi-path
  scenarios.
