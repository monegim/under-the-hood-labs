# Lab 13 — Broken DNS

## Objective
Build a two-hop DNS path (client → forwarding resolver → authoritative
upstream), watch a real resolution and its caching behave correctly, then
reproduce the two DNS failures that get confused with each other in almost
every incident: "I can't reach my resolver at all" vs. "my resolver is
reachable but is answering badly."

## Why this matters
"DNS is broken" is one of the most overused, least precise sentences in
on-call. It can mean the resolver is completely unreachable (a network
problem), the resolver is up but returning SERVFAIL (an upstream/config
problem), or the resolver answered correctly *days ago* and you're staring
at a stale cached answer (a TTL problem) — three different root causes,
three different fixes, and `dig` is the tool that tells them apart in
under a minute instead of you guessing.

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
client (10.0.1.10/24) -- resolver (forwarder) -- upstream (authoritative)
        10.0.1.0/24                  10.0.2.0/24
```
`resolver` is a pure forwarder — it holds no records of its own, it just
asks `upstream` and caches the answer. `upstream` is authoritative for one
made-up zone, `app.internal`.

## Step 1 — Deploy, install tools, address
```bash
sudo containerlab deploy -t topology.clab.yml

for n in client resolver upstream; do
  docker exec clab-broken-dns-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping dnsmasq dnsutils >/dev/null"
done

docker exec clab-broken-dns-client ip addr add 10.0.1.10/24 dev eth1
docker exec clab-broken-dns-client ip link set eth1 up

docker exec clab-broken-dns-resolver ip addr add 10.0.1.1/24 dev eth1
docker exec clab-broken-dns-resolver ip link set eth1 up
docker exec clab-broken-dns-resolver ip addr add 10.0.2.1/24 dev eth2
docker exec clab-broken-dns-resolver ip link set eth2 up

docker exec clab-broken-dns-upstream ip addr add 10.0.2.2/24 dev eth1
docker exec clab-broken-dns-upstream ip link set eth1 up
```
> No `ip_forward` and no routes needed anywhere — `resolver` isn't routing
> IP packets between the two subnets, it's a DNS *process* that receives a
> query on one interface and issues a brand-new query of its own out the
> other. That's an application-layer relay, not IP forwarding.

## Step 2 — Start the authoritative side
```bash
docker exec -d clab-broken-dns-upstream dnsmasq -k --no-resolv --no-hosts \
  --address=/app.internal/10.9.9.99 --local-ttl=20 \
  --listen-address=10.0.2.2 --bind-interfaces
```
`upstream` now answers `app.internal` with `10.9.9.99` and a 20-second TTL
— short on purpose, so you can watch it expire in real time instead of
waiting minutes.

## Step 3 — Start the forwarding resolver
```bash
docker exec -d clab-broken-dns-resolver dnsmasq -k --no-resolv \
  --server=10.0.2.2 --listen-address=10.0.1.1 --bind-interfaces --cache-size=150
```
`resolver` has no local records at all (`--no-resolv`, no `--address`) —
every query it doesn't already have cached gets forwarded to `10.0.2.2`.

## Step 4 — Point the client at the resolver and query
```bash
docker exec clab-broken-dns-client bash -c "echo 'nameserver 10.0.1.1' > /etc/resolv.conf"
docker exec clab-broken-dns-client dig +noall +answer app.internal
```
You should see `app.internal. 20 IN A 10.9.9.99` — a fresh answer straight
from `upstream`, TTL 20.

> On a real host (not a minimal container) this is the point where you'd
> also run `resolvectl status` / `resolvectl query app.internal` —
> `resolvectl` is `systemd-resolved`'s control command, and it shows you
> which resolver a given interface is actually configured to use plus its
> own cache, which matters when NetworkManager/systemd-resolved silently
> overrides a hand-edited `/etc/resolv.conf`. These containers don't run
> systemd, so this lab talks to `/etc/resolv.conf` and `dnsmasq` directly —
> the diagnostic logic is identical either way.

## Step 5 — Watch the cache do its job (and go stale)
Query again immediately and watch the TTL count down:
```bash
docker exec clab-broken-dns-client dig +noall +answer app.internal
sleep 5
docker exec clab-broken-dns-client dig +noall +answer app.internal
```
The TTL drops by roughly the number of seconds you slept — `resolver` is
serving this from its own cache, not re-asking `upstream` every time.

Now change what `upstream` answers, *without* touching `resolver`:
```bash
docker exec clab-broken-dns-upstream pkill dnsmasq
docker exec -d clab-broken-dns-upstream dnsmasq -k --no-resolv --no-hosts \
  --address=/app.internal/10.9.9.100 --local-ttl=20 \
  --listen-address=10.0.2.2 --bind-interfaces
docker exec clab-broken-dns-client dig +noall +answer app.internal
```
> Gotcha: if you run this within the 20-second cache window, `dig` still
> returns the *old* `10.9.9.99` — `resolver` hasn't gone back to ask
> `upstream` again yet, it's just serving what it already has. Wait past
> the TTL (`sleep 20`) and query again: only then does `10.9.9.100` show
> up. This is "the answer is wrong" in its most common real form — not a
> bug, just a cache that hasn't caught up yet with a change made somewhere
> upstream.

> Note on `dig +trace`: it walks the real public root → TLD → authoritative
> hierarchy, which only exists for real registered domains — it has
> nothing to walk for a made-up private zone like `app.internal`, so it
> isn't useful inside this lab. It's the right tool once you're back on a
> real host debugging a real public domain and need to find exactly which
> hop in that chain is misbehaving.

## Challenges

**Challenge A:**
```bash
docker exec clab-broken-dns-client bash -c "echo 'nameserver 10.0.1.99' > /etc/resolv.conf"
docker exec clab-broken-dns-client dig app.internal
```
Compare this against pinging the resolver's *real* address:
```bash
docker exec clab-broken-dns-client ping -c 2 10.0.1.1
```
Use both results together to work out exactly what class of problem this
is before you decide on a fix.

**Challenge B:**
```bash
docker exec clab-broken-dns-client bash -c "echo 'nameserver 10.0.1.1' > /etc/resolv.conf"
docker exec clab-broken-dns-resolver pkill dnsmasq
docker exec -d clab-broken-dns-resolver dnsmasq -k --no-resolv \
  --server=10.0.2.2 --listen-address=10.0.1.1 --bind-interfaces --cache-size=150
docker exec clab-broken-dns-upstream pkill dnsmasq
docker exec clab-broken-dns-client dig app.internal
```
The client's `nameserver` line is back to the correct `10.0.1.1`, and
`dig` gets an actual reply this time — not a timeout. Look at the status
line at the top of `dig`'s output before deciding whether that counts as
"working."

See `solution.md` only after you've formed your own diagnosis.
