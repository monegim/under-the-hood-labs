# Lab 17 — Solutions

## Challenge A — a replay command that looks like it ran, but recovered nothing

**Check:**
```bash
docker exec lab17-restore mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
```
Empty (or `Table 'appdb.accounts' doesn't exist` if the backup restore
itself was skipped too) — nothing from the replay made it in, even
though the command exited without an obvious crash.

**Diagnosis:** `mariadb-binlog`'s decoded replay stream opens every
session with a block of `SET @@session....` statements that reproduce
the exact session state the original writes ran under — standard,
necessary practice for accurate replay. One of those, `@@session
.check_constraint_checks`, is a MariaDB-specific session variable that
doesn't exist in MySQL 8.0 at all. When `mysql` (without `--force`)
executes a multi-statement script piped to it via stdin and hits an
error, its default behavior is to **stop immediately** — every statement
after the failing one, including all of the real `INSERT`/`UPDATE`
statements that were the entire point of the replay, never runs. The
command's own exit code is non-zero and the error text does print — but
it's one `ERROR` line sitting in the middle of several lines of
completely routine-looking `SET` output, in a tool everyone's used to
seeing print a security warning on every single invocation. It's easy to
glance at "did it print an ERROR" and miss it if you're scanning for a
crash rather than reading line by line.

**Fix (already shown in Step 5):**
```bash
mariadb-binlog ... | mysql --force -h restore -uroot -prootpass appdb
```
`--force` tells `mysql` to print each error and continue with the next
statement, rather than aborting the whole stream — appropriate here
specifically because you already know the one statement that will fail
(a harmless session-variable `SET`) and want everything else to proceed.

**Lesson:** cross-tool compatibility gaps in database tooling are common
whenever you mix vendors (MySQL server + MariaDB client tools, in this
case) — and the failure mode is rarely "obviously broken." It's "ran to
completion, printed some things, recovered nothing," which is far more
dangerous during a real recovery than an outright crash would be, because
it's the kind of result someone under pressure can mistake for success.
Always verify recovered data directly — a clean exit or a lack of a
crash is not verification.

---

## Challenge B — recovering the pre-disaster state loses a legitimate write that came after it

**Check:** compare the primary's disaster-time binlog: the `DELETE`
transaction has both a start position (`DISASTER_POS`, from Step 4) and
an end position — the `Xid`/`COMMIT` line immediately after the
`### DELETE FROM` block. Call that `DISASTER_END_POS`.

**Diagnosis:** Step 5/6's recovery replayed only up to `DISASTER_POS`,
which is correct for undoing the disaster but also throws away every
legitimate write that came after it — in this case, the row inserted
right after the `DELETE`. A single stop-at-disaster replay can only ever
recover "everything before the mistake," never "everything except the
mistake." Those aren't the same set once anything legitimate happened
afterward — which, in a real incident, is nearly always true, since the
mistake is rarely discovered in the same second it happens.

**Fix:** replay a *second* segment, starting right after the disaster's
own transaction ends, through to the end of the binlog — skipping only
the disaster's own position range, keeping everything on both sides of
it:
```bash
docker exec lab17-tools bash -c "
  mariadb-binlog --start-position=<DISASTER_END_POS> /tmp/mysql-bin.000003 | mysql --force -h restore -uroot -prootpass appdb
"
docker exec lab17-restore mysql -uroot -prootpass appdb -e "SELECT * FROM accounts ORDER BY id;"
```
This applies on top of the already-recovered state from Step 5/6, and
the previously-missing row appears without re-introducing the `DELETE`.

**Lesson:** "restore to right before the incident" and "recover
everything except the incident" are two different recovery goals with
two different procedures — a single stop-position replay only achieves
the first. When legitimate writes happened after the mistake (the
common case, not the exception), a real recovery is often two replay
passes around a gap, not one replay up to a cutoff.
