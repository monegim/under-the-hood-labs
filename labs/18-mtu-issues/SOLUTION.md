# Lab 18 — Solutions

## Challenge A — PMTUD blackhole via blocked ICMP

**Check:**
```bash
docker exec clab-mtu-lab-hostA tcpdump -ni eth1 -c 5 icmp
docker exec clab-mtu-lab-r1 iptables -L OUTPUT -v -n
```
On hostA, the oversized DF-set ping just times out — 100% packet loss,
*no* "Frag needed" message this time, nothing comes back at all. On r1,
the `iptables -L -v` counter on the DROP rule is incrementing every time
you ping.

**Diagnosis:** r1 is still doing the right thing internally — it still
refuses to forward the oversized DF packet into `gre1` and still generates
an ICMP "fragmentation needed" message back toward hostA. But that ICMP
reply is itself being dropped by the iptables rule before it leaves r1.
hostA never learns that anything is wrong; it just keeps sending the same
oversized packet, which keeps getting silently discarded, forever. This is
the textbook PMTUD blackhole.

**Fix:**
```bash
docker exec clab-mtu-lab-r1 iptables -D OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP
```

**Lesson:** PMTUD's entire feedback loop depends on ICMP "fragmentation
needed" getting back to the original sender. Any firewall/security-group
rule that blocks "unnecessary-looking" ICMP — a very common hardening
default — silently breaks path MTU discovery for every tunnel, VPN, or
oversized-MTU path behind it. Always explicitly permit ICMP type 3 (and
especially code 4) through any firewall sitting in front of a tunnel
endpoint.

---

## Challenge B — stale tunnel MTU after underlay change

**Check:**
```bash
docker exec clab-mtu-lab-r1 ip link show eth2
docker exec clab-mtu-lab-r1 ip link show gre1
```
`eth2` (the underlay interface) now reports `mtu 1400`, but `gre1` still
reports `mtu 1476` on both r1 and r2 — a size it can no longer actually
deliver without fragmenting.

**Diagnosis:** the GRE tunnel's MTU was computed once, at tunnel creation
time, based on the underlay's MTU *at that moment*. Lowering the physical
underlay's MTU afterward doesn't retroactively recalculate the tunnel's
advertised MTU — nothing in the kernel watches for that and fixes it up
for you. So `gre1` keeps telling the routing stack "I can carry 1476-byte
packets" when the real ceiling underneath it is now 1376 (1400 minus 24
bytes of GRE overhead). Traffic sized correctly for the *old* path now
silently fails the same way as Challenge A (and if Challenge A's iptables
rule is still in place, there's no ICMP telling anyone why).

**Fix:**
```bash
docker exec clab-mtu-lab-r1 ip link set gre1 mtu 1376
docker exec clab-mtu-lab-r2 ip link set gre1 mtu 1376
```

**Lesson:** tunnel MTU is not self-healing. If anything changes the real
carrying capacity of the path underneath a tunnel — a provider migration,
a new encapsulation layer added upstream, a lowered MTU on a cloud VPC
attachment — every tunnel interface riding on top of that path has a
stale, wrong MTU until you go recompute and reapply it by hand. Nothing
recalculates it automatically, on either end.
