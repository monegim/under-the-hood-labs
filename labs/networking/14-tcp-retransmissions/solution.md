# Lab 14 — Solutions

## Challenge A — retransmits from real packet loss

**Check:**
```bash
docker exec clab-tcp-retrans-client tcpdump -r /tmp/client-side.pcap | wc -l
docker exec clab-tcp-retrans-server tcpdump -r /tmp/server-side.pcap | wc -l
```
The server-side capture has noticeably fewer packets than the client-side
one — specific sequence numbers show up leaving the client's capture that
never appear anywhere in the server's capture at all, not even once.
```bash
docker exec clab-tcp-retrans-client ss -ti dst 10.0.0.20
```
`retrans:` climbs steadily over the course of the transfer, and `iperf3`'s
reported throughput is well below what Step 2's clean baseline showed.

**Diagnosis:** `tc netem loss 15%` drops packets on the client's egress
path before they ever reach the wire toward the server — this is *actual*
loss, not a slow receiver. The proof is structural: a packet that appears
in the sender's outbound capture but never appears in the receiver's
inbound capture, for the same sequence number, can only mean it was
dropped somewhere on the path between the two capture points. TCP's own
retransmission timer (RTO) or fast-retransmit-on-duplicate-ACK logic is
doing exactly what it's designed to do — resending data the far end never
acknowledged because it genuinely never received it.

**Fix:**
```bash
docker exec clab-tcp-retrans-client tc qdisc del dev eth1 root netem
```
In production this is the point where you'd instead be chasing a flaky
NIC, an oversubscribed link, a bad cable, or a congested hop — `netem` is
standing in for whatever the real physical/logical cause of loss is.

**Lesson:** "retransmits happened" only tells you TCP recovered from
*something*. Whether packets were actually lost in transit — as opposed to
arriving fine but never being acknowledged — can only be proven by
comparing a capture at the sender against a capture at the receiver for
the same sequence numbers. One-sided captures can only ever guess.

---

## Challenge B — retransmits from an unresponsive receiver

**Check:**
```bash
docker exec clab-tcp-retrans-server tcpdump -r /tmp/server-side.pcap | wc -l
docker exec clab-tcp-retrans-client tcpdump -r /tmp/client-side.pcap | wc -l
```
This time the two counts are close/identical — every packet the client
sent shows up in the server's capture too. Nothing was lost on the wire.
```bash
docker exec clab-tcp-retrans-server ps aux | grep iperf3
```
The `iperf3 -s` process shows state `T` (stopped) — `pkill -STOP` froze it
with `SIGSTOP`, exactly like a process pegged by CPU starvation or a
kernel scheduler that's stopped giving it runtime would look from the
outside.
```bash
docker exec clab-tcp-retrans-client ss -ti dst 10.0.0.20
```
`retrans:` is climbing here too, and superficially it looks like
Challenge A all over again.

**Diagnosis:** the data is arriving at the server's NIC just fine — the
capture proves it — but the stopped `iperf3` process never reads it off
the socket and never generates the ACKs the client is waiting for. From
the client's perspective this is indistinguishable from loss using RTO
alone: no ACK arrives in time, so the sender's TCP stack retransmits,
exactly as designed, even though every single retransmitted byte is
already sitting in the server's receive buffer. This is the "unresponsive
receiver" failure mode: the network did its job, the application (or the
CPU scheduler starving it, or a GC pause, or a stuck disk write it's
blocked on) did not.

**Fix:**
```bash
docker exec clab-tcp-retrans-server pkill -CONT -f "iperf3 -s"
```

**Lesson:** identical sender-side symptom (`ss -ti` retransmit counter
climbing), completely different root cause, and the fix for one does
nothing for the other — clearing `netem` wouldn't have helped Challenge B,
and restarting/unfreezing the receiving process wouldn't have helped
Challenge A. Comparing sender and receiver captures for the same segments
is what tells you which side of this you're actually dealing with, instead
of guessing "it's probably the network" every time you see retransmits.
