# Lab 17 — Concept: Point-in-Time Recovery Is Two Different Mechanisms Stacked

## What's actually going on

A full logical backup (`mysqldump`) captures a consistent snapshot of
every row at one instant — `--single-transaction` gets this without
locking tables, by taking the snapshot inside a single `REPEATABLE READ`
transaction using InnoDB's normal MVCC machinery. That snapshot is
complete but frozen: restoring it alone puts the database back exactly
as it was at backup time, with no way to recover anything written
afterward. The binary log is the other half of the mechanism — every
change since the server started (or since the last log rotation) is
recorded there as a stream of events, in commit order, which means it
can be replayed forward from any known point to reconstruct everything
that happened after it. Point-in-time recovery is these two mechanisms
used together: the backup provides the starting state, the binlog
provides everything since, and stopping the replay at a chosen position
lets you land the database at any moment in between — including "one
statement before the mistake."

The two positions this lab works with — where the backup was taken
(`mysqldump --master-data=2`'s recorded `CHANGE MASTER TO ... POS`) and
where the disaster transaction starts/ends (found by reading the decoded
binlog directly) — are just byte offsets into a specific binlog file.
`mysqlbinlog`/`mariadb-binlog --start-position`/`--stop-position` filter
the replay stream to exactly the range between two such offsets. This
is deliberately low-level and exact: there's no "restore to 2:47pm"
built into the tool itself (some managed database platforms build that
UX on top of exactly this mechanism, using timestamps embedded in binlog
events to compute the position for you), but the position-based
primitive underneath is what every point-in-time-recovery feature,
managed or self-hosted, ultimately reduces to.

This lab also demonstrates a real, easy-to-miss operational gap: the
official `mysql:8.0` Docker image ships `mysql`, `mysqldump`, and
several other client tools, but not `mysqlbinlog` — a genuine gap in
that image, not a simplification made for this lab. Debian's
`default-mysql-client` package (which pulls in MariaDB's client tools,
providing an equivalent binary named `mariadb-binlog`) is a reasonable,
verified-working substitute for reading and replaying MySQL 8.0's
ROW-format binary logs, including correctly treating MySQL's own
vendor-specific GTID event as an opaque, safely-ignorable event it
doesn't need to understand to decode everything else accurately. But
that cross-vendor combination isn't perfectly transparent — the decoded
session-variable preamble MariaDB's tooling emits includes at least one
variable (`check_constraint_checks`) that MySQL doesn't recognize,
which is exactly Challenge A's failure mode. Real infrastructure is
full of exactly this kind of "mostly compatible, except for one thing
that breaks quietly" tooling gap, and verifying recovered data directly
— rather than trusting a clean-looking command exit — is the general
defense against all of them, not just this specific one.

## Where this shows up in the real world

"Someone ran a `DELETE`/`UPDATE`/`DROP` without a `WHERE` clause" is one
of the most common categories of real production incident, precisely
because it requires no special conditions to trigger — a single
missing keystroke in an ad-hoc query during routine maintenance is
enough. Point-in-time recovery is the standard, expected response, and
it is genuinely time-pressured: every minute spent finding the right
binlog position is a minute the business is running on stale or missing
data. This is exactly why practicing the exact commands — not just
knowing the concept exists — is real, valuable DBRE skill: a managed
platform's "restore to timestamp" button is this same mechanism with a
friendlier interface, and understanding what it's doing underneath
means knowing what to do when self-hosting, when the managed tooling
doesn't support your exact scenario, or when the disaster is one
transaction inside a much larger set of legitimate writes you can't
afford to also lose (Challenge B's exact shape).

## Go deeper

- **Website/docs:** MySQL 8.0 Reference Manual, Point-in-Time (Incremental) Recovery — https://dev.mysql.com/doc/refman/8.0/en/point-in-time-recovery.html — the authoritative reference for this entire mechanism, backup-plus-binlog-replay, directly.
- **Website/docs:** MySQL 8.0 Reference Manual, `mysqlbinlog` — https://dev.mysql.com/doc/refman/8.0/en/mysqlbinlog.html — `--start-position`/`--stop-position` and every other binlog-reading option, for the canonical (MySQL-vendor) version of the tool this lab substitutes.
- **Website/docs:** MySQL 8.0 Reference Manual, `mysqldump` — https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html — `--single-transaction` and `--master-data`/`--source-data` semantics.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — covers backup strategy and recovery procedures as first-class operational topics, including binlog-based PITR.
- **Blog:** Percona, "A Simple Guide to MySQL Point-in-Time Recovery" — https://www.percona.com/blog/ — Percona's blog has multiple deep, practically-oriented posts on exactly this recovery pattern, including handling the multi-segment "skip just the bad transaction" case from Challenge B.
