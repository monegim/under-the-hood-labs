# Lab 5 — A Forgotten Transaction Blocks an Unrelated ALTER (and Everything Behind It)

## Objective
Reproduce a long-running (idle-in-transaction-shaped) transaction holding
a metadata lock (MDL) on a table, watch a completely unrelated `ALTER
TABLE` get stuck waiting for it, and then watch ordinary `SELECT`
statements against that same table pile up **behind the ALTER** — even
though those selects would have been perfectly fine running against the
original table on their own.

## Why this matters
"A simple `ALTER TABLE` took down the whole table" is a deceptively scary
incident, because the ALTER itself is usually not the problem — it's
stuck waiting, doing nothing, for a lock held by some completely unrelated
session that forgot to `COMMIT` or `ROLLBACK`. What makes this worse than
an ordinary blocked query: MySQL's metadata lock subsystem queues
requests **fairly** to keep DDL from starving forever behind a constant
stream of new reads/writes — which means once your ALTER is queued
waiting for the lock, every subsequent statement against that table,
including plain `SELECT`s that don't conflict with anything, gets queued
behind the ALTER too. One forgotten `COMMIT` can silently freeze an entire
table's traffic.

## Prerequisites
- Ubuntu VM, sudo access
- `mysql-server` (installed by `setup.sh`)

Check first:
```bash
uname -a
which mysql
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This script:
1. Creates an `orders` table.
2. Enables the `wait/lock/metadata/sql/mdl` `performance_schema`
   instrument (off by default in stock MySQL 8.0).
3. Starts a transaction that touches `orders` and then never commits
   (bounded at 5 minutes, self-terminating) — simulating an app or report
   script that opened a transaction and forgot to close it.
4. Fires an `ALTER TABLE orders ADD COLUMN notes ...` in the background.
5. Fires three ordinary `SELECT COUNT(*) FROM orders;` queries right after.

## Step 2 — See the pileup
```bash
mysql -uroot -prootpass -e "SHOW PROCESSLIST\G"
```
> Gotcha: look at the `State` column, not `Command`. The stuck sessions
> show `State: Waiting for table metadata lock` — a completely different
> wait reason from an ordinary row-lock wait (`Waiting for this lock` in
> `SHOW ENGINE INNODB STATUS`) or I/O wait. This one has nothing to do
> with row-level contention at all.

## Step 3 — Confirm which session is actually holding the lock
`SHOW PROCESSLIST` shows you who's *waiting*, not who's *holding*.
`performance_schema.metadata_locks` shows both:
```bash
mysql -uroot -prootpass -e "
  SELECT ml.OBJECT_TABLE, ml.LOCK_TYPE, ml.LOCK_STATUS, t.PROCESSLIST_ID, t.PROCESSLIST_STATE
  FROM performance_schema.metadata_locks ml
  JOIN performance_schema.threads t ON ml.OWNER_THREAD_ID = t.THREAD_ID
  WHERE ml.OBJECT_SCHEMA = 'appdb';
"
```
One row shows `LOCK_STATUS: GRANTED` with `LOCK_TYPE: SHARED_WRITE` (or
similar) — that's the long-running transaction, still holding its lock
because it never committed. The rest show `LOCK_STATUS: PENDING` — the
`ALTER` waiting for `EXCLUSIVE`, and every query behind it.

## Step 4 — Confirm the queue-behind-DDL behavior specifically
```bash
mysql -uroot -prootpass -e "SHOW PROCESSLIST\G" | grep -B2 "Waiting for table metadata lock"
```
Notice the plain `SELECT COUNT(*) FROM orders;` sessions are ALSO stuck in
`Waiting for table metadata lock`, not running — even though a `SELECT`
and the long-running transaction's `SELECT` don't actually conflict with
each other. They're queued behind the pending `ALTER`, not behind the
original transaction.

## Step 5 — Fix it: kill the session that never committed
```bash
mysql -uroot -prootpass -e "
  SELECT id, time, LEFT(info,60) AS info
  FROM information_schema.processlist
  WHERE command != 'Sleep' AND time > 5
  ORDER BY time DESC;
"
```
Find the connection id of the long-running transaction (the one that's
been open longest and is running `DO SLEEP(...)`), then:
```bash
mysql -uroot -prootpass -e "KILL <id>;"
```
Killing it releases its metadata lock, which lets the `ALTER` proceed —
which then lets every queued `SELECT` behind it proceed too.

## Step 6 — Confirm recovery
```bash
mysql -uroot -prootpass -e "SHOW PROCESSLIST\G"
mysql -uroot -prootpass appdb -e "DESCRIBE orders;"
```
No more `Waiting for table metadata lock` states, and `orders` now has
the `notes` column.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the blocker isn't a transaction at all:**
```bash
mysql -uroot -prootpass appdb -e "
  LOCK TABLES orders READ;
  SELECT SLEEP(120);
" > /tmp/lab05-locktables.log 2>&1 &
sleep 1
mysql -uroot -prootpass appdb -e "ALTER TABLE orders ADD COLUMN priority INT;" > /tmp/lab05-alter2.log 2>&1 &
```
Same symptom (`ALTER` stuck on `Waiting for table metadata lock`), but
this session was never in a transaction — check `performance_schema
.metadata_locks` and `SHOW PROCESSLIST` for it specifically. What's
different about how this lock was taken versus the main lab's forgotten
`COMMIT`, and does the fix (killing the session) still work the same way?

**Challenge B — the blocker is a frozen client, not a sleeping query:**
```bash
mysql -uroot -prootpass appdb -e "
  BEGIN;
  SELECT * FROM orders LIMIT 1;
  DO SLEEP(300);
  COMMIT;
" &
PID=$!
sleep 2
kill -STOP $PID 2>/dev/null || true
# (cleanup later: kill -CONT $PID; kill -9 $PID)
```
Same `DO SLEEP(300)` shape as the main lab's transaction — except this
time the OS process running the `mysql` client itself gets frozen
(`SIGSTOP`) partway through, not just executing a slow server-side
statement. The SQL `SLEEP` still runs to completion on the **server**
regardless of what the client process is doing, but once it's done and
mysqld tries to hand results back to a client that can no longer read its
socket, the connection can hang indefinitely — well past 300 seconds —
with nobody on the client side left to send `COMMIT` or even notice.
Using only `SHOW PROCESSLIST`/`performance_schema`, figure out how to
tell this case apart from the main lab's plain `DO SLEEP(300)`, and
whether `KILL <id>;` still works when the client process itself is
unreachable (frozen, crashed, or on a host that's gone).

See `solution.md` only after you've formed your own diagnosis.
