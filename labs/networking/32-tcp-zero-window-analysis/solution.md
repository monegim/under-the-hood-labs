# Lab 32 — Solution

## Root cause

The receiver's application layer reads data slower than the sender can
push it — a 2048-byte kernel receive buffer, draining in 512-byte
chunks with a 200ms pause between each read. TCP's flow control exists
exactly for this situation: once the kernel's receive buffer fills up
(because the application isn't calling `recv()` fast enough to empty
it), the receiver starts advertising a window size of zero in its
ACKs, telling the sender "stop sending, I have nowhere to put more
data." This is TCP working correctly, not a bug in TCP - the actual
problem is entirely on the application side of the receiving host,
several layers above anything a packet capture of the network itself
would normally think to blame.

## Why it happened

Nothing about the TCP handshake, routing, or the network path is
wrong here - every packet that's sent arrives, in order, uncorrupted.
The slowdown is caused by the receiving *application* not draining its
socket fast enough, which is invisible to any diagnostic that only
looks at whether packets are getting where they're going. It's
specifically the kind of problem that "the network looks fine" checks
(ping, traceroute, basic throughput tests against an idle receiver)
won't catch, because they don't reproduce the actual condition - an
application under real load, reading slower than data arrives.

## Why the obvious fixes don't work

- **Restarting the network / checking cables, MTU, routing**: nothing
  is wrong at any of those layers - every packet in the capture arrives
  correctly; the sender is just being told, correctly, to wait.
- **Increasing the sender's send buffer or retry logic**: doesn't
  address the actual constraint, which is the *receiver's* draining
  speed - the sender was already sending as fast as it was allowed to;
  giving it more room to queue data doesn't make the receiver read any
  faster.
- **Blaming packet loss**: nothing was lost or retransmitted due to
  loss here - Lab 14 covers that failure signature specifically, and
  it looks different in a capture (retransmissions of the *same*
  sequence data after a timeout) from this one (the receiver
  explicitly, successfully ACKing with `win 0`).

## The investigation

Reproduce with a capture running:
```bash
sudo ip netns exec client tcpdump -i veth-c -w /tmp/lab32.pcap -n &
sleep 1
sudo ip netns exec client python3 /tmp/lab32-client.py
sleep 1; sudo pkill tcpdump
```

Find the stalls without reading every packet:
```bash
tshark -r /tmp/lab32.pcap -Y 'tcp.analysis.zero_window'
```
Multiple `[TCP ZeroWindow]`-labeled frames, spread across nearly the
entire transfer.

Confirm what this looks like without `tshark`'s analysis:
```bash
tcpdump -r /tmp/lab32.pcap -n | grep 'win 0'
```
The same packets, but only findable by already knowing the exact
string to search for - `tshark`'s expert analysis exists precisely so
you don't have to know that in advance.

## The fix

```bash
sudo ip netns exec server pkill -f lab32-server.py
sudo ip netns exec server env RCVBUF=0 READ_SIZE=65536 READ_DELAY=0 python3 /tmp/lab32-server.py &
```
A receiver that reads promptly, in large chunks, with no artificial
buffer ceiling never advertises a zero window at all - confirmed by
`./check.sh` finding zero `tcp.analysis.zero_window` events on a fresh
capture.

---

## Challenge A — the signal that tells you when it recovers, not just when it stalls

**Check:**
```bash
tshark -r /tmp/lab32-a.pcap -Y 'tcp.analysis.window_update' -T fields -e frame.time_relative
tshark -r /tmp/lab32-a.pcap -Y 'tcp.analysis.zero_window' -T fields -e frame.time_relative
```
Roughly 7 `window_update` events, interleaved with roughly 15
`zero_window` events, spread across the entire ~7-second transfer -
not one stall near the start that clears and stays clear.

**Diagnosis:** `tcp.analysis.window_update` marks the receiver
announcing new room after previously advertising zero - it's the
*recovery* half of the same story `zero_window` tells the *stall*
half of. Looking at just the zero-window count alone tells you a
problem existed; looking at both together, and specifically how many
times recovery happened and stalled again, tells you this wasn't a
one-time hiccup - the receiver is chronically oscillating between
"full" and "just opened a little room" for the connection's entire
duration. A single stall-then-recover pair reads as "briefly busy." A
repeating cycle of 7 recoveries each immediately followed by another
stall reads as "structurally too slow for this workload," a
meaningfully different (and more urgent) diagnosis.

**Lesson:** `tcp.analysis.zero_window`'s count alone answers "did this
happen." Pairing it with `tcp.analysis.window_update` and looking at
the pattern between them answers the more useful question: is this a
transient blip or a sustained, structural mismatch between sender rate
and receiver capacity.

---

## Challenge B — an occasional blip is not the same severity as this

**Check:**
```bash
tshark -r /tmp/lab32-b.pcap -Y 'tcp.analysis.zero_window' | wc -l
```
`1`, against the main lab's 15 - for a receiver that's still
imperfect (`RCVBUF=4096`, a 20ms pause instead of 200ms) but
completes the transfer in a fraction of a second instead of several.

**Diagnosis:** a strict "zero zero-window events allowed" check would
flag both configurations identically - fail. But one of them
transferred 32KB in 15 milliseconds with a single, isolated moment of
backpressure; the other took over 7 seconds, chronically stalling
throughout. Treating both as equally urgent wastes attention on a
receiver that's performing perfectly adequately for practical
purposes, while providing no more useful signal about the genuinely
broken one than "yes, technically, this happened at some point."

**Fix (a better real-world check):** something closer to "how many
zero-window events, over what fraction of the connection's total
duration, or above what rate" - a bounded, small count on an otherwise
fast, short transfer is very different information from the same
mechanism firing repeatedly across nearly the entire duration of a
connection.

**Lesson:** a boolean "did this problem ever occur" check is often the
wrong shape for a real health signal - frequency, duration, and
proportion-of-total-time are usually what actually separates "this
happened once and doesn't matter" from "this is happening constantly
and does." This lab's own `check.sh` uses a strict zero-tolerance
threshold deliberately, because the *lab's* main scenario is severe
enough that zero tolerance is the right call here - but recognizing
when that threshold is too strict for a *different* situation is
itself part of the skill.
