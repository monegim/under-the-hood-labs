# Lab 8 — Connection Storm Exhausts max_connections

## Objective
Reproduce a broken application/connection-pool pattern that opens far
more MySQL connections than it should and never gives them back, exhausts
`max_connections`, and locks out legitimate new connections. Learn `SHOW
PROCESSLIST`/`Threads_connected` to identify the offending source, the
emergency fix (bump `max_connections`, kill idle connections), and the
real fix (connection pooling and `wait_timeout` at the app/proxy layer).

## Why this matters
"App can't connect to the database" pages are often not a database
problem at all — they're an application problem that happens to surface
as a database error. A connection pool with a bug (never returning
connections, reconnecting instead of reusing, a leak under a specific
error path) can exhaust `max_connections` in seconds during a deploy or a
traffic spike, and every other legitimate client — including, in the
worst case, your own monitoring or on-call tooling — starts getting
rejected with `ERROR 1040 (HY000): Too many connections`. Knowing MySQL
reserves one extra connection for privileged (`SUPER`/`CONNECTION_ADMIN`)
accounts specifically so an admin can still get in during exactly this
situation is the difference between being locked out of your own
incident and being able to fix it.

## Prerequisites
- Ubuntu VM, sudo access
- `mysql-server` (installed by `setup.sh`)

Check first:
```bash
uname -a
which mysql
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This script:
1. Sets `max_connections=50` (deliberately low, so this reproduces in
   seconds instead of needing hundreds of real processes) and leaves
   `wait_timeout` at its long 8-hour default.
2. Creates a low-privilege `appuser` (no `SUPER`/`CONNECTION_ADMIN` —
   unlike `root`, it has no reserved extra connection).
3. Opens 70 separate connections as `appuser`, each one just sleeping
   (bounded at 180s) instead of a pool reusing a small fixed set —
   simulating a connection pool that opens a new connection per request
   and never gives any of them back.
4. Attempts one more `appuser` connection to show it failing.

## Step 2 — Confirm the exhaustion
```bash
mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'max_connections';"
```
> Gotcha: `mysql -uroot ...` still works here even though connections are
> exhausted — root has `SUPER`, and MySQL reserves one extra connection
> slot specifically for accounts with `SUPER`/`CONNECTION_ADMIN`, on top
> of `max_connections`. A regular app account has no such reservation.

```bash
mysql -uappuser -pappuserpass appdb -e "SELECT 1;"
```
This fails with `ERROR 1040 (HY000): Too many connections.`

## Step 3 — Identify the offending source
```bash
mysql -uroot -prootpass -e "
  SELECT user, command, COUNT(*) AS n, LEFT(GROUP_CONCAT(DISTINCT host), 60) AS hosts
  FROM information_schema.processlist
  GROUP BY user, command
  ORDER BY n DESC;
"
```
One user (`appuser`), one command state (`Sleep`), dominating the entire
connection count — the classic signature of a pool that isn't reusing or
releasing connections, not a genuine surge of distinct real users.

## Step 4 — Emergency fix: relieve the immediate pressure
Two options, often used together during a live incident:
```bash
mysql -uroot -prootpass -e "SET GLOBAL max_connections=200;"
```
```bash
mysql -uroot -prootpass -N -e "
  SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist
  WHERE user='appuser' AND command='Sleep';
" | mysql -uroot -prootpass
```
> Gotcha: bumping `max_connections` alone doesn't fix anything if the pool
> is still misbehaving — it just moves the ceiling further away, buying
> time. Killing the idle sleepers is what actually relieves pressure
> right now.

## Step 5 — Confirm recovery
```bash
mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -uappuser -pappuserpass appdb -e "SELECT 1;"
```

## Step 6 — The real fix: bound the pool and tune wait_timeout
The database-side mitigation is not the fix — the pool itself needs a
hard maximum size well under `max_connections`, and connections need to
actually be released back to the pool after use. As a server-side safety
net (not a substitute for fixing the pool), a much shorter `wait_timeout`
means MySQL itself reaps genuinely idle connections instead of leaving
them to accumulate forever at their 8-hour default:
```bash
mysql -uroot -prootpass -e "SET GLOBAL wait_timeout=120;"
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the storm is coming from one specific host, not spread out:**
```bash
mysql -uroot -prootpass -e "
  SELECT host, COUNT(*) FROM information_schema.processlist GROUP BY host ORDER BY 2 DESC LIMIT 5;
"
```
Run this during Step 2's incident, before fixing anything. What does the
`host` column actually show for all those `appuser` connections in this
lab (all running on the same VM), and how would you adapt this exact
query in production to catch one misbehaving app server flooding
connections from among many legitimate ones?

**Challenge B — max_connections is fine, but table_open_cache/file
descriptors aren't:**
```bash
sudo tee /etc/mysql/mysql.conf.d/zzz-lab08-challengeb.cnf > /dev/null <<'EOF'
[mysqld]
max_connections=500
open_files_limit=200
EOF
sudo systemctl restart mysql
for i in $(seq 1 100); do
  nohup mysql -uappuser -pappuserpass appdb -e "DO SLEEP(30);" > /dev/null 2>&1 &
done
sleep 3
mysql -uappuser -pappuserpass appdb -e "SELECT 1;"
sudo systemctl stop mysql 2>/dev/null; sudo rm -f /etc/mysql/mysql.conf.d/zzz-lab08-challengeb.cnf; sudo systemctl start mysql
```
`max_connections` here is generously high (500), yet you can still hit
connection failures well before 500 real connections exist. Check
`sudo journalctl -u mysql --no-pager | tail -30` and `SHOW VARIABLES LIKE
'open_files_limit';`. What's actually the limiting resource this time, and
why does raising `max_connections` alone not help if this one isn't
raised too?

See `solution.md` only after you've formed your own diagnosis.
