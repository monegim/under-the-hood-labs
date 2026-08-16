# Lab 8 — LVM Snapshot Full (Invalid Snapshot)

## Objective
Reproduce an LVM copy-on-write (COW) snapshot running out of its
allocated space and flipping to `Invalid` — unusable for rollback, even
though the origin volume it was taken from is completely fine. Learn to
read `lvs -o+snap_percent` to watch a snapshot's COW space fill up, why
undersized snapshots are one of the most common backup-strategy mistakes
in LVM-based environments, and how to size and monitor them so this
doesn't happen silently.

## Why this matters
An LVM snapshot is not a full copy of a volume — it's a small, separate
LV that only stores the *original* contents of blocks the origin has
since overwritten (copy-on-write). That makes snapshots cheap and fast to
create, but it also means a snapshot has a fixed capacity of its own,
sized independently from the origin, and every write to the origin after
the snapshot was taken consumes a little of that capacity. If the origin
churns more than the snapshot was sized to absorb, the snapshot's COW
space fills completely and LVM marks it `Invalid` — it can no longer be
used to roll the origin back, and in most cases can no longer be mounted
at all. This is a very common real incident: someone takes a snapshot
before a risky change "just in case," sizes it small because disk is
tight, and finds out days later — when they actually need to roll
back — that the snapshot silently died from being too small.

## Prerequisites
- Linux VM, `sudo` access
- `lvm2` (`pvcreate`, `vgcreate`, `lvcreate`, `lvextend`, `lvconvert`) and
  `e2fsprogs`

Check first:
```bash
which pvcreate vgcreate lvcreate lvextend lvconvert lvs mkfs.ext4
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 400M volume group (`snapvg`) on a loop device, a 200M
ext4 origin LV (`origin`) mounted at `/mnt/snaporigin` with sample data,
then takes a deliberately small 20M COW snapshot (`snap1`) and churns the
origin with more writes than the snapshot can absorb — invalidating it
before you even start.

## Step 2 — Confirm the snapshot is invalid
```bash
sudo lvs -a -o+snap_percent,lv_attr snapvg
```
`lvs` prints a `WARNING: Invalid snapshot(s) found.` banner, and `snap1`
shows `Snap%` pinned near 100 with an `I` (invalid) in its attribute
state field.

## Step 3 — Confirm the origin itself is unaffected
```bash
df -h /mnt/snaporigin
cat /mnt/snaporigin/baseline_1 > /dev/null && echo "origin reads fine"
```
The live origin volume is completely healthy — it was never at risk.
Only the *rollback capability* the snapshot provided is gone.

## Step 4 — Try to use the dead snapshot
```bash
sudo mkdir -p /mnt/snap1
sudo mount /dev/snapvg/snap1 /mnt/snap1 2>&1 || true
```
This fails (or errors immediately on read) — once invalid, a COW
snapshot's data is gone and unrecoverable. There is no fix for `snap1`
itself.

## Step 5 — Clean up the dead snapshot and take a properly sized one
```bash
sudo lvremove -f /dev/snapvg/snap1
sudo lvcreate -s -L 150M -n snap2 /dev/snapvg/origin
sudo lvs -a -o+snap_percent snapvg
```
`snap2` is sized against actual expected churn instead of "whatever disk
was easy to spare" — the real fix for this class of incident is sizing
and monitoring, not a command you run after the fact.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — catching it before it dies:**
```bash
sudo lvcreate -s -L 20M -n snap3 /dev/snapvg/origin
for i in $(seq 1 6); do
    sudo -u nobody dd if=/dev/urandom of=/mnt/snaporigin/churn_$i bs=1M count=2 status=none
    sudo lvs -o+snap_percent snapvg | grep snap3
    sleep 1
done
```
Watch `Snap%` climb across each iteration. Before it reaches 100%,
diagnose what command would grow `snap3`'s allocated COW space in place,
and confirm it survives more churn afterward without going `Invalid`.

**Challenge B — merge that doesn't seem to happen:**
```bash
sudo -u nobody dd if=/dev/urandom of=/mnt/snaporigin/post_snapshot_change bs=1M count=2 status=none
sudo lvconvert --merge /dev/snapvg/snap3
sudo lvs snapvg
```
LVM reports the merge is delayed rather than doing it immediately, even
though `snap3` is a perfectly valid snapshot. Diagnose why a merge you
just requested doesn't actually happen yet, what state has to change for
it to proceed, and confirm the origin's data reflects the rollback once
it does.

See `solution.md` only after you've formed your own diagnosis.
