# Level 4 — Databases: MySQL

Twenty-two hands-on MySQL/InnoDB/MariaDB incidents, each a real environment with an
induced fault, not a quiz. Same DBRE instinct as the
[Postgres half of this level](../postgres): reproduce the incident,
diagnose it from first principles using MySQL's own system views and
tools, fix it, then work through two follow-up challenges that look
identical on the surface but have a different root cause.

## Labs

1. [`01-replication-lag-io-contention`](01-replication-lag-io-contention) —
   replication lag caused by I/O contention on the replica's own host,
   not the primary. Localizing lag with `Seconds_Behind_Source` and the
   IO vs. SQL thread split.
2. [`02-gtid-issues`](02-gtid-issues) — a write committed directly on a
   replica creates an errant GTID transaction that halts GTID-based
   replication outright.
3. [`03-deadlocks`](03-deadlocks) — a textbook InnoDB deadlock from two
   transactions taking the same two row locks in opposite order,
   diagnosed via the actual deadlock graph in `SHOW ENGINE INNODB
   STATUS`.
4. [`04-slow-queries`](04-slow-queries) — a query that was fine at small
   scale degrades as a table grows; the slow query log and `EXPLAIN` as
   the diagnostic path.
5. [`05-metadata-locks`](05-metadata-locks) — a forgotten open
   transaction holds a metadata lock that blocks an unrelated `ALTER
   TABLE` — and everything queued behind it, by design.
6. [`06-disk-full`](06-disk-full) — a MySQL instance fills its own disk
   through unpurged binary logs accumulating under normal write traffic.
7. [`07-binlog-corruption`](07-binlog-corruption) — a corrupted binary
   log file on the primary breaks replication downstream in a way
   that's specific to which file gets corrupted.
8. [`08-connection-storms`](08-connection-storms) — a broken
   connection-pool pattern exhausts `max_connections` by opening far
   more connections than it ever gives back.
9. [`09-innodb-redo-log-full`](09-innodb-redo-log-full) — an
   undersized InnoDB redo log forces aggressive checkpoint flushing
   under sustained write load, visibly collapsing throughput.
10. [`10-semi-sync-replication-timeout`](10-semi-sync-replication-timeout) —
    semi-synchronous replication silently falls back to async once a
    replica goes unreachable past `rpl_semi_sync_source_timeout`.
11. [`11-partition-pruning-failure`](11-partition-pruning-failure) —
    query patterns that silently defeat partition pruning on a
    RANGE-partitioned table, scanning every partition instead of one.
12. [`12-proxysql-routing-failure`](12-proxysql-routing-failure) — a
    one-line ProxySQL hostgroup swap sends writes to the read-only
    replica, with no startup error anywhere.
13. [`13-history-list-length-purge-lag`](13-history-list-length-purge-lag) —
    a long-running transaction holds InnoDB's purge thread back,
    growing the undo History List Length unbounded — the MySQL analog
    of Postgres's transaction-ID wraparound.
14. [`14-primary-failure-manual-promotion`](14-primary-failure-manual-promotion) —
    a primary dies with two replicas at different GTID positions;
    promoting the stale one causes a real `AUTO_INCREMENT` collision the
    moment the topology tries to reconcile.
15. [`15-proxysql-connection-pool-exhaustion`](15-proxysql-connection-pool-exhaustion) —
    ProxySQL's own per-backend connection pool fills up while MySQL
    itself sits nearly idle; contrasted with two other independent
    ProxySQL connection ceilings, each failing a different way.
16. [`16-auto-increment-exhaustion`](16-auto-increment-exhaustion) — a
    `TINYINT UNSIGNED AUTO_INCREMENT` primary key hits its ceiling while
    the table itself is nearly empty, since deleted rows never return
    their IDs to the pool.
17. [`17-point-in-time-recovery`](17-point-in-time-recovery) — recovering
    from a `DELETE` with no `WHERE` clause using a full backup plus
    binary log replay, stopped at the exact position before the mistake.
18. [`18-innodb-corruption-recovery`](18-innodb-corruption-recovery) — a
    single page's on-disk checksum stops matching its content, crashing
    `mysqld` outright; recovered with `innodb_force_recovery`, including
    why its highest level can return silently wrong data instead of
    crashing at all.
19. [`19-proxysql-auth-mismatch`](19-proxysql-auth-mismatch) — a backend
    password rotated directly on MySQL, without updating ProxySQL's
    copy, keeps working for a while on pooled connections before
    failing in a way that's easy to mistake for the wrong incident
    entirely.
20. [`20-proxysql-runtime-not-persisted`](20-proxysql-runtime-not-persisted) —
    a ProxySQL routing fix loaded `TO RUNTIME` but never `SAVE`d `TO
    DISK` silently reverts on the next unrelated restart, weeks after
    the change that actually caused it.
21. [`21-buffer-pool-sizing`](21-buffer-pool-sizing) — a table that
    outgrew its buffer pool degrades the hit ratio for otherwise
    unchanged, correctly-indexed queries; plus a single ad-hoc scan
    evicting a well-sized pool's genuinely hot data, and why `SET
    GLOBAL innodb_buffer_pool_size` doesn't survive a restart.
22. [`22-mariadb-system-versioning`](22-mariadb-system-versioning) — a
    MariaDB-only feature (no MySQL equivalent): `WITH SYSTEM
    VERSIONING` quietly keeps a full row for every `UPDATE`/`DELETE`
    forever by default, invisible to every query the application
    actually runs, until someone checks what's really on disk.

## Prerequisites

- Docker + the `docker compose` plugin for labs 1-2, 7, 9-20
- A Linux host with `sudo`/apt access for labs 3-6, 8 (these install
  `mysql-server` directly rather than using Docker — each README says
  exactly what's needed)

Same per-lab file set as every other level in this repo: `README.md`,
`solution.md`, `CONCEPTS.md`, `setup.sh`, `check.sh`, `reset.sh`.
