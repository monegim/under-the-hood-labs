# Lab 24 — Solutions

## Challenge A — Neighbor Discovery blocked instead of the service port

**Check:**
```bash
sudo ip netns exec client ping6 -c 2 fd00::2
sudo ip netns exec client curl -6 --max-time 5 -s -o /dev/null -w "%{time_total}s\n" http://[fd00::2]/
```
Both fail this time — `ping6` gets no reply at all, and `curl -6` times
out exactly like before, but now for a completely different reason.

**Diagnosis:** IPv6 doesn't use ARP — it uses Neighbor Discovery Protocol
(NDP), built on ICMPv6, to resolve a neighbor's link-layer address before
*anything* can be sent to it, including the ping itself. Blocking Neighbor
Solicitation/Advertisement messages breaks address resolution at a layer
underneath both ICMPv6 echo and TCP — the client can't even find out how
to frame a packet to the server's link-layer address, so nothing gets
sent at all, for any protocol. Step 3's block was much narrower: it let
NDP and ICMPv6 echo complete normally (the two hosts fully know how to
reach each other at L2/L3), and only intercepted TCP port 80 specifically.
That's why Step 4 showed a working `ping6` next to a broken `curl -6` — the
failure lived strictly at the service-port layer. Here, the failure lives
one layer lower, and it takes *everything* down with it, ping included.

**Fix:**
```bash
sudo ip netns exec server ip6tables -D INPUT -p icmpv6 --icmpv6-type neighbor-solicitation -j DROP
sudo ip netns exec server ip6tables -D INPUT -p icmpv6 --icmpv6-type neighbor-advertisement -j DROP
```

**Lesson:** "IPv6 is broken" is not one failure mode — it's a stack of
independently-breakable layers (Neighbor Discovery, ICMPv6 reachability,
then whatever transport/application traffic you actually care about), and
the symptom tells you which layer to look at: no neighbor resolution means
total silence on everything; a healthy ping next to a broken app port
means the problem is specific to that port/service, not to IPv6 as a
whole. Always localize which layer is actually failing before assuming
"IPv6 is down" as a blanket diagnosis.

---

## Challenge B — Happy Eyeballs configured with a long timeout

**Check:**
```bash
sudo ip netns exec client curl --max-time 10 -s -o /dev/null \
  -w "%{time_total}s\n" --happy-eyeballs-timeout-ms 5000 \
  --resolve svc.test:80:10.0.0.2,fd00::2 http://svc.test/
```
The result is close to 5 seconds — nearly as bad as Step 5's client with
no fallback logic at all, despite this being the exact same `curl` that
performed well in Step 6.

**Diagnosis:** `--happy-eyeballs-timeout-ms` is the head-start curl gives
its *first* connection attempt before it starts racing the next address
family in parallel. In Step 6, that value was curl's short default
(on the order of a couple hundred milliseconds), so the IPv4 attempt
started racing almost immediately and won quickly. Set it to 5000ms, and
curl dutifully waits nearly the entire 5 seconds for the (blackholed) IPv6
attempt before it ever starts trying IPv4 in parallel — functionally
reproducing the naive sequential-fallback behavior from Step 5, just with
extra steps. Supporting RFC 8305 doesn't automatically deliver its
benefit; the head-start delay has to actually be short relative to how
long a broken path can silently hang for, or the "race" degenerates back
into "wait, then try the next thing."

**Fix:**
```bash
sudo ip netns exec client curl --max-time 5 -s -o /dev/null \
  -w "%{time_total}s\n" --happy-eyeballs-timeout-ms 250 \
  --resolve svc.test:80:10.0.0.2,fd00::2 http://svc.test/
```

**Lesson:** Happy Eyeballs' benefit comes specifically from starting the
fallback attempt *soon*, not merely from attempting a fallback at all. A
client, library, or OS resolver with Happy Eyeballs support but a long or
misconfigured head-start timer gives you almost none of the protection the
mechanism is supposed to provide — "does this support RFC 8305" and "is it
actually fast in practice" are two different questions, and only checking
the first one is how a technically-compliant client still ends up with the
exact multi-second hangs Happy Eyeballs exists to prevent.
