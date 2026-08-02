# Lab 25 — Log Partition Full

## Objective
Reproduce a dedicated log partition filling up from a real runaway
error-retry loop, find the offending process, and set up rotation so it
can't happen silently again.

## Why this matters
A crash-looping process that logs every failed attempt is one of the most
common ways production disks fill up — not a slow leak over weeks, but a
partition going from fine to 100% in minutes. Many shops put `/var/log` (or
an app's logs) on its own partition specifically so a runaway logger can't
take out the root filesystem — but that only helps if you actually notice
and rotate/stop it before the log partition itself blocks every write the
app tries to make (including its own error log).

## Prerequisites
- Ubuntu VM, sudo access
- `losetup`, `mkfs.ext4`, `logrotate` (installed by default on Ubuntu)

Check first:
```bash
uname -a
which losetup mkfs.ext4 logrotate
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 300M loopback-backed filesystem mounted at `/var/log/myapp`
(standing in for a dedicated log partition), then starts `flaky-app.sh` — a
script that logs an error line in a tight loop with no throttling and no
rotation, simulating an app stuck retrying a connection that keeps
failing.

Wait ~15-30 seconds for it to fill.

## Step 2 — Confirm the symptom
```bash
df -h /var/log/myapp
```
Should show at or near 100% used.

## Step 3 — Find the actual offender
```bash
du -sh /var/log/myapp/*
```
> Gotcha: don't assume it's one file — `du -sh /var/log/myapp/*` shows you
> per-file size, which matters once you're dealing with a directory that
> has more than one log file in it.

Confirm which process is actively writing to it:
```bash
sudo lsof +D /var/log/myapp
```
The `flaky-app.sh` PID shows up with `error.log` open for writing.

## Step 4 — Watch the downstream failure
```bash
sudo -u nobody touch /var/log/myapp/canary.txt
```
Fails with `No space left on device` — any other process trying to write
into this same partition (including a real app's own logging) would fail
the exact same way once it's full.

## Step 5 — Stop the bleeding
```bash
sudo pkill -f flaky-app.sh
```

## Step 6 — Reclaim space without destroying the evidence
Don't just `rm` the log outright in a real incident — truncate it so any
open file handle and forensic tooling still works, and you keep a
paper trail:
```bash
sudo truncate -s 0 /var/log/myapp/error.log
df -h /var/log/myapp
```

## Step 7 — Prevent recurrence with logrotate
```bash
sudo tee /etc/logrotate.d/myapp > /dev/null <<'EOF'
/var/log/myapp/error.log {
    size 20M
    rotate 3
    missingok
    notifempty
    compress
}
EOF
sudo logrotate -f /etc/logrotate.d/myapp
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — more than one writer:**
```bash
sudo bash setup.sh
sudo cp /usr/local/bin/flaky-app.sh /usr/local/bin/flaky-app-2.sh
sudo sed -i 's/error.log/error2.log/' /usr/local/bin/flaky-app-2.sh
nohup /usr/local/bin/flaky-app-2.sh > /tmp/flaky-app-2.log 2>&1 &
disown
```
Stopping the first flaky app doesn't fully fix it this time. Find every
process writing into `/var/log/myapp`, not just the one you already know
about, before you declare it resolved.

**Challenge B — journald fills up instead:**
```bash
sudo tee /etc/systemd/system/crashloop-demo.service > /dev/null <<'EOF'
[Unit]
Description=Lab crash-loop (logs via stdout, captured by journald)

[Service]
ExecStart=/bin/bash -c 'while true; do echo "ERROR: config reload failed, retrying..."; done'
Restart=always
RestartSec=0

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl start crashloop-demo
```
No dedicated log partition involved this time — the app just logs to
stdout, which `journald` captures. Let it run for a minute, then check
`journalctl --disk-usage`. What's filling up, where does it actually live
on disk, and what's the equivalent of `logrotate` for journald?

See `SOLUTION.md` only after you've formed your own diagnosis.
