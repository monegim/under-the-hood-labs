# Lab 13 — Solutions

## Challenge A — nameserver unreachable

**Check:**
```bash
docker exec clab-broken-dns-client dig app.internal
```
After a long pause (`dig`'s default is 5 seconds x 2 retries), you get:
```
;; connection timed out; no servers could be reached
```
No `SERVFAIL`, no `NXDOMAIN`, no answer section at all — nothing came back
from anything.
```bash
docker exec clab-broken-dns-client ping -c 2 10.0.1.1
```
This succeeds — the client's own subnet and the real resolver at `10.0.1.1`
are both completely healthy.

**Diagnosis:** `/etc/resolv.conf` points at `10.0.1.99`, an address nothing
on the `10.0.1.0/24` segment answers on. This has nothing to do with DNS
as a protocol — the client never even gets a UDP packet back from *any*
process, because it's asking the wrong IP entirely. The ping to the real
resolver's address proves raw IP connectivity is fine, which is exactly
what isolates this as a configuration problem (wrong `nameserver` line),
not a network or DNS-server problem.

**Fix:**
```bash
docker exec clab-broken-dns-client bash -c "echo 'nameserver 10.0.1.1' > /etc/resolv.conf"
```

**Lesson:** a DNS timeout with zero response at all means the client isn't
even reaching a DNS server — check `/etc/resolv.conf` and raw reachability
to whatever IP is in it (`ping`, or `nc -uz` to port 53) before you go
anywhere near thinking about the resolver's configuration or upstream
health. This is the "can't reach the resolver" bucket, and it's the
easiest of the three to misdiagnose as "DNS is being slow," because a
timeout *feels* like a DNS problem even when DNS never entered the picture.

---

## Challenge B — resolver reachable, answering badly

**Check:**
```bash
docker exec clab-broken-dns-client dig app.internal
```
This comes back fast — no timeout — but the status line reads:
```
;; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: ...
```
`resolver` is clearly alive and listening: it replied immediately, with an
actual DNS message, just not a useful one.

**Diagnosis:** `resolver` is a pure forwarder with no local records of its
own — every query it can't already answer from cache has to go to
`upstream` at `10.0.2.2`. `upstream`'s `dnsmasq` process was killed, so
`resolver`'s forwarded query gets no reply, its own retry budget runs out,
and it does exactly what a forwarding resolver is supposed to do when its
upstream is unreachable: tell the client `SERVFAIL` rather than hang
forever. From the client's point of view this can look deceptively similar
to Challenge A ("DNS isn't working") — the only way to tell them apart is
that here you got an actual, fast DNS response with a status code, instead
of a timeout with none.

**Fix:**
```bash
docker exec -d clab-broken-dns-upstream dnsmasq -k --no-resolv --no-hosts \
  --address=/app.internal/10.9.9.99 --local-ttl=20 \
  --listen-address=10.0.2.2 --bind-interfaces
```

**Lesson:** "no response" and "a bad response" are different failure
domains and point at different hops. A timeout means look at reachability
to the resolver itself; a fast `SERVFAIL` (or any other non-`NOERROR`
status) means the resolver itself is fine and you need to look one hop
further out, at whatever it depends on to actually answer. Checking the
status line in `dig`'s output — not just whether it "worked" — is what
separates these two classes of DNS incident in seconds instead of minutes.
