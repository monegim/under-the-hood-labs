# Lab 6 — OSPF

## Objective
Run OSPF across three FRR routers, watch routes to two stub networks get
installed automatically with zero static routes, then break one adjacency
on purpose and diagnose exactly why.

## Why this matters
Static routing (Lab 3) doesn't scale — every route addition or removal is
a manual, error-prone edit on every router. OSPF is what real networks use
instead: routers discover neighbors, exchange topology, and compute routes
themselves. Almost every "why won't these two routers peer" incident in
production networking comes down to one of the handful of adjacency
requirements you'll break here on purpose.

## Prerequisites
- Docker
- containerlab
- `sudo` access

Check first:
```bash
docker version
containerlab version
```

## Step 1 — Deploy the topology
```bash
sudo containerlab deploy -t topology.clab.yml
```
Topology: `host1 (10.0.1.0/24) — r1 — r2 — r3 — host2 (10.0.3.0/24)`,
transit links `10.0.12.0/30` (r1-r2) and `10.0.23.0/30` (r2-r3). Linear on
purpose — no redundant path, so a broken adjacency partitions the network
cleanly instead of quietly rerouting around it.

## Step 2 — Enable OSPF on each router
`ospfd` is disabled by default in the FRR docker image (only `zebra` and
`staticd` run out of the box). Turn it on:
```bash
for r in r1 r2 r3; do
  docker exec clab-ospf-$r sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
  docker exec clab-ospf-$r /usr/lib/frr/frrinit.sh restart
done
```
> Double-check this against your actual FRR image version before relying
> on it in a demo — the daemons-file/restart-script mechanism has been
> stable across FRR docker releases, but exact paths can move between
> versions.

## Step 3 — Address hosts and stub-facing router interfaces
```bash
docker exec clab-ospf-host1 ip addr add 10.0.1.10/24 dev eth1
docker exec clab-ospf-host1 ip link set eth1 up
docker exec clab-ospf-host1 ip route add default via 10.0.1.1

docker exec clab-ospf-host2 ip addr add 10.0.3.10/24 dev eth1
docker exec clab-ospf-host2 ip link set eth1 up
docker exec clab-ospf-host2 ip route add default via 10.0.3.1
```

## Step 4 — Configure interfaces and OSPF on the routers
```bash
docker exec clab-ospf-r1 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.1.1/24" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.12.1/30" -c "exit" \
  -c "router ospf" -c "ospf router-id 1.1.1.1" \
  -c "network 10.0.1.0/24 area 0" -c "network 10.0.12.0/30 area 0"

docker exec clab-ospf-r2 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.12.2/30" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.23.1/30" -c "exit" \
  -c "router ospf" -c "ospf router-id 2.2.2.2" \
  -c "network 10.0.12.0/30 area 0" -c "network 10.0.23.0/30 area 0"

docker exec clab-ospf-r3 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.23.2/30" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.3.1/24" -c "exit" \
  -c "router ospf" -c "ospf router-id 3.3.3.3" \
  -c "network 10.0.23.0/30 area 0" -c "network 10.0.3.0/24 area 0"
```

## Step 5 — Verify adjacencies and route propagation
```bash
docker exec clab-ospf-r2 vtysh -c "show ip ospf neighbor"
docker exec clab-ospf-r1 vtysh -c "show ip route ospf"
docker exec clab-ospf-r3 vtysh -c "show ip route ospf"
```
`r1` should have a learned route to `10.0.3.0/24` via `r2` — nobody typed
that route anywhere. Confirm end to end:
```bash
docker exec clab-ospf-host1 ping -c 3 10.0.3.10
```

## Challenges

**Challenge A:**
```bash
docker exec clab-ospf-r3 vtysh -c "conf t" -c "router ospf" \
  -c "no network 10.0.23.0/30 area 0" -c "network 10.0.23.0/30 area 1"
```
`show ip ospf neighbor` on `r2` loses the `r3` adjacency. `r1 <-> r2` is
unaffected. Check both routers' OSPF interface state, not just the
neighbor table.

**Challenge B:**
```bash
docker exec clab-ospf-r2 vtysh -c "conf t" -c "interface eth2" -c "ip ospf hello-interval 5"
```
This looks smaller/harmless — just a timer tweak on one side. The
`r2 <-> r3` adjacency breaks anyway. Figure out what OSPF requires to
match between neighbors before it will even try to become friends, and why
changing it on only one side is worse than not touching it at all.

See `SOLUTION.md` only after you've formed your own diagnosis.
