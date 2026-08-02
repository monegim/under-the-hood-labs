# Lab 18 — MTU Issues

## Objective
Build a GRE tunnel, observe Path MTU Discovery (PMTUD) working correctly,
then reproduce the classic real-world outage where it silently stops
working — because something on the path is dropping the ICMP message that
makes PMTUD work at all.

## Why this matters
"Small packets work, large packets just vanish" is one of the most common
and most misdiagnosed production networking symptoms — it shows up behind
GRE/VXLAN/IPsec tunnels, VPNs, and any path with an MTU smaller than 1500
somewhere in the middle (a very common real case: cloud provider overlay
networks, MPLS providers, DSL/PPPoE links). PMTUD is supposed to handle
this transparently. It only works if ICMP "fragmentation needed" packets
can get back to the sender — and a huge number of "hardened" firewalls
block exactly that ICMP type by default, which is the real production
outage this lab reproduces.

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
hostA (10.1.1.10/24) -- r1 -- [underlay 172.16.0.0/30, mtu 1500] -- r2 -- hostB (10.2.2.10/24)
```
Same shape as lab 15 — a GRE tunnel between r1 and r2 carrying traffic
between two overlay LANs.

## Step 1 — Deploy, install tools, address, and enable forwarding
```bash
sudo containerlab deploy -t topology.clab.yml

for n in hostA r1 r2 hostB; do
  docker exec clab-mtu-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iptables >/dev/null"
done

docker exec clab-mtu-lab-hostA ip addr add 10.1.1.10/24 dev eth1
docker exec clab-mtu-lab-hostA ip link set eth1 up
docker exec clab-mtu-lab-hostA ip route add default via 10.1.1.1

docker exec clab-mtu-lab-r1 ip addr add 10.1.1.1/24 dev eth1
docker exec clab-mtu-lab-r1 ip link set eth1 up
docker exec clab-mtu-lab-r1 ip addr add 172.16.0.1/30 dev eth2
docker exec clab-mtu-lab-r1 ip link set eth2 up
docker exec clab-mtu-lab-r1 sysctl -w net.ipv4.ip_forward=1

docker exec clab-mtu-lab-r2 ip addr add 172.16.0.2/30 dev eth1
docker exec clab-mtu-lab-r2 ip link set eth1 up
docker exec clab-mtu-lab-r2 ip addr add 10.2.2.1/24 dev eth2
docker exec clab-mtu-lab-r2 ip link set eth2 up
docker exec clab-mtu-lab-r2 sysctl -w net.ipv4.ip_forward=1

docker exec clab-mtu-lab-hostB ip addr add 10.2.2.10/24 dev eth1
docker exec clab-mtu-lab-hostB ip link set eth1 up
docker exec clab-mtu-lab-hostB ip route add default via 10.2.2.1
```

## Step 2 — Build the GRE tunnel
```bash
docker exec clab-mtu-lab-r1 ip tunnel add gre1 mode gre remote 172.16.0.2 local 172.16.0.1 ttl 255
docker exec clab-mtu-lab-r1 ip addr add 192.168.100.1/30 dev gre1
docker exec clab-mtu-lab-r1 ip link set gre1 up
docker exec clab-mtu-lab-r1 ip route add 10.2.2.0/24 via 192.168.100.2 dev gre1

docker exec clab-mtu-lab-r2 ip tunnel add gre1 mode gre remote 172.16.0.1 local 172.16.0.2 ttl 255
docker exec clab-mtu-lab-r2 ip addr add 192.168.100.2/30 dev gre1
docker exec clab-mtu-lab-r2 ip link set gre1 up
docker exec clab-mtu-lab-r2 ip route add 10.1.1.0/24 via 192.168.100.1 dev gre1
```
Check the tunnel's own MTU:
```bash
docker exec clab-mtu-lab-r1 ip link show gre1
```
> Note the `mtu 1476`, not 1500. GRE adds 24 bytes of overhead (20-byte
> outer IPv4 header + 4-byte GRE header) — the kernel already accounts for
> this when it created the tunnel on top of a 1500-byte underlay.

## Step 3 — Confirm the underlay path first
```bash
docker exec clab-mtu-lab-hostA ping -c 3 10.2.2.10
```

## Step 4 — Watch PMTUD work correctly
A ping payload of 1448 bytes plus the 8-byte ICMP header and 20-byte IP
header adds up to exactly 1476 — it fits the tunnel's MTU with nothing to
spare:
```bash
docker exec clab-mtu-lab-hostA ping -M do -s 1448 -c 3 10.2.2.10
```
This should succeed cleanly. Now go one byte over:
```bash
docker exec clab-mtu-lab-hostA ping -M do -s 1449 -c 3 10.2.2.10
```
You should see `ping` itself report something like `Frag needed and DF set
(mtu = 1476)` — hostA is being told directly, in real time, that this
packet is too big for a link on the path, and exactly what size *would*
fit. This is PMTUD working exactly as designed.

## Challenges

**Challenge A:**
```bash
docker exec clab-mtu-lab-r1 iptables -A OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP
```
Run the exact same oversized ping from Step 4 again:
```bash
docker exec clab-mtu-lab-hostA ping -M do -s 1449 -c 3 10.2.2.10
```
Compare what you see now against what you saw in Step 4 — same command,
same packet size, very different behavior. Use `tcpdump` on hostA and on
r1 to work out exactly what's different before you fix it.

**Challenge B:**
```bash
docker exec clab-mtu-lab-r1 ip link set eth2 mtu 1400
docker exec clab-mtu-lab-r2 ip link set eth1 mtu 1400
```
This simulates the underlay's MTU shrinking after the tunnel was already
built (e.g. a provider migrating you to a lower-MTU transit link). Re-run
the Step 4 ping that used to work fine:
```bash
docker exec clab-mtu-lab-hostA ping -M do -s 1448 -c 3 10.2.2.10
```
Check `ip link show gre1` on both r1 and r2 before deciding what's going on
— compare the tunnel's reported MTU against what the underlay interface
actually reports now.

See `SOLUTION.md` only after you've formed your own diagnosis.
