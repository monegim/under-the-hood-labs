# Lab 4 — NAT

## Objective
Route an "internal" private-address host out through a NAT gateway to an
"external" host, using MASQUERADE for outbound traffic and DNAT for an
inbound port-forward — the two primitives behind every home router and
cloud NAT gateway.

## Why this matters
`docker run -p 8080:80`, AWS/GCP NAT gateways, and your home router's
port-forwarding page are all iptables/nftables DNAT and MASQUERADE rules
wearing a UI. Build this by hand once and "container can't reach the
internet" or "why can't I reach my service from outside" stop being
guessing games and start being a two-table lookup.

## Prerequisites
- Docker
- containerlab
- `sudo` access

Check first:
```bash
docker version
containerlab version
```

## Step 1 — Deploy the topology
```bash
sudo containerlab deploy -t topology.clab.yml
```
Topology: `host-int (192.168.100.0/24) — router — host-ext (203.0.113.0/24)`.
`host-ext` plays "the internet" — it will never get a route back to the
private `192.168.100.0/24` range, on purpose, because the real internet
doesn't have one either.

## Step 2 — Address everything
```bash
docker exec clab-nat-host-int ip addr add 192.168.100.10/24 dev eth1
docker exec clab-nat-host-int ip link set eth1 up
docker exec clab-nat-host-int ip route add default via 192.168.100.1

docker exec clab-nat-router ip addr add 192.168.100.1/24 dev eth1
docker exec clab-nat-router ip link set eth1 up
docker exec clab-nat-router ip addr add 203.0.113.1/24 dev eth2
docker exec clab-nat-router ip link set eth2 up

docker exec clab-nat-host-ext ip addr add 203.0.113.10/24 dev eth1
docker exec clab-nat-host-ext ip link set eth1 up
```
> `host-ext` gets no default route at all — it only knows about its own
> `/24`. That's intentional: it's standing in for a random host on the
> internet that has never heard of `192.168.100.0/24`.

## Step 3 — Turn the router into an actual router
```bash
docker exec clab-nat-router sysctl -w net.ipv4.ip_forward=1
```

## Step 4 — Prove NAT is necessary
```bash
docker exec clab-nat-host-int ping -c 3 203.0.113.10
```
This fails. `host-int`'s packets reach `host-ext` fine (confirm with
`tcpdump -n -i eth1` on `host-ext`), but the replies are addressed to
`192.168.100.10` — a network `host-ext` has no route to. The request gets
there; the reply has nowhere to go.

## Step 5 — Add MASQUERADE for outbound traffic
```bash
docker exec clab-nat-router iptables -t nat -A POSTROUTING -o eth2 -s 192.168.100.0/24 -j MASQUERADE
docker exec clab-nat-host-int ping -c 3 203.0.113.10
```
Now it works — `host-ext` sees the ping arriving from `203.0.113.1` (the
router's own external IP), and it knows exactly how to reply to that.
```bash
docker exec clab-nat-router iptables -t nat -L POSTROUTING -n -v
```

## Step 6 — DNAT: forward an inbound port to the internal host
Start a listener on `host-int`:
```bash
docker exec -d clab-nat-host-int nc -lp 8080
```
Forward the router's external port 8080 to it:
```bash
docker exec clab-nat-router iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.10:8080
docker exec clab-nat-router iptables -A FORWARD -p tcp -d 192.168.100.10 --dport 8080 -j ACCEPT
```
> The default `FORWARD` policy on a fresh node is typically ACCEPT, so this
> rule isn't strictly required yet — but write it anyway. Relying on a
> permissive default instead of an explicit rule is exactly the kind of
> thing that bites you the day someone locks the firewall down (see Lab 5).

Test from the "external" side:
```bash
docker exec clab-nat-host-ext sh -c 'echo hello | nc -w2 203.0.113.1 8080'
```
`host-ext` never talked to `192.168.100.10` directly — it only ever
addressed `203.0.113.1:8080`, and the router silently rewrote the
destination.

## Challenges

**Challenge A:**
```bash
docker exec clab-nat-router iptables -t nat -D POSTROUTING -o eth2 -s 192.168.100.0/24 -j MASQUERADE
```
Outbound connectivity from `host-int` breaks again. Check
`iptables -t nat -L -n -v` before concluding anything.

**Challenge B:**
```bash
docker exec clab-nat-router iptables -t nat -A POSTROUTING -o eth1 -s 192.168.100.0/24 -j MASQUERADE
```
This looks like it should fix Challenge A — there's a MASQUERADE rule
again. `host-int` still can't reach `host-ext`. Run
`iptables -t nat -L POSTROUTING -n -v` and look at the hit counters on each
rule, not just whether a rule exists.

See `SOLUTION.md` only after you've formed your own diagnosis.
