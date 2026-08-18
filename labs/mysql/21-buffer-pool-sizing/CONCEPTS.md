# Lab 21 — Concept: The Buffer Pool Is the Actual Cache Layer

## What's actually going on

InnoDB never reads or writes table data directly from disk on a
per-query basis — every page a query touches is read into the buffer
pool first, and every subsequent access to that page (as long as it
stays resident) is served from memory. `innodb_buffer_pool_size` is
the single most consequential number in a MySQL deployment's memory
budget precisely because of this: it's not a cache in the sense of
"an optimization that helps sometimes," it's the mechanism separating
"this read costs a memory access" from "this read costs a disk I/O,"
for every single row InnoDB ever serves. A working set that fits
comfortably inside the pool sees near-100% hit ratios almost for free.
A working set that's outgrown it degrades continuously and
proportionally — not a cliff, a slope — as a larger share of ordinary
reads become real, physical I/O.

Within the pool, InnoDB doesn't treat every cached page equally.
Pages live on an LRU list split into two zones: a "young" sublist for
data that's been accessed more than once, and an "old" sublist for
data that's only been touched once, most recently. New reads always
land in the old sublist first. `innodb_old_blocks_time` controls how
long a page must wait there before a second access is allowed to
promote it to young — a deliberate friction specifically aimed at one
scenario: a single large sequential scan (a report, a backup, an
analyst's one-off query) touching thousands of pages exactly once
each, which without this friction would flood the young sublist and
evict data that's been genuinely, repeatedly proven hot by real
traffic. This is what makes a correctly-*sized* buffer pool
insufficient on its own — sizing answers "is there enough room for the
steady-state working set," while scan resistance answers a completely
separate question: "can one unusual, ordinary-looking query still
displace it anyway."

Finally, `innodb_buffer_pool_size` being dynamically resizable (no
restart required) is a genuine operational convenience, but it's easy
to mistake for more permanence than it actually has. `SET GLOBAL`
changes only the running server's in-memory state — it was never
designed to also rewrite whatever configuration source (`my.cnf`, a
container's startup command, an orchestrator's manifest) a *future*
process start will read from. Every dynamic variable in MySQL carries
this same split by default, unlike systems (ProxySQL among them) that
force an explicit second step to persist a runtime change - which
means "I fixed it" and "I fixed it durably" are claims that have to be
verified separately, every time.

## Where this shows up in the real world

Buffer pool undersizing is one of the most common, slowest-developing
MySQL performance problems there is, precisely because nothing about
it is a discrete event — there's no single deploy, migration, or
config change to point at, just gradual data growth outpacing a memory
setting nobody revisited. It's also one of the easier problems to miss
in monitoring, since the query itself, its plan, and its index usage
all stay completely unchanged the entire time; only a buffer-pool-level
metric (hit ratio, `Innodb_buffer_pool_reads`) actually shows it.
Capacity planning for InnoDB workloads routinely includes tracking
table growth specifically against buffer pool size for this reason —
treating memory sizing as a one-time decision instead of an ongoing
one is a very common, very avoidable source of "why did this get
slower for no reason" incidents.

## Go deeper

- **Website/docs:** MySQL 8.0 Reference Manual, "InnoDB Buffer Pool" — https://dev.mysql.com/doc/refman/8.0/en/innodb-buffer-pool.html — the authoritative reference for buffer pool sizing, the LRU algorithm, and every variable this lab is built around.
- **Website/docs:** MySQL 8.0 Reference Manual, "Configuring InnoDB Buffer Pool Size" — https://dev.mysql.com/doc/refman/8.0/en/innodb-buffer-pool-resize.html — online resizing mechanics, including why it's chunk-aligned.
- **Website/docs:** MySQL 8.0 Reference Manual, "sys Schema" — https://dev.mysql.com/doc/refman/8.0/en/sys-schema.html — `sys.innodb_buffer_stats_by_table`, the view used throughout this lab to see per-table residency directly.
- **Blog:** Percona, "Percona Blog: InnoDB Buffer Pool" — https://www.percona.com/blog/ — Percona's team has written extensively and practically about real-world buffer pool sizing and scan-resistance tuning.
- **Book:** *High Performance MySQL* — Silvia Botros & Jeremy Tinley (O'Reilly) — the InnoDB internals and memory-tuning chapters cover buffer pool sizing, LRU behavior, and capacity planning in full depth.
