# Lab 10 — Static Routing

## Objective
Wire two Linux hosts on different subnets together through two FRR routers
using nothing but static routes, and see exactly what breaks when a return
route is missing.

## Why this matters
Static routing is what you fall back to when you don't want (or can't run)
a routing protocol — VPN gateways, small branch offices, air-gapped
segments. It's also the fastest way to understand what a dynamic routing
protocol (Lab 13) automates for you: every static route you type by hand
here is a route OSPF would compute and install on its own.

## Prerequisites
- Docker
- containerlab (install: `bash -c "$(curl -sL https://get.containerlab.dev)"`
  — see https://containerlab.dev/install/ for other methods)
- `sudo` access

Check first:
```bash
docker version
containerlab version
```

## Step 1 — Deploy the topology
```bash
sudo containerlab deploy -t topology.clab.yml
sudo containerlab inspect -t topology.clab.yml
```
Topology: `host1 (10.0.1.0/24) — r1 — r2 — host2 (10.0.2.0/24)`, with an
`r1`–`r2` transit link on `10.0.12.0/30`.

## Step 2 — Address the hosts
```bash
docker exec clab-static-routing-host1 ip addr add 10.0.1.10/24 dev eth1
docker exec clab-static-routing-host1 ip link set eth1 up
docker exec clab-static-routing-host1 ip route add default via 10.0.1.1

docker exec clab-static-routing-host2 ip addr add 10.0.2.10/24 dev eth1
docker exec clab-static-routing-host2 ip link set eth1 up
docker exec clab-static-routing-host2 ip route add default via 10.0.2.1
```

## Step 3 — Address the routers
```bash
docker exec clab-static-routing-r1 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.1.1/24" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.12.1/30" -c "exit"

docker exec clab-static-routing-r2 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.12.2/30" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.2.1/24" -c "exit"
```
Confirm:
```bash
docker exec clab-static-routing-r1 vtysh -c "show interface brief"
```

## Step 4 — Static routes on both routers, both directions
```bash
docker exec clab-static-routing-r1 vtysh -c "conf t" -c "ip route 10.0.2.0/24 10.0.12.2"
docker exec clab-static-routing-r2 vtysh -c "conf t" -c "ip route 10.0.1.0/24 10.0.12.1"
```
> Gotcha: `ip route` in FRR needs the `staticd` daemon running. It's
> enabled by default in the FRR docker image alongside `zebra` — nothing to
> turn on for this lab (compare to Lab 13, where OSPF needs a daemon
> explicitly enabled first).

## Step 5 — Test end to end
```bash
docker exec clab-static-routing-host1 ping -c 3 10.0.2.10
docker exec clab-static-routing-r1 vtysh -c "show ip route"
```
Both directions work because every hop — host1, r1, r2, host2 — has a
route back to wherever the packet came from. Miss just one of those four
and you get the classic "ping works one way" symptom.

## Challenges

**Challenge A:**
```bash
docker exec clab-static-routing-r2 vtysh -c "conf t" -c "no ip route 10.0.1.0/24 10.0.12.1"
```
Check what happens to the ping from each end separately, and look at what's
actually arriving at `r2` with `tcpdump` on its interfaces before deciding
what's broken.

**Challenge B:**
```bash
docker exec clab-static-routing-r1 vtysh -c "conf t" \
  -c "no ip route 10.0.2.0/24 10.0.12.2" \
  -c "ip route 10.0.2.0/24 10.0.12.99"
```
The route to `10.0.2.0/24` still shows up in `show ip route` on r1 — it's a
valid-looking route to a next-hop that doesn't exist on the transit link.
Check `ip neigh` on r1 for `10.0.12.99` and compare that signature to what
you saw in Challenge A.

See `SOLUTION.md` only after you've formed your own diagnosis.
