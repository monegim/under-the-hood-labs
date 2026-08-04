# Lab 22 — Concept: LACP Bonding

## What's actually going on

Linux's bonding driver can combine multiple physical (or, here, virtual)
interfaces into one logical device several different ways —
`active-backup` just fails over, `balance-rr` blindly round-robins frames
with no coordination with the other end at all. Mode `802.3ad` is
different in kind: it runs the actual IEEE 802.3ad/802.1AX Link
Aggregation Control Protocol, meaning each side sends LACPDUs (Link
Aggregation Control Protocol Data Units) advertising its own system ID,
a "key" identifying which links it considers aggregatable together, and
what it currently believes about the partner. Critically, this is a
negotiated protocol between two systems, not a local policy one side can
just decide on its own — which is exactly why a bond can have every
member link physically up and still fail to combine them: `bonding` only
puts a slave into the *active aggregator* once LACP has actually confirmed,
via this exchange, that the partner on the other end agrees they belong
together.

That "belong together" check has two independent conditions, and this
lab's two challenges each isolate one of them. First: is anyone on the
other end speaking LACP at all? If a link's partner never sends a valid
LACPDU back (because it's in `active-backup` mode, or the switch port was
never added to a channel-group), the local slave's LACP state machine
never reaches the "collecting/distributing" state and it never joins an
active aggregator — this is Challenge A's total failure and the main
walkthrough's partial one, differing only in how many of the bond's links
are affected. Second, and more subtly: even when LACP *is* running
successfully on every link, aggregation additionally requires that all the
links claiming to be one aggregate are actually talking to the *same*
partner system (compared via the partner's system MAC address in the
LACPDU). Two links each successfully negotiating LACP with two different
remote systems are, correctly, kept as two separate one-link aggregators —
this is Challenge B, and it's the scenario `Number of ports` and
`MII Status` alone will never reveal; you have to compare `Partner Mac
Address` across slaves specifically.

`/proc/net/bonding/bond0` exposes exactly the state needed to diagnose all
of this: per-bond fields (`Bonding Mode`, and under `802.3ad info`, the
`Active Aggregator Info` block with its `Aggregator ID` and `Number of
ports`) describe what the bond currently believes its working aggregate
looks like, while each `Slave Interface` block reports that slave's own
`MII Status` (raw link presence — nothing to do with LACP), its own
`Aggregator ID` (which aggregate group it's currently placed in), and its
negotiated `Partner Mac Address`. Reading this file well means never
stopping at the first "up" you see — a slave being `MII Status: up` is a
necessary condition for aggregation, never a sufficient one.

`lacp_rate` (this lab uses `fast`, a 1-second LACPDU interval, instead of
the `slow` 30-second default) only controls how often each side *asks* its
partner to transmit LACPDUs — it speeds up how quickly a real failure or
misconfiguration becomes visible in this lab, but it isn't itself part of
what determines whether aggregation succeeds.

## Where this shows up in the real world

- The single most common real-world version of this lab's main
  walkthrough: a server's NIC team (bond) is configured correctly, but only
  one of the two switch ports it's cabled to was actually added to the
  switch's LACP port-channel/EtherChannel group — the bond comes up,
  passes traffic, and quietly runs at half the throughput anyone expected,
  often for months before someone notices during a capacity review.
- Challenge B's scenario — a redundant cable landing on the wrong switch
  chassis — happens most often during a rack build-out or a cable
  re-patch where a "spare" port gets used without checking which switch
  it actually belongs to; both ends report perfectly healthy link and
  LACP state individually, which is why it survives basic health checks
  and only shows up when someone compares partner information per link.
- **Diagnosis scenario:** a bonded interface reports both members up, but
  observed throughput never exceeds what a single link should provide.
  `cat /proc/net/bonding/bondX` (Linux) or the switch-side LACP neighbor
  table, checked for `Number of ports`/partner consistency rather than
  just per-link status, is the fast path to "one link isn't actually
  aggregated" versus hours spent suspecting the application or the NIC
  driver.

## Go deeper
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — canonical reference for `ip-link(8)`, covering the bonding link-type options (`mode`, `miimon`, `lacp_rate`) used throughout this lab; also the home of the kernel's own bonding documentation conventions this lab's `/proc/net/bonding` output follows.
- **Book:** *Network Warrior* — Gary A. Donahue — strong practical coverage of LACP/EtherChannel troubleshooting from the switch-configuration side, a good complement to this lab's Linux-side view.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — clear structured tutorials on LACP negotiation and port-channel fundamentals that map directly onto the LACPDU exchange this lab is built around.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — covers LACP/EtherChannel configuration and troubleshooting on real switch platforms, useful for seeing the same protocol from the network-engineer side of the cable.
