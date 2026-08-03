# Lab 4 — Solutions

## Challenge A — stale statistics make a good index look bad

**Check:**
```bash
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM products WHERE category='rare';"
mysql -uroot -prootpass appdb -e "EXPLAIN ANALYZE SELECT * FROM products WHERE category='rare';"
mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM products WHERE category='rare';"
```
`EXPLAIN` still shows `key: idx_products_category` with a small `rows`
estimate (close to the original 50), but `SELECT COUNT(*)` reveals
`category='rare'` is actually ~200,050 rows now. `EXPLAIN ANALYZE` shows
the real elapsed time is far higher than the optimizer's row estimate
would predict — it's doing ~200,000 secondary-index lookups followed by
~200,000 individual primary-key row fetches (a secondary index in InnoDB
doesn't store the whole row, so each match costs an extra lookup back into
the clustered index), which is much more expensive than a single
sequential full table scan would have been for the same result set.

**Diagnosis:** with `innodb_stats_auto_recalc=OFF`, InnoDB's persisted
table/index statistics (`mysql.innodb_table_stats` /
`mysql.innodb_index_stats`) were never refreshed after the bulk `INSERT`
changed `category='rare'` from 0.01% of the table to roughly 40% of it.
The optimizer's plan choice is only as good as the cardinality estimates
it's working from — it picked the index because its stale statistics say
that's still a highly selective filter, when in reality a full table
scan (`type: ALL`) would now be cheaper than several hundred thousand
index-then-lookup round trips.

**Fix:**
```bash
mysql -uroot -prootpass appdb -e "ANALYZE TABLE products;"
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT * FROM products WHERE category='rare';"
```
After `ANALYZE TABLE` recomputes statistics, `EXPLAIN` should show a much
larger `rows` estimate for `category='rare'` and may switch to `type: ALL`
(or MySQL may still choose the index but with an accurate, much higher
cost estimate feeding into the rest of the query plan if this were part of
a larger join) — either way, the plan choice is now based on reality
instead of stale numbers.

**Lesson:** "the index isn't being used" and "the index is being used
questionably" are different problems with different fixes. A missing
index needs `CREATE INDEX`; a bad plan despite a perfectly good index
often needs `ANALYZE TABLE` — especially after any bulk load, backfill, or
large delete that changes a column's data distribution, since
`innodb_stats_auto_recalc`'s default threshold-based background refresh
(triggered after roughly 10% of a table's rows change) can lag well behind
the actual shape of your data, and can be disabled entirely, as this
challenge did on purpose.

---

## Challenge B — a function on the column defeats the index

**Check:**
```bash
mysql -uroot -prootpass appdb -e "EXPLAIN SELECT COUNT(*) FROM products WHERE YEAR(created_at) = 2023;"
```
`type: ALL`, `key: NULL`, despite `idx_products_created_at` existing on
exactly that column.

**Diagnosis:** `idx_products_created_at` is a B-tree index built on the
raw values of `created_at`, sorted as dates — it can only be used to
efficiently satisfy comparisons against `created_at` itself (`=`, `<`,
`>`, `BETWEEN`, etc.), because those map directly to a contiguous range
in the sorted index. `YEAR(created_at) = 2023` asks MySQL to compute
`YEAR()` on every row's value before it can compare — the index has no
way to look up "which index entries produce 2023 when passed through
`YEAR()`" without evaluating the function per row, which means scanning
all of them. This condition is **non-sargable** (not "Search ARGument
ABLE") — wrapping an indexed column in a function is one of the most
common ways to accidentally defeat an index that's perfectly correct.

**Fix:** rewrite the condition as a plain range comparison against the
raw column instead of transforming it:
```bash
mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT COUNT(*) FROM products
  WHERE created_at >= '2023-01-01' AND created_at < '2024-01-01';
"
```
`type` should now show `range`, `key: idx_products_created_at`, with
`rows` reflecting only the matching date range rather than the whole
table.

**Lesson:** an index existing on a column is not the same as an index
being *usable* for a specific query. Any function, calculation, or
implicit type conversion applied to an indexed column in a `WHERE` clause
(`YEAR(col)`, `DATE(col)`, `col + 1`, comparing a string column against a
number) can silently force a full scan even though `EXPLAIN`'s
`possible_keys` might make it look like the index should be a candidate.
Always check whether the condition can be rewritten to compare the raw
column directly before assuming a full scan means "no index exists."
