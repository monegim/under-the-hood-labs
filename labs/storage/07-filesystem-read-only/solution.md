# Lab 7 — Solutions

## Challenge A — XFS reacts differently than ext4

**Check:**
```bash
dmesg -T | tail -20
mount | grep roxfs
```
Instead of a clean `EXT4-fs error ... Remounting filesystem read-only`
line, look for XFS-specific messages — something like "Metadata I/O
error" or "Corruption of in-memory data detected," possibly followed by
the filesystem being marked shut down rather than cleanly flipped to
`ro` the way ext4 did.

**Diagnosis:** ext4's `errors=`/`tune2fs -e` mechanism is a simple,
explicit three-way switch (continue / remount read-only / panic) baked
into the ext4 driver itself. XFS doesn't expose the same simple
mount-time switch — its response to repeated metadata I/O errors is
governed by its own internal retry/shutdown logic (configurable via
`/sys/fs/xfs/<dev>/error/metadata/*/max_retries` and related knobs), and
beyond a retry threshold it can shut the filesystem down outright rather
than performing a clean read-only remount. A "shutdown" XFS filesystem is
generally in a worse state to try to recover in place than a cleanly
remounted-read-only ext4 one — `mount -o remount,rw` is not the
equivalent recovery step.

**Fix:**
```bash
sudo umount /mnt/roxfs 2>/dev/null || true
sudo dmsetup remove rofs0-xfs
sudo xfs_repair "$LOOPDEV"
sudo dmsetup create rofs0-xfs --table "0 $SIZE flakey $LOOPDEV 0 999999 0"
sudo mount /dev/mapper/rofs0-xfs /mnt/roxfs
```
(Or, more realistically: replace the underlying flaky device entirely,
then `xfs_repair` the fresh filesystem before trusting it, same as this
lab's main ext4 fix.)

**Lesson:** don't assume every filesystem's self-protective behavior on
error looks like ext4's `errors=remount-ro`. XFS's response to the same
class of problem can be more severe (a full shutdown) and needs
`xfs_repair` plus addressing the underlying device — a plain
`remount,rw` is not a meaningful recovery step for a shut-down XFS
filesystem the way it at least superficially is for a remounted-read-
only ext4 one.

---

## Challenge B — repeated remount-ro events mean nothing is actually fixed

**Check:**
```bash
dmesg -T | grep -i "remount" | tail -10
```
More than one "Remounting filesystem read-only" timestamp appears,
spaced roughly 15–30 seconds apart — matching the `dm-flakey` down-window
interval exactly.

**Diagnosis:** `mount -o remount,rw` only changes the filesystem's
current mount flags — it does nothing whatsoever to the underlying block
device that caused the read-only flip in the first place. If that device
is still unreliable (still cycling through `dm-flakey`'s down windows in
this lab; a still-failing disk/controller/cable in real life), the very
next write that lands during another bad window triggers the exact same
kernel response again. Seeing the event repeat is direct proof the
"fix" only ever addressed the symptom.

**Fix:**
```bash
sudo umount /mnt/rodata 2>/dev/null || true
sudo dmsetup remove rofs0
```
followed by Step 6's replacement of the underlying device — there is no
filesystem-level command that fixes this, because the filesystem was
never the problem.

**Lesson:** a single successful `mount -o remount,rw` is not evidence of
a fix — it's only evidence that the device happened to be in a working
window at that exact moment. The only real confirmation is checking
whether the error condition recurs, and the only durable fix addresses
the storage layer the filesystem sits on, not the filesystem's mount
flags. This is the general shape of "the fix didn't stick" incidents:
always ask whether you addressed the root cause or just reset the
symptom back to its default state.
