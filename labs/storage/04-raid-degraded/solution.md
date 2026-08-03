# Lab 4 — Solutions

## Challenge A — a second failure during the rebuild window

**Check:**
```bash
sudo mdadm --detail /dev/md0
cat /proc/mdstat
```
The array's `State` shows something like `clean, FAILED` (or `active,
degraded, Not Started` depending on timing), with two devices now marked
`faulty`/`removed` instead of one. `/proc/mdstat` no longer shows a
`recovery` line making progress — the rebuild stopped because it can't
complete.

**Diagnosis:** RAID5 can reconstruct exactly one missing member at a
time, because reconstruction works by XOR-ing parity against the
*remaining* members — with two members gone simultaneously, there is no
longer enough surviving data to reconstruct either of them. Slowing the
rebuild down with `speed_limit_max` (an `mdadm`/kernel throttle that
exists precisely so rebuilds don't saturate a production array's I/O)
widened the real window during which a second failure is catastrophic.
This is exactly what "degraded" means in practice: not "slower," but
"one failure away from data loss," for the entire duration of the
rebuild — which, on real multi-terabyte disks, can take many hours.

**Fix:** there isn't an `mdadm` command that recovers from this — two
failed members in a 3-disk RAID5 exceeds its fault tolerance by
definition. The real "fix" happened before this challenge: restoring from
backup, since the array itself no longer has the data. This challenge
has no in-array remediation on purpose.

**Lesson:** the fault tolerance of a RAID level is a hard limit, not a
guideline — RAID5 survives exactly 1 concurrent failure, RAID6 survives
2 (at the cost of a second parity disk), RAID1/10 survive 1 per mirrored
pair. The rebuild window is the most dangerous time in an array's life
specifically because it's when a second failure is most likely (the
remaining disks are all under sustained heavy read load reconstructing
the new member, which is exactly the kind of stress that reveals a
second marginal disk). This is the actual argument for RAID6 or hot
spares over RAID5 on larger arrays, and for keeping actual backups
regardless of which RAID level you use — RAID is for availability during
a single failure, not a substitute for backup.

---

## Challenge B — `--re-add` with a bitmap does a partial resync

**Check:**
```bash
cat /proc/mdstat
```
The recovery line finishes far faster than Step 5's full rebuild did (or
may show a much smaller "resync" range), and `mdadm --detail` reports the
device came back via a bitmap-based partial resync rather than a full
recovery.

**Diagnosis:** `mdadm --grow --bitmap=internal` added a write-intent
bitmap to the array — a small on-disk structure that tracks which
regions of the array have been written to *since* a member was last known
to be in sync. When a member drops out only briefly and you bring it back
with `--re-add` (as opposed to `--add`), `mdadm` checks that bitmap and
only re-syncs the regions marked as changed since the device left,
instead of reconstructing the entire disk from scratch. `--add` doesn't
do this — it always treats the device as a blank spare needing a full
rebuild, regardless of whether a bitmap exists or how briefly the device
was actually gone.

**Fix:** nothing to fix here — this challenge is demonstrating a faster,
better recovery path, not a broken state. The "fix" is knowing to reach
for `--re-add` (with a bitmap already in place) instead of `--add` when a
member's absence was brief.

**Lesson:** `--re-add` is only meaningful, and only fast, when three
things are true: a write-intent bitmap exists on the array, the returning
device is the *same* device that dropped out (not a different, blank
replacement disk), and the device wasn't gone so long that the bitmap's
tracked changes have been overwritten. If a physical disk actually failed
and was replaced with a new one, there's no meaningful "recent state" to
resync from — that's exactly when you want `--add` and a full rebuild.
Enabling a bitmap up front costs a small amount of write overhead in
exchange for dramatically shorter recovery windows on the common
"disk/controller blipped briefly" case, which is exactly when the array
is least protected.
