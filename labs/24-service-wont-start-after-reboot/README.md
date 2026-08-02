# Lab 24 — Service Won't Start After Reboot

## Objective
Reproduce a systemd startup-ordering bug — a service that depends on MySQL
but doesn't declare it — and learn to read `journalctl -u <unit>` for the
real cause instead of just restarting things until they work.

## Why this matters
"It worked before the reboot, now it's dead" is a very common ticket, and
the cause is almost always ordering: two services started in parallel by
systemd, one silently assuming the other is already up. This is invisible
in day-to-day operation (you rarely restart the whole box), which is
exactly why it only shows up after a reboot or a full cluster restart —
the worst possible time to discover it.

## Prerequisites
- Ubuntu VM, sudo access, systemd
- `mysql-server` (installed by `setup.sh`)

Check first:
```bash
uname -a
systemctl --version | head -1
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This installs a `webapp.service` that checks MySQL connectivity on start,
but has **no** `After=`/`Requires=` on `mysql.service`. It then simulates
the losing side of a boot-time race: stops mysql, then starts webapp.

> Gotcha: on a real reboot this bug doesn't fail every time — it depends on
> which service happens to win the race. That's what makes it dangerous:
> it can pass in testing and only bite you on the one reboot that matters.

## Step 2 — Confirm the failure
```bash
systemctl status webapp
```
Should show `failed` (or `activating (auto-restart)` briefly, then
`failed`, since `Restart=no`).

## Step 3 — Read the actual error
```bash
journalctl -u webapp --no-pager | tail -20
```
Look for the `mysqladmin ping` failure — something like `mysqladmin: connect
to server at 'localhost' failed / error: 'Can't connect to local MySQL
server'`.

## Step 4 — Confirm the root cause, not just the symptom
```bash
systemctl show webapp.service -p After -p Requires -p Wants
systemctl is-active mysql
```
`After=`/`Requires=` come back empty for `mysql.service` — nothing in the
unit file tells systemd these two need to be ordered. And `mysql` is
confirmed not running, which is exactly what `webapp.sh`'s connectivity
check caught.

## Step 5 — Fix it
```bash
sudo mkdir -p /etc/systemd/system/webapp.service.d
sudo tee /etc/systemd/system/webapp.service.d/override.conf > /dev/null <<'EOF'
[Unit]
After=mysql.service
Requires=mysql.service
EOF
sudo systemctl daemon-reload
sudo systemctl start mysql
sudo systemctl restart webapp
systemctl status webapp --no-pager
```
> Gotcha: `After=` alone only affects **order**, not whether MySQL actually
> succeeded — that's what `Requires=` adds. On Ubuntu, `mysql.service` uses
> `Type=notify`/proper readiness signaling, so "active" from systemd's
> point of view really does mean "accepting connections," which is why
> `After=mysql.service` is sufficient here for *timing* once `Requires=`
> guarantees mysql is actually started at all.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — After= without Requires=:**
```bash
sudo tee /etc/systemd/system/webapp.service.d/override.conf > /dev/null <<'EOF'
[Unit]
After=mysql.service
EOF
sudo systemctl daemon-reload
sudo systemctl stop mysql
sudo systemctl mask mysql.service
sudo systemctl restart webapp
systemctl status webapp
```
`webapp` still fails to connect, even with `After=` in place. Diagnose why
`After=` alone wasn't enough here, and what `mask` (vs. `stop`) tells you
about the difference between an ordering guarantee and a presence
guarantee.

**Challenge B — a bad fstab entry instead:**
```bash
sudo systemctl unmask mysql.service
sudo systemctl start mysql
echo '/dev/thisdoesnotexist /mnt/appdata ext4 defaults 0 2' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount -a
```
This is a different root cause than the MySQL ordering bug — a required
mount that will never come up. Check `systemctl status local-fs.target`
and `journalctl -xe` (or `journalctl -b`) for what a broken `fstab` entry
does to boot-time mount ordering, and think through what a service with
`RequiresMountsFor=/mnt/appdata` would experience on the next real reboot.

See `SOLUTION.md` only after you've formed your own diagnosis.
