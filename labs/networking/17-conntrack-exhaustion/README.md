# Lab 17 — Conntrack Exhaustion

## Objective
Fill a router's connection-tracking table to its configured maximum,
watch brand-new connections get silently dropped once it's full, then
reproduce the same end symptom from a completely different cause — not a
traffic burst, but connections that were never properly closed.

## Why this matters
Connection tracking is invisible right up until it isn't. A router or
firewall doing any kind of stateful filtering or NAT has to keep one
table entry per active flow, that table has a hard ceiling
(`nf_conntrack_max`), and once it's full the kernel doesn't degrade
gracefully — it drops the next new connection attempt, silently, with no
ICMP error, nothing in the application's logs, and nothing that looks
like a network problem from either endpoint's perspective. "Random"
connection failures under load are the single most common way this shows
up, and `conntrack` is the specific tool that turns "random" into "the
table's full, and here's exactly why."

## Prerequisites
- Docker + [containerlab](https://containerlab.dev) installed
- `debian:bookworm-slim` image pulled
- The `nf_conntrack` kernel module loaded on the **host** (containers
  share the host kernel's netfilter modules; each network namespace gets
  its own conntrack table instance once the module is loaded):
```bash
sudo modprobe nf_conntrack
lsmod | grep nf_conntrack
```

Check first:
```bash
docker version
containerlab version
docker pull debian:bookworm-slim
```

## Topology
```
client (10.0.1.10/24) -- r1 -- server (10.0.2.10/24)
```

## Step 1 — Deploy, install tools, address, enable forwarding
```bash
sudo containerlab deploy -t topology.clab.yml

for n in client r1 server; do
  docker exec clab-conntrack-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping iptables conntrack python3 procps >/dev/null"
done

docker exec clab-conntrack-lab-client ip addr add 10.0.1.10/24 dev eth1
docker exec clab-conntrack-lab-client ip link set eth1 up
docker exec clab-conntrack-lab-client ip route add default via 10.0.1.1

docker exec clab-conntrack-lab-r1 ip addr add 10.0.1.1/24 dev eth1
docker exec clab-conntrack-lab-r1 ip link set eth1 up
docker exec clab-conntrack-lab-r1 ip addr add 10.0.2.1/24 dev eth2
docker exec clab-conntrack-lab-r1 ip link set eth2 up
docker exec clab-conntrack-lab-r1 sysctl -w net.ipv4.ip_forward=1

docker exec clab-conntrack-lab-server ip addr add 10.0.2.10/24 dev eth1
docker exec clab-conntrack-lab-server ip link set eth1 up
docker exec clab-conntrack-lab-server ip route add default via 10.0.2.1

docker exec clab-conntrack-lab-client ping -c 3 10.0.2.10
```

## Step 2 — Make r1 actually track connections, and shrink its table
```bash
docker exec clab-conntrack-lab-r1 iptables -A FORWARD -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec clab-conntrack-lab-r1 sysctl -w net.netfilter.nf_conntrack_max=128
```
The explicit `-m conntrack` rule guarantees netfilter's connection-
tracking hooks are actually registered for forwarded traffic. Setting
`nf_conntrack_max` to a deliberately tiny 128 makes exhaustion something
you can trigger and watch in seconds, standing in for a real table that's
undersized relative to real connection concurrency.

## Step 3 — Start a listener that actually holds connections open
```bash
docker exec -d clab-conntrack-lab-server python3 -c "
import socket, threading
def handle(c):
    try:
        c.recv(1)
    except Exception:
        pass
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 9090))
s.listen(1024)
while True:
    conn, addr = s.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
"
```
Each accepted connection blocks on `recv()` until the client closes it —
this is what lets connections actually stay open long enough to fill a
table, instead of finishing instantly.

## Step 4 — Watch the table fill up
```bash
docker exec clab-conntrack-lab-client bash -c \
  'for i in $(seq 1 300); do (exec 3<>/dev/tcp/10.0.2.10/9090; sleep 15) & done'
sleep 3
docker exec clab-conntrack-lab-r1 conntrack -C
docker exec clab-conntrack-lab-r1 sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```
`conntrack -C` (count) should be sitting right at (or just under) 128 —
300 connection attempts, only enough room for 128 to actually get tracked.
```bash
docker exec clab-conntrack-lab-r1 conntrack -S
```
Look at the `insert_failed` and `drop` fields — both non-zero, climbing
if you re-run this while more attempts are still in flight.

## Step 5 — Let it drain back to healthy
```bash
sleep 20
docker exec clab-conntrack-lab-r1 conntrack -C
```
Step 4's connections all had a 15-second hold, so they close themselves
on their own — the count drops back down near zero without touching
anything. This is the healthy state the rest of this lab starts back
from.

## Challenges

**Challenge A:**
```bash
docker exec clab-conntrack-lab-client bash -c \
  'for i in $(seq 1 400); do (exec 3<>/dev/tcp/10.0.2.10/9090; sleep 20) & done'
```
While that's running, try one more connection yourself and see what
happens to it:
```bash
docker exec clab-conntrack-lab-client bash -c 'time (exec 3<>/dev/tcp/10.0.2.10/9090; echo ok)'
```
Check `conntrack -S`, `conntrack -C`, and `dmesg` on `r1` before deciding
exactly what's failing and why.

**Challenge B:**
Wait for Challenge A's connections to finish closing (`sleep 25`), then
build up the table again slowly instead of all at once — connections that
never close, arriving one at a time, standing in for a client application
with a socket-leak bug:
```bash
docker exec clab-conntrack-lab-client bash -c '
for i in $(seq 1 150); do
  (exec 3<>/dev/tcp/10.0.2.10/9090; while true; do sleep 3600; done) &
  sleep 0.3
done'
```
There's no burst here — connections trickle in slowly, well below any
rate that looks like an attack or a spike. Give it a minute, then check
`conntrack -C` and `conntrack -L -o extended | grep ESTABLISHED | head`.
Compare the picture this paints against Challenge A before deciding
whether the underlying problem is the same.

See `solution.md` only after you've formed your own diagnosis.
