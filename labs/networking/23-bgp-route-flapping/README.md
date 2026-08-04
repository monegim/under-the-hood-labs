# Lab 23 — BGP Route Flapping & Dampening

## Objective
Take the eBGP chain from Lab 7 and give it an unstable link instead of a
misconfiguration: watch a session go up and down repeatedly, watch that
instability propagate as repeated route withdrawals/advertisements to a
router that isn't even adjacent to the bad link, then apply BGP route
dampening to contain it — and see the real cost that mitigation carries.

## Why this matters
Lab 7 taught "Established" vs "routes actually advertised" as two
independent facts. This lab is about a third one: a session that goes
Established, drops, and re-establishes over and over doesn't just cost
you locally — every flap generates a fresh withdrawal and a fresh
advertisement that ripples to every router downstream, each one doing a
best-path recalculation it didn't need to do. Route dampening exists
specifically to stop a flapping link two hops away from making your entire
downstream routing table unstable — but it does this by intentionally
delaying route changes, which means it can also delay you finding out a
route is genuinely healthy again. That tradeoff is the entire point of
this lab.

## Prerequisites
- Docker + [containerlab](https://containerlab.dev) installed
- `quay.io/frrouting/frr` image pulled

Check first:
```bash
docker version
containerlab version
docker pull quay.io/frrouting/frr:latest
```

## Topology
```
r1 (AS 65001) --- r2 (AS 65002) --- r3 (AS 65003)
lo: 1.1.1.1/32     lo: 2.2.2.2/32     lo: 3.3.3.3/32
```
Same shape as Lab 7 (r1↔r2: `10.12.0.0/30`, r2↔r3: `10.23.0.0/30`) — this
lab is about what happens to that same chain when the r1↔r2 link itself is
unreliable, not about a config mistake.

## Step 1 — Deploy and address
```bash
sudo containerlab deploy -t topology.clab.yml
```
```bash
docker exec clab-bgp-flap-lab-r1 vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.12.0.1/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 1.1.1.1/32" \
  -c "end" \
  -c "write memory"

docker exec clab-bgp-flap-lab-r2 vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.12.0.2/30" \
  -c "exit" \
  -c "interface eth2" \
  -c "ip address 10.23.0.1/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 2.2.2.2/32" \
  -c "end" \
  -c "write memory"

docker exec clab-bgp-flap-lab-r3 vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.23.0.2/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 3.3.3.3/32" \
  -c "end" \
  -c "write memory"
```

## Step 2 — Configure eBGP peering
```bash
docker exec clab-bgp-flap-lab-r1 vtysh \
  -c "configure terminal" \
  -c "router bgp 65001" \
  -c "bgp router-id 1.1.1.1" \
  -c "neighbor 10.12.0.2 remote-as 65002" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "neighbor 10.12.0.2 activate" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"

docker exec clab-bgp-flap-lab-r2 vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "bgp router-id 2.2.2.2" \
  -c "neighbor 10.12.0.1 remote-as 65001" \
  -c "neighbor 10.23.0.2 remote-as 65003" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "neighbor 10.12.0.1 activate" \
  -c "neighbor 10.23.0.2 activate" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"

docker exec clab-bgp-flap-lab-r3 vtysh \
  -c "configure terminal" \
  -c "router bgp 65003" \
  -c "bgp router-id 3.3.3.3" \
  -c "neighbor 10.23.0.1 remote-as 65002" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "neighbor 10.23.0.1 activate" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"
```

## Step 3 — Verify the healthy baseline
```bash
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp summary"
docker exec clab-bgp-flap-lab-r3 vtysh -c "show ip route bgp"
docker exec clab-bgp-flap-lab-r3 ping -c 3 1.1.1.1
```
Both sessions Established, r3 has learned `1.1.1.1/32` via BGP, and can
reach it. Identical baseline to Lab 7 — the difference starts now.

## Step 4 — Start logging r3's view of the route in the background
```bash
( for i in $(seq 1 30); do
    ts=$(date +%T)
    state=$(docker exec clab-bgp-flap-lab-r3 vtysh -c "show ip route bgp" 2>/dev/null | grep -q "1.1.1.1" && echo "PRESENT" || echo "ABSENT")
    echo "$ts 1.1.1.1/32 on r3: $state"
    sleep 3
  done ) > /tmp/r3-route-log.txt &
```
Leave this running — it's just a passive observer polling r3 every 3
seconds for 90 seconds total.

## Step 5 — Simulate an unstable link
```bash
for i in $(seq 1 5); do
  echo "[flap $i] taking r1's link to r2 down"
  docker exec clab-bgp-flap-lab-r1 ip link set eth1 down
  sleep 5
  echo "[flap $i] bringing it back up"
  docker exec clab-bgp-flap-lab-r1 ip link set eth1 up
  sleep 10
done
```
This takes about 75 seconds — enough for `veth` carrier loss on `eth1` to
tear down the BGP session each time and let it re-establish once the link
returns (veth peers mirror each other's link state, so this is a faithful
stand-in for a flaky physical cable or a flapping optic on real hardware).

## Step 6 — Read the damage
```bash
cat /tmp/r3-route-log.txt
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp neighbor 10.12.0.1" | grep -i -E "state|connections"
```
The log shows `1.1.1.1/32` repeatedly going `PRESENT`/`ABSENT` on **r3** —
a router with no direct connection to the bad link at all — in lockstep
with r1's link toggling. `show bgp neighbor` on r2 shows the connection
counters climbing with every cycle. Every flap of a link two hops from r3
forced a full withdrawal and re-advertisement all the way down the chain.

## Step 7 — Apply dampening on r2
```bash
docker exec clab-bgp-flap-lab-r2 vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "address-family ipv4 unicast" \
  -c "bgp dampening 1 750 2000 1" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"
```
Parameters, in order: half-life 1 minute, reuse threshold 750, suppress
threshold 2000, max-suppress-time 1 minute. (Real deployments typically use
a 15-minute half-life — this lab uses 1 minute so you can watch the whole
lifecycle in a reasonable amount of time.) This tells r2: track every
flap of routes learned from r1 as a penalty, decaying with a 1-minute
half-life, and stop advertising a route to r3 once its accumulated penalty
crosses 2000.

## Step 8 — Flap the link again with dampening active
```bash
rm -f /tmp/r3-route-log2.txt
( for i in $(seq 1 30); do
    ts=$(date +%T)
    state=$(docker exec clab-bgp-flap-lab-r3 vtysh -c "show ip route bgp" 2>/dev/null | grep -q "1.1.1.1" && echo "PRESENT" || echo "ABSENT")
    echo "$ts 1.1.1.1/32 on r3: $state"
    sleep 3
  done ) > /tmp/r3-route-log2.txt &

for i in $(seq 1 5); do
  docker exec clab-bgp-flap-lab-r1 ip link set eth1 down
  sleep 5
  docker exec clab-bgp-flap-lab-r1 ip link set eth1 up
  sleep 10
done
```

## Step 9 — Compare the two logs
```bash
cat /tmp/r3-route-log2.txt
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp dampening dampened-paths"
```
This time `1.1.1.1/32` goes `ABSENT` on r3 once, early, and then **stays**
absent for the rest of the test — even during the several seconds in each
cycle where the r1↔r2 link is actually back up. `show bgp dampening
dampened-paths` on r2 shows `1.1.1.1/32` explicitly suppressed, with a
penalty value and a reuse time. r3 stopped seeing rapid flapping — at the
cost of not being able to reach `1.1.1.1` at all for a stretch, even during
moments the path was genuinely fine.

## Step 10 — Watch the tradeoff resolve
```bash
sleep 90
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp dampening dampened-paths"
docker exec clab-bgp-flap-lab-r3 vtysh -c "show ip route bgp"
```
Once the link has been stable long enough for the penalty to decay below
the reuse threshold, the route reappears on r3 on its own — with a
noticeable *delay* after the link actually became stable, not the instant
it did. That delay is dampening working exactly as designed, and it's also
the cost: **a legitimately recovered route doesn't get to prove itself
instantly** — it has to sit quiet for a while first.

## Challenges

**Challenge A:**
```bash
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp summary"
```
Run this any time after Step 7 while `1.1.1.1/32` is suppressed. The
session to r1 shows `Established` the whole time — dampening never touched
it. So what, specifically, is actually being withheld from r3, and where do
you have to look to see it, if not `show bgp summary`?

**Challenge B:**
```bash
docker exec clab-bgp-flap-lab-r2 vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "address-family ipv4 unicast" \
  -c "no bgp dampening 1 750 2000 1" \
  -c "bgp dampening 15 750 2000 60" \
  -c "exit-address-family" \
  -c "end"

docker exec clab-bgp-flap-lab-r1 ip link set eth1 down
sleep 5
docker exec clab-bgp-flap-lab-r1 ip link set eth1 up
```
(This uses realistic, production-typical dampening values — a 15-minute
half-life, 60-minute max-suppress-time — instead of Step 7's lab-scale
ones.) One single, brief flap — the kind a planned maintenance reboot
causes — now leads to `1.1.1.1/32` staying unreachable from r3 for a long
time relative to how long the actual problem lasted. Is this a bug in
dampening, or exactly what these numbers were configured to do? What
would you actually change, and is there a way to undo the current
suppression without waiting out the timer?

See `solution.md` only after you've formed your own diagnosis.
