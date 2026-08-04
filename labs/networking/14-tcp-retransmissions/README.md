# Lab 14 — TCP Retransmissions

## Objective
Run a real data transfer over a link with induced packet loss, read the
retransmissions it causes in `tcpdump` and `ss -i`, then reproduce a
second, completely different root cause — an unresponsive receiver — that
produces the exact same "client keeps retransmitting" surface symptom.

## Why this matters
"There are retransmits" is a symptom, not a diagnosis. A lossy link and an
overloaded/stuck receiving host both make a sender retransmit, and from
the sender's `ss -i` output alone the counters look identical. Telling
these apart requires capturing at *both* ends and comparing what actually
arrived, not just counting retransmissions on one side — the same
multi-point-capture discipline from Lab 12, applied to a genuinely
different failure class.

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
client (10.0.0.10/24) -- server (10.0.0.20/24)
```
A single direct link — no router needed, this lab is about what happens
on one hop, not about routing.

## Step 1 — Deploy, install tools, address
```bash
sudo containerlab deploy -t topology.clab.yml

for n in client server; do
  docker exec clab-tcp-retrans-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iperf3 procps >/dev/null"
done

docker exec clab-tcp-retrans-client ip addr add 10.0.0.10/24 dev eth1
docker exec clab-tcp-retrans-client ip link set eth1 up

docker exec clab-tcp-retrans-server ip addr add 10.0.0.20/24 dev eth1
docker exec clab-tcp-retrans-server ip link set eth1 up

docker exec clab-tcp-retrans-client ping -c 3 10.0.0.20
```

## Step 2 — Baseline: a clean transfer, zero retransmits
```bash
docker exec -d clab-tcp-retrans-server iperf3 -s
sleep 1
docker exec clab-tcp-retrans-client iperf3 -c 10.0.0.20 -t 5
```
While that runs (or right after), check the socket's retransmit counter:
```bash
docker exec clab-tcp-retrans-client ss -ti dst 10.0.0.20
```
Look for `retrans:0/0` (or very close to it) in the extended info line —
`retrans:<currently unacked>/<total so far>`. A clean link, clean run.

## Step 3 — Induce real packet loss with `tc netem`
```bash
docker exec clab-tcp-retrans-client tc qdisc add dev eth1 root netem loss 10%
docker exec clab-tcp-retrans-client iperf3 -c 10.0.0.20 -t 5
docker exec clab-tcp-retrans-client ss -ti dst 10.0.0.20
```
`retrans:` is now non-zero, and `iperf3`'s own reported throughput dropped
noticeably — 10% of packets never made it, and TCP is recovering by
retransmitting them. Capture on the client to see it directly:
```bash
docker exec clab-tcp-retrans-client tcpdump -ni eth1 -c 20 'tcp port 5201' &
docker exec clab-tcp-retrans-client iperf3 -c 10.0.0.20 -t 3
```
Look for repeated sequence numbers in the capture — the same segment
leaving twice because the first copy's ACK never came back in time.

Clean up the induced loss before continuing:
```bash
docker exec clab-tcp-retrans-client tc qdisc del dev eth1 root netem
```

## Challenges

**Challenge A:**
```bash
docker exec clab-tcp-retrans-client tc qdisc add dev eth1 root netem loss 15%
docker exec clab-tcp-retrans-server tcpdump -ni eth1 -w /tmp/server-side.pcap -c 200 &
docker exec clab-tcp-retrans-client tcpdump -ni eth1 -w /tmp/client-side.pcap -c 200 &
docker exec clab-tcp-retrans-client iperf3 -c 10.0.0.20 -t 5
```
Read both captures back (`tcpdump -r /tmp/client-side.pcap` /
`... /tmp/server-side.pcap`, or copy them out with `docker cp`) and compare
what each side actually saw before concluding anything about where the
loss is happening.

**Challenge B:**
```bash
docker exec clab-tcp-retrans-client tc qdisc del dev eth1 root netem
docker exec clab-tcp-retrans-server pkill -STOP -f "iperf3 -s"
docker exec clab-tcp-retrans-client iperf3 -c 10.0.0.20 -t 5
```
The link has zero configured loss this time. Run the same two-sided
capture as Challenge A, and also check `docker exec clab-tcp-retrans-server
ps aux | grep iperf3` for the process's state, before deciding what's
actually causing the retransmits here.

(Recovery: `docker exec clab-tcp-retrans-server pkill -CONT -f "iperf3 -s"`)

See `solution.md` only after you've formed your own diagnosis.
