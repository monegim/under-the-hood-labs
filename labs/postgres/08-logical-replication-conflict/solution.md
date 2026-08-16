# Lab 08 — Solutions

## Challenge A — the fast fix that quietly loses data

**Check:**
```bash
docker exec pglab8-publisher psql -U postgres -d appdb -c "SELECT * FROM orders ORDER BY id;"
docker exec pglab8-subscriber psql -U postgres -d appdb -c "SELECT * FROM orders ORDER BY id;"
```
Replication resumes and `id=4` shows up on the subscriber — but `id=3`
on the subscriber still shows the *original local* value
(`subscriber-local-item`), not the publisher's `publisher-item`. The two
sides have permanently diverged on that row, with no error anywhere to
tell you.

**Diagnosis:** `ALTER SUBSCRIPTION ... SKIP (lsn = ...)` doesn't skip
"the conflicting row" — it skips the *entire transaction* that ends at
that LSN. In this lab that transaction only contained the one `INSERT`,
so the effect looks narrow, but in production a single logical
transaction is very often many statements across many rows (a batch
job, an ORM flushing a unit of work, anything wrapped in `BEGIN`...
`COMMIT`). `SKIP` discards all of it unconditionally — every row that
transaction touched, not just the one that happened to collide — and
does so silently: no error, no log line calling out what was dropped,
just a `SELECT` away from ever noticing.

**Fix:** prefer resolving the actual conflict (delete or reconcile the
row that's in the way, as in the main lab's Step 4) over `SKIP` whenever
you can identify what's colliding and it's safe to do so. Reach for
`SKIP` only when you've confirmed you're willing to lose everything in
that specific transaction — for example, if you can regenerate it from
source, or you've independently verified via other means that it's safe
to discard.

**Lesson:** the fast fix and the correct fix are not the same command
here, and the fast one fails silently rather than loudly — which is the
worst combination for something that causes data loss. Always check
what a "resume replication" action actually resolves down to before
running it under time pressure.

---

## Challenge B — restarting doesn't fix this

**Check:**
```bash
docker logs pglab8-subscriber 2>&1 | grep "duplicate key" | tail -3
```
Identical `duplicate key value violates unique constraint "orders_pkey"`
immediately after the restart — the fresh apply worker fails on its
very first attempt.

**Diagnosis:** the apply worker's progress isn't tracked in the
subscriber process's memory — it's tracked by a *replication slot* on
the **publisher** (created automatically by `CREATE SUBSCRIPTION`, named
after the subscription) plus a *replication origin* on the subscriber
that records exactly how far that subscription has successfully
applied. Both of those live in on-disk state, independent of whether
any particular subscriber process or container is currently running.
Restarting the subscriber container starts a brand new apply worker,
but that worker immediately asks the publisher "resume from where I
left off" using that persisted position — which is still sitting right
before the same failing transaction. Nothing about a process restart
touches the data conflict that's actually causing the failure.

**Fix:** the same as the main lab — resolve what's actually blocking
progress (the conflicting row, or a deliberate `SKIP` per Challenge A's
tradeoffs). Restarts, redeploys, or failovers of either side don't
route around a replication conflict; they just reproduce it faster.

**Lesson:** logical replication state is durable and server-side by
design (so a subscriber can crash and resume without re-syncing from
scratch) — but that same durability means infrastructure-level fixes
("just restart it") have no effect on data-level problems. If a retrying
background worker fails identically after a restart, look for state it's
resuming from, not the process itself.
