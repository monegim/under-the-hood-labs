# Lab 10 — Semi-Sync Replication Timeout: the Silent Fallback to Async

## Objective
Stand up semi-synchronous replication, freeze the replica to simulate it
going unreachable, watch the primary stall on the next commit for exactly
`rpl_semi_sync_source_timeout`, and then discover that it **silently
degrades to plain asynchronous replication** afterward instead of erroring
— and stays that way, with zero durability guarantee, until nobody's
watching would ever notice.

## Why this matters
The entire point of semi-sync replication is a stronger durability
promise than async: "don't tell the client their write is committed until
at least one replica has the data too." Teams turn it on specifically
because they need that guarantee — a payment ledger, an inventory count,
anything where losing a just-committed write on primary failover is
unacceptable. But semi-sync's failure mode isn't "refuse to commit" — it's
"wait up to a timeout, then fall back to async and keep going as if
nothing happened." Nothing crashes. No error surfaces to the application.
`SHOW STATUS` flips one value from `ON` to `OFF`, and unless something is
actively alerting on that specific variable, the team believes they have a
durability guarantee they've actually been silently running without —
sometimes for hours.

## Prerequisites
- Docker + the `docker compose` plugin
- At least ~1GB free disk and some free RAM for two MySQL instances

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
1. Starts `primary` and `replica` with GTID-based async replication first.
2. Installs the semi-sync plugins (`rpl_semi_sync_source` on the primary,
   `rpl_semi_sync_replica` on the replica).
3. Enables semi-sync on both sides and sets a deliberately short
   `rpl_semi_sync_source_timeout` of 3000ms (3 seconds) — real production
   values are usually higher, this is shortened so the lab doesn't require
   long waits.
4. Writes a few warmup rows to confirm semi-sync commits are actually
   working end to end.

## Step 2 — Confirm semi-sync is genuinely active
```bash
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';"
```
Should read `ON`. This is the variable that matters — having the plugin
*installed* and the variable *set to 1* does not by itself guarantee
semi-sync is actively enforcing anything; `Rpl_semi_sync_source_status`
reflects whether it's currently succeeding at getting ACKs, live.

```bash
docker exec lab10-primary mysql -uroot -prootpass -e "
  SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_yes_tx';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_no_tx';
"
```
`Rpl_semi_sync_source_clients` should show 1 (the replica). `..._yes_tx`
counts transactions that got their ACK in time; `..._no_tx` counts ones
that timed out and had to fall back — right now it should be 0.

## Step 3 — Make the replica go unreachable
```bash
docker pause lab10-replica
```
`docker pause` freezes the container's processes without closing the TCP
connection — from the primary's point of view this looks exactly like a
replica that's alive on the network but too overloaded, GC-paused, or
otherwise stuck to respond. This is a more realistic simulation of a real
"slow replica" incident than simply killing the container outright.

## Step 4 — Watch a write stall, then silently succeed anyway
```bash
time docker exec lab10-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (data) VALUES ('during-outage');
"
```
This commit takes roughly 3 seconds (the configured timeout) — the primary
is genuinely waiting for an ACK that will never come. Then it returns
success anyway. The application sees a normal, successful `INSERT`. No
error. No warning in the client. Nothing about this response tells you the
durability guarantee you configured wasn't honored for this write.

## Step 5 — Confirm the silent fallback
```bash
docker exec lab10-primary mysql -uroot -prootpass -e "
  SHOW STATUS LIKE 'Rpl_semi_sync_source_status';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_no_tx';
"
```
`Rpl_semi_sync_source_status` is now `OFF` — the primary has switched
itself to asynchronous replication. `Rpl_semi_sync_source_no_tx` has
incremented. Every write from this point forward commits exactly like
async replication always has — fast, and with no guarantee the replica
has (or ever will have) the data — but nothing forces anyone to notice
unless they're specifically watching this status variable.

> Gotcha: check the MySQL error log too —
> `docker logs lab10-primary 2>&1 | grep -i semi-sync` — the timeout and
> fallback ARE logged there. The problem isn't that MySQL hides this; it's
> that almost nobody has log-based alerting on this specific line, and a
> status variable flipping silently is easy to never look at.

## Step 6 — Recovery and the automatic (also silent) re-enable
```bash
docker unpause lab10-replica
sleep 3
docker exec lab10-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (data) VALUES ('after-recovery');
"
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';"
```
Once the replica is responsive again and ACKs a transaction, semi-sync
re-enables itself automatically — `Rpl_semi_sync_source_status` flips back
to `ON` with no manual intervention. This cuts both ways: it means you
don't have to manually re-arm semi-sync after a transient blip, but it
also means the ONLY record that you ran without your durability guarantee
for some window is `Rpl_semi_sync_source_no_tx`'s counter and whatever you
logged at the time — there's no persistent "we degraded from N to M" event
your monitoring gets pushed unless you built that alerting yourself.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the timeout window is a data-loss window, prove it:**
```bash
docker pause lab10-replica
docker exec lab10-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (data) VALUES ('promoted-during-outage');
"
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW MASTER STATUS\G"
# now simulate a primary failure and inspect what the replica actually has:
docker exec lab10-replica mysql -uroot -prootpass appdb -e "SELECT * FROM orders ORDER BY id DESC LIMIT 3;"
docker unpause lab10-replica
```
The row `'promoted-during-outage'` committed successfully on the primary
(after the ~3s stall) while the replica was frozen. Check whether the
replica has that row immediately after `docker unpause` versus after
giving replication a few seconds to catch up — and explain in your own
words what would have happened to that specific row if the primary had
actually died instead of just being paused, in the exact window between
Step 4's timeout firing and Step 6's replica coming back.

**Challenge B — multiple replicas, and "at least one ACK" isn't "this
specific replica ACKed":**
```bash
docker compose up -d --scale replica=1
docker run -d --name lab10-replica2 --network lab10_default \
  -e MYSQL_ROOT_PASSWORD=rootpass -e MYSQL_DATABASE=appdb \
  mysql:8.0 --server-id=3 --log-bin=mysql-bin --binlog-format=ROW \
  --gtid-mode=ON --enforce-gtid-consistency=ON --relay-log=relay-bin --read-only=ON
sleep 15
docker exec lab10-replica2 mysql -uroot -prootpass -e "
  INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_slave.so';
  CHANGE REPLICATION SOURCE TO SOURCE_HOST='primary', SOURCE_USER='repl', SOURCE_PASSWORD='replpass', SOURCE_AUTO_POSITION=1;
  SET GLOBAL rpl_semi_sync_replica_enabled = 1;
  START REPLICA;
"
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';"
docker pause lab10-replica2
docker exec lab10-primary mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('two-replica-test');"
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';"
docker unpause lab10-replica2
```
With two semi-sync replicas attached, freeze only ONE of them and write
again. `rpl_semi_sync_source_wait_no_slave` (default `ON`) means the
primary only needs **any one** replica to ACK, not all of them. Figure out
whether this write stalled or committed immediately, what that implies
about which specific replica(s) are guaranteed to have a given write when
`Rpl_semi_sync_source_status` is `ON` with more than one replica attached,
and why "semi-sync is ON" is a weaker statement than it sounds once you
have more than one replica in the topology.

See `solution.md` only after you've formed your own diagnosis.
