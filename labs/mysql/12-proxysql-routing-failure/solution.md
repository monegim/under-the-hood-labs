# Lab 12 — Solutions

## Challenge A — a correct-looking rule that never fires because of ordering

**Check:**
```bash
docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "
  SELECT hostgroup, count_star, digest_text
  FROM stats_mysql_query_digest ORDER BY count_star DESC LIMIT 5;
"
```
The `SELECT * FROM orders WHERE id = 1 FOR UPDATE` shows up with
`hostgroup=20` — the read hostgroup, which in this challenge's setup is
the replica. A `FOR UPDATE` locking read against a read-only server fails
exactly like a plain write would.

**Diagnosis:** ProxySQL evaluates `mysql_query_rules` in ascending
`rule_id` order and, by default (`apply=1` with no explicit chaining),
stops at the **first** rule whose `match_pattern` matches the query. Rule
1 is `'^SELECT'` — and `SELECT ... FOR UPDATE` matches that just fine,
since it starts with `SELECT`. ProxySQL never even evaluates rule 2's
more specific `'^SELECT.*FOR UPDATE'` pattern, because rule 1 already
claimed the query. Both patterns are individually correct regular
expressions for what they're trying to match — the bug isn't in either
pattern, it's in putting the broad one *before* the narrow one.

**Fix:**
```bash
docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "
  DELETE FROM mysql_query_rules;
  INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
    (1, 1, '^SELECT.*FOR UPDATE', 10, 1),
    (2, 1, '^SELECT', 20, 1);
  LOAD MYSQL QUERY RULES TO RUNTIME;
  SAVE MYSQL QUERY RULES TO DISK;
"
```
Specific pattern first, general pattern second — exactly the order the
original (non-challenge) setup used in Step 5.

**Lesson:** query rule *order* is part of the routing logic, not just the
patterns themselves. A rule engine that stops at first match will always
let an earlier broad rule shadow a later narrow one — always order
special cases before their general fallback, and don't assume "the rule
is written correctly" is the same as "the rule is reachable."

---

## Challenge B — a fix that silently un-fixes itself

**Check:**
```bash
docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "
  SELECT * FROM mysql_replication_hostgroups;
  SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
"
```
`mysql_servers` shows the primary back in hostgroup 20 and the replica
back in hostgroup 10 — Step 5's manual fix has been reverted, and nobody
ran `UPDATE mysql_servers` again.

**Diagnosis:** `mysql_replication_hostgroups` turns on ProxySQL's
built-in replication monitor: it periodically checks each backend's
`read_only` value and *automatically* reassigns that server into either
`writer_hostgroup` (if `read_only=0`) or `reader_hostgroup` (if
`read_only=1`) — overwriting whatever is currently in `mysql_servers` on
every monitoring cycle, with no confirmation and no diff shown. The
values used here, `writer_hostgroup=20, reader_hostgroup=10`, are the
*original swapped numbers* from the incident, not the corrected ones from
Step 5. The primary is writable (`read_only=0`), so the monitor puts it
in hostgroup 20 — reintroducing the exact original misconfiguration,
automatically, on a timer, forever, until `mysql_replication_hostgroups`
itself is corrected or removed.

This is the trap: `mysql_replication_hostgroups` is presented as a
"just enable auto-failover-aware routing" feature, but it's still just
another place to encode the same two numbers — and once it's active, it
takes priority over any manual edit to `mysql_servers`, because it
re-applies itself continuously rather than once.

**Fix:** either delete the row (turn the monitor off) or, if you want the
automatic-reassignment behavior for real failover handling, put the
*correct* numbers in it:
```bash
docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "
  DELETE FROM mysql_replication_hostgroups;
  -- or, to keep auto-reassignment with the right mapping:
  -- INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup, check_type) VALUES (10, 20, 'read_only');
  UPDATE mysql_servers SET hostgroup_id = 10 WHERE hostname = 'primary';
  UPDATE mysql_servers SET hostgroup_id = 20 WHERE hostname = 'replica';
  LOAD MYSQL SERVERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
"
```

**Lesson:** a config table that actively re-asserts itself on a timer can
make a manual fix look successful right up until the next monitoring
cycle. When something you fixed comes back on its own, look for a
background process re-applying config, not for someone/something undoing
your change by hand — `mysql_replication_hostgroups`, health checks,
reconcile loops, and config-management agents all share this shape.
