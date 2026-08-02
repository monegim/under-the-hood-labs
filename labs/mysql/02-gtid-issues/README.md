# Lab 2 — GTID Errant Transaction Halts Replication

## Objective
Create a real "errant transaction" — a write committed directly on a
replica instead of the primary — and watch GTID-based replication halt with
a conflict that `START REPLICA` alone cannot fix. Learn to read the
GTID-specific fields in `SHOW REPLICA STATUS`, compare `gtid_executed` sets
across servers, and use the `SET GTID_NEXT` skip technique correctly.

## Why this matters
GTID replication was built to make position-based replication's worst
failure mode (manually calculating binlog file/offset after a failover)
obsolete — but it introduces its own failure mode: the **errant
transaction**. Any transaction committed directly on a replica (a
well-meaning DBA "just fixing one row" during an outage, an application
that reconnected to the wrong host after a botched failover, a replica
that was briefly promoted and took writes before anyone realized) gets a
GTID stamped with *that server's own UUID* — a GTID the primary never
generated and will never send again. If that transaction's data later
collides with something the primary legitimately writes, the replica's SQL
thread stops cold. The single most common mistake here: restarting
replication and expecting it to move past the error, the way you might
with a transient network blip. With GTID auto-positioning, the source
resends the *exact same transaction* every time — restarting changes
nothing until you address the GTID itself.

## Prerequisites
- Docker + the `docker compose` plugin
- At least ~1GB free disk for two MySQL instances

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Bring up the incident
```bash
chmod +x setup.sh
./setup.sh
```
This script:
1. Starts `primary` and `replica` via `docker compose`, GTID-based
   replication (`SOURCE_AUTO_POSITION=1`).
2. Creates an `orders` table with an explicit integer primary key (not
   `AUTO_INCREMENT` — so the id collision below is deterministic, not
   a coincidence of two auto-increment counters drifting).
3. Seeds a few rows on the primary and lets them replicate cleanly.
4. `STOP REPLICA`s the replica (simulating a short maintenance window or
   a moment where this node was mistakenly treated as writable).
5. Writes **directly to the replica** as root (root bypasses
   `--read-only=ON` — this is exactly why `read_only` alone doesn't stop a
   privileged user or a misconfigured app from writing to a replica).
6. Writes more rows to the primary, including one that reuses the same id
   the direct replica write used.
7. `START REPLICA`s again.

## Step 2 — See the halt
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_SQL_Errno|Last_SQL_Error"
```
> Gotcha: `Replica_IO_Running` is `Yes` — the IO thread is fetching events
> fine. It's `Replica_SQL_Running` that's `No`. The GTID was received and
> queued in the relay log without any problem; it's *applying* it that
> fails. Don't let a healthy IO thread convince you replication is "mostly
> working."

## Step 3 — Confirm it's a duplicate-key error, not a network issue
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -A2 "Last_SQL_Error"
```
You should see `Error_code: 1062` (`Duplicate entry '9999' for key
'orders.PRIMARY'`) and the GTID of the failing transaction.

## Step 4 — Prove restarting replication does not help
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "START REPLICA; SELECT SLEEP(2); SHOW REPLICA STATUS\G" \
  | grep -E "Replica_SQL_Running|Last_SQL_Errno"
```
Same error, every time. With `SOURCE_AUTO_POSITION=1`, the primary looks at
the replica's `gtid_executed` set, sees the failing GTID is not in it, and
sends that exact same transaction again. There is no "skip to the next
event" the way `SQL_SLAVE_SKIP_COUNTER` offered under position-based
replication — GTID mode disables that variable entirely.

## Step 5 — Find the errant transaction with GTID set comparison
```bash
docker exec lab02-primary mysql -uroot -prootpass -e "SELECT @@GLOBAL.gtid_executed\G"
docker exec lab02-replica mysql -uroot -prootpass -e "SELECT @@GLOBAL.gtid_executed\G"
```
The replica's `gtid_executed` contains one extra UUID:transaction-number
pair that the primary's does not — that's the errant transaction, stamped
with the **replica's own** `server_uuid`, not the primary's. You can
isolate it precisely with `GTID_SUBTRACT()`:
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "
  SELECT GTID_SUBTRACT(@@GLOBAL.gtid_executed,
    (SELECT gtid_executed FROM (SELECT '$(docker exec lab02-primary mysql -uroot -prootpass -N -e "SELECT @@GLOBAL.gtid_executed;")' AS gtid_executed) t)
  ) AS errant_gtids\G"
```

## Step 6 — Reconcile the data, then skip the GTID (don't just skip)
Skipping the GTID with `SET GTID_NEXT` tells MySQL "consider this
transaction already applied" — it does **not** apply the primary's version
of the row for you. If you skip first, the replica keeps its own stale
`written-directly-on-replica-by-mistake` row forever, silently diverged
from the primary. Reconcile first:
```bash
docker exec lab02-replica mysql -uroot -prootpass appdb -e "
  UPDATE orders SET data='the-real-order-9999-from-primary' WHERE id=9999;
"
```
Now tell the replica to treat the conflicting GTID as already executed,
as an empty transaction, using the primary's own GTID for that transaction
(read it out of `Last_SQL_Error` or `SHOW REPLICA STATUS` — it's the
`<source_uuid>:<n>` pair the SQL thread is stuck on):
```bash
SOURCE_UUID=$(docker exec lab02-primary mysql -uroot -prootpass -N -e "SELECT @@server_uuid;")
docker exec lab02-replica mysql -uroot -prootpass -e "
  STOP REPLICA;
  SET GTID_NEXT='${SOURCE_UUID}:6';
  BEGIN; COMMIT;
  SET GTID_NEXT='AUTOMATIC';
  START REPLICA;
"
```
> Gotcha: the transaction number (`:6` above) depends on how many
> transactions the primary has committed by the time you run this —
> read the actual number out of `Last_SQL_Error` rather than assuming it.

## Step 7 — Confirm recovery
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"
```
Both threads `Yes`, lag draining to `0`.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — an errant transaction that hasn't hurt anyone yet:**
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "STOP REPLICA;"
docker exec lab02-replica mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (id, data) VALUES (5555, 'another-direct-write-no-collision-yet');
"
docker exec lab02-replica mysql -uroot -prootpass -e "START REPLICA;"
```
This time replication does **not** halt — id `5555` was never used on the
primary, so nothing conflicts. Everything looks fine in `SHOW REPLICA
STATUS`. Using only GTID set comparison (no error to react to), prove this
replica now has an errant transaction sitting silently in its history, and
explain concretely what danger it poses if this replica is ever promoted
to primary during a future failover.

**Challenge B — binary logs purged out from under a lagging replica:**
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "STOP REPLICA;"
docker exec lab02-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (id, data) VALUES (6001,'x'),(6002,'x'),(6003,'x');
  FLUSH BINARY LOGS;
"
docker exec lab02-primary mysql -uroot -prootpass -e "
  SET GLOBAL binlog_expire_logs_seconds=1;
"
sleep 5
docker exec lab02-primary mysql -uroot -prootpass -e "FLUSH BINARY LOGS;"
docker exec lab02-replica mysql -uroot -prootpass -e "START REPLICA;"
```
A completely different GTID failure mode this time — check
`Last_IO_Errno`/`Last_IO_Error` on the replica. Diagnose what's missing,
why `gtid_purged` on the primary is now the relevant field (not
`gtid_executed`), and why this one genuinely has no in-place fix on the
existing replica.

See `solution.md` only after you've formed your own diagnosis.
