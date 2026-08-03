# Lab 35 — Idle in Transaction: One Session Blocks Everyone

## Objective
Reproduce a session that opens a transaction, takes a row lock, and then
just sits there — and learn to find and kill the exact blocking session
with `pg_stat_activity` and `pg_blocking_pids()` instead of guessing.

## Why this matters
A transaction that's `BEGIN`-ed but not yet committed or rolled back keeps
every lock it has acquired for as long as it stays open, whether or not
it's actively doing anything. "Idle in transaction" is Postgres's own name
for exactly this state, visible directly in `pg_stat_activity.state`. A
forgotten `COMMIT`, an application that opens a transaction and then waits
on a slow external call before finishing it, or a developer debugging in
a `psql` session with an open `BEGIN` are all the same shape of incident:
one connection, doing nothing, silently blocking every other query that
needs the same row (or table, for some lock types) — and the blocked
queries themselves give you almost no clue why, because from their
perspective they're just waiting.

## Prerequisites
- Docker + the `docker compose` plugin

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
1. Starts a single Postgres instance via `docker compose`.
2. Creates an `accounts` table with three rows.
3. Opens a session that runs `BEGIN; UPDATE accounts ... WHERE id = 1;`
   and then sits in `pg_sleep(300)` without committing — bounded to 5
   minutes so it self-resolves if you don't get to it, but long enough to
   diagnose and fix by hand.

## Step 2 — Reproduce the block
```bash
docker exec lab35-primary psql -U postgres -d appdb -c \
  "UPDATE accounts SET balance = balance + 50 WHERE id = 1;"
```
This hangs. It's waiting on a row lock held by the session from
`setup.sh`, and it will keep waiting until that transaction ends (commits,
rolls back, or gets killed) — Ctrl-C this in another terminal once you've
confirmed it hangs, or just let it wait while you diagnose in a separate
shell.

## Step 3 — Find the idle transaction
```bash
docker exec lab35-primary psql -U postgres -c "
  SELECT pid, state, now() - xact_start AS xact_age, query
  FROM pg_stat_activity
  WHERE state = 'idle in transaction';
"
```
> Gotcha: `state = 'idle in transaction'` means the session isn't running
> any query right now — but its transaction is still open, so every lock
> it already took is still held. `xact_start` (not `query_start`) is what
> tells you how long the transaction itself has been open.

## Step 4 — Confirm it's the actual blocker
```bash
docker exec lab35-primary psql -U postgres -c "
  SELECT pid, pg_blocking_pids(pid) AS blocked_by, query
  FROM pg_stat_activity
  WHERE cardinality(pg_blocking_pids(pid)) > 0;
"
```
`pg_blocking_pids()` (built into Postgres since 9.6) does the
lock-graph-walking for you — no manual self-join against `pg_locks`
needed. It returns exactly the PID(s) a given backend is waiting behind.

## Step 5 — Fix it
```bash
docker exec lab35-primary psql -U postgres -c \
  "SELECT pg_terminate_backend(<idle_pid>);"
```
(substitute the PID from Step 3). The blocked `UPDATE` from Step 2
completes immediately once the lock is released.

## Step 6 — Prevent it
```bash
docker exec lab35-primary psql -U postgres -c \
  "ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s'; SELECT pg_reload_conf();"
```
Any session that goes idle inside an open transaction for longer than
this will now be automatically terminated by Postgres itself, with an
error the client will actually see — no human needs to notice and run
`pg_terminate_backend()` by hand.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — actively running, not idle, and the timeout above won't save you:**
```bash
docker exec -d lab35-primary bash -c '
  psql -U postgres -d appdb -c "
    BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    SELECT pg_sleep(60) FROM generate_series(1,1);
    UPDATE accounts SET balance = balance - 10 WHERE id = 1;
    COMMIT;
  "
'
docker exec lab35-primary psql -U postgres -d appdb -c \
  "UPDATE accounts SET balance = balance + 5 WHERE id = 1;"
```
This blocks the same way as the main lab — but the blocking session's
`state` is `active`, not `idle in transaction`, the whole time. Check
whether `idle_in_transaction_session_timeout` from Step 6 does anything
for this case, and figure out what setting actually would have.

**Challenge B — a DDL statement queues up behind a reader, then everyone queues behind it:**
```bash
docker exec -d lab35-primary bash -c '
  psql -U postgres -d appdb -c "
    BEGIN;
    SELECT * FROM accounts;
    SELECT pg_sleep(45);
    COMMIT;
  "
'
sleep 1
docker exec -d lab35-primary psql -U postgres -d appdb -c \
  "ALTER TABLE accounts ADD COLUMN notes TEXT;"
sleep 1
docker exec lab35-primary psql -U postgres -d appdb -c \
  "SELECT balance FROM accounts WHERE id = 2;"
```
Even a plain `SELECT` on an unrelated row now hangs, despite nobody
holding a row-level lock on row 2. Check `pg_locks` (not just
`pg_stat_activity`) for both the `ALTER TABLE` and the final `SELECT`, and
figure out why an `ALTER TABLE` that's itself just waiting can still
block a read that has nothing to do with the column being added.

See `solution.md` only after you've formed your own diagnosis.
