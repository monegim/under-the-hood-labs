# Lab 11 — Partition Pruning Failure: When the Optimizer Can't Skip Partitions

## Objective
Run queries against a RANGE-partitioned table, confirm pruning is working
for a normal date-range query, then run query patterns that silently
defeat pruning — a non-sargable expression on the partition key, and an OR
condition with an unconstrained branch — and learn to catch it with
`EXPLAIN`'s `partitions` column before it becomes "this query got slower
after we partitioned the table, somehow."

## Why this matters
Partitioning is usually adopted specifically to make date-range queries
fast by letting MySQL skip entire partitions it can prove contain no
matching rows — pruning. But pruning isn't automatic just because a table
is partitioned; it depends entirely on whether the optimizer can map your
query's predicate back to the partitioning expression at plan time. Wrap
the partition column in the wrong function, join through a table that
never mentions it, or `OR` it together with an unrelated condition, and
MySQL falls back to scanning every partition — silently. The query still
returns correct results, so nothing "breaks" in the way a bug normally
would; it just gets slower in proportion to how much data has accumulated
in the partitions that didn't need to be touched, which is exactly the
kind of regression that's easy to miss until the table is much bigger.

> Note on `EXPLAIN PARTITIONS`: older MySQL versions used
> `EXPLAIN PARTITIONS SELECT ...` as a distinct syntax. As of MySQL 8.0,
> the `PARTITIONS` keyword is gone — a plain `EXPLAIN SELECT ...` always
> includes the `partitions` column in its output now, no special syntax
> needed. This lab uses plain `EXPLAIN` throughout for that reason.

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
This creates `events`, a table partitioned `RANGE (YEAR(created_at))` into
`p2021`..`p2024` plus a catch-all `pmax`, populates ~20,000 rows spread
across 2021-2024, and creates an unpartitioned `order_items` table
referencing it (for the JOIN challenge).

## Step 2 — Confirm pruning works for a normal date-range query
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT COUNT(*) FROM events
  WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
"
```
Look at the `partitions` column — it should list only `p2024`. The
optimizer recognized the range predicate maps cleanly onto
`YEAR(created_at)` and skipped every other partition.

## Step 3 — Defeat pruning with a non-sargable expression
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT COUNT(*) FROM events
  WHERE created_at + INTERVAL 0 DAY = '2024-06-15';
"
```
Same logical predicate (rows on 2024-06-15), functionally a no-op
(`+ INTERVAL 0 DAY` doesn't change the value) — but now check the
`partitions` column: it lists `p2021,p2022,p2023,p2024,pmax`, all five.
Wrapping the partition column in an arithmetic expression makes it opaque
to the pruning logic — the optimizer can no longer prove which partitions
could contain matches, so it scans all of them, even though the actual
matching rows are only ever in one.

## Step 4 — Quantify the difference, not just the row estimate
`EXPLAIN`'s `rows` column is an estimate. Confirm the actual difference in
rows physically read:
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  FLUSH STATUS;
  SELECT COUNT(*) FROM events WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
  SHOW SESSION STATUS LIKE 'Handler_read%';
"
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  FLUSH STATUS;
  SELECT COUNT(*) FROM events WHERE created_at + INTERVAL 0 DAY = '2024-06-15';
  SHOW SESSION STATUS LIKE 'Handler_read%';
"
```
`Handler_read_rnd_next` in the second run should be roughly 4-5x higher
than the first — real, physical evidence of scanning every partition
instead of one, not just a plan-time estimate.

## Step 5 — Fix it: rewrite the predicate to stay sargable
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT COUNT(*) FROM events WHERE created_at = '2024-06-15';
"
```
`partitions` is back to just `p2024`. Same result set, same logical
question, just expressed as a direct comparison on the partition column
instead of an expression wrapped around it. The general rule: for pruning
to work, the partition column has to appear bare (or wrapped only in one
of the small set of functions MySQL's pruning logic explicitly understands
— `YEAR()`, `TO_DAYS()`, `TO_SECONDS()`, and a few others applied directly
to the column) on at least one side of the comparison.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a JOIN that never mentions the partition key:**
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT e.id, e.customer_id
  FROM events e
  JOIN order_items oi ON oi.event_id = e.id
  WHERE oi.sku = 'SKU-7';
"
```
Check the `partitions` column for the `events` table in this plan. All
partitions are scanned — but this time there's no wrong-function bug to
fix. Explain why pruning was never possible here in the first place, what
information the optimizer would have needed and didn't have, and what
options exist to fix this WITHOUT ripping out partitioning (hint: think
about what the application actually knows about the data it's asking for,
versus what's expressed in this specific query).

**Challenge B — an OR condition with one unconstrained branch:**
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT COUNT(*) FROM events
  WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'
     OR customer_id = 42;
"
```
The first half of this `OR`, on its own, would prune beautifully (compare
to Step 2). Check the `partitions` column for the combined query and
figure out why adding an unrelated `OR customer_id = 42` clause changes
the pruning result for the ENTIRE query, not just adds extra rows from
whichever partitions contain `customer_id = 42`. Then figure out a query
shape that gets you the same combined result set while still letting
MySQL prune down to fewer partitions.

See `solution.md` only after you've formed your own diagnosis.
