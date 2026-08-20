# Lab 22 — MariaDB System-Versioned Tables

## Objective
Build a table with `WITH SYSTEM VERSIONING` — a MariaDB feature with
no equivalent in MySQL — run months of completely ordinary application
traffic against it, and discover that the table has been quietly
keeping a full row for every single `UPDATE`/`DELETE` it's ever
processed, forever, invisible to every query the application actually
runs.

## Why this matters
`WITH SYSTEM VERSIONING` (MariaDB 10.3+) turns any table into a
built-in temporal table: every `UPDATE` and `DELETE` doesn't overwrite
or remove data, it closes out the current row version and opens a new
one, all transparently, with zero application code changes required.
This is a genuinely powerful, MariaDB-only capability — real
point-in-time recovery and full audit history without a hand-rolled
shadow table or trigger. It's also a capability with an opt-out
retention policy that's easy to never notice needs setting: by
default, nothing ever purges old versions. A table that looks small
and normal in every query the application sends can be carrying years
of full row history on disk, discovered only when someone finally
looks at `information_schema` or the table's actual storage footprint.

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
Creates a system-versioned `accounts` table and simulates ~400
ordinary balance updates against 3 rows — nothing unusual, no bulk
job, just routine traffic over time.

## Step 2 — Reproduce the symptom
```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts;"
```
3 rows. Completely normal-looking.

## Step 3 — Find what's actually on disk
```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts FOR SYSTEM_TIME ALL;"
```
Over 400 rows — every historical version of every row this table has
ever had, none of them visible to the query in Step 2, all of them
still physically stored.

## Step 4 — Fix it
```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "DELETE HISTORY FROM accounts BEFORE SYSTEM_TIME NOW();"
```
`DELETE HISTORY` is a dedicated statement specifically for purging
old versions — it only ever touches historical rows, never the
current one.

## Step 5 — Verify
```bash
./check.sh
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the history isn't just overhead, it's the actual feature:**
```bash
./reset.sh
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT NOW(6);"
```
Note the timestamp, then immediately:
```bash
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "UPDATE accounts SET balance = 99999 WHERE owner='alice';"
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "
SELECT * FROM accounts FOR SYSTEM_TIME AS OF TIMESTAMP'<paste the timestamp you noted>' WHERE owner='alice';
"
```
Alice's balance, exactly as it was *before* that last update — no
audit table, no application logging, no trigger anyone wrote. Work out
why this changes the calculus on Step 4's fix: purging history isn't
free of tradeoffs the way purging an ordinary log table is, and what
you'd actually want to know about a table before deciding how
aggressively to purge it.

**Challenge B — deleting a row doesn't delete the row:**
```bash
./reset.sh
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "DELETE FROM accounts WHERE owner='bob';"
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts;"
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM accounts FOR SYSTEM_TIME ALL WHERE owner='bob';"
```
Bob is gone from the normal count - and still sitting right there in
history. Work out what this means for anyone assuming `DELETE FROM
accounts WHERE owner='bob'` is enough to actually remove bob's data
from this table (compliance/GDPR-style "right to erasure" requests are
exactly the scenario where this distinction stops being academic), and
what the actual, complete removal sequence has to include.

See `solution.md` only after you've formed your own diagnosis.
