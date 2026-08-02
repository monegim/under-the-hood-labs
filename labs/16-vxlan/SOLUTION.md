# Lab 16 — Solutions

## Challenge A — VNI mismatch

**Check:**
```bash
docker exec clab-vxlan-lab-r1 tcpdump -ni eth2 -c 5 udp port 4789
docker exec clab-vxlan-lab-r2 ip -s -d link show vxlan10
```
The capture on r1's underlay interface shows VXLAN frames going out fine —
r1's side never changed. But r2's `vxlan10` RX counters stay at zero: the
frames are arriving at r2's physical NIC (right UDP port, right
destination IP) but never get decapsulated onto r2's `vxlan10` device.

**Diagnosis:** r1 is still encapsulating with VNI 10, but r2's `vxlan10`
was recreated with VNI 20. The VXLAN header's VNI has to match a local
VXLAN device for the kernel to decapsulate the frame — r2's kernel receives
the UDP packet, sees a VNI it has no matching device for, and drops it
*after* it's already on the wire and past the physical NIC. That's why it
shows up in a capture on the underlay link but never shows up as
decapsulated traffic.

**Fix:**
```bash
docker exec clab-vxlan-lab-r2 ip link set vxlan10 nomaster
docker exec clab-vxlan-lab-r2 ip link del vxlan10
docker exec clab-vxlan-lab-r2 ip link add vxlan10 type vxlan id 10 dstport 4789 local 172.16.0.2 dev eth1
docker exec clab-vxlan-lab-r2 ip link set vxlan10 up
docker exec clab-vxlan-lab-r2 bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.1
docker exec clab-vxlan-lab-r2 ip link set vxlan10 master br0
```

**Lesson:** VXLAN failures can happen *after* the packet has visibly
crossed the underlay — "I can see it in tcpdump on the physical interface"
doesn't mean it made it into the overlay. Compare physical-interface
captures against the VXLAN device's own counters to find exactly which
side of decapsulation a frame is being lost on.

---

## Challenge B — missing FDB entry

**Check:**
```bash
docker exec clab-vxlan-lab-r1 tcpdump -ni eth2 -c 5 udp port 4789
```
Nothing leaves r1's underlay interface at all for hostA's traffic — not
even ARP requests.

```bash
docker exec clab-vxlan-lab-r1 bridge fdb show dev vxlan10
```
No `00:00:00:00:00:00` wildcard entry pointing at r2.

**Diagnosis:** with the `remote` left off the VXLAN device (as configured
in this lab, matching how flannel manages it), the *only* thing telling the
kernel where to flood unknown-unicast/broadcast/ARP traffic is that
wildcard FDB entry. Delete it and r1 has no VTEP to send BUM traffic to at
all — the frame is dropped locally on r1, before it ever reaches the
underlay. This is why nothing shows up even in a capture on r1's own
physical interface: the packet dies one hop earlier than in Challenge A.

**Fix:**
```bash
docker exec clab-vxlan-lab-r1 bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.2
```

**Lesson:** unlike multicast-mode VXLAN, a statically-configured/FDB-driven
VXLAN overlay (the way most CNI plugins run it) has no automatic peer
discovery — the FDB entries are the entire map of "who else is in this
overlay." Lose that state (a daemon crash, a node restart before the
controller reconciles) and the overlay silently stops working for that
node, with symptoms starting at "nothing even leaves the box," one whole
layer earlier than a VNI mismatch.
