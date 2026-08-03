# Lab 7 — The Filesystem Flipped Itself Read-Only

## Objective
Trigger a real ext4 auto-remount-to-read-only event using a simulated
storage error, learn that this is the **kernel** deciding your filesystem
isn't safe to write to anymore (not an admin, not a config mistake), and
learn why `mount -o remount,rw` alone — without fixing the actual
underlying problem — will very often just flip back.

## Why this matters
"The app suddenly can't write anything, mount shows `ro`" is a
disorienting page, because nobody remembers setting the filesystem
read-only. Nobody did — the kernel did, on purpose, as a data-safety
measure the moment it hit a write error it didn't trust itself to
recover from cleanly. Understanding this reframes the incident
correctly: the read-only flip is a symptom, and the underlying storage
problem is the actual root cause. Remounting `rw` without addressing that
root cause doesn't fix anything — it just gives the kernel a fresh chance
to flip back the next time it hits the same error.

## Prerequisites
- Linux VM, `sudo` access
- `dmsetup`, `e2fsprogs`, `xfsprogs` — installed by `setup.sh` if missing

Check first:
```bash
which dmsetup mkfs.ext4 mkfs.xfs
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a loop-device-backed `dm-flakey` device (up for 15s, erroring
for 15s), formats it ext4 with `tune2fs -e remount-ro` (explicitly setting
the filesystem's own error-behavior policy — don't rely on the distro
default), mounts it at `/mnt/rodata`, writes some initial data, and starts
a writer loop.

## Step 2 — Watch it happen
```bash
tail -f /var/log/rolab/writer.log
```
Writes succeed, then during a "down" window a write fails, and shortly
after:
```bash
mount | grep rodata
```
shows `ro` where it previously showed `rw` — nobody ran a remount
command. The kernel did this on its own.

## Step 3 — Confirm it was the kernel's decision
```bash
dmesg -T | tail -20
```
Look for `EXT4-fs error ... Remounting filesystem read-only`. This line
is the entire story: an I/O error occurred, the filesystem's configured
error policy is `remount-ro` (set explicitly in Step 1), so the kernel
remounted it read-only to stop any further writes from potentially making
things worse.

## Step 4 — Try the naive fix
```bash
sudo mount -o remount,rw /mnt/rodata
mount | grep rodata
```
This might appear to succeed immediately... or fail outright, depending
on whether the underlying `dm-flakey` device happens to be in an "up" or
"down" window right now.

## Step 5 — Watch it flip back
```bash
echo "test" | sudo tee /mnt/rodata/probe.txt
sleep 20
echo "test2" | sudo tee /mnt/rodata/probe2.txt
dmesg -T | tail -10
mount | grep rodata
```
Sooner or later (whenever the next "down" window hits), the same thing
happens again — the underlying device is still unreliable, so remounting
`rw` bought you nothing durable.

## Step 6 — Fix it properly: address the underlying device first
```bash
sudo umount /mnt/rodata 2>/dev/null || true
sudo dmsetup remove rofs0
sudo bash -c 'dd if=/dev/zero of=/var/lib/rolab/disk_replacement.img bs=1M count=200 status=none'
NEWLOOP=$(sudo losetup --find --show /var/lib/rolab/disk_replacement.img)
sudo mkfs.ext4 -q "$NEWLOOP"
sudo e2fsck -fy "$NEWLOOP"
sudo mount "$NEWLOOP" /mnt/rodata
```
Only *after* the unreliable device is gone does remounting stay stable —
and running `e2fsck` first (rather than assuming it's fine) accounts for
whatever writes were interrupted mid-transaction by the errors.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — same mechanism, but on XFS:**
```bash
sudo umount /mnt/rodata 2>/dev/null || true
sudo dmsetup remove rofs0 2>/dev/null || true
LOOPDEV=$(cat /var/lib/rolab/loopdev)
SIZE=$(sudo blockdev --getsz "$LOOPDEV")
sudo dmsetup create rofs0-xfs --table "0 $SIZE flakey $LOOPDEV 0 15 15"
sudo mkfs.xfs -q /dev/mapper/rofs0-xfs
sudo mkdir -p /mnt/roxfs
sudo mount /dev/mapper/rofs0-xfs /mnt/roxfs
while true; do echo x | sudo tee /mnt/roxfs/probe.txt >/dev/null 2>&1; sleep 1; done &
sleep 20
dmesg -T | tail -20
mount | grep roxfs
```
Diagnose whether XFS reacts to the same kind of error the same way ext4
did — does `mount -o remount,rw` even apply here the same way, and what
does XFS actually want you to do instead?

**Challenge B — "fixed" but still flapping:**
```bash
sudo mount -o remount,rw /mnt/rodata 2>&1 || true
echo probe1 | sudo tee /mnt/rodata/p1.txt >/dev/null 2>&1
sleep 16
echo probe2 | sudo tee /mnt/rodata/p2.txt >/dev/null 2>&1
dmesg -T | grep -i "remount" | tail -10
```
Count how many separate "Remounting filesystem read-only" events show up
in that `dmesg` output. Diagnose what that repetition — not just its
presence — tells you about whether this is actually fixed, and what you
should check about the underlying device before declaring victory.

See `solution.md` only after you've formed your own diagnosis.
