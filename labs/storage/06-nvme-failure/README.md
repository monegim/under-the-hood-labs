# Lab 6 — Simulated NVMe Failure

## Objective
Simulate a drive returning I/O errors — you cannot make a real NVMe drive
fail on demand inside a VM, so this lab uses the `dm-flakey` and
`dm-error` device-mapper targets over a loop device to inject errors that
behave the way a genuinely failing drive does. Learn where real drive
health surfaces (`dmesg`, `smartctl`), and which SMART attributes
actually predict failure versus which ones don't matter.

## Honesty check, up front
This is a **simulation**. `dmsetup`'s `flakey`/`error` targets make a
virtual block device return I/O errors on a schedule or permanently —
that's a faithful reproduction of *how errors surface to the kernel and
your application*, which is the actual skill this lab teaches. It is
**not** a real NVMe controller, so `smartctl` run against it will not
return real SMART data (there's no real drive attached). Real SMART
monitoring is covered here as reference material to actually apply on
real hardware, not as something to run meaningfully against the lab's
virtual device.

## Prerequisites
- Linux VM, `sudo` access
- `dmsetup` (`device-mapper`, present by default), `smartmontools`
  (`smartctl`) — installed by `setup.sh` if missing

Check first:
```bash
which dmsetup smartctl
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 300M loop-device-backed image, layers a `dm-flakey` device
on top of it (up for 20s, erroring for 10s, on a repeating cycle),
formats the flakey device with ext4, mounts it at `/mnt/nvmedata`, and
starts a small writer loop that logs every failed write.

## Step 2 — Watch it flap
```bash
tail -f /var/log/nvmelab/writer.log
```
Writes succeed for ~20 seconds, then start failing for ~10, then succeed
again — repeating. This "sometimes it works, sometimes it doesn't"
pattern is exactly what a real drive with a developing hardware problem
looks like, and it's more dangerous than a clean, total failure precisely
*because* it keeps look like it's fine again.

## Step 3 — Read the kernel's view
```bash
dmesg -T | tail -40
```
Look for I/O error messages tied to the `dm-` device during the "down"
windows — `Buffer I/O error on device dm-X`, or ext4 reporting failed
writes. This is the same place a real drive's errors would surface.

## Step 4 — Understand why `smartctl` won't help here
```bash
sudo smartctl -a /dev/mapper/nvme0 2>&1 || true
```
This fails or returns nothing meaningful — there's no real drive, no real
firmware, no real SMART log behind this device. On **real** hardware,
this is the command you'd run, and the attributes that actually matter
are in `CONCEPTS.md` — reference them there since this simulated device
can't demonstrate them directly.

## Step 5 — Decide the drive is untrustworthy and replace it
The lesson of the flapping pattern is: don't wait for it to fail
completely. Simulate replacing the drive:
```bash
sudo umount /mnt/nvmedata 2>/dev/null || true
sudo dmsetup remove nvme0
sudo bash -c 'dd if=/dev/zero of=/var/lib/nvmelab/disk_replacement.img bs=1M count=300 status=none'
NEWLOOP=$(sudo losetup --find --show /var/lib/nvmelab/disk_replacement.img)
sudo mkfs.ext4 -q "$NEWLOOP"
sudo mount "$NEWLOOP" /mnt/nvmedata
```
Writes to the replacement device are now stable — no flapping.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — total, permanent failure (not flapping):**
```bash
sudo umount /mnt/nvmedata 2>/dev/null || true
sudo dmsetup remove nvme0 2>/dev/null || true
LOOPDEV=$(cat /var/lib/nvmelab/loopdev)
SIZE=$(sudo blockdev --getsz "$LOOPDEV")
sudo dmsetup create nvme0-dead --table "0 $SIZE error"
sudo mount /dev/mapper/nvme0-dead /mnt/nvmedata 2>&1 || true
```
Diagnose how this differs from the main lab's behavior — does it flap, or
is every single operation affected? What does this tell you about the
"wait and see if it recovers" instinct in this case versus the main lab's
scenario?

**Challenge B — no errors at all, but the data is wrong:**
```bash
sudo dmsetup remove nvme0-dead 2>/dev/null || true
LOOPDEV=$(cat /var/lib/nvmelab/loopdev)
SIZE=$(sudo blockdev --getsz "$LOOPDEV")
sudo dmsetup create nvme0-corrupt --table "0 $SIZE flakey $LOOPDEV 0 20 10 1 corrupt_bio_byte 32 w 0 64"
sudo mkfs.ext4 -q /dev/mapper/nvme0-corrupt
sudo mount /dev/mapper/nvme0-corrupt /mnt/nvmedata
echo "important data" | sudo tee /mnt/nvmedata/critical.txt
sha256sum /mnt/nvmedata/critical.txt
sudo umount /mnt/nvmedata && sudo mount /dev/mapper/nvme0-corrupt /mnt/nvmedata
sha256sum /mnt/nvmedata/critical.txt
```
No I/O error appears anywhere — `dmesg` is silent. Diagnose what actually
happened to the file, why nothing in the kernel or filesystem layer
noticed, and what that implies about trusting "no errors in dmesg" as
proof that your data is intact.

See `solution.md` only after you've formed your own diagnosis.
