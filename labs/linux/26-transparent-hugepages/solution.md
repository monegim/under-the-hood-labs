# Lab 26 — Solutions

## Challenge A — "never" is a harder override than it looks

**Check:**
```bash
grep thp_fault_alloc /proc/vmstat
```
Under `madvise`, running `touch_madvise` increases the counter — its
explicit request is honored. Under `never`, the exact same program,
making the exact same `madvise(MADV_HUGEPAGE)` call, produces no
increase at all — and the `madvise()` syscall itself still reports
success, with nothing in the program's own output indicating its
request was ignored.

**Diagnosis:** `madvise` mode makes THP an opt-in decision per-process
— the kernel only allocates huge pages for memory regions a process has
specifically marked with `MADV_HUGEPAGE`, leaving everything else
alone. `never` is a global kill switch sitting above that entire
mechanism: no memory on the system gets backed by transparent huge
pages, full stop, regardless of what any individual process asks for.
`madvise(MADV_HUGEPAGE)` is a *hint*, and the kernel is always free to
decline it — `never` mode is simply configured to always decline every
hint, system-wide, with no per-call error since declining a hint isn't
a failure from the syscall's point of view.

**Fix:** there's nothing to "fix" here — this is `never` behaving
exactly as designed. The actual decision is *which* mode belongs on
this host: `madvise` if anything running here might genuinely benefit
from THP and knows to ask for it explicitly (a big in-memory analytics
job, a JVM configured to request huge pages for its heap), `never` if
you want an absolute guarantee that nothing on this host is ever
affected by THP-related compaction activity, full stop.

**Lesson:** choosing `never` as a blanket default across an entire
fleet trades away real, legitimate benefit for any workload that
actually wants huge pages — including future workloads nobody's
running yet — to protect against a problem that `madvise` already
solves for the *specific* workload you're worried about. `madvise` is
the narrower, more surgical fix; `never` is the blunt instrument, and
reaching for the blunt instrument by default is usually solving today's
problem at tomorrow's cost.

---

## Challenge B — the system-wide counter doesn't tell you *which* process

**Check:**
```bash
cat /proc/<pid>/smaps_rollup | grep AnonHugePages
```
Shows `AnonHugePages: 65536 kB` for this specific process under
`always` — the entire 64MB region it touched, backed by huge pages.

**Diagnosis:** `/proc/vmstat`'s `thp_fault_alloc` is a kernel-wide
aggregate counter — it tells you *that* huge-page allocation is
happening somewhere on the system, but nothing about which process(es)
are responsible, which matters enormously the moment more than one
memory-hungry process is running (nearly always, on a real host).
`/proc/<pid>/status` doesn't carry a huge-page field at all — the field
you want lives in `/proc/<pid>/smaps_rollup` (a pre-aggregated summary
of that process's full memory map, added specifically so tools don't
have to sum the much larger, per-mapping `/proc/<pid>/smaps` file by
hand) alongside `Rss`, `Pss`, and similar per-process memory
accounting.

**Fix:** not applicable here — this challenge is about the diagnostic
itself, not a misconfiguration to correct.

**Lesson:** system-wide counters are the right first check ("is this
happening at all on this host") but the wrong tool for "which process
is actually responsible" — that always requires a per-process view.
Reach for `/proc/<pid>/smaps_rollup` (or full `smaps` when you need
per-mapping detail, not just the rollup total) whenever a system-wide
signal needs to be attributed to a specific process before you can act
on it.
