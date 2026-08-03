# Lab 6 — MySQL Fills Its Own Disk: Unpurged Binary Logs

## Objective
Reproduce a MySQL instance filling up its OWN dedicated disk through
completely normal write traffic — not inode exhaustion (that's already
covered in `linux/11-disk-full-writes-fail`) — because binary logging is
on and nothing was ever configured to purge old binlog files. Learn
`SHOW BINARY LOGS`, `PURGE BINARY LOGS`, and `binlog_expire_logs_seconds`.

## Why this matters
Binary logs are not optional bookkeeping — they're required for
replication and point-in-time recovery, so you can't just turn them off
to "fix" this. But binlogs accumulate forever unless something purges
them, and `binlog_expire_logs_seconds=0` (an explicit "never expire," a
setting many configs still carry from years-old templates or a
lift-and-shift from MySQL 5.7, where the equivalent old-style default
behaved the same way) means MySQL will happily keep every binlog file
ever generated. On a busy write workload, that's a slow, entirely
predictable disk-full incident that looks alarming ("MySQL is refusing
writes!") but has an extremely simple, well-understood root cause once
you know where to look.

## Prerequisites
- Ubuntu VM, sudo access
- `losetup`, `mkfs.ext4` (part of `util-linux`/`e2fsprogs`, present by
  default)

Check first:
```bash
uname -a
which losetup mkfs.ext4
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This script:
1. Installs `mysql-server`.
2. Creates a dedicated 150M loop-mounted filesystem at
   `/mnt/mysql-binlogs` (safe and reversible — MySQL's real datadir is
   untouched) and points `log-bin` at it.
3. Sets `binlog_expire_logs_seconds=0` — the misconfiguration: nothing
   ever purges old binlogs — and `max_binlog_size=20M` so they rotate
   frequently and pile up fast.
4. Also creates a dedicated 100M loop-mounted filesystem at
   `/mnt/mysql-tmp` for `tmpdir` (used later, in Challenge B).
5. Runs a bounded write workload (large text rows) until the binlog
   filesystem is ~92% full or a write actually fails.

## Step 2 — See the misleading (or not-so-misleading) signal
```bash
df -h /mnt/mysql-binlogs
```
Nearly full, exactly as expected — unlike the inode lab, this one isn't
subtle; the bytes really are almost gone.

## Step 3 — Confirm what's actually eating the space
```bash
mysql -uroot -prootpass -e "SHOW BINARY LOGS;"
```
> Gotcha: count the files and sum the `File_size` column — this should
> account for nearly all of `/mnt/mysql-binlogs`'s used space. If it
> doesn't, something other than binlogs is filling that disk and you're
> diagnosing the wrong thing.

## Step 4 — Prove it with a real write attempt
```bash
mysql -uroot -prootpass appdb -e "INSERT INTO logs (payload) VALUES ('test');"
```
This fails (or is close to failing, depending on exactly how full the
disk got) with something like `Disk full` / `Error writing file` — MySQL
cannot commit a write it can't durably record in the binary log.

## Step 5 — Fix it: purge what's safe to purge
Check which binlog files are safe to remove — never purge a file a
replica still needs (see Lab 2's Challenge B for exactly what goes wrong
if you do). In this single-instance lab there's no replica depending on
them, so:
```bash
mysql -uroot -prootpass -e "
  SHOW BINARY LOGS;
"
mysql -uroot -prootpass -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 1 MINUTE;"
df -h /mnt/mysql-binlogs
```
Then fix the actual misconfiguration so this doesn't just recur:
```bash
mysql -uroot -prootpass -e "SET GLOBAL binlog_expire_logs_seconds=604800;"  # 7 days
```
(Persist it too — add `binlog_expire_logs_seconds=604800` to
`/etc/mysql/mysql.conf.d/zzz-lab06.cnf` in place of the `0`, or the
setting reverts on the next restart.)

## Step 6 — Confirm recovery
```bash
df -h /mnt/mysql-binlogs
mysql -uroot -prootpass appdb -e "INSERT INTO logs (payload) VALUES ('test-after-fix');"
```
Free space recovered, and the write succeeds.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — purging isn't instant relief if the workload keeps going:**
```bash
mysql -uroot -prootpass -e "SET GLOBAL binlog_expire_logs_seconds=604800;"
mysql -uroot -prootpass -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 1 MINUTE;"
for i in $(seq 1 100); do
  VALS=""
  for j in $(seq 1 50); do VALS="$VALS,(REPEAT('y', 2000))"; done
  mysql -uroot -prootpass appdb -e "INSERT INTO logs (payload) VALUES ${VALS#,};" 2>/dev/null
done
df -h /mnt/mysql-binlogs
```
You fixed the expiry setting and purged old logs, but disk usage climbs
right back up. What's the actual relationship between
`binlog_expire_logs_seconds` and how much headroom you need on the volume
backing your binlogs, given a steady write rate — is a time-based expiry
setting alone ever enough on its own?

**Challenge B — tmpdir, not binlogs, this time:**
```bash
mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS bigsort;
  CREATE TABLE bigsort (id INT AUTO_INCREMENT PRIMARY KEY, k VARCHAR(500), v VARCHAR(500));
  INSERT INTO bigsort (k, v)
  SELECT REPEAT('k', 500), REPEAT('v', 500) FROM logs LIMIT 1;
"
# multiply it up to ~200,000 wide rows so the sort genuinely can't fit in memory
for i in $(seq 1 18); do
  mysql -uroot -prootpass appdb -e "INSERT INTO bigsort (k, v) SELECT k, v FROM bigsort;"
done
mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM bigsort;"

# run the sort in the background and watch tmpdir fill WHILE it executes —
# MySQL unlinks its on-disk temp files as soon as the query ends, so you have
# to catch it in the act
mysql -uroot -prootpass appdb -e "SELECT * FROM bigsort ORDER BY v DESC, k DESC;" > /dev/null 2>/tmp/lab06-sort-err.log &
for i in $(seq 1 20); do sleep 0.5; df -h /mnt/mysql-tmp; done
wait
cat /tmp/lab06-sort-err.log
```
Different directory, different mechanism, same "disk full" shape — and
this time it can fail outright with something like `Error: The table
'...' is full` (errno 1114) rather than a slow climb. Diagnose what
specifically causes a `SELECT ... ORDER BY` to write to disk at all
(hint: check `SHOW STATUS LIKE 'Created_tmp%'`, `EXPLAIN`, and
`sort_buffer_size`), and what you'd change about either the query, the
schema, or the configuration to reduce how much it needs to spill.

See `solution.md` only after you've formed your own diagnosis.
