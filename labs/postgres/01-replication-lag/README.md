# Lab 31 — Streaming Replication Lag, Localized

## Objective
Stand up a real Postgres primary/standby pair over streaming replication,
watch replay lag climb, and learn to localize WHERE in the pipeline the
lag actually is — network/receive vs. local replay/apply — before touching
any configuration.

## Why this matters
"Replication lag" is not one thing in Postgres. WAL has to travel from the
primary to the standby's `pg_wal` (the receive side, handled by the
walreceiver process) and THEN get replayed against the standby's own data
files (the apply side, handled by the startup process in recovery mode).
Either side can be the bottleneck, and they need completely different
fixes: receive-side lag usually means network throughput/latency between
primary and standby; replay-side lag usually means the standby's own host
can't keep up (disk I/O, CPU, or something inside Postgres itself blocking
apply). Treating "lag" as a single number and guessing is how people tune
the wrong thing. This lab is built to prove replay-side lag from host
contention, the same instinct as the MySQL sibling lab.

## Prerequisites
- Docker + the `docker compose` plugin
- At least ~2GB free disk and some free RAM for two Postgres instances

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
1. Starts `primary`, `standby`, and an idle `io-hog` container via
   `docker compose`.
2. The standby's custom entrypoint takes a `pg_basebackup -R` from the
   primary on first start, which writes `standby.signal` and
   `primary_conninfo` for us — the standard way to stand up streaming
   replication from PG12 onward.
3. Creates an `orders` table and starts a **bounded** (~3 minute,
   self-terminating) write workload against `primary`.
4. Starts a **bounded** I/O contention burst on `io-hog` — 4 parallel
   writers, each overwriting the same 128MB file 40 times with
   `conv=fdatasync`, so total resident disk usage stays capped (~512MB)
   even though the total I/O throughput generated is large.

> Gotcha: `io-hog`'s scratch volume (`./data/standby-disk/io-hog-scratch`)
> and the standby's real PGDATA (`./data/standby-disk/pgdata`) are
> bind-mounted from **sibling directories under the same host path** on
> purpose — they need to share the same underlying disk for the
> contention to be real, without `io-hog` ever touching Postgres's actual
> data files.

## Step 2 — Confirm replication is healthy first
```bash
docker exec lab31-primary psql -U postgres -c \
  "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, replay_lag FROM pg_stat_replication;"
```
Right after setup finishes, `state` should be `streaming` and `replay_lag`
should be small/null.

## Step 3 — Watch it degrade
While the write workload and the I/O burst are both running (within a
couple minutes of `setup.sh` finishing), repeat:
```bash
docker exec lab31-primary psql -U postgres -c \
  "SELECT replay_lag, write_lag, flush_lag FROM pg_stat_replication;"
```
`replay_lag` should climb well above what it was.

> Gotcha: don't reach for `replica_parallel_workers`-style tuning or
> network settings yet. First figure out whether Postgres has even
> RECEIVED the WAL it's slow to apply — that tells you whether this is a
> network problem or a standby-host problem, and they need different
> fixes entirely.

## Step 4 — Localize: receive side or replay side?
On the standby itself:
```bash
docker exec lab31-standby psql -U postgres -c \
  "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"
```
If `pg_last_wal_receive_lsn()` is way ahead of `pg_last_wal_replay_lsn()`,
the WAL has already arrived — the standby's walreceiver is doing its job
fine. The bottleneck is REPLAY (applying WAL to local data files), not the
network. Confirm the receive side is actually healthy:
```bash
docker exec lab31-standby psql -U postgres -c \
  "SELECT status, received_lsn, latest_end_lsn FROM pg_stat_wal_receiver;"
```
`status` should be `streaming` and `received_lsn` should be moving right
along with the primary — the gap is entirely downstream of receipt.

## Step 5 — Diagnose at the OS/container level, not the Postgres level
```bash
docker stats --no-stream
```
Look at `io-hog`'s I/O column — it should dwarf everything else. Then
confirm what's actually happening on disk (run this on the HOST/VM
itself, not inside a container):
```bash
iostat -x 1 5
```
Look for high `%util` and elevated `await` on whichever device backs
Docker's storage. Cross-reference with `docker top lab31-io-hog` to
confirm `dd` is the process responsible. The standby's replay process
(the startup process, applying WAL to heap/index pages) needs random
read/write I/O to the same disk `io-hog` is hammering — that's why replay
suffers while the comparatively cheap sequential append of receiving raw
WAL bytes barely notices.

## Step 6 — Fix it
Stop the noisy neighbor:
```bash
docker exec lab31-io-hog pkill dd || true
```
Watch replay catch back up:
```bash
watch -n2 'docker exec lab31-primary psql -U postgres -c "SELECT replay_lag FROM pg_stat_replication;"'
```
`replay_lag` should fall back toward `0`/null as the standby works
through the WAL it already received but hadn't yet applied.

In a real production incident, you often can't just kill the other
workload — throttle it via cgroups instead:
```bash
docker update --device-write-bps /dev/sdX:10mb lab31-io-hog
```
(substitute the actual host block device backing your Docker storage).
The longer-term fix is infra-level: give the standby its own dedicated
disk/IOPS allocation instead of sharing one with whatever else runs on
that host.

## Re-triggering contention
Both generators from `setup.sh` are bounded and self-terminating. To
trigger another burst without re-running the whole script:
```bash
docker exec -d lab31-io-hog bash -c '
  for w in 1 2 3 4; do
    ( for i in $(seq 1 40); do dd if=/dev/zero of=/hogdata/hog-$w.dat bs=1M count=128 conv=fdatasync 2>/dev/null; done ) &
  done
  wait
'
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A:**
```bash
NPROC=$(docker exec lab31-io-hog nproc)
docker exec -d lab31-io-hog bash -c "
  for i in \$(seq 1 $NPROC); do
    ( timeout 240 yes > /dev/null ) &
  done
  wait
"
```
`replay_lag` climbs again, but this time `iostat` on the host shows the
disk barely busy. Diagnose what's actually being starved this time, and
how you'd tell the difference from Step 5's incident using only
`docker stats`/`iostat`/`top`.

**Challenge B:**
```bash
docker exec -d lab31-standby bash -c '
  psql -U postgres -d appdb -c "
    BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    SELECT count(*) FROM orders;
    SELECT pg_sleep(180);
    COMMIT;
  "
'
# meanwhile, back on the primary, churn the same rows so old versions need cleaning up:
docker exec -d lab31-primary bash -c '
  for i in $(seq 1 20); do
    psql -U postgres -d appdb -c "UPDATE orders SET data = repeat(chr(65+(random()*25)::int),200);" >/dev/null 2>&1
    psql -U postgres -d appdb -c "VACUUM orders;" >/dev/null 2>&1
    sleep 2
  done
'
```
`replay_lag` climbs yet again, but now BOTH `iostat` and `top`/`docker
stats` show the standby host sitting nearly idle. Figure out where the
bottleneck actually is this time (hint: it isn't a resource at all — the
standby was even started with `hot_standby_feedback=off` and a raised
`max_standby_streaming_delay` on purpose), and what standby-side system
view would confirm it directly.

See `solution.md` only after you've formed your own diagnosis.
