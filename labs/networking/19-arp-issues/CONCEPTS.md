# Lab 19 — Concept: ARP Caching and Gratuitous ARP

## What's actually going on

Every IP packet destined for another host on the same local segment still
has to travel inside an Ethernet frame, and Ethernet frames are addressed
by MAC, not IP — so before the kernel can actually put a packet for
`10.0.0.100` on the wire, it has to know which MAC address that IP
currently belongs to. ARP is the protocol that answers this: broadcast
"who has this IP?", the owner unicasts back "me, here's my MAC." The
kernel doesn't do this lookup for every single packet — it caches the
answer in the neighbor table (`ip neigh`, the modern replacement for the
old `arp` command's table), because re-resolving on every packet would be
wasteful and slow.

That cache entry isn't permanent, but it's also not instantly
self-correcting. Linux's neighbor subsystem runs a small state machine
per entry: `REACHABLE` (recently confirmed good), aging into `STALE`
after a timeout with no confirming traffic, then `DELAY` and `PROBE` if
something tries to use it again (an active unicast ARP re-request to
verify before use). Critically, an entry sitting in `REACHABLE` is used
as-is, with no re-verification at all, until it ages out on its own timer
— which is exactly why Challenge A's stale mapping doesn't fix itself
quickly just because the real owner changed. The kernel has no way to
know the MAC behind an IP changed unless something tells it, and nothing
did.

Gratuitous ARP is that "something." It's an ARP announcement sent without
being asked for one — a host broadcasting "IP X is at my MAC" purely to
update everyone else's cache proactively, generally sent (a) when an
interface first comes up with an address, to detect conflicts and prime
neighbors' caches, and (b) explicitly by high-availability software
(`keepalived`/VRRP, `pacemaker`, cloud provider VIP failover mechanisms)
the instant a virtual IP moves to a new active node. This lab's Step 4 is
that mechanism working exactly as intended: the moment `server-b` sends
its gratuitous ARP, every host that receives it overwrites its own cache
immediately — no waiting on `STALE`/`DELAY`/`PROBE` timers, no packet loss
at all if the timing lines up right. `ip neigh flush` is the manual,
on-demand equivalent: instead of waiting for the kernel's own timers to
decide an entry needs re-checking, it discards the cached mapping
immediately and forces the very next attempt to use it to re-ARP from
scratch.

Challenge B exists because "the gratuitous ARP was sent correctly" and
"the failover is actually correct" are two different claims. Sending the
announcement is necessary but not sufficient — if the previous owner of
the address never actually released it, you don't have a stale-cache
problem at all, you have two hosts genuinely willing to answer for the
same IP simultaneously. ARP itself has no arbitration mechanism for this;
whichever host answers a given request, or sends the most recent
gratuitous announcement, simply wins whatever cache it reaches until the
other one talks again. This is why Challenge B's fix is completely
different from Challenge A's: no amount of flushing or re-resolving helps
when the underlying configuration itself is contradictory.

## Where this shows up in the real world

- `keepalived`/VRRP virtual IP failover, cloud provider "floating IP"/
  "elastic IP" reassignment between instances on the same subnet, and any
  active/passive cluster sharing an address all depend on gratuitous ARP
  firing correctly on failover — a firewall or switch feature that
  filters gratuitous ARP (some security-hardened switch configs do this
  to prevent ARP-spoofing attacks) can silently break failover entirely.
- Replacing a NIC or re-imaging a server while keeping its IP address is
  a real-world version of Challenge A: every other host's cache still
  points at the old MAC until something re-ARPs.
- **Diagnosis scenario:** "we failed over the VIP and half our clients
  reconnected fine, half didn't" often comes down to which clients had a
  cache entry that happened to be due for re-verification anyway versus
  ones sitting comfortably in `REACHABLE` with no reason yet to doubt it
  — `ip neigh flush` on the affected hosts is the fast, safe fix while
  you find out why the gratuitous ARP either didn't arrive or didn't help.

## Go deeper
- **Website/docs:** man7.org, `arp(7)` —
  https://man7.org/linux/man-pages/man7/arp.7.html — the canonical
  reference for ARP, the kernel's neighbor cache, and its state machine.
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — the ARP chapter covers gratuitous ARP
  and cache behavior in detail.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on ARP, gratuitous ARP, and first-hop
  redundancy protocols (VRRP/HSRP) that depend on it.
- **Website/docs:** FRRouting docs — https://docs.frrouting.org — relevant
  if you want to see VRRP configured on real router software after
  working through this lab's manual version of the same mechanism.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal —
  hands-on networking walkthroughs that include ARP behavior and
  first-hop redundancy protocols.
