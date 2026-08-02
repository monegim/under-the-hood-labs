# Lab 24 — Solutions

## Challenge A — After= without Requires=

**Check:**
```bash
systemctl status webapp
journalctl -u webapp --no-pager | tail -10
systemctl show webapp.service -p After -p Requires
```
`After` now lists `mysql.service`, but `Requires` is still empty. `webapp`
still fails the same `mysqladmin ping` check.

**Diagnosis:** `After=` is a pure **ordering** directive — it tells systemd
"if both units are part of the same transaction, start this one later." It
does NOT pull `mysql.service` in as a dependency, and it does not care
whether `mysql.service` is even enabled, masked, or healthy. Since we
masked `mysql.service` and never asked systemd to start it, there's no
transaction where ordering applies — `webapp` just starts immediately on
its own, exactly as if `After=` weren't there at all.

**Fix:**
```bash
sudo tee /etc/systemd/system/webapp.service.d/override.conf > /dev/null <<'EOF'
[Unit]
After=mysql.service
Requires=mysql.service
EOF
sudo systemctl unmask mysql.service
sudo systemctl daemon-reload
sudo systemctl restart webapp
```
`Requires=` is what actually pulls `mysql.service` into the job and fails
`webapp`'s start cleanly (with a clear dependency-failure message) if mysql
can't come up, instead of starting anyway and failing at the application
level.

**Lesson:** `After=` answers "in what order," `Requires=`/`Wants=` answers
"does it need to exist at all." You almost always need both — ordering
alone is a very common half-fix that looks correct in quick testing (mysql
usually happens to be running) but doesn't protect you the one time it
isn't.

---

## Challenge B — bad fstab entry

**Check:**
```bash
sudo mount -a
```
Fails immediately: `mount: /mnt/appdata: special device /dev/thisdoesnotexist does not exist.`

```bash
systemctl status local-fs.target
systemctl list-units --type=mount --state=failed
journalctl -b | grep -i -E 'mount|appdata'
```
Shows a generated `mnt-appdata.mount` unit in `failed` state, and
`local-fs.target` either not fully reached or delayed.

**Diagnosis:** systemd auto-generates a `.mount` unit from every `/etc/fstab`
line at boot (via `systemd-fstab-generator`), and by default that mount is
required by `local-fs.target` unless the entry has the `nofail` option.
A service declaring `RequiresMountsFor=/mnt/appdata` would then fail to
start too — not because of anything in its own unit file, but because a
dependency two layers removed (a mount, generated from a config file) never
came up. This is exactly the "only breaks after reboot" class of bug: the
mount unit is only evaluated at boot / `daemon-reload` + `mount -a` time,
so a typo'd fstab entry sits harmless until the next full boot.

**Fix:**
```bash
sudo sed -i '/thisdoesnotexist/d' /etc/fstab
sudo systemctl daemon-reload
sudo mount -a
```

**Lesson:** an `fstab` typo is invisible until the next boot (or an
explicit `mount -a`/`daemon-reload`) — always validate fstab changes with
`sudo mount -a` (or `findmnt --verify`) immediately after editing it, not
after the next reboot finds out for you. And if a mount is genuinely
optional, use `nofail` so a bad entry degrades gracefully instead of
blocking `local-fs.target`.
