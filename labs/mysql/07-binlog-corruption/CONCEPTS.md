# Lab 7 — Concept: Binary Logs Are Ordinary Files, and Ordinary Files Can Rot

## What's actually going on

A binary log file is just a sequence of length-prefixed, checksummed
binary event records written to an ordinary file on disk — there's
nothing magical protecting it from the same failure modes as any other
file: a bad disk sector, a partial write during a power loss or host
crash, a botched `cp`/`rsync` during a backup or migration, or (as this
lab simulates directly) outright bit corruption. What makes corruption
here different from corruption in, say, an InnoDB tablespace file is
*when* it gets discovered. InnoDB continuously validates its own pages via
checksums during normal operation, so tablespace corruption tends to
surface quickly. A binlog file, once written and rotated away from, is
mostly just... sitting there, unread, until something specifically asks
to read through it — a replica's IO thread catching up from an old
position, a `mysqlbinlog` invocation during point-in-time recovery, or a
manual audit. Nothing continuously verifies its integrity in the
background. That's exactly why this lab's main scenario deliberately
corrupts an *already-rotated* file rather than the currently active one:
MySQL's crash-recovery logic at startup does validate (and, if needed,
safely truncate) whatever binlog file was open at the moment of the last
stop or crash — but it has no reason to, and does not, revisit any older,
already-rotated file, because those are assumed to be closed, immutable
history. An old file's corruption can sit completely undetected for an
arbitrary length of time.

When a replica's IO thread requests events starting at a specific
file/position (or, under GTID auto-positioning, the equivalent set of
transactions), it's doing exactly the same kind of read `mysqlbinlog`
does — parsing the binary event stream sequentially, verifying checksums
per event. Hit a corrupted region, and that parse simply fails: the IO
thread can't produce well-formed events to send onward or apply, and
`Replica_IO_Running` flips to `No` with a `Last_IO_Error` describing the
read/parse failure. This is a meaningfully different failure than Lab 2's
GTID conflict, even though both eventually show up as "replication
broken": there, the IO thread was working fine and only the SQL/apply
thread choked on a specific transaction it *could* read. Here, the IO
thread itself cannot successfully retrieve the data at all — which is
precisely why Lab 2's `SET GTID_NEXT` skip technique doesn't apply: that
trick tells the replica to consider a transaction it already *has* (in
its relay log) as already applied; it has nothing to offer when the
source-side data needed to produce that transaction in the first place
is unreadable.

This is also why there is often genuinely no clean single-command fix for
binlog corruption, unlike almost every other incident in this repo. The
honest, real-world answer is re-provisioning: take a fresh, consistent
snapshot of the primary's *current* state (via `mysqldump
--set-gtid-purged=ON`, or a physical tool like Percona XtraBackup) and
restore the replica from that, rather than trying to repair or route
around the specific corrupted bytes. `--set-gtid-purged=ON` matters
mechanically here: it captures the primary's `gtid_executed` set at the
moment of the dump and encodes it as `SET @@GLOBAL.gtid_purged=...` in the
restore script, so the freshly re-provisioned replica's own `gtid_purged`
correctly reflects "everything up through this snapshot is already
accounted for" — auto-positioning then resumes cleanly from whatever the
primary commits *after* the snapshot, without either side ever needing to
touch the corrupted history again.

## Where this shows up in the real world

Binlog corruption is rarer in practice than, say, replication lag or
deadlocks, but it's disproportionately scary when it happens precisely
because there's no standard playbook step that "fixes" it — every
postmortem for a real incident like this ends in some version of
"re-provisioned from a snapshot," not "repaired the file." It shows up
after real disk hardware failures, botched storage-level snapshot/restore
operations, filesystem corruption from an ungraceful VM host crash, or
(as Challenge B highlights) sitting silently in an old binlog nobody
reads until a disaster-recovery drill or a real incident tries to replay
it for point-in-time recovery — which is exactly why regularly testing
backup+binlog-replay recovery paths, not just taking backups, is
considered a baseline DBRE practice.

## Go deeper

- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/mysqlbinlog.html — `mysqlbinlog` usage for inspecting and validating binary log contents.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/show-binlog-events.html — `SHOW BINLOG EVENTS` syntax and output.
- **Website/docs:** MySQL official docs — https://dev.mysql.com/doc/refman/8.0/en/replication-gtids.html — `gtid_purged`/`gtid_executed` and how `--set-gtid-purged` on `mysqldump` interacts with re-provisioning a replica.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors — the operational discipline of testing recovery paths (not just taking backups) before you need them for real.
- **Website/blog:** Percona blog — https://www.percona.com/blog/ — coverage of binlog corruption incidents and safe replica re-provisioning practices.
