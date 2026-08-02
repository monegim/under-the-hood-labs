# Lab 11 — Solutions

## Challenge A — leaking sessions directory

**Check:**
```bash
df -i /mnt/appdata
find /mnt/appdata -maxdepth 1 -type d -exec sh -c 'echo -n "{}: "; find "{}" | wc -l' \;
```
`df -i` confirms inode exhaustion again. The `find | wc -l` loop shows the
`sessions/` directory holding almost the entire inode count on its own,
versus everything else being small.

**Diagnosis:** same root problem as the main lab (inode exhaustion), but in
a real incident you rarely start knowing which directory is the culprit —
you have to go find it. Counting files per top-level directory is the fast
way to localize it before you start deleting things.

**Fix:**
```bash
sudo -u nobody find /mnt/appdata/sessions -type f -delete
```

**Lesson:** when `df -i` says a filesystem is inode-exhausted, don't start
deleting from the root of the mount — count entries per subdirectory first
to find the actual leak, so you don't waste time (or accidentally delete
the wrong thing) guessing.

---

## Challenge B — reserved blocks for root

**Check:**
```bash
df -h /mnt/appdata
df -i /mnt/appdata
sudo tune2fs -l $(cat /var/lib/inodelab/loopdev) | grep -i "reserved block"
```
`df -i` is fine (plenty of inodes free). `df -h` shows real free space
too — `df` by default reports space available to the *calling user*, and
for a non-root user that number already excludes the reserved chunk. The
write still fails before finishing because the actual usable-by-`nobody`
space is smaller than 150M.

**Diagnosis:** `tune2fs -m 50` reserves 50% of the filesystem's blocks for
root only. This is normally a safety margin (default is 5%) so that
non-root processes filling a disk can't completely starve root — root can
always log in, write logs, and clean up. Here it's been cranked up to 50%
on purpose, so a regular user hits `ENOSPC` well before the disk is
actually full from an absolute point of view.

**Fix:** either lower the reservation, or run the write as the account
that's supposed to have access to that margin:
```bash
sudo tune2fs -m 5 $(cat /var/lib/inodelab/loopdev)
sudo -u nobody dd if=/dev/zero of=/mnt/appdata/bigfile bs=1M count=150
```

**Lesson:** "disk full" for a non-root process can mean the filesystem's
reserved-blocks margin (`tune2fs -m`), not the disk being physically full —
check `tune2fs -l | grep -i reserved` and compare `df -h`'s free space as
root vs. as the affected user before concluding the disk itself is out of
room.
