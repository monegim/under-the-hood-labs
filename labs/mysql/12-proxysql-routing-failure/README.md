# Lab 12 — ProxySQL Read/Write Split Misrouting

## Objective
Stand up a MySQL primary/replica pair behind ProxySQL configured for
read/write splitting, discover that writes are failing against a
"read-only" server while reads are hammering the wrong one, and diagnose
it using ProxySQL's own admin interface (`mysql_servers`,
`stats_mysql_query_digest`) instead of guessing at query rules.

## Why this matters
ProxySQL doesn't validate that your `mysql_servers` hostgroup assignments
match reality — if you tell it the primary is in the "read" hostgroup and
the replica is in the "write" hostgroup, it will route traffic exactly
that way, forever, with no startup warning. The result is two
simultaneously wrong things happening at once: writes get sent to a
replica that's genuinely read-only and fail outright (a very visible,
loud error an application will surface immediately), while reads get sent
to the primary — which usually doesn't fail, it just quietly defeats the
entire reason a read replica was provisioned, adding load to the one
server that can least afford a routing mistake. The loud failure gets
noticed fast; the quiet one can run for a long time before anyone connects
"why is the primary under more load than expected" to a proxy config typo.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Bring up the incident
```bash
chmod +x setup.sh
./setup.sh
```
This script:
1. Starts `primary`, `replica` (GTID replication, same pattern as the
   other MySQL replication labs), and `proxysql`.
2. Creates an `appuser` MySQL account on both backends and an `orders`
   table with a couple of seed rows.
3. Configures ProxySQL for read/write splitting — but with `mysql_servers`
   hostgroup assignments **swapped**: the primary is registered under
   hostgroup 20 (intended as the read/replica hostgroup) and the replica
   under hostgroup 10 (intended as the write/primary hostgroup).

## Step 2 — Reproduce the write failure
```bash
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "
  INSERT INTO orders (data) VALUES ('via-proxysql');
"
```
This fails with something like:
```
ERROR 1290 (HY000): The MySQL server is running with the --read-only option so it cannot execute this statement
```
The application's write went through ProxySQL fine — it's MySQL itself
rejecting the statement, because the backend ProxySQL routed it to
genuinely has `read_only=ON`.

## Step 3 — Confirm replication itself is healthy (rule out the obvious wrong guess)
```bash
docker exec lab12-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"
```
Both threads `Yes`, lag near 0 — replication itself is fine. The problem
isn't "the replica is broken," it's "ProxySQL is sending the wrong traffic
to the wrong place."

## Step 4 — Diagnose at the ProxySQL admin layer
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
"
```
Read this carefully against what you know: `primary` is the actual
read-write MySQL instance, `replica` is `read_only=ON`. Compare the
`hostgroup_id` each is registered under to the hostgroup your query rules
and `mysql_users.default_hostgroup` expect for writes vs. reads:
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  SELECT username, default_hostgroup FROM mysql_users;
  SELECT rule_id, match_pattern, destination_hostgroup, apply FROM mysql_query_rules ORDER BY rule_id;
"
```
`appuser`'s `default_hostgroup` is `10` (used for anything that doesn't
match a query rule — i.e. writes). Rule 2 sends `^SELECT` traffic to
hostgroup `20`. Now line those numbers up against Step 4's
`mysql_servers` output: hostgroup `10` is the REPLICA, hostgroup `20` is
the PRIMARY. That's the entire bug — one swapped assignment in
`mysql_servers`.

```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  SELECT hostgroup, count_star, digest_text
  FROM stats_mysql_query_digest ORDER BY count_star DESC LIMIT 10;
"
```
`stats_mysql_query_digest` confirms it from the traffic side: your
`SELECT` queries show `hostgroup=20`, your `INSERT` shows `hostgroup=10` —
matching the misconfiguration, not your intent.

## Step 5 — Fix it: correct the hostgroup assignment
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  UPDATE mysql_servers SET hostgroup_id = 10 WHERE hostname = 'primary';
  UPDATE mysql_servers SET hostgroup_id = 20 WHERE hostname = 'replica';
  LOAD MYSQL SERVERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
"
```

## Step 6 — Prove it
```bash
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "
  INSERT INTO orders (data) VALUES ('after-fix');
"
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "
  SELECT @@server_id;
"
```
The `INSERT` succeeds. `SELECT @@server_id` (routed via the `^SELECT` rule
to hostgroup 20, now correctly the replica) should return the replica's
`server_id` (`2`) — confirming reads are landing on the replica, not the
primary.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a correct-looking rule that never fires because of
ordering:**
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  DELETE FROM mysql_query_rules;
  INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
    (1, 1, '^SELECT', 20, 1),
    (2, 1, '^SELECT.*FOR UPDATE', 10, 1);
  LOAD MYSQL QUERY RULES TO RUNTIME;
"
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "
  SELECT * FROM orders WHERE id = 1 FOR UPDATE;
"
```
(Run it exactly like this — a single autocommit statement, not wrapped
in its own `BEGIN`/`COMMIT`. Wrapping it in an explicit transaction
changes what you observe here — see the note at the end of this
challenge for why.)

This locking read needs to go to the primary (a `SELECT ... FOR UPDATE`
against a read-only replica will fail the same way Step 2's plain write
did). Both rules LOOK individually correct. Check
`stats_mysql_query_digest` to see which hostgroup this query actually
landed in, and figure out why — the fix isn't rewriting either rule's
`match_pattern`, it's something about how ProxySQL evaluates the two rules
relative to each other.

Once you've formed a diagnosis, try the *same* query again, but this
time wrapped in an explicit transaction:
```bash
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "
  BEGIN;
  SELECT * FROM orders WHERE id = 1 FOR UPDATE;
  COMMIT;
"
```
This one succeeds — same query, same query rules, opposite result.
Check `stats_mysql_query_digest` again and compare the hostgroup each
version actually landed in. What does ProxySQL do differently once a
statement is inside an explicit `BEGIN`, and why does that make the
rule-ordering bug from the first version disappear rather than fix it?

**Challenge B — reads correctly routed to the primary still see stale data:**

Do this AFTER Step 5/6's fix is in place (correct hostgroups, correct
query rule order). Add a query-caching rule for reads on `orders`:
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  DELETE FROM mysql_query_rules;
  INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, cache_ttl, apply) VALUES
    (1, 1, '^SELECT.*FOR UPDATE', 10, NULL, 1),
    (2, 1, '^SELECT \\* FROM orders', 20, 60000, 1),
    (3, 1, '^SELECT', 20, NULL, 1);
  LOAD MYSQL QUERY RULES TO RUNTIME;
"
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "SELECT * FROM orders WHERE id = 1;"
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "UPDATE orders SET data='updated-value' WHERE id = 1;"
docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e "SELECT * FROM orders WHERE id = 1;"
```
The `UPDATE` succeeds — it's correctly routed to the writable hostgroup,
same as Step 6 confirmed. But the `SELECT` immediately after still
returns the *old* value. Query rules were correct, hostgroup routing was
correct, replication isn't even a factor here (there's only one row and
one write). Check `stats_mysql_query_digest` for this exact query and
look closely at its `hostgroup` column — what does a value of `-1` mean,
and what does that tell you about where this response actually came
from?

See `solution.md` only after you've formed your own diagnosis.
