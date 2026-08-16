# Lab 28 — Solutions

## Challenge A — the blunt "fix"

**Check:**
```bash
sudo ip netns exec ns1 bash -c 'echo hi | nc -6 -w2 fd00:26::2 9090'; echo "exit: $?"
sudo ip netns exec ns1 ping6 -c2 fd00:26::2
```
Port 9090 is unreachable, but so is *everything else* over IPv6 —
`ping6` fails too.

**Diagnosis:** `net.ipv6.conf.all.disable_ipv6=1` doesn't add a firewall
rule at all — it tears down IPv6 networking on the interface(s)
entirely, at the kernel level, below where any firewall would even see
traffic. The test in this challenge passes for a completely different
reason than the intended fix: not "port 9090 is blocked over IPv6," but
"IPv6 doesn't work at all anymore, for anything." Any other service on
this host that's supposed to be reachable over IPv6 — SSH, monitoring
agents, other application ports, IPv6-only peers — breaks at the same
time, silently, as a side effect nobody asked for.

**Fix:** re-enable IPv6 and use the scoped fix instead:
```bash
sudo ip netns exec ns2 sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo ip netns exec ns2 ip6tables -A INPUT -p tcp --dport 9090 -j DROP
```

**Lesson:** always prefer the fix scoped to exactly the thing that's
actually wrong. "Disable IPv6 globally" and "block this one port over
IPv6" can produce an identical result for the one test case you're
looking at, and completely different results for everything else on
the box — a fix should be evaluated by what it does to things you
*aren't* currently testing, not just the one symptom in front of you.

---

## Challenge B — rules that drifted apart over time

**Check:**
```bash
sudo ip netns exec ns2 iptables -S INPUT
sudo ip netns exec ns2 ip6tables -S INPUT
```
`iptables` blocks both 9090 and 2222; `ip6tables` blocks only 9090 —
port 2222 is open over IPv6 and nobody currently looking at either
ruleset in isolation would notice, because both individually look like
complete, sensible rule sets.

**Diagnosis:** there's no mechanism keeping `iptables` and `ip6tables`
in sync — every rule change made against one has to be manually,
separately, remembered and applied to the other, forever, and every
single change is an opportunity for the two to drift a little further
apart. This isn't a one-time mistake to fix; it's a structural gap that
recurs every time someone touches either rule set without touching the
other, and it gets harder to notice the longer the two lists have been
allowed to diverge.

**Fix (this instance):**
```bash
sudo ip netns exec ns2 ip6tables -A INPUT -p tcp --dport 2222 -j DROP
```
**Fix (the actual pattern):** the durable answer isn't "be more careful"
— it's removing the opportunity for drift entirely. Tools like
`nftables` (the netfilter successor to `iptables`/`ip6tables`) let you
write address-family-agnostic rules in a single ruleset, evaluated for
both IPv4 and IPv6 from one definition — the two-separate-lists problem
this whole lab is about doesn't exist there by construction, not by
discipline.

**Lesson:** any time a system requires the same logical change applied
identically in two or more independent places, treat the *requirement
to remember* as the actual bug, not each individual missed instance of
it. Where possible, replace "remember to update both" with tooling that
makes divergence structurally impossible rather than just less likely.
