# Lab 18 — InnoDB Corruption Recovery

## Objective
Recover a table after one page's on-disk checksum stops matching its
content — reproduce the exact crash this causes, bring the database back
online with `innodb_force_recovery`, and finish the recovery properly
instead of leaving the instance running in a reduced-safety mode
forever.

## Why this matters
InnoDB checksums every page and validates it on every read specifically
so that corrupted data is never silently returned as if it were correct
— by design, the default response to a checksum mismatch isn't "log a
warning and carry on," it's a hard crash. That's the right call for
data integrity, but it means "the database process just died and won't
come back up" is a real, not-hypothetical incident shape, and
`innodb_force_recovery` — a startup option, set before the server can
even start, not something you run against a live instance — is the
documented way back in. Understanding what it actually does (and
doesn't) do is the difference between a contained, well-handled
incident and either panicking or, worse, assuming "we set the flag, run
some backups, ship it" without knowing whether all the data actually
came back.

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
This creates an `orders` table with enough rows to span several 16KB
InnoDB pages, then — with the container stopped, corrupting data at rest
on disk safely, matching the same pattern used in
`07-binlog-corruption` — overwrites only the 4-byte checksum field of
one page. Every actual row byte on that page is left completely intact;
only the "this page is trustworthy" seal is broken.

## Step 2 — Reproduce the crash
```bash
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"
docker ps -a --filter name=lab18-primary
```
The query never returns — `mysqld` crashes immediately when it reads
the corrupted page. The container shows `Exited`, not `Up`. This is
InnoDB's checksum-mismatch fail-fast behavior working exactly as
designed, not a bug.

## Step 3 — Diagnose
```bash
docker logs lab18-primary 2>&1 | grep -i corrupt
```
```
[ERROR] [InnoDB] Database page corruption on disk or a failed file read of page [page id: space=2, page number=6]. You may have to recover from a backup.
```
The log names a numeric tablespace (`space=2`), not a table name — with
one table in this lab it's obvious which one, but in a real instance
with many tables it isn't. Resolve it once the instance is back up:
```bash
docker exec lab18-primary mysql -uroot -prootpass -e "
  SELECT SPACE, NAME FROM information_schema.INNODB_TABLESPACES WHERE SPACE = 2;
"
```

## Step 4 — Fix it: start with innodb_force_recovery
```bash
docker compose stop primary
FORCE_RECOVERY=1 docker compose up -d primary
```
`innodb_force_recovery=1` (`SRV_FORCE_IGNORE_CORRUPT`) tells InnoDB to
tolerate a checksum mismatch it finds rather than crash — the lowest,
safest level, and specifically the one meant for exactly this: getting
enough access to inspect and dump data.

## Step 5 — Verify
```bash
./check.sh
```
Confirms the container is up and all 125 rows are readable — because
this corruption never touched actual row bytes, only the checksum,
nothing was actually lost.

## Step 6 — Finish the recovery properly
Running indefinitely with `innodb_force_recovery` set is not a
long-term fix — it deliberately blocks ordinary writes:
```bash
docker exec lab18-primary mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('test');"
```
```
ERROR 1881 (HY000): Operation not allowed when innodb_force_recovery > 0.
```
Dump the now-accessible data, drop the corrupted table (DDL like `DROP
TABLE` *is* still allowed), copy the dump out to the host (the
container gets recreated in the next step — anything only inside it is
lost), restart cleanly, then copy the dump back in and restore:
```bash
docker exec lab18-primary sh -c "mysqldump -uroot -prootpass appdb orders > /tmp/salvage.sql"
docker exec lab18-primary mysql -uroot -prootpass appdb -e "DROP TABLE orders;"
docker cp lab18-primary:/tmp/salvage.sql /tmp/lab18-salvage.sql

docker compose stop primary
docker compose up -d primary

docker cp /tmp/lab18-salvage.sql lab18-primary:/tmp/salvage.sql
docker exec lab18-primary sh -c "mysql -uroot -prootpass appdb < /tmp/salvage.sql"
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"
```
The instance is now running with completely normal startup options
again, on a freshly-created, uncorrupted tablespace.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the highest recovery level doesn't crash, but don't trust it either:**
```bash
./reset.sh
docker compose stop primary
dd if=/dev/urandom of=./data/mysql/appdb/orders.ibd bs=1 seek=98400 count=8 conv=notrunc status=none
FORCE_RECOVERY=1 docker compose up -d primary
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"
```
(This corrupts 8 bytes *past* the page's 38-byte header — actual row
content this time, not just the checksum.) Even `innodb_force_recovery=1`
crashes on this one — genuine row-content corruption isn't something
that level tolerates, unlike Step 4's checksum-only case.

Now try the maximum level:
```bash
docker rm -f lab18-primary
FORCE_RECOVERY=6 docker compose up -d primary
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT id FROM orders ORDER BY id;" | wc -l
```
No crash this time — `SELECT COUNT(*)` returns a number and looks
completely successful. But compare it against actually counting the
rows the second query returns (and look at the raw `id` values in that
output list closely, not just the count). They don't agree with each
other, and at least one `id` value doesn't look like anything your
`AUTO_INCREMENT` column could have legitimately produced. What does
`innodb_force_recovery=6` actually skip that levels 1-4 don't, and why
is "the query didn't error" not remotely the same thing as "the query
returned everything, and only the real data"? What made this the
single most dangerous result you've gotten out of this table all lab,
worse than every crash so far?

**Challenge B — you can read the data, but you can't get it out the "normal" way yet:**
```bash
./reset.sh
docker compose stop primary
FORCE_RECOVERY=1 docker compose up -d primary
docker exec lab18-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE orders_copy AS SELECT * FROM orders;
"
```
This fails with the same `ERROR 1881` from Step 6, even though you're
just trying to copy data you can already successfully `SELECT`. Explain
precisely what `innodb_force_recovery > 0` blocks and what it doesn't
(you already saw `DROP TABLE` succeed in Step 6) — is the dividing line
"DDL vs. DML," "reads vs. writes," or something more specific than
either of those — and work out the actual sequence of operations
(spanning more than one server restart) that gets `orders`' data into a
brand new table without ever running an `INSERT`/`CREATE TABLE ... AS
SELECT` while `innodb_force_recovery` is still set.

See `solution.md` only after you've formed your own diagnosis.
