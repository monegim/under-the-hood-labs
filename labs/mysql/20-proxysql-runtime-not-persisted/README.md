# Lab 20 — ProxySQL RUNTIME Config Not Persisted to Disk

## Objective
Configure ProxySQL routing the way it actually happens under pressure —
`LOAD ... TO RUNTIME` to fix something right now — then watch it
silently vanish the next time ProxySQL restarts, because the one
command that makes a change survive a restart was never run.

## Why this matters
ProxySQL's configuration lives in three distinct places at once, and
it's entirely possible for them to disagree: the working tables you
edit directly (`mysql_users`, `mysql_servers`, ...), the active
in-memory `RUNTIME` config that's actually routing traffic right now,
and the on-disk config ProxySQL reloads from every time it starts.
`LOAD ... TO RUNTIME` moves a change from the working tables into
`RUNTIME` — traffic starts using it immediately. `SAVE ... TO DISK` is
a separate, easy-to-forget step that copies the working tables to the
on-disk config so a future restart doesn't lose them. Nothing checks
whether you did the second step, and nothing about a fix "working" — a
query succeeding right after you make the change — tells you whether
it will still be there tomorrow. That gap is exactly the shape of a
real incident: a fix goes in under pressure, everyone moves on, and
weeks later a routine restart (an upgrade, a host reboot, an
orchestrator rescheduling the container) reverts it with no warning
and no obvious connection to whatever triggered the restart.

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
This configures ProxySQL to route `appuser` to the backend, loads it
`TO RUNTIME` (so it's live and working), and deliberately never runs
`SAVE ... TO DISK`. It then restarts the ProxySQL container itself —
standing in for any routine restart in the real world — to make the
consequence land immediately instead of at some unpredictable future
point.

## Step 2 — Reproduce the failure
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
```
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'appuser'@'127.0.0.1' (using password: YES)
```
The `ProxySQL Error:` prefix and the `127.0.0.1` host mean this is a
client-facing rejection — ProxySQL itself doesn't recognize `appuser`
at all anymore, not "the password is wrong." Confirm it directly:
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT * FROM mysql_users;"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT * FROM mysql_servers;"
```
Both come back completely empty. ProxySQL didn't just lose the
`RUNTIME` copy of this config on restart — the working tables you
originally edited come back empty too, because those get reloaded from
the same on-disk source at every startup. The only place this
configuration still exists is your own memory of having typed it.

## Step 3 — Diagnose (and how you'd have caught this before it broke)
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT username FROM mysql_users;"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT username FROM disk.mysql_users;"
```
Both empty — which is itself the diagnosis. `disk` is a real, separate
database exposed on ProxySQL's admin interface (`SHOW DATABASES;`
lists it alongside `main`, `stats`, and `monitor`), backed directly by
the SQLite file ProxySQL actually reads on startup. If `disk.mysql_users`
had `appuser` in it and the working table didn't, that would point at
something else entirely (a bad edit made *after* a good save). Both
sides agreeing that nothing is there confirms this was never persisted
anywhere durable in the first place — restarting didn't corrupt or
lose a saved config, there simply never was one to lose.

That same comparison is far more useful run *before* a restart, right
after making a change: query the working `mysql_users` table against
`disk.mysql_users` the moment you finish `LOAD ... TO RUNTIME`. If they
don't match yet, your change is one restart away from disappearing,
whether or not anything looks broken right now — that's the window
where this is still a two-second fix instead of an incident.

## Step 4 — Fix it
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'primary', 3306);

  DELETE FROM mysql_users;
  INSERT INTO mysql_users (username, password, default_hostgroup, active) VALUES ('appuser', 'apppass', 10, 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
  SAVE MYSQL USERS TO DISK;
"
```
Same configuration as before, plus the two `SAVE ... TO DISK`
statements this incident was missing.

## Step 5 — Verify
```bash
./check.sh
```
Confirms a query through ProxySQL succeeds. For real confidence this
actually survives a restart (not just that it currently works):
```bash
docker compose restart proxysql
./check.sh
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — "I saved it" can be half true:**
```bash
./reset.sh
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'primary', 3306);

  DELETE FROM mysql_users;
  INSERT INTO mysql_users (username, password, default_hostgroup, active) VALUES ('appuser', 'apppass', 10, 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
docker compose restart proxysql
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT * FROM mysql_servers;"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT * FROM mysql_users;"
```
One `SAVE` statement is missing — just for users, not servers. After
the restart, one of these two tables comes back exactly as configured
and the other comes back completely empty. Work out which, and why
"I ran SAVE TO DISK" doesn't mean what it sounds like it means: there
is no single command that persists everything at once, and doing it
for one part of your configuration says nothing about any other part.

**Challenge B — the "reload config" command that goes the wrong way:**
```bash
./reset.sh
# (Step 4's fix, run in full — SAVE included for both servers and users)
docker exec lab20-primary mysql -uroot -prootpass -e "
  CREATE USER 'urgentuser'@'%' IDENTIFIED WITH mysql_native_password BY 'urgentpass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'urgentuser'@'%';
"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  INSERT INTO mysql_users (username, password, default_hostgroup, active) VALUES ('urgentuser', 'urgentpass', 10, 1);
  LOAD MYSQL USERS TO RUNTIME;
"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uurgentuser -purgentpass appdb -e "SELECT 1;"
```
`urgentuser` works — a second, urgent routing change, live in
`RUNTIME`, not yet saved. Now someone on the team, thinking they're
doing something safe and routine ("let me just reload the config to
make sure everything's in sync"), runs this:
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  LOAD MYSQL USERS FROM DISK;
  LOAD MYSQL USERS TO RUNTIME;
"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uurgentuser -purgentpass appdb -e "SELECT 1;"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
`urgentuser` is gone. `appuser` is fine. Figure out exactly what
`LOAD ... FROM DISK` does, which direction it moves data relative to
`LOAD ... TO RUNTIME` and `SAVE ... TO DISK`, and why it looked
completely harmless — arguably even responsible — to run, right up
until it silently deleted someone's not-yet-saved work.

See `solution.md` only after you've formed your own diagnosis.
