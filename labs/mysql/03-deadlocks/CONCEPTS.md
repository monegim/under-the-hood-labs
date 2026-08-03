# Lab 3 — Concept: Deadlocks Are Expected Behavior, Not a Bug

## What's actually going on

InnoDB is a row-locking engine: a transaction that modifies a row takes an
exclusive lock on it that's held until `COMMIT` or `ROLLBACK`, and any
other transaction wanting to modify (or, depending on isolation level,
even read with `FOR UPDATE`) that same row has to wait. This is exactly
how it should work — it's what makes concurrent transactions safe. The
problem arises only when two transactions each hold a lock the other one
needs: transaction A holds row 1 and wants row 2; transaction B holds row
2 and wants row 1. Neither can proceed, and neither ever will on its own —
this is a genuine circular wait, not a slow query that will eventually
finish. InnoDB runs a **deadlock detection algorithm** that actively walks
the wait-for graph (which transaction is waiting on which) looking for
cycles; the moment it finds one, it immediately picks a victim (generally
the transaction that has done the least work, measured by the number of
rows it has modified, since that one is "cheaper" to discard) and forces
that transaction to roll back with error 1213 (`SQLSTATE 40001`,
`ER_LOCK_DEADLOCK`). This happens in milliseconds — deadlock detection is
not the same mechanism as `innodb_lock_wait_timeout`, which is a much
longer fallback for the ordinary case of one transaction simply waiting
its turn (no cycle, just a queue) for longer than is reasonable.

`SHOW ENGINE INNODB STATUS`'s `LATEST DETECTED DEADLOCK` section is
InnoDB's own record of the last cycle it broke: for each of the two
transactions it directly compared, it prints the statement that was
running, the lock(s) it already held, and the lock it was waiting for
(`*** WAITING FOR THIS LOCK TO BE GRANTED`) — followed by which one it
chose to roll back. Reading this section correctly means matching up
*which row* each side holds against *which row* each side wants; the
cycle is the pattern where A's "waiting for" lock is exactly the lock B's
"holds" section lists, and vice versa. This lab's main scenario makes that
pattern as literal as possible: transaction A holds `id=1`'s row lock and
waits for `id=2`; transaction B holds `id=2`'s row lock and waits for
`id=1`. Challenge A shows the same shape arising from ordinary `INSERT`
statements, because inserting into a `UNIQUE`-indexed column takes an
implicit lock on the gap/index position being inserted into (needed to
enforce the uniqueness constraint against concurrent inserters) — the same
kind of "I hold this locked position, I want that one" cycle, just without
an explicit row existing yet. Challenge B stretches the same mechanism to
three participants, which matters because `SHOW ENGINE INNODB STATUS`
always prints exactly two transaction blocks regardless of how long the
actual cycle is — `performance_schema.data_lock_waits` is the tool that
shows the true, arbitrarily-long wait-for graph.

Because a deadlock always ends with one transaction rolled back — its
changes fully undone, as if it never ran — the only correct application-
level response is to catch that specific error and **retry the entire
transaction from the beginning**. This is different from most other
errors an app might see from MySQL: it isn't a bug, it isn't bad input,
and retrying is not a band-aid — it is the documented, intended way to
handle it, because InnoDB guarantees the rolled-back transaction's data
was never partially applied. Separately, and just as importantly: teams
that see repeated deadlocks between the same two code paths should fix the
*lock acquisition order* at the code or schema level (e.g., always update
rows sorted by primary key, or always insert in a canonical order) — this
doesn't make deadlocks impossible everywhere, but it eliminates the
specific recurring pattern, reducing how often the retry path even needs
to fire.

## Where this shows up in the real world

Any application with more than one code path that can touch the same two
(or more) rows in different orders will eventually deadlock under enough
concurrency — this is completely normal for busy OLTP workloads (funds
transfers, inventory decrements, any "update two related rows" pattern) and
is not, by itself, a sign anything is misconfigured. The actual incident is
almost always "the app doesn't retry on 1213" — surfacing as sporadic
failed requests, silently-dropped writes, or user-visible 500s that
correlate with concurrent traffic and vanish under low load, which makes
them notoriously hard to reproduce on demand outside of a deliberately
concurrent lab like this one. Teams running high-throughput transactional
workloads often add automatic retry-with-backoff specifically keyed on
`SQLSTATE 40001`/error 1213 as a standard piece of their data access layer,
precisely because it is expected to happen under load, not exceptional.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks.html — deadlock detection mechanics and how to read `SHOW ENGINE INNODB STATUS`'s deadlock section.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html — record locks, gap locks, and next-key locks, including why plain `INSERT` against a unique index takes more than "just a row lock."
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks-handling.html — the documented app-level guidance to retry transactions that fail with `ER_LOCK_DEADLOCK`.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — InnoDB locking internals and deadlock diagnosis in production workloads.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — frequent deep-dives on reading real deadlock graphs from production incidents.
