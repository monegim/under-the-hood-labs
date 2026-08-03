# Lab 5 — Solutions

## Challenge A — `ionice` needs a scheduler that supports priority classes

**Check:**
```bash
LOOPDEV=$(cat /var/lib/slowlab/loopdev)
DEV=$(basename "$LOOPDEV")
cat /sys/block/"$DEV"/queue/scheduler
```
Shows something like `[none] mq-deadline` or `[mq-deadline]` — no `bfq`
in sight, and definitely not selected.

**Diagnosis:** `ionice`'s priority classes (realtime, best-effort with
0–7 priority levels, idle) are only meaningful to an I/O scheduler that
actually implements per-process priority scheduling — historically
`cfq`, and on modern kernels `bfq`. The default scheduler for many block
devices today (especially virtio-blk/loop devices and NVMe, which is
exactly the kind of device this lab's loop device resembles) is
`mq-deadline` or `none`, neither of which look at I/O priority at all —
every request is treated the same regardless of what `ionice` class or
priority it was submitted with. Running `ionice` against a process is
never an error and never fails silently in an obvious way — the class
gets set successfully, it's the scheduler that ignores it, which is why
this is such a confusing gotcha in practice.

**Fix:**
```bash
echo bfq | sudo tee /sys/block/"$DEV"/queue/scheduler
HOGPID=$(pgrep -f 'fio --name=hog')
sudo ionice -c 3 -p "$HOGPID"
tail -20 /var/log/slowlab/service.log
```
With `bfq` active, `ionice -c 3` (idle class) actually changes how the
scheduler allocates disk time between the hog and the victim service.

**Lesson:** never assume `ionice` "should" be working just because the
command ran without error — check `/sys/block/<dev>/queue/scheduler`
first. This matters even more on cloud/VM disks and loop/virtual devices,
where the effective scheduler is often `none`/`mq-deadline` by default
and switching it may have limited or no effect anyway if the true
bottleneck is a shared host-level disk you don't control at all — in
that case, `ionice` on the guest can't help, because the contention is
happening a layer below where the guest's scheduler even operates.

---

## Challenge B — CPU-bound, not disk-bound this time

**Check:**
```bash
iostat -x 1 5
vmstat 1 5
```
`iostat -x` on the lab's device shows `%util` and `await` back to
baseline — no meaningful disk activity at all. `vmstat`'s `us` (user CPU)
column is pegged near 100 (two busy-looping `yes` processes each
saturating a CPU core), while `wa` (I/O wait) is at or near 0.

**Diagnosis:** killing `fio` removed all disk contention, but two `yes >
/dev/null` processes are now saturating CPU instead. The victim service
is still slow, but for a completely different reason: it's not getting
scheduled onto a CPU promptly, not waiting on disk. This is the whole
point of checking `iostat` and `vmstat` together rather than assuming
last incident's root cause still applies — "the service is slow" is a
symptom that maps to multiple, mutually exclusive root causes, and
disk-vs-CPU is one of the most basic branch points in diagnosing it.

**Fix:**
```bash
sudo pkill yes
tail -20 /var/log/slowlab/service.log
```
Killing the CPU hogs, not touching disk I/O at all, resolves it —
confirming the diagnosis.

**Lesson:** "it's slow" is not a diagnosis, and neither is "last time it
was the disk, so it's probably the disk again." Every slowness
investigation should start by checking utilization/saturation across the
actual candidate resources (CPU, disk, network, memory) rather than
pattern-matching to the most recent incident — `vmstat`'s `us`/`sy`
(CPU) vs `wa` (I/O wait) columns, read side-by-side with `iostat -x`'s
`%util`/`await`, are usually enough to immediately rule most candidates
in or out.
