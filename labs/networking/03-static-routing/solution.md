# Lab 3 — Solutions

## Challenge A — missing return route

**Check:**
```bash
docker exec clab-static-routing-r2 vtysh -c "show ip route"
```
`10.0.1.0/24` is gone. `tcpdump -n -i eth2` on r2 (toward host2) shows the
echo-request from host1 arriving fine; `tcpdump -n -i eth1` on r2 (toward
r1) shows nothing going back out.

**Diagnosis:** r2 can still forward host1's request TO host2 — that only
needs a route to `10.0.2.0/24`, which is directly connected on r2's `eth2`
and was never touched. What's missing is r2's route back to `10.0.1.0/24`
for the reply: host2's echo-reply arrives at r2 with no matching route, so
r2 drops it (or ICMP-unreachables it back to host2, not to host1). host1
never sees a reply and the ping just times out. This is the textbook
"ping works one way" bug: the forward path is fine, the return path is
blackholed one hop before completing the round trip.

**Fix:**
```bash
docker exec clab-static-routing-r2 vtysh -c "conf t" -c "ip route 10.0.1.0/24 10.0.12.1"
```

**Lesson:** a route being correct in one direction tells you nothing about
the other direction. Routing is inherently asymmetric unless you verify
both legs of the path explicitly — check the return route, not just the
forward one.

---

## Challenge B — route to a dead next-hop

**Check:**
```bash
docker exec clab-static-routing-r1 vtysh -c "show ip route 10.0.2.0/24"
docker exec clab-static-routing-r1 ip neigh show
```
The route is present and matches the prefix, via `10.0.12.99`. `ip neigh`
shows `10.0.12.99` as unresolved/`FAILED` (or absent entirely) — nothing on
the transit link answers ARP for that address.

**Diagnosis:** unlike Challenge A, the route table isn't missing anything —
it looks completely correct at a glance. The problem is the next-hop IP
itself: `10.0.12.99` isn't r2's real address (`10.0.12.2`), so ARP for it
never resolves and the route is functionally dead. `show ip route` will
happily show you a route that can never actually be used.

**Fix:**
```bash
docker exec clab-static-routing-r1 vtysh -c "conf t" \
  -c "no ip route 10.0.2.0/24 10.0.12.99" \
  -c "ip route 10.0.2.0/24 10.0.12.2"
```

**Lesson:** "the route is there" and "the route works" are not the same
claim. Always check ARP/neighbor resolution for a static route's next-hop
(`ip neigh`), not just whether the route table has an entry — especially
after a copy-pasted or typo'd static route.
