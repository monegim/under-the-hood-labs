# Lab 1 — Concept: Replication Lag Is a Symptom, Not a Diagnosis

## What's actually going on

MySQL replication (in the GTID-based mode this lab uses) works by having
the replica's **IO thread** pull binary log events from the primary and
write them into a local relay log, while a separate **SQL (apply) thread**
reads that relay log and actually executes the events against the
replica's own data — an `INSERT`/`UPDATE`/`DELETE` (or, for GTID
replication, a set of transactions identified by globally unique IDs
rather than raw binlog file/position coordinates) applied one after
another. `Seconds_Behind_Source` measures the gap between "when this
event happened on the primary" and "when the SQL thread finished applying
it" — critically, it is a *symptom* of the SQL thread being slower than
the primary's write rate, and that slowness can come from genuinely
different places: MySQL-level tuning (too few `replica_parallel_workers`,
suboptimal apply strategy), network latency between primary and replica,
or — as this lab is built to prove — the replica's own host being unable
to give the SQL thread the resources it needs to keep up, or something at
the MySQL level itself blocking it entirely. All three produce the exact
same headline number climbing, which is precisely why jumping straight to
MySQL config changes without first checking the host is the single most
common mistake in a real replication-lag incident.

The main lab and Challenge A demonstrate two different resource-layer
causes that look identical from `Seconds_Behind_Source` alone but require
completely different diagnosis. Disk I/O contention (the main lab, via
`io-hog`'s `dd ... conv=fdatasync` writers sharing the same underlying
block device as the replica's actual MySQL datadir) shows up as high
`%util` and elevated `await` in `iostat -x` — the SQL thread's writes
(and the InnoDB log flushes it depends on) are queued behind unrelated
I/O on the same physical disk, so applying events is available but slow.
CPU contention (Challenge A, via `yes` loops pinning every core) produces
a completely different `iostat` signature — the disk is fine, `%util`
low — but `docker stats`/`top` show the SQL thread's process simply not
getting scheduled enough CPU time, because Docker's default CPU shares
are a *fair-share* allocation, not a hard reservation: when the host is
genuinely oversubscribed, every container's actual CPU time shrinks,
including one doing latency-sensitive apply work. Same symptom, disjoint
root cause, disjoint fix (throttle/cap I/O vs throttle/cap CPU, or give
the replica dedicated resources instead of a shared host) — which is why
checking disk *and* CPU, not just one, is part of the correct diagnostic
sequence, not an optional extra step.

Challenge B is a different category of cause entirely: `FLUSH TABLES WITH
READ LOCK` takes a **global read lock** that blocks writes across the
whole server, and the SQL/apply thread's entire job is writes — applying
relay log events. With both `iostat` and `top`/`docker stats` showing the
replica host essentially idle, there is no resource being exhausted at
all; the apply thread is simply blocked waiting on a lock held by an
unrelated session (in this lab, one that took the lock and then sat in
`SELECT SLEEP(180)` without releasing it — the same shape as a backup
tool or an ad-hoc maintenance session that forgets `UNLOCK TABLES`, or a
long-running report query left open in the same session). `SHOW
PROCESSLIST` on the replica is what actually reveals this — a connection
sitting in `Sleep` state while still holding a lock it never released —
and it's the one diagnostic step that has nothing to do with OS-level
resource checks at all.

## Where this shows up in the real world

Replication lag is one of the most frequently paged DBRE symptoms, and
its causes span at least three distinct layers: MySQL configuration,
infrastructure/host resource contention (a noisy neighbor container, a
shared SAN, an oversubscribed hypervisor), and MySQL-internal locking
that has nothing to do with hardware at all. A backup tool or ad-hoc
maintenance session taking a global lock and not releasing it promptly is
a very real, recurring production incident — one that produces zero
evidence in `iostat`/`top`, so an engineer who only checks infrastructure
metrics can spend a long time confused about "healthy-looking hardware
with lagging replication." The correct instinct, in order, is: check the
replica's own OS-level resource usage first (disk, then CPU — cheap and
often the actual answer), and if both come back clean, check MySQL's own
lock/session state (`SHOW PROCESSLIST`) before assuming a config problem
that would require a completely different, much slower fix.

## Go deeper

- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors — directly addresses this "check the host before the database config" diagnostic discipline for replication and other DB incidents.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — the standard reference for replication internals, GTID mechanics, and lag diagnosis.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication.html — canonical reference for replication threads, GTID mode, and `SHOW REPLICA STATUS` fields.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — frequently covers real-world replication-lag postmortems distinguishing I/O, CPU, and locking causes.
- **YouTube:** Percona — https://www.youtube.com/@percona — talks and webinars on MySQL replication troubleshooting and performance diagnosis.
