# Incident 16 — Concept: When the Monitoring Pipeline Itself Fails Silently

## What's actually going on

Two mechanisms combine here, and the interaction between them - not
either one alone - is the actual lesson.

The first is **D-state / uninterruptible sleep**, the same mechanism
`labs/linux/09-process-stuck-in-d-state` demonstrates directly: a
process performing a blocking I/O syscall against an unreachable
network filesystem (a `hard` NFS mount whose server has gone dark)
enters `TASK_UNINTERRUPTIBLE` and stays there until the I/O either
completes or the kernel gives up - which, for a `hard` mount with no
timeout configured, can mean forever. Crucially, this isn't a bug in
the process; it's the kernel correctly refusing to unwind a syscall
mid-flight because doing so could leave on-disk (or on-NFS) state
inconsistent. `kill -9` doesn't touch a thread stuck this way until the
syscall returns, if it ever does.

The second mechanism is **partial liveness in a multi-threaded
process**. A process is usually treated as a single unit of "up" or
"down," but `metrics-agent` has two independent jobs running as two
independent threads: one collects and persists data (and can block),
the other answers HTTP requests from cached state (and doesn't block on
anything the first thread is doing). When the collector thread wedges,
the HTTP thread doesn't notice, doesn't care, and keeps answering `200
OK` with whatever it was last handed. From the outside - `systemctl
status`, a `curl` to the metrics port, a process list - the service
looks completely healthy. It *is*, in the narrow sense that its HTTP
server is up. It just isn't doing the one thing that makes its answers
meaningful anymore.

Put together: a failure mode that would be obvious in a single-threaded
service (it would just stop responding, and a scrape failure or
timeout would flag it immediately) becomes invisible in a
multi-threaded one, because the part that keeps working is the part
being watched from outside, and the part that broke is invisible
without checking data freshness specifically.

## Why "check staleness" has to be a first-class step

A flat, healthy-looking graph is consistent with exactly two
situations: the system is actually healthy and unchanging, or the
thing drawing the graph stopped updating. Nothing about the graph's
*shape* distinguishes them - that's the entire point of this incident.
The only distinguishing signal is metadata about the data itself: when
was this sample taken, relative to now? Real monitoring systems solve
this with an explicit staleness concept - Prometheus marks a scrape
target `up=0` when a scrape fails or times out, and treats metrics that
haven't been refreshed within a configured window as stale rather than
implicitly trustworthy forever. A homegrown collector that just caches
"whatever I had last" and serves it indefinitely has quietly opted out
of that safety net, and nothing about its behavior under a scrape
signals that it did.

The practical habit this incident is meant to build: whenever a
dashboard and reality disagree, check the dashboard's own freshness
before trusting either its "everything's fine" or its "everything's on
fire" - a flatlined graph and a genuinely healthy graph render
identically, and only a timestamp tells them apart.

## Where this shows up in the real world

Metrics pipelines built on custom collectors, textfile exporters, or
sidecar agents that write to a shared/network filesystem for
durability are common in shops that grew a monitoring stack
organically rather than adopting one wholesale. Any point in that
pipeline that can block indefinitely - a hung mount, a downstream API
call with no timeout, a lock that's never released - can produce this
exact "confidently wrong" dashboard. It's a materially worse failure
than the collector crashing outright, because a crashed collector
usually trips its own alert; a stuck one usually doesn't.

## Go deeper

- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et
  al. (free at https://sre.google/books/) — the monitoring chapters
  cover treating monitoring pipeline health (freshness, scrape success)
  as a first-class signal, not an assumption.
- **Book:** *Systems Performance* — Brendan Gregg — process state
  (`D` vs `R` vs `S`) and the kernel-level meaning of uninterruptible
  sleep are covered as part of the broader methodology for not trusting
  the first plausible-looking explanation for "the system is slow."
- **Website:** Brendan Gregg's site — https://www.brendangregg.com — the
  USE method's insistence on checking a resource's actual state, not
  just whatever a dashboard summarizes about it, is the same discipline
  this incident is built to exercise.
- Related lab in this repo: `labs/linux/09-process-stuck-in-d-state` -
  the exact NFS-hard-mount-plus-blocked-syscall mechanism used here,
  demonstrated on its own without the monitoring angle.
