# Lab 14 — Solutions

## Challenge A — promoting the stale replica breaks replication for real

**Check:**
```bash
docker exec lab14-replica-a mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" | grep -A1 Last_SQL_Error
```
```
Last_SQL_Error: ... Could not execute Write_rows event on table appdb.orders;
Duplicate entry '3' for key 'orders.PRIMARY', Error_code: 1062 ...
```
`Replica_SQL_Running` is `No` — replication has stopped entirely, not
just fallen behind.

**Diagnosis:** `orders.id` is `AUTO_INCREMENT`. On `replica-a`, the
table already had rows `id=1..4` (including the two rows only it ever
received). On `replica-b` — promoted while stale, with only `id=1..2` —
the very next auto-generated ID for a new row was `3`. That new row
replicated fine to nobody at first (there was no follower yet), but the
moment `replica-a` was pointed at `replica-b` and tried to apply that
same write, `replica-a` already had its *own*, different row with
`id=3` (`final-order-1`) — a genuine primary-key collision, not a
GTID-tracking issue. This is exactly what "split brain" costs in
practice: it's not abstract data loss, it's a concrete, mechanical
failure the moment the two divergent histories try to merge.

**Fix:** there's no clean automatic reconciliation here — the two rows
with colliding IDs are genuinely different data that both exist. In
practice this means manually inspecting both versions of the colliding
row(s), deciding what the correct final state is, and either skipping
the conflicting transaction (`SET GLOBAL sql_replica_skip_counter = 1;
START REPLICA;`, accepting that specific write is lost) or fixing the
data by hand before resuming replication — there is no flag that safely
automates this decision for you.

**Lesson:** the entire point of Steps 2-3 (checking row counts, then
GTIDs) is to make this exact failure impossible to reach by construction
— verify which replica is actually ahead *before* promoting, because
once two nodes have both accepted independent writes since diverging,
merging them is a manual, lossy, error-prone process, not a command.

---

## Challenge B — a correct promotion that's only half done

**Check:**
```bash
docker exec lab14-replica-b mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" | grep -E "Source_Host|Last_IO_Error"
```
```
Source_Host: primary
Last_IO_Error: Error connecting to source 'repl@primary:3306'. ... Unknown MySQL server host 'primary' (-2)
```

**Diagnosis:** `replica-b`'s replication configuration was never
touched — it's still configured to look for a host named `primary`,
which no longer exists. `START REPLICA` restarted its IO thread using
that stale configuration, which now fails to resolve/connect and
retries forever (once every 60 seconds, up to 86,400 times — roughly two
months). `replica-b`'s data is frozen at whatever it had before the
promotion, permanently, and nothing about this state is loud: the
container is healthy, `mysqld` is up, `SHOW REPLICA STATUS` returns
data normally — you have to actually read `Replica_IO_Running` (stuck
on `Connecting`, never `Yes`) and `Last_IO_Error` to notice anything is
wrong at all.

**Fix:** finish the promotion — re-point `replica-b` at the actual new
primary:
```bash
docker exec lab14-replica-b mysql -uroot -prootpass -e "
  STOP REPLICA;
  RESET REPLICA ALL;
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='replica-a',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"
```

**Lesson:** Challenge A fails loudly and immediately — replication stops
outright with an error impossible to miss. This failure mode is the
opposite: everything *looks* fine, the replica is "up," and the only
symptom is data silently going stale forever, which is far more likely
to go unnoticed until someone tries to read from `replica-b` (or
promotes it *again*, in a future incident, without realizing it's been
frozen for weeks) and gets wrong answers. A promotion runbook isn't
finished when the new primary accepts writes — it's finished when every
other node in the topology has been explicitly re-pointed and verified,
one by one.
