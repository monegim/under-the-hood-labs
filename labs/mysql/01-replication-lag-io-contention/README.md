# Lab 1 — DBRE Combo: Replication Lag from Host I/O Contention

## Objective
Stand up a real MySQL primary/replica pair, watch replication lag
(`Seconds_Behind_Source`) climb, and learn to diagnose it correctly: check
the replica's own OS-level resource usage BEFORE assuming it's a MySQL
configuration problem.

## Why this matters
This is the capstone of the whole repo — it combines Track 1/3 Linux
troubleshooting instincts (disk I/O contention, `iostat`, `docker stats`)
with DBRE-specific symptoms (`SHOW REPLICA STATUS`,
`Seconds_Behind_Source`). The single most common mistake in a real
replication-lag incident: jumping straight into MySQL config
(`replica_parallel_workers`, `innodb_buffer_pool_size`, network settings)
without first checking whether the replica's HOST is even capable of
keeping up — starved disk I/O, starved CPU, or a stuck lock upstream of
MySQL entirely will produce the exact same symptom (`Seconds_Behind_Source`
climbing) as an actual MySQL tuning problem, but need a completely
different fix.

## Prerequisites
- Docker + the `docker compose` plugin
- At least ~2GB free disk and some free RAM for two MySQL instances

Check first:
```bash
docker version
docker compose version
df -h .
```

## Step 1 — Bring up the incident
```bash
chmod +x setup.sh
./setup.sh
```
This script:
1. Starts `primary`, `replica`, and an idle `io-hog` container via
   `docker compose`.
2. Configures GTID-based replication (`CHANGE REPLICATION SOURCE TO
   ... SOURCE_AUTO_POSITION=1`) from `replica` to `primary`.
3. Creates an `orders` table and starts a **bounded** (~3 minute,
   self-terminating) write workload against `primary`.
4. Starts a **bounded** I/O contention burst on `io-hog` — 4 parallel
   writers, each overwriting the same 128MB file 40 times with
   `conv=fdatasync`, so total resident disk usage stays capped (~512MB)
   even though the total I/O throughput generated is large.

> Gotcha: `io-hog`'s scratch volume (`./data/replica-disk/io-hog-scratch`)
> and the replica's real MySQL datadir (`./data/replica-disk/mysql`) are
> bind-mounted from **sibling directories under the same host path** on
> purpose — they need to share the same underlying disk for the
> contention to be real, without `io-hog` ever touching MySQL's actual
> data files.

## Step 2 — Confirm replication is healthy first
```bash
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"
```
Right after setup finishes, this should show both threads `Yes` and
`Seconds_Behind_Source` at or near `0`.

## Step 3 — Watch it degrade
While the write workload and the I/O burst are both running (within a
couple minutes of `setup.sh` finishing), repeat:
```bash
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Seconds_Behind_Source|Replica_SQL_Running_State"
```
`Seconds_Behind_Source` should climb well above zero.

> Gotcha: don't reach for MySQL config yet. The instinct in a real
> incident is to start tuning `replica_parallel_workers` or checking
> network latency between primary and replica. Check the replica's OWN
> resource usage first — it's cheaper and it's usually the actual answer.

## Step 4 — Diagnose at the OS/container level, not the MySQL level
```bash
docker stats --no-stream
```
Look at `io-hog`'s I/O column — it should dwarf everything else. Then
confirm what's actually happening on disk (run this on the HOST/VM
itself, not inside a container — this is exactly the kind of check that
belongs at the infra layer, same instinct as Labs 23-27):
```bash
iostat -x 1 5
```
Look for high `%util` and elevated `await` on whichever device backs
Docker's storage. Cross-reference with `docker top lab30-io-hog` (works
even though the minimal MySQL image doesn't have `ps` installed — `docker
top` asks the HOST kernel for the container's processes, it doesn't need
anything installed inside the container) to confirm `dd` is the process
responsible.

## Step 5 — Fix it
The immediate fix for THIS incident — stop the noisy neighbor:
```bash
docker exec lab30-io-hog pkill dd || true
```
Watch the replica catch back up:
```bash
watch -n2 'docker exec lab30-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" | grep Seconds_Behind_Source'
```
`Seconds_Behind_Source` should fall back toward `0` as the SQL thread
works through the backlog in the relay log.

In a real production incident, you often can't just kill the other
workload — instead throttle it via cgroups, e.g.:
```bash
docker update --device-write-bps /dev/sdX:10mb lab30-io-hog
```
(substitute the actual host block device backing your Docker storage —
`docker info` / `lsblk` will tell you which one). The longer-term fix is
infra-level, same principle as the Linux track's CPU Steal Time lab: get the replica onto
its own dedicated disk/IOPS allocation instead of sharing one with
whatever else runs on that host.

## Re-triggering contention
Both generators from `setup.sh` are bounded and self-terminating. To
trigger another burst without re-running the whole script:
```bash
docker exec -d lab30-io-hog bash -c '
  for w in 1 2 3 4; do
    ( for i in $(seq 1 40); do dd if=/dev/zero of=/hogdata/hog-$w.dat bs=1M count=128 conv=fdatasync 2>/dev/null; done ) &
  done
  wait
'
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A:**
```bash
NPROC=$(docker exec lab30-io-hog nproc)
docker exec -d lab30-io-hog bash -c "
  for i in \$(seq 1 $NPROC); do
    ( timeout 240 yes > /dev/null ) &
  done
  wait
"
```
`Seconds_Behind_Source` climbs again, but this time `iostat` on the host
shows the disk barely busy. Diagnose what's actually being starved this
time, and how you'd tell the difference from Step 4's incident using only
`docker stats`/`iostat`/`top`.

**Challenge B:**
```bash
docker exec -d lab30-replica bash -c '
  mysql -uroot -prootpass -e "
    FLUSH TABLES WITH READ LOCK;
    SELECT SLEEP(180);
    UNLOCK TABLES;
  "
'
```
`Seconds_Behind_Source` climbs yet again, but now BOTH `iostat` and
`top`/`docker stats` show the replica host sitting nearly idle. Figure out
where the bottleneck actually is this time (hint: it isn't a resource at
all), and what you'd check on the MySQL side specifically to confirm it.

See `SOLUTION.md` only after you've formed your own diagnosis.
