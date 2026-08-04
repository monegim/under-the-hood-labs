# Lab 16 — Solutions

## Challenge A — stateful firewall on the return-path router

**Check:**
```bash
docker exec clab-asym-routing-r1 tcpdump -ni eth2 -c 4 tcp port 8080
```
The SYN from `client` shows up here, forwarded through `r1` toward
`server`, exactly once, no retransmits at this hop.
```bash
docker exec clab-asym-routing-r2 tcpdump -ni eth2 -c 4 tcp port 8080
```
The SYN-ACK from `server` shows up on `r2`'s server-facing interface —
`server` sent it, and it arrived at `r2` correctly, because `server`'s
route back to `client`'s subnet points at `r2`.
```bash
docker exec clab-asym-routing-r2 tcpdump -ni eth1 -c 4 tcp port 8080
```
Nothing arrives here at all — the SYN-ACK never makes it out `r2`'s
client-facing side.
```bash
docker exec clab-asym-routing-r2 iptables -L FORWARD -v -n
```
The counter on the `DROP` policy (or an implicit drop with no matching
rule) is incrementing.

**Diagnosis:** `r2` never saw the original SYN — it went through `r1`
instead, because `client`'s route to `server` points there. When the
SYN-ACK arrives at `r2` on the return leg, `r2`'s own conntrack table has
no record of this connection at all. A TCP segment with the SYN+ACK flags
and no prior SYN seen through this exact box doesn't get charitably
treated as part of an existing flow — with `nf_conntrack_tcp_loose=0`, it
is classified `INVALID`. `r2`'s `FORWARD` policy only explicitly allows
`ESTABLISHED,RELATED` (plus ICMP, unconditionally) — `INVALID` matches
neither, and the default policy is `DROP`. The SYN-ACK dies right there.
`client` never gets it, keeps retransmitting its SYN (which keeps
succeeding in reaching `server` via `r1`, generating a fresh SYN-ACK each
time — same result), and eventually gives up. Ping keeps working the
entire time because the ICMP rule doesn't care about connection state at
all.

**Fix:** eliminate the asymmetry — make both directions transit the same
router:
```bash
docker exec clab-asym-routing-server ip route replace 10.0.1.0/24 via 10.0.2.1 dev eth1
```
The production-grade version of this fix, when you can't simply force
symmetric routing (e.g. two routers are *meant* to load-share traffic),
is connection-tracking synchronization between the redundant devices —
tools like `conntrackd` exist specifically to replicate conntrack state
between a cluster of stateful firewalls so that whichever one sees the
return leg already has the state the other one built on the forward leg.

**Lesson:** "ping works, TCP doesn't" with otherwise-correct-looking
routing on both ends is the specific signature of a stateful device only
seeing one direction of a flow. It's not a routing bug in the traditional
sense (each individual route is perfectly valid and reachable) — it's a
routing *decision* colliding with a device that assumes it will see both
halves of every conversation.

---

## Challenge B — the firewall moved to the forward-path router

**Check:**
```bash
docker exec clab-asym-routing-r1 tcpdump -ni eth2 -c 4 tcp port 8080
```
Nothing shows up here at all this time — not even the initial SYN.
```bash
docker exec clab-asym-routing-r1 iptables -L FORWARD -v -n
```
The `DROP` policy counter is incrementing on `r1` instead of `r2`.
```bash
docker exec clab-asym-routing-r2 tcpdump -ni eth1 -c 4 tcp port 8080
```
Also nothing — there's nothing for `r2` to forward, because the
connection never got past `r1` on the way out.

**Diagnosis:** this is the mirror image of Challenge A, and the capture
comparison is exactly what tells the two apart. In Challenge A, the SYN
made it all the way to the server and the *reply* was what got dropped
(on `r2`, one hop before completing the round trip). Here, the very first
packet of the connection — the client's own SYN — never leaves `r1` at
all: `r1`'s policy only allows `ESTABLISHED,RELATED` and ICMP, with no
rule permitting a brand-new (`NEW`-state) TCP connection through in the
first place, so the SYN is dropped before `server` ever hears about it.
The routing asymmetry (return traffic still routed via `r2`) is present
but irrelevant here — there's no established connection for it to ever
matter for, because the forward leg never got that far. This is what
happens in practice when a firewall config gets copied or moved between
boxes with an assumption baked in ("this router only ever sees return
traffic, so it doesn't need a NEW-connection rule") that stops being true
the moment routing or firewall placement changes.

**Fix:** allow new connections out through `r1` (the box actually on the
forward path now):
```bash
docker exec clab-asym-routing-r1 iptables -I FORWARD -p tcp --dport 8080 -m conntrack --ctstate NEW -j ACCEPT
```

**Lesson:** don't assume which leg of an asymmetric path failed just
because the end-to-end symptom (`ping` fine, TCP hanging) looks identical
to a scenario you've already diagnosed. Capture at every hop along both
directions — a SYN that never leaves the first router is a categorically
different bug from a SYN-ACK that never makes it back through the last
one, even though both present identically from the client alone.
