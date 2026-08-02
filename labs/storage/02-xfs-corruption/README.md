# Lab 2 — XFS Corruption

## Objective
Simulate on-disk XFS metadata corruption on a loop device, learn to read
the corruption messages XFS logs to `dmesg`, understand why XFS reacts to
corruption by refusing to trust itself (shutting down / refusing to
mount) rather than silently continuing, and recover with `xfs_repair`.

## Why this matters
XFS is built around the assumption that if its own metadata doesn't add
up, continuing to operate on it is more dangerous than stopping. That's
the right call, but it means "the filesystem just disappeared / went
read-only / won't mount" is itself often the *symptom* you're paged for,
and the actual root cause (some metadata block got corrupted, usually
from a storage-layer problem — bad disk, bad cable, a firmware bug, an
interrupted write) is one `dmesg` scroll away. Knowing to look there
first, and that `xfs_repair` categorically requires the filesystem to be
unmounted, turns a scary "the data is gone" moment into a normal repair.

## Prerequisites
- Linux VM, `sudo` access
- `xfsprogs` (`mkfs.xfs`, `xfs_repair`, `xfs_db`) — installed by
  `setup.sh` if missing

Check first:
```bash
which mkfs.xfs xfs_repair xfs_db
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 200M loop-device-backed XFS filesystem, mounts it at
`/mnt/xfsdata`, writes some sample "app data" files, unmounts it, then
deliberately corrupts a block well inside the filesystem's data/metadata
region using raw `dd` writes directly to the loop device.

## Step 2 — Try to use it again
```bash
sudo mount /dev/loop0 /mnt/xfsdata 2>&1 || true
```
(`setup.sh` prints the exact loop device it used — substitute it in for
`/dev/loop0` for every command in this lab.)

Depending on exactly what got corrupted, this either fails outright at
mount time, or appears to mount fine but then errors the moment something
touches the corrupted region:
```bash
sudo ls -laR /mnt/xfsdata >/dev/null
```

## Step 3 — Read the actual signal
```bash
dmesg -T | tail -40
```
Look for lines like `Metadata corruption detected`, `Corruption of
in-memory data detected`, or `Please umount the filesystem and rectify
the problem`. This is XFS telling you exactly what it found and exactly
what it wants you to do next — unmount, then repair.

## Step 4 — Confirm it's unmounted, then repair
```bash
sudo umount /mnt/xfsdata 2>/dev/null || true
sudo xfs_repair /dev/loop0
```
> Gotcha: `xfs_repair` will refuse outright ("filesystem is mounted...
> cannot proceed") if you try to run it against a mounted filesystem.
> Unlike `e2fsck -n` on ext4, there is no safe "just look, don't touch"
> mode you can run while mounted — always unmount first.

## Step 5 — Remount and verify
```bash
sudo mount /dev/loop0 /mnt/xfsdata
ls -la /mnt/xfsdata
```
`xfs_repair` fixes structural metadata problems; depending on exactly
what was corrupted, some files may be relocated into `lost+found` if
their own metadata was unrecoverable. That's expected — the repair's job
is filesystem consistency, not guaranteeing zero data loss on the exact
blocks that were physically overwritten.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — corrupted while mounted, only noticed later:**
```bash
sudo umount /mnt/xfsdata 2>/dev/null || true
LOOPDEV=$(cat /var/lib/xfslab/loopdev)
sudo mount "$LOOPDEV" /mnt/xfsdata
sudo dd if=/dev/urandom of="$LOOPDEV" bs=4096 seek=8000 count=8 conv=notrunc
sudo ls -laR /mnt/xfsdata >/dev/null
```
The `dd` here writes directly to the block device while the filesystem is
still mounted on top of it — modeling a real bad-sector/bad-controller
event that happens to a live, in-use disk, not a disk you conveniently
already had offline. Diagnose what you can and can't safely do to this
filesystem *while it's still mounted*, and what your very first command
needs to be before touching it with any repair tool.

**Challenge B — repair says the log needs clearing:**
```bash
sudo umount /mnt/xfsdata 2>/dev/null || true
LOOPDEV=$(cat /var/lib/xfslab/loopdev)
LOGSTART=$(sudo xfs_db -x -c "sb 0" -c "print" "$LOOPDEV" | awk '/^logstart/ {print $3}')
BLOCKSIZE=$(sudo xfs_db -x -c "sb 0" -c "print" "$LOOPDEV" | awk '/^blocksize/ {print $3}')
sudo dd if=/dev/urandom of="$LOOPDEV" bs="$BLOCKSIZE" seek="$LOGSTART" count=64 conv=notrunc
sudo xfs_repair "$LOOPDEV"
```
This time `xfs_repair`'s normal pass reports it can't recover cleanly and
tells you it needs `-L` to proceed. Diagnose what part of the filesystem
this corruption actually hit (hint: it's not the same region as the main
lab or Challenge A), why `xfs_repair` is refusing to just proceed on its
own, and what `-L` actually costs you that a normal repair doesn't.

See `solution.md` only after you've formed your own diagnosis.
