# Lab 21 — Solutions

## Challenge A — a third redundant link added after STP has converged

**Check:**
```bash
bridge link show
sudo brctl showstp sw1
```
After the ~45 second wait, `sw1-c`/`sw2-c` settles into a state too —
you now have **two** of the **six** inter-switch ports (three links)
showing `state blocking`, and exactly one path between `sw1` and `sw2`
left forwarding.

**Diagnosis:** STP is not a one-time boot-time calculation — it's a
continuously running protocol. Adding a new port to a bridge that's
already running STP triggers that port through the standard
listening → learning → forwarding (or blocking) progression, driven by
BPDUs exchanged the whole time. During that transition the port does *not*
forward normal traffic yet (that's exactly what listening/learning
prevents), so the new link can't create a storm while STP is still
deciding what to do with it — the protection is active from the moment the
link comes up, not just after some batch recalculation.

**Fix:** nothing to fix — this is the expected, safe behavior. If you want
to remove the extra link, just delete it:
```bash
sudo ip link del sw1-c
```

**Lesson:** STP protects a network continuously, not just once. A newly
added redundant path is safe by default because forwarding is opt-in
(you have to reach `forwarding` state first) — the failure mode in this
lab's main walkthrough only happened because STP wasn't running on *either*
bridge at all when the second link went in, not because STP is slow to
react to new links.

---

## Challenge B — STP disabled on one bridge, still running on the other

**Check:**
```bash
sudo ip netns exec h2 timeout 3 tcpdump -ni veth-h2 -nn arp > /tmp/storm-b.log 2>/dev/null &
sleep 0.3
sudo ip netns exec h1 arping -c 1 -b -I veth-h1 10.0.0.2 >/dev/null 2>&1 || true
wait
wc -l /tmp/storm-b.log
```
Far more than one copy arrives again — the storm is back, even though
`sw1` never stopped running STP.

**Diagnosis:** these are two separate questions, and a bridge answers them
independently:
1. "Do I understand BPDUs and use them to compute a loop-free tree?" —
   governed by `stp_state`.
2. "Do I flood an ordinary broadcast/unknown-destination data frame out
   every port except the one it arrived on?" — this is a bridge's default
   forwarding behavior, and it happens *regardless* of `stp_state`.

`sw2` with `stp_state 0` stops participating in (1) but never stopped doing
(2) — it's now behaving like a dumb, unmanaged switch: whatever arrives on
`sw2-a` gets flooded straight back out `sw2-b` (and vice versa) with zero
loop awareness. Meanwhile `sw1` is still running STP correctly on its own
ports, but STP fundamentally requires **both** bridges on a shared segment
to participate in the same conversation to agree on which port blocks.
With `sw2` no longer treating BPDUs specially, `sw1`'s BPDUs don't get
reflected back to `sw1` the way they would from a real STP peer, so `sw1`
never gets the signal that would tell it "these two ports lead to the same
neighbor, block one." One side running STP perfectly cannot compensate for
the other side not running it at all.

**Fix:**
```bash
sudo ip link set sw2 type bridge stp_state 1
echo "waiting ~45s for reconvergence..."
sleep 45
```

**Lesson:** STP is a negotiated agreement between neighbors, not a
unilateral defense. A switch running STP flawlessly is not protected from
a loop through a neighbor that isn't running it — which is exactly why
"someone plugged an unmanaged switch or a misconfigured device into a
redundant link" is such a classically dangerous real-world mistake: the
managed side of the network can be perfectly configured and still not save
you.
