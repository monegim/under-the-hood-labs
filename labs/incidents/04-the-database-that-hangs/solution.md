# Incident 04 — Solution

## Root cause

`backup-job` runs four parallel `dd` processes in a permanent loop,
each writing a 128MB file with `conv=fdatasync` - meaning every write
is forced to disk immediately, not left in the page cache. Its scratch
directory (`./data/disk/backup-scratch`) and MySQL's real datadir
(`./data/disk/mysql`) are bind-mounted from sibling subdirectories of
the *same host path* on purpose, so they sit on the exact same
underlying disk. `backup-job` never touches a single MySQL data file -
it doesn't need to. It just needs to keep that shared disk's I/O queue
saturated.

MySQL's default durable-commit setting
(`innodb_flush_log_at_trx_commit=1`) means every `COMMIT` has to
`fsync()` the InnoDB redo log to disk before it can return success to
the client. `fsync()` doesn't care whose data is where on the device -
it has to wait for the physical device to confirm the write is durable,
and when four `dd` processes are continuously saturating that device's
write queue, MySQL's `fsync()` calls queue up right behind them.
Reads are unaffected because most reads are served from InnoDB's buffer
pool in memory and never have to wait on disk at all - only writes that
go through a full commit pay the fsync tax, which is exactly why "reads
are fine, writes are slow" is the reported symptom.

## Why it happened

`backup-job` was never designed with any awareness that something else
shares its disk - from its own point of view it's just writing files to
its own directory as fast as it can, which is completely reasonable in
isolation. The failure mode only exists at the *infrastructure* level:
whoever provisioned these containers didn't separate "the database's
disk" from "whatever else runs on this host's disk," so a workload with
zero logical relationship to the database (it never opens a MySQL file,
never sends MySQL a query) can still stall every write MySQL tries to
make, purely through shared physical I/O contention.

## Why the obvious fixes don't work

- **Scaling `app` to more replicas**: doesn't help - there's still one
  MySQL instance, on one disk, contending with the same `backup-job`.
  More app instances just means more connections queuing on the same
  slow commits.
- **Tuning MySQL's buffer pool / query cache / connection settings**:
  irrelevant - this isn't a caching or query-planning problem. The
  query itself is instant; it's the `COMMIT`'s `fsync()` that's slow,
  and no amount of buffer-pool tuning changes how fast the physical
  disk acknowledges a write.
- **Restarting `app` or `mysql`**: does nothing - `backup-job` is
  untouched and the disk is exactly as contended five seconds after
  the restart as it was before.
- **Adding CPU or memory to the host**: matches the page's own numbers
  (CPU and memory both look normal) - there's no compute or memory
  bottleneck to fix here, only I/O.

## The investigation

Confirm the symptom directly:
```bash
time curl -s -X POST http://localhost:8080/save \
  -H "Content-Type: application/json" -d '{"payload":"test"}'
```
Multi-second response time (or a timeout), where the same call was near-
instant before the incident.

Check container-level resource usage:
```bash
docker stats --no-stream
```
CPU and memory on `app` and `mysql` are unremarkable. The `BLOCK I/O`
column for `backup-job` dwarfs everything else.

Confirm it at the host/disk level, not just inside a container - this is
the layer that actually matters here:
```bash
iostat -x 1 5
```
Run on the Docker host itself. Look for `%util` near 100% and elevated
`await` on whichever device backs Docker's storage for this stack.

Cross-check which process is responsible:
```bash
docker top incident04-backup-job
```
Shows the `dd` processes actively running, even though the minimal
`mysql`/`alpine` images involved don't have a full process-inspection
toolset installed inside them - `docker top` asks the *host* kernel for
the container's processes, so it works regardless.

Confirm where MySQL itself is stuck, while a slow save is in flight:
```bash
docker exec incident04-mysql mysql -uroot -prootpass -e "SHOW PROCESSLIST\G"
```
The app's connection sits with a climbing `Time` value in a commit-
related wait state rather than actively executing a query - the INSERT
itself finished immediately; the connection is stuck waiting for the
transaction's fsync to be acknowledged by the (contended) disk.

## The fix

Immediate mitigation - stop the noisy neighbor:
```bash
docker compose stop backup-job
```
`/save` latency drops back to near-instant within seconds.

In a real incident you often can't just kill the other workload -
instead throttle its disk I/O via cgroups, e.g.:
```bash
docker update --device-write-bps /dev/sdX:10mb incident04-backup-job
```
(substitute the actual host block device backing your Docker storage).
The durable long-term fix is infrastructure-level: give the database its
own dedicated disk/IOPS allocation instead of sharing one with anything
else, and schedule genuinely heavy batch/backup I/O for windows and
volumes that can't contend with the database's commit path.

## Real-world examples of this pattern

- Cloud block storage (EBS, Persistent Disk, Azure Disk) with a shared
  IOPS/throughput budget: an unrelated batch job, log-rotation task, or
  even another VM on the same underlying SAN/host can silently steal
  I/O from a database that has no idea anything else exists.
- "The app hangs on save, nothing in the logs" is one of the most
  common DBRE-adjacent tickets there is, precisely because the app and
  the database are both behaving correctly from their own point of view
  - the actual bottleneck is a layer neither of them can see into
  without host-level tools like `iostat`.
- This is the same root mechanism as `labs/mysql/01-replication-lag-io-contention`
  (an unrelated process saturating a shared disk), presenting completely
  differently: there it showed up as replication lag between two MySQL
  instances; here it shows up as commit latency on a single instance
  that customers feel directly as "the app hangs on save."
