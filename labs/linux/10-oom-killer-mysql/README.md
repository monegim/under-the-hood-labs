# Lab 10 — OOM Killer Takes Out MySQL

## Objective
Trigger a real out-of-memory kill against `mysqld`, then find the evidence
in `dmesg`/`journalctl -k` and correlate it back to `innodb_buffer_pool_size`
being set too high for available memory.

## Why this matters
"MySQL just died, no error in the MySQL error log, connections just started
refusing" is a classic DBRE incident. The cause is rarely MySQL itself — the
Linux OOM killer silently ends the process because *something* on the box
demanded more memory than was available, and mysqld (with a big buffer pool)
is usually the fattest target. If you don't know to check `dmesg`/`journalctl
-k` for OOM evidence, you'll waste hours staring at MySQL logs that say
nothing, because the kernel — not mysqld — pulled the trigger.

## Prerequisites
- Ubuntu VM, sudo access
- `mysql-server`, `stress-ng` (installed by `setup.sh`)
- cgroup v2 (default on modern Ubuntu with systemd)

Check first:
```bash
uname -a
stat -fc %T /sys/fs/cgroup/
systemctl --version | head -1
```
> Expect `cgroup2fs`. If you see `tmpfs` instead, you're on cgroup v1 —
> the lab should still mostly work via systemd's compat layer, but results
> may vary.

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This:
1. Installs `mysql-server` and `stress-ng`.
2. Creates `oom-lab.slice` with `MemoryMax=1200M`.
3. Moves `mysql.service` into that slice.
4. Sets `innodb_buffer_pool_size=900M` — deliberately large relative to the
   slice.
5. Restarts mysqld inside the capped slice.
6. Runs `stress-ng --vm 1 --vm-bytes 500M` in the same slice, pushing
   combined memory use over the 1200M ceiling.

## Step 2 — Confirm mysqld is gone
```bash
systemctl status mysql
```
> Gotcha: `systemctl status` will say something like "failed" or show a
> recent restart, NOT anything mentioning memory — systemd only knows the
> process exited, not why.

## Step 3 — Find the OOM evidence
```bash
sudo dmesg -T | grep -i -E 'oom|killed process'
sudo journalctl -k --since "5 min ago" | grep -i oom
```
Look for a line like:
```
Memory cgroup out of memory: Killed process NNNN (mysqld) ...
```
This tells you it was a **cgroup-scoped** OOM kill (the slice's
`MemoryMax`), not a whole-system OOM — an important distinction for where
you look next.

## Step 4 — Correlate to the misconfiguration
```bash
sudo grep -r innodb_buffer_pool_size /etc/mysql/
systemctl show mysql.service -p MemoryMax -p Slice
```
`innodb_buffer_pool_size=900M` plus mysqld's normal per-connection and
thread overhead leaves almost no headroom in a 1200M slice — the
`stress-ng` sibling was just the straw that broke it.

## Step 5 — Fix it
Either lower the buffer pool to fit the memory budget, or raise the budget
to fit the buffer pool. For this lab, lower the buffer pool:
```bash
sudo sed -i 's/innodb_buffer_pool_size=900M/innodb_buffer_pool_size=512M/' /etc/mysql/mysql.conf.d/zzz-lab22.cnf
sudo systemctl restart mysql
systemctl status mysql --no-pager
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — still not enough headroom:**
```bash
sudo systemd-run --unit=oom-lab-hog2 --slice=oom-lab.slice \
    stress-ng --vm 1 --vm-bytes 700M --vm-keep --timeout 60s
```
Even after your Step 5 fix, mysqld gets killed again. Check the actual
numbers this time (`systemctl show mysql.service -p MemoryMax`, current RSS
via `systemctl status mysql`) instead of just repeating the same fix — what
combination of buffer pool size and slice limit would actually be safe?

**Challenge B — the restart loop:**
```bash
sudo systemctl set-property oom-lab.slice MemoryMax=700M
sudo systemctl restart mysql
sudo systemd-run --unit=oom-lab-hog3 --slice=oom-lab.slice \
    stress-ng --vm 1 --vm-bytes 400M --vm-keep --timeout 120s
```
Wait a couple minutes and check `systemctl status mysql` again. mysqld
keeps getting killed and restarted (systemd's default `Restart=on-failure`
policy on the Ubuntu mysql unit) instead of just failing once. What does
that do to anyone trying to connect during this window, and how do you
prove — from logs alone — that this is a repeating loop and not a single
one-off event?

See `SOLUTION.md` only after you've formed your own diagnosis.
