# Incident 11 — Concept: Read-Your-Writes Consistency and Replication Lag

## What's actually going on

MySQL's default replication is asynchronous, and "asynchronous" here has
a very specific, load-bearing meaning: when a client `COMMIT`s a
transaction on the primary, the primary considers that transaction
durable and acknowledges the commit as soon as *its own* binlog write
hits disk — full stop, no waiting on any replica. The replica's I/O
thread then pulls that binlog event over the network at its own pace,
writes it to a local relay log, and a separate SQL/apply thread replays
it against the replica's actual tables, also at its own pace. Those two
threads running independently, on their own schedule, driven by
whatever resources the replica happens to have free at that moment, is
the entire mechanism — there is no step anywhere in this pipeline where
the primary checks "has the replica actually applied this yet" before
telling the client the write succeeded. Under a healthy, idle replica,
this whole pipeline typically completes in single-digit milliseconds,
which is why the gap is invisible almost all the time. It is still,
structurally, a real gap with no upper bound — it just usually happens
to be small.

This incident's combined-mechanism trick is making that usually-small
gap large and persistent by starving the replica's *disk*, not its
database — `reporting-job` never touches MySQL at all, it just runs
continuous, unrelated write I/O against a directory that happens to be
bind-mounted from the same underlying host disk as the replica's
datadir. The replica's SQL thread still has to fsync every applied
transaction to that same physically contended disk, so its apply rate
drops to whatever I/O bandwidth `reporting-job` leaves behind — the
replica falls seconds behind not because replication is misconfigured,
but because the disk underneath it is busy with something replication
knows nothing about. This is the identical mechanism to
`labs/mysql/01-replication-lag-io-contention` and Incident 04 (a shared
disk resource, not a database setting, is the actual bottleneck) — what's
different here is which symptom that lag produces on the *application*
side: instead of slow commits, it's a read landing on the stale side of
a replication gap, at an unpredictable moment, with nothing in any log
recording that it happened.

"Read-your-writes consistency" is the name for the specific guarantee
that's missing: a session should see its own write reflected in
subsequent reads from that same session. A primary/replica split where
writes go to the primary and reads go to a replica does not provide this
guarantee by default — it provides *eventual* consistency (the replica
will get there, on its own schedule), which is a completely different
and weaker promise. Neither MySQL nor the pattern of "scale reads with a
replica" is doing anything wrong here; the gap exists precisely because
nobody in the application code asked "does this particular read need
read-your-writes, and if so, which host can actually provide it right
now" — a question that has to be answered at the application/architecture
layer, because the database has no way to know which reads are
allowed to be stale and which aren't.

## Where this shows up in the real world

This is one of the single most common failure modes in any web
application that adds a read replica for scaling without an explicit
strategy for the read paths that need to see their own recent writes —
"I saved my settings and they reverted," "my comment disappeared then
came back," "I checked out but my cart looks empty" tickets are
frequently this exact mechanism, and they're notoriously hard to
reproduce on demand precisely because the lag window is usually tiny and
only becomes user-visible under load or contention. It's common enough
that managed database platforms (AWS RDS read replicas, Google Cloud
SQL read replicas) document it explicitly as "eventually consistent
reads" rather than treating it as an edge case, and MySQL's own
replication documentation is direct about async replication making no
durability promise on the replica side at all.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication.html — MySQL's own documentation of asynchronous replication as designed, expected behavior.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-semisync.html — semisynchronous replication, and specifically why it narrows this window without closing it (it only waits for the replica's I/O thread to receive the transaction, not for the SQL thread to apply it).
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — frames exactly this kind of architecture-level consistency trade-off as a first-class reliability concern, not just a database config detail.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — deep coverage of replication internals and the operational implications of read/write splitting.
- **Website/docs:** Brendan Gregg's site — https://www.brendangregg.com — the USE method (Utilization/Saturation/Errors), directly relevant to the "check the resource layer, not the database config" instinct this incident's investigation relies on.
