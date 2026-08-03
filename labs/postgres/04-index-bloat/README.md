# Lab 34 — Index Bloat: The Row Count Lies

## Objective
Bloat a btree index through nothing but ordinary `UPDATE`s, confirm the
table's row count and even a plain `VACUUM` don't tell you anything is
wrong, then measure and fix the bloat with `pgstattuple` and
`REINDEX CONCURRENTLY`.

## Why this matters
Postgres never updates an index entry in place any more than it updates a
row in place — an `UPDATE` to an indexed column marks the old index entry
dead and inserts a new one, and `VACUUM` marks dead index entries as
reusable space WITHOUT necessarily shrinking the index file back down or
compacting half-empty pages. Enough churn on an indexed column, especially
with values that scatter across the whole key range instead of clustering,
leaves an index with far more allocated pages than its live entries need.
The table's row count stays exactly the same the whole time — this is
bloat that's invisible to `SELECT count(*)` and even to `n_dead_tup` on
the table itself, because it's the INDEX that's bloated, not the heap.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Bring up the incident
```bash
chmod +x setup.sh
./setup.sh
```
This script:
1. Starts a single Postgres instance via `docker compose`.
2. Enables the `pgstattuple` extension (bundled with the official image).
3. Creates a `widgets` table with a btree index on `sku`, seeded with
   50,000 rows.
4. Runs a bounded (30-round) workload of full-table `UPDATE`s that
   rewrite `sku` to a fresh random value every round — no `VACUUM`
   between rounds, so dead index entries accumulate across scattered
   pages.
5. Runs one plain `VACUUM` at the end — dead entries become reusable, but
   the index file does not shrink.

## Step 2 — See the misleading signal
```bash
docker exec lab34-primary psql -U postgres -d appdb -c "SELECT count(*) FROM widgets;"
```
Still 50,000 rows. Row count says nothing is wrong.

## Step 3 — Check the real signal
```bash
docker exec lab34-primary psql -U postgres -d appdb -c "
  SELECT version, tree_level, index_size, avg_leaf_density
  FROM pgstatindex('idx_widgets_sku');
"
```
> Gotcha: `avg_leaf_density` is `pgstattuple`'s measure of how full the
> index's leaf pages actually are — a freshly built btree is typically
> ~90% dense. A low value here (well under that) means most of
> `index_size` is empty space, not live entries, even though `VACUUM` has
> already run.

## Step 4 — Confirm it's the index, not the table
```bash
docker exec lab34-primary psql -U postgres -d appdb -c "
  SELECT pg_size_pretty(pg_relation_size('widgets')) AS table_size,
         pg_size_pretty(pg_relation_size('idx_widgets_sku')) AS index_size;
"
```
The table itself is roughly the size you'd expect for 50,000 rows. The
index, for the same 50,000 live entries, is not.

## Step 5 — Fix it online
A plain `REINDEX` takes an `ACCESS EXCLUSIVE` lock on the table for the
whole rebuild — blocking every read and write against it. `REINDEX
CONCURRENTLY` (PG12+) builds a new index alongside the old one while
normal reads/writes continue, then does a brief swap:
```bash
docker exec lab34-primary psql -U postgres -d appdb -c \
  "REINDEX INDEX CONCURRENTLY idx_widgets_sku;"
```
Confirm:
```bash
docker exec lab34-primary psql -U postgres -d appdb -c "
  SELECT avg_leaf_density FROM pgstatindex('idx_widgets_sku');
"
```
Should be back up near what a fresh index would show. Note:
`REINDEX CONCURRENTLY` cannot run inside an explicit transaction block,
and needs roughly double the disk space during the rebuild (old + new
index coexist briefly) — plan for that on a large index before running it
in production.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — "concurrently" still has to wait for something:**
```bash
docker exec -d lab34-primary bash -c '
  psql -U postgres -d appdb -c "
    BEGIN;
    SELECT * FROM widgets LIMIT 1;
    SELECT pg_sleep(60);
    COMMIT;
  "
'
# a couple seconds later, in another session:
docker exec lab34-primary psql -U postgres -d appdb -c \
  "REINDEX INDEX CONCURRENTLY idx_widgets_sku;"
```
The `REINDEX CONCURRENTLY` doesn't error, but it doesn't finish either —
it just sits there. Check `pg_stat_activity` for both sessions while
this is happening. What is `REINDEX CONCURRENTLY` actually waiting on,
and why does "concurrently" not mean "never blocks"?

**Challenge B — an interrupted `REINDEX CONCURRENTLY` leaves wreckage:**
```bash
docker exec -d lab34-primary psql -U postgres -d appdb -c \
  "REINDEX INDEX CONCURRENTLY idx_widgets_sku;"
sleep 1
docker restart -t 0 lab34-primary
```
(You may need to retry the timing once or twice — the goal is to kill
Postgres mid-rebuild, not after it finishes.) Once the container is back
up, `idx_widgets_sku` lookups still work, but something looks off in
`pg_indexes`/`pg_index`. Find it, and figure out why simply re-running
`REINDEX INDEX CONCURRENTLY idx_widgets_sku` again doesn't cleanly fix it
without one extra step first.

See `solution.md` only after you've formed your own diagnosis.
