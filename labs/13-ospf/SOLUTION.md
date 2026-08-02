# Lab 13 — Solutions

## Challenge A — area ID mismatch

**Check:**
```bash
docker exec clab-ospf-r2 vtysh -c "show ip ospf neighbor"
docker exec clab-ospf-r3 vtysh -c "show ip ospf interface eth1"
docker exec clab-ospf-r2 vtysh -c "show ip ospf interface eth2"
```
`r3` is missing from r2's neighbor table (or stuck at a low state and never
reaching `Full`). `r3`'s `eth1` reports `Area 1`; `r2`'s `eth2` on the same
link still reports `Area 0`.

**Diagnosis:** OSPF requires both ends of a link to agree on the area ID —
this is checked in the Hello packet itself. r3 now advertises area 1 on the
r2-r3 link while r2 still expects area 0 there, so r2 rejects r3's Hellos
(an area mismatch shows up in `debug ospf` output/logs). `r1-r2` is a
completely separate link and area statement, so it's untouched — this is
why only one adjacency broke, not the whole router.

**Fix:**
```bash
docker exec clab-ospf-r3 vtysh -c "conf t" -c "router ospf" \
  -c "no network 10.0.23.0/30 area 1" -c "network 10.0.23.0/30 area 0"
```

**Lesson:** OSPF area mismatches fail per-link, not per-router — always
check the specific interface's area (`show ip ospf interface`), not just
the router's overall config, especially on a router mid-redesign that
spans multiple areas.

---

## Challenge B — hello/dead timer mismatch

**Check:**
```bash
docker exec clab-ospf-r2 vtysh -c "show ip ospf interface eth2"
docker exec clab-ospf-r3 vtysh -c "show ip ospf interface eth1"
```
r2's `eth2` shows Hello 5; r3's `eth1` (same link) still shows the default
Hello 10. Dead interval didn't change on either side — FRR doesn't
auto-scale it when you tune Hello alone, so now they disagree on both.

**Diagnosis:** OSPF neighbors must agree on the Hello and Dead intervals
for a given link, checked exactly like the area ID — a Hello packet
carrying mismatched intervals gets rejected before an adjacency can even
start. It doesn't matter that only one side changed; agreement is
symmetric, so any solo change makes the pair inconsistent. This looks like
a smaller, more harmless change than Challenge A, but produces the
identical class of symptom: the adjacency simply won't form.

**Fix:** revert it (or change it identically on both sides):
```bash
docker exec clab-ospf-r2 vtysh -c "conf t" -c "interface eth2" -c "no ip ospf hello-interval"
```

**Lesson:** OSPF timers are a link-level agreement, not a per-router tuning
knob. Changing convergence-speed settings on only one router in a peering
pair doesn't make convergence faster on that end — it breaks the peering
outright.
