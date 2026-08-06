# Lab 9 — InnoDB Redo Log Too Small for the Write Load

## Objective
Run MySQL with a deliberately tiny InnoDB redo log capacity, watch write
throughput collapse under sustained load as checkpointing can't keep up,
read the checkpoint age directly out of `SHOW ENGINE INNODB STATUS`, and
fix it by sizing the redo log correctly for the workload.

## Why this matters
Every InnoDB write goes through the redo log first (write-ahead logging):
the change is logged, the log is flushed, and only later does the actual
data page get written back to disk in the background. The redo log has a
fixed capacity. If the checkpoint (the point up to which all data page
changes are safely on disk) can't advance fast enough to free up redo log
space, InnoDB has no choice but to force aggressive page flushing to catch
the checkpoint up — and while that's happening, new writes stall. This is
one of the most common "MySQL just got slow under load" incidents that
traces back to a single undersized config value, and it's easy to miss
because nothing is "down" — throughput just quietly degrades.

> Version note: this lab uses `innodb_redo_log_capacity`, the single
> setting that replaced `innodb_log_file_size` × `innodb_log_files_in_group`
> as of MySQL 8.0.30 and — unlike the old pair — can be changed online with
> `SET GLOBAL` instead of requiring a restart. If you're on an older 8.0.x
> release, the same underlying mechanism applies but you'd resize via
> `innodb_log_file_size` and a clean shutdown/restart instead.

## Prerequisites
- Docker + the `docker compose` plugin
- At least ~1GB free disk and some free RAM

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
1. Starts a single MySQL instance with `innodb_redo_log_capacity` set to
   8MB — the documented minimum, deliberately tiny for a lab.
2. Creates an `events` table with a `TEXT` payload column (wide rows
   generate more redo per write).
3. Runs a **bounded** write workload (200 batches of 20 rows, ~4KB payload
   each) and times how long it takes.

Note the elapsed time printed at the end — you'll compare it after the fix.

## Step 2 — Read the LOG section
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" \
  | sed -n '/^---$/,/^-------/p' | grep -E "Log sequence number|Log flushed up to|Last checkpoint at"
```
You'll see three LSN (log sequence number) values:
- `Log sequence number` — how far writes have gotten
- `Log flushed up to` — how far the redo log itself has been durably
  flushed to disk
- `Last checkpoint at` — how far dirty **data pages** have actually been
  written back; this is what determines how much redo log space can be
  reused

**Checkpoint age** = `Log sequence number` − `Last checkpoint at`. Compare
that gap to the 8MB capacity you configured — it should be sitting close
to the ceiling.

## Step 3 — Confirm it with status variables
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW GLOBAL STATUS LIKE 'Innodb_redo_log%';"
```
`Innodb_redo_log_capacity` confirms the configured ceiling;
`Innodb_redo_log_current_lsn` and `Innodb_redo_log_checkpoint_lsn` give
you the same two numbers as Step 2 without parsing free-text output — the
gap between them is the checkpoint age.

> Gotcha: don't assume this is disk I/O being slow in general — check
> `docker stats` too. In this lab the disk itself isn't overloaded; InnoDB
> is *self-throttling* writes on purpose because it's not safe to let the
> checkpoint fall further behind the tiny amount of redo log space
> available. That's a deliberate correctness mechanism, not a bug.

## Step 4 — Fix it: resize the redo log capacity
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "
  SET GLOBAL innodb_redo_log_capacity = 1073741824;
"
```
This is a **dynamic, online resize** as of 8.0.30 — no restart needed. It
happens in the background; watch it complete:
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW GLOBAL STATUS LIKE 'Innodb_redo_log_resize_status';"
```
Once the resize status is empty/idle, confirm the new capacity:
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_redo_log_capacity';"
```

## Step 5 — Prove the fix
Re-run the same bounded write workload and compare timing:
```bash
time docker exec lab09-primary bash -c '
  PAYLOAD=$(printf "x%.0s" $(seq 1 4000))
  for i in $(seq 1 200); do
    vals=""
    for j in $(seq 1 20); do
      vals="$vals,(\"$PAYLOAD\")"
    done
    vals="${vals#,}"
    mysql -uroot -prootpass appdb -e "INSERT INTO events (payload) VALUES $vals;" 2>/dev/null
  done
'
```
With 1GB of redo log headroom, checkpointing has room to run in the
background at a comfortable pace instead of racing to keep up — this run
should be noticeably faster than Step 1's.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the resize itself isn't instant:**
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "
  SET GLOBAL innodb_redo_log_capacity = 8388608;
"
# immediately, before it's had time to shrink:
docker exec lab09-primary mysql -uroot -prootpass -e "
  SET GLOBAL innodb_redo_log_capacity = 536870912;
  SHOW GLOBAL STATUS LIKE 'Innodb_redo_log_resize_status';
"
docker exec lab09-primary bash -c '
  for i in $(seq 1 50); do
    mysql -uroot -prootpass appdb -e "INSERT INTO events (payload) VALUES (REPEAT(\"y\",4000));" 2>/dev/null
  done
'
```
Fire writes at the instance while a resize is actively in progress. Check
`Innodb_redo_log_resize_status` and the checkpoint age together — figure
out whether it's safe to assume the fix is "done" the instant you run
`SET GLOBAL`, and what you'd check before telling an on-call channel the
incident is resolved.

**Challenge B — one oversized transaction, small redo log:**
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SET GLOBAL innodb_redo_log_capacity = 8388608;"
docker exec -d lab09-primary bash -c '
  mysql -uroot -prootpass appdb -e "
    BEGIN;
    INSERT INTO events (payload) SELECT REPEAT(\"z\", 4000) FROM events LIMIT 20;
    INSERT INTO events (payload) SELECT REPEAT(\"z\", 4000) FROM events;
    INSERT INTO events (payload) SELECT REPEAT(\"z\", 4000) FROM events;
    INSERT INTO events (payload) SELECT REPEAT(\"z\", 4000) FROM events;
    SELECT SLEEP(20);
    COMMIT;
  "
'
sleep 5
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" \
  | sed -n '/^---$/,/^-------/p' | grep -E "Log sequence number|Last checkpoint at"
```
This is one single, still-open (uncommitted) transaction generating a lot
of redo before it ever commits. Figure out why checkpoint age behaves
differently here than in the main lab's "many small transactions" case —
specifically, why the checkpoint can't advance past a certain point no
matter how much you wait, until this one session does something specific.

See `solution.md` only after you've formed your own diagnosis.
