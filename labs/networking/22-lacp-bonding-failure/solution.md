# Lab 22 — Solutions

## Challenge A — partner's whole bond running the wrong mode

**Check:**
```bash
sudo ip netns exec h1 cat /proc/net/bonding/bond0
sudo ip netns exec h1 ping -c 3 10.10.10.2
```
Both of `h1`'s slaves now show `MII Status: up`, but **neither** is part of
an active aggregator with any ports in it — `Number of ports: 0`, and the
ping fails completely. This is a different, worse outcome than Step 3/4,
where one link degraded but the bond stayed reachable.

**Diagnosis:** in Step 3/4, `h2` still had one properly-configured LACP
link — `h1` lost one member of its aggregate but kept a working path over
the other. Here, `h2`'s entire bond was rebuilt in `active-backup` mode,
which doesn't speak LACP at all — from `h1`'s side, *neither* link ever
gets a valid LACPDU response, so the 802.3ad state machine never brings
either slave into an active aggregator. A partial LACP misconfiguration
(one link) degrades a bond; a total one (the whole switch-side
port-channel never configured for LACP) takes the whole aggregate down,
even though every individual cable is fine and every interface reports
link-up. "MII Status: up" tells you the physical link exists — it tells
you nothing about whether LACP actually negotiated on top of it.

**Fix:**
```bash
sudo ip netns exec h2 ip link set veth-h2a nomaster
sudo ip netns exec h2 ip link set veth-h2b nomaster
sudo ip netns exec h2 ip link del bond0
sudo ip netns exec h2 ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast
sudo ip netns exec h2 ip link set veth-h2a master bond0
sudo ip netns exec h2 ip link set veth-h2b master bond0
sudo ip netns exec h2 ip link set veth-h2a up
sudo ip netns exec h2 ip link set veth-h2b up
sudo ip netns exec h2 ip addr add 10.10.10.2/24 dev bond0
sudo ip netns exec h2 ip link set bond0 up
```

**Lesson:** "the link light is on" and "LACP successfully negotiated an
aggregate" are two completely independent facts, exactly like the
Established-vs-advertised distinction in this series' BGP lab. Always
check `Number of ports` under `Active Aggregator Info`, not just per-slave
`MII Status`, before declaring a bond healthy.

---

## Challenge B — one link aggregated with the wrong partner

**Check:**
```bash
sudo ip netns exec h1 cat /proc/net/bonding/bond0
```
Both `veth-h1a` and `veth-h1b` show `MII Status: up`, and both are
successfully running LACP (neither is stuck retrying) — but their
`Partner Mac Address` fields are different, and their `Aggregator ID`
values differ too. Only one of the two ends up with ports in the active
aggregator; the other sits configured, link-up, LACP-capable, and
completely unused.

**Diagnosis:** LACP will only combine member links into a single aggregate
if they're all talking to the *same* partner system — that's the entire
point of the partner system MAC/key exchange in the LACPDU. `veth-h1b`
is physically connected to `h3`, a different system entirely, not to
`h2`. From LACP's point of view these are two unrelated, valid,
individually-successful negotiations that simply can't be merged, because
merging them would mean forwarding traffic for the same aggregate through
two different, unrelated remote systems — which defeats the entire purpose
of an aggregate. This is the exact digital equivalent of a redundant
uplink cable being plugged into the wrong switch chassis: everything
"looks" up and negotiated on both ends, and the only way to catch it is by
comparing which partner each link actually thinks it's talking to.

**Fix:**
```bash
sudo ip netns exec h1 ip link set veth-h1b nomaster
sudo ip netns exec h1 ip link del veth-h1b
sudo ip link add veth-h1b type veth peer name veth-h2b
sudo ip link set veth-h1b netns h1
sudo ip link set veth-h2b netns h2
sudo ip netns exec h1 ip link set veth-h1b master bond0
sudo ip netns exec h1 ip link set veth-h1b up
sudo ip netns exec h2 ip link set veth-h2b master bond0
sudo ip netns exec h2 ip link set veth-h2b up
sudo ip netns del h3
```

**Lesson:** matching `MII Status` and even successful LACP negotiation on
every member link is not sufficient proof a bond is correctly wired —
every slave also has to be negotiating with the *same* partner. In
production this is `show lacp neighbor` (or the equivalent) on the switch
side, or `Partner Mac Address` per slave on the Linux side; comparing that
field across slaves is the one check that catches a cross-connected
redundant link that every other symptom will otherwise hide.
