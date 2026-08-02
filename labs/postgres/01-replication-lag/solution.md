# Lab 31 — Solutions

## Challenge A — CPU contention, not I/O

**Check:**
```bash
iostat -x 1 5
docker stats --no-stream
docker exec lab31-primary psql -U postgres -c "SELECT replay_lag FROM pg_stat_replication;"
```
`iostat` shows `%util` low/normal on the underlying disk — nothing like
the saturation from the main lab. `docker stats` instead shows `io-hog`
pinning close to 100% CPU per core across all of the host's cores, while
`standby`'s CPU% is much lower than it needs to make progress.
`replay_lag` is climbing the same way it did in Step 3.

**Diagnosis:** the disk is fine this time — the standby's startup process
(the one that replays WAL) simply isn't getting scheduled enough CPU time
to work through the WAL it already received, because an unrelated
CPU-bound process (`io-hog`'s `yes` loops) is saturating every core on the
shared host. Docker's default CPU shares are a *fair-share* allocation,
not a hard reservation — when the host is genuinely oversubscribed, every
container's actual CPU time shrinks, including the one doing replication
apply. Same symptom as Step 5 (`replay_lag` up), completely different
resource at fault.

**Fix:**
```bash
docker exec lab31-io-hog pkill yes
```
Or, to prevent recurrence without killing legitimate workloads in
production, cap the noisy container's CPU allocation instead:
```bash
docker update --cpus="2" lab31-io-hog
```

**Lesson:** replay lag has more than one possible resource-layer cause.
Check disk (`iostat`) first, then CPU (`top`/`mpstat`/`docker stats`) —
don't assume it's always disk just because that's the more commonly told
story.

---

## Challenge B — an MVCC snapshot conflict, not a resource at all

**Check:**
```bash
iostat -x 1 5
top
docker exec lab31-standby psql -U postgres -c \
  "SELECT pid, state, query FROM pg_stat_activity WHERE state <> 'idle';"
docker exec lab31-standby psql -U postgres -c \
  "SELECT datname, confl_snapshot, confl_lock FROM pg_stat_database_conflicts;"
docker exec lab31-primary psql -U postgres -c "SELECT replay_lag FROM pg_stat_replication;"
```
`iostat` and `top` both show the standby host close to idle — no disk
saturation, no CPU saturation. `pg_stat_activity` on the standby shows a
`REPEATABLE READ` transaction sitting in `pg_sleep(180)`. `replay_lag` is
still climbing. `pg_stat_database_conflicts.confl_snapshot` increments
each time the primary's `VACUUM` removes a row version that the standby's
open transaction still needed.

**Diagnosis:** the standby's `REPEATABLE READ` transaction fixed its
snapshot at `BEGIN` and needs every row version visible under that
snapshot to remain readable for as long as the transaction stays open.
Meanwhile, `VACUUM orders` on the primary removes dead row versions that
are no longer needed there and generates a WAL record for it. When the
standby tries to replay that WAL record, Postgres detects that the
standby's own long-running query still needs the row version being
removed — a **recovery conflict**. Because this standby was started with
`hot_standby_feedback=off` (the default) and a raised
`max_standby_streaming_delay=300000` (5 minutes, up from the 30s
default), Postgres pauses WAL replay rather than immediately canceling the
conflicting query, so the lag is sustained and clearly observable instead
of resolving itself in ~30 seconds. Nothing here is a hardware resource —
CPU and disk stay idle the whole time, because replay is simply blocked
waiting for the conflicting standby query to get out of the way.

**Fix:** end the long-running standby transaction (commit, cancel, or
just let `pg_sleep` finish and the transaction commit on its own) and
replay resumes immediately:
```bash
docker exec lab31-standby psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' OR query ILIKE '%pg_sleep%';"
```
The real production fix is a design trade-off, not a one-line command:
either turn `hot_standby_feedback=on` so the standby tells the primary
"don't vacuum rows I still need" (at the cost of bloat accumulating on the
PRIMARY instead), or lower `max_standby_streaming_delay` so conflicting
standby queries get canceled quickly instead of stalling replay (at the
cost of canceling legitimate long-running read queries on the standby).
You cannot have long-running standby queries, an always-caught-up
standby, AND an always-clean primary simultaneously — pick which two.

**Lesson:** not every replication-lag incident is a resource problem.
`pg_stat_database_conflicts` on the standby is the one diagnostic step
that has nothing to do with OS-level resource checks at all, and it's the
only thing that would have caught this — a recovery conflict produces the
exact same headline symptom (`replay_lag` climbing) as CPU or I/O
contention, with zero evidence in `iostat`/`top`, and needs a completely
different fix (end the conflicting session, or change
`hot_standby_feedback`/`max_standby_streaming_delay`, not throttle a
container or buy faster disks).
