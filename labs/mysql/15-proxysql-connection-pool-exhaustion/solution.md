# Lab 15 — Solutions

## Challenge A — a per-user ceiling, not a per-backend one

**Check:**
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
```
ERROR 1226 (42000): User 'appuser' has exceeded the 'max_user_connections' resource (current value: 2)
```

**Diagnosis:** this is a genuinely third, independent ceiling —
`mysql_users.max_connections` caps how many simultaneous connections
ProxySQL will accept *from a specific username*, checked at the moment a
client connects to ProxySQL itself, before ProxySQL ever tries to hand
that client a backend connection. Compare that against the main lab's
symptom: Step 2's `SELECT 1` connected fine and then sat waiting several
seconds — the client was accepted, it just had to queue for a backend.
This error is immediate and explicit, and it names the exact resource
(`max_user_connections`) and its exact configured value in the message
itself — there's no ambiguity or queuing involved at all.

**Fix:**
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  UPDATE mysql_users SET max_connections=10000 WHERE username='appuser';
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL USERS TO DISK;
"
```

**Lesson:** an error that names a specific resource and value doesn't
need guessing — but it's still easy to misattribute to "the connection
pool" generically if you don't know ProxySQL enforces per-user,
per-backend, and global ceilings as three separate, independently
configured things.

---

## Challenge B — ProxySQL's own front door has a ceiling too

**Check:**
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
```
ERROR 1040 (08004): Too many connections
```
A third distinct error, different from both Step 2 (silent queuing, no
error at all) and Challenge A (`1226`, names `max_user_connections`
specifically). `1040`/`Too many connections` doesn't name a user or a
backend — because `mysql-max_connections` isn't scoped to either. It's
the absolute ceiling on how many client connections ProxySQL itself will
ever accept, full stop, regardless of which user or which backend
they're headed for.

**Diagnosis of the `stats_mysql_global` question:**
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SELECT * FROM stats_mysql_global WHERE Variable_Name LIKE 'Client_Connections%';
"
```
`Client_Connections_aborted` increments for *both* Challenge A's
per-user rejection and this challenge's global rejection (verified: both
scenarios bump the same counter) — it tracks every connection ProxySQL's
front end refused outright, regardless of which specific ceiling caused
the refusal. It does **not** reflect the main lab's per-backend pool
exhaustion at all — that's not a rejection, it's a successfully-accepted
client waiting in an internal queue, visible only via
`stats_mysql_connection_pool`'s `ConnUsed`/`ConnFree`, a completely
separate table.

**Fix:**
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SET mysql-max_connections=2048;
  LOAD MYSQL VARIABLES TO RUNTIME;
  SAVE MYSQL VARIABLES TO DISK;
"
```

**Lesson — checking order for a real incident:** given three
independent ceilings, check in this order, because each one's absence
rules out an entire category:
1. Does the client connection to ProxySQL itself succeed at all? If it's
   rejected outright (`1040` or `1226`), check `Client_Connections_aborted`
   to confirm it's a front-end rejection, then distinguish `1040` (global
   `mysql-max_connections`) from `1226` (per-user `mysql_users
   .max_connections`) by the error text itself.
2. If the client connection succeeds but queries hang, the client was
   accepted and is waiting for a backend — check `stats_mysql_connection_pool`
   (`ConnUsed`/`ConnFree`) for the relevant hostgroup, not
   `stats_mysql_global` at all.
