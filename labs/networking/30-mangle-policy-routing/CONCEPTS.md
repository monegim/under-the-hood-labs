# Lab 30 — Concept: Marking a Packet and Routing By That Mark Are Different Tools

## What's actually going on

Linux's `iptables` operates through several tables, and `mangle` is the
one specifically meant for *altering* a packet (TTL, TOS/DSCP bits, or
an internal-only `MARK`) rather than deciding whether it lives or dies
(`filter`'s job) or rewriting its addresses (`nat`'s job). A `MARK` set
in `mangle` never leaves the box - it's not part of the packet on the
wire, it's metadata the kernel attaches to the packet in memory, for
the rest of that same box's own processing to act on if it chooses to.
"If it chooses to" is the operative phrase: nothing about setting a
mark obligates any other subsystem to do anything differently because
of it.

Linux's routing itself is not a single table consulted once - it's a
policy routing framework: an ordered list of rules (`ip rule`), each
naming a match condition (a source, an incoming interface, a mark,
among others) and a routing table to consult if that condition
matches. The list is walked in ascending priority order (lower numbers
evaluated first, exactly like an `iptables` chain's top-to-bottom
walk), and the first rule whose table produces a usable route wins.
Every Linux system already has this framework active by default, with
three built-in rules — `local` (priority 0, always first), `main`
(priority 32766, where "normal" routes from `ip route add` live by
default), and `default` (priority 32767, effectively last) - which is
exactly why policy routing can be added incrementally to a system that
was never explicitly configured for it: `main`'s existing behavior is
just one entry in a list that was always extensible, not something
that needs replacing.

`mangle`'s `MARK` and `ip rule`'s `fwmark` match are the two ends of
one intentional bridge between these otherwise-unrelated subsystems -
netfilter provides a way to tag a packet, and policy routing provides
a way to make a routing decision conditional on that tag. Nothing
enforces that both halves exist together: a `MARK` with no
corresponding `ip rule` is simply inert, still fires, still costs
nothing, does nothing useful. An `ip rule` referencing a mark with no
route in the table it points at behaves identically to no rule at all
for any packet that reaches it, just via a different specific gap
(Challenge B). And an `ip rule` that exists, references the right
table, but sits at a priority number *after* whichever built-in rule
already resolves a route for that packet, never gets consulted in the
first place (Challenge A) - the packet's fate was already decided
before evaluation reached it.

## Where this shows up in the real world

Multi-WAN routers, VPN split-tunneling, and any setup routing specific
traffic classes over a dedicated path (a management network, a backup
uplink, a provider-specific route for compliance reasons) all rely on
exactly this `mangle`+`ip rule` pairing - it's the standard Linux
mechanism for "route this traffic differently based on something other
than its destination address alone." It's also one of the more
fragile pieces of infrastructure config precisely because it spans two
independently-maintained subsystems: a firewall change made without
touching routing config, or a routing change made without checking
what marks are actually set, can each look completely correct in
isolation while producing a system that silently doesn't do what
either half suggests it should. Debugging it requires checking both
halves as separate, independently-verifiable facts - a firing mangle
counter and a working `ip rule`/table are two different claims, and
confirming one is never evidence for the other.

## Go deeper

- **Man page:** `iproute2` policy routing — `man ip-rule` and `man ip-route` — the authoritative reference for rule priority ordering and table lookups.
- **Website/docs:** Linux Advanced Routing & Traffic Control HOWTO (LARTC) — https://lartc.org/howto/ — the classic, still-relevant deep reference for policy routing, multiple routing tables, and `mangle`-based marking.
- **Website/docs:** Netfilter/iptables documentation — https://www.netfilter.org/documentation/ — covers the `mangle` table's role relative to `filter` and `nat`.
- **Man page:** `iptables-extensions(8)` — `man iptables-extensions` (see the `MARK` target) — exact semantics of setting and matching firewall marks.
- **Website/docs:** Red Hat / RHEL networking guide, "Configuring policy-based routing" — a widely-used, practically-oriented walkthrough of the same `ip rule table` pattern this lab is built around (search the current RHEL networking docs — not linking a specific version to avoid citing one that may have moved).
