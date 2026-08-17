# Lab 19 — Solutions

## Challenge A — same error message, completely different cause

**Check:**
```bash
docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -pTOTALLYWRONG appdb -e "SELECT 1;"
```
```
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'appuser'@'127.0.0.1' (using password: YES)
```
Compare against the main lab's failure:
```
ERROR 1045 (28000) at line 1: Access denied for user 'appuser'@'172.26.0.3' (using password: YES)
```

**Diagnosis:** two details separate these, and both point at *which
side* did the rejecting:

- The `ProxySQL Error:` prefix. ProxySQL adds this prefix only to
  errors it generates itself, before ever talking to a backend — a
  client-facing authentication check that ProxySQL does locally,
  against its own stored `mysql_users` row. The main lab's error has no
  such prefix, because that rejection came from the real MySQL server
  and ProxySQL is just relaying the backend's own error text verbatim.
- The host in the error. `127.0.0.1` here is ProxySQL's own listening
  address, as seen from the client's connection to ProxySQL itself —
  this error never got past ProxySQL. `172.26.0.3` in the main lab is
  the ProxySQL container's address as seen *from the backend's side* —
  proof the rejection happened one hop further in, on the actual MySQL
  server.

A client typo'ing its own password fails the very first check ProxySQL
does, before any backend connection is even attempted — cheap, fast,
and entirely local to ProxySQL. The main lab's stale-password incident
passes that exact same first check (the client's password is correct,
by ProxySQL's own records) and only fails on the second, deeper check
against the real backend.

**Lesson:** don't stop reading an "Access denied" error at the words
"Access denied." The `ProxySQL Error:` prefix and which host appears in
the message tell you, immediately, whether to go fix the client's
credentials or go compare ProxySQL's stored password against the
backend's actual one — two completely different investigations that
this one error message covers for.

---

## Challenge B — the monitor user isn't the app user, and a broken one hides in plain sight

**Check (after waiting a full `mysql-monitor_connect_interval`, 60s by default):**
```bash
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT hostgroup_id, hostname, status FROM mysql_servers;"
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT hostname, connect_error FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 3;"
docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -protated-backend-pass appdb -e "SELECT 1;"
```
`status` says `ONLINE`. `mysql_server_connect_log` shows a fresh
`Access denied for user 'monitor'@'...'` on every check since the
password broke. The application query succeeds cleanly. All three, at
once.

**Diagnosis:** ProxySQL tracks the health of a backend server, not the
health of any one credential — and it uses *two separate* monitor
checks that don't behave the same way once a password goes bad:

- The **connect check** (`mysql-monitor_connect_interval`, 60s by
  default) opens a genuinely new connection each time it runs, which
  means it re-authenticates every single interval. This is the one
  that actually catches a broken monitor password, and it caught it
  here — that's exactly what showed up in
  `mysql_server_connect_log`.
- The **ping check** (`mysql-monitor_ping_interval`, 10s by default)
  keeps a connection open and reuses it — it's a lightweight keepalive
  against a connection that's already authenticated, not a fresh login
  attempt. MySQL doesn't invalidate that already-open session just
  because the password changed later (the same pooling behavior behind
  the main lab's incident, showing up again here on the monitor side).
  So `mysql_server_ping_log` keeps reporting success, using a session
  that was authenticated before the password broke.

Notice what's missing from ProxySQL's variables here: there's a
`mysql-monitor_ping_max_failures` (3, by default) governing when
repeated *ping* failures shun a server out of `status = ONLINE` — but
no equivalent variable for connect-check failures. The connect check
existing separately from the shunning logic entirely explains what you
just saw: the connect check can fail forever without `status` ever
reacting to it, because failing the connect check was never the signal
`status` is wired to. And the ping check — the one that *is* wired to
it — never fails here in the first place, for the reason above.
Either way, `status` was never going to move, and the application's own
`appuser` connections are a completely separate credential that was
never touched — nothing about its own path actually broke.

**Lesson:** `status = ONLINE` answers "can ProxySQL currently route to
this backend," not "is my monitoring actually working." A broken
monitor credential degrades silently — application traffic keeps
flowing (a real outage would be caught by the *next* connect check,
just like this fault was), but every diagnostic signal ProxySQL is
supposed to surface between now and then is compromised in a way
nothing in `mysql_servers` will tell you about. Check the monitor
user's credentials as their own, first-class thing to alert on — not
something you assume is fine because the application is fine.
