# Lab 11 — Btrfs Checksum Corruption (Single Device, No Redundancy)

## Objective
Build a small btrfs filesystem on a loop device, corrupt raw bytes
underneath it directly (bypassing btrfs entirely, the way real media
corruption would), and see btrfs's checksums actually catch it — loudly,
unlike ext4/XFS, which have no way to notice at all. Learn `btrfs scrub`
and `btrfs check`, and the difference between btrfs *detecting*
corruption (which it can always do, even alone) and btrfs *healing* it
(which needs redundancy this single-device setup deliberately doesn't
have).

## Honesty check, up front
This lab's filesystem is **one device, no RAID/mirroring** — on
purpose. Btrfs checksums every block of data and metadata by default
regardless of how many devices are in the filesystem, so corruption
detection works here exactly like it would in production. But
*self-healing* (transparently reconstructing corrupted data from a
second copy) only works when a second copy exists — a redundant
`raid1`/`dup`-profile setup across multiple devices, which this lab does
not build. Corrupted **data** in this lab is genuinely, permanently gone
once corrupted — that's not a limitation of the lab, that's the actual
lesson: checksums without redundancy give you an honest, loud failure
instead of a silent one, but they don't give you your data back.

## Prerequisites
- Linux VM, `sudo` access
- `btrfs-progs` (`mkfs.btrfs`, `btrfs`) — installed by `setup.sh` if
  missing

Check first:
```bash
which mkfs.btrfs btrfs
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 300M loop-device-backed image, formats it with btrfs
(explicitly `-d single -m dup` — single copy of data, duplicated
metadata, which is worth noting up front and comes back in Challenge A),
writes ~150M of sample data, keeps an untouched backup copy of that data
outside the loop device, then unmounts and corrupts a broad byte range
directly on the underlying loop device — well inside the region that
data actually landed on, sparing the superblock so the filesystem still
mounts.

## Step 2 — Confirm it still mounts
```bash
LOOPDEV=$(cat /var/lib/btrfslab/loopdev)
sudo mount "$LOOPDEV" /mnt/btrfsdata
```
It mounts cleanly — corruption inside data/metadata blocks doesn't
necessarily prevent mounting the way superblock corruption would (Lab 2
covers that case for XFS).

## Step 3 — Find out what's actually broken
```bash
for f in /mnt/btrfsdata/baseline_*; do
    echo "== $f =="
    sudo cat "$f" > /dev/null
done
dmesg -T | tail -40
```
Some files read back fine; others fail with `Input/output error`.
`dmesg` shows btrfs `checksum verify failed` (`csum failed`) messages
naming the affected files/blocks — this is btrfs actively refusing to
silently hand you corrupted bytes.

## Step 4 — Scrub for a full picture
```bash
sudo btrfs scrub start -B /mnt/btrfsdata
sudo btrfs scrub status /mnt/btrfsdata
```
`-B` runs the scrub in the foreground so it blocks until done.
`btrfs scrub status` reports counts of read errors, checksum errors,
*corrected* errors, and *uncorrectable* errors — read that distinction
carefully, it's the whole point of this lab.

## Step 5 — Check filesystem structure (unmounted)
```bash
sudo umount /mnt/btrfsdata
sudo btrfs check "$LOOPDEV"
```
`btrfs check` is a read-only diagnostic here (no `--repair` yet — see
Challenge B for why that flag deserves real caution). It reports any
structural/tree-level problems it finds.

## Step 6 — Fix it: recreate the filesystem and restore from backup
```bash
sudo mkfs.btrfs -f -d single -m dup "$LOOPDEV"
sudo mount "$LOOPDEV" /mnt/btrfsdata
sudo chmod 777 /mnt/btrfsdata
sudo cp -a /var/lib/btrfslab/backup/. /mnt/btrfsdata/
sudo -u nobody sha256sum /mnt/btrfsdata/baseline_1
```
There is no in-place repair for corrupted **data** on a single-device
btrfs filesystem — the real fix is the same one that applies to any
storage medium with corrupted data and no redundancy: restore from a
backup taken before the corruption happened.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — some errors say "corrected," some say "uncorrectable":**
```bash
sudo btrfs scrub status -d /mnt/btrfsdata
```
(Run this against the filesystem state from before Step 6's rebuild —
re-run `setup.sh` first if you already fixed it.) The scrub report
distinguishes errors it fixed from errors it couldn't. Diagnose why some
checksum failures were silently corrected while others, on the exact
same single-device filesystem this lab set up as having "no redundancy,"
were not — and what `-d single -m dup` from Step 1 has to do with it.

**Challenge B — the repair tool you'd reach for out of habit:**
```bash
sudo umount /mnt/btrfsdata 2>/dev/null || true
sudo btrfs check "$LOOPDEV"
```
After Lab 2's `xfs_repair` and Lab 3's `e2fsck`, the instinct here is to
reach for `btrfs check --repair`. Read `btrfs check --help` and the
warnings it prints before you do. Diagnose why btrfs's own documentation
treats `--repair` as fundamentally different in risk profile from
`xfs_repair`/`e2fsck -y`, and decide — with reasoning, not a guess —
whether running it against this lab's already-corrupted filesystem is
actually a good idea.

See `solution.md` only after you've formed your own diagnosis.
