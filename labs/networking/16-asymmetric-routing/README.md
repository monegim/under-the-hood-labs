# Lab 16 — Asymmetric Routing

## Objective
Build a topology where two routers both connect the same two subnets,
force the forward and return paths onto two *different* routers, and
watch a stateful firewall on the return-path router break TCP completely
while ICMP keeps working perfectly the whole time.

## Why this matters
This is a genuinely different failure mode from every other lab in this
series. Every other broken-firewall or broken-routing lab here has one
consistent path between two hosts. Real networks — especially anything
with redundant routers, ECMP, or two independent uplinks — routinely send
a connection's request one way and its reply another way, and *that's
normal and fine on its own*. It only becomes an outage the moment a
stateful device (a firewall, a NAT gateway, a load balancer doing
connection tracking) sits on just one of those two paths, because a
stateful device can only make sense of traffic if it sees *both* directions
of the same flow. "Ping works, TCP doesn't" is the signature of exactly
this problem, and this lab exists to make that signature unmistakable.

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
                    +-- r1 --+
                   /          \
client -- switch-a              switch-b -- server
                   \          /
                    +-- r2 --+
```
`switch-a` and `switch-b` are plain Linux bridges (the exact mechanism
from Lab 1, running inside their own containerlab node with three ports
enslaved to it) — that's what lets both `r1` and `r2` sit on `client`'s
subnet *and* on `server`'s subnet at the same time, exactly like two
routers both plugged into the same access switch on each side of a real
network. `client` and `server` each have a single NIC and a single IP;
which router carries their traffic is purely a matter of which one their
routing table points at.

## Step 1 — Deploy and build the two bridges
```bash
sudo containerlab deploy -t topology.clab.yml

for n in client switch-a r1 r2 switch-b server; do
  docker exec clab-asym-routing-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iptables conntrack python3 curl procps >/dev/null"
done

docker exec clab-asym-routing-switch-a bash -c "
  ip link add name br0 type bridge
  ip link set br0 up
  ip link set eth1 master br0
  ip link set eth2 master br0
  ip link set eth3 master br0
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
"

docker exec clab-asym-routing-switch-b bash -c "
  ip link add name br0 type bridge
  ip link set br0 up
  ip link set eth1 master br0
  ip link set eth2 master br0
  ip link set eth3 master br0
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
"
```
`switch-a`/`switch-b` never get an IP of their own — they're pure L2,
exactly like `br0` in Lab 1.

## Step 2 — Address everyone and turn r1/r2 into routers
```bash
docker exec clab-asym-routing-client ip addr add 10.0.1.10/24 dev eth1
docker exec clab-asym-routing-client ip link set eth1 up

docker exec clab-asym-routing-r1 ip addr add 10.0.1.1/24 dev eth1
docker exec clab-asym-routing-r1 ip link set eth1 up
docker exec clab-asym-routing-r1 ip addr add 10.0.2.1/24 dev eth2
docker exec clab-asym-routing-r1 ip link set eth2 up
docker exec clab-asym-routing-r1 sysctl -w net.ipv4.ip_forward=1

docker exec clab-asym-routing-r2 ip addr add 10.0.1.2/24 dev eth1
docker exec clab-asym-routing-r2 ip link set eth1 up
docker exec clab-asym-routing-r2 ip addr add 10.0.2.2/24 dev eth2
docker exec clab-asym-routing-r2 ip link set eth2 up
docker exec clab-asym-routing-r2 sysctl -w net.ipv4.ip_forward=1

docker exec clab-asym-routing-server ip addr add 10.0.2.10/24 dev eth1
docker exec clab-asym-routing-server ip link set eth1 up
```
`r1` and `r2` are both directly connected to *both* subnets (`10.0.1.0/24`
via `switch-a`, `10.0.2.0/24` via `switch-b`) — either one, alone, is a
perfectly complete path between `client` and `server`.

## Step 3 — Symmetric baseline: everything via r1
```bash
docker exec clab-asym-routing-client ip route add 10.0.2.0/24 via 10.0.1.1 dev eth1
docker exec clab-asym-routing-server ip route add 10.0.1.0/24 via 10.0.2.1 dev eth1

docker exec clab-asym-routing-client ping -c 3 10.0.2.10
docker exec -d clab-asym-routing-server python3 -m http.server 8080 --bind 0.0.0.0
docker exec clab-asym-routing-client curl -sv --max-time 5 http://10.0.2.10:8080/ -o /dev/null
```
Both directions go through `r1`. Ping and a real HTTP request both work —
a completely ordinary, symmetric path.

## Step 4 — Make it asymmetric (still no firewall — prove this alone is harmless)
```bash
docker exec clab-asym-routing-server ip route replace 10.0.1.0/24 via 10.0.2.2 dev eth1
```
Now the request goes `client -> r1 -> server`, but the reply comes back
`server -> r2 -> client` — genuinely different routers, genuinely
different paths.
```bash
docker exec clab-asym-routing-client ping -c 3 10.0.2.10
docker exec clab-asym-routing-client curl -sv --max-time 5 http://10.0.2.10:8080/ -o /dev/null
```
Both still succeed. **Asymmetric routing by itself breaks nothing** —
`r2` is currently just as permissive a router as `r1` is. Keep this result
in mind; it's the baseline the rest of this lab pushes against.

## Step 5 — Add a stateful firewall to r2 and watch it break
```bash
docker exec clab-asym-routing-r2 iptables -P FORWARD DROP
docker exec clab-asym-routing-r2 iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
docker exec clab-asym-routing-r2 iptables -A FORWARD -p icmp -j ACCEPT
docker exec clab-asym-routing-r2 sysctl -w net.netfilter.nf_conntrack_tcp_loose=0
```
> `nf_conntrack_tcp_loose=0` tells conntrack to *not* charitably adopt a
> connection it never saw the start of — some kernels default this to a
> looser setting that would mask exactly the bug this lab is built to
> show. Setting it explicitly makes the result deterministic regardless
> of what your kernel happens to default to.

Now retest both:
```bash
docker exec clab-asym-routing-client ping -c 3 10.0.2.10
docker exec clab-asym-routing-client curl -sv --max-time 8 http://10.0.2.10:8080/ -o /dev/null
```
Ping still succeeds — ICMP is explicitly allowed regardless of state. The
`curl` hangs and times out. Prove it to yourself with captures on both
routers before reading the diagnosis:
```bash
docker exec clab-asym-routing-r1 tcpdump -ni eth2 -c 4 tcp port 8080 &
docker exec clab-asym-routing-r2 tcpdump -ni eth2 -c 4 tcp port 8080 &
docker exec clab-asym-routing-client curl -sv --max-time 8 http://10.0.2.10:8080/ -o /dev/null
```
`r1`'s server-facing interface shows the SYN going out fine. `r2`'s
server-facing interface shows the SYN-ACK coming back from the server —
but it never reaches `r2`'s client-facing interface, and it certainly
never reaches `client`.

## Step 6 — Restore the healthy state
```bash
docker exec clab-asym-routing-server ip route replace 10.0.1.0/24 via 10.0.2.1 dev eth1
```
Routing is symmetric again (everything via `r1`), so `r2`'s firewall
never sees this traffic at all. This is the healthy state the rest of
this lab starts back from.
```bash
docker exec clab-asym-routing-client curl -sv --max-time 5 http://10.0.2.10:8080/ -o /dev/null
```

## Challenges

**Challenge A:**
```bash
docker exec clab-asym-routing-server ip route replace 10.0.1.0/24 via 10.0.2.2 dev eth1
```
This recreates Step 4/5's asymmetry against `r2`'s firewall, which is
still configured from Step 5. Diagnose it yourself this time — captures
on `r1`, `r2`, and `client` — before reading the solution.

**Challenge B:**
```bash
docker exec clab-asym-routing-r2 iptables -P FORWARD ACCEPT
docker exec clab-asym-routing-r2 iptables -F FORWARD
docker exec clab-asym-routing-r1 iptables -P FORWARD DROP
docker exec clab-asym-routing-r1 iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
docker exec clab-asym-routing-r1 iptables -A FORWARD -p icmp -j ACCEPT
```
The firewall has effectively moved from `r2` to `r1` — same ruleset,
different box — while the routing asymmetry from Challenge A is still in
place (`client` -> `server` via `r1`, `server` -> `client` via `r2`).
```bash
docker exec clab-asym-routing-client ping -c 3 10.0.2.10
docker exec clab-asym-routing-client curl -sv --max-time 8 http://10.0.2.10:8080/ -o /dev/null
```
Ping still works. `curl` still fails — but capture on `r1`'s *server-
facing* interface this time, alongside `r2`, and compare exactly what got
through and what didn't against Challenge A. The blocked leg is not the
same leg as last time.

See `solution.md` only after you've formed your own diagnosis.
