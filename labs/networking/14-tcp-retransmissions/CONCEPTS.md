# Lab 14 — Concept: TCP Retransmissions

## What's actually going on

TCP guarantees delivery by tracking, for every byte it sends, whether the
other end has acknowledged it — and retransmitting anything that goes
unacknowledged for too long. There are two independent mechanisms that
trigger a retransmission, and this lab's two challenges each exercise a
different one. The first is the retransmission timeout (RTO): every
connection tracks a smoothed round-trip-time estimate (SRTT) and its
variance, and computes an RTO from it (roughly SRTT + 4×deviation, per
RFC 6298); if no ACK arrives within that window, the sender assumes the
segment (or its ACK) was lost and resends it, doubling the RTO on each
consecutive failure (exponential backoff). The second is fast retransmit:
if the sender sees three duplicate ACKs in a row — the receiver
re-acknowledging the same byte offset repeatedly because a later segment
arrived out of order — it infers a gap and retransmits immediately,
without waiting for the RTO timer at all. `netem loss` in this lab
triggers both paths at different points in the same transfer, because
which one fires just depends on whether a loss happens to be followed by
enough subsequent in-order data to generate three duplicate ACKs.

`ss -i` (or `-ti` for TCP-specific extended fields) reads this state
straight out of the kernel's per-socket `tcp_info` structure — the same
structure `getsockopt(TCP_INFO)` exposes to applications. Its `retrans:`
field is formatted as `<currently-unacknowledged-retransmits>/<total-
retransmits-this-connection>`; watching the second number climb over the
life of a transfer is a direct, low-overhead way to quantify how much
recovery work TCP is doing, without needing a packet capture at all.
`tcpdump`, by contrast, shows you the actual segments — repeated sequence
numbers are visually obvious once you know to look for them, and
Wireshark/`tshark` will explicitly flag `[TCP Retransmission]` and
`[TCP Dup ACK]` for you using the same heuristics.

The reason this lab's two challenges look identical from the sender alone
is that RTO-triggered retransmission is a pure timeout: the sender has no
way to distinguish "the segment was lost in flight" from "the segment
arrived fine but the receiver never got around to acknowledging it." Both
produce exactly the same client-side symptom — no ACK within the RTO
window, retransmit. The only way to actually tell them apart is
structural: capture at both ends and compare. If a sequence number the
sender transmitted never shows up in the receiver's inbound capture at
all, the network dropped it — genuine loss. If it shows up on both sides
identically, the network is innocent and the receiver itself (an
overloaded CPU, a blocked disk write, a garbage-collection pause, or —
as simulated here — a `SIGSTOP`'d process) is the one failing to keep up
and acknowledge in time.

`tc netem loss <percent>` works by attaching a queuing discipline (qdisc)
to an egress interface that randomly discards a configured fraction of
packets *before* they leave that interface — it's a kernel-level packet
shaper, not an application-level simulation, so everything downstream
(TCP's real retransmission logic, real duplicate ACKs, real RTO math) is
completely genuine, not scripted or faked for the demo.

## Where this shows up in the real world

- Cloud/cross-region links with intermittent packet loss (congested
  transit, a flapping BGP path, a bad piece of hardware somewhere in the
  middle) produce exactly Challenge A's signature — throughput collapses
  and `ss -i` shows climbing retransmits, with nothing wrong at either
  endpoint.
- An application server pinned at 100% CPU, a database mid-`VACUUM`/major
  GC pause, or a receiving host whose disk write-back is stalled all
  produce Challenge B's signature: the network delivered everything, the
  process just wasn't scheduled in time to read the socket and ACK.
- **Diagnosis scenario:** "throughput to this one service tanked overnight
  and there are retransmits everywhere" gets escalated to network teams by
  default — but if a two-sided capture shows every packet arriving cleanly
  at the receiving host, the actual page should go to whoever owns that
  host's CPU/scheduling/GC behavior instead, saving a network team from
  chasing a link that was never the problem.

## Go deeper
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — the definitive treatment of TCP's
  retransmission timer, fast retransmit, and duplicate-ACK recovery.
- **Website/docs:** man7.org, `tcp(7)` —
  https://man7.org/linux/man-pages/man7/tcp.7.html — documents the kernel
  TCP socket options and the `tcp_info` fields `ss -i` surfaces.
- **Website/docs:** Cloudflare's engineering blog —
  https://blog.cloudflare.com — regularly publishes deep-dives on TCP
  internals and real-world retransmission/latency debugging.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on TCP's reliability mechanisms.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal —
  hands-on `tcpdump`/Wireshark walkthroughs that include reading
  retransmission and duplicate-ACK patterns.
