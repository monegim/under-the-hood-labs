# Lab 22 — Concept: System Versioning Is a Storage Model, Not a Log

## What's actually going on

`WITH SYSTEM VERSIONING` adds two hidden columns to a table — a row
start and row end timestamp — and changes what `UPDATE` and `DELETE`
actually do at the storage layer. Neither one overwrites or removes a
row in place anymore: an `UPDATE` closes the current row's end
timestamp and inserts a brand-new row with the updated values and an
open end timestamp; a `DELETE` closes the current row's end timestamp
and inserts nothing. Every ordinary query implicitly filters to rows
whose end timestamp is still open (`FOR SYSTEM_TIME AS OF NOW()`,
applied automatically), which is why the table looks and behaves
completely normally to any application code that was never written
with versioning in mind — the filtering is invisible by design. `FOR
SYSTEM_TIME ALL` (or `AS OF` a specific timestamp) simply removes that
implicit filter, exposing rows that were there the entire time.

This is a fundamentally different model from an application-level
audit log or a `history` shadow table populated by triggers — those
are opt-in, additive, and something a team has to actively decide to
maintain. System versioning is built into the storage engine itself,
transparent to every write, and — critically — has no default
retention policy. A conventional audit log grows because someone
decided logging mattered enough to build; a system-versioned table
grows because nothing was ever configured to make it stop, which is a
meaningfully different failure mode to watch for operationally: the
first requires someone to have built something, the second requires
someone to have *not* configured something.

`DELETE HISTORY` exists as its own dedicated statement — distinct from
a plain `DELETE` — specifically because "remove this data" and "stop
keeping old versions of this data" are different operations on a
versioned table, and conflating them would mean either losing the
ability to bound history growth without destroying current data, or
the reverse.

## Where this shows up in the real world

Financial ledgers, regulatory-compliance data, and anything with a
genuine "what did this record look like on this date" requirement are
the natural fit for system versioning — and also exactly the kind of
data most likely to accumulate for years before anyone circles back to
check what "no retention policy configured" has actually cost in
storage. It's a newer, less broadly known feature relative to MySQL's
much more commonly reached-for combination of triggers plus a manual
shadow table, which means fewer engineers have already internalized
"this needs a retention policy" as a reflex the way they might for,
say, binary log retention or a queue table. The compliance angle cuts
both ways too: the same versioning that makes point-in-time recovery
trivial is also exactly the mechanism that can make "delete this
user's data" quietly incomplete if the history side isn't purged
alongside the current row.

## Go deeper

- **Website/docs:** MariaDB Knowledge Base, "System-Versioned Tables" — https://mariadb.com/kb/en/system-versioned-tables/ — the authoritative reference for `WITH SYSTEM VERSIONING`, `FOR SYSTEM_TIME`, and `DELETE HISTORY`.
- **Website/docs:** MariaDB Knowledge Base, "Application-Time Periods" — https://mariadb.com/kb/en/application-time-periods/ — the related, distinct feature for tracking a business-defined validity period rather than the storage-transaction-driven one this lab covers.
- **Website/docs:** MariaDB Knowledge Base, "System Versioning Overview" — https://mariadb.com/kb/en/system-versioning-overview/ — background on the SQL:2011 temporal-table standard MariaDB's implementation is based on.
- **Comparison:** MariaDB vs. MySQL feature comparison (search "MariaDB vs MySQL differences" on mariadb.com) — system versioning is one of several features MariaDB has that MySQL has no equivalent for at all, rather than just a syntax difference.
- **Book:** *Developing Time-Oriented Database Applications in SQL* — Richard T. Snodgrass (free PDF widely available) — the foundational text on temporal database design that the SQL:2011 standard (and MariaDB's implementation) draws from.
