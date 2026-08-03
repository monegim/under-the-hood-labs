# Lab 6 — Solutions

## Challenge A — time-based expiry alone isn't a capacity plan

**Check:**
```bash
mysql -uroot -prootpass -e "SHOW BINARY LOGS;" | tail -5
df -h /mnt/mysql-binlogs
mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';"
```
`binlog_expire_logs_seconds` is now a sane 7 days, and you already ran
`PURGE BINARY LOGS`, yet disk usage on `/mnt/mysql-binlogs` climbs right
back toward full as the workload keeps running.

**Diagnosis:** `binlog_expire_logs_seconds` (and the older
`expire_logs_days`) controls **when a binlog file becomes eligible for
automatic removal**, not how much disk headroom you have or how fast you
produce binlog volume. Even at a well-chosen 7-day retention, if your
write rate produces more binlog data per day than your volume has free
space for seven days' worth of, you will still fill the disk — just more
slowly, which can actually be worse operationally (it looks fine for
days, then fills up on a weekend). Retention policy and capacity planning
are two different questions: retention answers "how much history do I
need to keep for replication/PITR," capacity answers "is this volume
physically big enough to hold that much history at this write rate."

**Fix:** size the binlog volume based on measured binlog bytes/day at
peak write rate, multiplied by your desired retention window, with real
headroom on top (not a round number picked without measuring) — and
separately, monitor `SHOW BINARY LOGS`' total size or disk `df` on the
binlog volume as an actual alerting metric, not just "did the expiry
setting get configured."

**Lesson:** `binlog_expire_logs_seconds` is necessary but not sufficient.
A time-based retention setting protects you from "nobody ever purges
anything" (this lab's original misconfiguration) — it does not protect
you from "we retain a reasonable amount of history, but that reasonable
amount is still bigger than the disk."

---

## Challenge B — filesort spilling to tmpdir, not binlogs

**Check:**
```bash
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM bigsort ORDER BY v DESC, k DESC;"
mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'sort_buffer_size';"
mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Created_tmp%';"
```
`EXPLAIN`'s `Extra` column shows `Using filesort`. `sort_buffer_size` is
the 8.0 default (256KB) — tiny compared to the ~200MB+ of `k`/`v` data
(500 bytes each, ~262,000 rows) that needs sorting. `Created_tmp_disk_
tables`/watching `df -h /mnt/mysql-tmp` while the query runs shows real
disk usage climbing toward the 100M `tmpdir` filesystem's limit, and
depending on exactly how large `bigsort` grew, the query can fail outright
with something like `Error: The table '/mnt/mysql-tmp/...' is full`
(errno 1114) — the on-disk equivalent of running out of memory, just for
temp/sort space instead of the binlog volume from the main lab.

**Diagnosis:** `ORDER BY` on columns that aren't covered by an index that
already returns rows in that order forces MySQL to materialize and sort
the result set — a **filesort**. When the data to be sorted doesn't fit
in `sort_buffer_size` (per-connection, allocated per sort, not shared),
MySQL falls back to an on-disk merge sort using files under `tmpdir`. This
is completely normal MySQL behavior for exactly the query shape this
challenge uses (large-ish text columns, no supporting index, real
row volume) — the "incident" isn't that MySQL used disk for a sort, it's
that the volume backing `tmpdir` wasn't sized for how big a temp table
this workload can actually generate.

**Fix:** in order of effectiveness, generally:
1. Add an index that lets MySQL avoid the sort entirely (an index on
   `(v, k)` here would let it read rows in the needed order directly —
   check `EXPLAIN` afterward for `Using filesort` disappearing).
2. Select only the columns actually needed instead of `SELECT *`,
   reducing how much data has to be sorted/materialized in the first
   place.
3. Increase `sort_buffer_size` for workloads that legitimately need to
   sort large result sets in memory — carefully, since it's allocated
   per sort operation per connection, not a single shared pool, so
   raising it globally on a high-concurrency server can itself cause
   memory pressure.
4. Give `tmpdir` enough dedicated headroom for your actual peak
   sort/temp-table volume, the same capacity-planning discipline as
   Challenge A, just for a different directory.

**Lesson:** "disk full" on a MySQL host isn't always about the data
directory or the binlogs — `tmpdir` is a distinct, separately
configurable location that ordinary `SELECT` queries (not just explicit
temp tables) can fill on their own, and it's sized/monitored independently
from everything else MySQL writes to disk.
