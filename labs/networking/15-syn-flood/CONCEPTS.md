# Lab 15 — Concept: SYN Floods and SYN Cookies

## What's actually going on

A normal TCP three-way handshake needs the server to remember something
between the SYN it receives and the ACK it hopes to get back — at minimum,
the connection's source/destination IP and port, and the sequence number
it chose for its own SYN-ACK. Traditionally, Linux stores this in a
"request socket," a small kernel structure sitting in a per-listening-
socket queue, bounded by `net.ipv4.tcp_max_syn_backlog`. This is exactly
the resource this lab exhausts: every spoofed SYN that will never receive
a real ACK still consumes one of these slots for the duration of the
retransmission/timeout window, and a flood arriving faster than entries
expire fills the queue completely — at which point the kernel has no
choice but to drop *every* further SYN, real or fake, because it has
nowhere left to record them.

`--rand-source` is doing more than anonymizing the attacker. `hping3`
builds raw packets directly with a raw socket, entirely bypassing the
kernel's own TCP state machine — it never calls `connect()`, so the
kernel has no record that it's "expecting" a SYN-ACK back for any of these
connections. If the attacker used its own real source address, `victim`'s
SYN-ACK replies would arrive at the attacker's kernel completely
unsolicited (no local socket claims that source port/sequence), and the
kernel's default behavior for an unexpected SYN-ACK is to immediately send
a RST back — which would tear down the exact half-open state on `victim`
that the flood is trying to build, defeating the attack from the
attacker's own stack without the attacker even trying. Spoofing the
source isn't an accessory to a SYN flood; it's close to a structural
requirement for it to work at all against a raw-socket-based tool.

SYN cookies are Linux's answer, and they work by removing the need for
that request-socket table entirely for this purpose. Instead of storing
per-connection state, the kernel computes a specially-constructed initial
sequence number for its SYN-ACK — encoding a hash of the connection's
5-tuple, a coarse timestamp, and an index into a small table of the
negotiated MSS values, all folded via a secret key into the 32-bit
sequence number field itself (RFC 4987 describes the general technique;
Linux's specific implementation is in `net/ipv4/syncookies.c`). When the
real ACK comes back, the kernel doesn't look anything up in a table — it
recomputes the expected cookie from the ACK's own acknowledgment number
and validates it cryptographically. If it's valid, the kernel reconstructs
the connection's parameters (including the MSS) from what it just
verified and completes the handshake on the spot. A spoofed SYN that never
gets a matching real ACK back costs the kernel nothing beyond computing
one SYN-ACK — no table entry ever existed to fill up in the first place.
This is precisely why Challenge B's "just make the backlog bigger" fails:
a bigger table is still a table, and only removing the table (syncookies)
removes the exhaustible resource.

The trade-off, and the reason `tcp_syncookies` isn't unconditionally on
even though it defaults to `1` on most distributions: cookie-validated
connections can't carry arbitrary TCP options across the handshake (the
sequence number only has room to encode a handful of common MSS values,
and things like SACK permitted / window scaling get approximated rather
than exactly preserved) the way a normal stored request socket can. In
practice this is invisible for virtually all real traffic, and Linux only
actually engages cookie mode once the real backlog is close to full,
falling back to normal handshake bookkeeping for everything else — so
enabling it costs nothing under normal load and only kicks in exactly
when this lab's exhaustion scenario would otherwise occur.

## Where this shows up in the real world

- Any internet-facing TCP listener (a web server, a load balancer, a bare
  database port accidentally left open) is a SYN flood target the moment
  it's reachable — this is one of the oldest DDoS techniques still in
  active use because it's cheap for the attacker and, on an unhardened
  host, devastating.
- Cloud load balancers and DDoS-scrubbing services (AWS Shield, Cloudflare
  Spectrum/Magic Transit, etc.) implement variations on the same SYN
  cookie idea at massive scale, often terminating the handshake at the
  edge before a spoofed flood ever reaches the actual origin server.
- **Diagnosis scenario:** "our API suddenly has a huge connection backlog
  and legitimate clients are getting connection timeouts, but CPU and
  bandwidth both look fine" is this lab's exact signature at production
  scale — `netstat -s`/`ss -s` SYN-drop counters climbing while everything
  else looks calm is the tell that this is backlog exhaustion, not
  overload.

## Go deeper
- **Website/docs:** man7.org, `tcp(7)` —
  https://man7.org/linux/man-pages/man7/tcp.7.html — documents
  `tcp_syncookies`, `tcp_max_syn_backlog`, and related kernel TCP tunables.
- **Website/docs:** Cloudflare's engineering blog —
  https://blog.cloudflare.com — has extensive, frequently cited deep-dives
  specifically on SYN floods and how large-scale mitigation works.
- **Book:** *TCP/IP Illustrated, Volume 1: The Protocols* — W. Richard
  Stevens (updated by Kevin Fall) — covers the three-way handshake and
  connection-establishment state machine this attack targets.
- **Website/docs:** NetworkLessons.com — https://networklessons.com —
  structured fundamentals on TCP connection establishment and common
  attacks against it.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has
  hands-on `hping3`/network security demonstrations, including flood-style
  traffic generation and analysis.
