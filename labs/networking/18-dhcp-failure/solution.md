# Lab 18 — Solutions

## Challenge A — address pool exhausted

**Check:**
```bash
docker exec clab-dhcp-lab-client dhclient -v -1 eth1
```
```
DHCPDISCOVER on eth1 to 255.255.255.255 port 67 interval ...
DHCPDISCOVER on eth1 to 255.255.255.255 port 67 interval ...
...
No DHCPOFFERS received.
```
Repeated `DHCPDISCOVER` broadcasts, and never a single `DHCPOFFER` back.
```bash
docker exec clab-dhcp-lab-dhcp-server bash -c "cat /var/lib/misc/dnsmasq.leases"
```
Both addresses in the pool, `10.50.0.100` and `10.50.0.101`, are already
leased to the two phantom MAC addresses seeded before the client even
asked, with a lease expiry far in the future.

**Diagnosis:** the server is completely healthy and completely reachable
— it received every `DHCPDISCOVER` (dnsmasq's own `--log-dhcp` output
confirms this if you check it) and made a correct decision: it has
nothing left to offer. A 2-address pool with 2 addresses already leased
has zero addresses left, full stop. This is not a network problem or a
misconfigured client; it's a capacity problem, and it looks identical to
"the DHCP server is down" from the client's point of view unless you
check the server's own lease state.

**Fix:** free up an address (release/expire an existing lease) or grow
the pool:
```bash
docker exec clab-dhcp-lab-dhcp-server pkill dnsmasq
docker exec clab-dhcp-lab-dhcp-server bash -c "rm -f /var/lib/misc/dnsmasq.leases"
docker exec -d clab-dhcp-lab-dhcp-server dnsmasq -k --no-resolv --no-hosts \
  --interface=eth1 --bind-interfaces \
  --dhcp-range=10.50.0.100,10.50.0.101,2m \
  --dhcp-leasefile=/var/lib/misc/dnsmasq.leases --log-dhcp
docker exec clab-dhcp-lab-client dhclient -v eth1
```

**Lesson:** "no DHCPOFFERS received" with `DHCPDISCOVER` going out
repeatedly means the client's own network path is fine — its broadcast is
reaching *somewhere*, or at least isn't being told no reachability
problem exists to blame. The server's own lease database (utilization
against pool size) is the very next thing to check, not the client's
config or the wire between them.

---

## Challenge B — lease expired, server unreachable for renewal

**Check:**
```bash
docker exec clab-dhcp-lab-client bash -c "sleep 130; ip addr show eth1"
```
`eth1` ends up with **no IPv4 address at all** by the end of the wait —
not just an old/stale one, gone entirely.
```bash
docker exec clab-dhcp-lab-client cat /var/lib/dhcp/dhclient.eth1.leases
```
The lease file shows the same address the client originally got, but its
recorded expiry has already passed.

**Diagnosis:** DHCP leases are time-limited on purpose, and renewal is an
active process, not a passive one. At roughly 50% of the lease lifetime
(T1), the client sends a unicast `DHCPREQUEST` straight to the server
that gave it the lease, asking to extend it. With the server's `dnsmasq`
process killed, that request goes unanswered. At roughly 87.5% of the
lease (T2, the rebinding time), the client escalates to a broadcast
`DHCPREQUEST`, asking *any* DHCP server to renew it — still nothing
answers, since there's only the one server and it's down. Once the lease
finally reaches 100% of its lifetime with no successful renewal at either
checkpoint, the client has no choice but to consider the address
invalid and remove it from the interface entirely — continuing to use an
address nobody can confirm is still assigned to you risks a collision
with whatever the server hands out to someone else next.

**Fix:** bring the DHCP server back and get a fresh lease:
```bash
docker exec -d clab-dhcp-lab-dhcp-server dnsmasq -k --no-resolv --no-hosts \
  --interface=eth1 --bind-interfaces \
  --dhcp-range=10.50.0.100,10.50.0.101,2m \
  --dhcp-leasefile=/var/lib/misc/dnsmasq.leases --log-dhcp
docker exec clab-dhcp-lab-client dhclient -v eth1
```

**Lesson:** the end state — no usable IP — is identical to Challenge A,
but the path there is completely different, and `dhclient -v`'s log is
what tells them apart: Challenge A never got an offer in the first place
(a capacity problem, visible from the very first `DHCPDISCOVER`);
Challenge B had a perfectly good lease and lost it because renewal
(`DHCPREQUEST` at T1/T2) went unanswered (a reachability problem,
visible only once you know to look at the timing of the renewal attempts
relative to when the lease was originally granted).
