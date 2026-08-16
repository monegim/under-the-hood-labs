# Lab 8 — Solutions

## Challenge A — extend the snapshot before it fills

**Check:**
```bash
sudo lvs -o+snap_percent snapvg
```
`Snap%` on `snap3` climbs toward 100% as the loop's `dd` writes churn the
origin — each overwritten block on the origin has to be copied into
`snap3` before being overwritten, and `snap3` only has 20M of COW space
to hold those copies.

**Diagnosis:** a COW snapshot's capacity is fixed at creation time and is
completely independent of the origin's size. `Snap%` is the single most
important number to watch on any active snapshot — it tells you how much
of that fixed COW space has been consumed, and it only ever goes up. Left
unattended, it eventually hits 100%, at which point the kernel's
`dm-snapshot` target marks the snapshot `Invalid` and it becomes useless
for rollback (see the main lab). Nothing about `snap3` looks different
from `snap1` at this point except that you're watching it in time to act.

**Fix:**
```bash
sudo lvextend -L +50M /dev/snapvg/snap3
sudo -u nobody dd if=/dev/urandom of=/mnt/snaporigin/churn_more bs=1M count=10 status=none
sudo lvs -o+snap_percent snapvg
```
`lvextend` works on a snapshot LV exactly like it does on any other
LV — it just grows the amount of COW space available. `Snap%` drops
(same amount of used space, larger denominator) and the snapshot
continues absorbing origin writes without going `Invalid`.

**Lesson:** an undersized snapshot isn't a one-time sizing decision —
it's an ongoing risk that grows with every write to the origin.
`lvs -o+snap_percent` (or an equivalent alert on it) needs to be checked
or monitored for the entire lifetime of the snapshot, and extending it
proactively at, say, 70-80% is cheap; recovering an already-`Invalid`
snapshot is not possible at all.

---

## Challenge B — merge is deferred while the origin is open

**Check:**
```bash
sudo lvconvert --merge /dev/snapvg/snap3
sudo lvs snapvg
```
The output says something like `Delaying merge since origin is open.` —
the merge did **not** happen despite the command returning without an
error.

**Diagnosis:** `lvconvert --merge` folds a snapshot's COW data back into
its origin, effectively rolling the origin back to the point-in-time the
snapshot was taken. But it can't safely rewrite blocks the origin's
filesystem is currently mounted and possibly using — the origin LV is
"open" for as long as it's mounted (or otherwise in use), so LVM defers
the actual merge instead of doing it unsafely underneath a live
filesystem. This is the same "open device" constraint you'll hit trying
to merge a snapshot of the root filesystem, where it has to wait until
the next boot.

**Fix:**
```bash
sudo umount /mnt/snaporigin
sudo lvchange -an snapvg/origin
sudo lvchange -ay snapvg/origin
sudo lvs snapvg
sudo mount /dev/snapvg/origin /mnt/snaporigin
cat /mnt/snaporigin/post_snapshot_change 2>&1 || echo "file is gone - origin rolled back"
```
Deactivating and reactivating the origin LV is what actually triggers the
deferred merge (for a non-root LV; on a root filesystem, a reboot serves
the same purpose). Once merged, `snap3` itself is consumed and disappears
from `lvs`, and the origin's contents reflect the snapshot's
point-in-time — the file written after the snapshot was taken is gone.

**Lesson:** `lvconvert --merge` returning success does not mean the merge
happened — it means the merge was *scheduled*. Always follow it with
`lvs` to confirm the snapshot is actually gone (fully merged) before
assuming a rollback took effect, especially in a script or runbook that
doesn't stop to look at the output.
