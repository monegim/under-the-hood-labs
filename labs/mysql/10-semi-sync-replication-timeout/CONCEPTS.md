# Lab 10 — Concept: Semi-Sync Is a Timeout With a Bailout, Not a Guarantee

## What's actually going on

Plain (async) MySQL replication commits on the primary the moment the
transaction's redo/binlog data is durable locally — the replica finding
out about it is a completely separate, unsynchronized event that could
happen milliseconds or minutes later. That's fast, but it means a primary
crash immediately after a commit can lose that transaction from every
replica's point of view, because the replica never got the chance to
receive it. Semi-synchronous replication narrows that gap: after the
primary makes a transaction's binlog event available, it blocks the
client's commit from returning until at least one semi-sync-enabled
replica has ACKed that it received (not necessarily applied — just
received into its relay log) that event, or until
`rpl_semi_sync_source_timeout` milliseconds pass, whichever comes first.
This is a genuinely useful middle ground between async (fast, weaker
guarantee) and fully synchronous/group-commit-style replication (strong
guarantee, but commit latency is now hostage to the slowest/least
available replica on every single write) — but the timeout half of that
sentence is the part that bites people.

When the timeout fires because no replica ACKed in time, the primary does
not refuse the commit and does not error — refusing writes because a
replica is slow would turn a replication problem into an availability
outage, which is exactly the failure mode a lot of teams enabling
semi-sync are trying to avoid in the first place. Instead, MySQL commits
the transaction anyway, flips `Rpl_semi_sync_source_status` to `OFF`, and
every subsequent write behaves like plain async replication until some
replica successfully ACKs a transaction again (at which point status
flips back to `ON` automatically, no operator action needed). This design
prioritizes availability over durability by default, silently, at exactly
the moment durability is what you configured semi-sync to protect. The
status variable is the only live signal this happened;
`Rpl_semi_sync_source_no_tx` is the cumulative counter of how many
transactions fell into this path since the primary started.

The multi-replica case (Challenge B) adds a second, easy-to-miss subtlety:
`rpl_semi_sync_source_wait_no_slave` (default `ON`) means "any ONE
attached semi-sync replica ACKing is sufficient" — the primary doesn't
track or expose which replica ACKed which transaction. With more than one
semi-sync replica, "status is ON" tells you the aggregate mechanism is
functioning, not that a specific replica you might be depending on for
failover or DR is actually current. Getting a stronger per-replica
guarantee means either waiting for ALL attached replicas
(`rpl_semi_sync_source_wait_no_slave=OFF`, at the cost of commit latency
being gated on your slowest replica) or architecting a dedicated semi-sync
pair around the specific durability requirement instead of treating every
attached replica as interchangeable.

## Where this shows up in the real world

Teams enable semi-sync specifically for financial, inventory, or
compliance-sensitive workloads where "we might have silently lost a
committed write" is unacceptable — then run it for months without
alerting on `Rpl_semi_sync_source_status` or `..._no_tx`, because the
system never visibly breaks: commits keep succeeding, applications keep
working, and the only trace of a degradation event is a status variable
and a couple of log lines that nobody's dashboard surfaces. The failure
mode isn't a page — it's a false sense of security that only gets
discovered during a postmortem after an actual primary failure loses data
the team believed semi-sync had protected. This is a recurring theme
across DBRE durability mechanisms generally: a guarantee that degrades
gracefully under stress is good engineering, but it's only good OPERATIONS
if the degradation itself is monitored as closely as the steady state.

## Go deeper

- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — covers semi-sync replication mechanics and the durability/availability trade-offs in depth.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — the broader discipline of monitoring degraded-but-not-down states, which is exactly what a semi-sync fallback is.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-semisync.html — canonical reference for semi-sync configuration, the timeout/fallback behavior, and `rpl_semi_sync_source_wait_no_slave`.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — operational deep dives on semi-sync replication behavior and failure scenarios.
- **YouTube:** Percona — https://www.youtube.com/@percona — talks covering MySQL replication durability trade-offs.
