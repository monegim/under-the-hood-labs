# Lab 28 — The IPv4-Only Firewall Rule and the IPv6 Gap

## Objective
Lock a port down with `iptables`, confirm it's blocked — then discover
the exact same port is still wide open over IPv6, because `ip6tables`
was never touched at all.

## Why this matters
`iptables` and `ip6tables` are two completely separate rule sets,
maintained independently, with no automatic synchronization between
them whatsoever. A firewall change that only updates `iptables` — which
is what most tutorials, most muscle memory, and most `iptables ...`
copy-pasted from an incident runbook actually do — leaves IPv6 traffic
to the exact same service completely unaffected. On a dual-stack host
(which is most hosts, by default, today), "I blocked that port" can be
true and false at the same time depending on which protocol you test
with, and testing with only one is how this goes unnoticed.

## Prerequisites
- A Linux VM, `sudo` access, `iptables`, `ip6tables`, `netcat-openbsd`
  (with IPv6 support — `nc -6`)

Check first:
```bash
which iptables ip6tables
nc -6 -h 2>&1 | head -1
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates `ns1` and `ns2`, both addressed for IPv4 (`10.20.0.0/24`)
and IPv6 (a `fd00:26::/64` unique local prefix), with `ns2` listening
on port 9090 over both. `iptables` inside `ns2` blocks the port over
IPv4; `ip6tables` is left completely untouched.

## Step 2 — Confirm the "fix" over IPv4
```bash
sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.20.0.2 9090'; echo "exit: $?"
```
Blocked, as expected.

## Step 3 — Test the exact same thing over IPv6
```bash
sudo ip netns exec ns1 bash -c 'echo hi | nc -6 -w2 fd00:26::2 9090'; echo "exit: $?"
```
Succeeds. Same service, same port, same source namespace — a
completely different outcome, because it went through a completely
different rule set.

## Step 4 — Confirm exactly why
```bash
sudo ip netns exec ns2 iptables -L INPUT -n
sudo ip netns exec ns2 ip6tables -L INPUT -n
```
`iptables` has the `DROP` rule; `ip6tables` has nothing at all —
default policy, no rules, wide open.

## Step 5 — Fix it: mirror the rule
```bash
sudo ip netns exec ns2 ip6tables -A INPUT -p tcp --dport 9090 -j DROP
```

## Step 6 — Verify parity
```bash
sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.20.0.2 9090'; echo "exit (v4): $?"
sudo ip netns exec ns1 bash -c 'echo hi | nc -6 -w2 fd00:26::2 9090'; echo "exit (v6): $?"
```
Both should now fail the same way.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the blunt "fix":**
```bash
sudo ip netns exec ns2 ip6tables -F
sudo ip netns exec ns2 sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo ip netns exec ns1 bash -c 'echo hi | nc -6 -w2 fd00:26::2 9090'; echo "exit: $?"
```
This "works" — IPv6 connectivity fails entirely now, port 9090 included.
Explain exactly what else this breaks that a scoped `ip6tables` rule
wouldn't have, and why "disable the whole protocol" is a fundamentally
different, much blunter kind of fix than "block this one port on this
one protocol" — even though both make this specific test pass.

**Challenge B — rules that drifted apart over time:**
```bash
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 ip6tables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 9090 -j DROP
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 2222 -j DROP
sudo ip netns exec ns2 ip6tables -A INPUT -p tcp --dport 9090 -j DROP
```
Two ports were supposed to be blocked (9090 and 2222) — an earlier
change added `2222` to the IPv4 rule set at some point and the IPv6
rule set was never updated to match, and now nobody remembers which
list is the "real" one. Compare both chains directly and figure out a
way to reliably catch this kind of *silent two-rule-sets drift* going
forward, beyond "remember to update both every time."

See `solution.md` only after you've formed your own diagnosis.
