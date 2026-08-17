# Lab 18 — Concept: Page Checksums and innodb_force_recovery

## What's actually going on

Every InnoDB page — 16KB by default — carries a checksum computed over
its contents, stored in a header field at the start of the page and
validated on every single read from disk. This exists because a
database silently returning corrupted data as if it were correct is
categorically worse than the database refusing to serve it at all —
wrong financial balances, wrong inventory counts, or wrong anything are
harder to detect and far more damaging than an outage. So by design,
the default response to a checksum mismatch isn't a warning and a
best-effort attempt to continue: it's an immediate, hard crash. This
lab's main scenario deliberately corrupts *only* the 4-byte checksum
field itself, leaving every actual row byte on that page untouched,
specifically to isolate this behavior from data loss — the crash you
see in Steps 2-3 is InnoDB refusing to trust a page it has no way to
verify, not evidence the underlying bytes are actually wrong (they
aren't, in this exact scenario).

`innodb_force_recovery` is a startup-time option (it cannot be set on a
running instance — the server has to be restarted with it) that
progressively relaxes this safety behavior, in six cumulative levels.
Level 1 (`SRV_FORCE_IGNORE_CORRUPT`) is the one this lab's main fix
uses: tolerate a checksum mismatch on an otherwise-intact page rather
than crash. Each higher level disables more — background operations,
certain consistency checks, eventually (level 6) skipping redo log
application on startup entirely. Every level shares one deliberate
restriction: as long as `innodb_force_recovery > 0`, InnoDB refuses any
operation that writes new committed data — plain `INSERT`s, and
anything that implies one, like `CREATE TABLE ... AS SELECT` — while
still allowing reads and certain non-data-writing DDL like `DROP TABLE`.
This is what makes force_recovery mode fundamentally a *diagnostic and
extraction* tool, not a way to keep operating normally: it's meant for
"get in, read out what you can, get back to normal operation," not for
running a live workload against.

The higher levels expose a genuinely more dangerous failure mode than
the crash they're meant to work around: when actual row *content* is
corrupted (not just a checksum), low force_recovery levels still crash
trying to parse the garbled bytes as a row — but the highest level can
succeed in returning *something*, without any indication that what it
returned is wrong. Different query shapes over the same corrupted data
can produce different, individually-incorrect results, because they
walk the page's structure differently and neither path has any
independent way to know the bytes it's interpreting are garbage. A
crash, however alarming, is at least honest about something being
wrong; a wrong-but-successful-looking result is not — which is why
treating anything extracted at the highest recovery levels as
unverified until independently cross-checked is not optional caution,
it's the only way to know whether you actually got real data back.

## Where this shows up in the real world

Page-level corruption is most often the result of hardware issues below
the database's control entirely — a failing disk, an uncorrected bit
flip in memory that gets written through, a power loss mid-write on a
system without battery-backed write caching — which is exactly why
InnoDB validates every page on every read rather than trusting the
filesystem or storage layer to have gotten it right. `innodb_force_recovery`
shows up in real incidents specifically when that validation catches
something and the instance won't start (or crashes immediately once it
does) — and the standard, correct procedure any experienced DBRE
follows is exactly this lab's shape: use the *lowest* level that gets
you enough access to dump data out, never assume a higher level's
success means more data survived than a lower level's crash implied,
and always finish by restoring into a genuinely fresh, uncorrupted
tablespace rather than leaving a production instance running in a
reduced-safety mode indefinitely.

## Go deeper

- **Website/docs:** MySQL 8.0 Reference Manual, Forcing InnoDB Recovery — https://dev.mysql.com/doc/refman/8.0/en/forcing-innodb-recovery.html — the authoritative reference for every `innodb_force_recovery` level and exactly what each one disables.
- **Website/docs:** MySQL 8.0 Reference Manual, InnoDB Checkpoints and Page Checksums — https://dev.mysql.com/doc/refman/8.0/en/innodb-checkpoints.html — background on how InnoDB validates on-disk pages.
- **Website/docs:** MySQL 8.0 Reference Manual, `INNODB_TABLESPACES` — https://dev.mysql.com/doc/refman/8.0/en/information-schema-innodb-tablespaces-table.html — the table used in Step 3 to resolve a numeric tablespace ID from an error message back to a real table name.
- **Blog:** Percona, "Fixing MySQL/InnoDB Corruption" — https://www.percona.com/blog/ — Percona's blog has multiple deep, practically-oriented posts on real InnoDB corruption incidents and recovery procedures, including the "don't trust force_recovery=6 results" caution this lab demonstrates directly.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — frames "when to trust a recovered system" as a first-class reliability question, directly applicable to the verification discipline this lab's Challenge A is built around.
