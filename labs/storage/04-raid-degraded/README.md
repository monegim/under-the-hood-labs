# Lab 4 — RAID Degraded (and the Risk Window During a Rebuild)

## Objective
Build a small 3-member software RAID5 array with `mdadm` on loop devices,
fail a member, observe the array running degraded, replace the failed
member and rebuild, and learn exactly what "degraded" costs you: a live
window where losing one more disk means the array is gone.

## Why this matters
RAID5 tolerates exactly one failed member — no more. A degraded array is
still serving reads and writes normally, which is precisely what makes it
dangerous: everything *looks* fine from the application's point of view,
right up until a second failure during the rebuild window turns "one
disk needs replacing" into "the array is unrecoverable and you're
restoring from backup." Knowing how to read `mdadm --detail` and
`/proc/mdstat`, and understanding what a rebuild actually does (read
every remaining disk, reconstruct the missing one), is the difference
between calmly replacing a disk and getting blindsided.

## Prerequisites
- Linux VM, `sudo` access
- `mdadm`, `e2fsprogs` — installed by `setup.sh` if missing

Check first:
```bash
which mdadm mkfs.ext4
```

## Step 1 — Build the array
```bash
sudo bash setup.sh
```
This creates three 150M loop-device-backed members, assembles them into
a RAID5 array (`/dev/md0`), waits for the initial sync, formats it with
ext4, mounts it at `/mnt/raiddata`, and writes sample data.

## Step 2 — Confirm it's healthy
```bash
sudo mdadm --detail /dev/md0
cat /proc/mdstat
```
`State: clean`, all three members `active sync`.

## Step 3 — Fail a member
```bash
LOOP1=$(sed -n '2p' /var/lib/raidlab/loopdevs)
sudo mdadm /dev/md0 --fail "$LOOP1"
sudo mdadm --detail /dev/md0
```
The array is now `clean, degraded` — still readable and writable, but one
member down. Notice the failed device's state is `faulty`, and the array
tolerates this exactly once.

## Step 4 — Prove the array still works, degraded
```bash
echo "still here" | sudo tee /mnt/raiddata/proof.txt
cat /mnt/raiddata/proof.txt
```
Reads/writes succeed — RAID5 reconstructs the failed member's data
on-the-fly from parity + the remaining disks for every operation. This
costs performance but not correctness, as long as nothing else fails.

## Step 5 — Remove the failed member and replace it
```bash
sudo mdadm /dev/md0 --remove "$LOOP1"
sudo mdadm /dev/md0 --add "$LOOP1"
```
This starts a rebuild. Watch it:
```bash
watch cat /proc/mdstat
```
The `recovery` line shows a percentage climbing toward 100%. Until it
finishes, the array is *still* degraded — the new member starts out
empty and has to be reconstructed from the others, exactly like a real
replacement disk.

## Step 6 — Confirm it's back to fully healthy
```bash
sudo mdadm --detail /dev/md0
```
`State: clean` (not degraded), all three members `active sync` again.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a second failure during the rebuild window:**
```bash
sudo sh -c 'echo 200 > /proc/sys/dev/raid/speed_limit_max'
LOOP1=$(sed -n '2p' /var/lib/raidlab/loopdevs)
LOOP2=$(sed -n '3p' /var/lib/raidlab/loopdevs)
sudo mdadm /dev/md0 --fail "$LOOP1" --remove "$LOOP1"
sudo mdadm /dev/md0 --add "$LOOP1"
sleep 3
sudo mdadm /dev/md0 --fail "$LOOP2"
sudo mdadm --detail /dev/md0
cat /proc/mdstat
```
The rebuild was deliberately slowed down first so there'd be a real
window to catch it mid-recovery. Diagnose what state the array is in now
that a *second* member has failed while the first was still rebuilding,
what that means for the data, and whether there's an `mdadm` command that
gets you out of this.

**Challenge B — `--add` vs `--re-add`:**
```bash
sudo mdadm /dev/md0 --grow --bitmap=internal
LOOP1=$(sed -n '2p' /var/lib/raidlab/loopdevs)
sudo mdadm /dev/md0 --fail "$LOOP1" --remove "$LOOP1"
sleep 2
sudo mdadm /dev/md0 --re-add "$LOOP1"
cat /proc/mdstat
```
Compare how long this "rebuild" takes and what `/proc/mdstat` reports
versus Step 5's plain `--add`. Diagnose what the bitmap changed, why
`--re-add` specifically (not `--add`) was able to take advantage of it,
and when in real life you would and wouldn't be able to use `--re-add`
at all.

See `solution.md` only after you've formed your own diagnosis.
