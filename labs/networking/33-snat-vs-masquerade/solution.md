# Lab 33 — Solution

## Root cause

`router`'s `SNAT` rule rewrites every outbound packet's source address
to a literal, hardcoded value (`192.0.2.10`) that was correct at the
moment the rule was written. `SNAT` never re-checks that value against
anything — it has no concept of "the address I should be using," only
"the address I was told to use." When `router`'s external interface
address genuinely changes (a DHCP renewal, a failover, any real-world
address reassignment), the `SNAT` rule keeps producing packets with a
source address that no longer belongs to any interface on the host at
all. `upstream` (or anything further upstream) has no way to route a
reply back to an address that isn't actually claimed by anything -
from `client`'s point of view, the connection just hangs and times
out.

## Why it happened

`SNAT` and `MASQUERADE` are frequently presented as near-equivalent -
both rewrite source addresses for outbound NAT, and on a host with a
genuinely static address they behave identically forever. The
difference only exists, and only matters, the moment the address
itself changes - which is exactly the scenario easiest to overlook
when first configuring NAT on what looks, at the time, like a stable
setup. `SNAT` was very likely chosen because it's marginally cheaper
(it doesn't need to look up the outgoing interface's current address
on every packet) or because the address genuinely was static when the
rule was written - neither of those makes it the wrong choice
*generally*, but both stop being true the moment "static" turns out to
have been temporary.

## Why the obvious fixes don't work

- **Restarting `router` or reloading `iptables`**: doesn't help - the
  `SNAT` rule's hardcoded address doesn't change on a restart, because
  nothing about a restart re-evaluates what that address should be.
- **Adding a route or fixing `client`'s config**: `client` never
  changed anything and has no visibility into what `router` rewrites
  its packets to - there's nothing on the client side to fix.
- **Waiting**: the address `router` is rewriting to isn't coming back
  - it was reassigned to nothing, or to something else entirely. This
    doesn't self-heal.

## The investigation

Confirm the symptom:
```bash
sudo ip netns exec client bash -c 'echo hi | nc -w3 192.0.2.20 9200'
```

Compare the NAT rule's target against the interface's actual current
address:
```bash
sudo ip netns exec router iptables -t nat -L POSTROUTING -n -v
sudo ip netns exec router ip addr show veth-r-ext
```
The rule references an address the interface simply doesn't have
anymore.

## The fix

```bash
sudo ip netns exec router iptables -t nat -F
sudo ip netns exec router iptables -t nat -A POSTROUTING -o veth-r-ext -j MASQUERADE
```
`MASQUERADE` looks up the outgoing interface's address at the time
each connection is established, rather than using a value fixed at
configuration time - it's the correct default any time the outbound
interface's address isn't a genuine, permanent constant.

---

## Challenge A — the exact same misconfiguration, and it doesn't fail yet

**Check:**
```bash
sudo ip netns exec upstream ip neigh show
```
The entry for `192.0.2.10` shows `STALE` (or `REACHABLE`, depending on
exact timing) rather than being absent.

**Diagnosis:** ARP resolution is cached, deliberately, so every packet
doesn't need a fresh ARP request - Linux (and every other IP stack)
keeps a neighbor table mapping IP addresses to link-layer addresses,
refreshed only periodically or on demand. Immediately after `router`'s
address changes, `upstream`'s ARP cache still has an entry mapping the
*old* address to `router`'s (unchanged) MAC address from before the
change. As long as that entry is still considered valid, `upstream`
keeps sending replies straight to `router`'s network interface
regardless of what IP address is actually configured on it -
`192.0.2.10` doesn't need to "exist" anywhere for the Ethernet frame to
physically arrive; ARP only needed to resolve it once, in the past.
The `SNAT` misconfiguration is real and complete the instant the
address changes - but its *effect* is delayed by however long the
stale cache entry survives, which in production is exactly the kind of
unpredictable, unrelated-looking trigger (a switch reboot, an ARP
table eviction under memory pressure, an idle timeout) that makes
"what changed right before this started" genuinely misleading.

**Lesson:** the moment a misconfiguration is introduced and the moment
it actually causes an outage can be two completely different points in
time, separated by an unrelated caching layer neither side of the
connection was thinking about. Confirming a fix "works" needs to
survive a fresh cache/re-resolution, not just an immediate retry -
`setup.sh`'s explicit ARP flush exists specifically to not let this
lab lie to you about being reproducible on demand.

---

## Challenge B — the quick fix works, right up until it doesn't, again

**Check:**
```bash
sudo ip netns exec router ip addr del 192.0.2.15/24 dev veth-r-ext
sudo ip netns exec router ip addr add 192.0.2.25/24 dev veth-r-ext
sudo ip netns exec upstream ip neigh flush all
sudo ip netns exec client bash -c 'echo hi | nc -w3 192.0.2.20 9200'
```
Broken again, identically, after updating the `SNAT` rule to match the
address once and then hitting a second, unrelated address change.

**Diagnosis:** updating `--to-source` to the new address is a
completely correct fix *for that one specific address change* - it's
not a mistake, it's just scoped to a single point in time the same way
the original rule was. `SNAT` fundamentally cannot express "whatever
the interface's address happens to be" - only "this literal value,"
which means any `SNAT`-based fix to this exact problem is only ever
correct until the next time the address changes, at which point the
identical failure recurs, requiring the identical manual intervention
again. `MASQUERADE`, configured once, needed zero changes across both
address changes in this lab, because it was never expressing a
specific address to begin with - it was expressing "whatever this
interface currently has," evaluated fresh every time.

**Lesson:** "the fix worked" and "the fix survives the next occurrence
of the same event" are different claims, and confusing them for
`SNAT` on a non-static address specifically produces a recurring
incident that looks, every single time, exactly like a fresh
regression - because from `SNAT`'s point of view, it genuinely is one.
If the underlying address is capable of changing at all, `MASQUERADE`
isn't just the more convenient choice, it's the one whose fix
generalizes past the specific incident that prompted it.
