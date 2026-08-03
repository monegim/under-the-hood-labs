# Lab 5 — Solutions

## Challenge A — LOCK TABLES, not a transaction

**Check:**
```bash
mysql -uroot -prootpass -e "SHOW PROCESSLIST\G" | grep -B3 "Waiting for table metadata lock"
mysql -uroot -prootpass -e "
  SELECT ml.OBJECT_TABLE, ml.LOCK_TYPE, ml.LOCK_STATUS, t.PROCESSLIST_ID
  FROM performance_schema.metadata_locks ml
  JOIN performance_schema.threads t ON ml.OWNER_THREAD_ID = t.THREAD_ID
  WHERE ml.OBJECT_SCHEMA = 'appdb';
"
```
`ALTER TABLE orders ADD COLUMN priority INT;` is stuck in `Waiting for
table metadata lock`, same as the main lab. `metadata_locks` shows the
`LOCK TABLES orders READ;` session holding a granted `SHARED_READ` (table)
lock, running `SELECT SLEEP(120)`.

**Diagnosis:** the mechanism holding the metadata lock is different this
time — there's no open transaction at all (`LOCK TABLES` is its own
locking construct, independent of `BEGIN`/`COMMIT`), but the *effect* on
MDL is the same: any session holding an explicit table lock, or sitting
inside an uncommitted transaction that has touched the table, blocks
`ALTER TABLE`'s exclusive metadata lock request identically. MDL doesn't
care *why* a session is holding a lock on the table, only that it is.

**Fix:** identical mechanism, same fix:
```bash
mysql -uroot -prootpass -e "
  SELECT id FROM information_schema.processlist WHERE info LIKE '%SLEEP(120)%';
"
mysql -uroot -prootpass -e "KILL <id>;"
```
Killing the session releases the `LOCK TABLES` lock (an explicit `UNLOCK
TABLES` would too, if the session were reachable), the `ALTER` proceeds.

**Lesson:** don't assume "metadata lock incident" always means "someone
forgot to commit." `LOCK TABLES`, a long-running `SELECT` under `REPEATABLE
READ`, a pending `ALTER` on the same table from another session, and even
a stuck `mysqldump` (which takes read locks by default in some modes) can
all produce the identical `Waiting for table metadata lock` symptom.
`performance_schema.metadata_locks` is what tells you which *kind* of
holder you're actually dealing with.

---

## Challenge B — a server-side sleep finishing into a dead client

**Check:**
```bash
mysql -uroot -prootpass -e "SHOW PROCESSLIST\G"
```
Early on (still inside the 300s `SLEEP`), this looks identical to the main
lab — `State: User sleep`. Wait for the 300 seconds to elapse, then check
again: the session no longer shows `User sleep` — `Command`/`State` shift
to something like an empty state or `Sending to client` (mysqld has
finished executing and is trying to write results back over a socket
nobody is reading, because the client process is frozen with `SIGSTOP`),
and the transaction is still open, its metadata lock still held. `ps` on
the host confirms the client process is in state `T` (stopped), not
running and not gone.

**Diagnosis:** this is a meaningfully different failure than the main
lab's, even though the MDL symptom looks the same: in the main lab, the
session is actively, deliberately holding the lock while a real (if
pointless) statement executes. Here, the SQL work is already done —
what's actually stuck is the TCP connection itself, because the process
on the other end can't drain its socket buffer. From MySQL's side alone,
this can be indistinguishable from a genuinely hung network path, a
client on a host that's crashed, or a container that got OOM-frozen —
`SHOW PROCESSLIST`'s `Time` column keeps climbing exactly the same way in
every one of those cases.

**Fix:**
```bash
mysql -uroot -prootpass -e "KILL <id>;"
```
`KILL` still works — and this is the important point. It operates
entirely on the server side: it terminates mysqld's thread for that
connection and forces a rollback, regardless of whether the client
process on the other end is frozen, crashed, or unreachable. You do not
need the client to cooperate, notice, or even still exist.

**Lesson:** a session stuck holding an MDL doesn't require a live,
well-behaved client on the other end — a frozen process, a dead
container, or a severed network path can hold a lock open just as
effectively as an app that legitimately forgot to commit, and for exactly
as long as nobody kills it server-side. This is why blindly waiting
"in case the client finishes on its own" is often the wrong instinct once
you've confirmed a session has been sitting in `Waiting for table
metadata lock` (or holding one) far longer than any legitimate query
should — `KILL` from the server side is safe and effective either way.
