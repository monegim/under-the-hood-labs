# Lab 1 — LVM Full (But the Volume Group Has Room)

## Objective
Reproduce the "the filesystem is full, but the volume group clearly has
free space" incident, and learn to check `df`, `lvs`, `vgs`, and `pvs` —
four different layers that can each independently be "full" — plus fix it
correctly with the two-step `lvextend` + `resize2fs`/`xfs_growfs`
process people forget the second half of.

## Why this matters
LVM adds a layer of indirection between physical disks and the filesystem
you actually write to: PVs (physical volumes) group into a VG (volume
group), and a VG is carved into LVs (logical volumes), each of which is
formatted with a filesystem. "No space left on device" tells you the
*filesystem* is full. It says nothing about whether the *LV* has room to
grow, or whether the *VG* has free extents to grow the LV into. All three
are checked with different commands, and a huge number of "disk full"
pages on LVM-backed hosts are resolved in seconds once someone actually
runs `vgs` instead of just staring at `df -h` in confusion. On top of
that, growing an LV does **not** grow the filesystem sitting on it —
that's a second, separate command, and forgetting it is one of the most
common LVM mistakes there is.

## Prerequisites
- Linux VM, `sudo` access
- `lvm2` (`pvcreate`, `vgcreate`, `lvcreate`, `lvextend`) and `e2fsprogs`/`xfsprogs`

Check first:
```bash
which pvcreate vgcreate lvcreate lvextend resize2fs xfs_growfs
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 500M volume group (`labvg`) out of two loop-device-backed
PVs, then a 60M ext4 logical volume (`lvapp`) mounted at `/mnt/appdata` —
using only a fraction of the VG's total space — and fills it until writes
fail.

## Step 2 — Confirm the filesystem is full
```bash
df -h /mnt/appdata
```
`Use%` is at (or near) 100%.

## Step 3 — Check the layer above it
```bash
sudo lvs labvg
sudo vgs labvg
sudo pvs
```
`lvs` shows `lvapp` is only 60M out of a 500M `labvg`. `vgs` shows
`VFree` with plenty of room. The filesystem is full; the volume group is
nowhere close.

## Step 4 — Prove the write actually fails
```bash
echo "hello" | sudo -u nobody tee /mnt/appdata/newfile.txt
```
Fails with `No space left on device`, even though `vgs` just told you
there's ~440M of free extents sitting right there in `labvg`.

## Step 5 — Fix it: extend the LV, THEN the filesystem
```bash
sudo lvextend -L +100M /dev/labvg/lvapp
df -h /mnt/appdata
```
> Gotcha: `lvextend` alone does not fix `df -h`. The LV is now 160M, but
> the ext4 filesystem sitting on it still thinks it's 60M — `df -h` looks
> unchanged. `lvextend` only grows the block device; it has no idea what
> filesystem, if any, lives on top of it, and never touches it.

```bash
sudo resize2fs /dev/labvg/lvapp
df -h /mnt/appdata
```
Now `df -h` shows the full 160M, and the write from Step 4 succeeds.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — thin-provisioned pool exhaustion:**
```bash
sudo lvcreate -L 80M --thinpool lvapp_pool labvg
sudo lvcreate -V 500M --thin -n lvapp_thin labvg/lvapp_pool
sudo mkfs.ext4 -q /dev/labvg/lvapp_thin
sudo mkdir -p /mnt/thinapp
sudo mount /dev/labvg/lvapp_thin /mnt/thinapp
sudo chmod 777 /mnt/thinapp
sudo -u nobody dd if=/dev/zero of=/mnt/thinapp/bigfile bs=1M count=400 status=none
```
`df -h /mnt/thinapp` reports a filesystem with a **500M** capacity (that's
the thin LV's advertised virtual size), so it looks like there should be
plenty of room — but the write fails after only ~80M. Diagnose what's
actually out of space here, and why resizing the thin LV's filesystem
won't help.

**Challenge B — the wrong resize tool for the filesystem:**
```bash
sudo lvcreate -L 60M -n lvxfs labvg
sudo mkfs.xfs -q /dev/labvg/lvxfs
sudo mkdir -p /mnt/xfsapp
sudo mount /dev/labvg/lvxfs /mnt/xfsapp
sudo chmod 777 /mnt/xfsapp
sudo -u nobody dd if=/dev/zero of=/mnt/xfsapp/bigfile bs=1M count=100 status=none
sudo lvextend -L +60M /dev/labvg/lvxfs
sudo resize2fs /dev/labvg/lvxfs
```
That last command errors out. Diagnose why the exact same fix from Step 5
doesn't apply here, and find the right tool — and note what it wants as
its argument instead of a device path.

See `solution.md` only after you've formed your own diagnosis.
