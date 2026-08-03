# Incident 02 — Solution

## Root cause

`r1` (the router on the `api` side of the GRE tunnel to `db`) has an
iptables rule silently dropping outbound ICMP "fragmentation needed"
messages:
```
iptables -A OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP
```
The GRE tunnel between `r1` and `r2` has a real MTU of 1476 (1500-byte
underlay minus 24 bytes of GRE overhead) - smaller than the 1500-byte
MTU either endpoint (`api`, `db`) assumes locally. Normally that
mismatch is invisible: when `db` sends a TCP segment too big to fit the
tunnel, `r1` sends back an ICMP "fragmentation needed" message telling
`db` to shrink future segments on that connection (Path MTU Discovery,
PMTUD) - this is the *exact* mechanism `labs/networking/11-mtu-issues`
demonstrates working correctly. Here, that ICMP reply never makes it
back to `db`, because `r1` throws it away before it leaves. `db` never
learns anything is wrong, keeps sending the same too-large segment with
the DF (Don't Fragment) bit set, and it vanishes into the tunnel every
time - a classic PMTUD blackhole.

This explains "works for some customers, not others" precisely: small
customers' order histories fit in a single TCP segment well under 1476
bytes and are never affected. `acme-corp` (customer 999)'s multi-hundred-
KB report is spread across many TCP segments, some of which are sized to
the endpoints' assumed ~1460-byte MSS - every one of those blackholes,
and the request hangs until the API's own subprocess timeout (12s) gives
up and returns an error. Nothing about this touches CPU, memory, or
MySQL's own query planner - `SHOW PROCESSLIST` on `db` would show the
query as already finished; the response just never arrives.

## Why it happened

"a routine firewall change last week" is the tell: someone hardened `r1`
by dropping ICMP types that looked unnecessary or risky to leave open
(ICMP is a common target for well-meaning security hardening - see
`labs/networking/05-firewalls`). Blocking ICMP echo (ping) is usually
harmless. Blocking ICMP type 3 (destination unreachable) code 4
(fragmentation needed) is not - it's not a diagnostic nicety, it's a
required feedback channel that the TCP/IP stack depends on for PMTUD to
function at all. The firewall change had zero effect on anything for
most traffic, which is exactly why it shipped without anyone noticing -
until a code path that happens to move enough data to need a smaller
segment size finally exercised it.

## Why the obvious fixes don't work

- **Restarting `api` or `db`**: does nothing - the blackhole is on the
  network path, not in either service's process state. The exact same
  request will fail again the moment it's retried.
- **Scaling up the database (more CPU/RAM/IOPS)**: irrelevant - `db`
  finishes the query and sends the reply promptly; the reply is what's
  being dropped, two hops away, well after MySQL has done its job.
- **Increasing the application's timeout so it "stops erroring"**: this
  is the trap. A longer client timeout doesn't fix the blackhole, it
  just makes the hang last longer before the same failure surfaces -
  worse for users, and it delays finding the actual cause even further.
- **Retrying the request**: the segment that gets blackholed is
  deterministic for a given amount of data on this specific broken path
  - retrying the identical query produces the identical hang, every
  time.

## The investigation

Confirm the failure is data-size-dependent, not customer-specific in any
meaningful sense:
```bash
docker exec clab-mtu-incident-api curl -s --max-time 15 'http://localhost:8000/report?customer_id=1'
docker exec clab-mtu-incident-api curl -s --max-time 15 'http://localhost:8000/report?customer_id=999'
```
The first returns instantly. The second hangs for ~12 seconds and then
returns a timeout error.

Reproduce it at the network layer directly, bypassing the app entirely -
exactly the `ping -M do -s <size>` technique from lab 11:
```bash
docker exec clab-mtu-incident-api ping -M do -s 1448 -c 3 10.2.2.10   # fits the tunnel: works
docker exec clab-mtu-incident-api ping -M do -s 1449 -c 3 10.2.2.10   # one byte over: should report "Frag needed"...
```
Instead of a clean "Frag needed" message, the oversized ping just times
out silently - 100% loss, no ICMP feedback at all. Compare this directly
against lab 11 Step 4, where the same oversized ping produces an
explicit, immediate "Frag needed and DF set (mtu = 1476)" message. The
*absence* of that message, replaced by silent packet loss, is the
signature of a PMTUD blackhole rather than PMTUD simply not being
needed.

Capture the traffic to see it directly:
```bash
docker exec clab-mtu-incident-r1 tcpdump -ni eth2 -c 20 'icmp or (tcp and greater 1400)' &
docker exec clab-mtu-incident-api curl -s --max-time 15 'http://localhost:8000/report?customer_id=999' >/dev/null
```
You'll see the oversized GRE-encapsulated segment leave toward `db`, and
- crucially - no ICMP coming back the other way.

Confirm the actual rule:
```bash
docker exec clab-mtu-incident-r1 iptables -L OUTPUT -v -n
```
A DROP rule matching `icmp fragmentation-needed` with a nonzero, still-
climbing packet counter.

## The fix

```bash
docker exec clab-mtu-incident-r1 iptables -D OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP
```
Re-run the large report - it now completes in well under a second, same
as the small one. PMTUD immediately starts working again: `db`'s
oversized first segment gets a real "fragmentation needed" reply, `db`
shrinks its estimate for that path, and retransmits at a size that fits.

For prevention: never blanket-drop ICMP type 3 on a firewall in front of
a tunnel, VPN, or any path with a non-default MTU. If ICMP needs to be
restricted for security reasons, allow type 3 code 4 specifically (and
rate-limit it if abuse is a concern) rather than dropping the whole
type. Monitor for retransmission-heavy connections or a step change in
`docker exec r1 tcpdump ... icmp` volume right after any firewall change
that touches ICMP rules.

## Real-world examples of this pattern

- Classic "VPN works fine for browsing but big file transfers or certain
  API calls hang" tickets - almost always a blocked ICMP frag-needed
  message somewhere on the VPN gateway or an intermediate firewall.
- Cloud provider overlay networks (VXLAN, GENEVE) and CNI plugins
  running MTU a few dozen bytes below 1500 are a very common real-world
  version of this exact tunnel-MTU mismatch; combined with an
  overzealous security group or NACL blocking ICMP, this is a
  well-documented, recurring Kubernetes/cloud-networking incident
  pattern.
- MPLS and DSL/PPPoE links with sub-1500 MTUs have produced this exact
  "small requests fine, large ones hang" symptom in enterprise networks
  for decades - long before containers or cloud overlays existed.
