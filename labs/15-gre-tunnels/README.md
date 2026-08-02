# Lab 15 — GRE Tunnels

## Objective
Build a GRE tunnel between two routers over an underlay network, and route
traffic between two "overlay" LANs through it — the same basic mechanism
behind site-to-site VPNs, `ip tunnel` based mesh networks, and a good chunk
of what a cloud provider's virtual network is doing under the covers.

## Why this matters
GRE is the simplest real IP-in-IP encapsulation you'll touch in production:
it shows up as the transport for a lot of legacy site-to-site VPNs, as a
building block inside IPsec (GRE-over-IPsec for routing protocols across a
tunnel), and conceptually it's the ancestor of VXLAN (lab 16) and every
other overlay tunneling tech. If you understand "an interface that
encapsulates whatever IP packet gets routed into it and ships it to a
remote endpoint," you understand the shape of nearly every tunnel
technology you'll meet.

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
hostA (10.1.1.10/24) -- r1 -- [underlay 172.16.0.0/30] -- r2 -- hostB (10.2.2.10/24)
```
r1 and r2 are the GRE tunnel endpoints. hostA/hostB are the "overlay" LANs
the tunnel exists to connect.

## Step 1 — Deploy and install tools
```bash
sudo containerlab deploy -t topology.clab.yml

for n in hostA r1 r2 hostB; do
  docker exec clab-gre-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump >/dev/null"
done
```

## Step 2 — Address the interfaces
```bash
docker exec clab-gre-lab-hostA ip addr add 10.1.1.10/24 dev eth1
docker exec clab-gre-lab-hostA ip link set eth1 up
docker exec clab-gre-lab-hostA ip route add default via 10.1.1.1

docker exec clab-gre-lab-r1 ip addr add 10.1.1.1/24 dev eth1
docker exec clab-gre-lab-r1 ip link set eth1 up
docker exec clab-gre-lab-r1 ip addr add 172.16.0.1/30 dev eth2
docker exec clab-gre-lab-r1 ip link set eth2 up

docker exec clab-gre-lab-r2 ip addr add 172.16.0.2/30 dev eth1
docker exec clab-gre-lab-r2 ip link set eth1 up
docker exec clab-gre-lab-r2 ip addr add 10.2.2.1/24 dev eth2
docker exec clab-gre-lab-r2 ip link set eth2 up

docker exec clab-gre-lab-hostB ip addr add 10.2.2.10/24 dev eth1
docker exec clab-gre-lab-hostB ip link set eth1 up
docker exec clab-gre-lab-hostB ip route add default via 10.2.2.1
```

Verify the underlay works before building anything on top of it:
```bash
docker exec clab-gre-lab-r1 ping -c 3 172.16.0.2
```

## Step 3 — Enable forwarding on the tunnel endpoints
```bash
docker exec clab-gre-lab-r1 sysctl -w net.ipv4.ip_forward=1
docker exec clab-gre-lab-r2 sysctl -w net.ipv4.ip_forward=1
```
> Gotcha: this is the single most common reason a tunnel "doesn't work" on
> the first try — the encapsulation is fine, but the kernel on the endpoint
> was never told to forward packets between interfaces at all.

## Step 4 — Build the GRE tunnel
```bash
docker exec clab-gre-lab-r1 ip tunnel add gre1 mode gre remote 172.16.0.2 local 172.16.0.1 ttl 255
docker exec clab-gre-lab-r1 ip addr add 192.168.100.1/30 dev gre1
docker exec clab-gre-lab-r1 ip link set gre1 up

docker exec clab-gre-lab-r2 ip tunnel add gre1 mode gre remote 172.16.0.1 local 172.16.0.2 ttl 255
docker exec clab-gre-lab-r2 ip addr add 192.168.100.2/30 dev gre1
docker exec clab-gre-lab-r2 ip link set gre1 up
```
Verify the tunnel itself (endpoint to endpoint, before routing anything
through it):
```bash
docker exec clab-gre-lab-r1 ping -c 3 192.168.100.2
```
> Gotcha: `ip link show gre1` will report the tunnel `mtu` as roughly 1476,
> not 1500 — GRE adds 24 bytes of overhead (20-byte outer IPv4 header +
> 4-byte GRE header). This is the setup for lab 18.

## Step 5 — Route the overlay subnets through the tunnel
```bash
docker exec clab-gre-lab-r1 ip route add 10.2.2.0/24 via 192.168.100.2 dev gre1
docker exec clab-gre-lab-r2 ip route add 10.1.1.0/24 via 192.168.100.1 dev gre1
```

## Step 6 — Test end to end
```bash
docker exec clab-gre-lab-hostA ping -c 3 10.2.2.10
```
Confirm what's actually on the wire — the underlay link should show GRE
(IP protocol 47), not plain ICMP:
```bash
docker exec clab-gre-lab-r1 tcpdump -ni eth2 -c 5 proto gre
```

## Challenges

**Challenge A:**
```bash
docker exec clab-gre-lab-r1 ip tunnel change gre1 remote 172.16.0.99
```
hostA can no longer reach hostB. Check `ip -d tunnel show gre1` and `ip
link show gre1` on r1 before you touch anything — notice what state the
interface reports itself as. Fix it.

**Challenge B:**
```bash
docker exec clab-gre-lab-r2 ip route del 10.1.1.0/24
```
This also breaks connectivity between hostA and hostB, but the failure
looks and behaves differently from Challenge A. Use `ping` and a capture on
both r1 and r2 to figure out exactly where each of these two breaks
actually happens before you fix either one.

See `SOLUTION.md` only after you've formed your own diagnosis.
