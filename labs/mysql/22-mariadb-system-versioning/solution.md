# Lab 22 — Solution

## Root cause

`accounts` was created `WITH SYSTEM VERSIONING`, which makes every
`UPDATE`/`DELETE` a non-destructive operation at the storage level:
the current row version gets its "valid until" timestamp closed out,
and a fresh row version is inserted for the new state (or, for a
`DELETE`, just closed out with nothing replacing it). Ordinary queries
only ever see the currently-valid version of each row, so the
application, its dashboards, and anyone running a normal `SELECT`
never see anything unusual. Nothing purges the closed-out versions by
default — they simply accumulate, one per write, forever.

## Why it happened

System versioning is opt-in at table-creation time and enabled with a
single clause — there's no accompanying prompt for a retention policy,
and the feature works completely correctly with none configured; it
just keeps every version indefinitely. A table can run in production
for a long time looking completely ordinary in every way the
application interacts with it, because the application never needed
to know versioning was even enabled to keep working.

## Why the obvious fixes don't work

- **`OPTIMIZE TABLE`**: reclaims fragmented space but doesn't remove
  any actual rows - the historical versions are real, live rows as far
  as InnoDB/Aria is concerned, not deleted-but-unreclaimed space.
- **Dropping and recreating the table**: destroys the history
  entirely, including whatever legitimate audit/recovery value it was
  providing - usually not what anyone actually wants, and not
  necessary; `DELETE HISTORY` exists precisely so you don't have to
  choose between "keep everything forever" and "keep nothing."
- **Regular `DELETE FROM accounts WHERE ...`**: doesn't touch history
  at all - it only closes out current rows, which themselves become
  more history. This is the exact same mechanism causing the problem
  in the first place (Challenge B), not a fix for it.

## The investigation

```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts;"
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts FOR SYSTEM_TIME ALL;"
```
3 visible rows against 400+ actual rows on disk - the entire incident
in two numbers.

## The fix

```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "DELETE HISTORY FROM accounts BEFORE SYSTEM_TIME NOW();"
```
A dedicated statement that only ever removes historical (closed-out)
row versions - the current version of every row is untouched. For an
ongoing policy rather than a one-time cleanup, this same statement
with a relative cutoff (e.g. `BEFORE SYSTEM_TIME NOW() - INTERVAL 90 DAY`)
run on a schedule keeps a bounded retention window instead of
unbounded growth.

## Challenge A — the history isn't just overhead, it's the actual feature

**Check:**
```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "
SELECT * FROM accounts FOR SYSTEM_TIME AS OF TIMESTAMP'<checkpoint>' WHERE owner='alice';
"
```
Alice's exact balance at that exact moment, recovered with a plain
`SELECT` - no audit table, no application-level logging.

**Diagnosis:** `FOR SYSTEM_TIME AS OF` reconstructs the table's state
at any past instant directly from the same version history that Step
4's fix purges. This is the actual purpose of the feature, not a side
effect - built-in point-in-time recovery and full change history for
any table, for free, without a single line of trigger or audit-log
code. Purging that history isn't a neutral cleanup operation the way
truncating a log table is; it's a real, deliberate tradeoff between
storage cost and how far back you can ever look again.

**Fix/lesson:** before purging aggressively, know what the table's
history is actually used for (or might need to be used for -
compliance, dispute resolution, debugging a "the balance was wrong
last Tuesday" ticket) and size the retention window to that need,
rather than defaulting to "purge everything, keep only current" out of
reflex once the growth problem is noticed.

## Challenge B — deleting a row doesn't delete the row

**Check:**
```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM accounts FOR SYSTEM_TIME ALL WHERE owner='bob';"
```
Bob's row, still there, after a `DELETE` that made him disappear from
every normal query.

**Diagnosis:** on a system-versioned table, `DELETE` is exactly as
non-destructive as `UPDATE` - it closes out the current version
(setting its "valid until" to now) without inserting a replacement,
which is what makes the row vanish from ordinary `SELECT`s. The actual
row data is untouched, sitting in history exactly like every prior
`UPDATE`'s superseded version. For most use cases this is desirable
(an accidental delete is trivially recoverable via `FOR SYSTEM_TIME AS
OF`) - but it means a `DELETE` alone is not a data-removal guarantee.

**Fix:** removing a row's data completely requires purging its
history too - `DELETE HISTORY FROM accounts BEFORE SYSTEM_TIME NOW()`
(or a version scoped to that specific row's history) after the
`DELETE`, not instead of it. Anywhere this table's `DELETE` is being
relied on for actual erasure (compliance requests being the sharpest
example), that has to be a documented two-step process, not an
assumption.

**Lesson:** on a system-versioned table, "removed from the table" and
"the data no longer exists anywhere in the table" are different
claims, and only one of them is true after a plain `DELETE`.
