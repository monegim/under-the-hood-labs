# Lab 9 — VXLAN

## Objective
Build a VXLAN overlay between two "VTEPs" so that two hosts on separate
physical underlay links appear to sit on one flat L2 network — the exact
mechanism behind Kubernetes CNI overlay backends (flannel's `vxlan`
backend, Calico's VXLAN mode) and most cloud/data-center overlay networks.

## Why this matters
VXLAN is how you get "one big L2 network" across L3 infrastructure that
doesn't actually support L2 anywhere. This lab deliberately builds VXLAN the
explicit way — static remote + manually programmed FDB entries — instead of
using multicast BUM flooding, because that's exactly how flannel's `vxlan`
backend actually works: a daemon on each node watches for peers and pushes
FDB/neighbor entries via netlink. When that state goes stale or a node
restarts without restoring it, you get precisely the "hosts can't reach
each other, VNI/tunnel looks fine" bug this lab reproduces.

## Prerequisites
- Docker + [containerlab](https://containerlab.dev) installed
- `debian:bookworm-slim` image pulled

Check first:
```bash
docker version
containerlab version
docker pull debian:bookworm-slim
```

## Topology
```
hostA (10.0.0.10/24) -- r1 -- [underlay 172.16.0.0/30] -- r2 -- hostB (10.0.0.20/24)
```
r1 and r2 act as VTEPs (VXLAN Tunnel Endpoints). hostA and hostB end up on
the same `10.0.0.0/24` broadcast domain despite being on different physical
segments.

## Step 1 — Deploy and install tools
```bash
sudo containerlab deploy -t topology.clab.yml

for n in hostA r1 r2 hostB; do
  docker exec clab-vxlan-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump >/dev/null"
done
```

## Step 2 — Address the underlay and the hosts
```bash
docker exec clab-vxlan-lab-r1 ip addr add 172.16.0.1/30 dev eth2
docker exec clab-vxlan-lab-r1 ip link set eth2 up

docker exec clab-vxlan-lab-r2 ip addr add 172.16.0.2/30 dev eth1
docker exec clab-vxlan-lab-r2 ip link set eth1 up

docker exec clab-vxlan-lab-hostA ip addr add 10.0.0.10/24 dev eth1
docker exec clab-vxlan-lab-hostA ip link set eth1 up

docker exec clab-vxlan-lab-hostB ip addr add 10.0.0.20/24 dev eth1
docker exec clab-vxlan-lab-hostB ip link set eth1 up
```
Verify the underlay before building the overlay:
```bash
docker exec clab-vxlan-lab-r1 ping -c 3 172.16.0.2
```
> Note: hostA and hostB get no default gateway — this is a pure L2
> overlay, there's no routing involved once VXLAN is up.

## Step 3 — Create the VXLAN interfaces (no default `remote`)
```bash
docker exec clab-vxlan-lab-r1 ip link add vxlan10 type vxlan id 10 dstport 4789 local 172.16.0.1 dev eth2
docker exec clab-vxlan-lab-r1 ip link set vxlan10 up

docker exec clab-vxlan-lab-r2 ip link add vxlan10 type vxlan id 10 dstport 4789 local 172.16.0.2 dev eth1
docker exec clab-vxlan-lab-r2 ip link set vxlan10 up
```
> Gotcha: we deliberately left out `remote` on the `vxlan10` device itself.
> With no default remote, the kernel has nowhere to send unknown-unicast,
> broadcast, or multicast (BUM) traffic — including ARP — until you tell it
> explicitly with an FDB entry. That's the next step.

## Step 4 — Program the FDB (this is what flannel's daemon does for you)
```bash
docker exec clab-vxlan-lab-r1 bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.2
docker exec clab-vxlan-lab-r2 bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.1
```
The all-zeros MAC is the wildcard entry: "for anything I don't have a
specific MAC entry for (including broadcast/ARP), flood it to this VTEP."

## Step 5 — Bridge the VXLAN interface to the local host-facing link
```bash
docker exec clab-vxlan-lab-r1 ip link add br0 type bridge
docker exec clab-vxlan-lab-r1 ip link set br0 up
docker exec clab-vxlan-lab-r1 ip link set eth1 master br0
docker exec clab-vxlan-lab-r1 ip link set eth1 up
docker exec clab-vxlan-lab-r1 ip link set vxlan10 master br0

docker exec clab-vxlan-lab-r2 ip link add br0 type bridge
docker exec clab-vxlan-lab-r2 ip link set br0 up
docker exec clab-vxlan-lab-r2 ip link set eth2 master br0
docker exec clab-vxlan-lab-r2 ip link set eth2 up
docker exec clab-vxlan-lab-r2 ip link set vxlan10 master br0
```

## Step 6 — Test it
```bash
docker exec clab-vxlan-lab-hostA ping -c 3 10.0.0.20
```
Confirm what's actually happening on the wire — the underlay link should
show VXLAN (UDP port 4789), and inside it a plain ARP/ICMP frame:
```bash
docker exec clab-vxlan-lab-r1 tcpdump -ni eth2 -c 5 udp port 4789
```

## Challenges

**Challenge A:**
```bash
docker exec clab-vxlan-lab-r2 ip link set vxlan10 nomaster
docker exec clab-vxlan-lab-r2 ip link set vxlan10 down
docker exec clab-vxlan-lab-r2 ip link del vxlan10
docker exec clab-vxlan-lab-r2 ip link add vxlan10 type vxlan id 20 dstport 4789 local 172.16.0.2 dev eth1
docker exec clab-vxlan-lab-r2 ip link set vxlan10 up
docker exec clab-vxlan-lab-r2 bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.1
docker exec clab-vxlan-lab-r2 ip link set vxlan10 master br0
```
hostA can no longer reach hostB. Capture on r1's underlay interface (`eth2`)
*and* check `ip -s -d link show vxlan10` on r2 before deciding what's wrong
— compare what leaves r1 against what actually shows up as decapsulated
traffic on r2's `vxlan10`.

**Challenge B:**
```bash
docker exec clab-vxlan-lab-r1 bridge fdb del 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.2
```
This also breaks hostA-to-hostB connectivity, but capture on r1's
underlay interface first — compare what you see leaving r1 in this case
versus Challenge A, before you touch anything.

See `SOLUTION.md` only after you've formed your own diagnosis.
