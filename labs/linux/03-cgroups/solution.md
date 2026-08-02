# Lab 3 — Solutions

## Challenge A — you limited more than you meant to

**Check:**
```bash
cat /sys/fs/cgroup/lab3b/cgroup.procs
cat /sys/fs/cgroup/lab3b/memory.current
cat /sys/fs/cgroup/lab3b/memory.events
```
Your interactive shell disconnects, hangs, or gets killed (you may see your
terminal drop, or `dmesg` shows your shell or a tool it spawned getting
OOM-killed) when you run something as ordinary as `apt list --installed`.

**Diagnosis:** you added your CURRENT interactive shell's PID to
`cgroup.procs`, not just the workload you intended to constrain. In cgroup
v2, `memory.max` applies to the TOTAL memory used by every process in the
cgroup combined — your shell, and everything it forks from that point on.
10 MiB is not enough headroom for a shell plus a moderately memory-hungry
command like `apt list`, so the combined usage crosses the limit and the
kernel's cgroup-aware OOM killer picks a victim from inside the cgroup —
which can be the new command, or your shell itself, depending on which
process looks like the better reclaim target.

**Fix:** don't put your interactive/management shell into the same cgroup
as the workload you want to limit. Launch the workload directly into the
cgroup instead (e.g. start it and immediately write its own PID to
`cgroup.procs`), or use a wrapper like `systemd-run --scope` /
`cgexec`-style tooling that puts only the target process's PID in the
cgroup, not your whole shell session.

**Lesson:** a cgroup limit applies to the aggregate of everything living
inside it — adding your own shell as a "convenience" to avoid typing a PID
means every future command you type from that shell shares the same
budget, including your own tooling.

---

## Challenge B — throttled despite "plenty" of quota

**Check:**
```bash
cat /sys/fs/cgroup/lab3c/cpu.stat
```
`nr_throttled` and `throttled_usec` climb quickly, even though "50000
100000" reads like "half a CPU is available" and the box may have several
idle cores.

**Diagnosis:** `cpu.max`'s quota is a hard ceiling on total CPU TIME
consumed by ALL threads/processes in the cgroup, summed together, per
100ms period — not a per-thread allowance. Four `stress-ng` workers each
trying to run flat-out on separate cores instantly exhaust a 50ms-per-100ms
combined budget within the first few milliseconds of the period, then get
throttled for the rest of it — regardless of how many idle CPUs the
machine has elsewhere. This is the exact mechanism behind one of the most
common real Kubernetes production surprises: a multi-threaded (or
multi-process) container gets throttled hard even though its AVERAGE CPU
usage looks well under its limit, because usage is bursty within each
100ms accounting window, and the quota is shared across every thread the
process spins up.

**Fix:** either raise the quota to account for actual concurrency
(`cpu.max` quota roughly proportional to `threads x expected per-thread
usage`), or reduce the process's own parallelism (e.g. cap
`GOMAXPROCS`/worker pool size) so it doesn't try to burst across more
threads than the quota can sustain in one period.

**Lesson:** a CPU quota is a shared budget across every thread in the
cgroup per accounting period, not a per-thread cap — "50% of a CPU" can
throttle a multi-threaded workload far more aggressively than the number
suggests once you have more runnable threads than the quota supports
concurrently.
