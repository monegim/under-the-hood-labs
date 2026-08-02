# Lab 3 — ext4 Recovery: Bad Superblocks and Unclean Unmounts

## Objective
Break an ext4 filesystem's primary superblock, recover it from one of
the automatic backup copies every ext4 filesystem carries, and learn the
difference between `e2fsck -n` (diagnose only, no changes) and actually
fixing things — plus the difference between a merely *unclean* unmount
(usually self-healing) and genuine *corruption* (which isn't).

## Why this matters
A filesystem that suddenly won't mount because of "bad superblock" errors
looks like a disaster, but ext4 formats every filesystem with several
redundant backup copies of the superblock specifically for this
situation — most admins have never needed to use one and don't know
they're there. Separately, conflating "the box didn't shut down cleanly"
with "the filesystem is corrupted" leads to unnecessary panic: ext4's
journal is designed to replay automatically and silently fix the former
case on the very next mount, no `fsck` required.

## Prerequisites
- Linux VM, `sudo` access
- `e2fsprogs` (`mkfs.ext4`, `e2fsck`, `tune2fs`, `debugfs`) — present by
  default on most distros

Check first:
```bash
which mkfs.ext4 e2fsck tune2fs debugfs
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 200M loop-device-backed ext4 filesystem, records its
backup superblock locations (via `mke2fs -n`, a dry run that computes
layout without formatting), writes sample files, unmounts it, then
zeroes out the primary superblock directly with `dd`.

## Step 2 — See the backup superblock locations
```bash
cat /var/lib/ext4lab/backup_superblocks.txt
```
`mke2fs -n` prints something like:
```
Superblock backups stored on blocks:
	32768, 98304, 163840, 229376, 294912
```
These block numbers were computed and saved *before* anything went
wrong — this is the reference you'd want to have from day one, since a
filesystem with a destroyed primary superblock generally can't tell you
its own backup locations.

## Step 3 — Try to mount it
```bash
LOOPDEV=$(cat /var/lib/ext4lab/loopdev)
sudo mount "$LOOPDEV" /mnt/ext4data
```
Fails — `mount: wrong fs type, bad option, bad superblock...` (or
similar). The kernel can't even identify this as an ext4 filesystem
anymore; the primary superblock is where that information lives.

## Step 4 — Diagnose without changing anything
```bash
sudo e2fsck -n "$LOOPDEV"
```
`-n` means "answer no to every prompt" — a read-only, look-but-don't-touch
pass. It reports the bad superblock but makes zero changes to the disk.

## Step 5 — Recover from a backup superblock
```bash
sudo e2fsck -b 32768 "$LOOPDEV"
```
(Use the *first* number from Step 2's output — it may not literally be
`32768` depending on how the filesystem was sized.) This tells `e2fsck`
to reconstruct the primary superblock from a known-good backup copy, then
run its normal consistency check using the recovered information.

## Step 6 — Remount and verify
```bash
sudo mount "$LOOPDEV" /mnt/ext4data
ls -la /mnt/ext4data
```
The sample files from Step 1 are intact — only the primary superblock was
damaged; the backup copy has everything needed to rebuild it.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — unclean unmount, not corruption:**
```bash
sudo umount /mnt/ext4data 2>/dev/null || true
LOOPDEV=$(cat /var/lib/ext4lab/loopdev)
sudo debugfs -w -R "ssv state 0" "$LOOPDEV"
sudo mount "$LOOPDEV" /mnt/ext4data
dmesg -T | tail -20
ls -la /mnt/ext4data
```
This flips the filesystem's own record of "was I unmounted cleanly?" to
"no" — the same flag a real crash or power loss would leave behind — but
touches nothing else. Diagnose what actually happens on this mount
(check `dmesg`), whether any files are missing or damaged, and whether
you needed `e2fsck` at all to get here. What does that tell you about the
difference between an unclean shutdown and real corruption?

**Challenge B — `e2fsck -n` vs actually fixing it:**
```bash
sudo umount /mnt/ext4data 2>/dev/null || true
LOOPDEV=$(cat /var/lib/ext4lab/loopdev)
INODE=$(sudo debugfs -R "stat /app_data_1" "$LOOPDEV" 2>/dev/null | awk -F'[ :]+' '/Inode:/{print $2; exit}')
sudo debugfs -w -R "sif <$INODE> links_count 5" "$LOOPDEV"
sudo e2fsck -n "$LOOPDEV"
```
`e2fsck -n` reports a link-count inconsistency on that inode but the
filesystem still shows the same problem if you check again — nothing was
actually written. Diagnose what `-n` is (and isn't) doing here, then find
the actual fix and confirm it stuck.

See `solution.md` only after you've formed your own diagnosis.
