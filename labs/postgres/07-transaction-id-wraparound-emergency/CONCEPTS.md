# Lab 07 — Concept: Transaction ID Wraparound

## What's actually going on

Every row version Postgres stores is tagged with the ID of the
transaction that created it (`xmin`) and, once superseded, the
transaction that deleted or replaced it (`xmax`). These transaction IDs
are 32-bit and compared using modular ("circular") arithmetic — a
transaction ID is "in the past" or "in the future" relative to the
current counter only up to about 2 billion IDs of separation. If the
counter were allowed to advance past that without anything happening to
the old row versions still lying around, an old committed row could
suddenly appear to be written by a transaction that hasn't happened
yet — which, to an MVCC database, looks indistinguishable from that row
never having existed. This is the wraparound problem, and it's a
correctness/data-loss issue, not a performance one.

Postgres avoids this with *freezing*: once a row version is old enough
that every possible future transaction is guaranteed to see it as
already committed, `VACUUM` rewrites its `xmin` to a special sentinel
value (`FrozenTransactionId`) that's always considered "in the past,"
permanently removing that row from the wraparound calculation.
`autovacuum_freeze_max_age` sets the ceiling: once a table's
`age(relfrozenxid)` — the transaction-ID distance since its oldest
unfrozen row — crosses that value, Postgres schedules an *aggressive*
autovacuum on that table specifically to catch up, overriding
per-table `autovacuum_enabled = false` settings, because this one
override exists purely as a last-resort safety net. This lab lowers
`autovacuum_freeze_max_age` to 100000 — Postgres's actual enforced
minimum for the setting, not an arbitrary small number — because the
real default (200,000,000) would take hundreds of millions of
transactions to reach in a lab environment; the freezing mechanism
itself is identical either way.

What that safety net cannot do anything about is autovacuum being
disabled *entirely* — no daemon means nothing is watching any table's
age, aggressive or not. That's the actual failure mode this lab
reproduces, and it's also why the fix in Step 5 restarts the container
rather than trying a live-reload: `autovacuum` was set as a
command-line argument to `postgres`, which sits above `ALTER SYSTEM` in
Postgres's own configuration-precedence order (compiled default →
`postgresql.conf` → `postgresql.auto.conf` → command-line arguments →
per-session `SET`), so `pg_reload_conf()` genuinely cannot touch it —
verified directly in Challenge A.

## Where this shows up in the real world

The classic real-world trigger is a bulk load or migration where
autovacuum is deliberately disabled to avoid it competing for I/O with
the load, and then never re-enabled afterward — sometimes for months,
until `age(relfrozenxid)` on some large, rarely-queried table finally
crosses into emergency territory. Once a database's age gets close
enough to the actual 2-billion-transaction limit, Postgres stops
accepting new write transactions entirely (`ERROR: database is not
accepting commands to avoid wraparound data loss`) until an
administrator runs `VACUUM` by hand — at that point it's a full
production outage, not a warning in the logs. Monitoring
`age(relfrozenxid)` (or the aggregate `age(datfrozenxid)` per database)
against `autovacuum_freeze_max_age` is standard DBRE practice for
exactly this reason — by the time an application notices, the fix is
already an incident, not routine maintenance.

## Go deeper

- **Website/docs:** PostgreSQL official docs, Routine Vacuuming — https://www.postgresql.org/docs/current/routine-vacuuming.html — the authoritative explanation of freezing, `autovacuum_freeze_max_age`, and the wraparound-prevention mechanism, including the failure-mode warnings.
- **Website/docs:** PostgreSQL official docs, Preventing Transaction ID Wraparound Failures — https://www.postgresql.org/docs/current/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND — the specific subsection on what happens as a database approaches the hard limit.
- **Website/docs:** PostgreSQL official docs, Run-time Configuration — https://www.postgresql.org/docs/current/runtime-config-autovacuum.html — `autovacuum_freeze_max_age` and related GUCs with their valid ranges.
- **Blog:** Crunchy Data, "Managing Transaction ID Wraparound in PostgreSQL" — https://www.crunchydata.com/blog/managing-transaction-id-wraparound-in-postgresql — a DBRE-focused walkthrough of monitoring and responding to wraparound risk in production.
- **Blog:** Percona, "Transaction Wraparound and What To Do About It" — https://www.percona.com/blog/transaction-wraparound-in-postgresql/ — covers the long-running-transaction interaction with vacuum's freeze horizon in more depth.
