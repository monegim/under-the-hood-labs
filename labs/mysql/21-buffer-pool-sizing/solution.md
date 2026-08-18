# Lab 21 — Solution

## Root cause

`innodb_buffer_pool_size` is 24MB. `working_set` has grown to ~75MB.
Random point lookups across the table's full ID range can't all be
served from cache at once — the pool doesn't have room to hold the
whole working set, so InnoDB constantly evicts one page to make room
for another. Every lookup landing on a currently-evicted page costs a
real disk read, even though the query and its index were never the
problem — `EXPLAIN` looks, and has always looked, identical.

## Why it happened

`innodb_buffer_pool_size` is set once, early, based on the working set
at the time — nothing about normal operation forces anyone to revisit
it as data grows. A table growing 10x over months is invisible to any
check that only looks at query plans or index usage; the only visible
symptom is a slowly degrading buffer pool hit ratio, a metric most
dashboards don't default to watching.

## Why the obvious fixes don't work

- **Adding an index**: there already is one (the primary key) — this
  isn't a missing-index problem. An index doesn't help if the index
  itself doesn't fit in memory.
- **Restarting MySQL**: makes it worse briefly — a restart empties the
  buffer pool entirely, so the next batch of queries starts fully cold.
- **Optimizing the query**: nothing to optimize — a primary-key point
  lookup is already the fastest access path InnoDB has. The cost is in
  whether the page is already in memory, not how the query is planned.

## The investigation

```bash
./check.sh
```
Hit ratio in the high 80s-low 90s%.

```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
docker exec lab21-primary mysql -uroot -prootpass -e "
SELECT ROUND((data_length+index_length)/1024/1024,1) AS working_set_mb
FROM information_schema.tables WHERE table_schema='appdb' AND table_name='working_set';
"
```
24MB against ~75MB — a complete explanation.

## The fix

```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SET GLOBAL innodb_buffer_pool_size = 134217728;"
```
Online-resizable, no restart needed. `./check.sh` confirms a hit ratio
at or above 93% once the newly available room is warmed by real traffic.

## Challenge A — a well-sized pool, wiped out by one query

**Check:** with `innodb_old_blocks_time` at its default (1000ms),
`hot_cache` barely moves after the reporting query. Set to `0`, the
same reporting query against the same tables evicts it almost
completely.

**Diagnosis:** InnoDB's LRU list has a "young" sublist (data accessed
repeatedly) and an "old" sublist (data read once). `innodb_old_blocks_time`
is the minimum time a page must sit in the old sublist before a
*second* access can promote it to young — stopping a single scan
(every page touched once) from flooding the young sublist and evicting
data proven hot by repeated use. It's not a memory reservation —
nothing sets aside pool space "for" any table. Set to `0`, every
newly-read page is treated as equally hot from its first touch,
putting a one-off scan on equal footing with genuinely hot data.

**Fix:** leave `innodb_old_blocks_time` at its default — this is one
of the few InnoDB settings where the out-of-the-box default is already
correct for most workloads.

**Lesson:** a correctly-sized buffer pool doesn't protect a steady-state
working set from a single ordinary-looking ad-hoc scan unless InnoDB's
own scan-resistance mechanism is active. Sizing the pool and protecting
it from scan pollution are two separate, both-necessary concerns.

## Challenge B — the fix that only lasts until the next restart

**Check:**
```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SET GLOBAL innodb_buffer_pool_size = 134217728;"
docker restart lab21-primary
docker exec lab21-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
```
Back to 24MB, as if the fix was never applied.

**Diagnosis:** `SET GLOBAL` changes a running server's in-memory
configuration only — it never touches whatever determines a *future*
startup's settings. Here that's the `--innodb-buffer-pool-size` value
in `docker-compose.yml`'s `command:` (in production: `my.cnf`, a
systemd unit, a Kubernetes manifest). Any fresh `mysqld` start — a
restart, a reboot, an upgrade, a rescheduled pod — reads from that
persistent source, not from a prior session's `SET GLOBAL`.

**Fix:**
```bash
BUFFER_POOL_SIZE=134217728 docker compose up -d
```
Confirmed by restarting again and checking the value holds.

**Lesson:** a dynamic, online-applied fix and a durable fix are
different claims — `SET GLOBAL` only makes the first one true. The
same distinction ProxySQL draws explicitly with `LOAD ... TO RUNTIME`
vs. `SAVE ... TO DISK`; MySQL's dynamic variables have no equivalent
two-step prompt, making it easy to believe an incident is fully
resolved when it's only resolved until the process restarts.
