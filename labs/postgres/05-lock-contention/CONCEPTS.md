# Lab 35 — Concept: Locks Are Held By Transactions, Not Statements

## What's actually going on

In Postgres, row-level and table-level locks are acquired by statements
but released by the enclosing transaction — a lock taken by an `UPDATE`
or a `SELECT ... FOR UPDATE` stays held for as long as the transaction
that ran it remains open, regardless of whether that transaction is
currently running anything at all. `pg_stat_activity.state` gives you the
vocabulary to tell these apart: `active` means a query is currently
executing; `idle` means the connection has no open transaction and isn't
doing anything; `idle in transaction` means a `BEGIN` happened, at least
one statement ran, and then... nothing — no `COMMIT`, no `ROLLBACK`, just
a connection sitting there with whatever locks it already acquired still
fully in effect. This is precisely the state a forgotten `COMMIT`, an
application holding a database transaction open across a slow HTTP call
to another service, or a developer's abandoned `psql` session all produce
— and from the outside, every other query trying to touch the same rows
just sees "waiting," with no indication of why.

`pg_blocking_pids(pid)` (a built-in function since Postgres 9.6) is the
direct way to answer "waiting on whom": pass it the PID of a blocked
backend and it returns the PID(s) actually holding the conflicting lock —
no manual self-join against `pg_locks` required, though `pg_locks` is
still what you need when the answer isn't about a single row at all.
Table-level locks in Postgres form a matrix of compatibility — a plain
`SELECT` takes `AccessShareLock`, a plain `UPDATE`/`DELETE`/`INSERT` takes
`RowExclusiveLock`, and most `ALTER TABLE`/`DROP`/`TRUNCATE` operations
take `AccessExclusiveLock`, which conflicts with every other lock mode
including `AccessShareLock`. Crucially, Postgres's lock manager is
request-order-fair: a new lock request that would be compatible with
every lock *currently granted* still has to wait if a conflicting request
is already *queued* ahead of it, even if that queued request hasn't been
granted yet either. This exists to stop an exclusive-lock requester from
being starved forever by a continuous stream of compatible shared
requests — but it means one slow DDL statement queued behind a
long-running read can back up every subsequent query against that table,
not just the ones that actually conflict with what the DDL is trying to
do. Challenge B is built specifically to make that queueing order visible
in `pg_locks`'s `granted` column.

`idle_in_transaction_session_timeout` (a real GUC, default `0` = disabled)
is Postgres's own answer to the main lab's specific failure mode: it
terminates any backend that's been sitting idle inside an open
transaction longer than the configured duration, converting a silent,
indefinite lock hold into a loud, immediate error the client actually
sees. It has a clean boundary, though: it only fires on the `idle in
transaction` state specifically. A transaction that's continuously
*active* — even running something pointless or slow the entire time, as
in Challenge A — never enters that state, and needs `statement_timeout`
(or an application-level timeout) instead.

## Where this shows up in the real world

Any application framework that opens a database transaction and then
does something slow before committing it — an external API call, a
queue publish, a synchronous email send — is one dependency hiccup away
from an idle-in-transaction incident, and these are notoriously
hard to spot from application logs alone, because the application code
itself isn't stuck; the database connection just never got told to
finish. DDL against a live, busy table is a separate, equally common
production incident: an `ADD COLUMN` or index change that looks
completely harmless in isolation can, if it happens to queue behind one
long-running report query, cascade into a full outage for that table
within seconds, because every subsequent query queues in order behind
the stuck DDL rather than skipping past it.

## Go deeper

- **Book:** *The Internals of PostgreSQL* — Hironobu Suzuki — https://www.interdb.jp/pg/ — the concurrency control chapters cover lock modes and the lock manager's queueing behavior.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — operational patterns for diagnosing and preventing lock-contention incidents in production databases.
- **Website/docs:** PostgreSQL official docs, explicit locking — https://www.postgresql.org/docs/current/explicit-locking.html — the full table-level lock mode compatibility matrix used throughout this lab.
- **Website/docs:** PostgreSQL official docs, `pg_locks` and `pg_stat_activity` — https://www.postgresql.org/docs/current/monitoring-stats.html — the exact views and columns (`state`, `wait_event`, `pg_blocking_pids()`) used throughout this lab.
- **YouTube:** CYBERTEC PostgreSQL — https://www.youtube.com/@CybertecPostgresql — operational content on lock contention and blocking-query diagnosis.
