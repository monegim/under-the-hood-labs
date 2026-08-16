# Lab 9 — Disk Quota Exceeded (Filesystem Has Plenty of Free Space)

## Objective
Reproduce a user hitting their per-user disk quota on an ext4 filesystem
and getting "Disk quota exceeded" write errors, even though `df` shows
the filesystem itself is nowhere near full. Learn `quotacheck`,
`edquota`/`setquota`, and `repquota`/`quota -u` to diagnose and fix it —
and how to tell this apart from the two other "can't write, but it's not
really disk-full" incidents (a filesystem genuinely out of space, and a
filesystem out of inodes) covered elsewhere in this repo.

## Why this matters
Disk quotas let an admin cap how much space (and how many files) an
individual user or group can consume on a shared filesystem, completely
independent of how much space the filesystem actually has left. That's
the entire point of quotas — protecting a shared filesystem from any one
user filling it — but it means "no space left" style errors can come from
three genuinely different places: the filesystem is actually full
(`df`), the filesystem is out of inodes (also `df`, with `-i`), or *this*
user has hit a cap that has nothing to do with either — checked with
`quota`/`repquota`, not `df` at all. Debugging the wrong layer here
wastes time freeing filesystem space that was never the problem, or
telling a user to "just write less" for a global capacity issue that
quotas had nothing to do with.

## Prerequisites
- Linux VM, `sudo` access
- `quota` package (`quotacheck`, `quotaon`, `setquota`, `edquota`,
  `repquota`, `quota`) and `e2fsprogs`

Check first:
```bash
which quotacheck quotaon setquota edquota repquota quota mkfs.ext4
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 200M ext4 filesystem on a loop device, mounts it at
`/mnt/quotadata` with `usrquota,grpquota`, runs `quotacheck` and
`quotaon`, sets user `nobody`'s block quota to a 20M soft / 25M hard
limit, and has `nobody` write until the hard limit is hit.

## Step 2 — Confirm the filesystem itself has room
```bash
df -h /mnt/quotadata
```
`Use%` is nowhere near 100% — the 200M filesystem barely has anything on
it.

## Step 3 — Check the quota layer instead
```bash
sudo quota -u nobody
sudo repquota -a
```
`quota -u nobody` shows block usage at (or flagged past) the 25M hard
limit on `/mnt/quotadata`. `repquota -a` shows the same thing
filesystem-wide, for every user with a quota entry.

## Step 4 — Prove the write actually fails
```bash
echo "hello" | sudo -u nobody tee -a /mnt/quotadata/newfile.txt
```
Fails with `Disk quota exceeded` — a different error from `No space left
on device`, and worth knowing the difference on sight.

## Step 5 — Fix it: raise the quota (or free up the user's usage)
```bash
sudo setquota -u nobody 200000 250000 0 0 /mnt/quotadata
sudo quota -u nobody
echo "hello" | sudo -u nobody tee -a /mnt/quotadata/newfile.txt
```
`setquota` takes block limits in 1K blocks: soft limit, hard limit, then
inode soft limit, hard limit, then the filesystem. With `nobody`'s block
limits raised well above their current usage, the write succeeds.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — soft limit, grace period, and what "grace" actually means:**
```bash
sudo setquota -u nobody 10000 25000 0 0 /mnt/quotadata
sudo setquota -t 60 60 /mnt/quotadata
sudo -u nobody dd if=/dev/zero of=/mnt/quotadata/gracefile bs=1M count=15 status=none
sudo quota -u nobody
sleep 65
echo "more" | sudo -u nobody tee -a /mnt/quotadata/gracefile
```
The 15M write succeeds even though it's past the 10M soft limit — but
the one-line append after the 65-second sleep fails, despite total usage
still being nowhere near the 25M hard limit. Diagnose what changed in
those 65 seconds, and what "soft limit" actually means once its grace
period has expired.

**Challenge B — quota exceeded from file count, not size:**
```bash
sudo setquota -u nobody 200000 250000 100 120 /mnt/quotadata
for i in $(seq 1 150); do
    sudo -u nobody touch "/mnt/quotadata/tiny_$i" 2>&1 | tail -1
done
df -h /mnt/quotadata
sudo quota -u nobody
```
The loop starts failing partway through with `Disk quota exceeded`, even
though every file created is empty (0 bytes) and `df -h` barely moves.
Diagnose which of `nobody`'s two independent quota limits this is, and
why it's a different failure mode than both this lab's main scenario and
a filesystem that's globally out of inodes.

See `solution.md` only after you've formed your own diagnosis.
