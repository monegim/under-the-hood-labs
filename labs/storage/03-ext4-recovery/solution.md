# Lab 3 — Solutions

## Challenge A — unclean unmount self-heals via journal replay

**Check:**
```bash
dmesg -T | tail -20
```
Look for something like `EXT4-fs (loopX): recovering journal` followed
shortly after by a normal mount success message, with **no** `e2fsck`
invocation anywhere in the sequence — the kernel did this entirely on its
own during `mount`.

**Diagnosis:** `debugfs -w -R "ssv state 0"` cleared the ext4 superblock's
"cleanly unmounted" flag — exactly what a real crash or power-loss event
leaves behind, without touching any actual file data or metadata
structures. This is a fundamentally different situation from Steps 1–6's
scenario: there, the primary superblock itself was destroyed
(unreadable/unidentifiable). Here, the superblock is perfectly intact and
readable; it just honestly reports "the last unmount wasn't clean." ext4
handles that case automatically at mount time by replaying its internal
journal — recovering whatever transactions were in flight — with zero
manual intervention needed. `ls -la` afterward shows all sample files
present and correct.

**Fix:** nothing to fix — this is the expected, designed-for case.
Confirm with:
```bash
sudo e2fsck -n "$LOOPDEV"
```
which reports the filesystem clean.

**Lesson:** "the box didn't shut down cleanly" and "the filesystem is
corrupted" are not the same incident, and treating them the same way
(reaching straight for `e2fsck -y` on a production filesystem, or worse,
reformatting) is unnecessary and can itself introduce risk. An unclean
unmount alone is exactly what ext4's journal exists to handle
transparently on the next mount — real corruption is when the journal
replay isn't enough, or the superblock/metadata itself doesn't add up,
which is what Steps 1–6's destroyed superblock actually was.

---

## Challenge B — `e2fsck -n` diagnoses, it does not fix

**Check:**
```bash
sudo e2fsck -n "$LOOPDEV"
# run it again:
sudo e2fsck -n "$LOOPDEV"
```
Both runs report the identical link-count inconsistency on the same
inode. If `-n` had changed anything, the second run would come back
clean.

**Diagnosis:** `-n` tells `e2fsck` to answer "no" to every "fix this?"
prompt it would normally ask interactively — it walks the entire
filesystem, finds every problem it knows how to find, and reports all of
them, but writes nothing back to disk. It's a genuine dry run, useful
for seeing the full scope of damage (or confirming there's none) before
committing to changes, especially against a filesystem you can't afford
to have altered by mistake.

**Fix:**
```bash
sudo e2fsck -fy "$LOOPDEV"
```
`-f` forces a full check even if the filesystem otherwise looks clean
enough to skip (relevant here since only one inode field was tampered
with), and `-y` answers "yes" to every fix prompt automatically, actually
correcting the inconsistency this time. Confirm:
```bash
sudo e2fsck -n "$LOOPDEV"
```
now reports clean.

**Lesson:** `e2fsck -n` and `e2fsck -y` (or plain interactive `e2fsck`)
are different tools for different moments — `-n` for "tell me what's
wrong without risking making it worse," `-y`/`-fy` for "I've reviewed
this, now actually fix it." Treating `-n` as if it already fixed
something is a common, avoidable mistake — always confirm the actual fix
ran, don't infer it from the diagnostic pass alone. Also note `e2fsck`
strongly warns against running against a *mounted* filesystem at all
(even with `-n`) — always unmount first, as this lab does.
