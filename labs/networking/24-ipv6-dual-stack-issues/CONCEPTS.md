# Lab 24 — Concept: IPv6 Dual-Stack & Happy Eyeballs

## What's actually going on

A dual-stack client resolving a hostname typically gets back both an A
(IPv4) and AAAA (IPv6) record. Historically, naive clients tried one
address family, waited for it to fully succeed or fail, and only then
tried the other — fine when failures are fast (connection refused,
network unreachable), disastrous when a broken path fails by *hanging*
instead. RFC 8305 ("Happy Eyeballs v2") exists specifically for that
disastrous case: instead of strictly sequential attempts, the client
starts connecting over one address family, and after a short
head-start delay (RFC 8305 recommends around 250ms; this is a
recommendation, not a hard requirement, which is exactly what Challenge B
exploits), starts a connection attempt to the other family *concurrently*,
using whichever one actually completes a handshake first and abandoning
the rest. The mechanism only works because that head-start delay is short
— short enough that even if the first attempt is fine, you've lost almost
nothing by also racing the second; short enough that if the first attempt
is silently broken, you're not stuck waiting on it for long before its
competitor gets a chance.

The reason a half-broken path is worse than an absent one comes directly
out of that design. If a hostname has no AAAA record at all, a client
never attempts IPv6 in the first place — zero cost, every single time. If
the AAAA record exists and resolves to something broken in a way that
*hangs* rather than fails fast (this lab's silently dropped TCP SYN, no
RST, no ICMP unreachable), every single connection attempt pays some
price for it: a well-implemented Happy-Eyeballs client pays the small,
bounded head-start delay before its IPv4 attempt gets to run; a client
without Happy Eyeballs support, or one whose head-start delay is
misconfigured to be long (Challenge B), pays close to the *entire* broken
connection's timeout, every time, because it never starts the working
attempt until the broken one has had its full chance to fail. Removing the
AAAA record entirely would have been strictly better for both kinds of
client than leaving it half-broken.

This lab's break is deliberately narrow — dropping only the TCP SYN to
port 80, not blocking IPv6 as a whole — because that's what makes it
realistic and hard to catch with a shallow health check. `ping6` (ICMPv6
echo) exercises a completely different code path than a TCP connection to
a specific port: it only proves the network layer and basic host
reachability work, and says nothing about whether the actual service is
reachable on that path. Challenge A goes one layer deeper still: Neighbor
Discovery Protocol (NDP), IPv6's replacement for ARP, has to successfully
resolve a neighbor's link-layer address (via Neighbor Solicitation/
Advertisement, both carried over ICMPv6) before *any* IPv6 packet —
including a ping — can be transmitted to that neighbor at all. Break NDP
and everything fails identically and totally; break only a firewall rule
higher up the stack (Step 3) and you get the much more diagnostically
confusing pattern of "ping works, the actual service doesn't" — three
different layers, three different failure signatures, and matching the
symptom to the layer is the entire troubleshooting skill this lab is
built around.

## Where this shows up in the real world

- A load balancer or reverse proxy with an IPv6 listener configured but a
  firewall rule, security group, or NACL that only got updated for IPv4 is
  an extremely common real cause of exactly this lab's Step 3 scenario —
  everything about the service "looks" dual-stack (DNS, ping, routing) and
  only actual client connections on the affected port reveal the problem,
  usually as "some users report slowness" rather than an outright outage
  report, because most of the affected users' clients are quietly falling
  back to IPv4 with Happy Eyeballs doing exactly its job.
- Corporate or mobile networks with known-bad, but not fully absent, IPv6
  transit are a widely documented real cause of client-perceived
  "flakiness" that traces back to this same mechanism — enough IPv6
  reachability to get an address and pass basic checks, not enough to
  reliably complete real connections.
- **Diagnosis scenario:** a service that "sometimes takes a few hundred
  extra milliseconds for some users, otherwise indistinguishable" is a
  classic Happy-Eyeballs-masked IPv6 problem — checking whether the
  service has a working AAAA record, then testing that address directly
  with `curl -6` or an equivalent rather than trusting `ping6`, is the fast
  way to confirm it before chasing an application-side performance
  regression that doesn't exist.

## Go deeper
- **Book:** *Computer Networking: A Top-Down Approach* — Jim Kurose & Keith Ross — covers IPv6 addressing, Neighbor Discovery, and the transition/dual-stack mechanisms this lab exercises directly.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — clear tutorials on IPv6 Neighbor Discovery Protocol and how it differs mechanically from ARP.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — canonical reference for `ip-link(8)`/`ip-address(8)` and general Linux networking commands used to build this lab's dual-stack topology.
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck — accessible explanations of IPv6 fundamentals and dual-stack behavior, good framing for why this transition period still causes real production issues.
