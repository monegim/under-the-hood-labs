# Lab 7 — Solutions

## Challenge A — corruption in the currently active file

**Check:**
```bash
docker logs lab07-primary 2>&1 | tail -40
docker exec lab07-primary mysql -uroot -prootpass -e "SHOW BINARY LOGS;"
```
Unlike the main lab, `docker logs lab07-primary` right after restart shows
InnoDB/binlog crash-recovery messages actively inspecting this file —
because from MySQL's point of view at startup, this was the log it was
writing to when it last stopped, and crash recovery always validates and,
if needed, safely truncates that specific file back to the last complete,
well-formed event it can find. Depending on exactly where the corrupted
bytes landed relative to event boundaries, the server may start up having
silently trimmed off everything after the corruption (data loss, but a
clean, working binlog) or, if the corruption happens to look like a
plausible-but-wrong event header, may fail to start at all or continue
serving a subtly truncated log.

**Diagnosis:** MySQL's binlog crash-recovery only ever scans the file
that was open/active at the moment of the last shutdown or crash — it has
no reason to (and does not) validate already-rotated files, because those
were closed cleanly with their own `Rotate` event and, under ordinary
operation, are assumed to be immutable history from that point on. That
asymmetry is exactly why the main lab deliberately corrupts an OLD
rotated file instead of the active one: corrupting the active file gets
"handled" (to varying degrees of gracefully) by recovery logic that
exists specifically for that file; corrupting an old one does not, and
silently produces exactly the kind of stuck replica this lab is built
around.

**Fix:** if recovery already truncated the file cleanly, there's nothing
further to do on the primary itself — but you must now determine whether
any transactions were lost in the trim, and whether any replica/backup
depended on them; if recovery failed to start mysqld cleanly, the honest
fix is restoring the primary's own datadir from its last known-good backup
rather than trying to hand-repair a binlog file at the byte level.

**Lesson:** an active binlog file being corrupted is, perversely, the
*less* silently dangerous case — MySQL's own startup logic is built to
detect and handle exactly that scenario (because it's the normal shape of
"the server crashed mid-write"). An old, already-rotated file being
corrupted has no equivalent safety net at all; nothing checks it until
something — a lagging replica, a backup job, a manual audit — actually
tries to read it, potentially much later.

---

## Challenge B — corruption discovered by a backup process, not a replica

**Check:**
```bash
cat /tmp/lab07-recovery-test.sql | tail -5
```
`mysqlbinlog` reading the corrupted file directly (no replica involved at
all) fails or truncates output partway through, the same signature of
failure as the main lab — but this time nothing about `SHOW REPLICA
STATUS` on any currently-attached replica necessarily changes, if none of
them still needed this particular (oldest) file.

**Diagnosis:** the danger here isn't a broken replica — it's a broken
**recovery path**. Point-in-time recovery (restore a backup, then replay
binlogs forward to a specific moment) depends on being able to read every
binlog file covering the window between the backup and the target
recovery time, in order. A corrupted file in that chain doesn't announce
itself with an error on any live server at all — everything can look
completely healthy in production — until the day someone actually needs
to *use* that specific binlog for recovery, at which point they discover
the gap during the worst possible moment: mid-incident, trying to restore.
This is arguably worse than the main lab's failure precisely because it's
silent by default; nothing routinely reads old binlog files unless a
replica needs to catch up through them or a recovery drill explicitly
exercises them.

**Fix:** there's no repair for the corrupted file itself — the same
honest answer as the main lab. What actually prevents this from being a
surprise: periodically *testing* recovery (restore a backup + replay
binlogs forward in a scratch environment, on a schedule, not just trusting
that backups exist) so a corrupted or missing binlog is discovered during
a drill, not during a real incident.

**Lesson:** binlog corruption's real risk profile isn't "will a replica
notice" — replicas are actually the *lucky* case, because they fail loud
and immediately. The dangerous case is a corrupted file sitting untested
in a backup/PITR chain that nobody exercises until it's needed for real.
Treat "can we actually replay our binlogs end-to-end" as something to
verify proactively, not something to assume.
