# Lab 32 — Concept: Replication Slots Are a Promise, Not a Cache

## What's actually going on

Every write to Postgres generates WAL (Write-Ahead Log) before the actual
data-page change is considered durable — this is the mechanism that makes
crash recovery and replication both possible. Under normal operation, WAL
segments only need to stick around long enough to satisfy crash recovery
and `archive_command` (if configured); once a checkpoint confirms
everything in an old segment is durably on disk and archived, that
segment becomes eligible to be recycled or removed. A **replication
slot** changes that calculus: it's a durable, on-disk record (in
`pg_replication_slots`) that tells the primary "don't remove WAL past
this LSN, no matter what, until whatever's using this slot confirms it no
longer needs it." That's exactly the right behavior when a replica or a
logical decoding consumer is actually connected and slowly catching up
after a network blip — the slot is what lets it resume cleanly instead of
needing a full resync. It's exactly the wrong behavior, silently, when
nothing is consuming from the slot at all: `restart_lsn` freezes at
whatever position it was at when the last consumer disconnected (or at
creation time if nothing ever connected), and WAL keeps accumulating
behind that frozen point forever, because by design Postgres has no way
to know the difference between "replica is temporarily behind" and
"replica is never coming back" — both look identical from the primary's
side: an inactive slot with a lagging `restart_lsn`.

`pg_replication_slots.wal_status` (added in PG13, alongside
`max_slot_wal_keep_size`) is the column that turns this from an invisible
time bomb into a monitorable value: `reserved` means everything is
within normal retention (`max_wal_size`) anyway; `extended` means the slot
is now the ONLY reason this WAL hasn't been removed; `unreserved` means
retained WAL has exceeded `max_slot_wal_keep_size` and removal could
happen on the next checkpoint; `lost` means it already has, and the slot
is now permanently broken — any consumer trying to resume from it will
get a "requested WAL segment has already been removed" error and needs a
fresh base backup (physical) or a recreated subscription (logical).
Without `max_slot_wal_keep_size` set (its default is `-1`, unlimited),
there is no automatic safety net at all — the slot will happily consume
100% of whatever disk `pg_wal` lives on before Postgres does anything
about it, which is exactly the incident this lab reproduces.

Logical replication slots (Challenge A) add a second, less visible
retention mechanism on top of WAL: `catalog_xmin`. Because logical
decoding reconstructs row changes using the table/column definitions as
they existed at the time of each change, it needs old versions of system
catalog rows to remain vacuumable-but-not-yet-vacuumed for as long as the
slot might still need them. An abandoned logical slot therefore also
blocks catalog cleanup cluster-wide — a kind of bloat that never shows up
in any single table's `pg_stat_user_tables` row, because it isn't in a
user table at all.

## Where this shows up in the real world

This is one of the most common "the primary died and nobody knows why"
incidents in real Postgres operations, because the chain of events is so
unremarkable: someone provisions a read replica or a logical replication
consumer (a CDC pipeline into Kafka/Debezium is a very common one), it
runs fine for months, then it gets decommissioned or its host dies — and
if nobody remembers to `pg_drop_replication_slot()` the corresponding
slot on the primary, the primary starts silently accumulating WAL from
that day forward with zero symptoms until the disk actually fills and the
primary itself goes down. Any monitoring stack for Postgres should alert
on `pg_replication_slots` where `active = false`, and separately on
`wal_status` approaching `extended`/`unreserved`, well before disk usage
itself becomes the alert — by the time disk usage triggers an alert, the
primary may already be seconds from refusing writes entirely.

## Go deeper

- **Book:** *The Internals of PostgreSQL* — Hironobu Suzuki — https://www.interdb.jp/pg/ — WAL and physical replication internals chapters explain exactly what a slot's `restart_lsn` protects and why.
- **Book:** *PostgreSQL 14 Internals* — Egor Rogov — https://postgrespro.com/community/books/internals — replication chapter covers slots, `catalog_xmin`, and logical decoding internals in depth.
- **Website/docs:** PostgreSQL official docs, replication config — https://www.postgresql.org/docs/current/runtime-config-replication.html — `max_slot_wal_keep_size` and related settings.
- **Website/docs:** PostgreSQL official docs, `pg_replication_slots` — https://www.postgresql.org/docs/current/view-pg-replication-slots.html — the exact columns (`active`, `restart_lsn`, `catalog_xmin`, `wal_status`) used throughout this lab.
- **Website/blog:** depesz — https://www.depesz.com — deep-dive posts on WAL internals and replication-slot gotchas.
- **YouTube:** CYBERTEC PostgreSQL — https://www.youtube.com/@CybertecPostgresql — operational content on replication slots and WAL management.
