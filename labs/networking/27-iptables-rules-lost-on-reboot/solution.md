# Lab 27 — Solutions

## Challenge A — backed up, but never wired up to load

**Check:**
```bash
systemctl is-enabled netfilter-persistent
```
Reports `disabled` (or "not found" if it isn't installed at all).

**Diagnosis:** `iptables-save > /etc/iptables/rules.v4` correctly wrote
a rules file the `netfilter-persistent` tooling knows how to read — but
having a correctly-placed file is not the same as having something
configured to *read* it automatically at boot. That's the job of the
`netfilter-persistent` **service** (a systemd unit provided by the
`netfilter-persistent`/`iptables-persistent` packages), and a service
that's installed but not enabled never runs at boot at all — it has to
be explicitly enabled, exactly like any other systemd service. A
perfect backup file with nothing scheduled to load it is exactly as
useless, at boot time, as no backup file at all.

**Fix:**
```bash
sudo systemctl enable netfilter-persistent
sudo systemctl enable --now netfilter-persistent
```

**Lesson:** "the data is backed up correctly" and "the data will
actually be restored/reloaded automatically" are two separate claims —
verify both, every time, for any persistence mechanism (firewall rules,
cron-driven backups, config management). A correct file sitting
un-loaded is a false sense of security that's often worse than knowing
you have no backup at all, because it looks solved.

---

## Challenge B — saved to the wrong place entirely

**Check:**
```bash
cat /etc/iptables/rules.v4 2>/dev/null | grep 9999 || echo "not found in the expected location"
```
The real rule lives in `/root/my-firewall-backup.txt` — a location
`netfilter-persistent` has no idea exists.

**Diagnosis:** `iptables-save` just prints the current ruleset to
stdout — where that output goes is entirely up to whatever redirected
it. `netfilter-persistent` (on Debian/Ubuntu) is hardcoded to read from
specific, documented paths (`/etc/iptables/rules.v4` for IPv4,
`/etc/iptables/rules.v6` for IPv6) — a perfectly valid, perfectly
correct rules file saved anywhere else is invisible to it, no matter how
confident the person who saved it felt.

**Fix:**
```bash
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
sudo systemctl enable --now netfilter-persistent
```
Or, the tool-native way that avoids needing to remember the exact path
at all:
```bash
sudo netfilter-persistent save
```

**Lesson:** don't hand-roll a persistence step for a tool that already
has a documented, purpose-built command for exactly that
(`netfilter-persistent save` over a manual `iptables-save > <path I
think is right>`) — the manual version has to get an undocumented
implementation detail (the exact expected path) correct by memory,
while the tool-native command can't get that part wrong.
