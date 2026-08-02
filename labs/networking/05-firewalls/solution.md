# Lab 5 — Solutions

## Challenge A — chain flushed, policy still DROP

**Check:**
```bash
docker exec clab-firewalls-fw iptables -L FORWARD -v -n
```
Zero rules, and `Chain FORWARD (policy DROP)`.

**Diagnosis:** `-F` only empties the chain's rule list — it does not touch
the chain's default policy. The policy was set to DROP back in Step 3, so
an empty chain now drops literally everything. This looks identical to
"nothing configured yet," but it's actually worse: five seconds ago this
was a working, deliberately-configured firewall.

**Fix:** re-add the rules from Steps 4-5 (or better: keep them in a script
you re-apply, not retyped by hand under pressure):
```bash
docker exec clab-firewalls-fw iptables -A FORWARD -i eth1 -o eth2 -p icmp --icmp-type echo-request -j ACCEPT
docker exec clab-firewalls-fw iptables -A FORWARD -i eth1 -o eth2 -p tcp --dport 80 -j ACCEPT
docker exec clab-firewalls-fw iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
```

**Lesson:** a chain's policy and its rule list are two independent pieces
of state. "Flushing the firewall" during a maintenance window doesn't
reset you to a known-good default — it resets you to whatever the policy
is, which after Step 3 is drop-everything.

---

## Challenge B — rule order breaks an established flow

**Check:**
```bash
docker exec clab-firewalls-fw iptables -L FORWARD -v -n --line-numbers
```
The new DROP rule sits at line 1, ahead of the `ESTABLISHED,RELATED` ACCEPT
rule.

**Diagnosis:** `iptables` evaluates rules top-to-bottom, first match wins.
The server's TCP replies (SYN-ACK, ACK, data) all have source port 80 —
exactly what the new rule matches — and it now sits above the
`ESTABLISHED,RELATED` rule that used to wave all of that through. The
client's SYN still reaches the server fine (that direction is untouched),
but every reply packet is dropped before the chain ever reaches the rule
that would have accepted it as return traffic. ICMP ping is unaffected
because it doesn't use TCP ports — the `--sport 80` match never applies to
it, a different protocol sailing straight past a rule that only targets
TCP/80.

**Fix:**
```bash
docker exec clab-firewalls-fw iptables -D FORWARD -p tcp --sport 80 -j DROP
```
(or, if a rule like this is genuinely needed, place it below the
`ESTABLISHED,RELATED` accept, not above it)

**Lesson:** where you insert a rule matters as much as what the rule says.
`-I chain 1` always wins the position race against everything already
there, including your stateful "allow return traffic" rule — a "quick fix"
inserted at the top of a chain can silently break flows nobody touched.
