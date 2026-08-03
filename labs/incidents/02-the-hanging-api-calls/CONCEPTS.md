# Incident 02 — Concept: Data-Size-Dependent Failures and the PMTUD Blackhole

## What's actually going on

Two mechanisms combine to turn a straightforward network misconfiguration
into what looks, from the outside, like a data-dependent database
problem.

The first is **tunnel MTU overhead**: any encapsulation (GRE here, but
the same applies to VXLAN, IPsec, WireGuard, or a VPN) adds header bytes
on top of the underlying link's MTU, so the tunnel's real usable MTU is
always somewhat smaller than the physical path underneath it - 1476
here, versus the 1500 either endpoint assumes about its own local
interface. This gap is completely normal and, by itself, harmless: TCP
is designed to discover and adapt to it automatically via Path MTU
Discovery. A sender transmits a segment with the "Don't Fragment" bit
set; if a router along the path can't forward it without fragmenting,
that router drops the oversized packet and sends back an ICMP
"fragmentation needed" message naming the actual MTU it can support. The
sender then shrinks its assumption for that path and retransmits at the
smaller size. This is exactly what `labs/networking/11-mtu-issues`
demonstrates step by step - it's supposed to be invisible in normal
operation.

The second mechanism is what turns "invisible" into "an intermittent,
customer-specific-looking incident": an intermediate firewall dropping
that specific ICMP message type. Once the feedback message can't get
back to the sender, PMTUD doesn't fail loudly - it fails *silently*.
The sender has no way to distinguish "my packet was delivered and I'm
just waiting for a slow reply" from "my packet vanished and nothing is
coming back," so it just keeps retransmitting the identical oversized
segment, which keeps getting silently discarded, for as long as the
connection's retransmission timers allow (often tens of seconds to
several minutes at the raw TCP level - this lab's API layer gives up
after 12 seconds via its own subprocess timeout, which is what actually
bounds the user-visible hang). Whether any given request trips this
depends entirely on whether it ever needs to send a segment above the
tunnel's real MTU - which has nothing to do with which customer, which
query, or which service is "at fault" in any code sense, and everything
to do with how many bytes that particular response happens to contain.
That's why this incident presents as "some customers, not others" rather
than "the tunnel is broken" - the underlying cause is binary and
constant, but its visible trigger is a threshold on payload size that
varies request-by-request.

## Where this shows up in the real world

This is one of the most common, most misdiagnosed production networking
symptoms that exists, precisely because the visible failure ("some
requests hang, others are fine, no errors logged anywhere") looks
nothing like a networking problem to whoever's paged first - it looks
like a slow query, a poison-pill record, or "something about that one
customer's data." It shows up behind VPNs, GRE/IPsec/WireGuard tunnels,
cloud provider overlay networks (VXLAN/GENEVE), and any link with a
non-default MTU - which describes most cloud and container networking
today. The fix is nearly always the same: find and remove (or narrow)
whatever is blocking ICMP type 3 on the path, rather than chasing the
symptom by raising application-level timeouts, adding retries, or
"optimizing" the specific queries that happen to trigger it.

## Go deeper

- **Book:** *Systems Performance* — Brendan Gregg — general methodology
  for distinguishing "the resource/layer that looks responsible" from
  "the resource/layer that's actually responsible," which is exactly the
  trap this incident sets (looks like a DB issue, is a network issue).
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/icmp.7.html
  and https://man7.org/linux/man-pages/man7/tcp.7.html — document the
  ICMP message types and the `IP_MTU_DISCOVER`/PMTUD mechanics
  referenced here in full detail.
- **Website:** Brendan Gregg's site — https://www.brendangregg.com — the
  USE method's emphasis on checking every layer on the path, not just
  the layer that seems obviously implicated, applies directly to
  "looks like the DB, is actually the network."
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et
  al. (free at https://sre.google/books/) — see the chapters on
  monitoring and effective troubleshooting for the general discipline of
  not trusting the first plausible-looking explanation.
