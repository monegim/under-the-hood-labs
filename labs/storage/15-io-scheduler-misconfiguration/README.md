# Lab 15 — I/O Scheduler Misconfiguration

## Objective
Prove that the active I/O scheduler — not just raw disk speed — decides
whether a latency-sensitive writer gets starved by a background I/O hog
under contention, by watching the exact same workload behave
differently under `none` versus a scheduler that actually does fairness
shaping.

> **Honesty note:** I/O scheduler effects are most visible on real
> rotational or genuinely queue-depth-limited hardware. This lab uses a
> loop device throttled via cgroup `io.max` to create real, measurable
> contention on a VM with no such hardware available — the mechanism is
> real, but the exact magnitude of the difference you see may vary by
> kernel version. Worth a live check before you trust the specific
> numbers, same caveat as `06-nvme-failure`'s simulation.

## Why this matters
Two processes sharing one disk under load is an extremely common
production shape — a backup job and a database, a batch export and an
API request handler, a log shipper and everything else. Which one wins
when both want the disk at once isn't decided by priority you set in
your application, or `nice`, or even always by `ionice` — it's decided
by the kernel's I/O scheduler, and if that scheduler is `none` (pure
FIFO, no fairness logic of any kind), *nothing* protects a
latency-sensitive process from being queued behind a bulk one, no
matter how you've configured the application layer.

## Prerequisites
- A Linux VM, `sudo` access, cgroup v2
- `fio`, `sysstat` (installed by `setup.sh` if missing)
- `bfq` scheduler support (`setup.sh` runs `modprobe bfq`) — if your
  kernel doesn't have it available, note that in your findings; the
  general lesson (scheduler choice matters, `none` provides none of
  this) still holds with `mq-deadline` as the alternative

Check first:
```bash
ls /sys/block/loop0/queue/scheduler 2>/dev/null || echo "will check the actual loop device setup.sh creates"
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates a 300M loop-device-backed filesystem, throttles it via
cgroup `io.max` to ~2MB/s and 200 IOPS (so there's genuine contention to
arbitrate), sets its scheduler to `none`, and starts two processes
inside that throttled cgroup: a latency-sensitive "foreground" writer
logging its own write latency, and a background `fio` hog doing
continuous random writes.

## Step 2 — Watch the sensitive writer suffer
```bash
tail -f /var/log/ioschedlab15/sensitive.log
```
Watch `write_latency_ms` — under `none`, the hog's requests and the
sensitive writer's requests are serviced in whatever order they
happened to queue, with no scheduler-level attempt to keep the
latency-sensitive one fast.

## Step 3 — Confirm the scheduler is the variable in play
```bash
LOOPDEV=$(cat /var/lib/ioschedlab15/loopdev)
cat /sys/block/"$(basename "$LOOPDEV")"/queue/scheduler
```
The bracketed entry is the active one — `[none]` right now.

## Step 4 — Switch to a scheduler that does fairness shaping
```bash
echo bfq | sudo tee /sys/block/"$(basename "$LOOPDEV")"/queue/scheduler
```
(If `bfq` isn't available on your kernel, try `mq-deadline` instead —
still a real improvement over `none`, via basic deadline-ordering
rather than `bfq`'s fuller proportional-fairness model.)

## Step 5 — Verify
```bash
tail -20 /var/log/ioschedlab15/sensitive.log
```
Compare the latency numbers to Step 2 — same hog, same throttle, same
everything except the scheduler.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `bfq` vs `mq-deadline`, and what each one is actually trading off:**
```bash
LOOPDEV=$(cat /var/lib/ioschedlab15/loopdev)
DEV="$(basename "$LOOPDEV")"
echo mq-deadline | sudo tee /sys/block/"$DEV"/queue/scheduler
sleep 15
tail -10 /var/log/ioschedlab15/sensitive.log
echo bfq | sudo tee /sys/block/"$DEV"/queue/scheduler
sleep 15
tail -10 /var/log/ioschedlab15/sensitive.log
```
Both are a real improvement over `none`. Compare them directly, and
find out (from `fio`'s own aggregate throughput numbers in
`/var/log/ioschedlab15/fio.log`, re-run for each scheduler) whether the
better latency fairness costs anything in raw hog throughput. Figure
out why `bfq` (Budget Fair Queueing, doing proportional-share
scheduling with real fairness accounting) and `mq-deadline` (a simpler
deadline-ordering guarantee) aren't just "old vs new" — they're
different strategies with different overhead.

**Challenge B — `ionice` alone doesn't help under `none`:**
```bash
LOOPDEV=$(cat /var/lib/ioschedlab15/loopdev)
DEV="$(basename "$LOOPDEV")"
echo none | sudo tee /sys/block/"$DEV"/queue/scheduler
sudo ionice -c3 -p "$(cat /var/lib/ioschedlab15/fio.pid)"
sleep 15
tail -10 /var/log/ioschedlab15/sensitive.log
```
`ionice -c3` (idle class — "only use the disk when nothing else wants
it") is set on the hog, and the sensitive writer's latency barely
improves, if at all. Figure out why an I/O priority hint that works
perfectly well under other schedulers does essentially nothing here —
specifically, what `none` actually is (a scheduler, or the *absence* of
one), and what that implies about whether there's any priority
mechanism left for `ionice` to talk to.

See `solution.md` only after you've formed your own diagnosis.
