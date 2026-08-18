# Lab 21 — Buffer Pool Sizing

## Objective
Watch a table that's always been fast for point lookups get
genuinely, measurably disk-bound — not because a query or an index
changed, but because it simply outgrew the memory set aside to cache
it — then fix it two different ways and learn why only one of those
fixes actually survives the next restart.

## Why this matters
InnoDB's buffer pool is the single most consequential piece of MySQL
memory tuning there is: every row read that isn't already cached there
means a real disk I/O, and every row read that *is* cached is
effectively free. `innodb_buffer_pool_size` is usually set once, early,
based on what the working set looked like at the time — and then
almost never revisited as the data actually grows. Nothing alerts on
this by default. The symptom isn't a query that suddenly looks
different in `EXPLAIN` — the plan is identical, the index is still
used correctly — it's the exact same query, using the exact same
index, quietly getting slower over months as a larger and larger
fraction of "should be instant" lookups turn into real disk reads.

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
This starts MySQL with a 24MB `innodb_buffer_pool_size` — a
reasonable setting when this app was new — and builds `working_set`,
a table that's since grown to ~75MB. `setup.sh` also runs a batch of
realistic random-lookup traffic so the buffer pool is already in its
real steady state, not artificially cold, by the time you start
investigating.

## Step 2 — Reproduce the symptom
```bash
./check.sh
```
Fires 2000 random point lookups across `working_set`'s full ID range
and reports the buffer pool hit ratio for that batch. It's stuck in
the high 80s - low 90s%, not the near-100% you'd expect for simple,
indexed primary-key lookups.

## Step 3 — Confirm the actual mismatch
```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
docker exec lab21-primary mysql -uroot -prootpass -e "
SELECT ROUND((data_length+index_length)/1024/1024,1) AS working_set_mb
FROM information_schema.tables WHERE table_schema='appdb' AND table_name='working_set';
"
```
A 24MB pool against a table that no longer fits inside it, comfortably.

## Step 4 — Fix it
```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SET GLOBAL innodb_buffer_pool_size = 134217728;"
```
`innodb_buffer_pool_size` is online-resizable in modern MySQL — no
restart required. Give it a moment (`SHOW STATUS LIKE
'Innodb_buffer_pool_resize_status';` will say `Completed` when it's
done), then drive a couple of warm-up batches so the newly available
room actually gets used:
```bash
for i in 1 2 3; do
docker exec lab21-primary bash -c "
for j in \$(seq 1 2000); do
  echo \"SELECT val FROM working_set WHERE id = \$(( (RANDOM * RANDOM * RANDOM) % 320000 + 1 ));\"
done | mysql -uroot -prootpass appdb -N
" >/dev/null
done
```

## Step 5 — Verify
```bash
./check.sh
```
Hit ratio should now be at or above 93%.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a well-sized pool, wiped out by one query:**
```bash
./reset.sh
docker exec lab21-primary mysql -uroot -prootpass appdb -e "
CREATE TABLE hot_cache (id INT PRIMARY KEY AUTO_INCREMENT, val VARCHAR(200)) ENGINE=InnoDB;
INSERT INTO hot_cache (val) SELECT LPAD(CONCAT('hot-', id), 200, 'x') FROM working_set LIMIT 20000;
CREATE TABLE reporting_table LIKE hot_cache;
INSERT INTO reporting_table SELECT * FROM hot_cache;
"
for i in 1 2 3 4 5; do
  docker exec lab21-primary mysql -uroot -prootpass appdb -e "INSERT INTO reporting_table (val) SELECT val FROM reporting_table;"
done
for i in 1 2 3 4; do
  docker exec lab21-primary mysql -uroot -prootpass appdb -e "SELECT SUM(LENGTH(val)) FROM hot_cache;" >/dev/null
  sleep 1.5
done
docker exec lab21-primary mysql -uroot -prootpass -e "SELECT * FROM sys.innodb_buffer_stats_by_table WHERE object_schema='appdb' AND object_name='hot_cache';"
```
`hot_cache` is small (~5MB) and, after that warm-up loop, genuinely
hot — note its `pages_old` column is at or near zero, meaning almost
all of it has been promoted out of the "just arrived" state. Now run
one, single, ordinary-looking reporting query:
```bash
docker exec lab21-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*), SUM(LENGTH(val)) FROM reporting_table;"
docker exec lab21-primary mysql -uroot -prootpass -e "SELECT * FROM sys.innodb_buffer_stats_by_table WHERE object_schema='appdb' AND object_name='hot_cache';"
```
`hot_cache` barely moved - it's still almost entirely resident. Now
repeat the entire sequence from a fresh `./reset.sh`, but before the
reporting query, run:
```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SET GLOBAL innodb_old_blocks_time = 0;"
```
Same reporting query, same tables, same sizes. Check `hot_cache`'s
residency again - what changed, and what does `innodb_old_blocks_time`
actually control? (It isn't "how much memory a table gets" - nothing
in this lab reserves memory per table at all.)

**Challenge B — the fix that only lasts until the next restart:**
```bash
./reset.sh
docker exec lab21-primary mysql -uroot -prootpass -e "SET GLOBAL innodb_buffer_pool_size = 134217728;"
docker exec lab21-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
docker restart lab21-primary
```
Wait for MySQL to come back up, then check the same variable again:
```bash
docker exec lab21-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
```
Back to 24MB - as if Step 4 never happened. Work out why, and what
actually needs to change (hint: `docker compose down` and inspect
`docker-compose.yml`'s `command:` section, specifically
`${BUFFER_POOL_SIZE:-25165824}`) for this fix to still be in effect
the next time something perfectly ordinary - a host reboot, a MySQL
upgrade, a container rescheduling - restarts this instance. Confirm
your fix by setting it and restarting again.

See `solution.md` only after you've formed your own diagnosis.
