# Lab 11 — Concept: Partition Pruning Is a Provability Problem

## What's actually going on

Partitioning splits one logical table into several physically separate
storage structures, each holding a defined subset of rows (in this lab,
one partition per year, via `RANGE (YEAR(created_at))`). The performance
benefit people actually want from this — **pruning** — is the optimizer
proving, at query-plan time, that some partitions cannot possibly contain
any row matching the query's `WHERE` clause, and skipping them entirely
before execution even starts. This is fundamentally a provability
exercise: MySQL has to look at your predicate and the partitioning
expression together and mathematically determine which partitions are
excluded. It can only do that for a limited, specific set of predicate
shapes — a direct comparison on the partitioning column, or the column
wrapped in one of a small set of functions MySQL's pruning logic
explicitly understands (`YEAR()`, `TO_DAYS()`, `TO_SECONDS()`, and a
handful of others, applied directly to the column with nothing else
composed around it). The moment your predicate falls outside that
recognized shape — an extra arithmetic operation, a different function, an
`OR` with an unrelated column, a join that doesn't touch the partitioning
column at all — the optimizer can't prove exclusion anymore, and "can't
prove excluded" defaults to "must be included." Every partition gets
scanned, silently, with correct results and no error, just more I/O than
necessary.

This lab demonstrates three genuinely different ways to lose pruning,
because they require different fixes. Wrapping the column in an
expression the optimizer doesn't recognize (`created_at + INTERVAL 0 DAY`)
is a pure query-authoring mistake — the information needed for pruning
exists, it's just expressed in a form MySQL can't parse for this purpose,
and rewriting the predicate to a recognized shape fixes it completely
(Steps 3-5). A join or filter that never references the partitioning
column at all (Challenge A) is a different category: there's no bug to
fix in the query, because the information genuinely isn't there — pruning
correctly falls back to a full scan given what was asked, and any fix has
to add real information (an explicit date filter derived from what the
application actually knows) rather than rephrase the existing query.
`OR` conditions (Challenge B) are the subtlest: pruning has to be provably
correct for the ENTIRE predicate as a whole, not clause-by-clause, so one
unconstrained `OR` branch defeats pruning for branches that would
otherwise have pruned perfectly fine on their own — splitting into a
`UNION` lets each half be planned (and pruned) independently again.

## Where this shows up in the real world

Partitioning is frequently adopted specifically to keep a large,
time-series-shaped table's queries fast as it grows — exactly the
`events`/`orders`/`logs`-style table in this lab. The regression this lab
demonstrates is insidious because it doesn't show up on day one: a query
written against a small, freshly-partitioned table is fast regardless of
whether pruning is actually working, because even a full scan of a small
table is cheap. The cost only becomes visible months later as data
accumulates in the partitions that never needed to be touched — by which
point the query has usually been copy-pasted into several other places, an
ORM has generated a similar shape automatically, or nobody remembers this
table is partitioned at all. `EXPLAIN`'s `partitions` column is the single
cheapest thing to check whenever a query against a partitioned table is
slower than its `WHERE` clause would suggest it should be.

## Go deeper

- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — covers partitioning strategy and pruning behavior in depth.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — the general discipline of verifying an optimization is actually happening, not just configured.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/partitioning-pruning.html — canonical reference for exactly which predicate shapes support pruning and which don't.
- **Website/docs:** MySQL official docs, `EXPLAIN` output format — https://dev.mysql.com/doc/refman/8.0/en/explain-output.html — documents the `partitions` column now always present in `EXPLAIN` output.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — practical partitioning and pruning troubleshooting posts.
