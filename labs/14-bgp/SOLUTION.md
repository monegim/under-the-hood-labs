# Lab 14 — Solutions

## Challenge A — AS number mismatch

**Check:**
```bash
docker exec clab-bgp-lab-r2 vtysh -c "show bgp summary"
docker exec clab-bgp-lab-r2 vtysh -c "show bgp neighbor 10.12.0.1"
```
The neighbor never reaches `Established` — it cycles through
`Active`/`Connect`/`OpenSent`, and `show bgp neighbor` reports a
notification like "Bad Peer AS" or shows the last reset reason referencing
the AS number.

**Diagnosis:** r2 is configured to expect r1 to be AS 65099, but r1 is
actually announcing AS 65001 in its BGP OPEN message. eBGP requires both
sides to agree on the peer's AS number exactly — r2 rejects the OPEN
message outright because the AS in it doesn't match what r2 was told to
expect.

**Fix:**
```bash
docker exec clab-bgp-lab-r2 vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "neighbor 10.12.0.1 remote-as 65001"
```

**Lesson:** a neighbor stuck in `Active`/`Connect` and never reaching
`Established` is almost always a session-establishment-level problem (AS
mismatch, TCP reachability, or an ACL) — not a routing problem. Always read
`show bgp neighbor <ip>` for the actual notification reason before guessing.

---

## Challenge B — missing redistribution

**Check:**
```bash
docker exec clab-bgp-lab-r2 vtysh -c "show bgp summary"
```
Both sessions still show `Established` — this alone tells you it's a
different kind of problem than Challenge A.

```bash
docker exec clab-bgp-lab-r1 vtysh -c "show ip route connected"
docker exec clab-bgp-lab-r1 vtysh -c "show bgp ipv4 unicast"
```
`1.1.1.1/32` is in r1's connected routing table, but absent from r1's own
BGP table.

**Diagnosis:** BGP does not automatically advertise every route in the
kernel routing table. A router only advertises what's explicitly injected
into BGP — via `redistribute connected` (or a `network` statement). r1's
loopback was never injected, so there was never anything for r1 to
advertise to r2 in the first place; r2 and r3 aren't failing to relay
it, there was nothing to relay.

**Fix:**
```bash
docker exec clab-bgp-lab-r1 vtysh \
  -c "configure terminal" \
  -c "router bgp 65001" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "exit-address-family"
```

**Lesson:** "the session is Established" and "my routes are being
advertised" are two independent facts, controlled by two independent pieces
of config. A healthy session tells you the control-plane transport works —
it tells you nothing about whether you remembered to actually put anything
on it.
