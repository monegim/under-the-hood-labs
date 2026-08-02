# Lab 3 — Solutions

## Challenge A — gap/index-record locks from concurrent INSERTs

**Check:**
```bash
mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | sed -n '/LATEST DETECTED DEADLOCK/,/^---TRANSACTION/p'
```
The deadlock (or, depending on timing, a lock-wait-timeout instead — see
below) shows both sessions holding an **exclusive lock on a gap/index
record** for the `UNIQUE KEY` on `email`, each waiting on the other's
insert intention lock for the OTHER row.

**Diagnosis:** `INSERT` isn't lock-free just because the row doesn't exist
yet. Under InnoDB's default `REPEATABLE READ` isolation, inserting into a
table with a `UNIQUE` index takes a lock on the gap/index position where
the new value would go, so that a concurrent transaction can't insert a
duplicate before this one commits (this is what actually enforces
uniqueness under concurrent inserts, not just the final duplicate-key
check). Session A inserts `alice@example.com` and holds a lock covering
that index position, then tries to insert `bob@example.com`; Session B has
done the mirror image — inserted `bob@example.com` and is now waiting for
the lock covering `alice@example.com`'s position, which Session A holds.
Same circular-wait shape as the main lab's `UPDATE`s, just on index-record
locks taken implicitly by `INSERT` rather than explicit row locks taken by
`UPDATE`.

**Fix:** identical in kind to the main lab — the application must retry on
1213 (or on a lock wait timeout, 1205, if InnoDB's detector doesn't happen
to catch this particular ordering as a full cycle before one side times
out). The schema-level fix that actually prevents this class of deadlock
going forward: have all code paths that insert into multi-row unique-keyed
batches sort by the unique key first, so every transaction acquires those
index locks in the same order.

**Lesson:** deadlocks aren't an `UPDATE`-only phenomenon. Any statement
that takes more than one lock — including plain `INSERT` against a
`UNIQUE` index — can deadlock against another transaction taking the same
locks in a different order.

---

## Challenge B — a three-way deadlock cycle

**Check:**
```bash
cat /tmp/lab03-3way-a.log /tmp/lab03-3way-b.log /tmp/lab03-3way-c.log
mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | sed -n '/LATEST DETECTED DEADLOCK/,/^---TRANSACTION/p'
```
Exactly one of the three logs shows `ERROR 1213`; the other two eventually
show `Query OK` (they just had to wait longer than usual). The `LATEST
DETECTED DEADLOCK` section shows two `*** (1) TRANSACTION` / `*** (2)
TRANSACTION` blocks — but tracing the actual row IDs each one is
holding/waiting on reveals the full cycle also involves the third session:
transaction 1 holds `id=1`, waiting for `id=2`; transaction 2 holds `id=2`,
waiting for `id=3` — and if you cross-reference thread/connection IDs with
`SHOW PROCESSLIST` at the moment of the deadlock, the session holding
`id=3` (waiting for `id=1`) closes the loop.

**Diagnosis:** `SHOW ENGINE INNODB STATUS`'s deadlock section always
prints exactly two transaction blocks — the two InnoDB is directly
comparing when it decides which to roll back — even when the actual
wait-for graph is a longer cycle. InnoDB's deadlock detector walks the
full wait-for graph looking for any cycle, but the killed victim is
chosen from wherever it closes the loop, not necessarily "transaction 1
vs transaction 3." In a 1→2→3→1 cycle, rolling back **any single**
transaction in the cycle is sufficient to break it — the moment session 3
(say) is rolled back, it releases the lock session 2 was waiting on, so
session 2 proceeds and commits, releasing the lock session 1 was waiting
on, so session 1 proceeds too. One victim, whole cycle unblocked.

**Fix:** same retry-on-1213 discipline as the other two scenarios — but
this scenario is a good reminder that reading `SHOW ENGINE INNODB STATUS`
literally (assuming only two sessions are ever involved because only two
are printed) can miss the real scope of a deadlock in production. Cross-
reference with `SHOW PROCESSLIST` (or `performance_schema.data_lock_waits`
in 8.0, which shows the full wait-for edges, not just two transactions at
a time) whenever more than two write paths touch the same rows.

**Lesson:** don't assume a deadlock is always exactly two transactions
just because that's what the classic textbook example (and this lab's
main scenario) shows. `performance_schema.data_lock_waits` is the tool
built specifically to show the complete graph, not just the pair InnoDB
happened to name when it picked a victim.
