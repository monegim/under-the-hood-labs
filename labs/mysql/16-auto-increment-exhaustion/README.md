# Lab 16 — Auto-Increment Exhaustion

## Objective
Watch an `AUTO_INCREMENT` primary key hit its column type's ceiling
while the table itself has almost no rows in it, then fix it — and learn
that "how many rows do we have" and "how close are we to running out of
IDs" are two completely different questions.

## Why this matters
`AUTO_INCREMENT` never reuses a value, even after the row that used it
is deleted. A table that's had heavy insert/delete churn — a queue
table, a staging table, a table for short-lived sessions — can be
nearly empty and still be seconds away from running out of IDs, because
the counter only ever moves forward. Once it hits the column type's
maximum, every subsequent insert fails, permanently, until someone
widens the column — and by default MySQL gives no warning as that
ceiling approaches, so the first signal is usually a production outage
during a random burst of write traffic.

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
This creates an `orders` table with `id TINYINT UNSIGNED AUTO_INCREMENT`
(max representable value: 255), then runs 24 batches of "insert 10 rows,
delete all of them" — 240 IDs consumed, 0 rows actually stored.

## Step 2 — Confirm the gap between row count and ID consumption
```bash
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SHOW CREATE TABLE orders\G"
```
The row count is 0. The `AUTO_INCREMENT=...` value in `SHOW CREATE
TABLE` is in the low 240s — nearly at the 255 ceiling. (Note:
`SHOW TABLE STATUS`'s `Auto_increment` column can show a stale/cached
value for InnoDB right after writes — `SHOW CREATE TABLE` is the
reliable, always-live source for the real current counter.)

## Step 3 — Push it over the edge
```bash
for i in $(seq 1 20); do
  docker exec lab16-primary mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('x');"
done
```
The first several succeed. Then every insert fails identically:
```
ERROR 1062 (23000) at line 1: Duplicate entry '255' for key 'orders.PRIMARY'
```
Not a special "out of IDs" error — a plain duplicate-key error, because
once the counter hits the column's maximum it stops advancing and every
new row tries the same value as the row already sitting at 255.

## Step 4 — Fix it: widen the column
```bash
docker exec lab16-primary mysql -uroot -prootpass appdb -e "
  ALTER TABLE orders MODIFY id SMALLINT UNSIGNED AUTO_INCREMENT;
"
```
`SMALLINT UNSIGNED` maxes out at 65,535 — plenty of headroom for now.

## Step 5 — Verify
```bash
./check.sh
```
Confirms a fresh insert succeeds and that real headroom exists between
the current counter and the column type's maximum (not just that the
very next insert happened to work).

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a quick fix that doubles headroom without changing the storage size:**
```bash
./reset.sh
docker exec lab16-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE orders;
  CREATE TABLE orders (id TINYINT AUTO_INCREMENT PRIMARY KEY, data VARCHAR(20));
"
for i in $(seq 1 130); do
  docker exec lab16-primary mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('x');" 2>&1 | tail -1
done
```
This table uses plain `TINYINT` (signed), not `TINYINT UNSIGNED` —
exhaustion hits at 127, not 255, roughly half as many inserts as the
main lab needed. Before reaching for `SMALLINT`/`INT`/`BIGINT`, try:
```bash
docker exec lab16-primary mysql -uroot -prootpass appdb -e "
  ALTER TABLE orders MODIFY id TINYINT UNSIGNED AUTO_INCREMENT;
"
docker exec lab16-primary mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('after-unsigned');"
```
This succeeds — same storage size (`TINYINT` is 1 byte either way), no
`ALTER` to a wider type at all. Explain exactly why converting `TINYINT`
to `TINYINT UNSIGNED` roughly doubles the usable range for an
`AUTO_INCREMENT` column specifically (not for a column storing arbitrary
signed values), and why this is a real, legitimate lever — not just a
trick — but still not a permanent fix.

**Challenge B — the counter runs out far faster than the insert count predicts:**
```bash
./reset.sh
docker exec lab16-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE orders;
  CREATE TABLE orders (id TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, data VARCHAR(20));
"
docker exec lab16-primary mysql -uroot -prootpass -e "SET GLOBAL auto_increment_increment = 10;"
for i in $(seq 1 20); do
  docker exec lab16-primary mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('x');"
done
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders; SHOW CREATE TABLE orders\G"
```
(`reset.sh` rebuilds the *original* churned table, already near its
255 ceiling from setup.sh's own churn — the `DROP`/`CREATE` above gives
this challenge a fresh counter starting near 0, so the jump is easy to
see clearly.)
20 inserts, but check how far the counter actually moved — nowhere near
20. Read up on `auto_increment_increment` and explain both what
legitimate, common setup this variable exists for, and why a table on
such an instance runs out of IDs proportionally faster than a naive
"we insert about N rows a day" calculation would predict.

See `solution.md` only after you've formed your own diagnosis.
