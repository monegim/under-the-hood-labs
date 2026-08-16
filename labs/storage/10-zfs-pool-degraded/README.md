# Lab 10 — ZFS Pool Degraded

## Objective
Build a small ZFS `raidz1` pool out of loop devices, fail one member, and
watch the pool run `DEGRADED` instead of failing outright. Learn
`zpool status` to read pool/vdev health, `zpool scrub` to verify data
integrity, and `zpool replace` to bring a failed member back to full
redundancy.

## Why this matters
ZFS folds together what LVM/mdadm/a filesystem do as three separate
layers (volume management, RAID, and filesystem) into one system with
its own vocabulary and its own health model. A `DEGRADED` pool is still
fully readable and writable — that's the entire point of redundancy —
but it's one more failure away from data loss, and `zpool status` is the
one command that tells you that at a glance. Unlike `mdadm` (Lab 4),
ZFS also checksums every block of data and metadata by default, so
`zpool scrub` isn't just "check the disks are spinning" — it's an
end-to-end integrity check that can find and, on a redundant pool,
silently repair corrupted data that a non-checksumming stack would never
even detect.

## Prerequisites
- Linux VM, `sudo` access
- `zfsutils-linux` (Debian/Ubuntu package name; ZFS is **not** in the
  mainline kernel due to licensing, so this installs the OpenZFS kernel
  modules via DKMS and can take a few minutes to build on first install,
  or may need a reboot/module reload if DKMS can't build against the
  running kernel — this is the one lab in this set most likely to need
  troubleshooting specific to your VM's kernel version)

Check first:
```bash
which zpool zfs
sudo modprobe zfs && echo "zfs module loaded OK"
```
If `zfsutils-linux` isn't installable or the module won't load on your
VM (common on minimal cloud images or kernels newer than what DKMS has
been built against), this lab cannot run — there's no loop-device
workaround for a missing kernel module the way there is for missing
disks.

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates three 200M loop-device-backed images, builds a `raidz1`
pool (`labpool`) out of them mounted at `/mnt/zfsdata`, writes sample
data, then takes one member offline — simulating a failed drive.

## Step 2 — Read the pool's health
```bash
sudo zpool status labpool
```
The pool state is `DEGRADED`. One vdev shows `OFFLINE` (or `FAULTED`),
the pool as a whole shows `state: DEGRADED`, and the summary explains
which device needs attention.

## Step 3 — Confirm the pool is still fully usable
```bash
df -h /mnt/zfsdata
cat /mnt/zfsdata/baseline_1 > /dev/null && echo "reads fine"
echo "still writable" | sudo tee /mnt/zfsdata/degraded_write_test
```
Redundancy means a `DEGRADED` `raidz1` pool keeps serving reads and
writes normally — the risk is losing a *second* member before you fix
the first, not an immediate outage.

## Step 4 — Scrub to verify integrity
```bash
sudo zpool scrub labpool
sudo zpool status labpool
```
Wait for the scrub to finish (`zpool status` shows progress, then a
completion summary). A scrub reads every block and verifies its checksum
against every other member with redundant data — it's the tool you'd run
before trusting a pool that just lost a member, not just after.

## Step 5 — Replace the failed member
```bash
sudo bash -c 'dd if=/dev/zero of=/var/lib/zfslab/disk4.img bs=1M count=200 status=none'
NEWLOOP=$(sudo losetup --find --show /var/lib/zfslab/disk4.img)
OLDLOOP=$(cat /var/lib/zfslab/loopdevs | sed -n '2p')
sudo zpool replace labpool "$OLDLOOP" "$NEWLOOP"
sudo zpool status labpool
```
Watch the `resilver` progress in `zpool status` until it completes. The
pool returns to `state: ONLINE` with all three members healthy.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — silent corruption, not an offline device:**
```bash
sudo zpool clear labpool
THIRDLOOP=$(cat /var/lib/zfslab/loopdevs | sed -n '3p')
sudo dd if=/dev/urandom of="$THIRDLOOP" bs=1M seek=50 count=20 conv=notrunc
sudo zpool status labpool
sudo zpool scrub labpool
sudo zpool status -v labpool
```
Right after the `dd`, `zpool status` may show nothing wrong at all — no
device is `OFFLINE`, nothing looks obviously broken. Diagnose what a
scrub actually finds here, what `CKSUM` errors in the output mean, and
whether the pool needed to lose a whole device for this corruption to
matter.

**Challenge B — a raidz vdev isn't a mirror:**
```bash
FIRSTLOOP=$(cat /var/lib/zfslab/loopdevs | sed -n '1p')
sudo zpool remove labpool "$FIRSTLOOP"
```
This fails. Diagnose why removing a member from a `raidz1` vdev isn't
possible the way `zpool remove` can shrink a mirror, and what that
implies about planning `raidz` pool sizing up front versus a mirror's
flexibility.

See `solution.md` only after you've formed your own diagnosis.
