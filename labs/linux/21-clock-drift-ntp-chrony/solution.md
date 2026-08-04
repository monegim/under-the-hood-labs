# Lab 21 — Solutions

## Challenge A — unreachable NTP server, silently never syncing

**Check:**
```bash
systemctl status chrony
chronyc sources -v
```
`systemctl status` shows `active (running)` — nothing looks wrong there.
`chronyc sources -v` tells a different story: the configured server
shows as unreachable (a `?` or blank reach column, reach value staying
at `0`), meaning chrony has never successfully polled it.

**Diagnosis:** the daemon is healthy; the *configuration* points at a
server that will never answer (`192.0.2.1` is a documentation/test
address, RFC 5737 — it's never routable). "The service is running" and
"the service is doing its job" are two different checks, and
`systemctl status` only ever answers the first one.

**Fix:**
```bash
sudo cp /etc/chrony/chrony.conf.lab21.bak /etc/chrony/chrony.conf
sudo systemctl restart chrony
chronyc sources -v
sudo chronyc makestep
```

**Lesson:** a synced-looking daemon can still be silently useless — always
check what it's actually configured to talk to (`chronyc sources`), not
just whether the process is alive (`systemctl status`).

---

## Challenge B — NTP traffic blocked at the firewall

**Check:**
```bash
chronyc sources -v
sudo tcpdump -ni any udp port 123 -c 5
```
`chronyc sources` looks similar to Challenge A (no successful sync) — but
`tcpdump` shows the real difference: outbound NTP packets (UDP/123)
*leaving* the host, with no replies ever coming back. In Challenge A,
nothing was ever sent anywhere useful in the first place (bad address);
here, requests are actually going out and being dropped somewhere on the
return path.

**Diagnosis:** a local firewall rule is dropping outbound UDP/123, so
chrony's requests never get a chance to reach a perfectly reachable,
correctly-configured server. From `chronyc sources` alone, this looks
identical to "server unreachable" — the only way to tell them apart is
to actually watch the packets.

**Fix:**
```bash
sudo iptables -D OUTPUT -p udp --dport 123 -j DROP
sudo chronyc makestep
```

**Lesson:** "not syncing" has at least two distinct failure layers —
configuration (pointed at the wrong place) and connectivity (blocked in
transit) — and they present identically in the application-level tool
(`chronyc`). When the app-level tool can't distinguish the cause, drop to
a packet capture; it's the only thing that tells you whether traffic is
leaving and coming back at all.
