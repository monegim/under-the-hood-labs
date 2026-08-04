# Lab 21 — STP Loop

## Objective
Wire two Linux bridges together with two parallel links (a genuine physical
Layer 2 loop), watch what an unprotected loop actually does to broadcast
traffic, then turn on Spanning Tree Protocol and watch it block exactly the
right port to make the redundancy safe.

## Why this matters
"Just add a second uplink for redundancy" is one of the most common access-
layer changes made in real networks — and one of the most common causes of
a total outage when STP isn't running or isn't participating on both ends.
Every managed switch you've ever plugged two cables into for resiliency is
relying on the same mechanism you're about to build and break by hand: an
elected root bridge, a computed shortest path to it, and every other path
put into blocking so frames only ever have one way to travel.

## Prerequisites
- Linux VM with `iproute2` (`ip`, `bridge` commands) and `bridge-utils`
  (`brctl`)
- `iputils-arping` and `tcpdump`
- `sudo` access

Check first:
```bash
ip -V
which bridge brctl arping tcpdump
lsmod | grep -q bridge || sudo modprobe bridge
# Debian/Ubuntu: sudo apt install -y bridge-utils iputils-arping tcpdump
```

## Step 1 — Build the topology
```bash
bash setup.sh
```
This wires up `sw1` and `sw2` (two Linux bridges standing in for two
switches), connected by **two** parallel veth links — a physical loop —
plus `h1` on `sw1` and `h2` on `sw2`. STP is deliberately left **off** on
both bridges: this is the "someone plugged in a second uplink for
redundancy and nobody turned Spanning Tree on" starting state.

## Step 2 — Confirm the loop is there
```bash
bridge link show
```
You'll see four bridge ports beyond the host uplinks: `sw1-a`/`sw2-a` and
`sw1-b`/`sw2-b` — two independent physical paths between the same two
bridges.

## Step 3 — Confirm basic connectivity works (for now)
```bash
sudo ip netns exec h1 ping -c 2 10.0.0.2
```
Works fine — with no traffic looping yet, a loop that isn't actively
carrying repeated frames looks completely healthy.

## Step 4 — Trigger a bounded storm demonstration
> **Safety note:** an unprotected bridging loop replicates broadcast frames
> without limit — Ethernet has no TTL, so nothing makes it decay on its
> own. Every command below is deliberately time-boxed (`timeout`, `-c`) so
> the demo can't run away with your CPU. Do not remove those bounds.

```bash
sudo ip netns exec h2 timeout 3 tcpdump -ni veth-h2 -nn arp > /tmp/storm.log 2>/dev/null &
sleep 0.3
sudo ip netns exec h1 arping -c 1 -b -I veth-h1 10.0.0.2 >/dev/null 2>&1 || true
wait
wc -l /tmp/storm.log
```
`h1` sent exactly **one** broadcast ARP request. Compare that to the line
count in `/tmp/storm.log` — with the loop unprotected you'll see it arrive
at `h2` many times over in that 3-second window, not once: `sw1` floods it
out both links to `sw2`, `sw2` floods each copy right back out its other
link toward `sw1`, and it keeps compounding for as long as anything lets it.

## Step 5 — Kill the storm immediately
```bash
sudo ip link set sw1-b down
```
This is the emergency mitigation a real NOC reaches for first: break the
physical loop right now, worry about the proper fix second. Confirm the
storm has actually stopped (a clean single-copy result):
```bash
sudo ip netns exec h2 timeout 3 tcpdump -ni veth-h2 -nn arp > /tmp/storm2.log 2>/dev/null &
sleep 0.3
sudo ip netns exec h1 arping -c 1 -b -I veth-h1 10.0.0.2 >/dev/null 2>&1 || true
wait
wc -l /tmp/storm2.log
```

## Step 6 — The real fix: turn on STP and restore the redundant link
```bash
sudo ip link set sw1-b up
sudo ip link set sw1 type bridge stp_state 1
sudo ip link set sw2 type bridge stp_state 1
echo "waiting ~45s for STP to converge (default timers: hello 2s, forward delay 15s x2 phases)..."
sleep 45
```

## Step 7 — Verify STP actually blocked the redundant path
```bash
bridge link show
sudo brctl showstp sw1
sudo brctl showstp sw2
```
Across the four inter-switch ports (`sw1-a`, `sw1-b`, `sw2-a`, `sw2-b`),
exactly one now shows `state blocking` — the redundant path STP identified
and shut down at the logical layer, while the physical cable stays plugged
in and ready to take over if the active path fails.

## Step 8 — Prove the loop is now safe even though it still physically exists
```bash
sudo ip netns exec h1 ping -c 2 10.0.0.2

sudo ip netns exec h2 timeout 3 tcpdump -ni veth-h2 -nn arp > /tmp/storm3.log 2>/dev/null &
sleep 0.3
sudo ip netns exec h1 arping -c 1 -b -I veth-h1 10.0.0.2 >/dev/null 2>&1 || true
wait
wc -l /tmp/storm3.log
```
Back to exactly one copy arriving — same physical topology as Step 4, same
broadcast frame, but now there's a logically loop-free tree on top of it.

## Challenges

**Challenge A:**
```bash
sudo ip link add sw1-c type veth peer name sw2-c
sudo ip link set sw1-c master sw1
sudo ip link set sw2-c master sw2
sudo ip link set sw1-c up
sudo ip link set sw2-c up
```
A third redundant link goes in while STP is already running and converged.
Does this cause a storm while STP works out what to do with it, or does
something protect traffic during the transition? Give it ~45 seconds, then
check `bridge link show` and `brctl showstp sw1` before concluding
anything.

**Challenge B:**
```bash
sudo ip link set sw2 type bridge stp_state 0
```
STP gets disabled on `sw2` only — `sw1` is left running STP the whole
time. Re-run the bounded storm test from Step 4 against this state. This
looks like it should be safe ("at least one side is still running STP"),
but check the result before assuming that. Work out what a bridge with STP
off actually does with ordinary data frames arriving on more than one port
from the same neighbor, and why that's a different question from what it
does with the neighbor's BPDUs.

See `solution.md` only after you've formed your own diagnosis.
