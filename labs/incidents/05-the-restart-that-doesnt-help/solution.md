# Incident 05 — Solution

## Root cause

`upload-worker.py` is mid-copy of a large file onto `/mnt/uploads`, a
`hard`-mounted NFS filesystem, when the NFS path gets cut (simulated
here with `iptables` dropping port 2049 in both directions - standing in
for a flaky storage backend, a network partition, or an overloaded NFS
server in production). Its in-flight `write()`/`fsync()` syscall is now
blocked inside the kernel waiting for an NFS reply that will never come,
which puts the process into uninterruptible sleep (`D` state, visible in
`ps`'s `STAT` column).

A process in `D` state cannot be killed by any signal, including
`SIGKILL` - the kernel won't schedule delivery of a pending signal until
the blocking syscall returns, and that syscall won't return until the
NFS request either gets a reply or the mount's own retry/timeout logic
gives up (which, on a `hard` mount, it's specifically configured *not*
to do - `hard` means "keep retrying forever," which is the right choice
for data-integrity reasons, and exactly what makes this incident
possible). `systemctl restart` has no special power here: its stop step
sends `SIGTERM`, waits, then `SIGKILL` - both are just signals, and
neither can touch a task the kernel refuses to schedule for signal
delivery. That's why the restart hangs or times out instead of quickly
cycling the service, and why doing it twice made no difference: the
underlying process was never in a state where a signal could reach it.

## Why it happened

Nothing in `upload-worker.py` is buggy - `open()`/`write()`/`fsync()`
against a mounted filesystem is about as ordinary as application code
gets. The NFS mount was deliberately configured `hard` (the correct
choice for anything writing real user data - a `soft` mount can silently
truncate or corrupt an in-flight write on timeout instead of just
hanging). That correctness is exactly what makes the hang total rather
than a quick, safe failure: `hard` trades "never silently corrupts data"
for "will hang indefinitely rather than give up," and an outage on the
storage backend cashes in that trade as a stuck process.

## Why the obvious fixes don't work

- **`systemctl restart upload-worker.service`** (already tried, twice,
  per the page): can't kill the blocked process - see above. Each
  attempt likely just adds noise: if the stop step times out, systemd
  may consider the old instance gone and start a *new* one, while the
  original process is still alive in the background, still blocked,
  still holding the NFS mount open. Check for more than one:
  ```bash
  ps -eo pid,ppid,stat,wchan:32,cmd | grep '[u]pload-worker.py'
  ```
  If you see more than one entry, especially more than one in `D`
  state, that's the fallout from the earlier restart attempts, not a
  new problem - deal with the mount, not with picking a PID to kill.
- **`kill -9 <pid>`**: the signal is accepted and queued by the kernel,
  but cannot be delivered while the task is in `TASK_UNINTERRUPTIBLE`.
  `ps` will still show the process afterward - it isn't ignoring the
  signal, it's not being scheduled to check for one.
- **Rebooting the VM**: works, eventually, but is a heavy hammer for a
  problem that has a much more targeted fix (see below), and doesn't
  address the actual cause (the storage path being unreachable) any
  faster than just fixing that path directly.

## The investigation

Confirm the process is actually stuck, not just slow:
```bash
systemctl status upload-worker.service --no-pager
ps -eo pid,ppid,stat,wchan:32,cmd | grep '[u]pload-worker.py'
```
`STAT` shows `D` (or `D+`). `WCHAN` shows the kernel function it's
blocked in - something NFS-related (e.g. an RPC-wait function).

Confirm a signal genuinely can't touch it:
```bash
sudo kill -9 <PID>
ps -o pid,stat,cmd -p <PID>
```
The process is still there.

Confirm the mount itself is the actual problem, not the process:
```bash
cat /proc/mounts | grep uploads
mountpoint -q /mnt/uploads && echo "still mounted"
```
The mount is still nominally present but effectively dead - anything
touching it blocks.

Find what's actually cutting the path:
```bash
sudo iptables -L OUTPUT -v -n | grep 2049
sudo iptables -L INPUT -v -n | grep 2049
```
DROP rules on port 2049 (NFS), with climbing packet counters every time
something tries to use the mount.

## The fix

Fix the actual cause - restore the NFS path:
```bash
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -D INPUT -p tcp --sport 2049 -j DROP
```
Give it a few seconds - removing the block doesn't instantly complete
the in-flight write, it just lets the retransmitted NFS request finally
get a response. The kernel still has to get the reply, finish the
syscall, *then* notice the already-queued `SIGKILL` (if one was sent)
and act on it. Don't panic and reboot the box just because the process
is still visible a few seconds after the fix - that's expected, not a
sign the fix didn't work:
```bash
sleep 5
ps -eo pid,stat,cmd | grep '[u]pload-worker.py'
```
Once every stuck process has actually exited, systemd's `Restart=always`
brings a clean instance up on its own, and the pending upload queue
starts draining.

## How to prevent it

- Alert on the actual business symptom (queue depth / age of oldest
  pending item) *and* on `D`-state process count on hosts that mount
  network storage - the second one turns "restart didn't help" from a
  confusing surprise into an expected, recognized pattern.
- Consider mount options with bounded timeouts (`timeo=`, `retrans=`) or
  a supervised health-check that pages on "mount unresponsive" directly,
  rather than only detecting it once a worker process hangs.
- Document, on the runbook for anything mounting NFS/network storage,
  that a stuck writer is fixed by restoring the storage path, not by
  restarting the service - so the second on-call doesn't burn another
  cycle on a third restart attempt.

## Real-world examples of this pattern

- Any NFS, SMB, or SAN-backed mount that becomes unreachable while a
  process has an in-flight write - one of the most common causes of
  "the service won't die" tickets in real infrastructure, and a frequent
  source of confused escalations precisely because `kill -9`, the
  universal "make it stop" tool, visibly does nothing.
- Kubernetes pods stuck in `Terminating` for exactly this reason - a
  container process blocked in `D` state on a hung volume mount (NFS,
  CSI driver issue, cloud block storage API being slow) can keep a pod
  from finishing termination no matter how many times it's deleted or
  how aggressively `kubectl delete --force` is used at the API level;
  the kernel-level block is unaffected by API-level deletion.
- Database or storage appliances that hang during a failover: client
  processes with in-flight I/O against the old primary can sit in `D`
  state until the client's own I/O timeout/retry logic gives up (if any
  exists) or the storage path is restored, regardless of how the
  application layer is restarted.
