# Lab 6 — Concept: MySQL Has More Than One Disk to Fill

## What's actually going on

Binary logs are MySQL's record of every change made to the data, written
independently of the actual data files, and they exist for two reasons:
replication (a replica's IO thread reads them from the source) and
point-in-time recovery (replaying binlogs forward from a backup to
recover up to just-before-an-incident). Because of that, MySQL never
deletes a binlog file on its own just because it's "old" — it only
removes one when told it's safe to, either explicitly via `PURGE BINARY
LOGS`, or automatically based on `binlog_expire_logs_seconds` (the
current name; `expire_logs_days` is the older, still-supported form).
Set that variable to `0` — an explicit "keep everything forever," and a
setting a surprising number of production configs still carry over from
older defaults or copy-pasted templates — and MySQL will do exactly what
it's told: retain every binlog file it has ever generated, indefinitely.
Combined with `max_binlog_size` controlling how often it rotates to a new
file, an entirely ordinary, unremarkable write workload will
predictably, mechanically fill whatever disk those files live on. There's
no bug here and no mystery once you check `SHOW BINARY LOGS` — the
symptom ("MySQL refuses writes, disk full") and the cause (nobody ever
configured retention) are both in plain sight; the only skill being
taught is knowing to check binlog disk usage as a specific, distinct
thing from checking the data directory's disk usage.

`PURGE BINARY LOGS BEFORE <date>` (or `PURGE BINARY LOGS TO
'<filename>'`) is the manual, immediate escape hatch — it deletes binlog
files older than the given point, but only ones MySQL believes nothing
still needs (it will refuse to purge past a position a currently-connected
replica hasn't consumed yet). `binlog_expire_logs_seconds` is the ongoing,
automatic version of the same policy, evaluated whenever a binlog rotates.
Neither one, by itself, is a capacity plan — as Challenge A demonstrates,
a perfectly reasonable retention window can still exceed your disk's
actual size if your write rate is high enough; retention answers "how
much history," not "do I have room for that much history."

`tmpdir` is a completely separate concern from binary logging, but
produces the identical-looking symptom: disk usage climbing, then writes
(or in this case, specific queries) failing with "no space." MySQL uses
`tmpdir` for on-disk temporary tables and for **filesort** — the sort
algorithm used whenever a query needs ordered results that can't be
produced directly from an index, and the data being sorted doesn't fit
within `sort_buffer_size` (allocated fresh per sort operation, per
connection — not one shared pool across the server). A query with a large
`ORDER BY` on unindexed columns over enough rows can, on its own, generate
gigabytes of on-disk merge-sort files with zero relation to binary logging
at all. Both failure modes get grouped under "MySQL disk full" in a page,
but they're different subsystems, different configuration knobs
(`binlog_expire_logs_seconds`/`max_binlog_size` vs.
`tmpdir`/`sort_buffer_size`/schema and query design), and — in production
— often different physical volumes entirely, which is exactly why this
lab mounts them as two separate dedicated filesystems.

## Where this shows up in the real world

Unbounded binlog growth is one of the most common "boring but real"
MySQL incidents — it doesn't require anything exotic, just enough write
volume and enough time with retention misconfigured or simply never set.
It disproportionately affects environments migrated or upgraded from
older MySQL versions/configs where "just keep binlogs forever" was a more
common default assumption, or where someone disabled expiry temporarily
during a migration/backup project and never re-enabled it. tmpdir
exhaustion from large sorts is the other classic shape — reporting
queries, ad-hoc analytics against a production OLTP schema, or a query
that used to run against a much smaller table are the usual triggers, and
it's a good reminder that "SELECT-only" workloads are not automatically
disk-safe just because they don't write to application tables.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/purge-binary-logs.html — `PURGE BINARY LOGS` syntax and safety semantics.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html — `binlog_expire_logs_seconds`, `max_binlog_size`, and related binary log configuration.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/internal-temporary-tables.html — when and why MySQL creates on-disk temporary tables, and how `tmpdir`/`sort_buffer_size` relate.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — binary log management and filesort/temp table internals.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — recurring operational coverage of binlog disk management and diagnosing filesort-driven disk usage.
