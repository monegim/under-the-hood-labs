# Lab 11 — Solutions

## Challenge A — a JOIN condition that never touches the partition key

**Check:**
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT e.id, e.customer_id
  FROM events e JOIN order_items oi ON oi.event_id = e.id
  WHERE oi.sku = 'SKU-7';
"
```
`partitions` for `events` lists all five partitions.

**Diagnosis:** this isn't a "wrong function" bug like Steps 3-5 — there is
no expression to fix, because the query genuinely never provides any
information about `created_at` at all. The join condition is on
`event_id`/`id`, and the filter is on `order_items.sku`. Pruning works by
proving a partition can't possibly contain matching rows given the
predicates present; with zero predicates touching the partitioning column,
the optimizer has nothing to prove anything with, and correctly falls back
to scanning every partition — this is pruning working exactly as designed
given the information available, not a defect.

**Fix:** there's no query-syntax trick that manufactures information that
isn't there. Real options, in order of how much they change:
1. If the application actually knows a relevant date range for this kind
   of lookup (e.g. "order items are only ever queried for orders from the
   last 90 days"), add that as an explicit redundant filter:
   `WHERE oi.sku = 'SKU-7' AND e.created_at >= CURDATE() - INTERVAL 90 DAY`
   — even though it's implied by the data pattern, MySQL can't infer it on
   its own, and providing it lets pruning work again.
2. If lookups by `sku` with no date context are a first-class, frequent
   access pattern, that's a signal the table might be partitioned on the
   wrong column for this workload — partitioning is a trade-off that
   speeds up SOME access patterns at no benefit (or even slight cost) to
   others; it's not a universal accelerator.
3. A secondary index on the join/filter columns still helps regardless of
   partitioning — partition pruning and indexing are complementary, not
   substitutes for each other.

**Lesson:** partition pruning can only use information your query
actually expresses. A join or filter that doesn't reference the
partitioning column (directly or through a column functionally dependent
on it) will always full-scan every partition, no matter how the query is
phrased — the fix has to add real information, not rephrase the same
missing information more cleverly.

---

## Challenge B — an OR with one unconstrained branch poisons the whole query

**Check:**
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN SELECT COUNT(*) FROM events
  WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'
     OR customer_id = 42;
"
```
`partitions` lists all five, even though the first half of the `OR` alone
(Step 2) prunes to just `p2024`.

**Diagnosis:** pruning has to be provably correct for the ENTIRE
predicate, not clause-by-clause. A row could satisfy this `WHERE` by
matching `customer_id = 42` regardless of what `created_at` is — including
values in `p2021`, `p2022`, or `p2023`. Since the optimizer can't rule out
any partition containing a `customer_id = 42` row (customer_id has no
relationship to the partitioning expression), it can't prune ANY
partition for the query as a whole, even though one of the two `OR`
branches would have pruned beautifully on its own. One unconstrained
branch is enough to poison pruning for the entire combined condition.

**Fix:** split the two logically independent conditions into a `UNION`
instead of an `OR`, so each half is optimized (and pruned) independently:
```bash
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  EXPLAIN
  SELECT id FROM events WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'
  UNION
  SELECT id FROM events WHERE customer_id = 42;
"
```
Check `partitions` for each branch of the `UNION` separately (the EXPLAIN
output has one row per branch) — the first branch prunes to `p2024`
exactly like Step 2; the second branch still scans all partitions (that
part is unavoidable — `customer_id` genuinely isn't a partition-affine
column), but the OVERALL query now does less work than the single `OR`
form, because at least the first branch's cost was cut by 4/5.

**Lesson:** `OR` across a partition-prunable condition and a
partition-unrelated condition costs you pruning on BOTH branches, not just
the unrelated one. Rewriting as a `UNION` (or `UNION ALL` if duplicates
across the two branches are impossible or acceptable) lets each branch
prune independently, recovering the savings on the half that can actually
benefit from it.
