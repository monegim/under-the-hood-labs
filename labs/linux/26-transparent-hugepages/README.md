# Lab 26 — Transparent Huge Pages Backing Memory You Didn't Ask For

## Objective
Prove that `transparent_hugepage=always` silently backs an ordinary
process's memory with 2MB huge pages whether that process wants it or
not — using the actual kernel counter that tells you when it happened,
not a guess — then fix it and confirm the workload is no longer
affected.

## Why this matters
Transparent Huge Pages reduce TLB pressure and can genuinely help
throughput-oriented workloads. But `always` mode applies that decision
to *every* eligible process on the host, and Redis, MongoDB, and
several other latency-sensitive databases explicitly document
recommending it be disabled specifically because the kernel's
background compaction work (`khugepaged`, trying to assemble
contiguous 2MB blocks out of fragmented physical memory) can introduce
latency spikes unrelated to anything the application itself is doing.
The default has shifted over the years — many modern distros ship
`madvise` instead of `always` — but plenty of systems, especially older
ones or ones provisioned from an older base image, still have `always`
set, silently.

## Prerequisites
- A Linux host or VM with THP support (`/sys/kernel/mm/transparent_hugepage/enabled` must exist)
- `sudo` access
- `gcc`

Check first:
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
gcc --version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This saves your system's current THP setting (so `reset.sh` never
leaves your machine worse off than it found it), compiles two small
programs (`touch_noopt` — an ordinary memory-touching workload that
never asks for huge pages; `touch_madvise` — one that explicitly
opts in, used in Challenge A), then sets THP to `always`.

## Step 2 — Confirm the incident
```bash
grep thp_fault_alloc /proc/vmstat
/var/tmp/lab26/touch_noopt
grep thp_fault_alloc /proc/vmstat
```
`thp_fault_alloc` — a real kernel counter of how many huge-page
allocations have happened at fault time, in `/proc/vmstat` — increases
after running a program that never asked for huge pages at all. This is
the actual, direct evidence that `always` mode is applying itself to
workloads regardless of what they want.

## Step 3 — Fix it
```bash
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```
`madvise` is the middle-ground default most modern distros ship: THP is
available, but only for processes that explicitly ask for it via
`madvise(MADV_HUGEPAGE)` — not applied blanket-wide.

## Step 4 — Verify
```bash
./check.sh
```
Confirms THP is set to `madvise` and — the part that actually matters —
that `touch_noopt` genuinely no longer triggers `thp_fault_alloc` to
increase.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — "never" is a harder override than it looks:**
```bash
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
grep thp_fault_alloc /proc/vmstat
/var/tmp/lab26/touch_madvise
grep thp_fault_alloc /proc/vmstat
```
Under `madvise`, this program — which explicitly calls
`madvise(MADV_HUGEPAGE)` on its own memory — *does* get huge pages,
correctly. Now:
```bash
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
grep thp_fault_alloc /proc/vmstat
/var/tmp/lab26/touch_madvise
grep thp_fault_alloc /proc/vmstat
```
Same program, same explicit request — and this time it gets nothing,
with no error reported anywhere (the `madvise()` syscall itself still
returns success). Explain exactly what `never` overrides that `madvise`
doesn't, and think through a real scenario where you'd want `madvise`
specifically (not `never`) even on a host running a workload you've
disabled THP for — what's the cost of choosing `never` as a blanket
default across an entire fleet instead of `madvise`?

**Challenge B — the system-wide counter doesn't tell you *which* process:**
```bash
cat > /tmp/touch_daemon.c <<'EOF'
#include <sys/mman.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main() {
    size_t sz = 64 * 1024 * 1024;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    memset(p, 1, sz);
    printf("pid=%d\n", getpid());
    sleep(120);
    return 0;
}
EOF
gcc /tmp/touch_daemon.c -o /tmp/touch_daemon
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
/tmp/touch_daemon &
```
On a real host, `/proc/vmstat`'s `thp_fault_alloc` is a system-wide
total — with more than one process running, it can't tell you which
one is actually the one affected. Using the PID this program printed,
find the per-process equivalent (look in `/proc/<pid>/`, not
`/proc/vmstat` — `status` won't have it, but a similarly-named file
will) that shows *this specific process's* huge-page usage directly,
in kilobytes.

See `solution.md` only after you've formed your own diagnosis.

## Cleaning up
This lab changes a system-wide kernel setting, not something scoped to
a container or namespace. When you're completely done (not just between
retries — `reset.sh` is for that), restore your system's original
setting:
```bash
cat /var/tmp/lab26/original-thp-setting.txt | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```
