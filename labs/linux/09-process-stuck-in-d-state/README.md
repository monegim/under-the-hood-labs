# Lab 9 — Process Stuck in D State

## Objective
Build a real process stuck in uninterruptible sleep (`D` state) using a
hung NFS mount, and learn why `kill -9` cannot touch it until the underlying
I/O resolves.

## Why this matters
Every SRE eventually hits a process that won't die no matter what signal
you send it. This is almost always a process blocked in kernel space on I/O
— a hung NFS/SAN mount, a failing disk, a stuck device driver — not a
process ignoring signals. Knowing the difference (and knowing you have to
fix the I/O, not the process) saves you from restarting the wrong thing or
rebooting a box that didn't need it.

## Prerequisites
- Ubuntu VM, sudo access, internet access for `apt install`
- `nfs-kernel-server`, `nfs-common`, `iptables` (installed by `setup.sh`)

Check first:
```bash
uname -a
which mount.nfs iptables
```

> Gotcha: this lab mounts NFS to `127.0.0.1` (localhost exporting to
> itself). That's unusual for production but is the most reliable, portable
> way to build this lab on any VM — it doesn't depend on real disk hardware
> or a second host.

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This exports `/srv/nfslab` over NFS to itself, mounts it at `/mnt/nfslab`
with a `hard` mount, starts a `dd` writing 2GB into it, then drops all
traffic to the NFS port (2049) mid-write.

## Step 2 — Find the hung process
```bash
ps aux | grep '[d]d'
```
Note the PID and the `STAT` column.

## Step 3 — Confirm D state
```bash
ps -o pid,stat,wchan:32,cmd -p <PID>
```
> `STAT` shows `D` (or `D+` if foreground). `WCHAN` shows the kernel
> function it's blocked in — for NFS this is usually something like
> `nfs_wait_bit_killable` or similar wait-on-RPC-reply function.

Cross-check with `/proc`:
```bash
cat /proc/<PID>/status | grep State
```

## Step 4 — Try to kill it (it won't work)
```bash
sudo kill -9 <PID>
ps -o pid,stat,cmd -p <PID>
```
> Gotcha: the process is still there. `SIGKILL` is queued by the kernel but
> cannot be delivered while the task is in `TASK_UNINTERRUPTIBLE` — it's
> not "ignoring" the signal, the kernel won't schedule it to check for
> pending signals until the blocking syscall returns.

## Step 5 — Fix the actual cause, then watch it die
```bash
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -D INPUT -p tcp --sport 2049 -j DROP
```
Give it a few seconds, then re-check:
```bash
ps -o pid,stat,cmd -p <PID>
```
The queued `SIGKILL` finally lands once the write can complete, and the
process exits.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — multiple hung processes at once:**
```bash
sudo bash -c 'for i in 1 2 3; do nohup dd if=/dev/zero of=/mnt/nfslab/file$i bs=1M count=2000 > /tmp/dd$i.log 2>&1 & disown; done'
sleep 1
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A INPUT -p tcp --sport 2049 -j DROP
```
Now find every affected process system-wide (not just the ones you started
on purpose — assume you didn't know how many there were), and figure out
whether killing the NFS block alone is enough, or whether you need to do
anything else to get the mount itself back to normal.

**Challenge B — the fix doesn't feel instant:**
Repeat the main lab (Step 1 through Step 4), but this time, right after you
remove the `iptables` rules in Step 5, immediately run:
```bash
ps -o pid,stat,cmd -p <PID>
```
one time only, without waiting. What state is it in, and why might a
teammate wrongly conclude "the fix didn't work"?

See `SOLUTION.md` only after you've formed your own diagnosis.
