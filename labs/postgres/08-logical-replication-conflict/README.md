# Lab 08 — Logical Replication Conflict

## Objective
Break a logical replication subscription with a single duplicate-key
conflict, watch it take down *all* replication for that subscription —
not just the conflicting row — and fix it without losing data.

## Why this matters
Logical replication (`CREATE PUBLICATION` / `CREATE SUBSCRIPTION`)
applies changes row by row, in the order they were committed on the
publisher. If any single row's change can't be applied — most commonly
a unique-constraint violation, because something wrote directly to the
"read-only" subscriber and drifted out of sync — the subscription's
apply worker errors out, and Postgres just restarts it and tries again
from the same point. Every retry hits the exact same conflict and fails
the exact same way, so the subscription doesn't process a single row
past that point until a human intervenes — including rows that have
nothing to do with the conflict at all.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This brings up a publisher and a subscriber, replicates an `orders`
table between them, then: inserts a row directly on the *subscriber*
with `id=3`, inserts a *different* row with the same `id=3` on the
publisher (which will try to replicate and collide), and finally
inserts one more ordinary row (`id=4`) on the publisher afterward.

## Step 2 — Confirm replication is stuck
```bash
docker exec pglab8-subscriber psql -U postgres -d appdb -c "SELECT * FROM pg_stat_subscription;"
docker logs pglab8-subscriber 2>&1 | grep -i "duplicate key" | tail -5
```
The apply worker is crash-looping on
`duplicate key value violates unique constraint "orders_pkey"`.

## Step 3 — Confirm it's not just the one row
```bash
docker exec pglab8-publisher psql -U postgres -d appdb -c "SELECT * FROM orders ORDER BY id;"
docker exec pglab8-subscriber psql -U postgres -d appdb -c "SELECT * FROM orders ORDER BY id;"
```
The publisher has 4 rows. The subscriber is missing `id=4` entirely —
a row that has nothing to do with the conflict — because it's queued
behind the failing transaction in the same replication stream.

## Step 4 — Fix it without losing data
```bash
docker exec pglab8-subscriber psql -U postgres -d appdb -c "DELETE FROM orders WHERE id = 3;"
```
Deleting the row that's blocking the conflict clears the way for the
apply worker's next automatic retry (it retries on its own every few
seconds — no restart needed) to apply the publisher's version cleanly.

## Step 5 — Verify
```bash
./check.sh
```
This confirms the subscriber's `orders` table now matches the
publisher's exactly (including `id=4`), and that the replication worker
has a live, stable PID instead of crash-looping.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the fast fix that quietly loses data:**
```bash
./reset.sh
sleep 5
docker logs pglab8-subscriber 2>&1 | grep "duplicate key" -A2 | grep -oE "finished at [0-9A-Fa-f]+/[0-9A-Fa-f]+"
```
Take the LSN from that `CONTEXT` line and run:
```bash
docker exec pglab8-subscriber psql -U postgres -d appdb -c "ALTER SUBSCRIPTION orders_sub DISABLE;"
docker exec pglab8-subscriber psql -U postgres -d appdb -c "ALTER SUBSCRIPTION orders_sub SKIP (lsn = '<lsn>');"
docker exec pglab8-subscriber psql -U postgres -d appdb -c "ALTER SUBSCRIPTION orders_sub ENABLE;"
```
This is faster than Step 4 — no need to inspect or reconcile the
conflicting row by hand — and replication does resume. But compare
`orders` on both sides afterward. What happened to the publisher's
version of `id=3`, and why? What does `SKIP` actually discard — just
the one conflicting row, or something larger?

**Challenge B — restarting doesn't fix this:**
```bash
./reset.sh
sleep 5
docker compose restart subscriber
sleep 8
docker logs pglab8-subscriber 2>&1 | grep "duplicate key" | tail -3
```
The exact same error, immediately, after a full container restart.
Explain why a fresh apply worker — with a fresh connection, a fresh
process, nothing carried over in memory — fails in exactly the same
place every single time. What state is this actually being replayed
from, and where does that state live?

See `solution.md` only after you've formed your own diagnosis.
