# Lab 15 — ProxySQL Connection Pool Exhaustion

## Objective
Watch new clients queue behind ProxySQL's own per-backend connection
pool — a completely separate, smaller limit than MySQL's own
`max_connections` — and learn that ProxySQL actually enforces *three*
independent connection ceilings, each failing in a different, specific
way.

## Why this matters
`12-proxysql-routing-failure` covers ProxySQL sending queries to the
wrong place; this lab is about a healthy, correctly-routed topology that
still can't serve traffic, because the pooler in front of the database
is the actual bottleneck — not the database itself. The instinct when an
app can't get a database connection is to look at the database
(`max_connections`, `SHOW PROCESSLIST`) — but a connection pooler like
ProxySQL sits in front of that limit specifically to multiplex many more
client connections onto far fewer backend ones, which means it has its
own capacity ceilings that have nothing to do with what MySQL itself is
configured to allow.

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
This brings up MySQL behind ProxySQL with the backend's connection pool
(`mysql_servers.max_connections`) set to 5, then launches 8 clients
through ProxySQL that each open a transaction and hold it for 30
seconds — 3 more than the pool has backend connections for.

## Step 2 — Reproduce the symptom
```bash
time docker exec lab15-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
This takes several seconds to complete — a plain `SELECT 1`, on a
database that's otherwise doing almost nothing.

## Step 3 — Check the wrong layer first (on purpose)
```bash
docker exec lab15-primary mysql -uroot -prootpass -e "
  SELECT COUNT(*) AS active_connections, @@max_connections FROM information_schema.processlist;
"
```
A handful of connections, nowhere close to `max_connections`. MySQL
itself looks completely healthy.

## Step 4 — Check the layer that's actually constrained
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SELECT hostgroup, srv_host, status, ConnUsed, ConnFree FROM stats_mysql_connection_pool;
"
```
`ConnUsed` is pinned at 5 (the configured `max_connections`), `ConnFree`
is 0. This is ProxySQL's own admin interface (port 6032, not the client
port 6033) — a separate MySQL-protocol connection you query with normal
SQL against ProxySQL's internal tables.

## Step 5 — Fix it
```bash
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  UPDATE mysql_servers SET max_connections=20 WHERE hostgroup_id=10;
  LOAD MYSQL SERVERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
"
```
`LOAD ... TO RUNTIME` applies the change immediately; `SAVE ... TO DISK`
persists it so it survives a ProxySQL restart. Both are needed.

## Step 6 — Verify
```bash
./check.sh
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a per-user ceiling, not a per-backend one:**
```bash
./reset.sh
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  UPDATE mysql_users SET max_connections=2 WHERE username='appuser';
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL USERS TO DISK;
"
for i in 1 2 3; do
  docker exec -d lab15-proxysql sh -c "mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e 'SELECT SLEEP(15);' > /tmp/u-\$i.log 2>&1"
done
sleep 3
docker exec lab15-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
This fails *immediately*, with an explicit error — not the silent
queuing from Step 2. `mysql_users` has its own `max_connections` column,
completely independent from the `mysql_servers.max_connections` from the
main lab. Read the exact error text and explain what it's actually
telling you: is this the same ceiling as before hit from a different
angle, or a genuinely third, separate limit — and how would you tell,
from the error alone, which of the two you'd just hit?

**Challenge B — ProxySQL's own front door has a ceiling too:**
```bash
./reset.sh
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SET mysql-max_connections=3;
  LOAD MYSQL VARIABLES TO RUNTIME;
  SAVE MYSQL VARIABLES TO DISK;
"
for i in 1 2 3 4 5; do
  docker exec -d lab15-proxysql sh -c "mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e 'SELECT SLEEP(15);' > /tmp/f-\$i.log 2>&1"
done
sleep 3
docker exec lab15-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SELECT * FROM stats_mysql_global WHERE Variable_Name LIKE 'Client_Connections%';
"
```
A third distinct failure — check the error text again, and compare it
against Challenge A's. `mysql-max_connections` is a global ProxySQL
variable (`SET`, not an `UPDATE` on a table), unrelated to any specific
user or backend. Given three independent ceilings now exist
(`mysql_servers.max_connections`, `mysql_users.max_connections`, and
`mysql-max_connections`), what's the actual order you'd check them in
during a real incident, and which one does `Client_Connections_aborted`
in `stats_mysql_global` actually tell you about — all three, or just
one?

See `solution.md` only after you've formed your own diagnosis.
