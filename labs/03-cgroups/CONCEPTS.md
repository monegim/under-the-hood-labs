# Lab 3 — Concept: cgroups (v2)

## What's actually going on

Namespaces (Labs 1-2) control what a process can *see*; cgroups control what
it's *allowed to consume*, and the two mechanisms are entirely independent —
a process can be in a totally isolated set of namespaces with no resource
limits at all, or resource-limited with zero namespace isolation. cgroup v2
represents this as a single unified tree of directories under
`/sys/fs/cgroup`, where each directory is a cgroup and each cgroup carries a
`cgroup.procs` file (real, host PIDs that are members) plus one virtual file
per active controller (`memory.max`, `cpu.max`, `pids.max`, ...). Nothing
here is a syscall you call directly the way `clone()`/`unshare()` are for
namespaces — it's entirely a filesystem interface: writing a number into
`memory.max` and reading `memory.current` back out are ordinary `write()`/
`read()` calls against a kernfs-backed pseudo-filesystem, which is exactly
why `docker run --memory=100m` and `kubectl` resource limits ultimately
bottom out in the container runtime doing the same `tee`-into-a-file dance
this lab does by hand.

The delegation model from Step 1 (`cgroup.subtree_control`) is the part that
trips almost everyone up the first time, and it's deliberate, not
accidental complexity. In cgroup v2 there's a hard rule called "no internal
processes" — with rare exceptions, a cgroup either contains processes or has
children with active controllers, not both in a way that would create
ambiguity about which layer's limit applies to a given process. To make that
consistent, enabling a controller for a cgroup's *children* is an act you
perform on the *parent* (`echo +memory +cpu +pids > .../cgroup.subtree_control`),
not the child — the parent has to explicitly opt in to delegating each
controller downward before any child directory even gets a `memory.max` file
to write to. This is why a brand-new `mkdir`'d cgroup starts nearly empty:
the kernel doesn't populate controller interface files until the ancestry
above it has delegated that controller, top-down, one level at a time.

The memory controller enforces `memory.max` via page accounting baked into
the kernel's memory management — every page charged to a process is charged
to its cgroup's page counter (this is the same infrastructure, `struct
mem_cgroup`, that's been part of the kernel's core page-reclaim path for
over a decade). When a cgroup's usage would cross `memory.max`, the kernel
first tries reclaim scoped to that cgroup, and if that's not enough, invokes
a cgroup-scoped OOM killer that only considers picking a victim from
*within that cgroup* — this is a structurally different code path from the
system-wide OOM killer that fires when the whole machine is out of memory,
which is why `dmesg` shows "Memory cgroup out of memory" rather than the
generic OOM message, and why one memory-hungry container getting killed
doesn't take down unrelated processes elsewhere on the box. `memory.events`'
`oom_kill` counter is a direct readout of this cgroup-scoped killer having
fired.

The CPU controller works completely differently, and this difference is
exactly what Challenge B is built to expose. `cpu.max`'s "$MAX $PERIOD" is
the kernel's CFS (Completely Fair Scheduler) bandwidth controller: every
`$PERIOD` microseconds, the cgroup as a *whole* is allocated `$MAX`
microseconds of CPU time, tracked as one shared runtime budget refilled once
per period and drawn down by every runnable thread/process in the cgroup
combined. It is not "each thread gets up to $MAX" — it's "the sum of all
threads' CPU time this period is capped at $MAX," enforced by the scheduler
literally taking runnable-but-out-of-budget tasks off the CPU (throttling
them) until the next period refills the bucket. Four `stress-ng` workers
burning flat-out on separate cores can chew through a "50% of one CPU"
budget in a couple of milliseconds and then sit throttled for the rest of
each 100ms window — which looks alarming on a dashboard ("`nr_throttled`
climbing, average CPU usage looks fine") but is exactly correct behavior
given how the budget is defined. This single mechanism is the most
frequently misdiagnosed metric in real Kubernetes clusters
(`container_cpu_cfs_throttled_seconds_total`).

## Where this shows up in the real world

`docker run --memory=100m --cpus=0.5` and a Kubernetes pod's
`resources.limits.memory` / `resources.limits.cpu` are translated by the
container runtime (containerd, CRI-O) into exactly the file writes this lab
does by hand — there is no separate enforcement mechanism, cgroups v2 *is*
the mechanism. When a pod shows `OOMKilled` in `kubectl describe pod`, the
fast diagnosis path is `memory.events`' `oom_kill` counter and
`memory.current` at the moment of death, not guessing at application-level
memory leaks first. When a multi-threaded service (a Go binary with a high
`GOMAXPROCS`, a JVM with a large thread pool, an nginx worker set) shows
latency spikes that don't correlate with the average CPU graph, the fast
diagnosis is checking `cpu.stat`'s `throttled_usec` against the container's
CPU limit and thread count — average utilization looking "fine" is
compatible with severe per-period throttling, and engineers who don't know
the shared-budget-per-period model waste hours chasing application code
instead of adjusting the CPU limit or the process's own concurrency.

## Go deeper

- **Website/docs:** Linux kernel cgroup v2 docs — https://docs.kernel.org/admin-guide/cgroup-v2.html — the official, authoritative reference for `subtree_control`, `memory.max`, `cpu.max`, and every semantics question this lab touches.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/cgroups.7.html — Michael Kerrisk's `cgroups(7)` overview, good complement to the kernel docs for the general model.
- **Book:** *Systems Performance* (2nd edition) — Brendan Gregg — covers cgroups, the CFS bandwidth controller, and how to read `cpu.stat`/`memory.events` from a production performance-debugging angle.
- **Website/blog:** Brendan Gregg's site — https://www.brendangregg.com — has material specifically on CPU throttling misdiagnosis in containerized environments, the exact Challenge B scenario.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — search the channel for Kubernetes CPU throttling / resource limits deep dives; hands-on demonstrations of this exact `cpu.max` behavior.
