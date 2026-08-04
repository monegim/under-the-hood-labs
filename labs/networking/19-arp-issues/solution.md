# Lab 19 — Solutions

## Challenge A — stale ARP entry, no gratuitous ARP sent

**Check:**
```bash
docker exec clab-arp-lab-client ip neigh show 10.0.0.100
```
Still shows `server-a`'s MAC — even though `server-a` no longer has
`10.0.0.100` configured at all.
```bash
docker exec clab-arp-lab-client ping -c 2 -W 2 10.0.0.100
```
Times out completely.
```bash
docker exec clab-arp-lab-client ping -c 2 10.0.0.21
```
Succeeds immediately — `server-b`'s own real address, on the same
segment, works fine.

**Diagnosis:** `client` is still sending every packet for `10.0.0.100` to
`server-a`'s MAC address, because that's what its ARP cache says, and
nothing told it otherwise. Those frames arrive at `server-a`'s NIC just
fine at Layer 2 — but `server-a`'s own kernel checks the destination IP
against its own configured addresses, finds no match (the VIP was
removed), and silently drops them. `client` never gets a reply and just
sees a timeout, identical on the surface to "the host is down." The
successful ping to `server-b`'s real address proves the segment, the
subnet, and `client`'s own routing are all completely fine — this is
purely a Layer 2 cache pointing at the wrong destination.

**Fix:**
```bash
docker exec clab-arp-lab-client ip neigh flush dev eth1
docker exec clab-arp-lab-client ping -c 2 10.0.0.100
```
Flushing forces a fresh ARP request the next time `10.0.0.100` is needed
— `server-b` (which now actually holds the address) answers, and the
cache gets corrected.

**Lesson:** a stale neighbor-table entry doesn't necessarily self-heal
quickly. Linux's neighbor state machine (`REACHABLE` → `STALE` → `DELAY`
→ `PROBE`) only re-verifies an entry once it's aged past `REACHABLE`, and
even then only actively re-probes it when there's a reason to (traffic
trying to use it). Gratuitous ARP exists specifically to short-circuit
that whole timer-driven process by proactively pushing the correct
mapping out to everyone the instant it changes — when it doesn't fire
(a broken/incomplete failover script, a VIP moved by hand without
remembering this step), you're left waiting on cache timers instead of
an immediate, correct update, and `ip neigh flush` is the manual override
for exactly that gap.

---

## Challenge B — the old owner never gave up the address

**Check:**
```bash
for i in 1 2 3 4; do
  docker exec clab-arp-lab-client ping -c 1 -W 1 10.0.0.100 >/dev/null
  docker exec clab-arp-lab-client ip neigh show 10.0.0.100
  sleep 2
done
```
The resolved MAC flips between two different addresses across the loop —
sometimes `server-a`'s, sometimes `server-b`'s — with no pattern tied to
anything `client` is doing.
```bash
docker exec clab-arp-lab-server-a ip addr show eth1
docker exec clab-arp-lab-server-b ip addr show eth1
```
`10.0.0.100/24` is configured on **both** hosts simultaneously.

**Diagnosis:** this isn't a caching problem at all — the gratuitous ARP
in this scenario worked exactly as designed. The actual bug is one layer
up: the failover process added the VIP to `server-b` but never removed it
from `server-a`, so two different hosts on the same segment are both
prepared to answer for the same IP address. Whichever one happens to
respond to a given ARP request (or send the most recent gratuitous
announcement) wins the client's cache until the other one asserts itself
again — this is a genuine IP/MAC conflict, not staleness, and no amount
of `ip neigh flush`ing fixes a conflict that keeps re-creating itself.

**Fix:** remove the VIP from whichever host shouldn't have it — the
actual standby:
```bash
docker exec clab-arp-lab-server-a ip addr del 10.0.0.100/24 dev eth1
```

**Lesson:** flapping ARP resolution for the same IP between two different
MACs is the signature of a duplicate/conflicting address assignment, not
a stale cache — and the fix is completely different (remove the
conflicting configuration from one of the two hosts) from Challenge A's
fix (force a fresh resolution). Checking `ip addr show` on every host
that could plausibly hold the VIP, not just the client's neighbor table,
is what tells these two apart.
