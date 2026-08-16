# Lab 15 — Concept: ProxySQL's Three Independent Connection Ceilings

## What's actually going on

ProxySQL sits between application clients and one or more MySQL
backends, and — like any connection pooler — exists specifically so
that a large number of client-side connections can share a much smaller
number of actual backend connections, each backend connection being
expensive in a way a client connection isn't (a real MySQL backend
connection is a full server-side thread/process with real memory
overhead; ProxySQL's own client-facing connections are comparatively
cheap). Making that work safely means ProxySQL has to police capacity
at more than one point, and this lab's three failure modes correspond
to three different points in that pipeline where it does so.

`mysql_servers.max_connections` (the main lab's fault) caps how many
connections ProxySQL will open to one specific backend, per hostgroup —
this is the multiplexing limit, the thing that lets many more clients
be served than the backend has connections for, by having ProxySQL hand
a backend connection to whichever client statement needs it *right
now*, then return it to the pool. When every backend connection is
currently checked out, a new client's request doesn't fail — it queues,
because from ProxySQL's point of view this is completely normal,
expected behavior under load, not an error condition.

`mysql_users.max_connections` (Challenge A) is checked earlier, at the
moment a specific client tries to authenticate to ProxySQL itself, and
it's scoped per-username — it exists to stop a single misbehaving
application or tenant from monopolizing ProxySQL's own client-handling
capacity, independent of how large the backend pool is. `mysql-
max_connections` (Challenge B) is checked at the same authentication
point but has no scope narrower than "all of ProxySQL" — it's the
absolute ceiling on ProxySQL's own front door, existing to protect
ProxySQL's own process (file descriptors, memory) regardless of which
users or backends are involved. Both of these front-end checks fail
*immediately and explicitly*, because ProxySQL can evaluate them the
instant a client connects, before any backend is ever involved — which
is structurally why they behave nothing like the pool-exhaustion case:
there's no reason to make a client wait for a decision ProxySQL already
has all the information to make instantly.

## Where this shows up in the real world

Connection pooler exhaustion masquerading as "the database is
overloaded" is one of the most common false diagnoses in production
MySQL environments — teams reach for scaling up MySQL itself (more
`max_connections`, a bigger instance) when the actual constraint is a
ProxySQL/PgBouncer/similar pool sized years ago for a different traffic
pattern. The three-way split this lab demonstrates is specifically a
ProxySQL characteristic worth knowing cold if you operate it: a
`1040`/`Too many connections` error gets escalated as "the database is
down" when it's actually ProxySQL's own front door, and a `1226`
(`max_user_connections`) gets misread as a MySQL-side privilege problem
when it's actually a ProxySQL per-user throttle — both are one `grep`
of the error text away from a fast, correct diagnosis, but only if you
know these are ProxySQL's own errors and not MySQL's.

## Go deeper

- **Website/docs:** ProxySQL official documentation, Global Variables — https://proxysql.com/documentation/global-variables/ — covers `mysql-max_connections` and every other `mysql-*` runtime variable.
- **Website/docs:** ProxySQL official documentation, `mysql_servers` table — https://proxysql.com/documentation/main-runtime/#mysql_servers — the authoritative reference for per-backend `max_connections` and hostgroup configuration.
- **Website/docs:** ProxySQL official documentation, `mysql_users` table — https://proxysql.com/documentation/main-runtime/#mysql_users — the per-user `max_connections` column and other per-user settings.
- **Website/docs:** ProxySQL official documentation, Statistics — https://proxysql.com/documentation/statistics/ — `stats_mysql_connection_pool` and `stats_mysql_global`, the two tables this lab relies on to tell these failure modes apart.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — frames connection management and pooling layers as first-class production reliability concerns, directly applicable across PgBouncer, ProxySQL, and similar tools.
