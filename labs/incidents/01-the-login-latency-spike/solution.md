# Incident 01 — Solution

## Root cause

MySQL's `max_connections` is capped at 30 (`docker-compose.yml`, `command:
--max-connections=30`). The `worker` container - a "loyalty-points
reconciler" background job - opens 26 direct connections to MySQL and
holds each one busy running a slow reconciliation query (stood in for
here by `SELECT SLEEP(20)`) in a tight forever-loop, immediately
reclaiming any connection the instant it frees up. That leaves roughly 4
of MySQL's 30 connection slots for everything else on the box, including
the login service's own connection pool (`DB_POOL_SIZE=10`).

Under normal login traffic this is invisible - there's usually a free
slot. Under any real concurrency, most login requests can't get a MySQL
connection at all. The login service doesn't fail instantly, though: it
retries getting a pool connection up to 3 times with a 400ms delay
between attempts (`app.py`, `get_connection_with_retry()`). Requests that
eventually find a free slot succeed, but only after ~1 second of retrying
- that's the 8ms→1.2s latency. Requests that exhaust all 3 retries return
`503` - that's the error rate. None of this touches the CPU or leaks
memory; the app and MySQL are simply queuing on a connection budget that
doesn't exist.

## Why it happened

The reconciler was written as a quick batch script: open a connection,
do the work, loop - no pooling, no cap on concurrency, no coordination
with anything else talking to the same database. Nothing about it is
individually wrong-looking in a code review. The bug only exists at the
level of "how many total connections does this database allow, and who
else is drawing from that same budget" - a question that has no natural
place to be asked when each service is reviewed in isolation.

## Why the obvious fixes don't work

- **Restarting the app** (`docker restart incident01-app`): the pool
  reconnects into exactly the same starved `max_connections` budget the
  worker is still holding. Latency comes right back within seconds.
- **Scaling the app to more replicas**: makes it strictly worse - more
  replicas means more connection-pool consumers competing for the same
  ~4 free slots, not more capacity.
- **Increasing the app's own pool size**: doesn't help, because the
  ceiling isn't the app's pool - it's MySQL's server-side
  `max_connections`. A bigger app-side pool just means more of the app's
  *own* connection attempts get refused too.
- **Throwing more CPU or memory at the host**: this matches the page's
  own numbers (CPU 25%, memory normal) - there is no compute or memory
  bottleneck here to fix.

## The investigation

```bash
docker stats --no-stream
```
CPU and memory on all three containers look unremarkable - nothing close
to saturated. This rules out a resource-exhaustion cause and points at
something queue-shaped instead.

```bash
time curl -s -X POST http://localhost:8080/login \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","password":"demopass"}'
```
Confirms the symptom directly - either a multi-hundred-millisecond-plus
response, or an outright `503` with `"error": "database unavailable"` in
the body.

```bash
docker exec incident01-mysql mysql -uroot -prootpass \
  -e "SHOW VARIABLES LIKE 'max_connections'; SHOW STATUS LIKE 'Threads_connected';"
```
`max_connections` is 30. `Threads_connected` sits right up near it,
constantly.

```bash
docker exec incident01-mysql mysql -uroot -prootpass -e "SHOW PROCESSLIST\G" | less
```
The overwhelming majority of connections show `Info: SELECT SLEEP(20)`.
Grouping by connecting host/user makes it obvious these all belong to one
source, not a spread of normal app traffic:
```bash
docker exec incident01-mysql mysql -uroot -prootpass \
  -e "SELECT host, COUNT(*) FROM information_schema.processlist GROUP BY host;"
```

## The fix

Immediate mitigation - stop the reconciler entirely, freeing its
connections back to the pool:
```bash
docker compose stop worker
```
Login latency and error rate recover within seconds, since the app's own
pool connections were never the problem - the free connection slots were.

The real fix (not just for this lab, for the pattern) is structural:
- Give background/batch jobs their own connection budget, separate from
  and smaller than what's reserved for user-facing request paths (e.g. a
  dedicated MySQL user with `MAX_USER_CONNECTIONS`, or a bounded pool in
  the job itself).
- Don't hold a connection open for the duration of a slow query if it can
  be avoided - fix the slow query (add the missing index; this lab's
  `SELECT SLEEP(20)` stands in for exactly that kind of unindexed scan),
  and/or checkpoint and release-reacquire around long-running work.
- Alert on `Threads_connected` as a fraction of `max_connections`, not
  just on MySQL being reachable - the server was up and answering the
  entire time.

## Real-world examples of this pattern

- Rails apps where Sidekiq/Resque workers share a Postgres/MySQL
  connection pool with Puma/Unicorn web workers, and a burst of
  long-running jobs starves web request connections - a very common
  cause of "the site is slow, the database looks fine" incidents.
  Documented widely in Rails/ActiveRecord connection-pool postmortems.
- An ad hoc backfill or migration script left running against production
  that never closes its connections, discovered only when unrelated
  user-facing requests start timing out.
- Cloud-managed databases (RDS, Cloud SQL) with a connection limit tied
  to instance size - a batch job or reporting tool that opens many
  long-lived connections is a frequent, recurring cause of "random"
  application-level connection failures that have nothing to do with the
  application's own code.
