# Lab 23 — Disk Shows 20% Full but Writes Fail

## Objective
Reproduce the classic "`df -h` says plenty of space free, but writes fail
with `ENOSPC`" gotcha, caused by inode exhaustion — and learn to check
`df -i` as a reflex, not an afterthought.

## Why this matters
"No space left on device" when `df -h` clearly shows free space is one of
the most confusing on-call pages there is, because everyone's first
instinct is to check bytes, not inodes. Any workload that creates lots of
tiny files — session stores, mail queues, cache directories, log-per-request
setups — can exhaust inodes long before it exhausts disk space. If you only
know to check `df -h`, you'll be stuck.

## Prerequisites
- Ubuntu VM, sudo access
- `losetup`, `mkfs.ext4` (part of `util-linux`/`e2fsprogs`, present by default)

Check first:
```bash
uname -a
which losetup mkfs.ext4 tune2fs
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 200M loopback-backed ext4 filesystem with only 2000 inodes
(`mkfs.ext4 -N 2000`), mounts it at `/mnt/appdata`, and fills it with empty
files (as `nobody`, simulating an app user) until it runs out of inodes.

## Step 2 — See the misleading signal
```bash
df -h /mnt/appdata
```
Notice how little space is "used" — most of the 200M is still free.

## Step 3 — Check the real signal
```bash
df -i /mnt/appdata
```
> Gotcha: `IUse%` is at (or near) 100% while `df -h`'s `Use%` is nowhere
> close. These are two completely independent resources on a filesystem —
> blocks and inodes — and you can run out of either one first.

## Step 4 — Prove it with a real write attempt
```bash
echo "hello" | sudo -u nobody tee /mnt/appdata/newfile.txt
```
This fails with `No space left on device` even though `df -h` says the
filesystem is nowhere near full.

## Step 5 — Confirm the exact number
```bash
sudo tune2fs -l $(cat /var/lib/inodelab/loopdev) | grep -E 'Inode count|Free inodes'
```
`Free inodes` is 0 (or very close to it).

## Step 6 — Fix it
The real fix is deleting files or provisioning a filesystem with a higher
inode count up front (`mkfs.ext4` picks an inode count based on expected
average file size — `-i <bytes-per-inode>` at format time, or `-N
<count>` directly). For this lab, free some inodes:
```bash
sudo -u nobody bash -c 'rm /mnt/appdata/file_1 /mnt/appdata/file_2 /mnt/appdata/file_3'
echo "hello" | sudo -u nobody tee /mnt/appdata/newfile.txt
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a specific leaking directory:**
```bash
sudo -u nobody mkdir -p /mnt/appdata/sessions
sudo -u nobody bash -c 'i=0; while touch /mnt/appdata/sessions/sess_$i 2>/dev/null; do i=$((i+1)); done'
```
Same symptom, different framing: imagine this is a web app's session-file
directory that never cleans up expired sessions. Diagnose it the same way —
what's the fastest way to prove it's this ONE directory causing the
exhaustion, without just guessing?

**Challenge B — reserved blocks, not inodes:**
```bash
sudo umount /mnt/appdata
LOOPDEV=$(cat /var/lib/inodelab/loopdev)
sudo mkfs.ext4 -q "$LOOPDEV"
sudo tune2fs -m 50 "$LOOPDEV"
sudo mount "$LOOPDEV" /mnt/appdata
sudo chmod 777 /mnt/appdata
sudo -u nobody dd if=/dev/zero of=/mnt/appdata/bigfile bs=1M count=150
```
This time `df -i` looks fine. The write still fails partway with `No space
left on device` while `df -h` shows free space left — but if you `sudo`
and retry the same write as root, it succeeds. What's actually reserved
here, and for whom?

See `SOLUTION.md` only after you've formed your own diagnosis.
