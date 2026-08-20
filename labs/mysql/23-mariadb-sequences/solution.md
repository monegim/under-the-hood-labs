# Lab 23 — Solution

## Root cause

`invoice_seq` was created with `CACHE 100`, which pre-reserves and
persists a whole block of 100 upcoming values to disk the moment the
first `NEXTVAL()` from that block is called — not incrementally, as
each value is actually issued. Only 3 values (1, 2, 3) were ever
actually handed out to a real invoice before the restart. The other 97
existed only in MariaDB's in-memory notion of "these are already
reserved, don't hand them out again" - a restart discards that
in-memory state, and the persisted `next_not_cached_value` (already
101, written to disk on the very first call) is where the sequence
resumes. Values 4 through 100 are not delayed, not recoverable, and
were never actually assigned to anything - they're simply gone.

## Why it happened

`CACHE` is documented, sensible, and enabled by a reasonable-looking
default (100) specifically to avoid a disk write on every single
`NEXTVAL()` call under real write throughput. Nothing about the syntax
or the default value signals "this entire block becomes unrecoverable
the moment anything restarts" - that's an implementation detail of how
the caching is persisted, not something visible from `CREATE SEQUENCE`
alone. It's exactly the kind of setting that looks like a pure
performance knob until a completely unrelated event (a restart) turns
it into data loss.

## Why the obvious fixes don't work

- **`ALTER SEQUENCE invoice_seq RESTART WITH 4`**: manually "fixes" the
  next value once, but does nothing about `CACHE 100` still being
  active - the next restart burns another block just the same.
- **Checking for a MariaDB bug/reporting it**: this is fully
  documented, intended behavior, not a defect - `CACHE` explicitly
  trades gap-free guarantees for reduced disk I/O, and MariaDB never
  promises otherwise.
- **Switching to `AUTO_INCREMENT`**: side-steps this specific mechanism
  but gives up genuine sequence features (sharing one counter across
  tables, explicit `CYCLE`/bounds) that may be the actual reason
  `SEQUENCE` was chosen - worth doing only if none of those features
  are actually needed.

## The investigation

```bash
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM invoices ORDER BY id;"
```
1, 2, 3, then 101.

```bash
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM invoice_seq;"
```
`next_not_cached_value` far ahead of anything actually issued, and
`cache_size` showing exactly how big the at-risk block was.

## The fix

```bash
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "ALTER SEQUENCE invoice_seq NOCACHE;"
```
Confirmed by `./check.sh`: a value issued, a real restart, and the
next value issued land consecutively.

---

## Challenge A — a `CYCLE` sequence and a duplicate-key error out of nowhere

**Check:** `INSERT INTO orders (note) VALUES ('f');` fails with
`Duplicate entry '1' for key 'PRIMARY'` on a table that's never
deleted a row.

**Diagnosis:** `small_seq` was created with `MAXVALUE 5 CYCLE` -
`CYCLE` means exactly what it says: once the sequence exhausts its
range, the *next* call wraps back around to `MINVALUE` and starts
reissuing values from there, by design. Nothing about `CYCLE` checks
whether a previously-issued value is still in use anywhere - it has no
visibility into the table's actual contents at all, only into its own
counter. `orders` still has rows with `id` 1 through 5; the wrapped
sequence hands out `1` again, and the primary key constraint - doing
exactly its job - rejects it.

**Fix:** `CYCLE` is appropriate for values that are inherently
short-lived or explicitly rotated out before the sequence wraps back
around to them (a bounded pool of session tokens, a fixed set of
slot numbers actively being recycled) - not for a primary key on a
table that keeps every row. For `orders`, either drop `CYCLE`
entirely (let the sequence exhaust and fail loudly, which is far
better than silently colliding) or size `MAXVALUE` so large that
wrapping is a non-event over any realistic table lifetime.

**Lesson:** `CYCLE` is a promise about the *sequence's* behavior, not
a promise that wrapping is safe for whatever the sequence happens to
be feeding - that safety depends entirely on whether the old values
are still around, which the sequence itself has no way to know.

---

## Challenge B — gaps in a table nobody ever deleted from

**Check:** `quotes` shows IDs 1, 2, 4 — never 3.

**Diagnosis:** `shared_seq` is named in the `DEFAULT` clause of *both*
`quotes` and `receipts` - a single counter, deliberately shared across
two tables, which is a real and documented MariaDB capability (useful
when two tables need IDs guaranteed never to collide with each
other's, without a compound key). `receipts`' one `INSERT` consumed
value 3 from the exact same counter `quotes` was drawing from -
`quotes` was never going to see it.

**Fix:** nothing is broken here - this is the sequence working exactly
as configured. The actual fix is diagnostic: before assuming a gap in
a sequence-backed column means deleted rows, check whether that
sequence is named anywhere else in the schema (`SELECT
table_name, column_name FROM information_schema.columns WHERE
column_default LIKE '%NEXTVAL%';` finds every table drawing from any
sequence) - a gap from a shared sequence and a gap from real deletions
look identical from inside the one table you're looking at.

**Lesson:** a sequence-backed ID column's gaps only mean "rows were
deleted" if that sequence is guaranteed to be exclusive to this one
table - which, on MariaDB, is a deliberate choice someone made, not a
default you can assume.
