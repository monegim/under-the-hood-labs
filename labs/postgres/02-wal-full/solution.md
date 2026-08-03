# Lab 32 — Solutions

## Challenge A — a logical slot also pins the system catalogs

**Check:**
```bash
docker exec lab32-primary psql -U postgres -c \
  "SELECT slot_name, slot_type, active, catalog_xmin, restart_lsn, wal_status FROM pg_replication_slots;"
```
`stuck_logical_slot` shows `active = f`, a frozen `restart_lsn` (same WAL
pinning as the physical slot), AND a `catalog_xmin` value that stops
advancing.

**Diagnosis:** logical decoding has to be able to reconstruct row images
from WAL using the table/column definitions as they existed at the time
each change was made, which means it also needs old versions of system
catalog rows (`pg_attribute`, `pg_class`, etc.) to stay around as long as
the slot might still need them. `catalog_xmin` is the oldest transaction
ID whose catalog versions the slot is still protecting. A logical slot
that's never consumed therefore doesn't just retain WAL — it also
prevents `VACUUM` from cleaning up dead rows in the shared system
catalogs across the ENTIRE cluster, not just one table. On a busy cluster
with frequent schema churn or just normal catalog churn, this is worse
than plain WAL retention: it's bloat you can't see with `pg_stat_user_tables`
at all, because the catalogs aren't "your" tables.

**Fix:**
```bash
docker exec lab32-primary psql -U postgres -c \
  "SELECT pg_drop_replication_slot('stuck_logical_slot');"
```
Same fix as the main lab — drop what nothing is consuming.

**Lesson:** every replication slot, physical or logical, pins WAL. Logical
slots pin catalog xmin on top of that. An unused logical slot is
strictly more dangerous than an unused physical one, and it's invisible
to any monitoring that only watches table-level bloat stats.

---

## Challenge B — `max_slot_wal_keep_size` trades disk space for the slot itself

**Check:**
```bash
docker exec lab32-primary psql -U postgres -c \
  "SELECT slot_name, active, restart_lsn, wal_status FROM pg_replication_slots;"
```
The WAL disk stayed healthy this time. But `restart_lsn` for `stuck_slot`
is now `NULL`, and `wal_status` reads `lost`.

**Diagnosis:** `max_slot_wal_keep_size` (PG13+) is exactly the safety net
this lab is missing by default — once the amount of WAL a slot would need
to retain exceeds this setting, the checkpointer invalidates the slot
instead of letting WAL grow without bound. That protects the disk, full
stop. But it does so by breaking the guarantee the slot existed to
provide: any replica or logical consumer that was relying on `stuck_slot`
and tries to reconnect now will fail with an error like
`requested WAL segment ... has already been removed`, because the WAL it
needs to resume from is genuinely gone. A physical replica in that state
needs a fresh `pg_basebackup`; a logical replication subscriber needs the
slot (and often the subscription) recreated from scratch.

**Fix:** there isn't a fix for the slot itself — it's unusable now. The
actual fix in production is upstream of this: set `max_slot_wal_keep_size`
to a value large enough to survive your worst-case expected
disconnect/maintenance window, and alert on `wal_status` reaching
`extended` well before it ever reaches `lost`, so someone can intervene
(fix the consumer, or deliberately drop the slot) before Postgres makes
the decision for you.

**Lesson:** `max_slot_wal_keep_size` is not a fix for "slots can fill your
disk," it's a choice about which failure you'd rather have — an
uncontrolled disk fill, or a replication slot that silently self-destructs
under sustained load. Both need monitoring; neither is "safe" to ignore.
