# Lab 2 — Concept: GTIDs Make Failover Easier and Errant Transactions Possible

## What's actually going on

Every MySQL transaction, when GTID mode is on, gets stamped with a
**global transaction identifier**: `source_uuid:transaction_number`, where
`source_uuid` is the `server_uuid` of whichever server *originally
committed* the transaction (not necessarily the server currently holding
it) and `transaction_number` is a strictly increasing counter scoped to
that UUID. A replica's `gtid_executed` system variable is the complete set
of every GTID it has ever applied, from any source, expressed as
UUID:ranges (e.g. `3E11FA47-71CA-11E1-9E33-C80AA9429562:1-5`). This is the
entire point of GTID-based replication: instead of a replica remembering
"binlog file X, byte offset Y" (which only makes sense relative to one
specific primary's binlog history, and becomes meaningless the moment you
fail over to a different server), it remembers a set of *transaction
identities* that mean the same thing no matter which server they came
from. `CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION=1` uses this:
the replica tells its new source "here's my `gtid_executed`, send me
anything you have that I don't," and the source computes the difference
itself. No more manually calculating binlog coordinates after a failover —
which used to be one of the most error-prone parts of a MySQL incident.

The trade-off: because a GTID's UUID reflects *whichever server first
committed it*, any transaction executed directly on a replica — not
relayed from a primary — gets stamped with that replica's own
`server_uuid`. MySQL has no way to distinguish "a legitimate write that
happened to land here" from "a mistake"; a GTID is a GTID. This lab's
`INSERT ... (9999, ...)` run directly against the replica became part of
that replica's permanent `gtid_executed` set the instant it committed,
indistinguishable at the protocol level from anything the primary itself
might have generated. This is exactly what the MySQL documentation calls
an **errant transaction**: a GTID present on one server's `gtid_executed`
that is not part of the accepted, source-of-truth transaction history.

The failure this lab reproduces — the SQL thread stopping with a
duplicate-key error — is really a downstream *symptom* of the errant
transaction, not the errant transaction itself; plenty of errant
transactions (Challenge A) sit completely silently until something
collides with them or a failover promotes that data into the wider
topology. When a collision does happen, restarting replication is a
reflex left over from position-based replication, where a transient issue
(network blip, a replica that briefly fell behind) really could be
resolved by just reconnecting. Under GTID auto-positioning, the source
looks at the replica's `gtid_executed`, sees the failing transaction's
GTID is still missing from it (because the SQL thread never successfully
applied it — the relay-logged copy is sitting there failing, and failing
again, and again), and resends the identical transaction every single
time. There is no forward-skip counter (`SQL_SLAVE_SKIP_COUNTER`, the old
position-based escape hatch) under GTID mode — it's explicitly disabled,
because "skip N events" doesn't mean anything when replication is
positioned by transaction identity rather than by counting events.

The actual fix, `SET GTID_NEXT='<uuid>:<n>'; BEGIN; COMMIT; SET
GTID_NEXT='AUTOMATIC';`, works by having the replica commit an **empty
transaction** under that exact GTID — which adds it to `gtid_executed`
without applying any of the real transaction's data changes. This
satisfies the source's auto-positioning logic ("you have this GTID now,
I won't resend it") without ever running the statement that failed. It is
a surgical tool, not a cleanup tool: it does nothing to reconcile whatever
data mismatch caused the conflict in the first place — that has to be
done manually, and *before* skipping, or the replica silently keeps
diverged data forever with no further errors to warn you.

## Where this shows up in the real world

Errant transactions are the single most common GTID-specific incident,
and they almost always trace back to one of two root causes: a manual
"quick fix" applied directly to a replica during an outage (arguably the
most common — someone SSHes in and runs an UPDATE against what they
believe, sometimes incorrectly, is the primary), or a failover/promotion
process that isn't fully automated and leaves a brief window where more
than one node accepts writes. Tools like Orchestrator and MySQL Router
exist specifically to make failover atomic enough that this window
effectively can't happen; a large fraction of real GTID incident
postmortems come from environments doing failover by hand, or with
partially-automated tooling that has a gap. The purged-binlog failure mode
in Challenge B is the other classic GTID incident: overly aggressive
`binlog_expire_logs_seconds`/`expire_logs_days` settings combined with a
replica that's offline or lagging for maintenance longer than expected.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-gtids.html — GTID concepts, `gtid_executed`, `gtid_purged`, and auto-positioning mechanics.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-gtids-failover.html — errant transactions, detecting them before failover, and why they matter specifically during promotion.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/glossary.html#glos_gtid — canonical GTID definition and terminology.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — GTID replication internals and failover mechanics in depth.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors — the operational discipline of safe failover and why manual replica writes during an incident are so dangerous.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — recurring coverage of errant-transaction incidents and the `GTID_NEXT` skip technique in practice.
