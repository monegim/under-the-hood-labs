# Lab 20 — Concept: ProxySQL's Three-Layer Configuration Model

## What's actually going on

ProxySQL doesn't have one configuration — it has three, and understanding
that they can each independently disagree with each other is the whole
key to this lab. The **working tables** (`mysql_servers`, `mysql_users`,
and others) are what you directly `INSERT`/`UPDATE`/`DELETE` against —
they're staging, not yet doing anything. **RUNTIME** is the live,
in-memory configuration actually routing traffic right now — a working
table's contents only take effect once you explicitly
`LOAD ... TO RUNTIME`, copying that category from the working tables
into RUNTIME. **DISK** is a persistent SQLite database ProxySQL reads
from at startup — a working table's contents only survive a restart
once you explicitly `SAVE ... TO DISK`. Three layers, three separate
commands, and no automatic sync between any of them in either
direction. Editing the working table changes nothing live. Loading to
RUNTIME changes live traffic but nothing about what survives a restart.
Only `SAVE ... TO DISK` addresses persistence, and it's the step
easiest to forget precisely because the fix already looks
finished — the query already works — by the time you'd normally think
to run it.

Two things make this worse than "just remember to run one extra
command." First, `SAVE`/`LOAD` operate per-category, not globally —
`mysql_servers` and `mysql_users` (and query rules, and variables, and
more) each need their own `LOAD ... TO RUNTIME` and `SAVE ... TO DISK`.
Running one is not evidence you ran, or even thought about, any other —
which is exactly how a routing fix (servers) ships fully durable while
a credentials fix (users) made in the same incident doesn't, with
nothing at the time distinguishing the two. Second, the *direction* of
these commands is genuinely easy to get backwards under pressure:
`LOAD ... FROM DISK` exists too, and it moves data the opposite way
from every other command in this lab — from the on-disk config back
*into* the working tables, overwriting them. A person reaching for "let
me reload/re-sync the config" with good intentions can run exactly this
command and instead silently discard whatever live, unsaved changes
were sitting in the working tables at that moment, with no warning and
no confirmation prompt.

ProxySQL does expose a way to check for drift between these layers
without waiting for a restart to find out the hard way: its admin
interface presents `disk` as a genuine, queryable database
(`SHOW DATABASES;` lists it next to `main`, `stats`, and `monitor`),
backed directly by the same SQLite file it reads at startup. Comparing
a working table against its `disk.*` counterpart, right after making a
change, answers the one question that actually matters — "if ProxySQL
restarted this second, would this survive?" — well before any restart
puts that question to the test for real.

## Where this shows up in the real world

Anywhere a live system separates "make it work now" from "make it
survive a restart" as two different actions, whoever's under pressure
to fix something immediately is going to complete the first one and
move on — that's not a character flaw, it's what "the outage is over"
actually feels like from inside an incident. The gap only becomes
visible at the next unrelated restart: an upgrade, a host reboot, an
orchestrator rescheduling a pod, none of which have any obvious
connection to a routing change made weeks earlier. That delay is what
makes this class of incident specifically hard to diagnose — the
person paged for "ProxySQL is rejecting everyone" has no natural reason
to suspect a config change that already, apparently, worked. Building
"did I persist this" into the same muscle memory as "did I load this"
— or automating the two together entirely, so a fix can't ship without
both — is the only real defense; the failure mode isn't a knowledge
gap once you've seen it, it's a step that's structurally too easy to
skip.

## Go deeper

- **Website/docs:** ProxySQL documentation, "Main Runtime Admin Tables" — https://proxysql.com/documentation/main-runtime/ — describes the working tables, `LOAD ... TO RUNTIME`, and `SAVE ... TO DISK` for each configuration category.
- **Website/docs:** ProxySQL documentation, Admin Interface / `disk` database — https://proxysql.com/documentation/ — background on the admin interface's separate `main`, `disk`, `stats`, and `monitor` databases used in this lab's Step 3.
- **Website/docs:** ProxySQL wiki, "ProxySQL Configuration" — https://github.com/sysown/proxysql/wiki/ProxySQL-Configuration — the canonical explanation of the MEMORY/RUNTIME/DISK/CONFIG FILE layering and the full set of `LOAD`/`SAVE` command pairs.
- **Blog:** Percona, "ProxySQL Series" — https://www.percona.com/blog/ — operational posts on ProxySQL configuration management, including common persistence pitfalls in production.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — the chapters on operational visibility and configuration management are directly relevant to why "it works right now" and "it will still work tomorrow" need to be treated as two separate, separately-verified claims.
