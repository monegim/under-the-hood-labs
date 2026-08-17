# Lab 27 — Solutions

## Challenge A — quantify exactly how misleading the "healthy" view is

**Check:** `docker stats` reports CPU% in the 20s-30s throughout the
loop — comfortably under the 50% quota, nothing a typical "alert if CPU
> 80%" rule would ever catch. Meanwhile `throttled_usec` climbs by
several seconds' worth of throttled time across the ~10-second loop —
verified directly: in testing, a single fixed burst alone (2 threads,
4M ops) accumulated around 175ms of throttled time out of roughly
160-330ms of real time for that one burst, meaning a substantial
fraction — often the majority — of each burst's wall-clock duration was
spent throttled, not computing.

**Diagnosis:** `docker stats`/`top`-style CPU% is fundamentally a
*utilization average over a sampling window* — typically ~1 second or
longer. Throttling happens at CFS's own period granularity (100ms by
default), which is finer than any human-facing monitoring tool
samples at. A container can be throttled for 40 of every 100ms
(spending well over a third of its time frozen) while its
utilization, averaged over a full second spanning several such
periods plus idle time, reads as a modest, unremarkable percentage.
The two numbers are measuring genuinely different things — one is
"how much CPU did you use, on average," the other is "how much time
were you *prevented* from using CPU when you needed it" — and only the
second one describes user-facing latency impact directly.

**Fix:** not applicable to this specific check — it's a diagnostic
exercise. The actionable takeaway is Step 4's real fix (raise the
quota) combined with changing what gets monitored.

**Lesson:** any CPU-utilization-based alert threshold, however
well-tuned, structurally cannot catch this failure mode — it needs a
`cpu.stat`/`nr_throttled`-based signal (most container orchestration
platforms expose this as a first-class metric, e.g. Kubernetes'
`container_cpu_cfs_throttled_periods_total`) monitored and alerted on
directly. If you've only ever set up CPU% alerts, this exact incident
can and will happen invisibly.

---

## Challenge B — sizing concurrency off the wrong number makes it worse

**Check:** the same 4,000,000 total operations, spread across `nproc`
threads (the host's full core count) instead of 2, took roughly
2.3x longer in wall-clock time and accumulated over an order of
magnitude more throttled time than the 2-thread version, verified
directly — in testing, 175ms of throttled time for the 2-thread run vs.
2.58 seconds for the same total work spread across 10 threads.

**Diagnosis:** `nproc` — and the equivalent syscalls/APIs most
languages' runtimes call under the hood (`sysconf(_SC_NPROCESSORS_ONLN)`
on Linux) — reports the number of CPUs visible to the *kernel*, which
for a container is the host's physical/virtual CPU count, not
whatever the container's own cgroup CPU quota happens to be. (Modern
kernels and some runtimes have gained partial cgroup-awareness for
this over the years, but it's inconsistent across languages, runtime
versions, and container platforms — never assume it without checking.)
Spreading a fixed amount of work across more threads than the quota
can actually run concurrently doesn't add capacity — the quota is
still 50ms of CPU time per 100ms period regardless of how many threads
are competing for it. What it *does* add is scheduling overhead
(context-switching between more competing threads) and, more
importantly, a higher chance that *any* of those threads needing CPU
in a given period exhausts the shared quota faster, since more
concurrent demand hits the same fixed ceiling sooner.

**Fix:** size thread/worker-pool concurrency off the actual cgroup
quota, not `nproc` — either by reading `/sys/fs/cgroup/cpu.max`
directly, or via a cgroup-aware runtime feature where one exists (the
JVM added this in JDK 10+ via `-XX:+UseContainerSupport`, on by
default since JDK 11, specifically because of this exact issue).

**Lesson:** this is a well-documented, historically very common
production issue for JVM-based applications specifically — older JVMs
(pre-JDK 10) always read the host's core count for default thread-pool
and garbage-collector-thread sizing, leading to containers requesting
far more concurrent threads than their actual CPU quota could ever
service, worsening exactly the throttling this lab demonstrates. The
general lesson extends to any language/runtime: never assume
"detected CPU count" and "CPU quota actually available to me" are the
same number inside a container.
