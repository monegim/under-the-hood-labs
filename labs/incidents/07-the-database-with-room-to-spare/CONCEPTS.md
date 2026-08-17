# Incident 07 — Concept: Inodes Are a Separate Budget From Bytes

## What's actually going on

Two mechanisms combine here: a filesystem resource almost nobody
monitors as a first reflex, and a database storage engine's need to
periodically create brand-new files, not just grow existing ones.

Every file or directory on a filesystem needs an inode - a fixed-size
metadata record (ownership, permissions, timestamps, pointers to the
actual data blocks) separate from the file's *content*. A filesystem
is formatted with a finite number of inodes, decided up front,
completely independent of how many bytes of storage it has - a
filesystem can be 99% empty by size and 100% full by inode count at
the same time, and vice versa. `df -h` reports byte usage; `df -i`
reports inode usage; they are two different questions with two
different answers, and only one of them is what most disk-usage
dashboards default to showing. A workload that creates huge numbers of
tiny files - a session store, a mail queue, a request-logger writing
one file per hit - can exhaust a filesystem's inode budget while its
byte usage barely moves, because inode cost is per-file, not
per-byte.

Postgres (like most databases) mostly *extends* existing files as data
grows - appending more blocks to a heap file it already has open
doesn't need a new inode at all. But a table's storage isn't just one
file forever: Postgres creates separate supporting files alongside a
table's main data file as it grows - a free-space map (`_fsm`) to track
which pages have room for new rows, a visibility map (`_vm`) for
vacuum/index-only-scan bookkeeping - and WAL segments get created fresh
when there's no already-used segment available to recycle. Every one of
those *is* a new-file-creation event, needing a fresh inode, and it
happens automatically, silently, whenever the table's growth crosses
the relevant threshold - not something application code requests or
even knows is happening. Under light, steady traffic, small individual
writes can keep succeeding for a long time even on an inode-exhausted
filesystem, simply because they don't happen to need a new file yet -
which is exactly what makes this fail *intermittently* rather than
immediately: the write that finally needs the next new file is the one
that fails, and every write behind it that depends on that same
not-yet-created file fails identically from then on.

## Where this shows up in the real world

Container platforms and cloud VMs routinely put multiple, logically
unrelated workloads on one shared filesystem - a database's data
volume, an application's log output, a session cache, a temp-file
scratch space - because it's simpler to provision one disk than several.
Nothing about that sharing is visible from either workload's own point
of view; each one just writes to its own directory. Inode exhaustion is
one of the most common "impossible" incidents precisely because the
standard first check (a disk-usage-in-bytes dashboard, `df -h`, cloud
storage-utilization alarms) reports everything as fine, and the actual
signal lives in a metric most monitoring setups never wire an alert
onto at all. Any workload that generates one file per unit of work -
logs, sessions, queues, generated reports, uploaded temp files - is a
latent version of this incident waiting for whatever else shares its
filesystem, database or not, to be the one that eventually needs a file
that can't be created.

## Go deeper

- **Website/docs:** man7.org, `statvfs(3)` — https://man7.org/linux/man-pages/man3/statvfs.3.html
  — the underlying system call `df -i` reads from; documents `f_files`/`f_ffree`
  (total/free inodes) as fields entirely separate from the byte-capacity fields.
- **Website/docs:** PostgreSQL documentation, "Free Space Map" — https://www.postgresql.org/docs/current/storage-fsm.html
  — what the `_fsm` fork this incident's error names is for, and when Postgres creates one.
- **Website/docs:** PostgreSQL documentation, "WAL Configuration" — https://www.postgresql.org/docs/current/wal-configuration.html
  — `min_wal_size`/`max_wal_size` and how Postgres recycles vs. creates new WAL segment files.
- **Man page:** `df(1)` — `man df` (`-i` flag) — the one-flag difference this entire incident hinges on.
- **Related lab:** [`labs/linux/11-disk-full-writes-fail`](../../linux/11-disk-full-writes-fail)
  — the same inode-exhaustion mechanism in isolation, on a bare
  filesystem with no database involved; this incident is what it looks
  like one layer up, through a real storage engine's error messages.
