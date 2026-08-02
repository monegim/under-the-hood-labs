# Lab 1 — Solutions

## Challenge A — host-side port left down

**Check:**
```bash
ip link show veth1-br
```
State shows `DOWN`, even though it's correctly enslaved to `br0`.

**Diagnosis:** `master br0` and administrative up/down are two independent
settings. The port is attached to the bridge, but a down port forwards
nothing — this is the exact mistake most people make the first time they
wire a bridge by hand instead of letting Docker/a CNI plugin do both steps
for them.

**Fix:**
```bash
sudo ip link set veth1-br up
```

**Lesson:** enslavement ("this port belongs to this bridge") and link state
("this port is on") are separate. Always check both when a bridge port
isn't forwarding.

---

## Challenge B — bridge itself down

**Check:**
```bash
ip -d link show br0
bridge link show
```
`br0` itself shows `state DOWN`, while `veth1-br`/`veth2-br` individually
still show up and enslaved.

**Diagnosis:** the bridge device is the "switch chassis" — if it's
administratively down, it doesn't matter that every individual port is up.
No frames get forwarded between ports at all, regardless of their own state.

**Fix:**
```bash
sudo ip link set br0 up
```

**Lesson:** when L2 forwarding breaks, check the state of the bridge
*master* device itself, not just its ports — the equivalent of checking
whether a real switch's backplane is powered on before you start checking
individual port lights.
