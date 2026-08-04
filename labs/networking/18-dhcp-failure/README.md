# Lab 18 — DHCP Failure

## Objective
Get a real DHCP lease with `dhclient`, then reproduce the two most common
ways a host ends up with no usable IP address at all: a server whose
address pool is completely exhausted, and a lease that expires while the
server is unreachable for renewal.

## Why this matters
"The host doesn't have an IP" is a dead end unless you know which of two
very different problems you're looking at. An exhausted pool means the
server is up, answering, and correctly saying no — nothing wrong with
reachability, the well is just dry. An unreachable server at renewal time
means the client had a perfectly good lease and lost it purely because it
couldn't phone home in time — a reachability problem, not a capacity
one. `dhclient -v`'s own output tells you immediately which one you're in,
if you know what to look for.

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
client (DHCP, no static IP) -- dhcp-server (10.50.0.1/24)
```
A tiny pool on purpose: only two leasable addresses,
`10.50.0.100`-`10.50.0.101`, and a short 2-minute lease time — both
picked so pool exhaustion and lease expiry are things you can watch
happen in real time instead of waiting hours.

## Step 1 — Deploy, install tools, address the server
```bash
sudo containerlab deploy -t topology.clab.yml

docker exec clab-dhcp-lab-client bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 isc-dhcp-client >/dev/null"
docker exec clab-dhcp-lab-dhcp-server bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 dnsmasq iputils-ping >/dev/null"

docker exec clab-dhcp-lab-dhcp-server ip addr add 10.50.0.1/24 dev eth1
docker exec clab-dhcp-lab-dhcp-server ip link set eth1 up

docker exec clab-dhcp-lab-client ip link set eth1 up
```
> `client` intentionally gets no address here — that's `dhclient`'s job.

## Step 2 — Start the DHCP server
```bash
docker exec -d clab-dhcp-lab-dhcp-server dnsmasq -k --no-resolv --no-hosts \
  --interface=eth1 --bind-interfaces \
  --dhcp-range=10.50.0.100,10.50.0.101,2m \
  --dhcp-leasefile=/var/lib/misc/dnsmasq.leases --log-dhcp
```
A pool of exactly two addresses, 2-minute leases.

## Step 3 — Get a real lease
```bash
docker exec clab-dhcp-lab-client dhclient -v eth1
```
You should see the full exchange in order: `DHCPDISCOVER` (broadcast, "is
anyone out there?"), `DHCPOFFER` (the server proposing an address),
`DHCPREQUEST` (the client formally asking for that specific one),
`DHCPACK` (the server confirming). Confirm the result:
```bash
docker exec clab-dhcp-lab-client ip addr show eth1
docker exec clab-dhcp-lab-client cat /var/lib/dhcp/dhclient.eth1.leases
```
> On a real host (not a minimal container), this is also where you'd run
> `journalctl -u NetworkManager` or `journalctl -u systemd-networkd` to
> see the same DHCP client log lines through systemd's journal instead of
> directly on the terminal. These containers don't run systemd, so
> `dhclient -v`'s own output is the log — the message sequence you're
> reading is identical either way.

## Step 4 — Release it cleanly before continuing
```bash
docker exec clab-dhcp-lab-client dhclient -r eth1
```
This frees the leased address back to the server's pool — confirm with
`docker exec clab-dhcp-lab-client ip addr show eth1` (no IPv4 address).

## Challenges

**Challenge A — pool exhausted:**
Pre-occupy both leasable addresses on the server *before* the client ever
asks, standing in for two other hosts that already hold them:
```bash
docker exec clab-dhcp-lab-dhcp-server pkill dnsmasq
docker exec clab-dhcp-lab-dhcp-server bash -c "cat > /var/lib/misc/dnsmasq.leases <<'EOF'
9999999999 aa:aa:aa:aa:aa:01 10.50.0.100 phantom1 *
9999999999 aa:aa:aa:aa:aa:02 10.50.0.101 phantom2 *
EOF"
docker exec -d clab-dhcp-lab-dhcp-server dnsmasq -k --no-resolv --no-hosts \
  --interface=eth1 --bind-interfaces \
  --dhcp-range=10.50.0.100,10.50.0.101,2m \
  --dhcp-leasefile=/var/lib/misc/dnsmasq.leases --log-dhcp
```
```bash
docker exec clab-dhcp-lab-client dhclient -v -1 eth1
```
(`-1` tells `dhclient` to try exactly once and give up instead of
retrying forever — useful for a lab, not something you'd typically use on
a real host that needs to keep trying.) Read the full output before
deciding what happened, and check what the server itself logged.

**Challenge B — server unreachable at renewal:**
Start clean and get a real lease first:
```bash
docker exec clab-dhcp-lab-dhcp-server pkill dnsmasq
docker exec clab-dhcp-lab-dhcp-server bash -c "rm -f /var/lib/misc/dnsmasq.leases"
docker exec -d clab-dhcp-lab-dhcp-server dnsmasq -k --no-resolv --no-hosts \
  --interface=eth1 --bind-interfaces \
  --dhcp-range=10.50.0.100,10.50.0.101,2m \
  --dhcp-leasefile=/var/lib/misc/dnsmasq.leases --log-dhcp
docker exec clab-dhcp-lab-client dhclient -v eth1
docker exec clab-dhcp-lab-client ip addr show eth1
```
Now take the server away right as the client would normally try to renew:
```bash
docker exec clab-dhcp-lab-dhcp-server pkill dnsmasq
```
Watch what happens over the next couple of minutes (the 2-minute lease
means renewal, rebind, and expiry all happen within that window):
```bash
docker exec clab-dhcp-lab-client bash -c "sleep 130; ip addr show eth1"
```
Compare the client's behavior here against Challenge A — same end state
(no usable IP), but pay attention to how it got there.

See `solution.md` only after you've formed your own diagnosis.
