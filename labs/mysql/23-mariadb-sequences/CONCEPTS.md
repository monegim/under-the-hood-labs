# Lab 23 — Concept: A Sequence Is an Object, Not a Column Property

## What's actually going on

MySQL's `AUTO_INCREMENT` is a property of one column on one table -
the counter lives with the table, and nothing else can reference it.
MariaDB's `SEQUENCE` inverts that relationship: it's a standalone
schema object, created and altered independently of any table, that
any number of columns on any number of tables can pull values from
via `NEXTVAL()`. That independence is exactly what makes it more
capable (one counter genuinely shared across tables, explicit
`CYCLE`/bounds behavior, `SETVAL()` for controlled jumps) and exactly
what makes its failure modes different from `AUTO_INCREMENT`'s more
familiar ones.

`CACHE` exists because persisting a sequence's current value to disk
on every single `NEXTVAL()` call would make it a meaningful write
bottleneck under real throughput - so instead, MariaDB reserves and
persists an entire block of upcoming values at once, then hands them
out from memory one at a time without touching disk again until the
block is exhausted. This is a real, standard technique (the same
class of tradeoff Oracle and PostgreSQL sequences make with their own
cache settings) - but it means the durable, on-disk state of the
sequence is always *ahead* of what's actually been issued, by up to
the full cache size, for the entire time that block is being consumed
from memory. Anything that discards in-memory state without a clean
handoff - a restart, a crash, `RESTART WITH` - leaves the durable
state exactly where it already was: ahead. There's no "how much of the
cache was actually used" recorded anywhere to roll back to; the gap
isn't calculated after the fact, it's just the natural consequence of
having already committed to a value that memory alone was tracking.

`CYCLE` and shared sequences are both real capabilities that solve
real problems - a rotating pool of bounded identifiers, one counter
guaranteeing uniqueness across multiple related tables - and both
depend entirely on the calling code understanding what guarantee a
sequence actually provides. A sequence guarantees each `NEXTVAL()`
call returns a value the sequence itself hasn't handed out before *in
the current cycle* - it says nothing about whether that value is safe
to reuse in whatever table ends up storing it, and nothing about which
specific table gets which values when several are drawing from the
same counter. Both of those are the calling schema's responsibility
entirely.

## Where this shows up in the real world

Sequence gaps from caching are one of the most common "wait, why did
my invoice/order numbers skip" support questions across every database
that implements cached sequences the same way (Oracle DBAs have been
fielding this exact question for decades) - and it's specifically
confusing here because nothing about it looks like an error: no
warning, no log entry calling out a skipped range, just a number that
was never issued. `CYCLE` misuse tends to surface later and more
alarmingly, as sporadic constraint-violation errors that look
data-corruption-adjacent right up until someone checks whether the
sequence backing the column actually wraps. Shared sequences are a
deliberate, valuable design choice in schemas that need cross-table ID
uniqueness (event-sourcing-style systems, anything unifying several
entity types under one identifier space) - and a source of real
confusion for anyone who joins the project later without knowing the
sharing was intentional.

## Go deeper

- **Website/docs:** MariaDB Knowledge Base, "Sequence Overview" — https://mariadb.com/kb/en/sequence-overview/ — the authoritative reference for `CREATE SEQUENCE`, `CACHE`, `CYCLE`, and every option this lab exercises.
- **Website/docs:** MariaDB Knowledge Base, "CREATE SEQUENCE" — https://mariadb.com/kb/en/create-sequence/ — full syntax reference, including `NOCACHE`/`CACHE n` and `CYCLE`/`NOCYCLE`.
- **Website/docs:** MariaDB Knowledge Base, "NEXTVAL" — https://mariadb.com/kb/en/nextval/ — exact semantics of value issuance and caching behavior.
- **Comparison:** Oracle Database documentation, "Sequences" (search "Oracle CREATE SEQUENCE CACHE") — Oracle's decades-older sequence implementation shares the exact same cache-vs-gap tradeoff; useful for seeing how a much older, widely-battle-tested system documents and discusses the identical mechanism.
- **Book:** *SQL Antipatterns* — Bill Karwin (Pragmatic Bookshelf) — the ID-generation-strategy chapters cover the broader class of assumptions ("gaps mean deletions," "IDs are sequential in insertion order") that this lab's challenges are each built around breaking.
