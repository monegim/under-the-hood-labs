# Lab 29 — Solutions

## Challenge A — confirm you understand exactly why Step 4/5 failed the way they did

**Check:**
```bash
sudo ip netns exec ns3 bash -c 'echo hi | nc -w2 10.30.0.2 7000'; echo "ns3 exit: $?"
```
Fails, or succeeds only inconsistently, depending on exactly how
recently `ns1`'s flood consumed the shared budget.

**Diagnosis:** `-m limit --limit 5/min --limit-burst 5` maintains
**one single token bucket for the entire rule** — every packet that
matches the rule's other conditions (here, `-p tcp --dport 7000`,
regardless of source) draws from that same bucket, no matter which
client sent it. It has no concept of "source" at all; it's counting
matching packets against the rule, full stop. `ns1`'s flood and `ns3`'s
one polite request are, as far as this rule is concerned, completely
indistinguishable — both are just "another packet matching this rule,"
competing for the same five-per-minute allowance. If `ns1` drains it
first, `ns3` finds an empty bucket regardless of how reasonable its own
behavior was.

**Fix:** switch to `hashlimit` with `--hashlimit-mode srcip`, which
maintains a *separate* bucket keyed by source IP — `ns1` and `ns3` each
get their own five-per-minute allowance, and one exhausting theirs has
zero effect on the other's.

**Lesson:** "rate limited" is not one guarantee — a shared/global limit
protects the service's aggregate capacity but offers zero fairness
between sources; a per-source limit protects each source's fair share
but doesn't cap the service's total exposure if enough distinct sources
show up at once (which `hashlimit`'s own overall ceiling options can
additionally bound, but that's a different knob again). Know which
property you actually need before picking the module and mode.

---

## Challenge B — a limit tuned too tight for real traffic

**Check:**
```bash
sudo ip netns exec ns3 bash -c 'for i in 1 2 3; do echo hi | nc -w1 10.30.0.2 7000; echo "  attempt $i: $?"; done'
```
Only the first attempt reliably succeeds; the second and third usually
fail, even though this is exactly the kind of light, ordinary traffic
the rule is supposed to tolerate.

**Diagnosis:** `--hashlimit-burst 1` means each source's bucket holds
exactly *one* token above the steady drip rate (`--hashlimit-upto
2/min`, refilling roughly once every 30 seconds) — the very first
request drains it completely, and anything else arriving before the
next slow refill gets rejected outright. A burst allowance that small
has no tolerance for even mildly bursty, completely normal client
behavior (a page load opening a couple of connections close together, a
health check retrying once after a transient blip) — it's tuned for a
traffic pattern ("exactly one request, ever, then wait a full 30+
seconds") that essentially no real client actually produces.

**Fix:** size the burst allowance around what legitimate traffic
actually looks like, not the smallest number that technically "works":
```bash
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 \
  -m hashlimit --hashlimit-name tuned --hashlimit-mode srcip \
  --hashlimit-upto 10/min --hashlimit-burst 5 -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 7000 -j REJECT
```

**Lesson:** a rate limit that technically works (it does limit
*something*) can still be the wrong fix if it doesn't account for what
normal usage actually looks like — "does this throttle an attacker" and
"does this tolerate a legitimate user" are two separate questions a
rate-limit configuration has to answer correctly at the same time, and
testing only the attack case (as this lab's earlier steps did) won't
catch a burst value that's too aggressive for real traffic.
