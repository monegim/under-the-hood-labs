# Lab 14 — Solutions

## Challenge A — `swapoff` isn't free

**Check:**
```bash
time sudo swapoff /var/lib/swaplab14/swapfile
```
This takes noticeably longer than a normal command, and while it's
running, `vmstat 1` shows heavy activity in the `si`/`so` (swap in/out)
columns — the system is visibly working, not just sitting there.

**Diagnosis:** `swapoff` doesn't just flip a switch and forget about
the pages that were out on that swap device — every single page
currently swapped out to it has to be read back into RAM *before*
`swapoff` can complete, because after it returns, that swap space is no
longer available to hold them. If RAM is tight (which, in a scenario
where swap filled up in the first place, it usually is), bringing all
of that data back into RAM can itself apply real memory pressure — in
the worst case, `swapoff` on an already-stressed system can fail
outright, or trigger the very OOM condition you were trying to relieve,
because completing it requires exactly the RAM headroom that's in short
supply.

**Fix:** in this lab, killing the hog first and letting memory pressure
subside before running `swapoff` avoids the problem; in a real incident,
the safer sequence is almost always "relieve the memory pressure first
(kill or throttle whatever's consuming it), then deal with the swap
device," not the reverse.

**Lesson:** `swapoff` is a real, potentially slow, potentially
memory-pressure-inducing operation — not a free administrative toggle.
Treat it with the same caution you'd give any operation whose cost
scales with how much data it has to move, because that's exactly what
it is.

---

## Challenge B — `vm.swappiness=0` doesn't fix this

**Check:**
```bash
free -h
swapon --show
```
Swap fills up at essentially the same rate as before, despite
`swappiness` set to its lowest value.

**Diagnosis:** `vm.swappiness` is a *preference weight* the kernel's
page reclaim logic uses when it has a genuine choice between two
reclaim strategies — evicting clean, reloadable page cache (file-backed
pages) versus swapping out anonymous memory (heap/stack allocations
with nowhere else to go but swap). A low swappiness biases reclaim
toward preferring to drop page cache first. But this lab's hog is
almost entirely anonymous memory (`bytearray` allocations, not file
reads), running inside a cgroup with a hard `memory.max`. Once that
cgroup's usage hits its limit, the kernel has to reclaim *something*
from that cgroup to satisfy the next allocation — if there's little or
no reclaimable page cache to fall back to, swapping the anonymous pages
is the only option left, and it happens *regardless* of how low
swappiness is set, because swappiness only ever adjusts a *preference*
between two reclaim paths that both remain available — it cannot
disable one of them.

**Fix:** there isn't one via swappiness — the actual fixes are the same
ones as the main lab: add more swap, raise the cgroup's `memory.max`, or
reduce how much anonymous memory the workload actually needs.

**Lesson:** `vm.swappiness` answers "when the kernel has a choice, which
should it prefer" — it does not answer "should the kernel ever swap at
all." Under hard memory pressure with mostly-anonymous memory and
little reclaimable cache, there often isn't a real choice left to bias,
and swapping happens regardless of the swappiness value. Don't reach
for swappiness tuning expecting it to prevent swapping outright — it
can't, by design.
