# Lab 27 — CFS CPU Quota Throttling Invisible to Top

## Objective
Reproduce a container getting CPU-throttled badly enough to make a
fixed unit of work take 5x longer than it should — while `docker
stats`' CPU% shows nothing alarming — then diagnose it correctly from
the cgroup's own throttling counters instead.

## Why this matters
A CPU limit like `--cpus=0.5` isn't a smooth, continuous cap — the
kernel's CFS bandwidth controller enforces it in discrete periods
(100ms by default): your container gets its quota's worth of CPU time
within each period, and once that's used up, every process in the
container is frozen until the next period starts, no matter how
briefly it needed a little more. A bursty workload — a request handler
that's mostly idle but occasionally needs real CPU for a moment — can
get throttled hard *within* individual periods while its CPU usage
*averaged* over any longer window looks completely unremarkable. This
is one of the most common "why is this container app slow, CPU usage
looks fine" incidents in any containerized/Kubernetes environment, and
the standard tools most people reach for first (`top`, `docker stats`)
structurally cannot show it, because they only report averaged
utilization, never throttling.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
Brings up a container limited to `0.5` CPU (`cpus: 0.5` in
`docker-compose.yml`) and installs `stress-ng`, used to generate a
fixed, repeatable amount of CPU work.

## Step 2 — Reproduce the symptom
```bash
docker exec lab27-app bash -c "time stress-ng --cpu 2 --cpu-method fibonacci --cpu-ops 4000000 --metrics-brief"
```
This fixed unit of work — 2 threads, 4 million fibonacci operations
total — takes noticeably longer than it should (compare: the same
command on an unconstrained container completes in well under 100ms).

## Step 3 — Check the layer that actually shows the problem
```bash
docker exec lab27-app grep -E "nr_throttled|throttled_usec" /sys/fs/cgroup/cpu.stat
```
`nr_throttled` (how many CFS periods this cgroup has been throttled in)
and `throttled_usec` (cumulative microseconds spent throttled) climb
visibly across that one command. Now compare against the view most
people check first:
```bash
docker stats lab27-app --no-stream
```
CPU% sits comfortably under the quota, unremarkable-looking — `docker
stats` (like `top`) reports *utilization averaged over its sampling
window*, which is structurally incapable of surfacing "throttled hard
for brief bursts, idle the rest of the time." Only `cpu.stat` tells you
throttling is happening at all.

## Step 4 — Fix it
```bash
docker compose stop app
CPU_LIMIT=2 docker compose up -d app
```

## Step 5 — Verify
```bash
./check.sh
```
Confirms the same fixed workload now completes quickly (under 200ms)
with negligible additional throttled time.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — quantify exactly how misleading the "healthy" view is:**
```bash
./reset.sh
docker exec -d lab27-app bash -c '
for i in $(seq 1 20); do
  stress-ng --cpu 2 --cpu-method fibonacci --cpu-ops 4000000 >/dev/null 2>&1
  sleep 0.5
done
'
docker stats lab27-app --no-stream
```
While that loop runs (repeated bursts, half a second apart — a
reasonable stand-in for "handles occasional requests"), `docker stats`
reports CPU% in the 20s-30s, nowhere near the 50% quota. Check
`cpu.stat`'s `throttled_usec` before and after this loop finishes and
compute what fraction of the loop's *total* wall-clock time was spent
throttled. Given that number, explain precisely why a monitoring setup
that alerts only on CPU utilization crossing some threshold (a very
common default) would never fire for this incident, no matter how bad
the user-facing latency impact actually is.

**Challenge B — sizing concurrency off the wrong number makes it worse:**
```bash
./reset.sh
docker exec lab27-app nproc
```
This container is limited to `0.5` CPU, but `nproc` — what most
thread-pool-sizing logic actually calls — reports the *host's* full
CPU count, completely unaware of the cgroup limit. Compare:
```bash
docker exec lab27-app grep throttled_usec /sys/fs/cgroup/cpu.stat
docker exec lab27-app bash -c "time stress-ng --cpu 2 --cpu-method fibonacci --cpu-ops 4000000 --metrics-brief"
docker exec lab27-app grep throttled_usec /sys/fs/cgroup/cpu.stat
```
against running the *same total amount of work* spread across as many
threads as `nproc` reports instead of 2:
```bash
docker exec lab27-app grep throttled_usec /sys/fs/cgroup/cpu.stat
docker exec lab27-app bash -c "time stress-ng --cpu \$(nproc) --cpu-method fibonacci --cpu-ops 4000000 --metrics-brief"
docker exec lab27-app grep throttled_usec /sys/fs/cgroup/cpu.stat
```
The `nproc`-sized version is dramatically slower and racks up far more
throttled time for the exact same amount of actual work. Explain why
more threads, sharing the exact same fixed quota, makes throttling
*worse* rather than just "no better" — and name a real category of
application (hint: what does `Runtime.availableProcessors()` return,
and what does it get used for by default?) that has historically hit
this exact problem in production.

See `solution.md` only after you've formed your own diagnosis.
