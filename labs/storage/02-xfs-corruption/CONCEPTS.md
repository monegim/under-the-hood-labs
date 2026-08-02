# Lab 2 — Concept: Why XFS Shuts Down Instead of Limping On, and What `xfs_repair` Actually Does

## What's actually going on

Modern XFS (the default "v5" on-disk format used by `mkfs.xfs` for years
now) stamps CRC32C checksums on essentially every metadata structure it
writes — inodes, directory blocks, allocation group headers, B-tree
nodes. Every time the kernel reads one of these structures back off disk,
it recomputes the checksum and compares. If it doesn't match, XFS treats
this as proof that something is now inconsistent with what it wrote, and
its designed response is to stop trusting that structure immediately —
logging a corruption message to `dmesg` and, depending on what was hit,
either refusing the operation, shutting the filesystem down, or (if the
damage is severe enough) refusing to mount at all. This is a deliberate
design philosophy, not a bug or overreaction: continuing to operate on
metadata that's already been proven internally inconsistent risks
cascading the damage into structures that were still fine, which is
strictly worse than stopping cleanly right where the first problem was
detected. The corollary is that "the filesystem disappeared" or "won't
mount" is very often the *symptom*, not the root cause — the actual root
cause is almost always something upstream: a real bad sector, a flaky
cable or controller, an interrupted write, or (as this lab demonstrates
for teaching purposes) a directly corrupted block.

`xfs_repair` is XFS's offline consistency checker and fixer, and its most
important operational rule is that it requires the filesystem to be
**completely unmounted** — it will flatly refuse to run against a mounted
device. This is different from ext4's `e2fsck`, which at least offers a
read-only `-n` inspection mode that's *relatively* safe to point at a
mounted filesystem (though still not recommended for anything beyond
looking). XFS offers no equivalent; the tool assumes exclusive, offline
access to the block device from the very first step. `xfs_repair`'s
normal pass works by walking every metadata structure using its own
independent logic (not blindly trusting the structures it's checking),
rebuilding anything inconsistent, and — critically — starts by trying to
replay the filesystem's internal **log** (the XFS equivalent of a
journal) to recover any transactions that were in flight at the moment
of an unclean shutdown or corruption event. If the log itself turns out
to be unreadable or inconsistent, `xfs_repair` does not guess at what
might have been in it; it stops and requires the operator to explicitly
pass `-L` to acknowledge zeroing the log and proceeding without that
recovery — a genuinely destructive step, since anything that was only
recorded in the unreplayed log and nowhere else on disk yet is gone once
you do this.

Where in the filesystem the corruption lands changes what you observe,
which is exactly what this lab's two challenges are built to show.
Corruption hitting ordinary data or non-critical metadata typically
surfaces lazily — nothing happens until something actually reads the
affected block, which can be much later than when the corruption
occurred and can look like an unrelated operation suddenly failing
(Challenge A). Corruption hitting the log specifically is more severe,
because the log is exactly the mechanism XFS relies on to recover from an
unclean state in the first place — if that mechanism itself is broken,
there's no safety net left to fall back on, which is why `xfs_repair`
refuses to proceed silently and instead demands the explicit, clearly
destructive `-L` acknowledgment (Challenge B).

## Where this shows up in the real world

XFS is the default filesystem on RHEL/CentOS/Rocky/Alma and is heavily
used under large data stores and databases precisely because of its
scalability and this same checksum-everything design. In production,
"XFS metadata corruption" pages usually trace back to a real hardware
event — a failing disk, a RAID controller with a battery-backed cache
that lost power mid-write, a SAN path flapping — rather than anything
XFS itself did wrong. The practical skill this lab builds is exactly the
sequence a real incident demands: check `dmesg` first (it will tell you
almost exactly what structure was affected and what it wants you to do),
confirm the filesystem is unmounted before touching it with any repair
tool, and treat `-L` as a deliberate, costly decision rather than a flag
you pass because the first attempt "didn't work."

## Go deeper

- **Website/docs:** Linux kernel docs — https://docs.kernel.org/filesystems/ —
  official XFS filesystem documentation, including on-disk format and
  metadata checksumming.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — canonical
  reference for `xfs_repair(8)` and `xfs_db(8)` flags and behavior.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — authoritative XFS
  administration and repair guides.
- **Book:** *Systems Performance* — Brendan Gregg — file system internals
  chapters cover the general principles behind journaling/logging
  filesystems and corruption recovery.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  covers filesystem administration including XFS basics.

**Confidence flag:** the exact `xfs_db -x -c "sb 0" -c "print"` field
names (`logstart`, `blocksize`) used in Challenge B, and whether
`xfs_repair` reliably asks for `-L` from corrupting that exact region,
have not been verified on a live system — dry-run this lab before
recording and adjust if the field names or repair output differ.
