# Lab 18 — Solutions

## Challenge A — the highest recovery level doesn't crash, but don't trust it either

**Check:**
```bash
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT id FROM orders ORDER BY id;" | wc -l
```
At `innodb_force_recovery=1`, this row-content corruption (not just a
checksum) still crashes `mysqld` — level 1 only tolerates a checksum
mismatch on a page whose actual bytes are otherwise intact, which isn't
the case here. At `innodb_force_recovery=6`, the query returns a
number instead of crashing — but the count from `SELECT COUNT(*)` and
the number of rows `SELECT id FROM orders` actually lists disagree with
each other, and looking at the listed `id` values directly, at least one
of them is a huge, nonsensical number nothing your `AUTO_INCREMENT`
column would ever generate.

**Diagnosis:** `innodb_force_recovery=6` is `SRV_FORCE_NO_LOG_REDO`, the
highest level, and it includes every lower level's behavior — including
level 1's "ignore corrupt pages and try to skip past them during a
scan" and level 4's disabling of certain background consistency checks.
At this level, when InnoDB's row-parsing code encounters genuinely
garbled bytes where a row should be, it doesn't reliably detect that
the bytes are garbage — it can interpret them *as if* they were a valid
row, however nonsensical the result. Different query paths
(`COUNT(*)`'s internal counting mechanism vs. an actual row-by-row
`SELECT id`) can walk the corrupted structure differently and arrive at
different, individually-wrong answers, neither of which is flagged as
suspect by the server in any way — no warning, no error, just a
result set that looks exactly as valid as a correct one.

**Fix:** there isn't one, for this specific page's data — this
corruption genuinely destroyed those rows, and no `innodb_force_recovery`
level recovers destroyed bytes; it only controls how tolerant InnoDB is
of trying to read past them. The only real "fix" is treating any
`innodb_force_recovery=6` result as unverified until cross-checked
against an independent source of truth — a real, known-good backup, an
application-level row count from before the incident, or (at minimum)
two different query shapes over the same data agreeing with each other.

**Lesson:** a crash is honest — it tells you something is wrong, loudly,
the moment it happens. `innodb_force_recovery=6`'s silent wrong answer
is the opposite: it looks exactly like success. Escalating to the
highest recovery level to "just get something back" trades a loud,
obvious failure for a quiet, easy-to-miss one — treat any data pulled
out at that level as provisional and unverified, never as confirmed
recovered, until you've checked it another way.

---

## Challenge B — you can read the data, but you can't get it out the "normal" way yet

**Check:**
```bash
docker exec lab18-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE orders_copy AS SELECT * FROM orders;
"
```
```
ERROR 1881 (HY000): Operation not allowed when innodb_force_recovery > 0.
```
Same error as Step 6's plain `INSERT` — even though the `SELECT` half of
this statement works completely fine on its own.

**Diagnosis:** `innodb_force_recovery > 0` doesn't distinguish "DDL vs.
DML," and it doesn't block *all* DDL either — Step 6 already showed
`DROP TABLE` succeeding. The actual line is narrower: it blocks anything
that would make InnoDB *write new data* — inserting rows, whether via a
plain `INSERT` or the implicit inserts inside `CREATE TABLE ... AS
SELECT`. `DROP TABLE` only removes a catalog entry and unlinks a file;
it writes nothing new into the storage engine's own data structures the
same way an insert does. This is a deliberate, narrow safety boundary:
force_recovery mode exists to let you *read out* of a possibly-damaged
instance without making that instance's on-disk state any more
complicated while you're doing it — reads and metadata removal are
allowed, anything that adds new committed data is not.

**Fix:** the sequence has to cross a server restart, because writing
requires being *out* of force_recovery mode entirely — the exact Step 6
flow: dump the readable data out (`mysqldump`, itself just reads), copy
that dump somewhere that survives a container being recreated, stop the
instance, start it again with `innodb_force_recovery` unset (normal
startup, now safe since the corrupted table is already gone if you
dropped it, or you're about to load into a different, fresh table),
*then* run the actual insert-shaped restore. There's no single-command
way to do this while the write restriction is active — that restriction
existing at all is the entire point.

**Lesson:** `innodb_force_recovery`'s write restriction isn't a bug to
route around, and there's no flag to bypass it (that would defeat what
it's protecting against) — the two-phase "read out under recovery, then
write back in under normal operation" shape is the actual intended
workflow, not a workaround for a limitation.
