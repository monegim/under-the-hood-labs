# Lab 19 — ProxySQL Auth Mismatch

## Objective
Diagnose why an application account that ProxySQL happily accepts still
can't run a single query — trace the failure down to a stale password
ProxySQL is holding for the backend, fix it, and learn to tell apart
three different-looking "access denied" errors that all sound the same
at first glance.

## Why this matters
ProxySQL sits between your application and MySQL, and for a given user
it stores exactly one password in `mysql_users` — that same value does
double duty as both the credential it checks an incoming client
against *and* the credential it presents to the real backend on that
client's behalf. Rotate the password on the backend directly (a
security team's routine credential rotation, a compliance-driven
change, anything that bypasses ProxySQL) without updating ProxySQL's
copy, and you get a genuinely confusing incident shape: the
application's own password never changed, so ProxySQL's client-facing
check still passes — the failure only shows up one layer deeper, and
often not immediately, because ProxySQL doesn't retroactively drop
connections it already had pooled and authenticated before the
rotation. Things can keep working for a while after the change that
actually broke them, which is exactly the kind of delayed, confusing
correlation that makes an incident hard to diagnose under pressure.

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
This brings up a MySQL backend and a ProxySQL instance in front of it,
configures `appuser` identically on both sides, confirms a query
through ProxySQL works, then rotates `appuser`'s password directly on
the backend — without telling ProxySQL. It also forces ProxySQL's
already-open backend connection to recycle (more on why in Step 2), so
the incident is live and reproducible the moment setup finishes,
instead of surfacing unpredictably whenever a connection happens to
get recycled on its own.

## Step 2 — Reproduce the failure
```bash
docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;"
```
```
ERROR 1045 (28000) at line 1: Access denied for user 'appuser'@'172.26.0.3' (using password: YES)
```
This is the *client's* password (`apppass`) — the one that's never
changed, and the one ProxySQL's client-facing check still accepts
without complaint. The error only appears once ProxySQL tries to use
that same stored password to open a connection to the real backend.
Note the host in the error — `172.26.0.3` is the ProxySQL container's
own address as seen *from the backend's side*, not the client's. That
detail matters in Step 4.

Why didn't this fail immediately after the rotation in Step 1, before
setup.sh forced the issue? MySQL doesn't invalidate a session that's
already authenticated just because the user's password changes later
— so a connection ProxySQL pooled *before* the rotation kept working
fine using credentials that, on paper, no longer exist. The failure
only appears once that pooled connection gets recycled and ProxySQL
has to authenticate to the backend again — which can happen minutes or
hours after the actual rotation, making "what changed right before
this started" much harder to answer in a real incident than it sounds.

## Step 3 — Diagnose
```bash
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SELECT username, password FROM mysql_users WHERE username='appuser';
"
```
ProxySQL still has `apppass` on file. Compare that against what the
backend actually expects now — you won't have this in a real incident
(you don't get to just print the plaintext password), but for this
lab, trying the old password directly against the backend confirms it:
```bash
docker exec lab19-primary mysql -uappuser -papppass appdb -e "SELECT 1;"
```
```
ERROR 1045 (28000): Access denied for user 'appuser'@'localhost' (using password: YES)
```
The backend rejects `apppass` outright. ProxySQL's copy is stale.

## Step 4 — Fix it
Sync ProxySQL's stored credential to match what the backend actually
has now:
```bash
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  UPDATE mysql_users SET password='rotated-backend-pass' WHERE username='appuser';
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL USERS TO DISK;
"
```
`LOAD ... TO RUNTIME` makes the change take effect immediately;
`SAVE ... TO DISK` makes it survive a ProxySQL restart (skip that half
and the fix silently reverts the next time ProxySQL restarts — its own
kind of incident). Because ProxySQL uses this one value for both
directions, the application now has to connect with the new password
too — that's the real-world coordination this incident actually
represents: a credential rotation isn't done until every consumer of
that credential, ProxySQL included, is updated to match.

## Step 5 — Verify
```bash
./check.sh
```
Reads `appuser`'s current password straight out of ProxySQL and
confirms a query through ProxySQL succeeds with it — passing regardless
of which direction you fixed the mismatch from, since either way it's
actually testing "is ProxySQL's stored credential consistent with what
the backend accepts."

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — same error message, completely different cause:**
```bash
./reset.sh
docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -pTOTALLYWRONG appdb -e "SELECT 1;"
```
```
ERROR 1045 (28000): ProxySQL Error: Access denied for user 'appuser'@'127.0.0.1' (using password: YES)
```
This also says "Access denied," but look closely at two details that
differ from Step 2's error: the `ProxySQL Error:` prefix, and the host
— `127.0.0.1` here instead of a container-network address like
`172.26.0.3`. Work out what each of those two details tells you about
*which side* rejected the connection, and why a client typo'ing its
own password produces a visibly different error than the backend
rejecting a stale one — even though both start with the identical
words "Access denied."

**Challenge B — the monitor user isn't the app user, and a broken one hides in plain sight:**
```bash
./reset.sh
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  UPDATE mysql_users SET password='rotated-backend-pass' WHERE username='appuser';
  LOAD MYSQL USERS TO RUNTIME;
"
docker exec lab19-primary mysql -uroot -prootpass -e "
  ALTER USER 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'wrong-monitor-pass';
"
```
ProxySQL only opens a *fresh* connection for its monitor "connect"
check once per `mysql-monitor_connect_interval` (60 seconds by
default) — wait a full minute for one of those to land, then compare
all three of these:
```bash
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT hostgroup_id, hostname, status FROM mysql_servers;"
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT hostname, connect_error FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 3;"
docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -protated-backend-pass appdb -e "SELECT 1;"
```
`mysql_servers.status` says `ONLINE`. The connect log tells a different
story. And the actual application query — using `appuser`, not
`monitor` — succeeds without any trouble at all. Explain why breaking
the monitor user's credentials doesn't take the backend offline from
ProxySQL's point of view, why `status` alone is not proof that
monitoring is actually working, and what you've silently lost the
ability to detect for as long as this goes unnoticed.

See `solution.md` only after you've formed your own diagnosis.
