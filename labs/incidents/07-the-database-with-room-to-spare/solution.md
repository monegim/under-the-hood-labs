# Incident 07 — Solution

## Root cause

`postgres`'s data directory and `request-logger`'s log directory are
both subdirectories of the *same* underlying filesystem - a
volume deliberately mounted with a small, fixed inode ceiling
(`nr_inodes=3000` on a tmpfs volume, chosen so this reproduces
portably without a privileged loopback ext4 filesystem). `request-logger`
writes one tiny file per simulated "request," forever, on a fixed
interval - completely reasonable in isolation, exactly the kind of
per-request audit-log pattern a real service might have. It never opens
a single Postgres file and has no code path that touches the database
at all. It just needs to keep creating new files.

A filesystem's inode count and its byte capacity are two independent
resources. `request-logger`'s files are tiny - a few bytes each - so it
exhausts the volume's *inode* budget (every file or directory needs one,
regardless of size) long before it makes a dent in the volume's *byte*
budget. Once every inode is spoken for, `postgres` can keep writing to
files it already has open just fine - normal row inserts mostly just
extend an existing file's length, which doesn't need a new inode - but
the moment `users` grows enough to need a new supporting file (its
free-space map, in this incident) creating that file fails outright:
`could not create file "base/16384/16386_fsm": No space left on
device`. From that point on, every further write to that table hits
the exact same wall, because the table can't grow at all without the
file it can't create.

## Why it happened

Nobody who set up `request-logger` was thinking about Postgres at all
- from its own point of view, it's writing small files into its own
directory, which is exactly what it was built to do. The failure only
exists because of an infrastructure decision made somewhere else
entirely: whoever provisioned these containers put the database's data
directory and an unrelated logging directory on the *same* filesystem,
with a shared, finite inode budget neither workload has any visibility
into or accounting against. Two components with zero logical
relationship - one never queries the other, one never opens the
other's files - can still take each other down purely by sharing a
resource neither of them was ever told to watch.

## Why the obvious fixes don't work

- **Restarting `app` or `postgres`**: does nothing - the shared
  volume's inode table is untouched by a restart. `postgres` comes
  back up, tries the same write, hits the same "No space left on
  device."
- **Scaling `app` to more replicas**: doesn't help - there's still one
  Postgres instance, on one exhausted filesystem, and more app
  instances just means more connections all hitting the identical
  wall.
- **Deleting rows from `users`**: doesn't free a single inode.
  Deleting *rows* changes what's inside an already-existing file; the
  file itself (and the inode it occupies) is untouched. The problem
  was never "the table is too big," it's "the filesystem has no more
  inodes to hand out," and those are answered by two completely
  different actions.
- **Checking Postgres's own disk usage** (`du -sh` on the data
  directory, or Postgres's own size functions): shows a small, boring
  number, because none of this is about how much data Postgres has
  written. It's the filesystem's inode table, not Postgres's own
  storage accounting, that's actually full.

## The investigation

Confirm the symptom directly:
```bash
curl -s -X POST http://localhost:8080/signup \
  -H "Content-Type: application/json" -d '{"email":"test@example.com"}'
```
A `500` with a Postgres error message, not a timeout and not a clean
success.

Check the disk usage dashboard's own claim, on the volume Postgres's
data directory actually lives on:
```bash
docker exec incident07-postgres df -h /data
```
Comfortably under capacity, exactly as reported - bytes were never the
issue.

Check the other thing a filesystem tracks:
```bash
docker exec incident07-postgres df -i /data
```
`IUse%` at 100%, `IFree` at 0. This is the entire incident, in one
command most people don't reach for as automatically as `df -h`.

Confirm what's actually eating the shared budget - `du` won't show it
(files this small barely register in bytes), but a file count will:
```bash
docker exec incident07-postgres find /data/applogs -type f | wc -l
```
Thousands of tiny files, still growing, from a container the page
never mentioned.

Cross-check that `request-logger` is genuinely still writing, even
though it never appears in a database-focused view of this stack:
```bash
docker logs --tail 5 incident07-request-logger
docker top incident07-request-logger
```

## The fix

Immediate mitigation - stop the process still consuming inodes, then
reclaim what it already used:
```bash
docker compose stop request-logger
docker exec incident07-postgres sh -c "rm -rf /data/applogs/*"
```
Signups start succeeding again as soon as inodes are available - no
change to `postgres` or `app` at all.

The durable fix is architectural, not a cleanup script: give
`request-logger` (or whatever unrelated workload ends up sharing a
host with a database in production) its own isolated volume with its
own inode budget, so nothing it does - however pathological - can ever
threaten the database's own ability to write again. If per-request log
files are genuinely needed, batching them (one rotating file instead
of one-file-per-request) removes the unbounded inode growth at the
source, independent of which volume they end up on.

## Real-world examples of this pattern

- Session stores, mail queues, and any "one file per request/message"
  pattern are the classic real-world inode killers - they're designed
  around small individual files, which is precisely what makes them
  dangerous to anything sharing their filesystem.
- Container platforms that default every workload on a host to the
  same disk (a shared EBS volume, a single node's root filesystem) can
  reproduce this exact incident at the infrastructure level: one
  noisy-neighbor container's temp-file habit degrades a completely
  unrelated database's availability, with disk-usage-in-bytes
  dashboards showing nothing wrong the entire time.
- This is the database-flavored version of the exact mechanism in
  `labs/linux/11-disk-full-writes-fail` - there it's a generic "`df -h`
  says 20% full, but writes fail with `ENOSPC`" gotcha on a bare
  filesystem; here the same root cause shows up one layer higher, as a
  specific, cryptic Postgres file-creation error that looks like a
  database problem until you check the one metric the on-call
  dashboard never surfaced.
