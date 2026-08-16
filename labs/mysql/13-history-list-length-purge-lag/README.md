# Lab 13 — History List Length / Purge Lag

## Objective
Watch InnoDB's `purge` — the background process that continuously
cleans up old row versions — get held back by a single long-running
transaction, growing the undo `History List Length` unbounded, then
learn to find and kill the actual blocker instead of guessing.

## Why this matters
InnoDB is MVCC: every `UPDATE`/`DELETE` doesn't overwrite a row in
place, it writes a new version and keeps the old one in an undo log,
because some other transaction might still need to see the "before"
state under its own snapshot. A background `purge` thread continuously
walks these old versions and reclaims the ones nothing can possibly need
anymore. This works fine under normal load — until a single
long-running transaction (an abandoned `psql`-style session, a
report query someone forgot about, a stuck batch job) keeps an old
snapshot pinned open. Purge can't safely remove anything newer than the
oldest snapshot still in use, so it simply stops making progress on
that boundary — not just for that transaction's own tables, for
*everything* — while writes elsewhere keep piling up undo data behind
it. This is one of the most common real reasons a MySQL instance's data
directory quietly grows for no obvious reason, and it's almost always
diagnosed by looking in the wrong place first.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This brings up MySQL, creates a `churn` table with a single hot row,
starts a transaction that opens a snapshot and then just sits there
(bounded at 300s, self-terminating), and — while that transaction stays
open — updates the same row 5,000 times.

## Step 2 — Confirm the incident
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | grep "History list length"
```
5,000 — one for every update that happened while the snapshot was
pinned open. Under normal conditions, purge would have kept this near
zero the whole time.

## Step 3 — Find what's actually holding it back
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "
  SELECT trx_id, trx_started, trx_mysql_thread_id, trx_query
  FROM information_schema.innodb_trx
  ORDER BY trx_started;
"
```
One row: the transaction from `setup.sh`, still open, still holding its
snapshot from before any of the 5,000 updates happened.

## Step 4 — Fix it
```bash
docker exec lab13-primary mysql -uroot -prootpass -e "KILL <trx_mysql_thread_id>;"
```
(substitute the ID from Step 3).

## Step 5 — Verify
```bash
./check.sh
```
Purge runs on a background thread, not instantly — this can take up to
about a minute to fully catch up on a backlog this size, which is why
`check.sh` polls rather than checking once.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the blocker never touched the table that's growing:**
```bash
./reset.sh
# kill setup.sh's own blocking transaction first, so only the one below is active
docker exec lab13-primary mysql -uroot -prootpass -e "
  SELECT trx_mysql_thread_id FROM information_schema.innodb_trx;
"
docker exec lab13-primary mysql -uroot -prootpass -e "KILL <that_thread_id>;"
docker exec lab13-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS unrelated;
  CREATE TABLE unrelated (id INT PRIMARY KEY);
  INSERT INTO unrelated VALUES (1);
"
docker exec -d lab13-primary mysql -uroot -prootpass appdb -e "
  BEGIN;
  SELECT * FROM unrelated;
  DO SLEEP(300);
  COMMIT;
"
sleep 2
docker exec lab13-primary mysql -uroot -prootpass appdb -e "CALL churn_rows(3000);"
docker exec lab13-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | grep "History list length"
```
The blocking transaction only ever queried `unrelated` — it never once
touched `churn` — and History List Length still climbs by exactly the
same mechanism. Explain, in terms of what a transaction's snapshot
actually is, why *which tables it queries* is completely irrelevant to
whether it blocks purge.

**Challenge B — killing the obvious suspect does nothing at all:**
```bash
./reset.sh
# kill setup.sh's own blocking transaction first
docker exec lab13-primary mysql -uroot -prootpass -e "SELECT trx_mysql_thread_id FROM information_schema.innodb_trx;"
docker exec lab13-primary mysql -uroot -prootpass -e "KILL <that_thread_id>;"
# a trivial-looking transaction, started FIRST (older)
docker exec lab13-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS trivial;
  CREATE TABLE trivial (id INT PRIMARY KEY);
  INSERT INTO trivial VALUES (1);
"
docker exec -d lab13-primary mysql -uroot -prootpass appdb -e "
  BEGIN; SELECT * FROM trivial; DO SLEEP(200); COMMIT;
"
sleep 2
# the "obvious" transaction, started SECOND (newer) — this is the one that touches churn
docker exec -d lab13-primary mysql -uroot -prootpass appdb -e "
  BEGIN; SELECT * FROM churn; DO SLEEP(200); COMMIT;
"
sleep 2
docker exec lab13-primary mysql -uroot -prootpass appdb -e "CALL churn_rows(2000);"
docker exec lab13-primary mysql -uroot -prootpass -e "
  SELECT trx_id, trx_started, trx_mysql_thread_id FROM information_schema.innodb_trx ORDER BY trx_started;
"
```
Two open transactions now exist. Kill only the one that actually touched
`churn` — the "obvious" one — and watch History List Length for a full
minute or more. Then check `information_schema.innodb_trx` again; the
other transaction (the trivial-looking one, querying a table with a
single row) is still sitting there. What does `trx_started` on each row
tell you about which one you actually needed to kill first, and why did
killing the "obviously related" transaction change nothing at all?

See `solution.md` only after you've formed your own diagnosis.
