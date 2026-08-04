# Lab 20 — Solutions

## Challenge A — old narrow rule re-added below the fix

**Check:**
```bash
docker exec clab-natexh-router iptables -t nat -L POSTROUTING -n -v --line-numbers
```
Four rules now exist. The re-added `MASQUERADE --to-ports 40000-40004` rule
sits *above* the two SNAT rules from Step 7 (appended after them means it
landed at the bottom of the list as printed here, but check the actual
rule order you produced — whichever MASQUERADE/SNAT rule matches first
for a given packet is the one that counts). Run the test and check counters
again: the first matching rule for `192.168.50.0/24 -> eth2` traffic is
accumulating all the hits; the other rules stay at 0.

**Diagnosis:** `iptables` chains are evaluated top to bottom, first match
wins, full stop. It doesn't matter that the "correct," dual-IP fix from
Step 7 is present and perfectly configured — if an earlier rule already
matches the same traffic, the later rules never get evaluated at all. This
is functionally identical to Lab 4's Challenge B lesson (a rule doing
nothing despite being syntactically correct) but for a different reason:
there it was the wrong interface: here it's the wrong *position*.

**Fix:**
```bash
docker exec clab-natexh-router iptables -t nat -D POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -j MASQUERADE --to-ports 40000-40004
```

**Lesson:** "the fix is in the ruleset" and "the fix is what's actually
running" are not the same claim. Whenever a NAT/firewall change doesn't
seem to take effect, check rule *order* and hit *counters*
(`-L -n -v --line-numbers`) before assuming the new rule is broken — it's
very often an old rule still winning the race.

---

## Challenge B — 14 connections against a 10-port ceiling

**Check:**
```bash
docker exec clab-natexh-router conntrack -L -p tcp --dport 9000 2>/dev/null | wc -l
```
Caps at 10, split across both `.1` and `.21`'s 5-port pools. 4 of the 14
attempts fail — but this time it's not a rule-ordering bug. Every rule from
Step 7 is present, correctly ordered, and doing exactly what it's supposed
to do.

**Diagnosis:** the dual-IP fix doubled the ceiling from 5 to 10 — it didn't
remove the ceiling. Adding capacity is not the same as adding unlimited
capacity. This is the entire lesson of the lab compressed into one
scenario: no amount of iptables cleverness invents a port that doesn't
exist. Two IPs at 5 ports each is still only 10 ports.

**Fix (either is legitimate; pick based on what's actually true in
production):**
```bash
# Option 1: add a third public IP and a third SNAT rule
docker exec clab-natexh-router ip addr add 203.0.113.22/24 dev eth2
docker exec clab-natexh-router iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -m statistic --mode nth --every 3 --packet 0 \
  -j SNAT --to-source 203.0.113.1:40000-40004
# (and rebalance the remaining rules across .21 and .22 the same way)

# Option 2: reduce concurrent connection volume instead — connection
# pooling/reuse at the application layer so you need fewer simultaneous
# outbound sessions in the first place, rather than more IP addresses
```

**Lesson:** once you've confirmed the ceiling is real port math and not a
misconfiguration, there are exactly two levers: more public IPs (horizontal
scaling of the port pool) or fewer concurrent connections (reducing demand
on the pool you have). Everything else — bigger conntrack tables, tweaking
timeouts, restarting the router — treats the symptom, not the ceiling.
