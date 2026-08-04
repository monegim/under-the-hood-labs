# Lab 21 — Concept: Spanning Tree Protocol

## What's actually going on

Ethernet frames have no TTL. IP packets get decremented and dropped when a
routing loop forms; a bridged frame circulating through a Layer 2 loop
just keeps going, replicating every time it hits a bridge with more than
one way to flood it, forever. That's the entire reason Spanning Tree
Protocol exists: bridges are only safe to interconnect redundantly if
something computes a loop-free logical tree on top of the physical
topology and disables forwarding on every link that isn't part of that
tree. STP does this by electing a root bridge (the one with the lowest
bridge ID — priority plus MAC, both configurable but MAC breaks ties by
default), having every other bridge compute its shortest path *to* that
root, and then, for any segment where more than one bridge could forward
onto it, electing exactly one "designated" bridge/port and blocking the
rest. In this lab's topology, `sw1` and `sw2` are connected by two
physical links; STP's job is to pick one of those two links as the
logical path and block the other one, without you ever unplugging a cable.

The failure mode in Step 4 happens because Linux bridges default to
`stp_state 0` — plain flooding, no loop awareness at all. A bridge in this
mode still does the one thing bridges fundamentally do: forward an unknown-
destination or broadcast frame out every port except the one it arrived
on. With a genuine physical loop and no protocol blocking anything, a
single broadcast frame from `h1` gets flooded by `sw1` out both `sw1-a` and
`sw1-b`; `sw2` receives two copies and floods each one back out its *other*
port toward `sw1`; `sw1` receives those and floods them again — the
replication compounds with every round trip, which is why the bounded
capture in Step 4 sees far more than the single frame `h1` actually sent,
and why an unbounded version of this same test would eventually consume
all available bandwidth and CPU on every device in the loop (a real
broadcast storm, not a metaphorical one).

Challenge B is the sharper version of the same idea: STP protection is a
property of a *segment*, not of an individual bridge. A bridge can run STP
flawlessly on its own ports and still be part of an unprotected loop if its
neighbor on that segment doesn't participate. This is because two separate
mechanisms are involved: whether a bridge treats frames destined to the
IEEE-reserved bridge-group multicast range (BPDUs) specially, which
`stp_state` controls, versus whether it floods ordinary data frames with
no loop awareness at all, which it does unconditionally regardless of
`stp_state`. A bridge with STP off doesn't just "opt out of blocking" — it
stops being part of the negotiation that would have told the *other*
bridge a loop exists in the first place, since it no longer reflects or
reacts to BPDUs the way a participating peer would.

Classic 802.1D STP is also slow by design: default timers are a 2-second
hello, a 20-second max age, and a 15-second forward delay applied *twice*
(listening then learning) before a port reaches forwarding — 30-50 seconds
of convergence time for even a simple topology change. This is exactly why
Rapid STP (802.1w) and per-VLAN variants exist in production networks:
they replace this timer-based convergence with an explicit handshake
between neighbors, cutting typical convergence to sub-second in most
topologies. This lab uses classic STP's default timers deliberately, so
the 45-second waits you did in Steps 6 and 7 are the genuine, unoptimized
convergence time real 1990s-era Ethernet switches lived with.

## Where this shows up in the real world

- Access-layer switches with dual uplinks to two distribution switches are
  the single most common place STP runs in production networks — exactly
  the topology built in this lab, just usually drawn as a diagram instead
  of built with `ip link`.
- A classic on-call scenario: someone adds a "temporary" second cable
  between two switches for testing or backup, on a switch or a segment
  where STP was never enabled (or was disabled for troubleshooting and
  never re-enabled) — within seconds the whole broadcast domain saturates,
  and every device on it appears to lose connectivity simultaneously,
  which often gets misdiagnosed as a much bigger outage than "one extra
  cable" before someone thinks to check for a loop.
- **Diagnosis scenario:** near-100% utilization on switch uplinks with no
  corresponding legitimate traffic increase, paired with widespread,
  simultaneous connectivity loss across an entire VLAN, is the classic
  broadcast-storm signature — `brctl showstp`/`bridge -d link show` on the
  switches at the edge of the suspected loop, checking for ports stuck
  outside `forwarding` or a a topology change count that's spiking, is the
  fast way to confirm it before physically tracing cables.

## Go deeper
- **Book:** *Network Warrior* — Gary A. Donahue — has some of the best practically-oriented STP material available, specifically strong on diagnosing real storm/loop incidents.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — Rene Molenaar's STP tutorials cover the root bridge election, port roles, and timer mechanics this lab implements directly.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — canonical reference for `ip-link(8)`, including the bridge link type options (`stp_state`, `forward_delay`, etc.) used throughout this lab.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has walkthroughs covering STP/RSTP behavior on real switch hardware, useful for seeing the same concepts outside a Linux-bridge lab.
