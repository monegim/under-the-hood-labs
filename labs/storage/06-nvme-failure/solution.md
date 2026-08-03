# Lab 6 — Solutions

## Challenge A — total failure vs flapping

**Check:**
```bash
dmesg -T | tail -20
sudo dd if=/dev/zero of=/mnt/nvmedata/test bs=4k count=1 2>&1 || true
```
Every single operation fails immediately and consistently — there is no
"up" window at all, because the `error` target (unlike `flakey`) fails
100% of I/O, unconditionally, forever.

**Diagnosis:** the main lab's `flakey` target cycles between a healthy
window and an erroring window, which is a faithful model of a *degrading*
drive — one that hasn't died yet but is throwing intermittent errors,
often due to a developing hardware fault, marginal cabling/connector, or
firmware bug. `error` is a different, simpler failure mode: total,
immediate, and permanent — every read and write fails, with no recovery
window at all. This is what an actually dead drive, a fully severed
connection, or a controller that's completely stopped responding looks
like.

**Fix:** there's no "wait for it to come back" here — a completely dead
device has no recovery window to catch. The correct action is immediate
failover/restore from backup or replica, exactly like the main lab's
Step 5 replacement, just without any ambiguity about whether to wait
first.

**Lesson:** the "wait and see if it recovers" instinct that's actually
somewhat reasonable for a flapping/intermittent device (rare bit errors
that a retry might succeed past) is actively wrong for a total failure —
there's no partial credit for waiting on a device with zero working
windows. Knowing which pattern you're looking at (some operations
succeed vs. literally none do) tells you immediately whether "give it a
minute" is a reasonable diagnostic step or a waste of an incident's most
valuable resource: time.

---

## Challenge B — silent corruption, no kernel error at all

**Check:**
```bash
dmesg -T | tail -20
```
Nothing. No I/O error, no warning, nothing tying back to the corrupted
write. The two `sha256sum` outputs from the README's repro steps differ
even though nothing in the kernel complained.

**Diagnosis:** `dm-flakey`'s `corrupt_bio_byte` feature flips a specific
byte in a write's data *silently* — the I/O still completes successfully
from the kernel/block layer's point of view; only the actual bytes on
disk are wrong. ext4 has no built-in checksumming of ordinary file data
(only some of its own metadata is protected, depending on features
enabled) — so a flipped data byte in a regular file is completely
invisible to the filesystem. It doesn't look like an error anywhere in
the stack, because as far as every layer below the application is
concerned, nothing went wrong: the write "succeeded," the read "succeeded,"
and the bytes returned are simply not the bytes that were meant to be
there.

**Fix:** there is no fix at the filesystem/kernel layer for data that's
already silently wrong — by the time you've noticed via a checksum
mismatch, the only real fix is restoring the affected file from a known-
good backup. The fix going forward is detection capability: application-
level checksums (verify a hash after every critical write, as this
challenge's `sha256sum` comparison does manually), or a filesystem/
storage layer that checksums actual data blocks, not just metadata (ZFS
and Btrfs both do this; plain ext4/XFS do not for ordinary file data).

**Lesson:** "no errors in `dmesg`" is not proof that your data is intact
— it's only proof that nothing along the I/O path *detected* a problem,
which silent bit-level corruption is specifically defined by evading.
This is the scariest realistic pre-failure NVMe/SSD behavior, more so
than clean I/O errors, because it produces zero alerts by design. Real
protection against it requires either a checksumming filesystem or
application-level integrity checks — never assume block-level success
means byte-level correctness on any storage medium.
