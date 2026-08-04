# Lab 15 — Solutions

## Challenge A — SYN backlog exhausted, SYN cookies off

**Check:**
```bash
docker exec clab-syn-flood-victim sysctl net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog
```
```
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_max_syn_backlog = 128
```
```bash
docker exec clab-syn-flood-victim netstat -s | grep -i -E "SYN|listen|overflow"
```
A SYN-drop-related counter is climbing continuously while the flood runs.

**Diagnosis:** with `tcp_syncookies` disabled, the kernel handles every
inbound SYN the traditional way — allocate a small request-socket entry
recording the half-open connection, and hold it until either the final ACK
of the handshake arrives or it times out. That table has a hard ceiling
(`tcp_max_syn_backlog`, here artificially set to 128). `hping3 --flood
--rand-source` generates SYNs from thousands of different fake source
addresses, none of which will ever send the final ACK, so every single
entry the flood creates sits there doing nothing until it times out —
and at flood rate, the 128-slot table fills far faster than entries can
expire. Once it's full, the kernel silently drops *any* new SYN, including
the legitimate client's, indistinguishable at that point from an attacker's.

**Fix:**
```bash
docker exec clab-syn-flood-victim sysctl -w net.ipv4.tcp_syncookies=1
docker exec clab-syn-flood-attacker bash -c "time nc -zv -w 3 10.0.0.20 8080"
```
The legitimate connection now succeeds immediately, even with the flood
still running.

**Lesson:** a small, static half-open-connection table is straightforwardly
exhaustible by any determined-enough flood — no cleverness required from
the attacker, just spoofed sources and volume. Enabling `tcp_syncookies`
is the real fix because it eliminates the *need* for that table in the
first place, per the mechanism below.

---

## Challenge B — a bigger backlog is not a fix

**Check:**
```bash
docker exec clab-syn-flood-victim sysctl net.ipv4.tcp_max_syn_backlog
# net.ipv4.tcp_max_syn_backlog = 4096
docker exec clab-syn-flood-attacker bash -c "time nc -zv -w 3 10.0.0.20 8080"
```
Given a few seconds of sustained flooding, the legitimate connection times
out again — it just took longer to start failing than it did in
Challenge A.

**Diagnosis:** `tcp_max_syn_backlog=4096` is still a fixed, finite number.
`hping3 --flood` isn't rate-limited to "whatever fit in 128 slots" — it
sends as fast as the attacker's CPU/NIC allow, so a 32x bigger queue just
means the flood needs roughly 32x as many packets (a fraction of a second
more, at flood rate) to fill it completely. Nothing about raising the
ceiling changes the fundamental problem: `tcp_syncookies=0` means every
inbound SYN still consumes a real, finite table slot, and any flood large
enough (which, on the modern internet, is trivially large enough) will
eventually consume all of them, whatever the ceiling is set to.

**Fix:** the same one as Challenge A — `tcp_syncookies=1`. Once it's on,
the backlog size stops being the thing standing between the victim and
exhaustion at all.

**Lesson:** tuning a queue's *size* only ever buys time against a flood,
never immunity from one — it's treating the symptom. SYN cookies fix the
actual mechanism: instead of storing a request-socket per inbound SYN, the
kernel encodes the connection's essential state (a hash of source/dest
IP/port, a timestamp, and the negotiated MSS) directly into the SYN-ACK's
initial sequence number, and verifies it cryptographically when the real
ACK comes back — no table entry, no backlog slot, and no state at all
exists for a spoofed SYN with no real client behind it. This is why
`tcp_syncookies` is the specific, correct kernel-level mitigation for SYN
floods, and why "just raise the backlog number" is the fix that looks
right and isn't.
