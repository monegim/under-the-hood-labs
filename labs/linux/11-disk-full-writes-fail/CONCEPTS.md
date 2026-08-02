# Lab 11 — Concept: Inodes, Reserved Blocks, and the Two Independent Ways a Filesystem Runs Out of Room

## What's actually going on

An ext4 filesystem tracks two genuinely separate, independently
exhaustible resources: **data blocks** (the storage capacity you think of
as "disk space") and **inodes** (fixed-size metadata structures, one per
file/directory/symlink, holding ownership, permissions, timestamps, and
pointers to the data blocks that make up the file's content). `df -h`
reports block usage; `df -i` reports inode usage. Critically, the number
of inodes on an ext4 filesystem is normally decided once, at `mkfs` time,
and does not grow afterward — `mkfs.ext4` picks an inode count based on an
assumption about average file size (the `-i bytes-per-inode` ratio, or an
explicit count via `-N`). This lab deliberately formats with `-N 2000` on
a 200M filesystem — nowhere near enough inodes for that much space if the
workload creates lots of small/empty files — which is exactly the
mismatch that produces the lab's core gotcha: `df -h` shows plenty of
bytes free because almost none of the actual space got used, while `df
-i` shows `IUse%` at 100% because every one of the 2000 inode slots is
already allocated to a file, empty or not. A `write()`/`open(O_CREAT)`
call that would create a *new* file fails with `ENOSPC` ("No space left on
device") the moment there are zero free inodes, completely independent of
how many data blocks remain — the kernel simply has nowhere to record a
new file's metadata, regardless of how much room there is to store its
content.

This is precisely why any workload that creates large numbers of small or
zero-byte files — session stores, mail queues (one file per message),
cache directories, log-per-request setups, or (as in Challenge A) a
web app's session-file directory that never cleans up expired sessions —
can exhaust inodes long before it exhausts space, in a way that's
completely invisible to anyone only checking `df -h`. Diagnosing which
directory is the actual leak (Challenge A) comes down to the same
principle used elsewhere in this series: don't start deleting from the
mount root, count entries per subdirectory first (a `find | wc -l` sweep)
to localize the actual offender before touching anything.

Challenge B exposes a second, unrelated mechanism that produces an
identical-looking symptom for a completely different reason: ext4
reserves a configurable percentage of its data blocks (`tune2fs -m`,
default 5%) that only root can allocate into. This exists as a
deliberate safety margin — a filesystem filled entirely by unprivileged
processes should never be able to fully starve root, since root needs
guaranteed room to log in, write diagnostic logs, and clean things up.
`df` by default reports space available *to the calling user* — for a
non-root process, that figure already excludes the root-reserved chunk,
so `df -h` correctly shows less free space available to that user than
the filesystem's raw total. Cranking the reservation up to 50% (as this
lab does) means a normal user hits `ENOSPC` well before the disk is
anywhere close to physically full, and the write only succeeds when
retried as root, which is the tell that this is a reservation issue, not
a real capacity issue.

## Where this shows up in the real world

"`No space left on device` when `df -h` clearly shows free space" is one
of the most confusing on-call pages there is, precisely because the
instinctive first check (bytes) is the wrong resource to look at in both
of this lab's scenarios. Any high-file-count workload is a real inode-
exhaustion risk in production — mail servers, PHP session directories,
Docker image layer caches, and CI artifact directories are classic real
offenders. The reserved-blocks case shows up any time a shared filesystem
approaches capacity and non-root writes start failing mysteriously while
root's own writes (backups, log rotation, cleanup scripts) keep working
fine, which is by design, not a bug. Reflexively checking `df -i` alongside
`df -h`, and `tune2fs -l | grep -i reserved` when the numbers still don't
add up, turns a confusing page into a two-command diagnosis.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers inodes, filesystem metadata, and the `ENOSPC` semantics behind both failure modes in this lab.
- **Book:** *Systems Performance* — Brendan Gregg — general methodology for diagnosing "the resource that's actually exhausted isn't the obvious one," directly applicable here.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man8/mke2fs.8.html — documents `mkfs.ext4`'s inode-count/bytes-per-inode behavior and `tune2fs`'s reserved-blocks option.
- **Website/docs:** Arch Linux Wiki — https://wiki.archlinux.org — has precise, practical pages on ext4 inode sizing and filesystem troubleshooting.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — covers filesystem administration fundamentals including inode and block accounting.
