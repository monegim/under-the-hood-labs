# Lab 26 — Concept: Transparent Huge Pages

## What's actually going on

The kernel maps virtual memory to physical memory in fixed-size pages —
4KB by default on most architectures — and every memory access has to
be translated from virtual to physical through the CPU's Translation
Lookaside Buffer (TLB), a small, fast, limited-size cache of recent
translations. A process with a large memory footprint touches far more
4KB pages than the TLB can hold entries for, causing frequent TLB
misses, each of which costs a real (if small) stall while the CPU walks
page tables in memory to resolve the translation. A 2MB huge page
covers the same address range as 512 individual 4KB pages using a
*single* TLB entry — dramatically reducing TLB pressure for
large-footprint workloads, which is the entire reason Transparent Huge
Pages exist as a Linux feature at all.

"Transparent" specifically means the kernel manages this without an
application needing to use special APIs to request huge memory
regions explicitly (as hugetlbfs, the older, non-transparent mechanism,
requires) — ordinary `malloc`/`mmap`-allocated memory can be
transparently backed by huge pages if the kernel decides it's eligible.
`transparent_hugepage/enabled` controls when the kernel makes that
decision: `always` applies it to every eligible allocation, `never`
disables it universally, and `madvise` — the middle ground most modern
distros default to — only applies it to memory a process has explicitly
tagged with `madvise(MADV_HUGEPAGE)`, leaving everything else as
ordinary 4KB pages.

The catch is that assembling a 2MB huge page requires 512 *physically
contiguous* 4KB pages, and physical memory fragments over time as a
system runs — allocations and frees of different sizes leave scattered
free 4KB gaps rather than tidy 2MB blocks. When a huge-page allocation
can't be satisfied immediately from already-contiguous free memory, the
kernel either falls back to ordinary 4KB pages for that allocation, or
triggers memory compaction — actively relocating pages in physical
memory to create contiguous space — which is real CPU and I/O-adjacent
work happening synchronously in some paths and via the `khugepaged`
background kernel thread in others. Under `always` mode specifically,
this compaction work gets triggered for allocations the requesting
process never asked for and may not benefit from at all, which is
exactly the unpredictable-latency mechanism that leads latency-sensitive
software to recommend disabling it.

## Where this shows up in the real world

Redis's own documentation and startup warnings explicitly flag THP as a
latency risk and recommend `madvise` or `never`; MongoDB's production
notes do the same. This is one of the most commonly cargo-culted "just
disable THP" pieces of database tuning advice repeated in production
runbooks — often applied as `never` everywhere by default without
anyone checking whether `madvise` (available on any reasonably modern
kernel) would have solved the actual problem without giving up THP's
real benefit for anything else running on the same host. The
system-wide vs. per-process distinction in this lab's two challenges
matters in practice for exactly this reason: diagnosing "is THP
actually the cause of the latency I'm seeing" on a shared host requires
being able to attribute huge-page usage to the *specific* process
under investigation, not just confirming THP activity is happening
somewhere.

## Go deeper

- **Website/docs:** Linux kernel documentation, Transparent Hugepage Support — https://www.kernel.org/doc/html/latest/admin-guide/mm/transhuge.html — the authoritative reference for every THP sysfs knob, including `enabled`, `defrag`, and the `khugepaged/*` tuning parameters.
- **Website/docs:** Redis documentation, Latency due to Transparent Huge Pages — https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency/ — a real vendor's operational guidance on exactly this issue, from the application side.
- **Website/docs:** `proc(5)` man page — https://man7.org/linux/man-pages/man5/proc.5.html — documents `/proc/vmstat`'s `thp_*` counters and the per-process `smaps`/`smaps_rollup` fields used throughout this lab.
- **Blog:** Brendan Gregg, "THP (Transparent Huge Pages)" performance notes — https://www.brendangregg.com/blog/ — Gregg's broader body of Linux performance work provides deep context for how memory-subsystem tuning decisions like this one fit into systems performance work generally.
- **Book:** *Systems Performance* — Brendan Gregg (2nd edition, Addison-Wesley) — the standard reference for Linux performance methodology, including memory subsystem analysis and when kernel-level tuning like THP mode is (and isn't) the right lever.
