# Lab 20 — Solutions

## Challenge A — many small CPU hogs

**Check:**
```bash
uptime
ps aux --sort=-%cpu | head -10
pgrep -fa 'yes' | wc -l
```
`top`'s top line no longer shows one process at ~100% — instead you see 6
`yes` processes each around `100/nproc`% or fighting for the same cores.
Load average is high, but no single row screams "kill me."

**Diagnosis:** the total CPU demand hasn't changed conceptually from the
main lab — it's the same kind of hog — but splitting it across several
processes defeats the "just look at the top line" habit. You have to sum
CPU by command name, not by PID:
```bash
ps aux --sort=-%cpu | awk '$11=="yes" {sum+=$3} END {print sum "% total"}'
```

**Fix:**
```bash
sudo pkill -x yes
```

**Lesson:** don't diagnose off the single highest `%CPU` row — group and sum
by command/user. A fork bomb or a batch of runaway workers can hide as many
"medium" rows instead of one "obvious" one.

---

## Challenge B — memory pressure disguised as "slow"

**Check:**
```bash
free -h
vmstat 1 5
```
`free -h` shows `available` memory shrinking and `swap` used climbing (if
swap exists). `vmstat`'s `si`/`so` columns (swap in/out) are non-zero, and
the `b` column (processes blocked on I/O) may be > 0. CPU (`us`/`sy`
columns) looks unremarkable — this is the tell that it's NOT a CPU problem.

```bash
ps aux --sort=-%mem | head -5
```
Shows the Python process's RSS climbing over time if you run it twice a few
seconds apart.

**Diagnosis:** the process keeps allocating memory it never frees. Once
available RAM runs low, the kernel starts reclaiming page cache and
swapping, and every process on the box pays a latency tax for it — disk I/O
for swap is orders of magnitude slower than RAM, so everything "feels slow"
even though no process is CPU-bound. This is why "server is slow" needs
`free`/`vmstat` checked alongside `top`, not instead of it.

**Fix:**
```bash
pkill -f "hogs.append"
```

**Lesson:** high CPU isn't the only cause of "slow" — memory pressure and
swapping produce the identical symptom (everything sluggish) with a
completely different signature in the tools. Always check `free -h` and
`vmstat` before you commit to a CPU-only diagnosis.
