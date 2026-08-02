# Lab 20 — Why Is the Server Slow

## Objective
Diagnose a concrete, specific cause of "the server feels slow" — a CPU-bound
background process that isn't obviously "the app" — using `top`, `ps`,
`uptime`, and `vmstat` instead of guessing.

## Why this matters
"The server is slow" is one of the most common vague tickets an SRE gets.
Most people jump straight to "must be the app" or "must need more CPU."
The real skill is: look at the actual numbers first (load average, per-process
CPU, run queue) before touching anything. Half the time it's a stray process
someone forgot about — a cron job, a leftover debug script, a runaway report
generator — not the application at all.

## Prerequisites
- Linux VM, sudo access
- `top`, `ps`, `vmstat` (all in `procps`, installed by default on Ubuntu)

Check first:
```bash
uname -a
which top ps vmstat uptime
nproc
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This installs and starts `/usr/local/bin/report-generator.sh` in the
background — a disguised CPU hog (`yes > /dev/null`). Imagine a teammate
says "the server's been sluggish since this morning."

## Step 2 — Confirm the symptom
```bash
uptime
```
> Gotcha: load average is a count of runnable + uninterruptible processes,
> not a percentage. A load of `1.00` on a 1-core box is 100% saturated; the
> same `1.00` on a 16-core box is nothing. Always check `nproc` alongside
> load average.

## Step 3 — Find the actual offender
```bash
top
```
Sort by CPU (default in `top`) and look at the `%CPU` column. Note the PID
and command name.

> Gotcha: the process is literally named `report-generator.sh` — a real
> incident won't be this honest. Don't rely on the name; rely on `%CPU`.

Cross-check with `ps`:
```bash
ps aux --sort=-%cpu | head -5
```

## Step 4 — Confirm it, don't assume it
```bash
cat /proc/$(pgrep -f report-generator.sh)/status | grep -E 'State|Threads'
```
Confirm the process is actually in `R` (running) state, burning CPU, not
just sitting there.

## Step 5 — Fix it
```bash
sudo pkill -f report-generator.sh
uptime
```
Load average should start dropping within the next minute (it's an average,
not instantaneous).

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — many small hogs instead of one big one:**
```bash
sudo bash -c 'for i in $(seq 1 6); do nohup yes > /dev/null 2>&1 & disown; done'
```
`top`'s default view still shows CPU eaten, but now split across several
processes instead of one obvious top line. Figure out the total damage, not
just the single worst offender, and how you'd prove it's the same root
cause.

**Challenge B — memory pressure instead of CPU:**
```bash
python3 -c "
import time
hogs = []
while True:
    hogs.append(bytearray(50 * 1024 * 1024))
    time.sleep(0.2)
" &
disown
```
The server "feels slow" again, but this time `top`'s CPU numbers look mostly
normal. Check `free -h` and `vmstat 1 5` before you conclude anything. What's
actually happening, and why does it make everything else on the box slow too?

See `SOLUTION.md` only after you've formed your own diagnosis.
