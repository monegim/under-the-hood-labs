# Lab 10 — Solutions

## Challenge A — scrub finds and self-heals silent corruption

**Check:**
```bash
sudo zpool status labpool
```
Immediately after the `dd`, this can show `state: ONLINE` with no
obvious problem — the corruption is sitting in unused-or-not-yet-read
sectors of one member's backing file, and ZFS hasn't touched those
blocks yet to notice. Only after:
```bash
sudo zpool scrub labpool
sudo zpool status -v labpool
```
does the picture change: the scrubbed device shows a non-zero `CKSUM`
error count, and `zpool status -v` lists which files (if any user data
was actually hit) were affected — often none, if the corrupted region
landed on unallocated space, which is worth checking for directly.

**Diagnosis:** ZFS checksums every block of data and metadata by
default, independent of any RAID-level redundancy — this is different
from `mdadm`/hardware RAID, which only knows a block is bad if the
underlying device reports an I/O error. A block silently returning wrong
bytes (bit rot, a firmware bug, a bad sector that hasn't been remapped
yet) produces no I/O error at all — the device claims the read
succeeded. ZFS catches this anyway because it independently verifies the
checksum stored for that block against what was actually read. On a
redundant pool like `raidz1`, when a checksum mismatch is found, ZFS
doesn't just report it — it reconstructs the correct data from parity on
the healthy members and rewrites the correct data over the corrupted
copy, transparently. This is `raidz`'s self-healing: it happens as a side
effect of a scrub (or even a normal read hitting the bad block), and no
manual intervention beyond running the scrub is needed for it to
self-correct.

**Fix:** there usually isn't a separate "fix" step — the scrub itself is
the fix. Confirm it:
```bash
sudo zpool status labpool
```
`CKSUM` errors remain visible as a historical count until cleared:
```bash
sudo zpool clear labpool
sudo zpool status labpool
```
`zpool clear` resets the error counters once you've confirmed the pool
is healthy again; it does not itself fix anything, so don't run it as a
substitute for actually scrubbing.

**Lesson:** "no I/O error" is not the same thing as "the data is
correct" — the exact same lesson as this repo's simulated-NVMe-failure
lab, but ZFS is one of the few filesystems that can actually detect and
correct it automatically, and only because it has both checksums *and*
redundancy. A single-device ZFS pool (or Lab 11's single-device btrfs
filesystem) can detect this same corruption via its checksum, but has
nothing to reconstruct the correct data from — detection without
redundancy still means data loss, just a *noticed* data loss instead of
a silent one.

---

## Challenge B — raidz vdevs can't be shrunk by removing a member

**Check:**
```bash
sudo zpool remove labpool <device>
```
This errors out — ZFS refuses, with a message to the effect that the
device is part of a RAID-Z vdev and can't be removed that way.

**Diagnosis:** `zpool remove` is only supported for top-level vdevs that
are mirrors, or for devices that were added as hot spares, cache, or log
devices — never for an individual disk that's part of a `raidz`/`raidz2`/
`raidz3` group. This isn't a missing feature so much as a structural
consequence of how `raidz` parity is laid out across all members of the
vdev simultaneously (unlike a mirror, where each member is a complete,
independent copy that can be dropped on its own). Removing one disk from
a mirror just leaves a smaller mirror (or a single unmirrored copy);
there's no equivalent "smaller raidz" to fall back to by dropping one
member, since the parity math was computed across the original set.

**Fix:** there isn't a live one — a `raidz` vdev's member count is fixed
for the life of that vdev. The only ways to change a `raidz` pool's
underlying disk count are: replacing individual members one at a time
with larger disks (`zpool replace`, growing capacity without changing
member count) or building a new pool with the desired layout and
migrating data (`zfs send`/`zfs receive`) rather than reshaping the
existing one in place.

**Lesson:** `raidz` sizing is a decision made once, at pool creation
time, not something to defer — plan the member count for where you
expect the pool to end up, not just where it starts. A mirror trades
some of `raidz`'s space efficiency for exactly this kind of operational
flexibility, and that tradeoff is worth making deliberately rather than
discovering it the hard way mid-incident.
