# Lab 15 — Concept: I/O Schedulers and Where Fairness Actually Lives

## What's actually going on

Every block device in Linux has an associated request queue, and sitting
in front of that queue is an I/O scheduler — the component responsible
for deciding, when multiple I/O requests are pending at once, which one
actually gets dispatched to the hardware next. On modern kernels this
lives in the blk-mq (multi-queue block layer) framework, and the
available/active scheduler for a given device is readable and settable
through `/sys/block/<dev>/queue/scheduler` — the bracketed entry in that
file's output is the one currently doing the arbitrating.

`none` isn't a minimal or fast scheduler — it's the deliberate absence
of one: requests get dispatched in whatever order they arrive (FIFO, at
the block layer), with no concept of deadlines, priority classes, or
fairness between whatever processes or cgroups issued them. This is a
completely reasonable choice on hardware that already does sophisticated
internal request reordering and prioritization on its own (many modern
NVMe SSDs, with deep native command queues), where an OS-level scheduler
would mostly just add overhead on top of work the device is already
doing well. It is a poor choice the moment you have genuinely
latency-sensitive work sharing a device with bulk/background work and
no scheduling layer anywhere is doing fairness accounting — which is
exactly this lab's setup.

`mq-deadline` and `bfq` are two different answers to "what should a
scheduler that isn't `none` actually optimize for." `mq-deadline`
attaches a deadline to each request and mostly services in arrival
order, jumping the queue for anything about to breach its deadline —
cheap to implement and reason about, and it bounds worst-case latency,
but it isn't doing proportional fairness between different I/O sources.
`bfq` is a full proportional-share scheduler (the name literally means
Budget Fair Queueing): it tracks separate queues per process (and, with
cgroup `io` controller integration, per cgroup), assigns each a "budget"
of service time/bytes, and actively interleaves dispatch to approximate
fair, latency-aware access for everyone competing for the device — at
real additional CPU/bookkeeping cost per I/O compared to `mq-deadline`'s
much simpler deadline check.

`ionice` sets a priority class and level on a specific process — but
that value is inert unless the active scheduler both understands I/O
priority classes and is designed to act on them. `bfq` (like `cfq`
before it) explicitly implements class-aware scheduling and genuinely
changes behavior based on `ionice`; `none`, having no scheduling logic
of any kind, has nothing to read that priority into. This is why the
exact same `ionice` command can be meaningful under one scheduler and a
complete no-op under another — the command doesn't fail, it just has no
mechanism downstream willing to act on it.

## Where this shows up in the real world

Container hosts, CI runners, and database servers all commonly run
mixed workloads on shared storage — backup/export jobs alongside
latency-sensitive request handling — and the I/O scheduler is one of
the least-checked configuration items when that mix starts causing
latency problems, because it's invisible from the application layer
entirely. Cloud images and many container base images default to
`none` or `mq-deadline` (optimized for the common case of fast,
internally-queuing virtual/NVMe storage), which is often the right
choice — until a workload's actual contention profile calls for real
fairness shaping and nobody thinks to check `/sys/block/*/queue/scheduler`
as part of investigating "why is this one process's latency so
inconsistent under load."

## Go deeper

- **Website/docs:** Linux kernel block layer documentation — https://docs.kernel.org/block/index.html — official documentation of blk-mq, the available I/O schedulers, and their design goals.
- **Website/docs:** Linux kernel BFQ documentation — https://docs.kernel.org/block/bfq-iosched.html — official documentation of BFQ's proportional-share model and configuration.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man1/ionice.1.html — the `ionice` command reference, including its priority classes.
- **Book:** *Systems Performance* — Brendan Gregg — direct coverage of I/O schedulers, queueing theory basics, and disk I/O latency analysis.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — practical storage/performance administration content alongside its broader Linux material.
