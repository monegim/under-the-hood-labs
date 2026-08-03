# Lab 4 — A Query That Used to Be Fast Isn't Anymore

## Objective
Reproduce the most common shape of MySQL performance incident — a query
that was fine when the table was small and is now slow — using the slow
query log and `EXPLAIN` to find and fix a missing index, then use
`ANALYZE TABLE` to fix a *different* kind of slowdown: a plan that went
bad because the optimizer's statistics are stale, not because an index is
missing.

## Why this matters
"It was fast last month" is one of the most common DBRE tickets there is,
and the instinct to just "add an index" isn't always right — sometimes
the index already exists and the real problem is that the optimizer's
cardinality estimates are out of date, or the query itself is written in
a way that can't use the index it has. Treating every slow query as a
missing-index problem means you'll eventually "fix" something that wasn't
actually broken that way, and miss the real cause.

## Prerequisites
- Ubuntu VM, sudo access
- `mysql-server` (installed by `setup.sh`)
- A few hundred MB free disk (500k-row table) and a minute or two for
  `setup.sh` to generate it

Check first:
```bash
uname -a
which mysql
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This enables the slow query log (`long_query_time=0.2`, plus
`log_queries_not_using_indexes=1` as a safety net so this shows up
regardless of how fast your VM's disk is), generates a 500,000-row
`products` table with **no index on `sku` or `category`** — only the
`id` primary key — and fires 20 point lookups by `sku`, the exact
pattern a real app would use to look up "the product with this SKU."

## Step 2 — Find it in the slow query log
```bash
sudo tail -n 40 /var/log/mysql/mysql-slow.log
```
Look for `# Query_time:` lines around the `SELECT * FROM products WHERE
sku=...` queries. If `mysqldumpslow` is available, it's easier to read in
aggregate:
```bash
sudo mysqldumpslow -s t /var/log/mysql/mysql-slow.log | head -20
```

## Step 3 — Confirm it with EXPLAIN
```bash
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM products WHERE sku='SKU-000123';"
```
> Gotcha: look at the `type` column, not just whether `key` is `NULL`.
> `type: ALL` means a full table scan; `rows` shows roughly how many rows
> MySQL expects to examine (should read close to 500000 — the entire
> table — for one row you want).

For a more detailed cost breakdown:
```bash
mysql -uroot -prootpass appdb -e "EXPLAIN ANALYZE SELECT * FROM products WHERE sku='SKU-000123';"
```
`EXPLAIN ANALYZE` actually *runs* the query and reports real timing per
step, not just the optimizer's estimate — useful when you don't trust the
estimate alone.

## Step 4 — Fix it: add the missing index
```bash
mysql -uroot -prootpass appdb -e "CREATE INDEX idx_products_sku ON products(sku);"
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM products WHERE sku='SKU-000123';"
```
`type` should now show `const` or `ref`, `key: idx_products_sku`, and
`rows` should drop to `1`.

## Step 5 — Confirm the fix with a real timing comparison
```bash
mysql -uroot -prootpass appdb -e "EXPLAIN ANALYZE SELECT * FROM products WHERE sku='SKU-000123';"
```
Compare the `actual time=` value against Step 3's — should be dramatically
lower now that MySQL isn't scanning all 500,000 rows for one match.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — stale statistics, not a missing index:**
```bash
mysql -uroot -prootpass -e "SET GLOBAL innodb_stats_auto_recalc=OFF;"
mysql -uroot -prootpass appdb -e "
  UPDATE products SET category='rare' WHERE id <= 50;
  CREATE INDEX idx_products_category ON products(category);
  ANALYZE TABLE products;
"
echo "--- baseline plan while 'rare' really is rare (50 out of 500000 rows) ---"
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM products WHERE category='rare';"

echo "--- now a big backfill lands: 'rare' stops being rare, but we don't re-analyze ---"
mysql -uroot -prootpass appdb -e "
  INSERT INTO products (sku, category, price, created_at)
  SELECT CONCAT('SKU-BULK-', id), 'rare', price, created_at FROM products WHERE id BETWEEN 100000 AND 300000;
"
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM products WHERE category='rare';"
```
The index on `category` still exists and `EXPLAIN` still picks it — but
`category='rare'` is now roughly 40% of the table, not 0.01%. Compare
`EXPLAIN ANALYZE` timing here against a plain `EXPLAIN ANALYZE SELECT *
FROM products;` full scan of the same table, and figure out what's
actually gone wrong (hint: nothing is missing this time).

**Challenge B — an index that exists but can't be used:**
```bash
mysql -uroot -prootpass appdb -e "CREATE INDEX idx_products_created_at ON products(created_at);"
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT COUNT(*) FROM products WHERE YEAR(created_at) = 2023;"
```
There's an index directly on `created_at`, and `EXPLAIN` still shows
`type: ALL`. Figure out exactly why the optimizer can't use an index that
unambiguously exists on the exact column in the `WHERE` clause, and rewrite
the query so it can.

See `solution.md` only after you've formed your own diagnosis.
