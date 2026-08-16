# Lab 14 — Primary Failure and Manual Promotion

## Objective
Lose a primary with two replicas that aren't equally caught up, promote
the correct one using GTID position (not a guess), re-point the other
replica at it, and verify the topology is fully healthy again — then
find out exactly what breaks when either step is done wrong.

## Why this matters
Losing a primary is the incident every replication topology exists to
survive, and "promote a replica" is the correct instinct — but *which*
replica, decided *how*, is the part that actually determines whether
this is a clean recovery or a second incident stacked on top of the
first. Two replicas of the same primary are not interchangeable the
moment either one falls even slightly behind, and MySQL gives you the
exact tool to tell them apart (`gtid_executed`) — the failure mode this
lab reproduces is skipping that check and promoting whichever replica
was simply "the designated backup" or easiest to reach.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This brings up a primary and two replicas (`replica-a`, `replica-b`)
under GTID-based replication, writes some baseline data, then
deliberately stops replication on `replica-b` before writing two more
rows on the primary — so only `replica-a` has them. It then stops the
primary container entirely, simulating a hard failure.

## Step 2 — Confirm the split
```bash
docker exec lab14-replica-a mysql -uroot -prootpass appdb -e "SELECT * FROM orders;"
docker exec lab14-replica-b mysql -uroot -prootpass appdb -e "SELECT * FROM orders;"
```
`replica-a` has 4 rows, `replica-b` has 2. Promoting the wrong one loses
data the moment anything writes to it.

## Step 3 — Confirm it with GTIDs, not just row counts
```bash
docker exec lab14-replica-a mysql -uroot -prootpass -e "SELECT @@GLOBAL.gtid_executed;"
docker exec lab14-replica-b mysql -uroot -prootpass -e "SELECT @@GLOBAL.gtid_executed;"
```
For the primary's own UUID in the set, `replica-a`'s range extends
further than `replica-b`'s — the same conclusion as Step 2, but this is
the check that scales to real schemas where "just compare row counts"
isn't meaningful.

## Step 4 — Promote the correct replica
```bash
docker exec lab14-replica-a mysql -uroot -prootpass -e "
  STOP REPLICA;
  RESET REPLICA ALL;
  SET GLOBAL read_only = OFF;
  SET GLOBAL super_read_only = OFF;
"
```
`RESET REPLICA ALL` clears its replication configuration entirely (so it
stops trying to reconnect to the dead primary); disabling `read_only`
and `super_read_only` is what actually makes it accept writes.

## Step 5 — Re-point the other replica at the new primary
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
`SOURCE_AUTO_POSITION=1` lets `replica-b` figure out for itself, via
GTIDs, exactly which transactions it's still missing from `replica-a` —
no manual binlog file/offset bookkeeping needed.

## Step 6 — Verify
```bash
./check.sh
```
Confirms the promoted replica is writable, the other one is actively
following it (not just configured to), and both agree on the data.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — promoting the stale replica breaks replication for real:**
```bash
./reset.sh
docker exec lab14-replica-b mysql -uroot -prootpass -e "
  STOP REPLICA;
  RESET REPLICA ALL;
  SET GLOBAL read_only = OFF;
  SET GLOBAL super_read_only = OFF;
"
docker exec lab14-replica-b mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (item) VALUES ('post-wrong-promotion-order');
"
docker exec lab14-replica-a mysql -uroot -prootpass -e "
  STOP REPLICA;
  RESET REPLICA ALL;
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='replica-b',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"
sleep 3
docker exec lab14-replica-a mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" | grep -E "Replica_SQL_Running|Last_SQL_Error"
```
Promote `replica-b` (the stale one) instead, write one new row to it,
then try to point `replica-a` (which has the two rows `replica-b` never
saw) at it as if it were the new primary. Replication doesn't just lag —
it stops outright with an error. Read the exact error text (`SHOW
REPLICA STATUS`'s `Last_SQL_Error`, or `docker logs lab14-replica-a`) and
explain precisely what collided and why `AUTO_INCREMENT` is the
mechanism that turned "we lost two rows" into "replication is now
broken."

**Challenge B — a correct promotion that's only half done:**
```bash
./reset.sh
docker exec lab14-replica-a mysql -uroot -prootpass -e "
  STOP REPLICA;
  RESET REPLICA ALL;
  SET GLOBAL read_only = OFF;
  SET GLOBAL super_read_only = OFF;
"
docker exec lab14-replica-a mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (item) VALUES ('post-promotion-1');
"
docker exec lab14-replica-b mysql -uroot -prootpass -e "START REPLICA;"
sleep 3
docker exec lab14-replica-b mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" | grep -E "Source_Host|Replica_IO_Running|Last_IO_Error"
```
This time you promoted the *correct* replica (`replica-a`) — but instead
of re-pointing `replica-b` at it, you just told `replica-b` to resume
replicating with its old (unchanged) configuration. Check what
`Source_Host` it's still trying to reach, and what `Last_IO_Error` says.
Nothing crashed, nothing alerted — explain why this failure mode is
specifically dangerous compared to Challenge A's, in terms of how
visible it is and how long it could go unnoticed.

See `solution.md` only after you've formed your own diagnosis.
