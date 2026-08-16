# Lab 08 — Concept: Logical Replication Apply Conflicts

## What's actually going on

Logical replication decodes committed transactions from the publisher's
write-ahead log and replays them against the subscriber as ordinary SQL
operations (`INSERT`/`UPDATE`/`DELETE`), applied by a dedicated
background process called the apply worker. Because it's replaying
*real* row-level operations rather than copying physical pages, it goes
through the exact same constraint checks any other write would — which
means a subscriber table that was never supposed to be written to
directly, but was anyway, can now genuinely conflict with what's
arriving from the publisher.

The apply worker processes one transaction at a time, in commit order,
and it's transactional itself: if applying a transaction fails partway
through, nothing from it is applied, the worker exits with an error, and
Postgres's background worker infrastructure restarts it after a short
delay (`wal_retrieve_retry_interval`, 5 seconds by default). The
restarted worker resumes from the exact same position and hits the exact
same conflict — because "the exact same position" isn't in-memory
state, it's tracked durably: a replication slot on the publisher marks
how far it's safe to have sent data, and a replication origin on the
subscriber marks how far that data has actually been applied. This is
precisely why restarting the subscriber (Challenge B) changes nothing —
the failure isn't in the worker process, it's in the data, and the
worker's job is specifically to keep retrying until that's resolved.

`ALTER SUBSCRIPTION ... SKIP (lsn = ...)` exists as an escape hatch for
exactly this stuck state — but it operates at transaction granularity,
not row granularity, because that's the unit the apply worker actually
processes. There's no built-in "skip just this one row and keep the
rest of the transaction" option, which is why Challenge A's fast fix
can silently discard more than the row that was actually in conflict.

## Where this shows up in the real world

Logical replication is commonly used for zero-downtime major-version
upgrades, selective table replication, and feeding downstream analytics
or search systems — all cases where the subscriber is meant to be
either read-only or independently managed. Conflicts show up whenever
that boundary gets violated: a script that "just this once" writes
directly to what's supposed to be a read replica, a failed-over
application that reconnects to the wrong side, or a subscriber that was
manually patched to fix one bad row and inadvertently created a new
collision. Because the failure mode is a silent, indefinite replication
stall rather than a loud outage, monitoring `pg_stat_subscription` for a
worker with a live PID (and comparing `latest_end_lsn` against the
publisher's current WAL position) is the standard way teams catch this
before "replication lag" quietly becomes "replication stopped."

## Go deeper

- **Website/docs:** PostgreSQL official docs, Logical Replication — https://www.postgresql.org/docs/current/logical-replication.html — the full mechanism: publications, subscriptions, apply workers, and conflict handling.
- **Website/docs:** PostgreSQL official docs, `ALTER SUBSCRIPTION` — https://www.postgresql.org/docs/current/sql-altersubscription.html — the authoritative reference for `SKIP`, `DISABLE`/`ENABLE`, and what each actually does to replication state.
- **Website/docs:** PostgreSQL official docs, Logical Replication Conflicts — https://www.postgresql.org/docs/current/logical-replication-conflicts.html — describes exactly this failure mode and the officially recommended resolution paths.
- **Blog:** PostgreSQL Wiki, "Logical Replication" — https://wiki.postgresql.org/wiki/Logical_Replication — community-maintained operational notes and gotchas beyond the core docs.
- **Blog:** Cybertec, "Handling conflicts in PostgreSQL logical replication" — https://www.cybertec-postgresql.com/en/postgresql-logical-replication-conflicts/ — a DBRE-focused walkthrough of diagnosing and resolving exactly this scenario.
