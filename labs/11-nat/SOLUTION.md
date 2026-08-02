# Lab 11 — Solutions

## Challenge A — MASQUERADE rule removed

**Check:**
```bash
docker exec clab-nat-router iptables -t nat -L POSTROUTING -n -v
```
The `nat` table's `POSTROUTING` chain is empty — no MASQUERADE rule at all.

**Diagnosis:** NAT translation for outbound traffic isn't happening
anymore. `host-int`'s packets leave the router still sourced as
`192.168.100.10`, and `host-ext` (which has no route back to that private
range) can't reply. Identical symptom to "no NAT configured yet" back in
Step 4.

**Fix:**
```bash
docker exec clab-nat-router iptables -t nat -A POSTROUTING -o eth2 -s 192.168.100.0/24 -j MASQUERADE
```

**Lesson:** NAT rules live in a separate table (`-t nat`) from your regular
filter rules. A config-management tool or backup/restore script that only
handles the filter table (a bare `iptables-save`/`-restore` without `-t
nat`, or a rule-sync job that forgot the nat table) will silently wipe your
NAT behavior, and nothing will look wrong in the `FORWARD` chain — you have
to check the nat table specifically.

---

## Challenge B — MASQUERADE bound to the wrong interface

**Check:**
```bash
docker exec clab-nat-router iptables -t nat -L POSTROUTING -n -v
```
The rule is there, but its packet/byte counters stay at `0` no matter how
many pings you send.

**Diagnosis:** the rule says `-o eth1`, but `host-int`'s traffic to
`host-ext` leaves the router via `eth2` (the external interface). A
`POSTROUTING` rule only fires for packets actually egressing the named
interface — `eth1` traffic in this direction never happens, so this rule
can never match, no matter how correct it looks written down. A rule
existing in the table is not the same as a rule doing anything.

**Fix:**
```bash
docker exec clab-nat-router iptables -t nat -D POSTROUTING -o eth1 -s 192.168.100.0/24 -j MASQUERADE
docker exec clab-nat-router iptables -t nat -A POSTROUTING -o eth2 -s 192.168.100.0/24 -j MASQUERADE
```

**Lesson:** always check hit counters (`-v`), not just rule presence. A
rule with a wrong match criterion — wrong interface, wrong source, wrong
anything — sits in the table silently doing nothing forever, and a plain
`iptables -L` without counters won't tell you that. This is exactly the
failure mode of a templated rule with the wrong variable substituted (e.g.
an Ansible/Terraform iptables role handed `$internal_if` where it needed
`$external_if`).
