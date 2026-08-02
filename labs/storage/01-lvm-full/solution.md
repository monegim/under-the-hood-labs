# Lab 1 — Solutions

## Challenge A — thin pool exhaustion, not LV exhaustion

**Check:**
```bash
df -h /mnt/thinapp
sudo lvs -a -o+data_percent,metadata_percent labvg
```
`df -h` shows the filesystem's nominal 500M size (the thin LV's *virtual*
size — what you asked for when you ran `lvcreate -V 500M`), which is why
it looks like there should be room. `lvs -a` tells a different story:
`lvapp_pool` (visible as `lvapp_pool` and its hidden `_tdata`/`_tmeta`
sub-volumes with `-a`) shows `Data%` at or near 100%.

**Diagnosis:** thin provisioning lets you create logical volumes whose
*advertised* size is bigger than the physical storage actually backing
them — that's the entire point, it's an overcommit mechanism, the same
idea as thin-provisioned cloud disks. Blocks are only actually allocated
from the pool's real 80M of backing space as data is written. The thin
LV's filesystem (`/mnt/thinapp`) has no way to know the pool behind it is
almost out of real extents — as far as ext4 is concerned, it's sitting on
a 500M block device. The write fails not because the *filesystem* ran out
of space, but because the *pool* ran out of real extents to hand out when
ext4 asked for more blocks. Resizing the thin LV's filesystem changes
nothing, because the LV's virtual size was never the constraint.

**Fix:**
```bash
sudo lvextend -L +100M labvg/lvapp_pool
sudo -u nobody dd if=/dev/zero of=/mnt/thinapp/bigfile2 bs=1M count=50 status=none
```
Grow the **pool**, not the thin LV or its filesystem — the pool is where
the real backing storage lives. The thin LV's virtual size (500M) and its
filesystem size don't need to change at all for more writes to succeed,
since the LV was already "big enough" on paper; it just needed real
extents behind it.

**Lesson:** thin-provisioned pools can be full while every thin LV inside
them still reports lots of free space at the filesystem layer. Always
check `lvs -a -o+data_percent,metadata_percent` on the *pool*, not just
`df` on the thin volume's mount point, before concluding there's no real
capacity problem.

---

## Challenge B — resize2fs is for the ext family, not XFS

**Check:**
```bash
sudo blkid /dev/labvg/lvxfs
sudo resize2fs /dev/labvg/lvxfs
```
`blkid` reports `TYPE="xfs"`. `resize2fs` fails with something like
`resize2fs: Bad magic number in super-block while trying to open
/dev/labvg/lvxfs` — it's an ext2/3/4-only tool and doesn't understand an
XFS superblock at all.

**Diagnosis:** `lvextend` worked fine — it operates purely on the block
device and doesn't care what filesystem is on it. But growing the
filesystem itself is filesystem-specific: ext2/3/4 use `resize2fs`, XFS
uses `xfs_growfs`. Using the wrong tool doesn't corrupt anything here
(`resize2fs` just refuses to touch a filesystem type it doesn't
recognize), but it's a real "wait, why didn't that work" moment on a box
you don't administer daily.

**Fix:**
```bash
sudo xfs_growfs /mnt/xfsapp
df -h /mnt/xfsapp
```
Note the argument: `xfs_growfs` takes the **mount point**, not the
underlying device path — the reverse of `resize2fs`, which takes the
device. `xfs_growfs` also only works on a *mounted* XFS filesystem (XFS
has no concept of offline resize the way ext4's `resize2fs` allows), and
it can only grow a filesystem, never shrink one — there is no `xfs_shrinkfs`.

**Lesson:** `lvextend` is filesystem-agnostic; the second step of the
resize is not. Check the filesystem type (`blkid` or `df -T`) before
reaching for `resize2fs` out of habit, and remember `xfs_growfs` wants the
mount point while `resize2fs` wants the device.
