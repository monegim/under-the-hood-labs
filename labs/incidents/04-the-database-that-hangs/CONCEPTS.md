# Incident 04 — Concept: Durable Commits Are an I/O Contract, Not Just a MySQL Setting

## What's actually going on

Two mechanisms combine here: a durability guarantee that depends on
physical I/O, and a noisy-neighbor workload that happens to share the
same physical I/O.

MySQL's `innodb_flush_log_at_trx_commit=1` (the default, and the safe
setting for not losing committed data on a crash) means a `COMMIT`
isn't allowed to report success until the transaction's redo log entry
has actually been forced to durable storage via `fsync()`. This is a
correctness guarantee, not a performance knob - it's what makes
"the database said my write succeeded" mean something. But it also
means every commit's latency is, by design, coupled to how fast the
underlying disk can acknowledge a synchronous write *right now* - not
its theoretical peak throughput, not its average latency, but its
current queue depth. A read, by contrast, is usually served entirely
from the InnoDB buffer pool in memory and never touches the disk at
all under normal conditions - which is exactly why a disk-contention
incident presents as "writes are slow, reads are fine" rather than
"everything is uniformly slow."

The second mechanism is that a disk's I/O capacity is a genuinely shared,
finite resource across everything that writes to it - the disk has no
concept of "this write is for a critical database commit" versus "this
write is an unrelated batch job's scratch file." Docker bind mounts (or
any shared block device/filesystem) don't isolate I/O between
containers by default; two containers writing to two different
directories on the same physical disk are still contending for the same
queue, the same bandwidth, the same underlying hardware. A workload with
literally zero logical connection to the database - never opens a MySQL
file, never speaks the MySQL protocol - can still make every one of the
database's commits slower, purely by winning a share of the disk's
attention that the database's fsync calls now have to wait behind.

## Where this shows up in the real world

Any database (MySQL, Postgres, or otherwise) configured for durable
commits is, by design, only as fast as its disk's current write
latency, which makes it uniquely vulnerable to unrelated I/O-heavy
neighbors: backup jobs, log shippers, other VMs on the same SAN, or
other containers on the same host disk. Cloud block storage services
often make this contention explicit (a provisioned IOPS/throughput
budget genuinely shared across whatever's attached to that volume), but
the same physical reality exists even without a cloud abstraction in the
way - a disk only has so much queue depth, at any given moment, for
everyone. Diagnosing this requires looking at the resource layer
(`iostat`, `docker stats`'s block I/O column) rather than the
application or database configuration layer, since neither the app nor
the database is misconfigured - the resource underneath both of them is
simply oversubscribed.

## Go deeper

- **Book:** *Systems Performance* — Brendan Gregg — the definitive
  treatment of disk I/O latency/saturation analysis (`iostat`, `await`,
  `%util`) that this incident is built around.
- **Website:** Brendan Gregg's site — https://www.brendangregg.com — the
  USE method (Utilization/Saturation/Errors) applied to storage devices
  is exactly the checklist that catches "the disk is saturated" instead
  of chasing database configuration that isn't the actual problem.
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et
  al. (free at https://sre.google/books/) — see the chapters on
  addressing resource contention between workloads sharing
  infrastructure.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man2/fsync.2.html
  — documents exactly what `fsync()` guarantees and why it necessarily
  blocks on the underlying device.
