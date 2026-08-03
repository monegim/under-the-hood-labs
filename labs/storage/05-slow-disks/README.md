# Lab 5 — Slow Disks: Proving It's I/O, Not the App

## Objective
Build a small service that's slow purely because of disk I/O contention
(not CPU), starve it with a competing I/O-heavy process, and learn to use
`iostat -x` (`await`, `%util`) to prove the disk — not the application —
is the bottleneck, then fix it with `ionice`.

## Why this matters
"The service is slow" gets blamed on the application's code far more
often than it should be. When the real cause is disk contention, no
amount of code review finds it — the fix is recognizing the I/O signature
(`await` climbing, `%util` near 100%) and dealing with the competing
workload, not the service. This is exactly the kind of methodology
mistake the USE method (Utilization, Saturation, Errors) exists to
prevent: check the resource, don't assume which one is guilty.

## Prerequisites
- Linux VM, `sudo` access
- `sysstat` (`iostat`), `fio` — installed by `setup.sh` if missing

Check first:
```bash
which iostat fio ionice
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 300M loop-device-backed ext4 filesystem at `/mnt/slowdata`,
starts a small background "victim" service that repeatedly writes and
`fsync`s a tiny file and logs how long each write took, and lets it run
long enough to record a healthy baseline latency.

## Step 2 — Confirm the baseline is healthy
```bash
tail -20 /var/log/slowlab/service.log
```
Write latencies should be small and consistent (a handful of
milliseconds).

## Step 3 — Start the competing I/O hog
```bash
sudo bash -c 'cd /mnt/slowdata && fio --name=hog --filename=hogfile --size=250M \
  --rw=randwrite --bs=4k --numjobs=4 --time_based --runtime=120 --direct=1 \
  --output=/var/log/slowlab/fio.log &'
```
(`setup.sh` already started this for you — this is shown so you know
exactly what's generating the load.)

## Step 4 — Watch the victim service degrade
```bash
tail -20 /var/log/slowlab/service.log
```
Latencies jump from single-digit milliseconds to much higher — nothing in
the service's code changed; it's contending for the same disk as `fio`.

## Step 5 — Prove it's disk, not CPU
```bash
iostat -x 1 5
vmstat 1 5
```
On the loop device backing `/mnt/slowdata`: `%util` near 100%, `await`
(and `w_await`) elevated. In `vmstat`, the `wa` (I/O wait) column is
elevated while `us`/`sy` (actual CPU use) stay low — the CPU is mostly
idle, waiting on disk, which is the whole proof that this isn't a
CPU-bound problem.

## Step 6 — Fix it: deprioritize the hog's I/O
```bash
HOGPID=$(pgrep -f 'fio --name=hog')
sudo ionice -c 3 -p "$HOGPID"
```
`-c 3` is the "idle" I/O class — the hog only gets disk time when nothing
else wants it. Watch `service.log` recover.

> Gotcha: `ionice` only has a real effect on I/O schedulers that support
> priority classes (`bfq`, and historically `cfq`). Check what's actually
> active:
> ```bash
> cat /sys/block/$(basename $(readlink -f /var/lib/slowlab/loopdev))/queue/scheduler
> ```
> If it shows `none` or `mq-deadline` with no `[bfq]`, `ionice` may do
> nothing at all, no matter how correctly you ran it — see Challenge A.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `ionice` had zero effect:**
```bash
HOGPID=$(pgrep -f 'fio --name=hog')
sudo ionice -c 3 -p "$HOGPID"
tail -20 /var/log/slowlab/service.log
```
Latencies stay just as bad as before you ran `ionice`. Diagnose why the
exact same fix from Step 6 didn't work this time (hint: check the block
device's active I/O scheduler), and what you'd need to change before
`ionice` can have any effect at all.

**Challenge B — it's not the disk this time:**
```bash
sudo pkill -f 'fio --name=hog'
sudo bash -c 'yes > /dev/null &'
sudo bash -c 'yes > /dev/null &'
tail -20 /var/log/slowlab/service.log
```
The service is still slow. Diagnose whether this is the same problem as
before using `iostat -x` and `vmstat` together — don't assume "slow"
still means "disk" just because that's what it meant a minute ago.

See `solution.md` only after you've formed your own diagnosis.
