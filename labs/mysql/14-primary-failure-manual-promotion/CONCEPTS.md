# Lab 14 — Concept: GTID Position as the Source of Truth for Promotion

## What's actually going on

MySQL's GTID (Global Transaction Identifier) mode assigns every
committed transaction a globally unique ID — `<source-uuid>:<sequence
number>` — at the moment it's written to the primary's binary log.
Every replica tracks two GTID sets: `Retrieved_Gtid_Set` (transactions
it has received and written to its relay log) and `Executed_Gtid_Set`
(transactions it has actually applied). `@@GLOBAL.gtid_executed`
exposes the executed set directly, and it's a complete, comparable
summary of exactly how far a given server has gotten — which is what
makes it possible to answer "which of these two replicas is more
caught up" precisely, rather than by inference from row counts or
`SHOW REPLICA STATUS`'s `Seconds_Behind_Source` (which only reflects lag
on a replica that's *currently* connected and replicating — useless the
moment replication has been stopped, as in this lab).

`SOURCE_AUTO_POSITION=1` (the modern replacement for manually specifying
a binlog file and offset) uses exactly this GTID comparison at the
protocol level: when a replica connects, it tells the new source its own
`Executed_Gtid_Set`, and the source computes and streams only the
transactions the replica doesn't have yet. This is precisely why
re-pointing `replica-b` at the newly-promoted `replica-a` in the main
lab "just works" without any manual bookkeeping — as long as
`replica-b`'s GTID set really is a strict subset of `replica-a`'s.
Challenge A breaks exactly that assumption: once `replica-b` accepts an
independent write after promotion, its GTID history is no longer a
subset *or* a superset of `replica-a`'s — the two have genuinely
diverged, and no amount of auto-positioning can reconcile that, because
there is no single correct merged answer. The `AUTO_INCREMENT` primary
key collision is the concrete symptom, but the underlying problem is
that both nodes accepted writes as if they were "the" primary — this is
split brain in the most literal sense.

`RESET REPLICA ALL` (as opposed to just `STOP REPLICA`) is what actually
clears a server's stored connection configuration (source host,
credentials, position) — `STOP REPLICA` alone just pauses the threads
without forgetting where they were pointed, which is exactly why
Challenge B's `replica-b` resumed trying to reach the literal string
`primary` again: nothing had ever told it to forget that configuration,
so `START REPLICA` simply restarted the same (now-broken) connection
attempt.

## Where this shows up in the real world

Automated failover tooling (Orchestrator, MHA, group replication, or a
cloud provider's managed-MySQL failover) exists specifically to make
this GTID comparison and promotion sequence happen correctly and fast,
without a human in the loop making an error under pressure — which is
exactly the scenario this lab reproduces manually. Teams running MySQL
without automated failover (common for smaller deployments, or as a
deliberate choice to keep a human in the loop for such a consequential
decision) need this exact runbook memorized and rehearsed, because
during a real primary failure there usually isn't time to look up the
correct sequence of commands, and getting Step 4 wrong (Challenge A) or
skipping Step 5 (Challenge B) are both extremely common, well-documented
real incidents in MySQL operations — often discovered well after the
fact, when someone notices a "replica" that's actually been frozen and
silently stale for days or weeks.

## Go deeper

- **Website/docs:** MySQL 8.0 Reference Manual, Replication with Global Transaction Identifiers — https://dev.mysql.com/doc/refman/8.0/en/replication-gtids.html — the authoritative explanation of GTID sets, auto-positioning, and how replicas track them.
- **Website/docs:** MySQL 8.0 Reference Manual, `CHANGE REPLICATION SOURCE TO` — https://dev.mysql.com/doc/refman/8.0/en/change-replication-source-to.html — every option this lab uses, including `SOURCE_AUTO_POSITION`.
- **Website/docs:** MySQL 8.0 Reference Manual, `RESET REPLICA` — https://dev.mysql.com/doc/refman/8.0/en/reset-replica.html — the precise difference between `STOP REPLICA` and `RESET REPLICA ALL`.
- **Tool/docs:** Orchestrator (GitHub, openark/orchestrator) — https://github.com/openark/orchestrator — a widely-used real-world tool for exactly this: automated MySQL topology discovery and safe promotion during failures.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — covers failover/promotion runbooks and the human-process side of exactly this kind of incident.
