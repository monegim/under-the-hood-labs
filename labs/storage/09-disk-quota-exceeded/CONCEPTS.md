# Lab 9 — Concept: Disk Quotas Are a Per-User Cap, Not a Filesystem-Capacity Question

## What's actually going on

Linux disk quotas let an administrator limit how much space and how many
files (inodes) an individual user or group can consume on a filesystem,
tracked completely separately from how full the filesystem actually is.
On ext2/3/4, this is implemented via hidden accounting files
(`aquota.user`, `aquota.group`) that the kernel updates on every write,
once quota tracking has been turned on for that mount with
`usrquota`/`grpquota` mount options and initialized with `quotacheck`
(which scans the filesystem and builds the initial per-user/group usage
totals) and `quotaon`. From that point on, every write the kernel handles
checks the writing user's current usage against their configured limits
*before* it checks whether the filesystem itself has free blocks —
which is exactly why a user can get blocked with plenty of real capacity
sitting unused: the quota check fails first, and the filesystem-capacity
question is never even reached.

Quota limits come in two independent pairs, each with a soft and a hard
value: block limits (space, in 1K units for `setquota`) and inode limits
(file count). Hitting a **hard** limit is an unconditional stop — the
write fails immediately with `EDQUOT` ("Disk quota exceeded"), full stop.
A **soft** limit works differently and is the part most people get wrong:
crossing it does not fail anything by itself. It starts a grace-period
timer (configured filesystem-wide with `edquota -t` or `setquota -t`,
traditionally defaulting to seven days). For as long as that timer is
running, the user can go on writing right up to the hard limit exactly as
if the soft limit didn't exist — it's a warning state, not an
enforcement state. The moment the grace period *expires* while the user
is still over the soft limit, the kernel starts treating the soft limit
as if it were the hard limit: any write that would keep usage above the
soft threshold is rejected, even though the actual hard limit may be far
away. This two-stage behavior — permissive, then suddenly strict, with no
change in the error message the user sees either time it eventually
fails — is precisely why grace-period warnings that get ignored turn into
a surprise outage days later with no obvious trigger.

The block/inode split matters just as much as the soft/hard split. A
user can be well within their block (space) quota while blocked entirely
on inode (file count) quota, or the reverse — many small files can
exhaust an inode limit while barely touching a space limit, and a few
huge files can do the opposite. `quota -u <user>` and `repquota -a` both
report blocks and inodes as separate columns for exactly this reason.
This is a different failure surface from a filesystem running out of
inodes *globally* (which affects every user and shows up in `df -i`
system-wide) — quota inode exhaustion is a cap on one specific user,
enforced regardless of how many inodes the filesystem as a whole has
free. `df` and `df -i` answer "how full is the filesystem"; `quota`/
`repquota` answer a completely different question, "how much of their
personal allowance has this user used" — and neither command can answer
the other's question.

## Where this shows up in the real world

Shared multi-user systems — university and research computing clusters,
shared hosting, CI build servers with per-team home directories, mail
servers capping mailbox size per account — are the classic environments
where per-user quotas matter, precisely because a single user's runaway
process or careless script can otherwise fill a shared filesystem for
everyone else. The soft-limit-plus-grace-period mechanism exists
specifically to give a user a warning window (traditionally communicated
by `warnquota`-style nightly email) before enforcement kicks in, rather
than failing writes the instant a threshold is crossed — but that only
works if someone is actually reading the warnings, which is why grace
period expiry is a genuinely common "why did this suddenly start failing
with no changes on our end" support ticket.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers
  quota semantics (`quotactl(2)`) and how filesystem-level limits are
  enforced at the syscall layer.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ —
  canonical reference for `quotactl(2)`, `quotacheck(8)`, `setquota(8)`,
  `edquota(8)`, and `repquota(8)`.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — has a dedicated disk quota
  administration guide covering setup, soft/hard limits, and grace
  periods on ext4/XFS.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — practical
  disk quota setup and troubleshooting pages.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  Linux storage and filesystem administration content.

**Confidence flag:** the exact `setquota -t <block-grace> <inode-grace>
<filesystem>` argument format (plain integers being interpreted as
seconds) is written from memory of the general `setquota`/`edquota`
grace-time interface and has **not** been tested live — some
distributions' `setquota` expect a unit suffix (`60seconds`, `1days`)
rather than a bare number. Verify against `man setquota` on the target
system before relying on the exact syntax in Challenge A; if a bare
integer is rejected, the fix is almost certainly appending a unit. The
soft/hard and block/inode semantics described here are standard,
well-documented Linux quota behavior and are high-confidence.
