# Lab 15 — Solutions

## Challenge A — high load, but it's not steal and it's not really CPU either

**Check:**
The pasted `vmstat` output, read column by column:
```
 r  b   ...  us sy id wa st
12  3   ...  38 14  4 42  2
14  2   ...  41 16  3 38  2
11  4   ...  35 15  5 43  2
```
`st` is 2% — noise, not the story. `r` (processes runnable, waiting for a
CPU) is in double digits, which looks like CPU pressure at first glance.
But look at `wa` (time waiting on I/O) — 38-43%, and `b` (processes in
uninterruptible sleep, i.e. blocked on I/O) is nonzero every sample.

**Diagnosis:** this is an I/O bottleneck, not a CPU or hypervisor problem.
`wa` this high means the CPUs are frequently idle-but-blocked waiting for
disk (or network storage) to respond, not actually computing. The
elevated `r` count is a side effect: processes queue up waiting for their
turn once their I/O finally completes, which inflates the run-queue number
even though the root cause is storage latency, not CPU scarcity. `st` at
2% tells you the hypervisor isn't the problem here.

**Fix (next steps, since this is a read-the-log challenge, not a live
box):** run `iostat -x 1` and look at `%util`, `await`, and `r_await`/
`w_await` on the underlying block device to confirm and find which disk/
volume is the bottleneck; check for a single process hammering it with
`iotop`.

**Lesson:** don't read `r` (run queue) in isolation — always cross-check
`wa` and `b` before concluding "CPU-bound." A busy-looking run queue caused
by I/O waits needs a completely different fix (storage) than one caused by
actual compute demand (more/faster CPU) or steal (infra-level fix).

---

## Challenge B — averaging hides a single starved vCPU

**Check:**
The pasted `mpstat -P ALL` output:
```
all    ... %steal    9.80  ... %idle 82.30
  0    ... %steal    3.00  ... %idle 91.00
  4    ... %steal   68.40  ... %idle 22.70
```
The `all` row shows a mild 9.8% steal — easy to dismiss. But CPU 4 alone
is being robbed of 68.4% of its time, while every other core is fine
(3-4.8% steal).

**Diagnosis:** `mpstat -P ALL`'s `all` line is an arithmetic mean across
every vCPU. One severely-throttled core sitting next to seven healthy ones
gets diluted into a number that looks unremarkable system-wide. But if
your workload has anything single-threaded or pinned to a specific vCPU —
a MySQL thread doing critical work, a single-threaded app, an
interrupt-heavy NIC queue bound to one CPU — landing on that one starved
vCPU is enough to tank the whole thing's performance while every other
metric on the box looks calm. This is exactly why "system looks mostly
fine, but this one service is randomly slow" incidents happen on shared
infra: the average lies, the per-core view doesn't.

**Fix (infra layer, same principle as the main lab):** this points at
uneven scheduling of this VM's vCPUs on the host — get the host owner to
check what's contending for the physical core backing vCPU 4 specifically,
or request CPU pinning/dedicated cores so vCPU-to-pCPU mapping is stable
instead of migrating (which is often the exact cause of one vCPU being
unlucky).

**Lesson:** always check `mpstat -P ALL` per-core, not just the aggregate
row. A single hot/starved core can hide behind a healthy-looking average,
especially on systems with mixed single-threaded and multi-threaded
workloads.
