# Lab 2 — Solutions

## Challenge A — port moved to the wrong VLAN

**Check:**
```bash
bridge vlan show dev veth2-br
```
Shows `vid 20 PVID Egress Untagged` instead of `vid 10`.

**Diagnosis:** `veth2-br`'s access VLAN was changed from 10 to 20. `ns2`
didn't lose connectivity in the usual sense — it moved to an entirely
different broadcast domain. It lost `ns1` (its old VLAN) and is now in the
same L2 domain as `ns3`/`ns4` (though it keeps its old `10.10.0.0/24`
address, so it won't have full IP reachability there either without
re-addressing). Real production analog: a switch port gets re-provisioned
for a different rack or tenant and the cabling/labeling documentation isn't
updated to match.

**Fix:**
```bash
sudo bridge vlan del dev veth2-br vid 20
sudo bridge vlan add dev veth2-br vid 10 pvid untagged
```

**Lesson:** "ping stopped working" can mean the device moved to the wrong
network, not that the network broke. Always check which VLAN/PVID a port
is actually in (`bridge vlan show`) before assuming a routing or link
problem.

---

## Challenge B — trunk missing a VLAN

**Check:**
```bash
bridge vlan show dev veth5-br
```
`vid 20` is gone from the trunk port's allowed list — only `vid 10`
remains tagged.

**Diagnosis:** the router's `veth5.20` sub-interface is still fully
configured and expects VLAN 20-tagged frames, but the bridge trunk port was
never told to carry VLAN 20 anymore. This is the exact same failure class
as forgetting `switchport trunk allowed vlan add 20` on a real switch —
one end of the trunk is correctly configured, the other end silently
dropped support for that VLAN.

**Fix:**
```bash
sudo bridge vlan add dev veth5-br vid 20
```

**Lesson:** a VLAN sub-interface being configured correctly on one end of a
trunk means nothing if the trunk itself doesn't carry that VLAN. Always
check both ends — the trunk's allowed-VLAN list *and* the sub-interface —
not just the one that's easiest to look at.
