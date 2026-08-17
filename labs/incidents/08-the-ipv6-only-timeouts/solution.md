# Incident 08 — Solution

## Root cause

`backend` is reachable over both IPv4 and IPv6 on the shared Docker
network - Docker's embedded DNS returns both an AAAA and an A record
for a plain lookup of `backend`, IPv6 first. `frontend`'s HTTP client
(`requests`, and the standard-library socket code underneath it) has
no Happy Eyeballs behavior: it resolves the hostname, tries the
*first* address returned, and only moves on to the next one if that
attempt fails or times out - it doesn't race both in parallel. That's
not a bug in `requests`; it's the default behavior of a large share of
real HTTP client libraries, in most languages, unless something
explicitly implements RFC 8305.

An `ip6tables` rule on `backend` `DROP`s incoming TCP to its app port
(8080) over IPv6 only - not `REJECT`, `DROP`. `REJECT` sends back an
immediate RST, which a client interprets as "connection refused" and
moves on instantly. `DROP` sends back nothing at all, so the client's
SYN is simply never acknowledged, and the connection attempt sits
there until *the client's own timeout* gives up on it - `frontend`
sets a `timeout=5` on its `requests.post()` call, so every single
`/checkout` call spends 5 seconds hung on the (silently dropped) IPv6
attempt before finally trying IPv4, which succeeds in a few
milliseconds. Every request succeeds. Every request also takes just
over 5 seconds, because the IPv4 fallback isn't the fast path here -
it's what happens *after* the slow path finally gives up.

## Why it happened

Nothing about the IPv6 path being *reachable* changed - `ping6` still
gets a response, because `ip6tables` only touches the one rule that
was added, for the one port that was targeted. That's precisely what
makes this worse than IPv6 being absent entirely: a client with zero
Happy Eyeballs behavior pays the full cost of a hung connection
attempt on *every single request*, forever, because the broken address
never stops being offered as a candidate - DNS has no idea one of the
two addresses it's handing out leads to a dead end at the TCP layer,
and nothing about a working `ping6` would ever tell you otherwise.

## Why the obvious fixes don't work

- **Restarting `frontend` or `backend`**: does nothing - the
  `ip6tables` rule lives on `backend` and isn't touched by either
  container restarting; the exact same DROP is waiting for the next
  connection attempt either way.
- **Checking `backend`'s CPU/memory/logs**: all unremarkable, because
  `backend` isn't slow or struggling at all - it never even sees the
  IPv6 connection attempt. There's nothing in its own logs to find,
  because a dropped SYN never reaches the application layer.
- **Scaling `frontend` to more replicas**: doesn't help - every
  replica resolves the same DNS records, gets IPv6 first, and pays the
  identical 5-second tax on every request, independently.
- **Confirming "IPv6 works" via `ping6`**: this is the trap the whole
  incident is built around. `ping6`/ICMP and a TCP connection to a
  specific port are two entirely different tests, handled by two
  entirely different code paths (kernel-level ICMP echo vs. a
  userspace socket accepting on a specific port) - one working says
  nothing whatsoever about the other.

## The investigation

Confirm the symptom directly:
```bash
curl -s -w '\ntotal: %{time_total}s\n' -X POST http://localhost:8090/checkout
```
A `total` sitting just over 5 seconds, every single time - not
occasional, not random, remarkably consistent.

Check basic IPv6 reachability from `frontend`:
```bash
docker exec incident08-frontend ping -c2 -W2 fd08::10
```
Instant replies. By this test alone, IPv6 looks completely fine.

Now test the actual port the application uses, over each address
family separately:
```bash
docker exec incident08-frontend curl -s -4 -o /dev/null -w 'IPv4 total: %{time_total}s\n' --max-time 8 -X POST http://172.30.0.10:8080/checkout
docker exec incident08-frontend curl -s -6 -o /dev/null -w 'IPv6 total: %{time_total}s\n' --max-time 8 -X POST "http://[fd08::10]:8080/checkout"
```
IPv4 returns in a few milliseconds. IPv6 hangs for the full
`--max-time`, then fails with a timeout - a completely different
result from the `ping6` test one command earlier.

Confirm what's actually happening on `backend`'s side:
```bash
docker exec incident08-backend ip6tables -L -n
```
```
Chain INPUT (policy ACCEPT)
target     prot opt source               destination
DROP       tcp  --  ::/0                 ::/0                 tcp dpt:8080
```
A `DROP`, specifically for TCP, specifically for port 8080, over
`ip6tables` only - `iptables -L -n` (the IPv4 table) would show nothing
at all here.

## The fix

Immediate mitigation - remove the rule that's actually causing this:
```bash
docker exec incident08-backend ip6tables -D INPUT -p tcp --dport 8080 -j DROP
```
`/checkout` drops back to a few milliseconds immediately - no restart
of either container required.

For a durable fix, address the failure at both layers it exists at:
whoever/whatever manages firewall rules on real hosts needs to treat
`ip6tables` and `iptables` as one rule set to keep in sync, not two
independently-maintained ones (a rule added to block/allow something
on IPv4 with no equivalent IPv6 rule is exactly how a gap like this
opens in the first place). Separately, and just as importantly: a
client library with real Happy Eyeballs behavior (racing IPv4 and IPv6
connection attempts in parallel, using whichever wins) would have
made this incident nearly invisible - a few milliseconds of wasted
effort on the losing race instead of a hard 5-second tax on every
single request. Neither fix alone is sufficient on its own in a real
fleet: the firewall gap will recur eventually, and a well-behaved
client only limits the blast radius of the next one, it doesn't
prevent it.

## Real-world examples of this pattern

- Cloud load balancers and CDNs that added IPv6 support incrementally
  are a common source of exactly this shape of incident: a backend
  target gets an IPv6 address in DNS before the security group/firewall
  rules protecting it have been fully mirrored from IPv4, and clients
  with naive address-selection behavior eat the full timeout on every
  request until someone notices.
- This is the same underlying mechanism as
  `labs/networking/24-ipv6-dual-stack-issues` (a half-broken IPv6 path
  being worse than a fully absent one) combined with
  `labs/networking/28-iptables-ipv6-gap` (`iptables` and `ip6tables`
  being two independently-maintained rule sets) - here the two combine
  into a single, business-visible "why did checkout get slower"
  incident instead of either mechanism being demonstrated in
  isolation.
- Any client library or runtime that resolves a hostname once and
  tries addresses sequentially - which is still extremely common
  outside of browsers, which are essentially the only class of client
  that reliably implements full Happy Eyeballs - is a latent version
  of this incident waiting for exactly this kind of partial dual-stack
  misconfiguration to make it real.
