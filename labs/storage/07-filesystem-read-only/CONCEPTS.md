# Lab 7 — Concept: Why the Kernel Flips a Filesystem Read-Only on Its Own

## What's actually going on

ext4 has an explicit, configurable policy for what to do when it hits an
internal error it can't recover from cleanly — a failed write, a metadata
inconsistency detected mid-operation — stored directly in the
superblock and settable persistently with `tune2fs -e
{continue|remount-ro|panic}`, or overridden at mount time with the
`errors=` mount option. `continue` logs the error and tries to carry on
(risky — the filesystem may already be inconsistent); `remount-ro`
immediately, forcibly remounts the filesystem read-only, stopping any
further writes from potentially compounding whatever went wrong;
`panic` crashes the kernel outright, on the theory that continuing to
run at all next to a corrupted filesystem is unacceptable for some
workloads. `remount-ro` is the common, sensible default for general
-purpose systems, and it's important to internalize that this is
genuinely the **kernel** making this decision autonomously, the instant
it hits a write error, with no administrator action involved at all —
which is exactly why the incident is so disorienting the first time
someone hits it: nobody remembers "setting" the filesystem to read-only,
because nobody did.

The critical operational consequence is that `mount -o remount,rw`
changes only the filesystem's *mount flags* — it has zero effect on
whatever underlying condition caused the kernel to flip it read-only in
the first place. If the root cause was a transient, already-resolved
blip, remounting `rw` is a legitimate, sufficient fix. But if the root
cause is an underlying device that's still unreliable — a failing disk,
a flaky cable/controller, or (as this lab simulates) a `dm-flakey`
device still cycling through error windows — the very next write that
lands during another bad moment triggers the identical kernel response
again. Seeing "Remounting filesystem read-only" recur in `dmesg` after
you've already remounted `rw` once is unambiguous proof the underlying
problem was never addressed; a single successful remount is not evidence
of anything except that the device happened to be behaving at that exact
moment.

XFS does not implement the same three-way `errors=` switch as ext4.
Its response to persistent metadata I/O errors is governed by its own
internal retry-then-shutdown logic (tunable via sysfs knobs under
`/sys/fs/xfs/<dev>/error/`), and once XFS decides a filesystem is no
longer trustworthy, its typical response is a full filesystem shutdown —
a more severe, all-writes-and-often-all-reads-blocked state — rather than
a clean read-only remount. This means the "just remount rw" recovery
step that at least superficially seems to apply to an ext4
`remount-ro` event is not the equivalent move for a shut-down XFS
filesystem; XFS generally needs to be unmounted and run through
`xfs_repair` (see Lab 2) after any error-driven shutdown before it's
trustworthy again, and even ext4, once it's gone through a forced
read-only event, is worth running `e2fsck` against afterward (see Lab 3)
rather than assuming its journal alone fully accounted for whatever was
interrupted.

## Where this shows up in the real world

Any production host on spinning disks, SSDs, SAN-attached storage, or
even a cloud provider's virtualized block storage can hit a transient
storage-layer blip that trips this exact mechanism — and "the
application suddenly can't write, `df`/`mount` shows the filesystem is
`ro`" is one of the most common ways a storage hardware problem first
announces itself to an on-call engineer, well before any hardware-level
alerting (SMART, storage array health checks) necessarily fires. The
practical discipline this lab builds — check `dmesg` first to confirm
it's genuinely the kernel's error-response mechanism (not an admin
action or a misapplied config), remount `rw` only as a first cautious
probe rather than a confirmed fix, and watch for recurrence before
declaring victory — maps directly onto how real "why is the disk
suddenly read-only" incidents get correctly triaged.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/ext4.5.html
  and `tune2fs(8)` — canonical reference for the `errors=`
  continue/remount-ro/panic behavior.
- **Website/docs:** Linux kernel docs — https://docs.kernel.org/filesystems/ —
  ext4 and XFS official documentation, including error-handling behavior.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — filesystem error-handling and
  recovery administration guides.
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — mount
  semantics and filesystem error-handling background.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  covers filesystem administration including mount options and error
  handling.

**Confidence flag:** the exact XFS sysfs paths under
`/sys/fs/xfs/<dev>/error/` and the precise wording/behavior of an XFS
metadata-error-triggered shutdown (Challenge A) have not been verified
live — the general "XFS shuts down rather than cleanly remounting
read-only" behavior is believed correct, but exact dmesg wording and
sysfs tunable names should be confirmed against
`Documentation/admin-guide/xfs.rst` in the kernel source before
recording.
