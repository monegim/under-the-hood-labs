# Lab 8 — Concept: Copy-on-Write Snapshots, and Why Undersized Ones Die Silently

## What's actually going on

An LVM snapshot is not a copy of a volume — copying the whole thing would
defeat the point of a snapshot being fast and cheap to create. Instead,
when you run `lvcreate -s -L 20M -n snap1 /dev/vg/origin`, LVM creates a
small, separate logical volume (the "COW device") and a kernel
`dm-snapshot` mapping that intercepts writes to the origin. The first
time *after the snapshot was taken* that the origin is about to overwrite
a block, `dm-snapshot` first copies that block's *original* contents into
the COW device, then lets the write to the origin proceed — copy-on-write.
Reading the snapshot itself means reading through this mapping: for any
block the origin hasn't touched since the snapshot, you're reading the
origin directly; for any block that has changed, you're reading the
preserved original copy sitting in the COW device. This is what makes a
snapshot represent a specific point in time using only a fraction of the
origin's total size — you only pay for the blocks that actually change.

The critical consequence is that a snapshot's capacity is fixed at
creation time (`-L 20M` in this lab) and is entirely independent of the
origin's size or how much data is "logically" in the snapshot. Every
block the origin overwrites after the snapshot was taken consumes a
little more of that fixed COW space — regardless of whether the new data
is bigger or smaller than the old, the fact that the block changed is
what costs space. `lvs -o+snap_percent` shows exactly how much of that
COW space has been used, and it is a monotonically increasing number for
the life of the snapshot — it never goes back down on its own. Once it
hits 100%, the kernel's `dm-snapshot` target has nowhere left to preserve
the next original block that's about to be overwritten, and it marks the
whole snapshot `Invalid`. An invalid snapshot isn't "missing some
recent changes" — it's unconditionally unusable for rollback from that
point forward, because the target can no longer guarantee it's showing
you a coherent point-in-time view.

This is precisely why the origin volume is never at risk from a full
snapshot: the origin is always written to directly, and the COW device is
purely a side record of what the origin used to look like. A `snap1`
going `Invalid` is bad news only for anyone who was counting on it as a
rollback point or backup source — it has zero effect on the live data
sitting on the origin. That asymmetry is also what makes undersized
snapshots such a deceptively easy mistake: nothing about the origin looks
different, no application error occurs, and the failure is completely
silent unless someone happens to check `lvs -o+snap_percent` (or a merge
is actually attempted later and fails). `lvconvert --merge`, separately,
folds a *valid* snapshot's COW data back into the origin to perform an
actual rollback — but it refuses to do this while the origin LV is open
(mounted), deferring the merge until the origin is next deactivated and
reactivated, because rewriting blocks out from under a live, mounted
filesystem is not something LVM will do unsafely.

## Where this shows up in the real world

Pre-change snapshots are one of the most common LVM patterns in
production: take a snapshot immediately before a risky database
migration, package upgrade, or config change, keep it around as a
rollback option, and drop it once the change is confirmed good. The
recurring real-world mistake is sizing that snapshot based on "how much
free space is comfortably lying around" rather than "how much will this
origin actually churn before I'm done with the snapshot" — a database
under active write load, or a change that involves rewriting large files,
can burn through a 5-10% COW allocation far faster than intuition
suggests, especially if the snapshot needs to survive hours rather than
minutes. Backup tools and hypervisor-level snapshot mechanisms (traditional
Xen/KVM host backup scripts built on LVM snapshots, for instance) hit this
constantly, which is why production runbooks that use LVM snapshots
almost always pair them with active `snap_percent` monitoring and
alerting, not a fire-and-forget `lvcreate`.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — background
  on block device and filesystem semantics that underpin how a mapped
  device like a snapshot presents itself to userspace.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — has detailed LVM snapshot
  administration guides covering sizing, monitoring, and merging.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — practical LVM
  pages covering snapshot creation, `lvextend`, and `lvconvert --merge`.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — canonical
  reference for `lvm(8)`, `lvcreate(8)`, and `lvconvert(8)`.
- **Website/docs:** Linux kernel docs —
  https://docs.kernel.org/admin-guide/device-mapper/ — the `dm-snapshot`
  target documentation describing the copy-on-write mechanism at the
  device-mapper level.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — LVM
  administration content including snapshot creation and management.

**Confidence flag:** the exact `lvs` attribute-field character shown for
an invalid snapshot (`I` in the state position of `lv_attr`) and the
precise wording of the `Delaying merge since origin is open.` message are
written from memory of documented LVM behavior and have **not** been
tested live against a real `lvs`/`lvconvert` invocation. The underlying
mechanism described — COW space exhaustion invalidating a snapshot, and
merges being deferred while the origin is open — is well documented and
high-confidence; the exact console strings should be verified against a
real run before being treated as gospel in a script that greps for them.
