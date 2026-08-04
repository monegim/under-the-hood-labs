# Lab 22 — LACP Bonding Failure

## Objective
Build a real LACP (802.3ad) link aggregate between two Linux bonding
interfaces — no physical switch required, LACP negotiates peer-to-peer —
then watch what happens when one member link's partner isn't actually
running LACP, and learn to read `/proc/net/bonding/bond0` well enough to
tell "degraded" from "down" from "connected to the wrong thing entirely."

## Why this matters
Bonded/aggregated links (802.3ad, sometimes still called "EtherChannel" or
"port-channel" on switch config) are how servers get more than one NIC's
worth of bandwidth and survive a single cable or switch port dying. LACP is
the protocol that keeps both ends honest about which physical links
actually belong in the same aggregate — and a huge fraction of real "the
bond isn't giving me the throughput I expected" tickets trace back to one
member link not being in the switch's LACP channel-group at all, not to
anything wrong with the server.

## Prerequisites
- Linux VM with `iproute2` and the `bonding` kernel module
- `sudo` access

Check first:
```bash
ip -V
sudo modprobe bonding max_bonds=0
lsmod | grep bonding
cat /proc/net/bonding/bond0 2>/dev/null; echo "(should not exist yet)"
```
> `max_bonds=0` stops the module from auto-creating a `bond0` in the root
> netns on load — we want every bond created explicitly, inside a
> namespace.

## Step 1 — Build the topology
```bash
bash setup.sh
```
This creates two namespaces, `h1` and `h2`, each with a `bond0` in
`802.3ad` mode aggregating **two** veth links between them (`veth-h1a`↔
`veth-h2a` and `veth-h1b`↔`veth-h2b`). `lacp_rate fast` is set on both ends
so LACPDUs exchange every second instead of the 30-second default —
purely to make convergence fast enough to watch in a lab.

## Step 2 — Verify the aggregate actually formed
```bash
sudo ip netns exec h1 ping -c 3 10.10.10.2
sudo ip netns exec h1 cat /proc/net/bonding/bond0
sudo ip netns exec h2 cat /proc/net/bonding/bond0
```
Look for, on both sides:
- `Bonding Mode: IEEE 802.3ad Dynamic link aggregation`
- Under `Active Aggregator Info`: **`Number of ports: 2`**
- Both `Slave Interface` blocks showing `MII Status: up` and the **same**
  `Aggregator ID`
- Matching `Partner Mac Address` on both slaves (they're both talking to
  the same partner system)

That `Number of ports: 2` line is the one thing that actually proves both
physical links are working *as a single aggregate* — a bond can have two
slaves with MII Status up and still not be aggregating them together, which
is exactly what you're about to cause.

## Step 3 — Break one link's LACP partner
```bash
sudo ip netns exec h2 ip link set veth-h2b nomaster
sudo ip netns exec h2 ip link set veth-h2b up
```
This simulates the single most common real cause of this failure: the
switch port on the other end of one cable was never added to the LACP
channel-group. `veth-h2b` is still up as a plain interface — physically
fine — it's just not running LACP on h2's side anymore.

## Step 4 — Read the damage
```bash
sudo ip netns exec h1 cat /proc/net/bonding/bond0
```
`veth-h1a` is unaffected. `veth-h1b` is still `MII Status: up` (the link
itself is physically fine — this is not a cable problem) but it's no
longer part of the active aggregator: `Number of ports` under
`Active Aggregator Info` has dropped to **1**, and `veth-h1b`'s own
`Aggregator ID` no longer matches `veth-h1a`'s. `h1` keeps sending LACPDUs
out `veth-h1b` and simply never gets a reply, because nothing on the other
end is speaking LACP on that link anymore.
```bash
sudo ip netns exec h1 ping -c 3 10.10.10.2
```
Still works — this is the important part. The bond isn't down, it's
**degraded**: still fully connected, just running at half the aggregate
capacity it thinks it has, silently.

## Step 5 — Fix it
```bash
sudo ip netns exec h2 ip link set veth-h2b master bond0
sudo ip netns exec h2 ip link set veth-h2b up
```
Give LACP a few seconds (with `lacp_rate fast`, well under 10s) then
re-check `/proc/net/bonding/bond0` on `h1` — `Number of ports: 2` again.

## Challenges

**Challenge A:**
```bash
sudo ip netns exec h2 ip link set veth-h2a nomaster
sudo ip netns exec h2 ip link set veth-h2b nomaster
sudo ip netns exec h2 ip link del bond0
sudo ip netns exec h2 ip link add bond0 type bond mode active-backup miimon 100
sudo ip netns exec h2 ip link set veth-h2a master bond0
sudo ip netns exec h2 ip link set veth-h2b master bond0
sudo ip netns exec h2 ip link set veth-h2a up
sudo ip netns exec h2 ip link set veth-h2b up
sudo ip netns exec h2 ip addr add 10.10.10.2/24 dev bond0
sudo ip netns exec h2 ip link set bond0 up
```
`h2`'s whole bond gets rebuilt in `active-backup` mode instead of
`802.3ad` (simulating a switch whose port-channel was never configured for
LACP at all, on *either* member link). Check `/proc/net/bonding/bond0` on
`h1` and try to ping `10.10.10.2` before concluding anything — this looks
like Step 3/4's failure but compare the `Number of ports` count and the
actual reachability result closely; they're not the same outcome.

**Challenge B:**
```bash
sudo ip netns exec h1 ip link set veth-h1b nomaster
sudo ip netns exec h1 ip link del veth-h1b
sudo ip netns add h3
sudo ip link add veth-h1b type veth peer name veth-h3a
sudo ip link set veth-h1b netns h1
sudo ip link set veth-h3a netns h3
sudo ip netns exec h1 ip link set veth-h1b master bond0
sudo ip netns exec h1 ip link set veth-h1b up
sudo ip netns exec h3 ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast
sudo ip netns exec h3 ip link set veth-h3a master bond0
sudo ip netns exec h3 ip link set veth-h3a up
sudo ip netns exec h3 ip addr add 10.10.10.3/24 dev bond0
sudo ip netns exec h3 ip link set bond0 up
sudo ip netns exec h3 ip link set lo up
```
`h1`'s second link now goes to an entirely different LACP speaker (`h3`)
instead of `h2` — as if the redundant cable had been plugged into the
wrong switch chassis. Both of `h1`'s slaves show `MII Status: up` and both
are running LACP successfully — just not with the same partner. Compare
`Partner Mac Address` across `h1`'s two `Slave Interface` blocks in
`/proc/net/bonding/bond0` before concluding what's actually wrong.

See `solution.md` only after you've formed your own diagnosis.
