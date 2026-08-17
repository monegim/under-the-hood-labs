# Lab 12 — Concept: ProxySQL Query Routing

## What's actually going on

ProxySQL sits between your application and MySQL as a proxy that
understands the MySQL wire protocol well enough to inspect every query
and decide, per-query, which backend server it should go to. It doesn't
do this by asking MySQL anything at query time — it makes the decision
entirely from its own in-memory tables (`mysql_servers`,
`mysql_users`, `mysql_query_rules`), which you configure through a
completely separate MySQL-protocol "admin interface" on port 6032 (as
opposed to the actual traffic port, 6033 in this lab). This split is the
root of why misconfiguration here is so easy and so silent: ProxySQL has
no way to know that you *meant* hostgroup 10 to be "the writer" — a
hostgroup is just an integer bucket of servers to ProxySQL. If you tell
it server A is in bucket 10 and server B is in bucket 20, it will route
exactly that way with total confidence, whether or not bucket 10 actually
contains a writable server. There's no validation step, no "this server
claims read_only=1 but you configured it as a writer" warning at all.

Query routing itself happens through `mysql_query_rules`, which
ProxySQL evaluates as an ordered list against each incoming query's text
(via regex on `match_pattern`) — first match wins by default, which is
precisely what makes Challenge A possible: a broad pattern earlier in
`rule_id` order silently absorbs traffic that a later, more specific rule
was written to catch, *except* while a statement is inside an explicit
`BEGIN`/`COMMIT` transaction — ProxySQL pins every statement in an
open transaction to whichever backend connection it's already using,
specifically because a transaction can't safely be split across two
physical MySQL servers mid-flight, which is why the exact same broken
rule ordering produces different results depending on whether the query
runs standalone or inside a transaction. Every connecting user also has
a `default_hostgroup` in `mysql_users`, which is where a query lands if
*no* rule matches it at all — meaning a completely unmatched write
statement doesn't error out, it just goes wherever that user's default
points, correct or not.

Query rules have a second, independent job beyond routing: `cache_ttl`
lets a rule tell ProxySQL to cache that query's *result set* in its own
memory for a given number of milliseconds, serving repeat reads without
touching a backend at all — a real, useful latency optimization for
read-heavy, rarely-changing data. But ProxySQL's cache has no idea when
the underlying data changes; it just holds the cached rows until the TTL
expires, full stop. A write that goes through cleanly, immediately
followed by a read of the same row, can return the pre-write value for
the entire TTL window — indistinguishable from replication lag by
symptom alone (`stats_mysql_query_digest` shows a `hostgroup` of `-1`
for a cached response — ProxySQL's marker for "answered without
contacting any backend at all").

The specific failure mode here — `read_only=ON` rejecting a write — is
MySQL's own replica-protection mechanism, unrelated to ProxySQL: any
MySQL instance started with `--read-only` (which every sane replica
should be) refuses all non-superuser writes at the SQL layer, returning
error 1290. That's a deliberate, loud safety net. The dangerous half of
this bug is the read side: sending `SELECT`s to the primary when they
should go to a replica produces *no error at all* — the primary answers
correctly, it's just now carrying read load that was supposed to be
offloaded, and nothing in the stack surfaces that as a problem until
someone notices unexplained primary load or checks
`stats_mysql_query_digest`'s hostgroup column against their own mental
model of where traffic should be going.

## Where this shows up in the real world

Hostgroup swaps are one of the most common ProxySQL production incidents
precisely because they're a one-line data-entry error (two `INSERT`
statements with the numbers transposed) that produces two very different
symptoms at once: a loud, immediate failure (writes erroring against a
read-only server — gets a page fast) and a quiet, ongoing one (reads
hitting the primary — often goes unnoticed for a long time, showing up
only as "why does the primary have more load than the workload should
produce"). Query-result caching (Challenge B) is a separate, equally
common source of "read your own writes" bugs specifically because teams
add `cache_ttl` to a read-heavy query rule for a real latency win, and
the bug only shows up for the narrow set of rows that get written and
then immediately re-read — exactly the pattern a user hitting "save"
and then reloading the page produces, and exactly the symptom that gets
misdiagnosed as replication lag, since both look identical from the
application's point of view: "I just wrote this, why isn't it there?"

## Go deeper

- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko. Covers replication topologies and proxy-layer read/write splitting design, the context this lab's mistake happens inside of.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly). Frames proxy/routing-layer config as production infrastructure requiring the same rigor as the database itself — directly relevant to why a "one INSERT statement" bug like this deserves a runbook.
- **Website/docs:** ProxySQL official documentation — https://proxysql.com/documentation/ — authoritative reference for `mysql_servers`, `mysql_query_rules` evaluation order, and query-result caching (`cache_ttl`) used throughout this lab.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-solutions-scaleout.html — MySQL's own documentation on read scale-out and the `read_only`/`super_read_only` mechanism this lab's write failures rely on.
- **YouTube:** Percona — https://www.youtube.com/@percona — has ProxySQL-specific operational content alongside their broader MySQL replication/scaling material.
