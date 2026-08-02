# Lab 12 — Packet Captures

## Objective
Learn `tcpdump`/`tshark` fundamentals — capture filters vs display filters,
reading a TCP handshake, and telling apart three different "connection
doesn't work" signatures — by using them to pinpoint exactly where a
connection is actually failing across three hosts.

## Why this matters
"It doesn't connect" has several genuinely different root causes that all
look the same from the client alone: nothing listening, a host firewall
silently dropping the packet, and a middlebox actively rejecting it. The
only way to tell them apart with certainty is capturing at more than one
point along the path and comparing what each side actually saw. This is
the single most important escalation skill in network troubleshooting —
it's what separates "I think it's the firewall" from "I can prove exactly
which hop drops it."

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
client (10.0.1.10/24) -- r1 (router) -- server (10.0.2.10/24)
```
r1 only routes between the two subnets — it does no filtering by default.

## Step 1 — Deploy, install tools, address, enable forwarding
```bash
sudo containerlab deploy -t topology.clab.yml

for n in client server; do
  docker exec clab-pcap-lab-$n bash -c \
    "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump tshark python3 curl >/dev/null"
done
docker exec clab-pcap-lab-r1 bash -c \
  "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iptables >/dev/null"

docker exec clab-pcap-lab-client ip addr add 10.0.1.10/24 dev eth1
docker exec clab-pcap-lab-client ip link set eth1 up
docker exec clab-pcap-lab-client ip route add default via 10.0.1.1

docker exec clab-pcap-lab-r1 ip addr add 10.0.1.1/24 dev eth1
docker exec clab-pcap-lab-r1 ip link set eth1 up
docker exec clab-pcap-lab-r1 ip addr add 10.0.2.1/24 dev eth2
docker exec clab-pcap-lab-r1 ip link set eth2 up
docker exec clab-pcap-lab-r1 sysctl -w net.ipv4.ip_forward=1

docker exec clab-pcap-lab-server ip addr add 10.0.2.10/24 dev eth1
docker exec clab-pcap-lab-server ip link set eth1 up
docker exec clab-pcap-lab-server ip route add default via 10.0.2.1
```
```bash
docker exec clab-pcap-lab-client ping -c 3 10.0.2.10
```

## Step 2 — Start a real listener and read a clean handshake
```bash
docker exec -d clab-pcap-lab-server python3 -m http.server 8080 --bind 0.0.0.0
```
Start a capture on the server first, then generate traffic from the client:
```bash
docker exec clab-pcap-lab-server tcpdump -ni eth1 -c 10 tcp port 8080 &
docker exec clab-pcap-lab-client curl -sv --max-time 5 http://10.0.2.10:8080/ -o /dev/null
```
You should see three lines that matter, in order:
```
IP client.xxxxx > server.8080: Flags [S], seq ...
IP server.8080 > client.xxxxx: Flags [S.], seq ..., ack ...
IP client.xxxxx > server.8080: Flags [.], ack ...
```
`S` = SYN, `S.` = SYN-ACK, `.` = plain ACK — the three-way handshake,
followed by the actual HTTP request/response data.

## Step 3 — Capture filters vs display filters
A **capture filter** (BPF syntax) limits what's captured at the kernel
level, before it ever reaches userspace — cheap, but limited expressiveness:
```bash
docker exec clab-pcap-lab-server tcpdump -ni eth1 -c 5 'tcp port 8080 and tcp[tcpflags] & tcp-syn != 0'
```
A **display filter** (Wireshark/tshark syntax) filters *after* capture —
you can capture broadly and slice by any field afterward:
```bash
docker exec clab-pcap-lab-server tshark -ni eth1 -c 5 -Y 'tcp.flags.syn==1 && tcp.flags.ack==0'
```
> Gotcha: `-f` on `tshark`/`tcpdump` is a capture filter (BPF syntax,
> applied while capturing); `-Y` on `tshark` is a display filter (Wireshark
> field syntax, applied after). Mixing up the syntax between the two is
> one of the most common tcpdump/tshark beginner mistakes.

## Step 4 — See what "nothing listening" actually looks like
Kill the listener, then try again:
```bash
docker exec clab-pcap-lab-server pkill -f http.server
docker exec clab-pcap-lab-client tcpdump -ni eth1 -c 4 tcp port 8080 &
docker exec clab-pcap-lab-client curl -sv --max-time 5 http://10.0.2.10:8080/ -o /dev/null
```
With nothing listening, the kernel itself immediately sends back a `Flags
[R.]` (RST-ACK) — no retransmits, no delay. Keep this signature in mind:
it's the baseline "normal" no-listener case, and it's different from both
challenges below.

Restart the listener before continuing:
```bash
docker exec -d clab-pcap-lab-server python3 -m http.server 8080 --bind 0.0.0.0
```

## Challenges

**Challenge A:**
```bash
docker exec clab-pcap-lab-server iptables -A INPUT -p tcp --dport 8080 -j DROP
```
```bash
docker exec clab-pcap-lab-client tcpdump -ni eth1 -c 6 tcp port 8080 &
docker exec clab-pcap-lab-client curl -sv --max-time 8 http://10.0.2.10:8080/ -o /dev/null
```
Capture simultaneously on the client, on r1 (both interfaces), and on the
server itself before you draw any conclusions. Compare what each of the
three actually sees.

**Challenge B:**
```bash
docker exec clab-pcap-lab-r1 iptables -A FORWARD -p tcp --dport 8080 -j REJECT --reject-with tcp-reset
```
```bash
docker exec clab-pcap-lab-client tcpdump -ni eth1 -c 4 tcp port 8080 &
docker exec clab-pcap-lab-client curl -sv --max-time 8 http://10.0.2.10:8080/ -o /dev/null
```
From the client alone, this might look like the "nothing listening" case
from Step 4. Capture on the server too, and on r1, before deciding whether
that's actually true.

See `SOLUTION.md` only after you've formed your own diagnosis.
