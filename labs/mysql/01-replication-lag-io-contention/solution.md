# Lab 1 — Solutions

## Challenge A — CPU contention, not I/O

**Check:**
```bash
iostat -x 1 5
docker stats --no-stream
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Seconds_Behind_Source|Replica_SQL_Running_State"
```
`iostat` shows `%util` low/normal on the underlying disk — nothing like
the saturation from the main lab. `docker stats` instead shows `io-hog`
pinning close to 100% CPU per core across all of the host's cores, while
`replica`'s CPU% is much lower than it needs to make progress.
`Seconds_Behind_Source` is climbing the same way it did in Step 3.

**Diagnosis:** this time the disk is fine — the replica's SQL/apply
thread simply isn't getting scheduled enough CPU time to work through the
relay log, because an unrelated CPU-bound process (`io-hog`'s `yes`
loops) is saturating every core on the shared host. Docker's default CPU
shares are a *fair-share* allocation, not a hard reservation — when the
host is genuinely oversubscribed, every container's actual CPU time
shrinks, including containers doing important work like replication
apply. Same symptom as Step 3 (`Seconds_Behind_Source` up), completely
different resource at fault. This is the same category of lesson as Lab
27 (steal time): a resource-starved consumer of replication data looks
identical from the `Seconds_Behind_Source` number alone — you have to look
at the resource layer to tell CPU starvation apart from I/O starvation.

**Fix:**
```bash
docker exec lab30-io-hog pkill yes
```
Or, to prevent recurrence without having to kill legitimate workloads in
production, cap the noisy container's CPU allocation instead:
```bash
docker update --cpus="2" lab30-io-hog
```

**Lesson:** "replication lag" is a symptom with more than one possible
resource-layer cause. Before touching MySQL config, check disk (`iostat`),
then CPU (`top`/`mpstat`/`docker stats`) — don't assume it's always disk
just because that's the more commonly told story.

---

## Challenge B — a lock, not a resource at all

**Check:**
```bash
iostat -x 1 5
top
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW PROCESSLIST\G"
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Seconds_Behind_Source|Replica_SQL_Running_State"
```
`iostat` and `top` both show the replica host close to idle — no disk
saturation, no CPU saturation. `SHOW REPLICA STATUS` still shows
`Seconds_Behind_Source` climbing. `SHOW PROCESSLIST` reveals a connection
sitting in `SELECT SLEEP(180)` that is still holding a global lock it took
out earlier with `FLUSH TABLES WITH READ LOCK`.

**Diagnosis:** `FLUSH TABLES WITH READ LOCK` blocks every write on the
server, and the replication SQL/apply thread's job is entirely writes
(applying relay log events). It doesn't matter that CPU and disk are both
free — the apply thread is simply blocked waiting for a lock that has
nothing to do with hardware resources at all. This is a very real incident
pattern: a backup tool or an ad-hoc maintenance session takes a global
read lock on a replica (common with older backup workflows), the session
doesn't release it promptly (a hung script, a forgotten `UNLOCK TABLES`,
a long-running report query kept in the same session), and replication
silently stalls behind it with no OS-level symptom to point to.

**Fix:**
```bash
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW PROCESSLIST" | grep Sleep
# find the offending connection id, then:
docker exec lab30-replica mysql -uroot -prootpass -e "KILL <id>;"
```
Killing the blocking session releases the lock immediately; the SQL
thread resumes and `Seconds_Behind_Source` drains back toward `0`.

**Lesson:** not every replication-lag incident is infra-caused. Always
check the replica's own MySQL-level state (`SHOW PROCESSLIST`, lock/wait
status) alongside OS-level resource checks — a stuck lock produces the
exact same headline symptom (`Seconds_Behind_Source` climbing) as CPU or
I/O contention, with zero evidence in `iostat`/`top`, and needs a
completely different fix (kill the session, not throttle a container or
buy faster disks).
