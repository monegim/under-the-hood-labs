# Lab 32 — TCP Zero-Window Analysis

## Objective
Run a real transfer where the receiver can't keep up, capture it, and
learn to find the exact moment things went wrong using `tshark`'s
built-in TCP analysis — instead of scrolling through raw packets
looking for a field value you'd have to already know to look for.

## Why this matters
Lab 12 covered capture/display filters and reading a handshake; Lab 14
covered telling packet loss apart from a stuck receiver. This lab is
about a different, narrower skill: once you have a capture, how do you
actually *find* the interesting packets in it without reading every
single one? Wireshark/`tshark` don't just record traffic — they
analyze it as they go, flagging retransmissions, duplicate ACKs,
out-of-order segments, and zero-window conditions automatically, and
exposing all of it as filterable fields (`tcp.analysis.*`). Reading raw
`tcpdump` output for something like a zero-window stall means knowing
in advance to look for a `win 0` field buried in one line among
thousands — `tcp.analysis.zero_window` finds every one of them
instantly, labeled, with zero prior knowledge of what you're looking
for required.

## Prerequisites
- A Linux VM, `sudo` access, `python3`, `tcpdump`, `tshark`

Check first:
```bash
which python3 tcpdump tshark
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This starts a receiver on `server` with a deliberately tiny receive
buffer that reads slowly (2048-byte buffer, 512 bytes per read, a
200ms pause between reads) — think a receiver whose application layer
can't drain data as fast as the network can deliver it.

## Step 2 — Reproduce the symptom with a real capture
```bash
sudo ip netns exec client tcpdump -i veth-c -w /tmp/lab32.pcap -n &
sleep 1
sudo ip netns exec client python3 /tmp/lab32-client.py
sleep 1; sudo pkill tcpdump
```
The transfer completes (nothing errors), but takes several seconds for
what's only 32KB of data.

## Step 3 — Find the problem without reading every packet
```bash
tshark -r /tmp/lab32.pcap -Y 'tcp.analysis.zero_window'
```
A list of every frame where the receiver advertised a full (zero)
window — telling the sender "stop, I have no room left" — labeled
`[TCP ZeroWindow]` right in the output. Compare against just grepping
raw `tcpdump` text for the same thing:
```bash
tcpdump -r /tmp/lab32.pcap -n | grep 'win 0'
```
Same information, technically — but only if you already knew to look
for exactly that string.

## Step 4 — Fix it
The real fix is application-level (read faster, size buffers
appropriately for the actual throughput needed) — for this lab,
restart the receiver without the artificial constraints:
```bash
sudo ip netns exec server pkill -f lab32-server.py
sudo ip netns exec server env RCVBUF=0 READ_SIZE=65536 READ_DELAY=0 python3 /tmp/lab32-server.py &
```

## Step 5 — Verify
```bash
./check.sh
```
Runs a fresh capture-and-transfer cycle and requires zero
`tcp.analysis.zero_window` events.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the signal that tells you when it recovers, not just when it stalls:**
```bash
./reset.sh
sudo ip netns exec client tcpdump -i veth-c -w /tmp/lab32-a.pcap -n &
sleep 1
sudo ip netns exec client python3 /tmp/lab32-client.py
sleep 1; sudo pkill tcpdump
tshark -r /tmp/lab32-a.pcap -Y 'tcp.analysis.window_update' -T fields -e frame.time_relative
tshark -r /tmp/lab32-a.pcap -Y 'tcp.analysis.zero_window' -T fields -e frame.time_relative
```
`window_update` events mark the receiver announcing it has room
again, after a stall. Compare the two timestamp lists side by side —
what's the actual shape of what's happening to this connection across
the full transfer: one stall that eventually clears, or something
else entirely? What does the *count* of `window_update` events (not
just their presence) tell you that a single "was there a stall, yes or
no" check wouldn't?

**Challenge B — an occasional blip is not the same severity as this:**
```bash
./reset.sh
sudo ip netns exec server pkill -f lab32-server.py
sudo ip netns exec server env RCVBUF=4096 READ_SIZE=2048 READ_DELAY=0.02 python3 /tmp/lab32-server.py &
sleep 1
sudo ip netns exec client tcpdump -i veth-c -w /tmp/lab32-b.pcap -n &
sleep 1
sudo ip netns exec client python3 /tmp/lab32-client.py
sleep 1; sudo pkill tcpdump
tshark -r /tmp/lab32-b.pcap -Y 'tcp.analysis.zero_window' | wc -l
```
This receiver is *also* imperfect - just far less severely (a bigger
buffer, faster reads, a much shorter pause). Compare the zero-window
count against Step 3's. Both configurations technically have "a
zero-window problem" by a strict yes/no check - work out why treating
those two results as equally urgent would be the wrong call, and what
a more useful pass/fail threshold for a real monitoring check might
look like instead of a bare "zero events allowed."

See `solution.md` only after you've formed your own diagnosis.
