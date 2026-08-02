# Lab 16 — Solutions

## Challenge A — limits.conf doesn't apply to systemd services

**Check:**
```bash
systemctl show lab28-hog.service -p LimitNOFILE
grep -i "open files" /proc/$(systemctl show -p MainPID --value lab28-hog.service)/limits
journalctl -u lab28-hog.service -n 20 --no-pager
```
`systemctl show ... -p LimitNOFILE` reports `64` — completely unaffected
by the lines you appended to `/etc/security/limits.conf`. The journal
shows the same `EMFILE` crash as before.

**Diagnosis:** `/etc/security/limits.conf` is read by `pam_limits.so`,
which only runs during a PAM-managed login session (SSH login, `su -`,
console login, etc.). systemd starts services directly from PID 1 via
`fork()`/`exec()` — there's no PAM session involved anywhere in that path,
so `pam_limits.so` never runs and `limits.conf` is never consulted. The
only thing that sets resource limits for a systemd unit is the unit's own
`Limit*=` directives (or `DefaultLimitNOFILE=` in
`/etc/systemd/system.conf` if the unit doesn't override it).

**Fix:**
```bash
sudo mkdir -p /etc/systemd/system/lab28-hog.service.d
sudo tee /etc/systemd/system/lab28-hog.service.d/override.conf > /dev/null <<'EOF'
[Service]
LimitNOFILE=65536
EOF
sudo systemctl daemon-reload
sudo systemctl restart lab28-hog.service
```

**Lesson:** "how a process is started" determines which limit mechanism
applies — not what kind of workload it is. Before touching
`limits.conf`, check `systemctl show <unit> -p LimitNOFILE` (or grep the
unit file) to confirm you're editing the mechanism that's actually in
effect for that process.

---

## Challenge B — forgot `daemon-reload`

**Check:**
```bash
cat /etc/systemd/system/lab28-hog.service | grep LimitNOFILE
systemctl show lab28-hog.service -p LimitNOFILE
grep -i "open files" /proc/$(systemctl show -p MainPID --value lab28-hog.service)/limits
```
The file on disk says `LimitNOFILE=65536`. `systemctl show` (systemd's
in-memory view) still reports `64`, and so does the running process's
`/proc/<pid>/limits`.

**Diagnosis:** systemd parses unit files once and keeps that parsed
configuration in memory. Editing a unit file on disk does not
automatically invalidate that cache — `systemctl restart` restarts the
*process* using whatever unit definition systemd currently has loaded,
which is still the old one. `systemctl daemon-reload` is the step that
tells systemd "re-read unit files from disk" go get its in-memory model
updated. Skip it, and every `start`/`restart` after your edit keeps using
the stale config, silently.

**Fix:**
```bash
sudo systemctl daemon-reload
sudo systemctl restart lab28-hog.service
grep -i "open files" /proc/$(systemctl show -p MainPID --value lab28-hog.service)/limits
```

**Lesson:** editing a unit file is not the same as applying it. Any time
you touch a `.service` file (or a drop-in) by hand, `daemon-reload` before
`restart` is not optional — and if a "fix" you just applied doesn't seem
to be taking effect, check whether you actually reloaded systemd's view
of the config before assuming the fix itself is wrong.
