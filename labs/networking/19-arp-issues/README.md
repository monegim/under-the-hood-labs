# Lab 19 — ARP Issues

## Objective
Move a virtual IP between two hosts on the same segment, watch a
gratuitous ARP update every neighbor's cache instantly and correctly, then
reproduce two different ways that safety mechanism fails: one where it
never fires, and one where the old owner never actually lets go.

## Why this matters
Layer 3 routing can be completely correct — right subnet, right prefix,
right gateway — and a host can still be unreachable, because the last
step of getting a packet onto the wire depends on Layer 2: mapping an IP
to a MAC address. A stale ARP cache entry after a failover, a replaced
NIC, or a VIP moving to a new box is one of the most common "everything
looks right but it doesn't work" bugs on a local segment, and it's
invisible to anyone only checking routes.

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
client -- switch -- server-a
              \
               -- server-b
```
`switch` is a plain Linux bridge (Lab 1's technique, running inside its
own containerlab node with three ports enslaved to it) — `client`,
`server-a`, and `server-b` all share one broadcast domain, `10.0.0.0/24`.
`server-a` and `server-b` are a manually-operated stand-in for an
active/standby pair (what `keepalived`/VRRP automate in production) —
one of them holds a shared virtual IP, `10.0.0.100`, at any given time.

## Step 1 — Deploy and build the switch
```bash
sudo containerlab deploy -t topology.clab.yml

for n in client switch server-a server-b; do
  docker exec clab-arp-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping iputils-arping >/dev/null"
done

docker exec clab-arp-lab-switch bash -c "
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

## Step 2 — Address everyone, VIP on server-a
```bash
docker exec clab-arp-lab-client ip addr add 10.0.0.10/24 dev eth1
docker exec clab-arp-lab-client ip link set eth1 up

docker exec clab-arp-lab-server-a ip addr add 10.0.0.20/24 dev eth1
docker exec clab-arp-lab-server-a ip link set eth1 up
docker exec clab-arp-lab-server-a ip addr add 10.0.0.100/24 dev eth1

docker exec clab-arp-lab-server-b ip addr add 10.0.0.21/24 dev eth1
docker exec clab-arp-lab-server-b ip link set eth1 up
```
`server-a` holds both its own identity address (`10.0.0.20`) and the
shared VIP (`10.0.0.100`). `server-b` only has its own identity for now.

## Step 3 — Resolve the VIP and see it cached
```bash
docker exec clab-arp-lab-client ping -c 3 10.0.0.100
docker exec clab-arp-lab-client ip neigh show 10.0.0.100
```
`ip neigh` shows `10.0.0.100` resolved to `server-a`'s MAC. Confirm which
MAC that actually is:
```bash
docker exec clab-arp-lab-server-a ip link show eth1
```
Same address — `client` learned it via ARP the normal way (broadcast
request, unicast reply) the first time it needed it.

## Step 4 — Fail the VIP over, the *correct* way
```bash
docker exec clab-arp-lab-server-a ip addr del 10.0.0.100/24 dev eth1
docker exec clab-arp-lab-server-b ip addr add 10.0.0.100/24 dev eth1
docker exec clab-arp-lab-server-b arping -U -c 1 -I eth1 10.0.0.100
```
`arping -U` sends an unsolicited (gratuitous) ARP — `server-b` announcing
"10.0.0.100 is at my MAC now" to the whole segment, without anyone asking.
Check the client's cache *without pinging anything first*:
```bash
docker exec clab-arp-lab-client ip neigh show 10.0.0.100
```
It already points at `server-b`'s MAC. The gratuitous ARP updated it
proactively — this is exactly the mechanism VRRP/keepalived rely on to
make a failover invisible to everyone else on the segment.

## Challenges

**Challenge A — no gratuitous ARP sent:**
```bash
docker exec clab-arp-lab-server-b ip addr del 10.0.0.100/24 dev eth1
docker exec clab-arp-lab-server-a ip addr add 10.0.0.100/24 dev eth1
docker exec clab-arp-lab-client ping -c 2 10.0.0.100
docker exec clab-arp-lab-server-a ip addr del 10.0.0.100/24 dev eth1
docker exec clab-arp-lab-server-b ip addr add 10.0.0.100/24 dev eth1
```
The VIP moved from `server-a` to `server-b` again, same as Step 4 — but
this time, nobody sent a gratuitous ARP. Try reaching the VIP, and also
try reaching `server-b`'s own real identity address directly:
```bash
docker exec clab-arp-lab-client ping -c 2 -W 2 10.0.0.100
docker exec clab-arp-lab-client ping -c 2 10.0.0.21
```
Check `ip neigh show 10.0.0.100` on the client before deciding what's
actually wrong.

**Challenge B — old owner never let go:**
```bash
docker exec clab-arp-lab-server-b ip addr del 10.0.0.100/24 dev eth1 2>/dev/null || true
docker exec clab-arp-lab-server-a ip addr add 10.0.0.100/24 dev eth1 2>/dev/null || true
docker exec clab-arp-lab-server-b ip addr add 10.0.0.100/24 dev eth1
docker exec clab-arp-lab-server-b arping -U -c 1 -I eth1 10.0.0.100
```
This time the failover *does* send a gratuitous ARP correctly. Ping the
VIP a few times in a row from the client, checking `ip neigh show
10.0.0.100` after each one:
```bash
for i in 1 2 3 4; do
  docker exec clab-arp-lab-client ping -c 1 -W 1 10.0.0.100 >/dev/null
  docker exec clab-arp-lab-client ip neigh show 10.0.0.100
  sleep 2
done
```
If the resolved MAC isn't staying put, check `ip addr show eth1` on
*both* `server-a` and `server-b` before blaming the client's cache again.

See `solution.md` only after you've formed your own diagnosis.
