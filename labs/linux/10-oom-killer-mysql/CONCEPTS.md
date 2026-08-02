# Lab 10 — Concept: The OOM Killer, cgroup Memory Limits, and Why MySQL Logs Say Nothing

## What's actually going on

Linux over-commits memory by design — `malloc()`/`mmap()` handing back an
address range doesn't mean physical pages are allocated yet; pages get
backed on first touch. This lets the system support many processes each
reserving more virtual memory than actually exists, on the assumption most
of it won't all be touched at once. The tradeoff is that when memory
genuinely does run out — every process touching everything it asked for,
with nothing left to reclaim — the kernel cannot simply fail the
allocation the way it fails a file open; by the time the shortage is real,
some allocation deep inside some process's code path *must* succeed or the
kernel itself risks deadlocking. The **OOM killer** is the kernel's
last-resort answer: pick a process, using a scoring heuristic weighted
mostly by resident memory size (`oom_score`, adjustable per-process via
`oom_score_adj`), and kill it outright with `SIGKILL` to free its pages
immediately. This is why `mysqld` — with a large `innodb_buffer_pool_size`
making it the fattest process in the cgroup — is almost always the
selected victim in a memory-pressure incident, even when it isn't the
process that caused the pressure.

This lab specifically triggers a **cgroup-scoped** OOM kill, not a
whole-system one, and that distinction matters for where you look next.
`systemd`'s `MemoryMax=` on a slice/unit translates directly to
`memory.max` in that cgroup's **cgroup v2** memory controller. When the
total charged memory of every process in that cgroup exceeds
`memory.max`, the kernel invokes the OOM killer scoped to *that cgroup
only* — it picks a victim from among the slice's own processes,
independent of whether the rest of the system has plenty of free memory.
This is exactly why the dmesg line reads `Memory cgroup out of memory:
Killed process ... (mysqld)` rather than a generic system-wide OOM
message, and why moving `mysql.service` into a slice with a hard
`MemoryMax` creates a failure mode that's invisible to anyone just
watching overall host memory usage.

The reason MySQL's own error log says nothing useful is structural, not a
logging bug: `SIGKILL` cannot be caught, blocked, or handled by the
receiving process — it's delivered and acted on essentially immediately,
with the kernel tearing the process down before it gets a chance to run
any signal handler, flush a log, or write a clean shutdown message.
`systemctl status` only knows that the process exited and (depending on
the unit's `Restart=` policy) that it restarted — it has no visibility
into *why* the kernel decided to kill it. The only place that fact is
actually recorded is the kernel's own log, via `dmesg`/`journalctl -k`,
because the kernel is the actor that made the decision.

`innodb_buffer_pool_size` matters here specifically because it's normally
the single largest, most deliberately-sized memory consumer in a MySQL
process — but it is not mysqld's *only* memory consumer. Per-connection
buffers, thread stacks, temp tables, and the InnoDB log buffer all sit on
top of it, which is why the realistic rule of thumb (confirmed by
Challenge A) is real RSS around buffer-pool-size-plus-15-to-25%-overhead,
not the buffer pool figure taken at face value. Sizing exactly to a memory
ceiling with no margin, as this lab deliberately does, leaves no room for
that overhead or for any sibling process, and Challenge B shows the
compounding failure mode: `Restart=on-failure` (the Ubuntu mysql unit's
default) brings mysqld right back up after every kill, it reallocates the
same oversized buffer pool, and gets killed again — a repeating loop that,
from the outside, looks like intermittent flakiness rather than an obvious
resource problem unless you specifically count kill events over a time
window instead of trusting current process status.

## Where this shows up in the real world

"MySQL just died, error log says nothing, connections started refusing" is
one of the most common DBRE pages there is, and the cause is almost never
MySQL itself deciding to exit — it's the kernel (or, increasingly, a
cgroup limit imposed by a container orchestrator or systemd slice)
reclaiming memory from the fattest process on the box. This is exactly the
mechanism behind Kubernetes pods hitting their memory limit and getting
OOM-killed, and behind bare-metal database hosts where a batch job,
backup process, or misconfigured cache silently steals headroom from a
tightly-sized buffer pool. Engineers who know to check `dmesg`/`journalctl
-k` first — before staring at an application log that structurally cannot
contain the answer — find this in minutes; engineers who don't can burn
hours re-reading MySQL logs that will never say "I was killed."

## Go deeper

- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors — covers capacity planning and memory sizing tradeoffs for production database hosts directly relevant to this lab.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — the standard reference for sizing `innodb_buffer_pool_size` and understanding MySQL's real memory footprint.
- **Website/docs:** Linux kernel docs — https://docs.kernel.org — the cgroup v2 memory controller documentation covers `memory.max` and OOM-kill scoping in detail.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/proc.5.html — see also `cgroups(7)` for the OOM-killer and memory-accounting model this lab exercises.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — regularly covers MySQL OOM incidents and buffer-pool-sizing guidance in production contexts.
