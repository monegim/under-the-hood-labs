# Lab 9 — Solutions

## Challenge A — soft limit + expired grace period behaves like a hard limit

**Check:**
```bash
sudo quota -u nobody
```
Right after the 15M write, usage shows past the 10K-block (10M) soft
limit but under the 25K-block (25M) hard limit, with a grace time
counting down. After the 65-second sleep, the same append that would
have succeeded a minute earlier now fails with `Disk quota exceeded`.

**Diagnosis:** a soft limit is not a hard stop — it's a threshold that
starts a grace-period timer the moment usage crosses it. While the grace
period is running, the user can keep writing right up to the hard limit,
same as if no soft limit existed. But once the grace period expires
*while usage is still over the soft limit*, the kernel starts enforcing
the soft limit as if it were the hard limit — any further write that
would keep usage above the soft threshold is rejected with `EDQUOT`
(`Disk quota exceeded`), even though the hard limit (25M) was never
close to being reached. `quota -u nobody` shows this by flagging the
over-soft usage once the grace timer has run out.

**Fix:**
```bash
sudo -u nobody rm /mnt/quotadata/gracefile
sudo quota -u nobody
echo "more" | sudo -u nobody tee -a /mnt/quotadata/gracefile2
```
Getting usage back under the soft limit clears the expired-grace penalty
immediately — there's no cooldown once you're compliant again. The other
valid fix is raising the soft limit itself with `setquota` if the usage
is legitimate.

**Lesson:** "soft limit" does not mean "advisory" — it means "temporarily
tolerated." Once its grace period lapses, it is enforced exactly like a
hard limit until usage drops back under it. Treating grace period
warnings as noise instead of an approaching hard stop is a common way
this incident catches people by surprise days after the warning first
appeared.

---

## Challenge B — inode quota, not block quota

**Check:**
```bash
sudo quota -u nobody
df -h /mnt/quotadata
df -i /mnt/quotadata
```
`quota -u nobody` shows the **files** column (not the blocks column) at
or past its limit — `nobody` is at 100-120 files used, block usage
barely moved. `df -h` confirms almost no space consumed. `df -i` on the
whole filesystem shows plenty of inodes free system-wide.

**Diagnosis:** `setquota` takes two completely independent limit pairs:
block limits (how much *space* a user can consume) and inode limits (how
many *files* a user can own), each with their own soft/hard values. This
challenge set `nobody`'s inode hard limit to 120 — nowhere near this
filesystem's actual inode capacity — so the loop fails once `nobody`
personally owns 120 files, regardless of how tiny each one is or how much
real capacity the filesystem has left in either dimension. This is
distinct from a filesystem running out of inodes globally (every user
affected, `df -i` at 100%, covered elsewhere in this repo): here the
*filesystem* has inodes to spare, but this specific user has hit a
personal cap on file count, exactly the way the main lab's block quota
capped their space regardless of filesystem capacity.

**Fix:**
```bash
sudo setquota -u nobody 200000 250000 500 600 /mnt/quotadata
sudo -u nobody touch /mnt/quotadata/tiny_151
```
Raise the inode limits (or have the user remove some of their existing
files) — the same two-step reasoning as the main lab's block quota fix,
applied to the file-count dimension instead of the space dimension.

**Lesson:** every quota check needs to consider both dimensions
independently — a user can be completely fine on space and still blocked
on file count, or vice versa. `quota -u <user>` shows both columns side
by side for exactly this reason; skimming only the blocks column (out of
habit from thinking about quotas as "disk space limits") will miss this
failure mode entirely.
