# Lab 18 — Concept: DHCP Leases, Pools, and Renewal

## What's actually going on

DHCP is a lease, not a permanent assignment, and the whole protocol is
built around that fact. The exchange this lab watches in Step 3 — DISCOVER,
OFFER, REQUEST, ACK (commonly abbreviated DORA) — exists because IP
address assignment on a shared network needs a negotiation, not just an
announcement: a client broadcasts that it needs an address (`DISCOVER`,
since it doesn't know a server's address yet — it doesn't have an IP
address of its own to be reached at either), a server proposes one
(`OFFER`), the client formally claims that specific offer
(`REQUEST` — broadcast, not unicast, specifically so that if more than
one server made an offer, every server sees which one won and the losers
can free their tentative reservations), and the server confirms
(`ACK`). Every address handed out this way comes with an expiry
(the lease time) baked in from the start.

A server's pool is just a range of addresses it's willing to hand out,
and its lease database (this lab uses `dnsmasq`'s own lease file, in the
same `<expiry> <mac> <ip> <hostname> <client-id>` format real dnsmasq
deployments persist to disk) is the source of truth for which of those
addresses are currently spoken for. When every address in the pool has an
active, unexpired lease against it, the server has nothing left to
propose — it isn't broken, it isn't unreachable, it's making a completely
correct decision with insufficient inventory. This is exactly why
Challenge A's `dhclient -v` output shows the client's own `DISCOVER`
broadcasts going out repeatedly and getting no `OFFER` back at all: the
server heard every one of them and had nothing to say.

Renewal is where the time-limited nature of a lease becomes an active
liability instead of just bookkeeping. RFC 2131 defines two checkpoints:
T1, at 50% of the lease lifetime, when the client sends a *unicast*
`DHCPREQUEST` directly to the server that granted the lease, asking to
extend it (renewing); and T2, at 87.5%, when — if T1's renewal attempt
got no answer — the client escalates to a *broadcast* `DHCPREQUEST` that
any DHCP server can answer (rebinding, since the original server might be
the one that's gone and a different one on the segment might be able to
help). If neither checkpoint gets a response and the lease reaches its
actual expiry, the client's own DHCP client is required to stop using the
address — continuing to hold onto an IP nobody has confirmed is still
yours risks handing that same address to someone else and creating a
duplicate. This lab's short 2-minute lease exists purely to make that
entire T1→T2→expiry sequence something you can watch complete in about
two minutes instead of waiting out a real lease's usual hours-to-days
lifetime.

The reason Challenges A and B need genuinely different diagnostic
approaches despite an identical end state (no usable IP) is that they
fail at different points in this lifecycle. Challenge A fails before a
lease is ever granted at all — the very first `DISCOVER` never gets an
`OFFER`. Challenge B fails *after* a lease was successfully granted,
purely because the follow-up renewal conversation couldn't happen — the
client had everything it needed and lost it specifically because the
server it depended on for renewal wasn't there when the clock ran out.

## Where this shows up in the real world

- Conference/event networks, guest Wi-Fi, and rapidly-scaling container or
  VM fleets are classic places to exhaust a DHCP pool that was sized for
  a smaller, more static population of hosts — Challenge A's exact shape.
- A DHCP server that's briefly unreachable during a maintenance window,
  a network partition, or a failover that didn't complete in time
  produces Challenge B's exact shape for every client whose lease happens
  to come up for renewal during that window — sometimes with a
  significant delay before it's even noticed, since a client mid-lease
  (not yet at T1) looks completely fine until its own renewal clock hits.
- **Diagnosis scenario:** "some hosts on this VLAN have no IP and others
  are fine" often comes down to exactly when each host's lease happened
  to expire relative to a DHCP outage window — the hosts whose lease
  clock hadn't hit T1 yet rode out the outage invisibly; the ones that
  did hit T1/T2 during the window are the ones paging you.

## Go deeper
- **Website/docs:** man7.org, `dhclient(8)` —
  https://man7.org/linux/man-pages/man8/dhclient.8.html — the canonical
  reference for `dhclient`'s options (including `-v`, `-1`, `-r`) and its
  lease-file format.
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — covers the DHCP/BOOTP message exchange
  and lease lifecycle this lab is built on.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on the DORA exchange and DHCP relay/renewal
  behavior.
- **Website/docs:** Cloudflare's engineering blog —
  https://blog.cloudflare.com — occasional deep-dives touching on DHCP
  and network provisioning at scale.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck —
  accessible walkthroughs of how DHCP actually works end to end.
