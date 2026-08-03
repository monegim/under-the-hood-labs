# Lab 8 — Concept: A Connection Limit Protects the Server, Not the App

## What's actually going on

Every MySQL client connection costs the server real resources — a thread
(or, under the thread pool plugin, a slot in a fixed-size pool), memory
for per-connection buffers (`sort_buffer_size`, `join_buffer_size`, and
others are allocated per-connection/per-operation, not shared), and at
least one OS file descriptor. `max_connections` exists to protect the
server from being overwhelmed by more simultaneous clients than it can
realistically serve — once that ceiling is hit, MySQL rejects any further
new connection attempt outright with `ERROR 1040 (HY000): Too many
connections`, before the new connection ever gets to run a single query.
Critically, this limit counts connections, not activity: a connection
sitting completely idle in `Sleep` state (a client that ran one query and
then never disconnected, never sent another statement, and never got
closed) consumes a slot exactly as fully as one running a heavy query
right now. A broken connection pool — one that opens a new connection per
request instead of reusing a fixed set, or that leaks a connection down
some error-handling code path that forgets to close it — can exhaust
`max_connections` with connections doing absolutely nothing, which is
exactly what this lab reproduces: 50 slots, all consumed by sessions
sitting in `DO SLEEP(...)`, with zero real query load on the server at
all.

MySQL carves out one specific exception to `max_connections`: an account
holding the `SUPER` privilege (or, in 8.0's more granular privilege model,
`CONNECTION_ADMIN`) can still connect even after ordinary accounts start
being rejected, via one extra reserved connection slot on top of
`max_connections`. This isn't an accident or a bug — it exists
specifically so that an operator with administrative access always has a
way in during exactly this kind of incident, to run `SHOW PROCESSLIST`,
identify the offending sessions, and `KILL` them, without needing to
first solve the chicken-and-egg problem of "I can't connect to fix the
thing preventing me from connecting."

Two configuration levers matter here, and they solve different halves of
the problem. `max_connections` is the hard ceiling — raising it during an
incident (`SET GLOBAL max_connections=...`) buys headroom immediately,
but does nothing to stop whatever is actually consuming connections
faster than it should; it just moves the wall further away. `wait_timeout`
(and its interactive-session counterpart, `interactive_timeout`) is the
one that addresses genuinely idle connections specifically: MySQL's
default is a generous 8 hours, meaning a connection that goes idle (no
new statement sent) will sit there, fully consuming its slot, for up to 8
hours before the server itself closes it. A much shorter `wait_timeout` is
a real server-side safety net against a leaking pool — but it's a
mitigation, not the fix, because the actual bug (a pool not returning
connections, or opening far more than it needs) still exists at the
application layer and will keep generating new sleeping connections up to
whatever the new, shorter timeout allows.

## Where this shows up in the real world

Connection storms are one of the most common "the database is fine, the
app is what broke" incidents: a deploy introduces a connection-pool
regression, a downstream dependency slows down and each in-flight request
holds its connection longer than usual while a fixed-size pool keeps
opening more to compensate, or a traffic spike combined with a
too-small database-side `max_connections` (or a too-generous one, paired
with a pool that has no maximum of its own) causes the exact same
"database suddenly rejecting everyone" symptom. Any operator's first
useful move is almost always `SHOW PROCESSLIST`/`Threads_connected`
grouped by user and command — distinguishing "many different real users
doing real work" from "one user, one state (`Sleep`), way too many times"
takes seconds and immediately tells you whether you're looking at
capacity planning or a bug.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_max_connections — `max_connections`, including the reserved extra connection for `SUPER`/`CONNECTION_ADMIN`.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_wait_timeout — `wait_timeout`/`interactive_timeout` semantics.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_open_files_limit — `open_files_limit` and how mysqld silently recalculates effective connection capacity against it at startup.
- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — connection handling, pooling patterns, and resource sizing for connection-heavy workloads.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — recurring coverage of connection-storm incidents and application-side pooling misconfigurations.
