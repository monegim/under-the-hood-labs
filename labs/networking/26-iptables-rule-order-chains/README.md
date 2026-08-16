# Lab 26 — iptables Rule Order and Custom Chains

## Objective
Diagnose why a correctly-written allow-list rule inside a custom chain
never actually takes effect — the chain itself is fine, the *order* the
main chain reaches it in is the bug.

## Why this matters
`iptables` evaluates a chain's rules top to bottom and stops at the
first match — there's no "check every rule and pick the most specific
one" logic, no reordering by priority. A broad rule earlier in the
chain — especially a catch-all `DROP`/`ACCEPT` — permanently shadows
every rule after it for any packet that matches the broad one first,
including jumps to custom chains that look, read in isolation,
completely correct. This is one of the most common real iptables
mistakes, and it's specifically hard to spot by reading the custom
chain alone — you have to read the *calling* chain's order too.

## Prerequisites
- A Linux VM, `sudo` access, `iptables`, `netcat-openbsd` (or any `nc`
  that supports `-lk`)

Check first:
```bash
which iptables nc
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates `ns1` (client) and `ns2` (server, listening on TCP 8080),
connected by a veth pair, and builds a ruleset inside `ns2`: a custom
chain `ALLOWED` with a correct rule allowing `ns1`'s address, and an
`INPUT` chain that jumps to it — but only *after* a catch-all `DROP`.

## Step 2 — Reproduce the symptom
```bash
sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.10.0.2 8080'; echo "exit: $?"
```
Fails, despite the `ALLOWED` chain having exactly the rule that should
let this through.

## Step 3 — Read the chain in order, not in isolation
```bash
sudo ip netns exec ns2 iptables -L INPUT -n -v --line-numbers
```
Read every rule from the top. Find where the jump to `ALLOWED` sits
relative to the `DROP` rule.

## Step 4 — Confirm with counters
```bash
sudo ip netns exec ns2 iptables -Z    # zero all counters
sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.10.0.2 8080' >/dev/null 2>&1
sudo ip netns exec ns2 iptables -L INPUT -n -v
sudo ip netns exec ns2 iptables -L ALLOWED -n -v
```
The `DROP` rule's packet counter increments; `ALLOWED`'s stays at zero
— direct proof the jump is never reached.

## Step 5 — Fix the order
```bash
sudo ip netns exec ns2 iptables -D INPUT -j DROP
sudo ip netns exec ns2 iptables -A INPUT -j DROP
```
(Delete the catch-all `DROP` and re-append it — putting it back at the
very end, after the jump to `ALLOWED` instead of before it. In a real
ruleset you'd more surgically `-I INPUT <line-number>` the jump above
the `DROP` instead of deleting/re-adding, but the end effect is the
same: specific rules before the catch-all, always.)

## Step 6 — Verify
```bash
sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.10.0.2 8080'; echo "exit: $?"
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a jump that "falls through" instead of deciding:**
```bash
sudo ip netns exec ns2 iptables -F INPUT
sudo ip netns exec ns2 iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 8080 -j ALLOWED
sudo ip netns exec ns2 iptables -A INPUT -j ACCEPT
```
Traffic from a source that's *not* in `ALLOWED`'s allow-list still gets
through. Read `iptables -L INPUT -n -v --line-numbers` again and figure
out exactly what happens when a packet enters a custom chain, matches
none of its rules, and reaches the end of it — does it get dropped
there, or does something else happen?

**Challenge B — appended after the point of no return:**
```bash
sudo ip netns exec ns2 iptables -F INPUT
sudo ip netns exec ns2 iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -j DROP
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 8080 -s 10.10.0.1 -j ACCEPT
```
A specific, correctly-written `ACCEPT` rule for exactly the right
source and port — still doesn't work. This is the same symptom as the
main lab, produced a different way: figure out precisely which
`iptables` flag was used here that guarantees this outcome no matter
what the rule itself says, and what the one-character difference is
that would have prevented it.

See `solution.md` only after you've formed your own diagnosis.
