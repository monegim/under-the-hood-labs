# Lab 34 — Concept: Indexes Bloat Independently of Their Table

## What's actually going on

A btree index is its own tree of pages, separate from the heap (table)
pages it points into, and it follows the same MVCC rule as the heap: an
`UPDATE` to an indexed column doesn't modify the existing index entry in
place, it inserts a brand-new entry pointing at the new row version and
leaves the old entry to be cleaned up later, once nothing can see it
anymore. `VACUUM` does clean those dead entries up — it marks the space
they occupied as reusable — but "reusable" is not the same as "returned to
the OS" or "compacted." A page that's mostly dead entries after vacuuming
stays allocated to the index and stays mostly empty until either new
inserts happen to land on it again (which depends on key distribution) or
something explicitly rebuilds the index. Feed a btree index enough
updates where the new values scatter across the whole key range — random
values, as this lab uses, rather than clustering near recently-updated
keys — and you get exactly the worst case: dead entries spread across
many pages, with new entries scattered just as widely, so pages rarely get
fully emptied out and reclaimed. The heap can look completely normal
(`n_dead_tup` low after a vacuum, row count unchanged) while the index for
that same table is carrying pages that are mostly empty space.

`pgstattuple`'s `pgstatindex()` function is the direct, quantitative way
to see this: `avg_leaf_density` reports the average percentage of each
leaf page that's actually occupied by live data versus free space. A
freshly built btree is typically around 90% dense; a bloated one can be
well under 50%. `index_size` compared against what you'd expect for the
live row count (or against `pgstatindex`'s own `internal_pages`/
`leaf_pages` counts) tells the same story from a different angle. Neither
of these numbers comes from the table's own statistics — you have to ask
the index directly.

Fixing bloat means rebuilding, not vacuuming harder. A plain `REINDEX`
rewrites the index from scratch, but takes an `ACCESS EXCLUSIVE` lock on
the underlying table for the entire operation — no reads, no writes,
until it's done. `REINDEX CONCURRENTLY` (added in PG12, and extended to
whole tables with `REINDEX TABLE CONCURRENTLY` in PG14) instead builds a
brand-new index as a separate object while the old one keeps serving
queries, validates it, and only takes a brief lock at the very end to swap
the new index in and drop the old one. That safety isn't free: it needs
roughly double the disk space while both indexes coexist, it can't run
inside an explicit transaction block, its final swap phase still has to
wait for transactions that were already open when it started (Challenge
A), and — the sharpest edge — if the server is killed mid-rebuild, the
in-progress replacement index is left behind, invalid and orphaned
(`pg_index.indisvalid = false`), requiring a manual `DROP INDEX
CONCURRENTLY` before you can safely retry (Challenge B). Postgres's own
documentation calls this failure mode out explicitly, precisely because
it surprises people who assume "concurrently" implies "safe to interrupt."

## Where this shows up in the real world

Any indexed column with high update churn and low value locality — status
flags that flip back and forth, timestamps that get "touched" on every
write, UUIDs or hashes used as foreign keys — is a candidate for this
exact failure mode over time. Teams often notice only when query plans
start preferring sequential scans over an index that's technically present
but has grown so bloated that using it is no longer cheaper, and are
surprised that `VACUUM` (which they may already be running regularly)
didn't prevent it. `REINDEX CONCURRENTLY` is the standard production
answer specifically because a plain `REINDEX` on a busy table means a
real, customer-visible outage for however long the rebuild takes — but
teams that reach for it during an incident, under time pressure, are
exactly the population most likely to kill it partway through and then be
confused by the leftover invalid index the next morning.

## Go deeper

- **Book:** *The Internals of PostgreSQL* — Hironobu Suzuki — https://www.interdb.jp/pg/ — covers btree index structure and page-level internals in detail.
- **Book:** *PostgreSQL 14 Internals* — Egor Rogov — https://postgrespro.com/community/books/internals — index internals and maintenance chapters.
- **Website/docs:** PostgreSQL official docs, `pgstattuple` — https://www.postgresql.org/docs/current/pgstattuple.html — `pgstatindex()` and every column it returns, including `avg_leaf_density`.
- **Website/docs:** PostgreSQL official docs, `REINDEX` — https://www.postgresql.org/docs/current/sql-reindex.html — the CONCURRENTLY section documents the exact interrupted-rebuild failure mode used in Challenge B.
- **Website/blog:** depesz — https://www.depesz.com — deep-dive posts on index internals and bloat measurement.
- **YouTube:** CYBERTEC PostgreSQL — https://www.youtube.com/@CybertecPostgresql — operational content on index bloat and maintenance.
