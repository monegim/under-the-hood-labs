# Lab 1 — Solutions

## Challenge A — interface down

**Check:**
```bash
sudo ip netns exec ns1 ip link show veth1
```
State shows `DOWN`.

**Diagnosis:** the link itself is administratively down — nothing to do with
IP addressing or routing. This is a "layer 1/2" problem, not a "layer 3" one.

**Fix:**
```bash
sudo ip netns exec ns1 ip link set veth1 up
```

**Lesson:** always check link state (`ip link`) before you check IP/routing.
Cheap check, rules out a whole category of problems in one command.

---

## Challenge B — address removed

**Check:**
```bash
sudo ip netns exec ns2 ip a
```
`veth2` is UP, but has no IP address — `ping` from ns1 will hang/fail with a
different signature (ARP requests going unanswered) than Challenge A.

**Diagnosis:** layer 2 is fine (the cable and interface are up), but layer 3
addressing is missing. This is why checking `ip link` alone isn't enough —
you need both link state and address state.

**Fix:**
```bash
sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
```

**Lesson:** "can't reach X" has at least two different root causes at two
different layers, and they look different if you know what to check
(`ip link` vs `ip addr`) — this is the core skill: always separate "is the
link up" from "is it addressed" from "is it routed."
