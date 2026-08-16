# Lab 07 — Solutions

## Challenge A — the live fix that silently does nothing

**Check:**
```bash
docker exec pglab7-primary psql -U postgres -d appdb -c "SHOW autovacuum;"
```
Still `off`, even after `ALTER SYSTEM SET autovacuum = on;` followed by
`SELECT pg_reload_conf();` both report success.

**Diagnosis:** Postgres resolves each configuration parameter from
several sources, and they don't all carry the same weight. From lowest
to highest precedence: the compiled-in default, `postgresql.conf`,
`postgresql.auto.conf` (which is exactly what `ALTER SYSTEM` writes to),
and then — above all of those — any value passed as a command-line
option to the `postgres` process itself, e.g. `-c autovacuum=off`. This
lab's `docker-compose.yml` sets `autovacuum` that way, in the
container's `command:` block, specifically so this challenge is real
rather than theoretical. `pg_reload_conf()` re-reads `postgresql.conf`
and `postgresql.auto.conf` and applies anything reloadable — but it has
no power over a value that was pinned on the command line at process
start. That value only changes if the process itself is started again
with different arguments.

**Fix:**
```bash
docker compose stop primary
AUTOVACUUM=on docker compose up -d primary
```
This lab's `docker-compose.yml` reads `autovacuum` from an `AUTOVACUUM`
environment variable (defaulting to `off`), so recreating the container
with `AUTOVACUUM=on` actually changes the command-line value instead of
trying to override it after the fact.

**Lesson:** `ALTER SYSTEM` + `pg_reload_conf()` is the right instinct for
changing a `sighup`-context setting without downtime — but only when
that setting isn't already pinned by something with higher precedence.
Before trusting a live reload, check whether the current value is coming
from a command-line flag, an environment-driven container command, or a
supervisor/orchestrator that reapplies flags on every restart — any of
which will silently outrank `ALTER SYSTEM` every time.

---

## Challenge B — a long-running transaction caps what `VACUUM FREEZE` can do

**Check:**
```bash
docker exec pglab7-primary psql -U postgres -d appdb -c "SELECT age(relfrozenxid) FROM pg_class WHERE relname='counters';"
```
The age drops after `VACUUM FREEZE`, but plateaus roughly at the age the
table had *when the background transaction began* — not at 0.

**Diagnosis:** Every transaction registers its own `xmin` — the oldest
transaction ID it might still need to treat as "not yet committed" —
for as long as it stays open. `VACUUM` (including `VACUUM FREEZE`)
computes a single cluster-wide horizon from the oldest `xmin` across
every active backend, and it can only freeze row versions that are
guaranteed visible to *everyone*, including that long-running
transaction. Rows written by `burn_xids` before the transaction began
are older than its `xmin` and freeze normally. Rows written *after* it
began are newer than that transaction's registered `xmin`, so `VACUUM
FREEZE` has to leave them alone — not because the transaction touched
`counters`, but purely because the transaction is still open and its
`xmin` is part of the horizon calculation regardless of what it queries.

**Fix:**
```bash
docker exec pglab7-primary psql -U postgres -d appdb -c "
  SELECT pid, state, now()-xact_start AS xact_age, query
  FROM pg_stat_activity WHERE state <> 'idle' AND pid <> pg_backend_pid();
"
docker exec pglab7-primary psql -U postgres -d appdb -c "SELECT pg_terminate_backend(<pid>);"
docker exec pglab7-primary psql -U postgres -d appdb -c "VACUUM FREEZE counters;"
```
Once the long-running transaction is gone, its `xmin` no longer holds
the horizon back, and a second `VACUUM FREEZE` drops the age to 0.

**Lesson:** a wraparound emergency isn't always resolved the moment you
run `VACUUM FREEZE` — if anything is holding an old transaction open
(an idle app connection, a stuck batch job, a forgotten `psql` session),
freezing can only make partial progress until that transaction ends.
Checking `pg_stat_activity` for old `xact_start` values is as much a
part of the fix as running `VACUUM FREEZE` itself.
