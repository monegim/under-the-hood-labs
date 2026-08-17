# Lab 12 — Solutions

## Challenge A — a correct-looking rule that never fires because of ordering

**Check:**
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
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
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
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

**Why the `BEGIN`/`COMMIT`-wrapped version succeeds anyway:** run the
exact same (still-broken, pre-fix) query rules again, but wrap the
locking read in an explicit transaction — it succeeds, landing on
hostgroup 10 despite the rules being identically wrong. ProxySQL's query
rules route the *first* statement of a session/transaction, but once a
session is inside an explicit multi-statement transaction (opened with
`BEGIN`), every subsequent statement in that same transaction is pinned
to whichever backend connection the transaction is already using —
ProxySQL will not silently move a `COMMIT`-pending transaction to a
different physical server mid-flight, since that would break atomicity
outright (a partial transaction can't span two separate MySQL backends).
Here, `BEGIN` itself gets routed to hostgroup 10 (ProxySQL's routing for
transaction-control statements without a specific matching rule falls
back to `default_hostgroup`, which is 10 for `appuser`), and the `FOR
UPDATE` read that follows just rides along on that same pinned
connection — the broken rule 1/rule 2 ordering never even gets a chance
to misroute it, because query-rule evaluation for routing purposes only
really matters at the point a new backend connection would otherwise be
chosen.

**The trap this creates:** an engineer debugging exactly this incident
by testing with `BEGIN ... COMMIT` (a very natural instinct — "let me
wrap it safely") will see it work and conclude the rules are fine, while
the exact same query run by the real application under autocommit fails
in production. Reproducing a routing incident has to match how the real
traffic is actually shaped — transactional or not — not just the query
text.

---

## Challenge B — reads correctly routed to the primary still see stale data

**Check:**
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  SELECT hostgroup, digest_text, count_star FROM stats_mysql_query_digest
  WHERE digest_text LIKE '%orders WHERE id%' ORDER BY last_seen DESC LIMIT 5;
"
```
The repeated `SELECT * FROM orders WHERE id = ?` shows an entry with
`hostgroup = -1`. Every other query in this lab has shown a real
hostgroup (10 or 20) — `-1` is different in kind, not just value.

**Diagnosis:** `-1` is ProxySQL's marker for "this response came from
the query cache, not from any backend at all." Rule 2 in this
challenge's setup carries `cache_ttl=60000` — for 60 seconds after the
*first* time a matching `SELECT` runs, ProxySQL serves every identical
subsequent request straight out of its own in-memory cache, without
forwarding it to MySQL again. `mysql_servers`, hostgroup routing, and
replication all did their job correctly here — the write went to the
primary, and if you'd disabled caching the very next read would have
gone to the (correct) read hostgroup and returned the fresh value. The
staleness has nothing to do with *where* the read was routed; it never
reached a database at all.

**Fix:** either drop the cache TTL for this rule (routing decisions and
caching decisions can be set independently, so removing `cache_ttl`
doesn't undo the Step 5/6 fix), or invalidate the cache after writes that
matter:
```bash
docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -e "
  UPDATE mysql_query_rules SET cache_ttl=NULL WHERE rule_id=2;
  LOAD MYSQL QUERY RULES TO RUNTIME;
  SAVE MYSQL QUERY RULES TO DISK;
"
```

**Lesson:** a proxy sitting between the app and the database can affect
correctness in ways that have nothing to do with which backend a query
was sent to. Before assuming "stale read" means replication lag or a
routing bug, check whether anything in the path — a query cache, an
application-level cache, a CDN in front of an API — might be answering
requests without touching the database at all. `stats_mysql_query_digest`
showing hostgroup `-1` is ProxySQL's own explicit way of telling you
exactly that, if you know to look for it.
