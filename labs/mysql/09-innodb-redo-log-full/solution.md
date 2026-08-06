# Lab 9 — Solutions

## Challenge A — resize is asynchronous, don't declare victory early

**Check:**
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW GLOBAL STATUS LIKE 'Innodb_redo_log_resize_status';"
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" \
  | sed -n '/^---$/,/^-------/p' | grep -E "Log sequence number|Last checkpoint at"
```
`Innodb_redo_log_resize_status` is non-empty while the resize is still in
progress — it describes what InnoDB is currently doing to reshape the
redo log files on disk. Writes issued during this window can still show
elevated checkpoint age relative to the OLD (smaller) capacity, because
the new capacity isn't fully in effect until the resize finishes.

**Diagnosis:** `SET GLOBAL innodb_redo_log_capacity = ...` returns
immediately, but the actual resize (shrinking or growing the underlying
log files) happens asynchronously in a background thread. Between issuing
the command and the resize completing, InnoDB is still operating under
constraints close to the old capacity. Treating the `SET GLOBAL` command
itself as "the fix is live" is the mistake — the fix isn't live until
`Innodb_redo_log_resize_status` goes back to empty.

**Fix:** wait for the resize to actually finish before re-testing or
declaring the incident resolved:
```bash
until [ -z "$(docker exec lab09-primary mysql -uroot -prootpass -N -e "SHOW GLOBAL STATUS LIKE 'Innodb_redo_log_resize_status';" | awk '{print $2}')" ]; do
  sleep 2
done
echo "resize complete"
```

**Lesson:** a dynamic/online config change is not automatically an
*instant* one. Any time a fix involves a resize, rebuild, or background
migration of internal storage structures, check for a status indicator
of the operation actually completing before you tell anyone the incident
is over — the same category of mistake as declaring a database "recovered"
the moment a `CHANGE REPLICATION SOURCE TO` command returns, before
replication threads have actually caught up.

---

## Challenge B — an open transaction pins the checkpoint, no matter the redo log size

**Check:**
```bash
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW PROCESSLIST;"
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" \
  | grep -A5 "TRANSACTIONS"
```
`SHOW PROCESSLIST` shows a connection sitting in `SLEEP(20)` inside an open
transaction. `SHOW ENGINE INNODB STATUS`'s TRANSACTIONS section lists it
with a low (old) transaction ID relative to newer, already-committed work
— it's the oldest active transaction in the system.

**Diagnosis:** InnoDB's checkpoint can only advance past the redo log
record that belongs to the OLDEST still-open transaction — it can never
discard/reuse redo log space for a change whose transaction hasn't
committed yet, because that change might still need to be rolled back or
crash-recovered. A single long-running transaction that has generated a
lot of redo (four `INSERT ... SELECT` statements against a growing table)
holds the checkpoint pinned near that transaction's start LSN for as long
as it stays open — regardless of how large you make
`innodb_redo_log_capacity`, because the problem here isn't capacity, it's
that nothing is being allowed to become "safely committed and flushable"
in the first place.

**Fix:** the transaction has to actually commit or roll back — no
config change substitutes for that:
```bash
# either let it finish naturally (the SLEEP(20) will end and COMMIT will run), or:
docker exec lab09-primary mysql -uroot -prootpass -e "
  SELECT id FROM information_schema.processlist WHERE info LIKE '%SLEEP%';
"
# then: KILL <id>;
```
Once the transaction ends, the checkpoint is free to advance again.

**Lesson:** redo log sizing (Steps 1-5) solves the "many small
transactions generating more redo than the log can hold" problem. It does
NOT solve "one long-running transaction is holding the checkpoint
hostage" — that's an application/query pattern problem (long-running
transactions, forgotten `COMMIT`s, batch jobs that should chunk their
work), and it will reproduce at ANY redo log size, just with a longer
fuse. Watch `SHOW ENGINE INNODB STATUS`'s TRANSACTIONS section for the
oldest active transaction whenever checkpoint age looks stuck rather than
gradually recovering.
