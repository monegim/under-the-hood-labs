# Lab 13 — Solutions

## Challenge A — the blocker never touched the table that's growing

**Check:**
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "
  SELECT trx_id, trx_started, trx_query FROM information_schema.innodb_trx;
"
```
The open transaction's `trx_query` (or its history, via `SELECT * FROM
unrelated`) shows it only ever touched `unrelated` — nothing about
`churn` at all.

**Diagnosis:** a transaction's snapshot isn't a per-table concept — it's
a single point in the database's overall transaction-ID timeline,
established the moment the transaction takes its first consistent read
(under `REPEATABLE READ`, MySQL's default). From that point on, the
transaction is *entitled* to see the database exactly as it looked at
that moment, for *any* table it might query later, even ones it hasn't
touched yet and even ones that didn't exist yet. Purge has no way to
know in advance which tables a still-open transaction might query next,
so it has to preserve every old row version across the *entire*
database that's newer than the oldest open snapshot — not just for
tables that transaction happens to have already read.

**Fix:** same as the main lab — find the transaction via
`information_schema.innodb_trx` (its query history is irrelevant to
whether it's a purge blocker) and end it:
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "KILL <trx_mysql_thread_id>;"
```

**Lesson:** never use "what has this session actually queried" as a
filter when hunting for a purge blocker — check every row in
`information_schema.innodb_trx`, full stop, regardless of how unrelated
or idle it looks.

---

## Challenge B — killing the obvious suspect does nothing at all

**Check:**
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "
  SELECT trx_id, trx_started FROM information_schema.innodb_trx;
"
docker exec lab13-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | grep "History list length"
```
After killing the transaction that touched `churn`, `innodb_trx` still
shows one row — the `trivial` transaction — and History List Length
hasn't moved even slightly, no matter how long you wait (verified live
for 90+ seconds with no change).

**Diagnosis:** purge is bounded by exactly one thing: the single
*oldest* read view currently open anywhere in the system — not "any"
open transaction, not "the one that looks related." The `trivial`
transaction was started first, so its snapshot predates the `churn`
transaction's snapshot, which in turn predates all 2,000 updates from
`churn_rows`. Killing the *newer* `churn`-touching transaction removes a
read view that was never the actual bottleneck — the older `trivial`
transaction was always the one holding purge back, and it doesn't matter
in the slightest that it never touched the table you were worried about.
This is why the fix has to be ordered correctly: find the row in
`information_schema.innodb_trx` with the *oldest* `trx_started`, not the
one whose query looks most relevant to the incident.

**Fix:**
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "
  SELECT trx_id, trx_started, trx_mysql_thread_id FROM information_schema.innodb_trx ORDER BY trx_started;
"
docker exec lab13-primary mysql -uroot -prootpass -e "KILL <oldest_trx_mysql_thread_id>;"
```
Once the genuinely oldest transaction is gone, purge can advance again —
confirmed via `./check.sh` or by polling History List Length directly.

**Lesson:** when more than one transaction is open, "kill the one that
touched the table" is a reasonable-sounding instinct that is completely
disconnected from how purge actually works. Sort
`information_schema.innodb_trx` by `trx_started` and go after the oldest
row first — every other transaction, however suspicious it looks, has
zero effect on purge until that one is gone.
