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
claims read_only=1 but you configured it as a writer" warning — that
gap is what Challenge B's `mysql_replication_hostgroups` feature exists
to close, and why misusing it (feeding it the same wrong numbers) makes
the exact same class of bug self-reinforcing instead of self-correcting.

Query routing itself happens through `mysql_query_rules`, which
ProxySQL evaluates as an ordered list against each incoming query's text
(via regex on `match_pattern`) — first match wins by default, which is
precisely what makes Challenge A possible: a broad pattern earlier in
`rule_id` order silently absorbs traffic that a later, more specific rule
was written to catch. Every connecting user also has a
`default_hostgroup` in `mysql_users`, which is where a query lands if
*no* rule matches it at all — meaning a completely unmatched write
statement doesn't error out, it just goes wherever that user's default
points, correct or not.

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
produce"). Teams that add ProxySQL's replication-monitor automation
(`mysql_replication_hostgroups`) specifically to prevent hostgroup drift
during failovers can, as in Challenge B, encode the *same* transposition
mistake into that automation — at which point the system actively fights
any manual correction, which is a much more confusing incident to be
inside of than a static misconfiguration, since "I fixed it and it broke
again on its own" looks like a completely different, scarier class of bug.

## Go deeper

- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko. Covers replication topologies and proxy-layer read/write splitting design, the context this lab's mistake happens inside of.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly). Frames proxy/routing-layer config as production infrastructure requiring the same rigor as the database itself — directly relevant to why a "one INSERT statement" bug like this deserves a runbook.
- **Website/docs:** ProxySQL official documentation — https://proxysql.com/documentation/ — authoritative reference for `mysql_servers`, `mysql_query_rules` evaluation order, and `mysql_replication_hostgroups` behavior used throughout this lab.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-solutions-scaleout.html — MySQL's own documentation on read scale-out and the `read_only`/`super_read_only` mechanism this lab's write failures rely on.
- **YouTube:** Percona — https://www.youtube.com/@percona — has ProxySQL-specific operational content alongside their broader MySQL replication/scaling material.
