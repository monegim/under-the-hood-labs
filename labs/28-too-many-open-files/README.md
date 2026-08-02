# Lab 28 — Too Many Open Files

## Objective
Reproduce a real file-descriptor exhaustion (`EMFILE`, "Too many open
files") incident, diagnose current usage vs the configured limit, and
learn the two *different* mechanisms that set that limit — and why fixing
only one of them is a common, confusing mistake.

## Why this matters
Every "too many open files" incident boils down to the same question: is
the process hitting `RLIMIT_NOFILE`, and if so, where does that limit
actually come from? There are two unrelated mechanisms on a typical Linux
box:
- **systemd services** get their limits from the unit file (`LimitNOFILE=`
  in `[Service]`), applied directly by PID 1 when it execs the process.
- **PAM-based login sessions** (SSH logins, `su -`, cron in some setups,
  anything going through `pam_limits.so`) get their limits from
  `/etc/security/limits.conf` (or `/etc/security/limits.d/*.conf`).

These two are **not the same mechanism** and do not affect each other. The
single most common mistake in this incident: someone raises the limit in
`limits.conf`, restarts the (systemd-managed) service, and is baffled when
it still crashes — because systemd never consulted `limits.conf` in the
first place.

## Prerequisites
- Linux VM, Python 3, `lsof`
- `sudo` access (for the systemd-specific challenges)

Check first:
```bash
ulimit -Sn
ulimit -Hn
cat /proc/sys/fs/file-nr
cat /proc/sys/fs/file-max
which lsof python3
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This starts a Python process that opens files in a loop under an
artificially low soft limit (`ulimit -n 64`), captures its PID to
`/var/tmp/lab28/hog.pid`, and lets it run into `EMFILE` on purpose. It then
sleeps, holding all its fds open so you can inspect it.

## Step 2 — Confirm the symptom
```bash
cat /var/tmp/lab28/err.log
```
You should see something like:
```
FAILED after opening 61 files: [Errno 24] Too many open files: '/var/tmp/lab28/junk_61.tmp'
```
`Errno 24` is `EMFILE` — the per-process open-file limit, not the
system-wide `file-max`.

## Step 3 — Check current usage vs the configured limit
```bash
PID=$(cat /var/tmp/lab28/hog.pid)
grep -i "open files" /proc/$PID/limits
lsof -p "$PID" | wc -l
ls -la /proc/$PID/fd | wc -l
```
`/proc/$PID/limits` shows the actual soft/hard `Max open files` this
process is running under (both `64` here, since a plain `ulimit -n N`
without `-S`/`-H` sets both soft and hard). `lsof -p` and `/proc/$PID/fd`
both independently confirm it's sitting right at that ceiling (61 opened
files + stdin/stdout/stderr = 64).

> Gotcha: `/proc/$PID/limits` is the ground truth for **that specific
> process**. `ulimit -n` in your current shell tells you nothing about a
> different process's limit — a very common mistake is checking your own
> shell's `ulimit` and assuming it matches the service you're debugging.

Also check the system-wide ceiling — a second, unrelated way this error
can happen:
```bash
cat /proc/sys/fs/file-nr
cat /proc/sys/fs/file-max
```
`file-nr`'s first field is the total file handles currently allocated
system-wide; if that's near `file-max`, no single process's `ulimit` will
save you — the whole kernel table is full. That's a `sysctl
fs.file-max` problem, a different fix from a per-process `ulimit`.

## Step 4 — Fix it for a running process, without a restart
If you can't afford to restart the process, you can raise a *running*
process's limit live with `prlimit` (requires `CAP_SYS_RESOURCE`, i.e.
root, to raise a hard limit):
```bash
PID=$(cat /var/tmp/lab28/hog.pid)
sudo prlimit --pid "$PID" --nofile=4096:4096
grep -i "open files" /proc/$PID/limits
```
The process itself doesn't automatically retry old failed opens, but any
new `open()` calls it makes from now on can succeed.

## Step 5 — The two REAL fixes (and why they're different)

**If the process is managed by systemd**, the limit lives in the unit.
First, put the same hog under systemd so you have a real unit to work
with:
```bash
sudo tee /etc/systemd/system/lab28-hog.service > /dev/null <<'EOF'
[Unit]
Description=Lab 28 fd hog (systemd-managed)

[Service]
ExecStart=/usr/bin/python3 /var/tmp/lab28/fd_hog.py
LimitNOFILE=64

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl start lab28-hog.service
journalctl -u lab28-hog.service -n 20 --no-pager
```
It hits the same `EMFILE` at 64, now under systemd. Fix it via a drop-in
(cleaner than editing the shipped unit directly):
```bash
sudo mkdir -p /etc/systemd/system/lab28-hog.service.d
sudo tee /etc/systemd/system/lab28-hog.service.d/override.conf > /dev/null <<'EOF'
[Service]
LimitNOFILE=65536
EOF
sudo systemctl daemon-reload
sudo systemctl restart lab28-hog.service
```
> Gotcha: `systemctl daemon-reload` is **required** after editing any unit
> file or drop-in. Without it, `systemctl restart` uses the OLD in-memory
> unit definition — systemd does not auto-detect unit file changes on
> disk for you.

**If the process is started via a login session** (SSH, `su -`, or
anything going through PAM), the limit lives in `limits.conf` instead, and
only applies to **new** sessions:
```bash
echo "appuser soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "appuser hard nofile 65536" | sudo tee -a /etc/security/limits.conf
# then start a NEW session for appuser (new SSH login, new `su - appuser`, etc.)
```
Editing the file does nothing for sessions that already exist — `pam_limits.so`
only applies limits at session start.

**Why both exist:** systemd services are spawned directly by PID 1, which
never goes through a PAM login flow, so `limits.conf` is irrelevant to
them. Session-based processes (a shell you SSH into, tools launched from
that shell) never read systemd unit files. Same symptom (`EMFILE`), two
completely separate configuration paths depending on *how the process was
started* — not what kind of process it is.

## Challenges (don't read ahead — diagnose before you fix)

These continue from the systemd unit you already built in Step 5.

**Challenge A:**
```bash
sudo rm -f /etc/systemd/system/lab28-hog.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart lab28-hog.service
journalctl -u lab28-hog.service -n 20 --no-pager

# "fix" attempt:
echo "root soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "root hard nofile 65536" | sudo tee -a /etc/security/limits.conf
sudo systemctl restart lab28-hog.service
journalctl -u lab28-hog.service -n 20 --no-pager
```
The service still dies with the same `EMFILE` after the "fix." Diagnose
why the `limits.conf` change had zero effect here.

**Challenge B:**
```bash
sudo systemctl stop lab28-hog.service
sudo rm -f /etc/systemd/system/lab28-hog.service.d/override.conf
sudo sed -i 's/LimitNOFILE=64/LimitNOFILE=65536/' /etc/systemd/system/lab28-hog.service
sudo systemctl restart lab28-hog.service
journalctl -u lab28-hog.service -n 20 --no-pager
grep -i "open files" /proc/$(systemctl show -p MainPID --value lab28-hog.service)/limits
```
You edited the unit file with the correct new value and restarted, but
`/proc/<pid>/limits` still shows the OLD limit. What step got skipped?

See `SOLUTION.md` only after you've formed your own diagnosis.
