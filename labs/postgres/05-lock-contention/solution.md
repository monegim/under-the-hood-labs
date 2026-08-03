# Lab 35 — Solutions

## Challenge A — actively running, not idle, and the wrong timeout

**Check:**
```bash
docker exec lab35-primary psql -U postgres -c "
  SELECT pid, state, now() - query_start AS query_age, query
  FROM pg_stat_activity WHERE datname = 'appdb' AND state <> 'idle';
"
```
The blocking session shows `state = active` for the entire 60 seconds —
never `idle in transaction`. `idle_in_transaction_session_timeout` from
the main lab's Step 6 does nothing here, because it only terminates
sessions that are idle inside an open transaction; this session is always
busy running something (`SELECT ... FOR UPDATE`, then a sleep expressed
as an actual running query via `generate_series`, then the `UPDATE`) —
Postgres has no way to know it's "wasting time" from the state alone.

**Diagnosis:** `SELECT ... FOR UPDATE` takes a row lock immediately and
holds it for the rest of the transaction, exactly like the main lab — the
difference is purely about which GUC would have prevented the long hold.
A session that's continuously active, even if what it's actively doing is
pointless or slow, is not something `idle_in_transaction_session_timeout`
can touch.

**Fix:** same mechanism as the main lab — find and terminate the actual
backend:
```bash
docker exec lab35-primary psql -U postgres -c \
  "SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;"
docker exec lab35-primary psql -U postgres -c "SELECT pg_terminate_backend(<pid>);"
```
The real prevention here is `statement_timeout` (caps how long any single
statement is allowed to run) rather than
`idle_in_transaction_session_timeout` — though note a single
`pg_sleep(60)`-style statement is itself the kind of thing `statement_timeout`
is designed to cut off; a transaction split across several shorter
statements with application-level delays between them (the more realistic
version of this problem) needs an application-level timeout/circuit
breaker instead, since Postgres has no visibility into what the client is
doing between statements once it's back to `idle in transaction`... which
loops back to the main lab's fix for that specific gap.

**Lesson:** "idle in transaction" and "long-running but active" are two
different failure modes that happen to produce the identical symptom
(a blocked query) and need two different settings to prevent
(`idle_in_transaction_session_timeout` vs `statement_timeout`). Check
`pg_stat_activity.state` before reaching for either one.

---

## Challenge B — a queued DDL statement blocks everyone behind it, not just the table it's changing

**Check:**
```bash
docker exec lab35-primary psql -U postgres -c "
  SELECT pid, state, wait_event_type, wait_event, query
  FROM pg_stat_activity WHERE datname = 'appdb' AND state <> 'idle';
"
docker exec lab35-primary psql -U postgres -c "
  SELECT pid, locktype, relation::regclass, mode, granted
  FROM pg_locks WHERE relation = 'accounts'::regclass;
"
```
`pg_locks` shows three rows against `accounts`: the original long `SELECT`
holding `AccessShareLock` (`granted = t`), the `ALTER TABLE` waiting on
`AccessExclusiveLock` (`granted = f`), and the final plain `SELECT` ALSO
waiting — on `AccessShareLock` (`granted = f`), even though
`AccessShareLock` doesn't conflict with the first session's
`AccessShareLock` at all.

**Diagnosis:** Postgres's lock manager grants locks fairly, in request
order, when there's a conflict anywhere in the queue — a new lock request
that would be compatible with every currently-*granted* lock still has to
wait if an earlier, still-*waiting* request for a conflicting lock mode is
ahead of it in the queue. Here: the long `SELECT` holds
`AccessShareLock`; the `ALTER TABLE` needs `AccessExclusiveLock`, which
conflicts with the held `AccessShareLock`, so it waits; the final
`SELECT`'s `AccessShareLock` request would be perfectly compatible with
the first session's lock, but because the `ALTER TABLE`'s conflicting
request is already queued ahead of it, the new `SELECT` queues behind the
`ALTER TABLE` too, rather than jumping ahead of it. This exists
specifically to prevent an exclusive-lock request from being starved
forever by a continuous stream of compatible shared-lock requests — but
the side effect is that one slow DDL statement against a busy table can
back up every subsequent query against that table, not just ones that
actually conflict with the DDL.

**Fix:** end the original long-running `SELECT`'s transaction so the
`ALTER TABLE` can acquire its lock and finish, which drains the whole
queue behind it:
```bash
docker exec lab35-primary psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query ILIKE 'SELECT * FROM accounts%';"
```
In production, the actual prevention is scheduling DDL against busy
tables carefully: run it with a short `lock_timeout` set so it fails fast
instead of queueing indefinitely (`SET lock_timeout = '2s';` before the
`ALTER TABLE`), and during low-traffic windows when long-running
`SELECT`s are less likely to already be in flight.

**Lesson:** `pg_stat_activity` alone won't show you this — it'll just
show several sessions "waiting," with no obvious reason a read-only
`SELECT` on an unrelated row should be blocked. `pg_locks`, checked for
BOTH granted and ungranted (`granted = f`) rows against the table, is what
reveals the queue order and explains why a completely unrelated read got
stuck behind a DDL statement that hasn't even run yet.
