# Lab 10 — Concept: ZFS Pools, RAID-Z Redundancy, and End-to-End Checksums

## What's actually going on

ZFS collapses volume management, RAID, and the filesystem into a single
system with its own object model, but the health picture still boils
down to a small number of layers worth knowing by name. A **vdev**
(virtual device) is either a single disk, a mirror of disks, or a
`raidz`/`raidz2`/`raidz3` group (single, double, or triple parity,
conceptually similar to RAID5/6 but computed and checked at the
block level rather than the whole-stripe level); a **pool** is one or
more top-level vdevs combined, and it's the pool that datasets and
zvols are actually carved out of. `zpool status` is the single command
that reports health at every level of this: pool state
(`ONLINE`/`DEGRADED`/`FAULTED`), each vdev's state, and each individual
member disk's state, all in one tree-shaped output — there's no separate
`pvs`/`vgs`/`lvs`-style split the way LVM has, because ZFS was designed
as one system from the start rather than layered protocols bolted
together over time.

A `raidz1` vdev tolerates exactly one member failing without data loss,
the same guarantee as RAID5 — lose a second member before the first is
replaced and the vdev (and the whole pool, if it's the only vdev) is
gone. `zpool offline <device>` is how this lab simulates a failed drive:
it cleanly marks a member unavailable, exactly what taking a failing
drive out of service looks like from ZFS's point of view, and the pool
immediately reports `DEGRADED` — read/write service continues using
parity to reconstruct whatever the missing device would have provided,
at some performance cost, but with zero interruption. `zpool replace
<old> <new>` swaps in a new member and triggers a **resilver** — ZFS's
version of a RAID rebuild, reconstructing the replaced device's data
from the surviving members' data and parity. `zpool status` shows
resilver progress live, the same way `/proc/mdstat` shows an `mdadm`
rebuild's progress.

The feature that has no real equivalent in ext4/XFS/mdadm/LVM is that
ZFS checksums every block of data *and* metadata by default, independent
of whether the pool has any redundancy at all. This means ZFS can detect
a block that was returned successfully by the underlying device but
whose contents don't match its recorded checksum — silent corruption,
sometimes called bit rot, that a device reports no I/O error for at all,
because as far as the device's firmware is concerned the read
"succeeded." On a pool with redundancy (a mirror or any `raidz` level),
detecting a checksum mismatch triggers automatic self-healing: ZFS
reconstructs the correct data from a healthy copy or from parity and
rewrites it over the bad copy, all as a side effect of the read (or of a
`zpool scrub`, which proactively reads and verifies every block in the
pool rather than waiting for something to read it naturally).
Self-healing is a property of *redundancy plus checksums together* — a
single-device ZFS pool still detects corruption via checksum mismatch (a
capability plain ext4/XFS simply don't have), but has no second copy or
parity to reconstruct from, so detection there means a confirmed,
noticed data loss rather than a silent one. `zpool scrub` is the
operational habit this all points to: run it on a schedule, not just
reactively after a device fails, since corruption can sit undetected in
cold data for a long time otherwise.

## Where this shows up in the real world

ZFS (and its Solaris/illumos and now widely-used OpenZFS/FreeBSD/Linux
descendants) is a standard choice anywhere data integrity matters more
than raw simplicity: NAS appliances (TrueNAS/FreeNAS), backup targets,
and database/VM storage backends where silent corruption over years of
operation is a real, documented risk on any storage medium, not a
theoretical one. The self-healing behavior demonstrated in Challenge A is
frequently cited as ZFS's headline feature over a traditional
mdadm+ext4/XFS stack precisely because mdadm and ext4/XFS have no way to
know a "successful" read returned wrong bytes — they can only react to
I/O errors the device itself reports, which silent corruption never
produces. `zpool scrub` run on a regular cron schedule (commonly weekly
or monthly) is standard operational practice on any production ZFS pool
for exactly this reason — it's the only mechanism that surfaces
corruption sitting in data nobody has read recently.

## Go deeper

- **Website/docs:** OpenZFS docs — https://openzfs.github.io/openzfs-docs/
  — the official, authoritative reference for `zpool`/`zfs` commands,
  `raidz` design, scrub behavior, and self-healing.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ —
  reference for `zpool(8)` and `zfs(8)` as packaged for Linux.
- **Book:** *Systems Performance* — Brendan Gregg — file system and disk
  I/O chapters cover checksumming filesystems and their performance
  tradeoffs relative to non-checksumming ones.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — has a
  precise, practical ZFS page covering pool creation, `raidz`, scrubbing,
  and device replacement.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  has dedicated ZFS administration and `raidz`/mirror walkthroughs.

**Confidence flag:** the exact `zpool remove` error message text for
attempting to remove a `raidz` member, and the precise `zpool status -v`
output format for reporting `CKSUM` errors and affected file paths, are
written from documented OpenZFS behavior but have **not** been tested
live against a real pool on this environment. The underlying
constraints — `raidz` vdevs not supporting member removal, and
checksum-driven self-healing on redundant pools — are core, well-documented
OpenZFS design properties and are high-confidence; DKMS module build
success is the single most likely point of failure for actually running
this lab, flagged explicitly in the README's Prerequisites.
