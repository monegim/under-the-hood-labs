# Lab 20 — NAT Port Exhaustion

## Objective
Drive a MASQUERADE (SNAT) router past its available ephemeral port pool and
watch new outbound connections start failing while existing ones keep
working fine — then fix it the only two ways that actually work.

## Why this matters
Lab 4 covered *that* MASQUERADE rewrites source addresses. This lab covers
the part that actually pages people at 3am: MASQUERADE needs a free
external port for every single outbound connection it translates, and that
pool is finite — one external IP has at most ~64,511 usable ports. CGNAT
ISPs, AWS/GCP NAT Gateways, and any Kubernetes cluster egressing through one
NAT device all hit this same ceiling in production. It's a completely
different failure mode from the conntrack-table exhaustion covered
elsewhere in this series: that one is about running out of *tracked flow
slots*; this one is about running out of *source ports on one IP*, and it
happens even with a conntrack table that has plenty of room left.

## Prerequisites
- Docker + [containerlab](https://containerlab.dev) installed
- `nicolaka/netshoot` image pulled

Check first:
```bash
docker version
containerlab version
docker pull nicolaka/netshoot:latest
```

## Topology
```
host-int (192.168.50.0/24) --- router --- host-ext (203.0.113.0/24)
```
`router` will get **two** addresses on its external interface
(`203.0.113.1` and `203.0.113.21`) partway through this lab — that's the
real fix, not a typo.

## Step 1 — Deploy the topology
```bash
sudo containerlab deploy -t topology.clab.yml
```

## Step 2 — Address everything
```bash
docker exec clab-natexh-host-int ip addr add 192.168.50.10/24 dev eth1
docker exec clab-natexh-host-int ip link set eth1 up
docker exec clab-natexh-host-int ip route add default via 192.168.50.1

docker exec clab-natexh-router ip addr add 192.168.50.1/24 dev eth1
docker exec clab-natexh-router ip link set eth1 up
docker exec clab-natexh-router ip addr add 203.0.113.1/24 dev eth2
docker exec clab-natexh-router ip link set eth2 up

docker exec clab-natexh-host-ext ip addr add 203.0.113.20/24 dev eth1
docker exec clab-natexh-host-ext ip link set eth1 up

docker exec clab-natexh-router sysctl -w net.ipv4.ip_forward=1
```

## Step 3 — Install tools and start a listener that holds connections open
```bash
docker exec clab-natexh-host-ext apk add --no-cache socat >/dev/null
docker exec clab-natexh-router apk add --no-cache conntrack-tools >/dev/null

docker exec -d clab-natexh-host-ext socat TCP-LISTEN:9000,fork,reuseaddr SYSTEM:'cat'
```
`fork` means this listener accepts as many simultaneous connections as
thrown at it, one child per connection, and just echoes back whatever it
receives — good enough to hold a connection open so we can look at it.

## Step 4 — Add a deliberately tiny SNAT port pool
```bash
docker exec clab-natexh-router iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -j MASQUERADE --to-ports 40000-40004
```
That's **5** ports. A real external IP has on the order of 64,511 usable
ports (65535 total, minus the 0–1023 reserved/well-known range) — we're
using 5 here so the ceiling is reachable in seconds instead of after
thousands of real connections. The mechanism is identical at either scale.

## Step 5 — Baseline: prove it works under the pool's capacity
```bash
for i in 1 2 3; do
  ( docker exec clab-natexh-host-int timeout 8 bash -c \
      'exec 3<>/dev/tcp/203.0.113.20/9000 && sleep 6' \
    && echo "conn $i: OK" || echo "conn $i: FAIL" ) &
done
wait
```
While that's running (or right after), look at the router's NAT sessions:
```bash
docker exec clab-natexh-router conntrack -L -p tcp --dport 9000 2>/dev/null
```
Three entries, each translated to a **different** port somewhere in
`40000-40004`. That per-connection port is the whole reason MASQUERADE can
tell these three flows apart on the way back.

## Step 6 — Push past the ceiling
```bash
for i in $(seq 1 8); do
  ( docker exec clab-natexh-host-int timeout 8 bash -c \
      'exec 3<>/dev/tcp/203.0.113.20/9000 && sleep 6' \
    && echo "conn $i: OK" || echo "conn $i: FAIL" ) &
done
wait
```
Only 5 of the 8 succeed. Check the router:
```bash
docker exec clab-natexh-router conntrack -L -p tcp --dport 9000 2>/dev/null | wc -l
```
Exactly 5 — the pool, not the number of attempts, is the ceiling.
> Gotcha: the failing connections don't get an instant "connection
> refused." With no free port to allocate, the kernel can't build a NAT
> session for the SYN at all, so it just drops the packet — the client
> sees nothing and has to wait out its own connect timeout. In production
> this looks exactly like a network black hole, not like a firewall block,
> which is what makes it so easy to misdiagnose as "the network is flaky"
> instead of "the NAT device is out of ports."

## Step 7 — The only two real fixes
You cannot configure your way to more than ~64,511 ports on a single IP —
that ceiling is protocol, not policy. The two levers that actually work are
**more public IPs** or **fewer concurrent connections**. Here we add a
second external IP and split new connections across both port pools:
```bash
docker exec clab-natexh-router ip addr add 203.0.113.21/24 dev eth2

docker exec clab-natexh-router iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -m statistic --mode nth --every 2 --packet 0 \
  -j SNAT --to-source 203.0.113.1:40000-40004
docker exec clab-natexh-router iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -j SNAT --to-source 203.0.113.21:40000-40004
```
> Gotcha: the old `--to-ports 40000-40004` MASQUERADE rule from Step 4 is
> still sitting in the chain. Remove it, or the two new rules below it
> never get a chance to match anything:
```bash
docker exec clab-natexh-router iptables -t nat -D POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -j MASQUERADE --to-ports 40000-40004
```
The `nth --every 2` rule catches roughly half of new connections and SNATs
them via `.1`'s 5-port pool; everything else falls through to the
unconditional second rule and gets `.21`'s 5-port pool — 10 usable ports
total instead of 5.

## Step 8 — Re-test with 8 concurrent connections
```bash
for i in $(seq 1 8); do
  ( docker exec clab-natexh-host-int timeout 8 bash -c \
      'exec 3<>/dev/tcp/203.0.113.20/9000 && sleep 6' \
    && echo "conn $i: OK" || echo "conn $i: FAIL" ) &
done
wait

docker exec clab-natexh-router conntrack -L -p tcp --dport 9000 2>/dev/null
```
All 8 succeed, and the conntrack output shows sessions translated through
**both** `203.0.113.1` and `203.0.113.21`.

## Challenges

**Challenge A:**
```bash
docker exec clab-natexh-router iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -j MASQUERADE --to-ports 40000-40004
```
(This re-adds the old Step 4 rule at the *bottom* of the chain, simulating
someone re-applying an old config snippet without checking what was already
there.) Run the Step 8 test again — it fails the same way it did in Step 6,
even though the dual-IP rules from Step 7 are still present. Use
`iptables -t nat -L POSTROUTING -n -v --line-numbers` and look at which
rule's counters are actually incrementing before concluding anything.

**Challenge B:**
```bash
for i in $(seq 1 14); do
  ( docker exec clab-natexh-host-int timeout 8 bash -c \
      'exec 3<>/dev/tcp/203.0.113.20/9000 && sleep 6' \
    && echo "conn $i: OK" || echo "conn $i: FAIL" ) &
done
wait
```
(Run this against the healthy Step 8 state, not Challenge A's broken
state.) Some of these 14 fail even though Step 7's fix is correctly in
place and fully working. This isn't a regression — figure out what the
numbers are actually telling you, and what the two legitimate options are
from here.

See `solution.md` only after you've formed your own diagnosis.
