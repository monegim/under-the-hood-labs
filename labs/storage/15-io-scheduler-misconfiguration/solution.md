# Lab 15 — Solutions

## Challenge A — `bfq` vs `mq-deadline`, and what each one is actually trading off

**Check:**
```bash
grep -oE 'iops=[0-9]+' /var/log/ioschedlab15/fio.log | head -1
tail -5 /var/log/ioschedlab15/sensitive.log
```
Compare both metrics across the two runs. `bfq` typically gives the
sensitive writer the tightest, most consistent latency, at some cost to
the hog's raw aggregate IOPS; `mq-deadline` usually lands in between —
noticeably better than `none` for the sensitive writer, with less
overhead (and less latency consistency) than `bfq`.

**Diagnosis:** these aren't "good vs less-good" — they're different
strategies at different complexity/overhead levels. `mq-deadline` gives
every request a deadline and mostly services in arrival order until a
request's deadline is about to be missed, at which point it jumps the
queue — cheap to compute, gives a real bound on worst-case latency, but
doesn't reason about *fairness between different processes/cgroups*
beyond that. `bfq` (Budget Fair Queueing) does real proportional-share
scheduling — it tracks per-process (or per-cgroup, with `blkio`/`io`
controller integration) "budgets" and actively interleaves service to
approximate fair, low-latency access for everyone, which is more
CPU/bookkeeping overhead per I/O than `mq-deadline`'s simpler deadline
check, and can cost some raw throughput on a workload where one process
is deliberately trying to maximize bulk throughput at the expense of
everything else.

**Fix:** neither is universally "the right one" — `bfq` is the better
default when you have genuinely latency-sensitive, interactive, or
mixed-priority workloads sharing a device (desktop use, and this lab's
scenario); `mq-deadline` (or even `none`, on hardware with deep native
queuing that does its own scheduling, like many NVMe SSDs) is often
preferred where raw aggregate throughput matters more than
inter-process fairness and the workload is more uniform.

**Lesson:** "which I/O scheduler is best" doesn't have a single answer —
it depends on whether you're optimizing for worst-case latency
fairness across competing consumers or maximum aggregate throughput for
a single dominant workload, and picking one always costs something in
the other dimension.

---

## Challenge B — `ionice` alone doesn't help under `none`

**Check:**
```bash
LOOPDEV=$(cat /var/lib/ioschedlab15/loopdev)
cat /sys/block/"$(basename "$LOOPDEV")"/queue/scheduler
```
Shows `[none]` — and the sensitive writer's latency stayed roughly the
same as before `ionice -c3` was applied to the hog.

**Diagnosis:** `ionice` sets an I/O priority class/level on a process —
but that priority is only meaningful to a scheduler that actually reads
and acts on it. `none` is not a lightweight, low-priority-aware
scheduler; it is the *absence* of scheduling logic — a pure FIFO
passthrough that hands requests to the block device in arrival order,
with zero concept of process identity, priority class, or fairness of
any kind. Setting `ionice -c3` on the hog under `none` is instructing a
mechanism that isn't there to listen — the priority hint has nowhere to
land. This is exactly why `06-slow-disks`'s note that "`ionice` doesn't
always help" is true, and this lab is the "why": `ionice`'s
effectiveness is entirely conditional on the active scheduler actually
implementing I/O priority classes (`bfq` does, thoroughly; `cfq`, its
predecessor, did too; `mq-deadline` has limited/no meaningful priority
differentiation; `none` has none at all).

**Fix:** switch to a scheduler that actually honors `ionice`:
```bash
echo bfq | sudo tee /sys/block/"$(basename "$LOOPDEV")"/queue/scheduler
sudo ionice -c3 -p "$(cat /var/lib/ioschedlab15/fio.pid)"
```
Now the same `ionice` setting has a real effect, because `bfq` actually
implements the priority-class semantics `ionice` is expressing.

**Lesson:** `ionice` is a *request*, not a guarantee — it only works if
the scheduler underneath is capable of and configured to honor it.
Before assuming an `ionice` setting isn't working because of a bad
value or the wrong process, check what scheduler is actually active;
under `none`, no `ionice` setting will ever do anything at all.
