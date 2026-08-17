# Lab 19 — Concept: ProxySQL Credential Storage and Connection Pooling

## What's actually going on

ProxySQL sits in front of MySQL as a proxy, and for every user it's
configured to accept, its `mysql_users` table stores exactly one
password — not a client-facing password and a separate backend
password, just one value. That single value does double duty: it's
what ProxySQL checks an incoming client's credentials against, *and*
it's what ProxySQL itself presents when it opens a connection to the
real backend on that client's behalf. Nothing forces those two roles to
stay in sync automatically — if the backend's actual password changes
(a manual `ALTER USER`, a credential-rotation policy, anything that
touches MySQL directly instead of going through ProxySQL) and nobody
updates ProxySQL's copy, ProxySQL keeps accepting clients using the old
password just fine, because its own client-facing check never
consulted the backend at all. The failure only appears one layer
deeper, when ProxySQL tries to actually use that same stale password
against the real server.

Making this worse — and more realistic as an incident — ProxySQL pools
backend connections and reuses them across queries rather than opening
a fresh one every time. MySQL, like most database servers, does not
retroactively invalidate a session that's already authenticated just
because the underlying user's password changes later. So a connection
ProxySQL opened *before* a password rotation keeps working perfectly
fine afterward, using credentials that, from the backend's current
point of view, no longer exist. The actual failure only surfaces once
that specific pooled connection gets recycled for some other reason —
an idle timeout, a backend restart, ProxySQL itself restarting — and
ProxySQL has to authenticate fresh. That can happen anywhere from
instantly to hours after the actual rotation, which is exactly the kind
of delayed, hard-to-correlate symptom that makes credential-rotation
incidents so much harder to trace back to their real cause than the
underlying mechanism actually is.

This split shows up again, slightly differently, in how ProxySQL
monitors backend health. Its "connect" check
(`mysql-monitor_connect_interval`) opens a genuinely new connection
every interval and therefore re-authenticates every time — it's the
one that reliably notices a broken credential. Its "ping" check
(`mysql-monitor_ping_interval`) reuses an already-open, already
-authenticated connection as a lightweight keepalive, and inherits the
exact same pooling blind spot as the application traffic does: a
password that breaks *after* the ping connection was established stays
invisible to it indefinitely. Only the ping check feeds ProxySQL's
`mysql-monitor_ping_max_failures`-based shunning logic that can flip a
server's `status` away from `ONLINE` — there's no equivalent
failure-count threshold wired to the connect check at all. The result:
a broken monitor credential can sit in `mysql_server_connect_log`,
failing every single check, forever, without `mysql_servers.status`
ever reflecting it, and without the application noticing anything is
wrong either.

## Where this shows up in the real world

Credential rotation is routine — security policy, compliance
requirements, or just responding to a suspected leak — and any process
for it that doesn't explicitly include "and update ProxySQL's copy of
this" will eventually produce exactly this incident. It's a
particularly nasty one operationally because the delay between cause
and symptom (driven by connection pooling) breaks the instinct to look
at "what changed right before this started" — by the time a pooled
connection finally recycles and the failure appears, the actual
rotation can be long forgotten, buried behind whatever else happened in
between. The fix — keep ProxySQL's stored credentials in lock-step with
whatever system of record issues them, ideally through the same
automation that performs the rotation rather than a manual follow-up
step — is straightforward once you know this is the failure mode; the
hard part is recognizing it from the symptom, which looks like
"everything was fine, then randomly wasn't" rather than anything
obviously connected to a password change.

## Go deeper

- **Website/docs:** ProxySQL documentation, "Users" configuration — https://proxysql.com/documentation/main-runtime/#mysql_users — describes the `mysql_users` table and how ProxySQL uses a user's stored password for both client authentication and backend connections.
- **Website/docs:** ProxySQL documentation, "Global Variables" (Monitor section) — https://proxysql.com/documentation/global-variables/ — covers `mysql-monitor_connect_interval`, `mysql-monitor_ping_interval`, and `mysql-monitor_ping_max_failures`, the variables behind this lab's Challenge B.
- **Website/docs:** MySQL 8.0 Reference Manual, "Adding Accounts, Assigning Privileges, and Dropping Accounts" — https://dev.mysql.com/doc/refman/8.0/en/adding-users.html — background on `ALTER USER` and how MySQL handles already-open sessions when a password changes.
- **Blog:** Percona, "ProxySQL Series" — https://www.percona.com/blog/ — Percona's ProxySQL posts cover connection pooling behavior and monitor configuration in more operational depth than the reference docs alone.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — the chapters on infrastructure engineering and mediation layers (proxies like ProxySQL sitting between application and datastore) frame exactly this class of "correctly-configured-until-something-upstream-changes" failure.
