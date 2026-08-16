# Incident 16 — Solution

## Root cause

Two independent things are wrong at the same time, and each one hides
the other:

1. **Real degradation**: a set of CPU-hungry background processes (the
   "log reindexing" job) are pegging every core on the box, so
   `orders-api`'s `/work` endpoint - which does real CPU-bound work per
   request - is genuinely, measurably slower than baseline.
2. **A blind monitoring system**: `metrics-agent`'s collector thread
   persists every sample to `/mnt/metricslab`, a hard NFS mount. The
   NFS server behind that mount became unreachable (an `iptables DROP`
   on port 2049 - "a flaky storage backend"), so the collector's
   `write()`/`fsync()` call blocked in the kernel (D state,
   `TASK_UNINTERRUPTIBLE`) and never returned. It's stuck on the sample
   it was writing *before* the CPU hog started, so `/metrics` keeps
   serving that one healthy-looking JSON blob forever, with a
   `timestamp` field that stopped advancing the instant the mount hung.

Neither problem is visible from the other's evidence. `curl
localhost:8080/work` shows real, current latency - it says nothing
about whether the dashboard is accurate. `curl localhost:9100/metrics`
returns instantly with a 200 and plausible-looking numbers - it says
nothing about whether those numbers are current. The only way to tell
"the graph is flat because things are fine" from "the graph is flat
because the thing drawing it is stuck" is to check *when* the data
underneath it was last produced.

## Why it happened

`metrics-agent` was written the way most homegrown collectors are:
sample data, persist it somewhere durable, serve the latest sample.
Durability got bolted on later (a compliance ask - "metrics need to
survive a VM rebuild") by pointing the collector's writes at an NFS
mount, using the same `hard` mount type production storage paths
correctly use everywhere else in this environment (`soft` mounts
silently corrupt data on timeout, so nobody wanted that). What nobody
accounted for is that a `hard` mount trades "never silently lose data"
for "block forever if the server disappears" - and the collector loop
and the HTTP server happened to end up on different threads of the
same process, so the failure mode isn't "the agent goes down" (which
would be obvious - `curl` would refuse the connection, or the endpoint
would time out), it's "the agent silently stops updating one specific
field while continuing to answer every request instantly." That's a far
worse failure mode for a monitoring system, because it's indistinguishable
from "everything is fine" without actively checking for it.

The CPU-hungry job landing at almost the same time is what makes this a
real incident rather than a curiosity: if the NFS mount had hung five
minutes *before* the reindexing job started, the frozen snapshot would
have been just as stale, but it also would have been accurate by
coincidence - nobody would have noticed or cared. The timing here -
monitoring goes blind right as the thing it's watching starts
degrading - is exactly what makes "check the dashboard" the wrong first
move, and it's exactly the kind of coincidence real on-call shifts
produce constantly.

## Why the obvious fixes don't work

- **"The dashboard says it's fine, so it's probably a client-side/CDN
  issue"**: this is the trap the page is designed to set. The dashboard
  isn't reporting "fine," it's reporting "unchanged" - and those are
  only the same thing if the collector behind it is actually running.
- **Restarting `orders-api`**: does nothing for the real problem (the
  CPU hogs keep running and keep starving whatever process is on the
  box, including a freshly restarted one) and does nothing for the
  monitoring problem either (metrics-agent's blocked thread has nothing
  to do with orders-api's process lifecycle).
- **Restarting `metrics-agent`**: looks like it should fix the
  monitoring half, and briefly does - the new process's collector loop
  will attempt a fresh sample - but the write to `/mnt/metricslab` will
  block again immediately, because the NFS path is still down. The
  dashboard goes right back to frozen, just on a new "last good" value.
- **Killing the CPU hogs alone**: fixes the real customer-facing
  latency. The dashboard, however, stays frozen on the pre-incident
  values forever, because nothing about killing an unrelated process
  unblocks metrics-agent's stuck `write()` call. The next on-call will
  have a dashboard that says "healthy" no matter what actually happens
  next, until someone notices and fixes the NFS path - which is the
  whole danger of this incident class.

## The investigation

Confirm the two signals disagree:
```bash
curl -s -w '\ntime: %{time_total}s\n' http://localhost:8080/work
curl -s http://localhost:9100/metrics
```
`/work` takes noticeably longer than its usual sub-100ms. `/metrics`
returns instantly with a small `work_latency_ms` and a `timestamp`.

Check whether that timestamp is actually current:
```bash
date +%s
```
Compare the two. If `/metrics`'s `timestamp` is minutes (or more) in
the past relative to `date +%s`, the dashboard isn't lying about the
past - it's just not talking about the present. This single comparison
is the crux of the whole incident.

Confirm the CPU pressure is real and find its source:
```bash
top
ps -eo pid,pcpu,cmd --sort=-pcpu | head -20
```
A handful of unfamiliar Python processes consuming close to 100% CPU
each, one per core.

Confirm `metrics-agent` is stuck, not dead, and find where:
```bash
systemctl status metrics-agent.service      # active (running) - not crashed
ps -eo pid,stat,wchan:32,cmd | grep '[m]etrics-agent'
```
The process is alive, `STAT` shows `D` (or a thread in `D` under
`/proc/<pid>/task/*/status`), and `WCHAN` points at something
NFS/RPC-related - it's blocked inside a syscall, not busy and not
exited.

Confirm the NFS path specifically:
```bash
mount | grep metricslab
sudo iptables -L OUTPUT -v -n | grep 2049
```
A hard NFS mount, and a DROP rule on port 2049 with a nonzero, climbing
packet counter - the same signature as `labs/linux/09-process-stuck-in-d-state`.

## The fix

Both problems need fixing; fixing one doesn't fix the page.

Stop the CPU-hungry background job:
```bash
sudo pkill -9 -f "1103515245"   # or: kill the PIDs in /var/lib/metricslab/hog.pids
```
`/work` returns to its normal, fast baseline immediately.

Restore the NFS path so the blocked collector thread can finally
complete its write and resume sampling:
```bash
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -D INPUT -p tcp --sport 2049 -j DROP
```
No restart of `metrics-agent` is required - the pending `write()`
unblocks on its own once the network path comes back, the collector
loop moves on to its next iteration, and `/metrics`'s `timestamp` starts
advancing again within one sample interval.

For prevention: every scrape/collector endpoint should expose its own
freshness as a first-class field (a `last_updated`/`scrape_timestamp`,
or - better - let the actual monitoring system, e.g. Prometheus,
own that judgment via its built-in `up` metric and staleness handling
rather than a homegrown collector serving cached values indefinitely).
Never let a metrics pipeline's own durability path block the read path
that answers scrapes; if persistence must be synchronous, it belongs in
a separate process so a stuck write degrades independently observable
"collector health," not the numbers being reported as current.

## Real-world examples of this pattern

- Custom Prometheus "pushgateway"-style setups and homegrown
  node_exporter textfile collectors are a classic source of this exact
  failure: the textfile collector script hangs (often on a slow/absent
  network filesystem or a downstream API call) mid-write, and
  Prometheus happily keeps serving the last-written file's contents
  with no indication anything is wrong, because from Prometheus's point
  of view the *scrape* of the textfile collector's endpoint succeeded.
- Any dashboard built on "last known value" caching (common in mobile
  and embedded monitoring UIs to avoid flicker on transient scrape
  failures) can present this exact false-healthy signature during a
  real, ongoing outage.
- The general pattern - a health/metrics pipeline that fails silently
  rather than loudly - is exactly why Google's SRE guidance treats
  monitoring staleness/pipeline health as a first-class thing to alert
  on, not an implementation detail: see the monitoring chapters in
  *Site Reliability Engineering* (free at https://sre.google/books/).
