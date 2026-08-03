# Lab 5 — Concept: Proving a Slowdown Is Actually Disk I/O

## What's actually going on

A disk (or, in a VM, the block device backing a filesystem) can only
service so many I/O operations concurrently before requests start
queueing. `iostat -x` exposes exactly this queueing behavior per block
device: `%util` is the percentage of time the device had at least one
request outstanding (effectively "how busy is it"), and `await` (split
into `r_await`/`w_await` on newer `iostat`) is the average time, in
milliseconds, a request spent from submission to completion — including
time spent waiting in the queue behind other requests, not just the
physical I/O itself. When a previously-fast service suddenly shows high
write latency, `await` climbing alongside `%util` near 100% on the
relevant device is close to definitive proof that requests are queueing
behind something else, not that the service's own code got slower.
`vmstat`'s columns tell the complementary story at the whole-system
level: `us`/`sy` are actual CPU time (user/system), while `wa` is time
the CPU spent idle specifically because a process was blocked waiting on
I/O to complete. A service that's slow with `wa` elevated and `us`/`sy`
low is waiting on disk, not burning CPU cycles — checking both together
is what turns "the service feels slow" into an actual, resource-specific
diagnosis instead of a guess.

`ionice` is the tool for actually doing something about I/O contention
once you've proven it's real: it sets a process's I/O scheduling class
(realtime, best-effort with priority 0–7, or idle) so the kernel's I/O
scheduler can prefer some processes' requests over others when the
device is under contention. The critical, easy-to-miss caveat is that
`ionice` classes are meaningless to a scheduler that doesn't implement
them — historically `cfq`, and on modern kernels `bfq`, are the
schedulers that actually honor I/O priority; the commonly-default
`mq-deadline` and `none` schedulers used on many modern block devices
(this is especially common for NVMe and virtualized/loop block devices)
process requests without any concept of per-process priority at all.
`ionice -c 3 -p <pid>` will run successfully and report no error in
either case — the command doesn't fail, the scheduler simply ignores the
hint — which is exactly why checking `/sys/block/<dev>/queue/scheduler`
before concluding `ionice` "isn't working" is a real, non-obvious step
worth building as a reflex.

Diagnosing "slow" always has to stay open to more than one candidate
resource, which is the entire point of pairing a disk-contention scenario
(this lab's main incident) with a CPU-contention one (Challenge B) using
the identical victim service and the identical symptom ("writes are
slow"). The correct methodology — check utilization and saturation across
each candidate resource (disk, CPU, memory, network) rather than assuming
the resource that was guilty last time is guilty again — is the core idea
behind Brendan Gregg's USE method (Utilization, Saturation, Errors): work
the actual evidence per resource, don't pattern-match to the most recent
incident.

## Where this shows up in the real world

Any shared-disk environment — a multi-tenant VM host, a database sharing
storage with a batch/backup job, a container host where one noisy
neighbor runs a disk-heavy build — produces exactly this symptom: an
application whose code hasn't changed suddenly showing elevated latency,
purely from queueing behind someone else's I/O. `iostat -x`'s `await`/
`%util` pairing is the standard first check any experienced SRE reaches
for the moment "slow" is reported and CPU/memory both look fine.
`ionice`'s scheduler dependency is a real, recurring gotcha in cloud
environments specifically, since many cloud block storage backends and
virtualized disks default to `none`/`mq-deadline`, meaning a
well-intentioned `ionice -c 3` on a backup or batch job may do nothing at
all unless someone deliberately checked and switched the scheduler — or,
in fully virtualized/cloud-storage scenarios, `ionice` may not be able to
help at all, because the actual contention is happening on shared
storage a layer below where the guest's I/O scheduler has any influence.

## Go deeper

- **Book:** *Systems Performance* — Brendan Gregg — the definitive
  reference for `iostat`, the USE method, and disk I/O latency analysis
  generally; directly applicable to this entire lab.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man1/iostat.1.html
  and `ionice(1)` — canonical reference for `iostat -x` column meanings
  and `ionice` class semantics.
- **Website/docs:** Linux kernel docs — https://docs.kernel.org/filesystems/
  (see the block layer / I/O scheduler documentation) — background on
  `mq-deadline`, `bfq`, and `none` scheduler behavior.
- **Website/docs:** Brendan Gregg's site — https://www.brendangregg.com —
  USE method reference pages and Linux performance checklists.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  covers Linux performance monitoring tools including `iostat`/`vmstat`.

**Confidence flag:** whether `bfq` is available/selectable at all for a
given loop device (`/sys/block/<dev>/queue/scheduler` on some kernel
builds may not list it if the `bfq-iosched` module isn't loaded), and
the exact degree `ionice` improves latency once `bfq` is active on a
loop-backed device specifically, have not been verified live — dry-run
this lab and be ready to note in-recording if `bfq` isn't selectable on
the test VM's kernel.
