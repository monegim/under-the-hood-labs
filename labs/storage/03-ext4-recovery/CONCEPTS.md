# Lab 3 — Concept: Superblock Redundancy, and Unclean Unmount vs Real Corruption

## What's actually going on

Every ext4 filesystem stores its own layout metadata — total size, block
size, inode count, feature flags, and more — in a **superblock**, a fixed
1024-byte structure located near the very start of the filesystem. The
kernel reads the primary superblock at mount time to even recognize the
device as ext4 at all; if it's destroyed or unreadable, `mount` fails
outright with a generic "wrong fs type, bad option, bad superblock"
error, because as far as the kernel can tell, there's no valid
filesystem signature there anymore. What most people never learn until
they need it is that `mkfs.ext4` doesn't write the superblock just once —
by default (via the `sparse_super` feature) it writes several redundant
backup copies at computed block offsets spread across the filesystem,
specifically so a damaged primary copy doesn't mean total loss. Running
`mke2fs -n` (a dry-run of the format process — it computes the exact
layout a real `mkfs.ext4` would produce, without writing anything) prints
these exact backup block numbers, which is why capturing that output
*before* anything goes wrong is worth doing on any filesystem you
actually care about. `e2fsck -b <block>` tells `e2fsck` to reconstruct
the primary superblock from a specified backup copy, then run its normal
consistency check using that recovered information — this is precisely
what turns "the filesystem is gone" into a routine, few-minute recovery.

`e2fsck` itself has a critical distinction between diagnosing and fixing
that trips people up constantly: `-n` runs a completely read-only pass
that answers "no" to every internal "should I fix this?" prompt, meaning
it reports every problem it finds but changes absolutely nothing on
disk — useful for understanding the scope of damage before you commit to
touching anything, especially against a filesystem you can't afford to
have altered by a wrong guess. Actually fixing anything requires `-y`
(auto-answer yes to every fix prompt) or interactive confirmation, often
combined with `-f` to force a full check even when the filesystem's own
state flag suggests it's already clean. Treating a `-n` pass as if it
already resolved something — a very natural mistake, since the output
looks almost identical either way except for whether changes were
actually written — is one of the most common ext4 recovery mistakes.

Separately, and just as important: an **unclean unmount** (the state left
behind by a crash, power loss, or `kill -9` on something holding the
filesystem open) is not the same incident as corruption, even though both
can look alarming from the outside. ext4's superblock carries a simple
flag recording whether the filesystem was cleanly unmounted last time.
When that flag says "no," the kernel's own mount path automatically
replays the filesystem's internal journal — recovering whatever
transactions were only partially committed — with zero manual
intervention, no `e2fsck` invocation required at all. This is the entire
point of journaling: crash consistency without a manual repair step for
the common case. Real corruption — a superblock that's actually
unreadable, or metadata whose internal structure literally doesn't add
up — is a different, rarer situation where the journal alone can't help,
because there's nothing consistent left to replay from; that's what
actually calls for `e2fsck` and, per this lab's main scenario, potentially
a backup superblock.

## Where this shows up in the real world

"The filesystem won't mount, bad superblock" is a legitimately scary page
for anyone who's never needed a backup superblock before — and the fix,
once you know it's an option, is often faster than restoring from backup
media. Any host that's had a partial/aborted disk write (a bad sector
that happened to land on the primary superblock's location, a botched
partition/`dd` operation, certain firmware bugs) can hit this. The
unclean-unmount-vs-corruption distinction matters constantly in
practice: after any ungraceful reboot (power event, OOM killer taking
down something with open file handles, a hypervisor host crashing under
a VM), it's worth checking `dmesg` for a routine "recovering journal"
message before assuming anything is actually broken — most of the time,
ext4 already fixed it before you even finished logging in.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers
  inodes, superblocks, and journaling filesystem semantics in depth.
- **Book:** *Understanding the Linux Kernel* — Daniel P. Bovet & Marco
  Cesati (O'Reilly) — internals of how the VFS and ext-family filesystems
  handle mount-time superblock validation and journal replay.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man8/e2fsck.8.html
  and `mke2fs(8)` — canonical reference for `e2fsck`/`mke2fs` flags,
  including `-n`, `-b`, and backup superblock behavior.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — ext4 administration and
  recovery guides.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  covers ext4 filesystem administration and recovery fundamentals.

**Confidence flag:** `debugfs -w -R "ssv state 0"` and `debugfs -w -R
"sif <inode> links_count 5"` are believed-correct `debugfs` field/command
names (`ssv`/`sif` and the `state`/`links_count` superblock/inode fields
are documented in `debugfs(8)`), but have not been exercised on a live
filesystem — dry-run before recording and confirm the exact output
`e2fsck` produces for each.
