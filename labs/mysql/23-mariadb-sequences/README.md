# Lab 23 — MariaDB Sequences

## Objective
Build an invoices table backed by a `SEQUENCE` object — a real,
first-class database object MySQL has no equivalent for at all — issue
a few real invoice numbers, restart the database the way a completely
routine deploy or host reboot would, and discover that nearly a
hundred invoice numbers just vanished, permanently, without a single
error anywhere.

## Why this matters
MariaDB's `SEQUENCE` is a genuinely different mechanism from MySQL's
`AUTO_INCREMENT` — a standalone object, not a column property, that
can back one table's primary key, several tables' keys at once, cycle,
have explicit bounds, and (the part this lab is built around) cache a
block of upcoming values in memory to avoid a disk write on every
single `NEXTVAL()` call. That caching is a real, sensible performance
optimization — and it comes with a cost nothing in the `CREATE
SEQUENCE` syntax warns you about: the *entire* cached block is
reserved and persisted to disk the moment the first value from it is
requested, not consumed one at a time as each value is actually
issued. A restart at any point after that — which is any point at all,
practically speaking — throws away every cached value that hadn't
actually been handed out yet, forever. The gap isn't a bug. It's
`CACHE` doing exactly what it's documented to do, in a way most people
never think through until it costs them a hundred invoice numbers.

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
Creates `invoice_seq` (`CACHE 100`) backing an `invoices` table, issues
3 real invoice numbers, then restarts MariaDB — a completely ordinary
restart, nothing destructive — and issues one more.

## Step 2 — Reproduce the symptom
```bash
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM invoices ORDER BY id;"
```
IDs 1, 2, 3 — then 101. Not 4.

## Step 3 — Confirm what actually happened
```bash
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM invoice_seq;"
```
`next_not_cached_value` is already far ahead of what's actually been
issued — the entire 100-value cache block was reserved on disk the
moment the first `NEXTVAL()` was called, long before values 4 through
100 were ever actually handed out to anything.

## Step 4 — Fix it
```bash
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "ALTER SEQUENCE invoice_seq NOCACHE;"
```
Every value is now persisted as it's actually issued - no pre-reserved
block left to lose on the next restart. (A smaller `CACHE` size is a
middle ground: bounds the maximum possible gap instead of eliminating
it, at a small ongoing cost to write throughput.)

## Step 5 — Verify
```bash
./check.sh
```
Issues a value, restarts MariaDB for real, issues another, and
confirms they're consecutive (or nearly so) instead of separated by a
whole cache block.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a `CYCLE` sequence and a duplicate-key error out of nowhere:**
```bash
./reset.sh
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "
CREATE SEQUENCE small_seq START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 5 CYCLE;
CREATE TABLE orders (id BIGINT PRIMARY KEY DEFAULT (NEXTVAL(small_seq)), note VARCHAR(50));
INSERT INTO orders (note) VALUES ('a'),('b'),('c'),('d'),('e');
SELECT * FROM orders;
"
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "INSERT INTO orders (note) VALUES ('f');"
```
A perfectly ordinary `INSERT`, on a table that's never had a duplicate
key problem, fails with `Duplicate entry '1' for key 'PRIMARY'`. Work
out exactly what `CYCLE` promises (check `MAXVALUE`/`MINVALUE` on the
sequence), why that promise is fundamentally incompatible with a
primary key that isn't also being cleaned up as it goes, and what
`CYCLE` is actually meant for versus when reaching for it on a
still-growing, never-deleted-from table is the mistake.

**Challenge B — gaps in a table nobody ever deleted from:**
```bash
./reset.sh
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "
CREATE SEQUENCE shared_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE TABLE quotes (id BIGINT PRIMARY KEY DEFAULT (NEXTVAL(shared_seq)), note VARCHAR(50));
CREATE TABLE receipts (id BIGINT PRIMARY KEY DEFAULT (NEXTVAL(shared_seq)), note VARCHAR(50));
INSERT INTO quotes (note) VALUES ('q-a'),('q-b');
INSERT INTO receipts (note) VALUES ('r-a');
INSERT INTO quotes (note) VALUES ('q-c');
SELECT * FROM quotes ORDER BY id;
"
```
`quotes` has IDs 1, 2, 4 — a gap at 3, on a table nobody has deleted a
single row from. Check `receipts` too, and work out what `shared_seq`
being named in *two* different tables' `DEFAULT` clauses actually
means, why this is a deliberate, documented MariaDB capability and not
a coincidence, and what it implies about ever assuming a sequence
column's gaps mean "this many rows were deleted" for a shared sequence
specifically.

See `solution.md` only after you've formed your own diagnosis.
