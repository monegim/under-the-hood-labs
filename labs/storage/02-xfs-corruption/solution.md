# Lab 2 — Solutions

## Challenge A — corruption on a live, mounted filesystem

**Check:**
```bash
dmesg -T | tail -40
```
Somewhere in there: an XFS corruption message (metadata CRC mismatch or
"Corruption of in-memory data detected") logged at the moment `ls -laR`
touched the corrupted block — not at the moment the `dd` actually ran.
The kernel had no reason to notice anything until something asked it to
read that specific block.

**Diagnosis:** the corruption happened to a filesystem that was live and
mounted the entire time, which is the realistic case — a bad sector, a
flaky cable, or a controller hiccup doesn't wait for a convenient
maintenance window. XFS doesn't proactively scan every block looking for
problems; it only notices when something actually reads or writes the
affected block, which is why the error surfaced on `ls -laR`, not
immediately after the `dd`. Critically, you cannot run `xfs_repair`
against this filesystem right now — it is still mounted, and `xfs_repair`
categorically refuses to operate on a mounted filesystem (unlike `e2fsck
-n` on ext4, which can at least *inspect* a mounted filesystem safely).

**Fix:**
```bash
sudo umount /mnt/xfsdata
sudo xfs_repair "$LOOPDEV"
sudo mount "$LOOPDEV" /mnt/xfsdata
```
Unmount first, always — there is no shortcut here.

**Lesson:** real corruption doesn't announce itself when it happens; it
announces itself the next time something touches the affected block,
which can be much later and can look like an unrelated command
"suddenly" failing. And regardless of when you find out, the very first
step is always the same: get the filesystem unmounted before you touch it
with `xfs_repair`.

---

## Challenge B — corrupted log requires `-L`

**Check:**
```bash
sudo xfs_repair "$LOOPDEV"
```
The output reports that the log is dirty/unrecoverable and that you need
to re-run with `-L` to proceed (`xfs_repair` refuses to guess at replaying
a log it can't trust).

**Diagnosis:** this challenge specifically targeted the filesystem's
internal **log** (XFS's equivalent of a journal), located using `xfs_db`
to read the superblock's `logstart`/`blocksize` fields rather than
guessing at an offset — the log's location isn't fixed across every XFS
filesystem, since it depends on how the filesystem was formatted. A
corrupted log is a different, more serious situation than corrupted data
or ordinary metadata: on a clean shutdown, the log should be empty; on an
unclean one, `xfs_repair`'s normal behavior is to replay it to recover any
in-flight transactions before checking anything else. If the log itself
is unreadable, there is nothing valid to replay, and `xfs_repair` won't
guess — it stops and asks you to explicitly acknowledge that with `-L`.

**Fix:**
```bash
sudo xfs_repair -L "$LOOPDEV"
sudo mount "$LOOPDEV" /mnt/xfsdata
```
`-L` tells `xfs_repair` to zero the log and proceed without replaying it.

**Lesson:** `-L` is a last resort, not a routine flag — it discards
whatever transactions were sitting in the log waiting to be replayed,
which on a real production filesystem means losing however much
just-written data hadn't been fully committed yet. Only reach for it when
`xfs_repair`'s normal pass explicitly tells you it's required, and treat
any data written in the moments before the corruption/crash as suspect
afterward.
