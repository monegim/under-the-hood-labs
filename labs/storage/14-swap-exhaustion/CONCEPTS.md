# Lab 14 — Concept: Swap Space, Reclaim, and cgroup Memory Limits

## What's actually going on

Swap exists so the kernel has somewhere to put memory pages that aren't
being actively used right now, freeing up physical RAM for something
that needs it more urgently. When a process (or, as in this lab, a
cgroup with a `memory.max` limit) needs more memory than is currently
available, the kernel's page reclaim logic looks for pages it can evict:
clean file-backed pages (page cache) can just be dropped, since they're
still on disk and can be re-read later at the cost of an I/O; anonymous
pages (heap, stack, `bytearray` allocations — memory with no backing
file) can't simply be dropped, since dropping them would lose data that
exists nowhere else — the only way to free RAM occupied by an anonymous
page without losing its contents is to write it out to swap first. This
is why a workload that's almost entirely anonymous memory (like this
lab's hog) drives swap usage specifically, rather than being satisfied
by dropping cache.

`memory.max` on a cgroup v2 controller is a hard ceiling on that
cgroup's memory usage — once a cgroup hits it, the kernel forces reclaim
*within that cgroup* to make room for further allocations, using
whatever's reclaimable (cache first, by swappiness preference, then
anonymous-via-swap). If swap itself also runs out while the cgroup is
still over its limit and there's nothing left to reclaim, the
cgroup-scoped OOM killer activates — this is a deliberately narrower,
faster-acting mechanism than the system-wide OOM killer: it only needs
to consider processes inside the one cgroup that's actually over
budget, rather than scoring every process on the whole machine.

`vm.swappiness` (a value from 0-200, though 0-100 is the traditional
range) is a tunable that biases the *relative preference* between those
two reclaim strategies — higher values lean toward swapping anonymous
memory more readily even when cache eviction would also be possible;
lower values lean toward exhausting cache first. It's a dial on a
choice, not a switch that disables one of the options — when the choice
effectively doesn't exist (little or no reclaimable cache present,
which is exactly the situation in this lab's cgroup, dominated by
freshly-allocated anonymous memory with no cache to fall back to),
swappiness has nothing left to influence, and swapping proceeds exactly
as it would at any other setting.

## Where this shows up in the real world

"Memory looks fine, but the app was OOM-killed" is a genuinely common
and genuinely confusing production symptom, and swap exhaustion inside
a resource-limited cgroup (the exact mechanism containers and
Kubernetes pods with memory limits use) is one of the more common
underlying causes — `free -h` on the *host* can look completely healthy
while one specific cgroup is pinned against its own limit with its
share of swap fully consumed. It's also a common source of confused
tuning advice: teams adjusting `vm.swappiness` expecting it to solve an
OOM problem, when the actual fix needed is more swap, a higher memory
limit, or less memory demand — swappiness tuning addresses reclaim
*efficiency and cache behavior*, not capacity.

## Go deeper

- **Book:** *Systems Performance* — Brendan Gregg — direct coverage of memory reclaim, swap, and the USE method applied to memory subsystems.
- **Website/docs:** Linux kernel cgroup v2 documentation — https://docs.kernel.org/admin-guide/cgroup-v2.html — authoritative reference for `memory.max`, `memory.swap.max`, and cgroup-scoped OOM behavior.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/proc.5.html — `/proc/meminfo` and `/proc/swaps` field reference.
- **Website/docs:** Linux kernel documentation on `vm.swappiness` — https://docs.kernel.org/admin-guide/sysctl/vm.html#swappiness — official description of what the sysctl actually influences.
- **YouTube:** Brendan Gregg's conference talks, linked from his own site's talks page — https://www.brendangregg.com/overview.html — rather than a single channel URL.
