# Lab 17 — Solutions

## Challenge A — table full from a burst of concurrent connections

**Check:**
```bash
docker exec clab-conntrack-lab-r1 sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```
`nf_conntrack_count` is pinned at `128`, exactly equal to
`nf_conntrack_max` — the table is completely full.
```bash
docker exec clab-conntrack-lab-r1 conntrack -S
```
`insert_failed` and `drop` are both nonzero and increase further if you
retry a new connection while the burst is still active.
```bash
docker exec clab-conntrack-lab-client bash -c 'time (exec 3<>/dev/tcp/10.0.2.10/9090; echo ok)'
```
This new attempt hangs until the shell's own TCP connect timeout, then
fails — no RST, no ICMP error, just silence.
```bash
sudo dmesg | grep -i conntrack
```
On the host (or wherever the kernel log is visible for `r1`'s network
namespace), you'll see repeated `nf_conntrack: table full, dropping
packet` — the single most direct confirmation available.

**Diagnosis:** `r1` is tracking every forwarded connection (Step 2's
explicit conntrack rule ensures that), and the table's ceiling
(`nf_conntrack_max=128`) is far smaller than the number of concurrent
connections this burst creates. Once full, the kernel's conntrack code
fails closed: a new connection that needs a fresh table entry and can't
get one has its packet dropped outright, silently, before it's even
forwarded toward `server`. From either endpoint, this looks exactly like
"the network is being flaky" — no error message points at conntrack
specifically unless you go looking at `r1`'s own counters and kernel log.

**Fix:**
```bash
docker exec clab-conntrack-lab-r1 sysctl -w net.netfilter.nf_conntrack_max=8192
```
In production this is a capacity-planning fix: size `nf_conntrack_max`
(and the underlying hash table, `net.netfilter.nf_conntrack_buckets`) for
the actual peak concurrent-connection count you expect, with headroom —
not for whatever the distribution's default happened to be.

**Lesson:** a full conntrack table fails silently and looks identical to
generic packet loss or an unresponsive server from outside the box that's
actually enforcing the limit. `conntrack -C`/`-S` and the kernel log are
the only places this failure actually announces itself — check them
specifically instead of assuming the network or the destination is at
fault.

---

## Challenge B — table full from leaked, never-closed connections

**Check:**
```bash
docker exec clab-conntrack-lab-r1 conntrack -C
```
Also at (or near) `128` — same symptom as Challenge A on the surface.
```bash
docker exec clab-conntrack-lab-r1 conntrack -L -o extended | grep ESTABLISHED | head
```
Every entry here shows a large remaining timeout (well under the full
`ESTABLISHED` timeout ceiling, but clearly not seconds-old, freshly-torn-
down entries either) and there's no burst of recent `NEW`-state churn to
point at — just a steady population of long-lived connections. Nothing in
`r1`'s recent traffic pattern looks like an attack or a spike; the
connections simply never got closed.

**Diagnosis:** this time the table filled up gradually, from a client
application that opens a connection and never closes it (a real and
extremely common bug class — a missing `close()`/`finally` block, a retry
loop that reconnects without cleaning up the old socket, a connection
pool with no idle eviction). Each individual connection is completely
legitimate when it's created; the problem is purely that none of them
ever get torn down, so they accumulate against the same fixed
`nf_conntrack_max` ceiling Challenge A hit, just far more slowly and with
no burst signature to spot.

**Fix:** raising `nf_conntrack_max` buys headroom the same way it did in
Challenge A, but doesn't touch the actual bug — the real fix here is on
the client application side: close connections it's done with. As an
operational stopgap while that gets fixed, forcibly evicting the leaked
entries frees the table immediately:
```bash
docker exec clab-conntrack-lab-r1 conntrack -F
```

**Lesson:** identical symptom (`conntrack -C` pinned at the max, new
connections silently dropped), genuinely different root cause. The
tell isn't the count — it's the *composition* of what's actually in the
table. A pile of long-lived, unremarkable-looking `ESTABLISHED` entries
with no recent creation burst points at a leak, not an attack or a
traffic spike, and the fix for one (capacity/rate mitigation) does
nothing for the other (a client that needs to actually close its
sockets).
