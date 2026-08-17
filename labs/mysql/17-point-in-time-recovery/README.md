# Lab 17 — Point-in-Time Recovery

## Objective
Recover from a `DELETE` with no `WHERE` clause using a full backup plus
binary log replay — not just "restore the backup," which alone would
lose everything written since the last backup ran, disaster or not.

## Why this matters
A full backup answers "what did the database look like at backup time."
It says nothing about the hours (or days) of writes between that backup
and the moment something went wrong. Point-in-time recovery — restore
the last full backup, then replay the binary log forward from exactly
where that backup left off, up to (but not including) the disastrous
statement — is the actual mechanism behind "restore to 2:47pm" that
every managed-database provider's dashboard makes look like a button
click. Understanding what's really happening under that button is the
difference between confidently running a real recovery under pressure
and hoping a vendor's magic works.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

**A real constraint worth knowing up front:** the official `mysql:8.0`
Docker image does not ship `mysqlbinlog` at all. This lab uses a
separate `tools` container (Debian + `default-mysql-client`, which
provides an equivalent binary named `mariadb-binlog`) to read and replay
binary logs — see `CONCEPTS.md` for why, and for a real compatibility
wrinkle this combination has that you'll hit in Step 5.

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates an `accounts` table, seeds it, takes a full backup with its
binary log position recorded, makes more normal writes, then runs
`DELETE FROM accounts;` with no `WHERE` clause — the disaster — followed
by one more normal write afterward (nobody's noticed yet).

## Step 2 — Confirm the damage
```bash
docker exec lab17-primary mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
```
Only the row inserted *after* the disaster survives. The backup alone,
restored as-is, would only get you back to the seed data — missing both
the legitimate writes made after the backup *and* the write made after
the disaster.

## Step 3 — Find where the backup left off
```bash
docker exec lab17-tools grep "CHANGE MASTER" /tmp/backup.sql
```
`mysqldump --master-data=2` recorded the exact binary log file and
position at backup time as a comment in the dump — this is where replay
needs to start.

## Step 4 — Find exactly where the disaster starts
```bash
docker exec lab17-tools mariadb-binlog --base64-output=DECODE-ROWS -v /tmp/mysql-bin.000003 | grep -B12 "DELETE FROM \`appdb\`.\`accounts\`"
```
Look at the lines above the `### DELETE FROM` block for a `# at N` marker
right before a `Query ... BEGIN` line — that `N` is the position where
this transaction starts. Note it; call it `DISASTER_POS`. (The exact
number varies run to run — that's expected. Read it from your own output,
don't reuse a number from this file.)

## Step 5 — Restore the backup, then replay up to (not past) the disaster
```bash
docker exec lab17-tools bash -c "mysql -h restore -uroot -prootpass < /tmp/backup.sql"
docker exec lab17-tools bash -c "
  mariadb-binlog --start-position=<BACKUP_POS> --stop-position=<DISASTER_POS> /tmp/mysql-bin.000003 | mysql --force -h restore -uroot -prootpass appdb
"
```
`--force` is required here, not optional — without it this command
silently recovers nothing. See Challenge A for exactly why, and don't
skip understanding it: it's the kind of thing that looks like it worked
when it didn't.

## Step 6 — Verify
```bash
./check.sh
```
Confirms the `restore` target has exactly the pre-disaster state:
accounts 1-4, with account 1's balance correctly reflecting the update
made after the backup but before the disaster.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a replay command that looks like it ran, but recovered nothing:**
```bash
./reset.sh
# ... repeat Steps 3-5, but WITHOUT --force this time:
docker exec lab17-tools bash -c "
  mariadb-binlog --start-position=<BACKUP_POS> --stop-position=<DISASTER_POS> /tmp/mysql-bin.000003 | mysql -h restore -uroot -prootpass appdb
"
docker exec lab17-restore mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
```
The command completes. It's not obviously hung or crashed. But
`accounts` on the restore target is empty or missing entirely — nothing
was recovered. Scroll back through the actual output (don't just check
that the command returned) and find the exact error. What is
`check_constraint_checks`, why does setting it fail specifically in this
cross-tool combination, and why does one failed `SET` statement near the
top of the replay stream take out every real data statement after it?

**Challenge B — recovering the pre-disaster state loses a legitimate write that came after it:**
```bash
docker exec lab17-restore mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
```
After Step 6's fix, this shows accounts 1-4 — correct, but missing the
row that was inserted *after* the disaster (Step 1's last write, before
anyone noticed the problem). That row is legitimate; nothing about it
was ever wrong. Using the `DISASTER_POS` from Step 4, find the position
where the disaster's transaction actually *ends* (the `COMMIT`/`Xid`
line right after the `### DELETE FROM` block) and figure out how to
recover that later write too — without re-running the `DELETE` itself.

See `solution.md` only after you've formed your own diagnosis.
