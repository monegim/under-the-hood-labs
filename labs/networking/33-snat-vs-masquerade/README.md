# Lab 33 — SNAT vs. MASQUERADE

## Objective
Set up outbound NAT two different, superficially interchangeable
ways — static `SNAT` and `MASQUERADE` — change the NAT gateway's
public-facing address the way a real DHCP renewal or failover would,
and watch one of them keep working without any changes while the
other silently breaks every outbound connection.

## Why this matters
`SNAT --to-source <ip>` and `MASQUERADE` are both "rewrite the source
address for outbound NAT," and plenty of guides treat them as
interchangeable — `MASQUERADE` is even commonly described as "just a
convenience wrapper" over `SNAT`. The difference that actually matters
operationally is what each one does when the gateway's own address
changes: `SNAT` rewrites to a hardcoded address you typed once, and
never checks whether that address still belongs to anything.
`MASQUERADE` looks up the outgoing interface's *current* address on
every single connection it establishes. On a genuinely static address
(a real static public IP allocation) this difference never surfaces.
On anything that can change — DHCP leases, cloud floating/elastic IPs
during failover, an ISP-assigned address after a modem reset — `SNAT`
becomes a ticking outage that can sit completely unnoticed for a long
time before it actually fires, for reasons this lab's challenges dig
into directly.

## Prerequisites
- A Linux VM, `sudo` access, `iptables`, `iproute2`, `netcat-openbsd`, `python3`

Check first:
```bash
which iptables ip nc python3
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This builds `client` → `router` → `upstream`, configures static
`SNAT` on `router` hardcoded to its current address (`192.0.2.10`),
confirms it works, then simulates a real address change: `router`'s
external address "renews" to `192.0.2.15`, and `upstream`'s ARP cache
for the old address is flushed (standing in for that cache naturally
expiring over time in a real network) so the incident is immediately
reproducible instead of something you'd have to wait an indeterminate
amount of time to see.

## Step 2 — Reproduce the symptom
```bash
sudo ip netns exec client bash -c 'echo hi | nc -w3 192.0.2.20 9200'
```
Times out. `client` itself hasn't changed anything.

## Step 3 — Compare the NAT rule against reality
```bash
sudo ip netns exec router iptables -t nat -L POSTROUTING -n -v
sudo ip netns exec router ip addr show veth-r-ext
```
The `SNAT` rule still says `to:192.0.2.10`. The interface it's
attached to now has `192.0.2.15`. `192.0.2.10` isn't bound to
anything on this host at all anymore.

## Step 4 — Fix it
```bash
sudo ip netns exec router iptables -t nat -F
sudo ip netns exec router iptables -t nat -A POSTROUTING -o veth-r-ext -j MASQUERADE
```
`MASQUERADE` doesn't need a hardcoded address — it asks the outgoing
interface what its current address is, for every connection, every
time.

## Step 5 — Verify
```bash
./check.sh
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the exact same misconfiguration, and it doesn't fail yet:**
```bash
./reset.sh
```
Before touching anything else, picture the sequence `setup.sh` just
ran: it changed `router`'s address, *then* explicitly flushed
`upstream`'s ARP cache, as two separate steps. What do you think
`nc -w3 192.0.2.20 9200` from `client` would have shown if `setup.sh`
had stopped right after changing the address, without that flush step
at all? Reason about it first, then confirm by inspecting
`upstream`'s ARP table for `192.0.2.10` right after `./reset.sh`
finishes:
```bash
sudo ip netns exec upstream ip neigh show
```
Work out what state that stale entry is in, why it would let traffic
through anyway for a while, and what that implies about how long a
newly-introduced stale-`SNAT` misconfiguration can sit completely
invisible in production before an unrelated, unremarkable event (an
ARP cache entry finally expiring, a switch reboot, anything that
forces re-resolution) makes it fail for what looks like no reason at
all.

**Challenge B — the quick fix works, right up until it doesn't, again:**
```bash
./reset.sh
sudo ip netns exec router iptables -t nat -F
sudo ip netns exec router iptables -t nat -A POSTROUTING -o veth-r-ext -j SNAT --to-source 192.0.2.15
sudo ip netns exec upstream ip neigh flush all
sudo ip netns exec client bash -c 'echo hi | nc -w3 192.0.2.20 9200'
```
Works — updating the hardcoded address to match reality is a
completely valid fix, and it's tempting to stop right there since the
symptom is gone. Now simulate one more renewal, the same way
`setup.sh` did the first one:
```bash
sudo ip netns exec router ip addr del 192.0.2.15/24 dev veth-r-ext
sudo ip netns exec router ip addr add 192.0.2.25/24 dev veth-r-ext
sudo ip netns exec upstream ip neigh flush all
sudo ip netns exec client bash -c 'echo hi | nc -w3 192.0.2.20 9200'
```
Broken again, from the exact same underlying cause. Compare this
against what `Step 4`'s fix (`MASQUERADE`) would do faced with this
exact same second address change, with zero rule changes of any kind.
What does "fixed" actually mean here, if the same category of event
just breaks it again?

See `solution.md` only after you've formed your own diagnosis.
