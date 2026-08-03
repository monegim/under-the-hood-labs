# Lab 5 — Concept: Metadata Locks Protect Schema Consistency, and They Queue Fairly

## What's actually going on

Every SQL statement that touches a table — not just DDL — takes a
**metadata lock** (MDL) on it for the duration of the statement, or for
the duration of the enclosing transaction if it's inside one. Almost all
ordinary statements take a lightweight `SHARED` (or more precisely
`SHARED_READ`/`SHARED_WRITE`) metadata lock: many sessions can hold
`SHARED` MDL on the same table at once, which is why normal concurrent
reads and writes don't block each other at this layer. `ALTER TABLE`,
`DROP TABLE`, and other DDL need an `EXCLUSIVE` metadata lock instead —
one that cannot coexist with *any* other session's lock on the table,
shared or otherwise, because changing the table's structure while another
session might be mid-statement against the old structure would be unsafe.
An `EXCLUSIVE` MDL request has to wait for every existing `SHARED` MDL
holder to finish first. In this lab, the long-running transaction's
`SELECT` grabbed and is still holding a `SHARED` MDL — not because it's
doing anything with the table anymore, but because MDL is scoped to the
whole transaction, not the individual statement, and the transaction
never committed. The `ALTER TABLE` genuinely cannot start until that
transaction ends, one way or another.

The part that catches people off guard is what happens *after* the ALTER
is already queued: MySQL's metadata lock subsystem is explicitly designed
so that once an `EXCLUSIVE` request is waiting, it takes priority over any
*new* `SHARED` requests that arrive after it — otherwise, on a busy table,
a constant stream of new reads and writes could keep a pending `ALTER
TABLE` waiting forever (a real, well-documented DDL-starvation problem in
earlier MySQL behavior). The fix for that starvation problem creates a
different, equally real operational hazard: any ordinary query issued
*after* the ALTER started waiting also has to wait, even if — like this
lab's plain `SELECT COUNT(*) FROM orders`s — it would never have
conflicted with the original blocking transaction on its own. A single
forgotten `COMMIT` can therefore cascade into every query against that
table queuing up, the moment anyone happens to run an ALTER (a routine
migration, a schema-management tool, an ORM-driven auto-migration) against
it.

`SHOW PROCESSLIST`'s `State` column is the first signal: `Waiting for
table metadata lock` is a distinct wait reason from row-lock waits (which
show up in `SHOW ENGINE INNODB STATUS`, as in Lab 3) or I/O waits — it
tells you immediately that this is a schema-lock issue, not a data-lock
issue, which points you toward completely different tools. `SHOW
PROCESSLIST` alone, though, only shows you who's *waiting* — it doesn't
show who's *holding* the lock everyone's stuck behind.
`performance_schema.metadata_locks` (joined against
`performance_schema.threads` to map back to a processlist ID) is the table
built specifically to answer that: each row is one lock, its `LOCK_STATUS`
(`GRANTED` vs `PENDING`), and which thread owns it. Note that this
specific instrument (`wait/lock/metadata/sql/mdl`) is **disabled by
default** in stock MySQL 8.0 — you have to explicitly enable it in
`performance_schema.setup_instruments`, as this lab's `setup.sh` does,
before the information becomes visible at all.

## Where this shows up in the real world

This is one of the most common "routine migration takes down production"
incident shapes: a schema-migration tool runs an `ALTER TABLE` against a
busy table, and it happens to queue behind some unrelated long-running
transaction that was already sitting there (a report query someone forgot
was still open, a connection pool that leaked a transaction, an ORM
session with unexpectedly long scope) — the ALTER itself did nothing
wrong, but from the outside, "we ran a migration and the whole app went
down" is exactly what it looks like, because every subsequent query
against that table queues up behind the stuck ALTER within seconds.
Anyone running schema migrations against live traffic should have a
standard first move of checking `SHOW PROCESSLIST`/`metadata_locks` for
long-running transactions on the target table *before* issuing the DDL,
and many migration tools (`gh-ost`, `pt-online-schema-change`) exist
specifically to avoid taking a blocking `EXCLUSIVE` MDL on a live table at
all for this exact reason.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/metadata-locking.html — MDL types, scope, and the DDL-fairness queuing behavior this lab reproduces.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/performance-schema-metadata-locks-table.html — the `metadata_locks` table, its columns, and enabling the underlying instrument.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/lock-tables.html — `LOCK TABLES` semantics, relevant to Challenge A.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors — the operational discipline of checking for long-running transactions before running schema changes against production.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — recurring coverage of MDL-related incidents during live schema migrations, and safer alternatives like `pt-online-schema-change`.
