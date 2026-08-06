# Lab 9 — Concept: The Redo Log Is a Capacity-Limited Buffer, Not Infinite Storage

## What's actually going on

InnoDB, like almost every serious database engine, uses write-ahead
logging: before a data page change is durable, the *intent* to make that
change is written to a sequential, append-only redo log and flushed to
disk. This is deliberately cheap — sequential I/O is fast — so a
transaction can commit as soon as its redo log entry is durable, without
waiting for the (much more expensive, random-I/O) actual data pages to be
rewritten. Those data page writes happen later, in the background, done
by threads that gradually "catch up" the on-disk data files to match what
the redo log says should have happened. The point up to which all the
data-page-level effects of the redo log have actually been written back
to disk is called the **checkpoint**. Everything in the redo log before
the checkpoint is safe to discard (or, in a fixed-capacity ring-buffer-like
log, to overwrite) — everything after it still needs to exist in case of a
crash, because it's the only durable record of changes that haven't made
it to their real home yet.

The redo log has a hard-configured capacity
(`innodb_redo_log_capacity` — a single setting since MySQL 8.0.30,
replacing the older `innodb_log_file_size` × `innodb_log_files_in_group`
product). That capacity puts a ceiling on how far ahead of the checkpoint
the current log sequence number (LSN) is allowed to get — the **checkpoint
age**. If write volume keeps generating new redo faster than the
background flushing threads can advance the checkpoint, checkpoint age
climbs toward that ceiling. InnoDB doesn't let it exceed the ceiling: as
checkpoint age approaches capacity, it switches from lazy, low-priority
background page flushing into "furious flushing" — an aggressive mode that
prioritizes writing dirty pages back to disk over almost everything else,
which directly steals I/O and CPU capacity from foreground query threads.
The result, from the application's point of view, is writes (and often
reads competing for the same I/O) getting visibly slower under sustained
load, with no error, no crash, and nothing showing up as "disk is full" —
just a system quietly self-throttling to protect a durability guarantee
it can't safely relax.

This lab makes the mechanism impossible to miss by setting
`innodb_redo_log_capacity` to 8MB — the documented minimum — against a
workload writing wide rows. In any real deployment the fix is proactive
sizing: give the redo log enough headroom that normal peak write bursts
never push checkpoint age anywhere near the ceiling, using
`SHOW ENGINE INNODB STATUS`'s LOG section (`Log sequence number` minus
`Last checkpoint at`) or the `Innodb_redo_log_current_lsn` /
`Innodb_redo_log_checkpoint_lsn` status variables to actually measure it
under representative load, rather than guessing a number. The trade-off
that keeps people from just setting it enormous: a bigger redo log means
more work (and more time) has to happen during crash recovery on restart,
since InnoDB has to replay everything since the last checkpoint before
the instance is usable again. Sizing the redo log is choosing a point on
that curve, not picking one extreme.

## Where this shows up in the real world

Undersized redo log capacity is a classic "worked fine in staging, fell
over during a real traffic spike" incident: staging's write volume never
got close to generating enough redo per second to expose the ceiling,
production's did. It's also a common side effect of blindly copying a
config from a smaller, older deployment forward as a database grows —
`innodb_log_file_size` (or its modern successor) is exactly the kind of
setting nobody revisits until it's already the bottleneck. Because the
symptom is "everything got slower" rather than a hard error, teams often
burn time on schema/index tuning or scaling out reads before anyone checks
`SHOW ENGINE INNODB STATUS`'s LOG section — the actual answer is usually
right there.

## Go deeper

- **Book:** *High Performance MySQL* — Baron Schwartz, Peter Zaitsev, Vadim Tkachenko — the standard reference for InnoDB's write path, checkpointing, and redo log tuning.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — capacity planning and the general discipline of measuring before sizing config that gates durability.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/innodb-redo-log.html — canonical reference for `innodb_redo_log_capacity`, checkpointing, and the 8.0.30 online-resize behavior.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — frequent deep dives on InnoDB redo log sizing and real-world write-stall postmortems.
- **YouTube:** Percona — https://www.youtube.com/@percona — talks on InnoDB internals and write-path performance tuning.
