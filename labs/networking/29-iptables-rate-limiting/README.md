# Lab 29 — iptables Rate Limiting

## Objective
Protect a service from a connection flood with real rate limiting —
then discover that a naive `-m limit` rule shares its budget across
*everyone*, meaning one noisy client can still lock out every
legitimate one too, just via a different mechanism than having no
limit at all.

## Why this matters
Rate limiting sounds like a solved problem once you've added *a* rule
that throttles *something* — but "throttled" and "throttled per source,
fairly" are different guarantees, and the difference only shows up once
there's more than one client in the picture. A rate limit that's
actually a single shared token bucket for the whole rule protects the
service from total volume, but does nothing to stop one bad actor from
consuming the entire budget and taking every well-behaved client down
with them — which, from a user's perspective, is a self-inflicted
outage that looks exactly like the flood you were trying to prevent.

## Prerequisites
- A Linux VM, `sudo` access, `iptables`, `netcat-openbsd`

Check first:
```bash
which iptables nc
iptables -m limit --help 2>&1 | head -3
iptables -m hashlimit --help 2>&1 | head -3
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates a bridge with three namespaces: `ns1` (a client that's
about to play the role of a noisy/flooding source), `ns2` (the server,
listening on port 7000), and `ns3` (a second, well-behaved client).
`ns2` starts with no rate limiting at all.

## Step 2 — Confirm it's currently unprotected
```bash
sudo ip netns exec ns1 bash -c 'for i in $(seq 1 20); do echo hi | nc -w1 10.30.0.2 7000; done'
```
All 20 succeed — nothing is throttling this at all.

## Step 3 — Add rate limiting
```bash
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -m limit --limit 5/min --limit-burst 5 -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -j REJECT
```

## Step 4 — Confirm it throttles the flood
```bash
sudo ip netns exec ns1 bash -c 'for i in $(seq 1 15); do echo hi | nc -w1 10.30.0.2 7000; echo "  attempt $i: $?"; done'
```
The first few succeed (the burst allowance), then most start failing.

## Step 5 — Now check whether ns3 can still get through
```bash
sudo ip netns exec ns3 bash -c 'echo hi | nc -w2 10.30.0.2 7000'; echo "exit: $?"
```
Run this *while ns1 is still actively flooding* (or right after) —
does `ns3`, which never sent more than one request, still get through?

## Step 6 — Fix it properly: per-source limiting
```bash
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 \
  -m hashlimit --hashlimit-name flood7000 --hashlimit-mode srcip \
  --hashlimit-upto 5/min --hashlimit-burst 5 -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -j REJECT
```
`hashlimit` with `--hashlimit-mode srcip` keeps a *separate* budget per
source IP, instead of one shared budget for the whole rule.

## Step 7 — Verify
```bash
sudo ip netns exec ns1 bash -c 'for i in $(seq 1 15); do echo hi | nc -w1 10.30.0.2 7000; done'
sudo ip netns exec ns3 bash -c 'echo hi | nc -w2 10.30.0.2 7000'; echo "ns3 exit: $?"
```
`ns1`'s flood is still throttled — but `ns3` now succeeds regardless of
how hard `ns1` is hammering the service.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — confirm you understand exactly why Step 4/5 failed the way they did:**
```bash
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -m limit --limit 5/min --limit-burst 5 -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -j REJECT
sudo ip netns exec ns1 bash -c 'for i in $(seq 1 10); do echo hi | nc -w1 10.30.0.2 7000 >/dev/null 2>&1; done'
sudo ip netns exec ns3 bash -c 'echo hi | nc -w2 10.30.0.2 7000'; echo "ns3 exit: $?"
```
Before looking at `solution.md`: explain in your own words, precisely,
what `-m limit`'s "budget" actually belongs to — one client, the whole
rule, something else — and why that answer means `ns3`'s single,
perfectly reasonable request can fail here.

**Challenge B — a limit tuned too tight for real traffic:**
```bash
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 \
  -m hashlimit --hashlimit-name tootight --hashlimit-mode srcip \
  --hashlimit-upto 2/min --hashlimit-burst 1 -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -j REJECT

sudo ip netns exec ns3 bash -c 'for i in 1 2 3; do echo hi | nc -w1 10.30.0.2 7000; echo "  attempt $i: $?"; done'
```
`ns3` is doing nothing unreasonable — three quick, ordinary requests,
the kind a normal client (a browser opening a few connections for one
page load, a health check retrying once) does all the time — and most
of them fail. This is per-source limiting working *exactly as
configured*, and still wrong. Figure out what specifically about
`--hashlimit-burst 1` makes even light, completely normal traffic
patterns fail, and pick values that would actually tolerate this.

See `solution.md` only after you've formed your own diagnosis.
