# Lab 4 — Concept: The Optimizer Is Only as Good as What It's Working From

## What's actually going on

MySQL's query optimizer doesn't know your data — it estimates. For any
given query, it looks at the available indexes, the statistics it has
cached about how many rows exist and how values are distributed
(cardinality estimates, kept in `mysql.innodb_table_stats` and
`mysql.innodb_index_stats` for InnoDB tables under
`innodb_stats_persistent=ON`, the 8.0 default), and picks whichever
access plan it *estimates* will be cheapest — a full table scan, an index
lookup, a range scan, and so on. That estimate can be wrong in two
completely different ways, and this lab is built to make you tell them
apart. The most obvious way: no index exists for the column you're
filtering on, so the only plan available really is a full scan — `EXPLAIN`
shows `type: ALL`, and the fix genuinely is `CREATE INDEX`. The less
obvious way: an index exists, `EXPLAIN` says the optimizer is using it,
and it's still the wrong choice — because the row-count and selectivity
numbers the optimizer is using to make that judgment are stale relative to
what the table actually looks like right now.

The slow query log (`slow_query_log`, `long_query_time`) exists to catch
both cases at the traffic level rather than requiring you to already
suspect a specific query — anything running longer than the threshold
(or, with `log_queries_not_using_indexes=1`, anything not using an index
at all regardless of how fast it happened to run) gets written out with
its actual execution time. `EXPLAIN` then shows you the *plan* the
optimizer chose without running the query; `EXPLAIN ANALYZE` (added in
8.0.18) actually executes the query and reports real per-step timing
alongside the original estimates — which is exactly what's needed to
catch the stale-statistics case, because the mismatch between the
optimizer's `rows` estimate and the real number of rows actually processed
is the tell that something in the optimizer's model of the data doesn't
match reality anymore.

`ANALYZE TABLE` forces InnoDB to recompute those persisted statistics
immediately by sampling pages of the table. Under
`innodb_stats_auto_recalc` (on by default), MySQL is supposed to trigger
this automatically once roughly 10% of a table's rows have changed since
the last analysis — but that's a background, best-effort mechanism, not
an instant guarantee, and it can be disabled outright (as this lab's
Challenge A does, to make the staleness deterministic and reproducible
rather than racing a background thread). Any workload with a large,
sudden shift in data distribution — a bulk backfill, a big archival
delete, importing a partner's dataset — can outrun that auto-recalc
threshold, or land right in the window before it fires, leaving the
optimizer making decisions based on a shape of the data that no longer
exists.

A third, distinct failure mode — Challenge B — has nothing to do with
statistics or missing indexes at all: a perfectly good, perfectly
up-to-date index can be completely unusable for a specific query if the
`WHERE` clause wraps the indexed column in a function or expression
(`YEAR(created_at)`, `LOWER(email)`, implicit type coercion between a
string column and a numeric literal). A B-tree index is built on the
literal sorted values of a column; MySQL can only use it directly for
comparisons against those literal values. The moment you transform the
column before comparing it, the index's sort order no longer corresponds
to anything useful for that comparison, and MySQL falls back to
evaluating the expression row-by-row — a full scan, even though
`possible_keys` and the index definition both look correct at a glance.

## Where this shows up in the real world

"This query used to be instant" is one of the most common DBRE tickets,
and reflexively adding an index is the wrong response often enough to be
worth checking first: teams that add indexes without checking `EXPLAIN`
first sometimes discover the index they added isn't even the one being
used, or that the real fix was `ANALYZE TABLE` after a migration/backfill
job, or that the query itself needs rewriting to be sargable. Bulk data
migrations, ETL backfills, and archival/cleanup jobs are the most common
real-world trigger for the stale-statistics failure mode specifically —
any process that changes a large fraction of a table's rows in one shot
is exactly the scenario `innodb_stats_auto_recalc`'s threshold-based
design handles worst.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/using-explain.html — reading `EXPLAIN` output, `type`, `rows`, `Extra`, and `EXPLAIN ANALYZE`.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/innodb-persistent-stats.html — how InnoDB persistent statistics work, `innodb_stats_auto_recalc`, and when `ANALYZE TABLE` is needed.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html — configuring and reading the slow query log, including `log_queries_not_using_indexes`.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — the standard reference on indexing strategy, sargable predicates, and optimizer statistics.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — frequent real-world case studies on stale statistics and non-sargable query patterns causing production slowdowns.
