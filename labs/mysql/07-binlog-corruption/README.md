# Lab 7 — Corrupted Binary Log Breaks Replication Downstream

## Objective
Simulate a corrupted binary log file on the primary (bit-level
corruption of an already-rotated file, done safely in a throwaway
container — **never do this to a real system**) and watch a lagging
replica's IO thread fail trying to read through it. Learn to use
`mysqlbinlog` to inspect binlog integrity, `SHOW BINLOG EVENTS`, and be
honest about the real-world fix path: binlog corruption often has no
clean in-place repair, only damage control.

## Why this matters
Binary logs are ordinary files on disk, and disks fail in ordinary ways —
a bad block, a botched filesystem-level restore, a partial write during a
host crash, a bug in a backup/replication tool that touches the wrong
bytes. When it happens to a binlog file a replica still needs, the
failure doesn't look like a MySQL bug — it looks like replication just
stopped, with an error message about a specific file and offset. The
single most important thing to internalize here: unlike most of this
repo's other incidents, there usually is no "run this one command and
it's fixed" ending. Once the bytes are gone, they're gone — the honest
answer is often "re-provision from a known-good source," not "recover the
corrupted file."

## Prerequisites
- Docker + the `docker compose` plugin
- At least ~1GB free disk for two MySQL instances

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
1. Starts `primary` and `replica` via `docker compose`, GTID-based
   replication.
2. Seeds a small `orders` table and lets it replicate cleanly.
3. `STOP REPLICA`s the replica (simulating routine maintenance).
4. Writes several rounds of data to the primary, force-rotating the
   binlog (`FLUSH BINARY LOGS`) between rounds, so multiple **old**
   binlog files accumulate that the paused replica still needs.
5. Stops the primary container, corrupts the **oldest rotated** binlog
   file directly on disk (overwrites 256 bytes in the middle with random
   data — deliberately not the currently active file, and deliberately
   not a truncation, so MySQL's own crash-recovery logic at restart has
   no reason to touch it), then restarts the primary.
6. Resumes the replica — its IO thread now has to read forward through
   the corrupted file to catch up.

## Step 2 — See the failure
```bash
docker exec lab07-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Last_IO_Errno|Last_IO_Error"
```
> Gotcha: it's `Replica_IO_Running` that's `No` here, the opposite of Lab
> 2's failure — the IO thread itself can't even successfully fetch and
> read the source's binlog, versus Lab 2 where fetching worked fine and
> only applying failed.

## Step 3 — Inspect the binlog directly with mysqlbinlog
```bash
docker exec lab07-primary mysqlbinlog -uroot -prootpass \
  --read-from-remote-server --host=127.0.0.1 --user=root --password=rootpass \
  $(docker exec lab07-primary mysql -uroot -prootpass -N -e "SHOW BINARY LOGS;" | awk 'NR==1{print $1}') \
  2>&1 | tail -30
```
Or, simpler, directly against the file inside the container:
```bash
docker exec lab07-primary bash -c "cd /var/lib/mysql && mysqlbinlog \$(mysql -uroot -prootpass -N -e 'SHOW BINARY LOGS;' | head -1 | awk '{print \$1}')" 2>&1 | tail -30
```
Look for `mysqlbinlog` erroring out partway through
(`ERROR: Error in Log_event::read_log_event()` or a checksum mismatch) —
this confirms the corruption is real and shows you exactly how far into
the file the data is still readable.

## Step 4 — Confirm with SHOW BINLOG EVENTS
```bash
docker exec lab07-primary mysql -uroot -prootpass -e "SHOW BINARY LOGS;"
docker exec lab07-primary mysql -uroot -prootpass -e "SHOW BINLOG EVENTS IN '<the corrupted filename>' LIMIT 20;"
```
This may itself error out or stop short, depending on how far into the
file the corrupted bytes are — either way, it confirms the file is unusable
past a certain point, on the primary's own copy, not just from the
replica's point of view.

## Step 5 — The honest fix: re-provision, don't try to repair
There is no supported way to "un-corrupt" a binlog file, and the
GTID-skip trick from Lab 2 doesn't apply here — that technique works when
the SQL/apply thread already has the transaction in its relay log and
just fails to *apply* it; here the IO thread can't even *retrieve* it from
the source in the first place. The real fix is a fresh, consistent
snapshot of the primary's current state:
```bash
docker exec lab07-primary mysqldump -uroot -prootpass --all-databases \
  --source-data=2 --single-transaction --set-gtid-purged=ON > /tmp/lab07-snapshot.sql
docker exec lab07-replica mysql -uroot -prootpass -e "STOP REPLICA; RESET REPLICA ALL;"
docker exec -i lab07-replica mysql -uroot -prootpass < /tmp/lab07-snapshot.sql
docker exec lab07-replica mysql -uroot -prootpass -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary', SOURCE_USER='repl', SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"
```
`--set-gtid-purged=ON` (the 8.0 default) captures the primary's
`gtid_executed` at dump time and emits it as the replica's new
`gtid_purged` on restore — the replica now correctly believes everything
in the snapshot is "already applied," so auto-positioning resumes cleanly
from *after* the snapshot, without ever needing the corrupted file's
contents at all.

## Step 6 — Confirm recovery
```bash
docker exec lab07-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the corruption is in the CURRENTLY active file:**
```bash
docker compose stop primary
ACTIVE_FILE=$(docker exec lab07-primary bash -c "cat /var/lib/mysql/mysql-bin.index 2>/dev/null" 2>/dev/null | tail -1 | sed 's#.*/##')
echo "(container is stopped, so read the file name from the host bind mount instead)"
ACTIVE_FILE=$(tail -1 ./data/primary/mysql-bin.index | sed 's#.*/##')
sudo dd if=/dev/urandom of="./data/primary/${ACTIVE_FILE}" bs=1 seek=200 count=64 conv=notrunc status=none
docker compose start primary
```
This time you corrupted the file that was still active/being written to
when the primary stopped. Check the primary's own error log
(`docker logs lab07-primary`) right after it restarts. Does MySQL's
startup crash-recovery behave the same way toward this file as it did
toward the already-rotated one in the main lab? What does that imply
about which binlog files are riskier to lose to corruption — the active
one, or an old rotated one still needed by a lagging replica?

**Challenge B — corruption discovered only during a backup, not from a replica:**
```bash
OLDEST_FILE=$(docker exec lab07-primary mysql -uroot -prootpass -N -e "SHOW BINARY LOGS;" | head -1 | awk '{print $1}')
docker compose stop primary
sudo dd if=/dev/urandom of="./data/primary/${OLDEST_FILE}" bs=1 seek=100 count=64 conv=notrunc status=none
docker compose start primary
docker exec lab07-primary mysqlbinlog "/var/lib/mysql/${OLDEST_FILE}" > /tmp/lab07-recovery-test.sql 2>&1
tail -5 /tmp/lab07-recovery-test.sql
```
No replica is even involved this time — replication on the existing
replica may keep working fine if it never needed this particular file.
Where would this corruption actually get discovered in a real
environment if not from a replica erroring out, and why does that make it
more dangerous, not less, than the main lab's scenario?

See `solution.md` only after you've formed your own diagnosis.
