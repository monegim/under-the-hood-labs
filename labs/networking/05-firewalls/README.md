# Lab 5 — Firewalls

## Objective
Lock down a router with a default-DROP `FORWARD` policy, add back exactly
the traffic you want, and see two realistic ways a "correct-looking"
firewall config still breaks connections.

## Why this matters
Every cloud security group, NSG, and NACL eventually compiles down to an
ordered list of allow/deny rules evaluated top-to-bottom, plus a default
policy for anything unmatched. Understand `iptables`' `-P`, `-A`, `-I`, and
stateful matching, and you understand the exact model every cloud firewall
abstraction is hiding from you.

## Prerequisites
- Docker
- containerlab
- `sudo` access

Check first:
```bash
docker version
containerlab version
```

## Step 1 — Deploy and address
```bash
sudo containerlab deploy -t topology.clab.yml
```
Topology: `client (10.10.1.0/24) — fw — server (10.10.2.0/24)`.
```bash
docker exec clab-firewalls-client ip addr add 10.10.1.10/24 dev eth1
docker exec clab-firewalls-client ip link set eth1 up
docker exec clab-firewalls-client ip route add default via 10.10.1.1

docker exec clab-firewalls-fw ip addr add 10.10.1.1/24 dev eth1
docker exec clab-firewalls-fw ip link set eth1 up
docker exec clab-firewalls-fw ip addr add 10.10.2.1/24 dev eth2
docker exec clab-firewalls-fw ip link set eth2 up
docker exec clab-firewalls-fw sysctl -w net.ipv4.ip_forward=1

docker exec clab-firewalls-server ip addr add 10.10.2.10/24 dev eth1
docker exec clab-firewalls-server ip link set eth1 up
docker exec clab-firewalls-server ip route add default via 10.10.2.1
```

## Step 2 — Confirm the "wide open" baseline
```bash
docker exec clab-firewalls-client ping -c 2 10.10.2.10
docker exec -d clab-firewalls-server nc -lp 80
docker exec clab-firewalls-client sh -c 'echo hi | nc -w2 10.10.2.10 80'
```
Both work — `fw` is just routing so far, no filtering yet.

## Step 3 — Default-DROP the FORWARD chain
```bash
docker exec clab-firewalls-fw iptables -P FORWARD DROP
docker exec clab-firewalls-client ping -c 2 10.10.2.10
```
> Gotcha: this breaks everything through the firewall instantly, including
> traffic you fully intend to allow later. A default-DROP policy takes
> effect immediately — there's no grace period while you add your ACCEPT
> rules, so do this on a maintenance window, not on a router mid-traffic.

## Step 4 — Add back exactly what you asked for (one direction only)
```bash
docker exec clab-firewalls-fw iptables -A FORWARD -i eth1 -o eth2 -p icmp --icmp-type echo-request -j ACCEPT
docker exec clab-firewalls-fw iptables -A FORWARD -i eth1 -o eth2 -p tcp --dport 80 -j ACCEPT
docker exec clab-firewalls-client ping -c 2 10.10.2.10
```
Still 100% packet loss. Check `iptables -L FORWARD -v -n` — the
echo-request rule's counter is incrementing (the request is getting
through to the server), but nothing comes back. Both rules above only
match the `eth1 -> eth2` direction — the reply has no rule allowing
`eth2 -> eth1`.

## Step 5 — Add the stateful return-traffic rule
```bash
docker exec clab-firewalls-fw iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
docker exec clab-firewalls-client ping -c 2 10.10.2.10
docker exec clab-firewalls-client sh -c 'echo hi | nc -w2 10.10.2.10 80'
```
Now both work. This one rule covers return traffic for *any* connection
already permitted outbound — no need for a mirrored rule per direction per
service.
> Gotcha: this rule only helps if it actually gets evaluated before the
> chain falls through to the default DROP policy. Appending it (`-A`) is
> fine here since nothing after it blocks it — but insert a DROP rule
> ahead of it later (see Challenge B) and order suddenly matters a lot.

## Step 6 — Protect the firewall host itself (INPUT chain)
```bash
docker exec clab-firewalls-fw iptables -A INPUT -i lo -j ACCEPT
docker exec clab-firewalls-fw iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
docker exec clab-firewalls-fw iptables -P INPUT DROP
docker exec clab-firewalls-client ping -c 2 10.10.1.1
```
This last ping fails — `INPUT` is now default-DROP and there's no rule
allowing ICMP *to the firewall itself*. That's a separate concern from
`FORWARD` (traffic passing through vs. traffic destined for the router).
Add it if you want the firewall to answer pings:
```bash
docker exec clab-firewalls-fw iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
```

## Challenges

**Challenge A:**
```bash
docker exec clab-firewalls-fw iptables -F FORWARD
```
Everything through the firewall stops instantly. Check the policy, not
just the rule list.

**Challenge B:**
```bash
docker exec clab-firewalls-fw iptables -I FORWARD 1 -p tcp --sport 80 -j DROP
```
Ping still works. The TCP connection to port 80 doesn't. Use
`iptables -L FORWARD -v -n --line-numbers` and think about what "insert at
position 1" actually did to the rules you built in Steps 4-5.

See `SOLUTION.md` only after you've formed your own diagnosis.
