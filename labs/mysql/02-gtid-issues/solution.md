# Lab 2 — Solutions

## Challenge A — a silent errant transaction, no collision yet

**Check:**
```bash
docker exec lab02-primary mysql -uroot -prootpass -N -e "SELECT @@GLOBAL.gtid_executed;"
docker exec lab02-replica mysql -uroot -prootpass -N -e "SELECT @@GLOBAL.gtid_executed;"
docker exec lab02-replica mysql -uroot -prootpass -e "
  SELECT GTID_SUBTRACT(@@GLOBAL.gtid_executed, '<paste primary gtid_executed here>') AS errant_gtids\G"
```
`SHOW REPLICA STATUS` shows both threads `Yes` and lag at `0` — nothing
looks wrong. But `GTID_SUBTRACT()` (replica's set minus the primary's set)
returns a non-empty result: one GTID under the **replica's own
`server_uuid`** with transaction number `2` (the first direct write from
the main lab was `:1`, this one is `:2`).

**Diagnosis:** this is an errant transaction exactly like the one that
caused the main lab's crash — the only difference is luck: id `5555` was
never touched on the primary, so there was no collision to surface it.
Nothing in `SHOW REPLICA STATUS`, `SHOW PROCESSLIST`, or the error log
gives any hint this exists. The only way to find it is to explicitly
compare GTID sets across servers — which is precisely what
`dev.mysql.com`'s replication-and-GTID documentation recommends doing
*before* any failover, not after something breaks.

**The danger:** if this replica is ever promoted to primary (planned
failover, or an unplanned one during an incident), every OTHER replica
that starts replicating from it will receive `<replica-uuid>:2` as a
completely ordinary transaction — because from the newly-promoted
primary's point of view, it's just part of its history. The row
`(5555, 'another-direct-write-no-collision-yet')` — data nobody outside
this one replica ever intended to commit — gets silently propagated to
every downstream server as if it were a real, sanctioned write. There's no
error, no alert, just quietly wrong data spreading through the whole
topology.

**Fix (proactive, not reactive):** before promoting any replica, diff its
`gtid_executed` against every other node's using `GTID_SUBTRACT()` (or
`mysqlbinlog --skip-gtids` inspection of its own recent binlog events) and
treat any non-empty result as a stop-the-promotion finding. If you find
one after the fact but before promotion, either drop and re-provision that
replica from a clean source, or manually assess whether the errant data is
safe to keep and formally adopt it (rare, and always a deliberate call,
never a default).

**Lesson:** GTID conflicts don't always announce themselves with an error.
An errant transaction is dangerous *because* it can sit invisibly for a
long time — the failure mode isn't "replication breaks," it's "replication
keeps working, and quietly launders one server's local write into the
whole topology's shared history the next time a failover happens."

---

## Challenge B — purged binary logs, not a data conflict

**Check:**
```bash
docker exec lab02-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Last_IO_Errno|Last_IO_Error"
docker exec lab02-primary mysql -uroot -prootpass -e "SELECT @@GLOBAL.gtid_purged\G"
```
`Replica_IO_Running` is `No` this time (not the SQL thread — the IO thread
itself can't even fetch). `Last_IO_Error` reads something like: *"Got
fatal error 1236 from source when reading data from binary log: 'The
replica is connecting using CHANGE MASTER TO ... SOURCE_AUTO_POSITION = 1,
but the source has purged binary logs containing GTIDs that the replica
requires.'"*

**Diagnosis:** setting `binlog_expire_logs_seconds=1` and then rotating
with `FLUSH BINARY LOGS` caused the primary to purge old binlog files —
including ones containing GTIDs the still-behind replica had never
fetched (it was `STOP REPLICA`'d while the primary kept committing and
rotating). Auto-positioning works by the replica telling the primary "here
is my `gtid_executed`, send me everything after it"; the primary can only
honor that if it still *has* those transactions in a binlog file on disk.
Once purged, they're gone — this is exactly what `gtid_purged` on the
primary now reflects (the set of GTIDs that were executed and later
removed from the retained binlogs, as opposed to `gtid_executed`, which
is everything ever executed whether or not the binlog for it still
exists).

**Fix:** there's no way to make the primary hand over data it no longer
has. The real fix is re-provisioning: take a fresh logical or physical
backup of the primary (`mysqldump --all-databases --source-data=2` in 8.0,
which captures `gtid_executed` as of the dump and emits it as
`SET @@GLOBAL.gtid_purged=...` on restore, or a physical tool like
Percona XtraBackup), restore it onto the replica, and start replication
fresh from that snapshot's position — the replica's `gtid_purged` after
restore correctly reflects everything already contained in the backup, so
auto-positioning resumes cleanly for anything committed *after* the
snapshot, without ever needing the purged binlogs at all.

**Lesson:** `expire_logs`/`binlog_expire_logs_seconds` exists to bound disk
usage, but it is a blunt tool — it does not know or care whether a replica
still needs a given binlog file. Purging is safe only when you know every
replica (and every backup/DR process that depends on those binlogs) has
already consumed what it needs. A replica that's been `STOP REPLICA`'d or
disconnected for maintenance is exactly the case that gets caught out by
an aggressive expiry setting — this is the same category of mistake as
Lab 6 (MySQL disk full / binlog purging), from the opposite side: there,
not purging enough causes disk exhaustion; here, purging too eagerly
breaks a replica that hadn't caught up yet.
