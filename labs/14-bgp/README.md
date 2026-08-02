# Lab 14 — BGP

## Objective
Stand up three FRR routers in three different Autonomous Systems, peer them
with eBGP, and prove routes are actually being learned via BGP — not just
that the session is up.

## Why this matters
Every "the internet" your traffic crosses is a mesh of BGP sessions between
ASes. Inside a data center, BGP is also how Kubernetes CNIs like Calico (in
BGP mode) and top-of-rack switches exchange routes, and it's the control
plane behind anycast VIPs. "The BGP session is Established" and "the route
I expect is actually being advertised" are two completely different facts —
conflating them is one of the most common real-world BGP troubleshooting
mistakes, and this lab is built specifically to make you feel that
difference.

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
r1↔r2 link: 10.12.0.0/30. r2↔r3 link: 10.23.0.0/30. Each router's loopback
stands in for a "customer network" that AS is originating.

## Step 1 — Deploy the topology
```bash
sudo containerlab deploy -t topology.clab.yml
containerlab inspect -t topology.clab.yml
```
> Gotcha: the custom `/etc/frr/daemons` bind mount is what turns `bgpd` on —
> the stock FRR image ships with only `zebra`/`staticd` enabled. If `vtysh`
> says `bgpd` isn't running, check this file landed correctly.

## Step 2 — Address the interfaces
Everything below goes through `vtysh` on each node (`docker exec -it
clab-bgp-lab-r1 vtysh`), or non-interactively with repeated `-c`:

```bash
docker exec clab-bgp-lab-r1 vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.12.0.1/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 1.1.1.1/32" \
  -c "end" \
  -c "write memory"

docker exec clab-bgp-lab-r2 vtysh \
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

docker exec clab-bgp-lab-r3 vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.23.0.2/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 3.3.3.3/32" \
  -c "end" \
  -c "write memory"
```

Verify layer 3 works before touching BGP at all:
```bash
docker exec clab-bgp-lab-r1 ping -c 3 10.12.0.2
docker exec clab-bgp-lab-r2 ping -c 3 10.23.0.2
```

## Step 3 — Configure eBGP peering
```bash
docker exec clab-bgp-lab-r1 vtysh \
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

docker exec clab-bgp-lab-r2 vtysh \
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

docker exec clab-bgp-lab-r3 vtysh \
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
> Gotcha: `redistribute connected` is what pushes each router's own directly
> connected networks (here, its loopback) into BGP. Without it, a session
> can be perfectly Established and still advertise nothing of yours — this
> is exactly what Challenge B is about.

## Step 4 — Verify the session
```bash
docker exec clab-bgp-lab-r2 vtysh -c "show bgp summary"
```
Both neighbors should show state `Established` (a numeric "up time" in that
column, not a state name, also means Established).

## Step 5 — Verify routes are actually learned
```bash
docker exec clab-bgp-lab-r3 vtysh -c "show bgp ipv4 unicast"
docker exec clab-bgp-lab-r3 vtysh -c "show ip route bgp"
```
r3 should show `1.1.1.1/32` learned via BGP, next-hop `10.23.0.1` (r2) — a
route r3 never directly connects to, propagated across an AS it doesn't
peer with, purely through r2 re-advertising what it learned from r1 (normal
eBGP behavior — no split-horizon between different eBGP peers).

```bash
docker exec clab-bgp-lab-r3 ping -c 3 1.1.1.1
```

## Challenges

**Challenge A:**
```bash
docker exec clab-bgp-lab-r2 vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "neighbor 10.12.0.1 remote-as 65099"
```
The r1↔r2 session drops. Check `show bgp summary` and `show bgp neighbor
10.12.0.1` on both sides before concluding anything — the neighbor state
column and the log line telling you *why* it's not Established are both
important. Fix it.

**Challenge B:**
```bash
docker exec clab-bgp-lab-r1 vtysh \
  -c "configure terminal" \
  -c "router bgp 65001" \
  -c "address-family ipv4 unicast" \
  -c "no redistribute connected"
```
The session stays Established (check it — really check it). r3 can no
longer reach `1.1.1.1`. This looks like it should be the same kind of
problem as Challenge A but it isn't — figure out what evidence tells you
these are two different failure classes before you fix it.

See `SOLUTION.md` only after you've formed your own diagnosis.
