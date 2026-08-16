# Lab 11 — Solutions

## Challenge A — dup metadata self-heals, single data doesn't

**Check:**
```bash
sudo btrfs scrub status -d /mnt/btrfsdata
```
The per-device breakdown shows some non-zero count under corrected
errors and, separately, a non-zero count under uncorrectable errors (the
exact split depends on exactly which bytes the setup script's `dd`
happened to land on, but both categories are typically present).

**Diagnosis:** Step 1 formatted this filesystem with `-d single -m dup`
explicitly — a single copy of **data**, but two copies of **metadata**,
even though it's all sitting on one loop device. `dup` is a real
redundancy profile, just a much smaller-scale one than a `raid1` across
two whole disks: btrfs deliberately writes the filesystem's metadata
(the B-trees describing where everything is, not the file contents
themselves) twice, to two different physical locations on the same
device. So when the corruption from Step 1 happens to land on a metadata
block, btrfs's scrub finds the checksum mismatch, reads the second copy,
confirms it's good, and rewrites the correct copy over the bad one —
silently self-healed, reported as "corrected." When the corruption lands
on a **data** block, there is no second copy anywhere to fall back to
(`-d single`), so the exact same checksum-mismatch detection happens, but
there's nothing to reconstruct from — reported as "uncorrectable," and
that's the file (or part of it) genuinely gone.

**Fix:** there's no fix for the uncorrectable (data) errors beyond
restoring from backup, as the main lab does. For the corrected (metadata)
errors, nothing further is needed — the scrub already fixed them.

**Lesson:** "single device" doesn't mean "zero redundancy" on btrfs —
metadata gets a second copy by default specifically because losing
metadata (the filesystem's own map of itself) is categorically worse
than losing one file's data; it can mean losing access to everything.
Data redundancy is a separate, opt-in decision (`-d raid1`, `-d dup`,
or an underlying redundant device) that this lab's single-loop-device
setup deliberately doesn't have, which is exactly why data corruption
here is unrecoverable in place while some metadata corruption might not
even be noticeable without checking the scrub report closely.

---

## Challenge B — `btrfs check --repair` is not a routine fix

**Check:**
```bash
sudo btrfs check --help 2>&1 | head -30
```
The help output and btrfs's own documentation carry an explicit warning
that `--repair` should not be run without understanding what it's about
to do, and is not something to reach for casually the way `xfs_repair`
or `e2fsck -y` are.

**Diagnosis:** `xfs_repair` and `e2fsck` are the designed, expected,
routine path back to a consistent filesystem after corruption on their
respective filesystems — running them is the normal fix, not a
last resort. `btrfs check --repair` has historically had a different,
riskier reputation in the btrfs community: it can, in some cases, make a
damaged filesystem's problems worse rather than better, because repairing
btrfs's copy-on-write B-tree structures correctly is a harder problem
than repairing a simpler on-disk layout, and the tool's repair logic has
not always kept pace with every corruption case it might encounter. This
doesn't mean `btrfs check --repair` is never appropriate — it means it's
a "read the specific warnings, ideally get a second opinion, and back up
whatever you can reach first" tool, not a "run it and move on" tool the
way the ext4/XFS equivalents are treated in this repo's earlier labs.

**Fix:** for this lab's actual corruption (which is data corruption
btrfs already told you is unrecoverable via the scrub in Step 4, plus
whatever metadata scrub already self-healed via Challenge A), running
`--repair` has nothing left to usefully fix — the right move is the same
as the main lab's Step 6: recreate the filesystem and restore from
backup, not attempt an in-place repair of data that checksums have
already confirmed is gone.

**Lesson:** not every filesystem-repair tool carries the same risk
profile, and treating them as interchangeable "just run the repair
command" steps is a mistake. Read a repair tool's own warnings before
running it, especially on a filesystem you're less familiar with day to
day than ext4/XFS — and remember that for genuinely lost data (as opposed
to a damaged-but-recoverable tree structure), no repair tool substitutes
for a backup or redundancy that was never there in the first place.
