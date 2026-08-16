# Lab 13 — Concept: InnoDB's Undo Log, Purge, and the History List

## What's actually going on

InnoDB implements MVCC (multi-version concurrency control) by never
overwriting a committed row in place when it's updated or deleted —
instead, the new version is written, and the *old* version is preserved
in an undo log record, linked from the row via a rollback pointer. This
is what lets a long-running `REPEATABLE READ` transaction see a
consistent snapshot of the whole database even while other transactions
keep committing changes underneath it: any transaction whose snapshot
predates a given change can still find the old version it's entitled to
see by following the undo chain. The `History List Length` is exactly
the count of these old-but-still-tracked row versions sitting in the
rollback segments waiting to be reclaimed.

A dedicated background `purge` thread (or several, via
`innodb_purge_threads`) walks this history continuously, deleting undo
records that are provably no longer needed by *any* currently active
transaction. "No longer needed" is computed against a single boundary —
the oldest read view (snapshot) currently held open anywhere in the
system, sometimes called the purge view. Every `REPEATABLE READ`
transaction (MySQL's default isolation level) establishes its read view
at its first consistent read and holds it for the transaction's entire
lifetime, no matter what it queries afterward — which is exactly why
Challenge A's transaction blocks purge on a table it never touched, and
why Challenge B's second, trivial-looking transaction is just as much of
a blocker as the first: purge doesn't examine what a transaction has
*done*, only how old its snapshot is relative to everything else still
open. As long as the single oldest snapshot in the system stays open,
purge can't advance past it, and every subsequent write anywhere in the
database keeps adding to the backlog behind that fixed point.

This mirrors the same underlying problem PostgreSQL's autovacuum solves
for transaction ID wraparound (see `postgres/07`), even though the
mechanisms and failure modes differ in the details: both engines run a
continuous background cleanup process specifically because MVCC
requires keeping old row versions around for as long as anything might
still need them, and both have exactly one failure mode that matters —
something holding an old snapshot open indefinitely, for reasons that
have nothing to do with which tables that session cares about.

## Where this shows up in the real world

A classic, extremely common real-world trigger is `mysqldump
--single-transaction` — the standard way to take a consistent logical
backup without locking tables — which works by opening exactly this
kind of long-lived `REPEATABLE READ` transaction for the entire
duration of the dump. On a large database or a slow/overloaded backup
window, that's easily tens of minutes with real write traffic
continuing the whole time, and if nobody is watching History List
Length, the undo tablespace (or `ibdata1`, depending on configuration)
grows the entire time and doesn't shrink back down automatically even
after the dump finishes and space *could* be reclaimed — purge has to
catch up first, which itself competes with foreground I/O. An
abandoned ORM session that opened a transaction and never committed or
rolled back is the other extremely common cause, and it's exactly why
DBRE teams alert on `information_schema.innodb_trx` entries with a
`trx_started` older than some threshold (often a few minutes), not just
on History List Length itself — by the time HLL is visibly elevated,
the actual fix (find and end the old transaction) is the same either
way, but catching the open transaction earlier avoids the backlog
altogether.

## Go deeper

- **Website/docs:** MySQL 8.0 Reference Manual, InnoDB Multi-Versioning — https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html — the authoritative explanation of undo logs, read views, and purge.
- **Website/docs:** MySQL 8.0 Reference Manual, `information_schema.INNODB_TRX` — https://dev.mysql.com/doc/refman/8.0/en/information-schema-innodb-trx-table.html — the reference for every column used to hunt down a purge blocker.
- **Website/docs:** MySQL 8.0 Reference Manual, `mysqldump` — Using `--single-transaction` — https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html#option_mysqldump_single-transaction — documents exactly how and why the backup transaction stays open for the dump's full duration.
- **Blog:** Percona, "Understanding InnoDB's Purge Thread and History List Length" style operational posts on the Percona blog — https://www.percona.com/blog/ — search "history list length" for current, detailed operational deep-dives on diagnosing this in production.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — frames exactly this class of "background maintenance process starved by application behavior" incident as core DBRE territory, applicable across engines.
