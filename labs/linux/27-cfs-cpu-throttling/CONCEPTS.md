# Lab 27 — Concept: CFS Bandwidth Control and Throttling

## What's actually going on

The Completely Fair Scheduler (CFS) is Linux's default process
scheduler, and CFS *bandwidth control* is the specific mechanism that
lets a cgroup be given a CPU limit expressed as a ratio rather than a
fixed core count — `cpu.max` (cgroup v2; `cpu.cfs_quota_us`/
`cpu.cfs_period_us` in v1) stores exactly two numbers: a *period*
(how often the quota resets, 100ms by default) and a *quota* (how many
microseconds of CPU time the cgroup is allowed to consume within each
period, summed across however many threads are running concurrently).
`docker run --cpus=0.5` translates directly to a period of 100000µs and
a quota of 50000µs — 50% of one core's time, per 100ms window. The
kernel enforces this by tracking how much quota a cgroup has consumed
within the current period and, the instant it's exhausted, marking
every runnable task in that cgroup as throttled — genuinely unable to
be scheduled at all — until the next period begins and the quota
resets.

This period-based enforcement is what makes throttling invisible to
utilization-based monitoring. `docker stats`, `top`, and virtually
every dashboard's "CPU usage" metric report *utilization* — CPU time
consumed divided by wall-clock time elapsed, averaged over some
sampling window that's almost always coarser than CFS's own 100ms
period. A cgroup that uses its entire quota in the first 50ms of every
100ms period, then sits idle for the rest, is throttled for roughly
half of all elapsed time — but a utilization sample taken once a
second (or even once every 100ms, if you're unusually thorough) sees
"used some CPU, then was idle" and reports a moderate, unremarkable
percentage, because idle-due-to-throttling and idle-because-there-was-
nothing-to-do are indistinguishable from a pure utilization
measurement. Only `cpu.stat`'s `nr_throttled` (count of periods where
this cgroup hit its limit) and `throttled_usec` (cumulative time spent
throttled) actually distinguish the two.

The number of threads contending for a fixed quota matters because
quota is consumed in aggregate across every thread in the cgroup, not
per-thread — a quota good for "1 thread running flat-out" gets
exhausted proportionally faster if 10 threads are all trying to run
concurrently within the same period, even though the *total* amount of
useful work getting done isn't any higher (there's still only 50ms of
real CPU time available per 100ms, split however many ways). This is
exactly why sizing concurrency off `nproc` (which reports the host's
CPU count, since the kernel's CPU topology isn't namespaced by cgroups
the way PIDs or network interfaces are) rather than the actual quota
makes throttling measurably worse: more threads competing for the
identical fixed budget, not more budget.

## Where this shows up in the real world

This is one of the most frequently rediscovered performance issues in
Kubernetes specifically, to the point of having its own well-known
name in the community ("CPU throttling," often discovered via
`container_cpu_cfs_throttled_periods_total` in Prometheus/Grafana
dashboards after someone notices p99 latency spikes that don't
correlate with any CPU utilization graph). It's especially common
right after a service gets containerized for the first time and its
CPU limit gets set to "whatever felt reasonable" without load-testing
bursty traffic patterns against it, or after a language runtime
upgrade quietly starts sizing its own internal thread/GC pools off
`nproc` in a way it didn't before. The general lesson — utilization
metrics and throttling metrics answer different questions, and only
one of them explains user-facing latency directly — applies to any
cgroup-limited environment, not just Kubernetes: plain Docker, systemd
resource-controlled services, and any other CFS-bandwidth-controlled
workload all share this exact mechanism.

## Go deeper

- **Website/docs:** Linux kernel documentation, CFS Bandwidth Control — https://docs.kernel.org/scheduler/sched-bwc.html — the authoritative reference for `cpu.max`/`cpu.cfs_quota_us`/`cpu.cfs_period_us` and the throttling mechanism itself.
- **Website/docs:** `cgroups(7)` man page — https://man7.org/linux/man-pages/man7/cgroups.7.html — general cgroup v1/v2 background, including the `cpu` controller.
- **Blog:** Dan Luu, "CPU utilization is a broken metric" — https://danluu.com/cgroup-throttling/ — a widely-cited, deeply technical breakdown of exactly this CFS throttling-vs-utilization gap, from firsthand production debugging.
- **Blog:** Indeed Engineering, "Unthrottled: Fixing CPU Limits in the Cloud" — a well-known writeup (search title; specific URL has moved over time) of production-scale CFS throttling debugging and the case for switching some workloads off hard CPU limits entirely.
- **Book:** *Systems Performance* — Brendan Gregg (2nd edition, Addison-Wesley) — covers CPU scheduling and cgroup resource controls as part of its broader Linux performance methodology, directly relevant background for reasoning about this class of issue systematically.
