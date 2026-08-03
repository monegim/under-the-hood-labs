# Lab 34 — Solutions

## Challenge A — waiting on a long-running transaction, not "never blocks"

**Check:**
```bash
docker exec lab34-primary psql -U postgres -c \
  "SELECT pid, state, wait_event_type, wait_event, query FROM pg_stat_activity WHERE datname = 'appdb';"
```
One session shows `state = active`, deep in `pg_sleep(60)`, inside an open
transaction. The `REINDEX INDEX CONCURRENTLY` session shows up too,
sitting with a wait event, not erroring out or completing.

**Diagnosis:** `REINDEX CONCURRENTLY` really does avoid holding a single
long `ACCESS EXCLUSIVE` lock for the whole rebuild — that's the entire
point of it — but it still has multiple short phases, and at certain
phase transitions (building the new index, then validating it, then
swapping it in for the old one) it needs to wait for transactions that
were already running when it started to finish, so it can be sure no one
is still relying on the old index definition mid-swap. A transaction that
opened before the reindex started and is still open (even just idling in
`pg_sleep`) is exactly the kind of thing it has to wait out. "Concurrently"
means "doesn't block NEW queries with a long exclusive lock," not "never
waits on anything."

**Fix:** end the long-running transaction:
```bash
docker exec lab34-primary psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query ILIKE '%pg_sleep%';"
```
The reindex proceeds and finishes.

**Lesson:** before running `REINDEX CONCURRENTLY` in production, check
`pg_stat_activity` for old, long-running transactions against the same
table first — it won't fail because of them, but it can queue behind them
indefinitely, which looks a lot like a hang if you don't know to check.

---

## Challenge B — an interrupted `REINDEX CONCURRENTLY` leaves an invalid index behind

**Check:**
```bash
docker exec lab34-primary psql -U postgres -d appdb -c "\d widgets"
docker exec lab34-primary psql -U postgres -d appdb -c "
  SELECT c.relname, i.indisvalid, i.indisready
  FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
  WHERE c.relname LIKE 'idx_widgets_sku%';
"
```
There are now two index entries: the original `idx_widgets_sku`
(`indisvalid = t`, unaffected) and a leftover, invalid one — typically
named with a `_ccnew` suffix — with `indisvalid = f`. It's not usable by
the planner and doesn't get cleaned up automatically.

**Diagnosis:** `REINDEX CONCURRENTLY` builds the replacement index as a
separate, temporarily-named object while the original stays live and
usable, and only swaps/drops at the very end. If the server is killed
(a crash, or here, a forced `docker restart -t 0`) before that final swap,
the in-progress replacement is left behind, invalid and orphaned — this
exact failure mode is called out explicitly in Postgres's own
documentation for `REINDEX CONCURRENTLY`. It costs disk space and clutters
`\d`, but it does NOT affect correctness: the original index is untouched
and still valid the whole time, which is why lookups kept working.

**Fix:** drop the invalid leftover, then retry:
```bash
docker exec lab34-primary psql -U postgres -d appdb -c \
  "DROP INDEX CONCURRENTLY idx_widgets_sku_ccnew;"
docker exec lab34-primary psql -U postgres -d appdb -c \
  "REINDEX INDEX CONCURRENTLY idx_widgets_sku;"
```
(substitute whatever the actual leftover index is named —
`SELECT relname FROM pg_class WHERE relname LIKE 'idx_widgets_sku_cc%';`
if unsure.)

**Lesson:** `REINDEX CONCURRENTLY`'s safety comes at the cost of a real
failure mode: an interrupted run doesn't roll back cleanly, it leaves an
invalid index that a human (or an automated check) has to notice and drop
before retrying. Never assume a `REINDEX CONCURRENTLY` that got
interrupted "probably just needs to be re-run" — check `pg_index.indisvalid`
first.
