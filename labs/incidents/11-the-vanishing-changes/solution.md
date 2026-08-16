# Incident 11 — Solution

## Root cause

`app`'s `POST /save` always writes to `primary`. `GET /note/<id>` reads
from `replica` (`READS_FROM=replica` in `docker-compose.yml`) - a common
"scale out reads" choice that silently assumes replication is
synchronous. It isn't: MySQL's default asynchronous replication means
`primary` acknowledges a `COMMIT` as soon as *its own* binlog write is
durable, without waiting for `replica` to receive or apply that
transaction at all. Under light load with an idle replica, the gap is
usually a few milliseconds - small enough that a user who saves, waits a
beat, then reloads almost never notices. `reporting-job` changes that: it
runs a permanent, unrelated write workload (`dd ... conv=fdatasync`) into
a directory that's bind-mounted from the **same underlying host disk** as
`replica`'s real datadir (`./data/replica-disk/mysql` and
`./data/replica-disk/reporting-scratch` are sibling directories on
purpose - same trick as incident 04). `reporting-job` never touches a
MySQL file, but it keeps that shared disk's I/O queue busy enough that
`replica`'s SQL/apply thread stays measurably, continuously behind -
seconds behind, not milliseconds. Any `GET /note/<id>` that lands in that
window sees whatever `replica` last had: the previous value, or nothing
at all if the row was just inserted. A moment later, once the apply
thread catches up, the exact same `GET` returns the correct value - which
is exactly the "it saved fine, then reverted, then came back" pattern in
the tickets.

## Why it happened

Nothing in `app.py` is buggy in the usual sense - `POST /save` does an
`INSERT ... ON DUPLICATE KEY UPDATE` and commits, full stop; `GET
/note/<id>` does a plain `SELECT`. Reading from a replica to spread out
read load is also a completely standard, reasonable pattern on its own.
The bug only exists at the seam between the two: nobody asked "does a
user need to see their own write immediately after making it, and if so,
which host can guarantee that?" Async replication was never lying about
what it does - MySQL's own documentation is explicit that replicas apply
changes after the fact, on their own schedule - the application was just
built as if "the database" were one consistent thing instead of two
instances with a real, variable gap between them.

## Why the obvious fixes don't work

- **Looking for a delete, a TTL, a cache eviction, or a bug in the save
  code**: there isn't one. `notes.text` is never deleted or overwritten
  with a wrong value on `primary` - `primary` has the correct data the
  entire time. The "vanishing" only ever happens on the read side.
- **Restarting `app`**: reconnects to the exact same `primary`/`replica`
  split, with `reporting-job` still contending for the replica's disk.
  The next `POST`-then-`GET` race is just as likely as before.
- **Retrying the `GET` a couple of times client-side**: masks the
  symptom under mild lag but doesn't fix it, and gives no guarantee under
  worse contention - it's papering over an unbounded window, not closing
  it.
- **Adding more read replicas to "spread the load"**: makes it worse, not
  better - more replicas means more chances that a given read lands on
  one that hasn't caught up yet.
- **Throwing more CPU or memory at either MySQL host**: this was never a
  compute problem - `primary` and `replica` are both fast, individually
  correct, and doing exactly what they're configured to do.

## The investigation

Reproduce the symptom directly - write, then read immediately:
```bash
curl -s -X POST http://localhost:8080/save \
  -H "Content-Type: application/json" -d '{"id":"note-1","text":"first"}'
curl -s http://localhost:8080/note/note-1
```
Run this in a loop a few times in a row (or use `check.sh`) and some
iterations will come back `404 not_found` or with stale text, even though
the `POST` itself always reports `"status":"saved"`.

Check replication health directly while reproducing:
```bash
docker exec incident11-replica mysql -uroot -prootpass -e \
  "SHOW REPLICA STATUS\G" | grep -E "Seconds_Behind_Source|Replica_SQL_Running_State"
```
`Seconds_Behind_Source` sits above zero, not spiking-and-recovering to 0
in a blink the way a healthy, idle replica would.

Compare the two instances directly, bypassing the app entirely:
```bash
docker exec incident11-primary mysql -uroot -prootpass appdb -e \
  "SELECT * FROM notes WHERE id='note-1';"
docker exec incident11-replica mysql -uroot -prootpass appdb -e \
  "SELECT * FROM notes WHERE id='note-1';"
```
Run this right after a save - `primary` already has the new value,
`replica` may still show the old one (or no row, if it's a new id).

Confirm *why* the replica is behind - check the resource layer, not MySQL
config, same instinct as incident 04:
```bash
docker stats --no-stream
iostat -x 1 5
```
`reporting-job`'s block I/O dwarfs everything else; `iostat` on the host
shows high `%util`/`await` on the disk backing `./data/replica-disk`.
`docker top incident11-reporting-job` confirms the `dd` processes, even
though the `mysql`/`alpine` images involved don't ship a full process
toolset.

The response body itself is a built-in clue: `GET /note/<id>` includes
`"read_from": "<host>"` - confirming every read in this incident actually
goes to `replica`, not `primary`.

## The fix

Immediate mitigation - stop contending for the replica's disk:
```bash
docker compose stop reporting-job
```
This shrinks the lag window a lot, but doesn't eliminate it - async
replication still has *some* nonzero delay even on an idle host, so this
alone doesn't make the read-after-write pattern actually correct, just
less likely to be noticed.

The real fix is architectural, not a config toggle to "turn on sync
replication" (MySQL's semisynchronous mode still only waits for the
change to reach a replica's relay log, not to be applied and readable -
it narrows the window, it doesn't close it):
- Route reads that need to see their own recent writes to `primary`
  instead of a replica - this lab's `app` supports this directly via
  `READS_FROM=primary` in `docker-compose.yml`, followed by
  `docker compose up -d app`.
- If replica reads are worth keeping for scale, do it selectively: read
  from `primary` for a short window right after a write from the same
  session (a "read-your-writes" / sticky-primary pattern), and fall back
  to replicas for everything else.
- Alert on `Seconds_Behind_Source` as a real SLI if replicas serve any
  user-facing reads at all - "replication is lagging" should page before
  support tickets do.

## Real-world examples of this pattern

- Postgres and MySQL "read replica for scaling" setups are one of the
  most common sources of "my data disappeared" tickets in web apps -
  documented extensively in both projects' own replication docs
  (https://dev.mysql.com/doc/refman/8.0/en/replication.html) as expected,
  by-design behavior, not a bug to file against the database.
- Managed database services (RDS read replicas, Cloud SQL read replicas)
  make this an explicit, named trade-off in their own documentation -
  "eventually consistent" reads - precisely because so many teams wire up
  a replica for read scaling without an explicit read-your-writes story
  for the paths that need one.
- The same mechanism, presenting differently: this is the app-visible
  twin of `labs/mysql/01-replication-lag-io-contention` and incident 04 -
  same "unrelated workload saturates the shared disk under a MySQL
  instance" root cause, but here the symptom isn't slow commits, it's a
  read landing on the wrong side of a replication gap.
