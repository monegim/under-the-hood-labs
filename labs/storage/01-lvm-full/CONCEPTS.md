# Lab 1 — Concept: LVM's Layers, and Why "Full" Means Different Things at Each One

## What's actually going on

LVM inserts three distinct layers of abstraction between physical disks
and the filesystem an application actually writes to: **physical volumes**
(PVs — a disk or partition initialized with `pvcreate`), **volume groups**
(VGs — a pool of storage formed by combining one or more PVs, tracked in
fixed-size chunks called extents), and **logical volumes** (LVs —
carved out of a VG's free extents, and it's an LV that finally gets a
filesystem put on it). Each layer has its own, completely independent
notion of "how much space is used," and each is inspected with a
different command: `pvs` for physical volumes, `vgs` for the pool of
extents a VG has available, `lvs` for how big each LV is and how it maps
into the VG, and `df` for how full the *filesystem* sitting on top of an
LV is. A filesystem reporting 100% full via `df -h` says nothing about
whether its LV has room in the VG to grow — that's a completely separate
question answered by `vgs`'s `VFree` column. This lab's core scenario (a
60M LV completely full inside a 500M VG) is exactly this: the resource
that's actually exhausted (the LV's fixed size) is one layer removed from
the resource everyone instinctively checks first (`df -h`'s block usage).

Growing an LV and growing the filesystem on it are two genuinely separate
operations, and this is the single most common LVM mistake in practice.
`lvextend -L +100M /dev/labvg/lvapp` only changes how many extents from
the VG are mapped into that LV — it operates purely at the block-device
level and has no awareness of, or interest in, what filesystem (if any)
sits on top. The filesystem itself has its own on-disk record of how many
blocks it thinks it owns, set at `mkfs` time, and that number does not
magically update just because the underlying block device got bigger.
Growing it is a second, filesystem-specific step: `resize2fs` for the
ext2/3/4 family, `xfs_growfs` for XFS. These two tools are also not
interchangeable and not even symmetric in how they're invoked —
`resize2fs` takes the block device path, `xfs_growfs` takes the *mount
point* and requires the filesystem to already be mounted (XFS has no
offline-resize path at all), and XFS can only ever grow, never shrink.
Running `resize2fs` against an XFS device fails immediately with a "bad
magic number" error, because `resize2fs` is reading for an ext-family
superblock signature it will never find on an XFS device.

Thin provisioning (Challenge A) adds one more twist to the same
"which layer is actually full" question. A thin pool is a chunk of real,
physically-backed VG space; thin LVs carved from it are given a *virtual*
size that can be, and routinely is, far larger than the pool's actual
backing capacity — that's the entire feature, an overcommit mechanism
identical in spirit to thin-provisioned cloud block storage. Blocks are
only actually allocated from the pool as data is written (allocate-on-
write), so a thin LV's filesystem can report gigabytes of nominal free
space while the pool behind it — checked with `lvs -a
-o+data_percent,metadata_percent`, not plain `lvs` — is at 100% real
utilization and has nothing left to hand out. The filesystem-level `df`
number in this case is not lying exactly, but it's answering "how big is
this volume," not "how much real storage backs it," and conflating those
two questions is precisely what makes thin-pool exhaustion such a
surprising failure mode the first time someone hits it.

## Where this shows up in the real world

Any host provisioned with LVM — which is most default partitioning
layouts on RHEL/CentOS/Ubuntu server installs, and effectively all
container-host and VM-image storage backends — can hit this. A common
real pattern: an application's data partition was sized conservatively at
provisioning time, the VG has spare capacity sitting unused on purpose
(reserved for exactly this situation), and the on-call fix is two
commands, not a disruptive resize of the underlying disk. Thin-pool
exhaustion is the sharper, scarier version of this in production —
Docker's `devicemapper` storage driver (deprecated but still found on
older hosts) and many enterprise SAN/VM storage layers use thin
provisioning by default, and a thin pool silently approaching 100% real
utilization while every individual volume reports plenty of "free" space
is a well-known way for an entire cluster of VMs or containers to start
failing writes simultaneously with very little advance warning unless
someone is actively monitoring pool-level (not volume-level) utilization.

## Go deeper

- **Book:** *Systems Performance* — Brendan Gregg — storage stack and file
  system chapters cover the layered nature of block I/O that LVM sits
  within.
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — filesystem
  and mount semantics chapters are useful background for how a filesystem's
  notion of size is independent of the block device beneath it.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — has thorough, authoritative
  LVM administration guides covering PV/VG/LV concepts, thin provisioning,
  and resizing.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — has precise,
  practical LVM pages covering `lvextend`/`resize2fs`/`xfs_growfs` usage.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — canonical
  reference for `lvm(8)`, `lvextend(8)`, and related tools.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — has
  dedicated LVM administration walkthroughs including thin provisioning.
