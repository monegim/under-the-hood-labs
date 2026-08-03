# Level 3 — Storage

Every lab here builds a small, disposable "disk" out of a loop device (or
a device-mapper target layered on top of one), breaks it on purpose, and
walks you through diagnosing and fixing it with the same tools you'd
reach for on a real host. Nothing touches a real disk or partition.

## Labs

1. [`01-lvm-full`](01-lvm-full) — a filesystem full while its LVM volume
   group has plenty of free space; the two-step `lvextend` +
   `resize2fs`/`xfs_growfs` fix; thin-provisioning overcommit.
2. [`02-xfs-corruption`](02-xfs-corruption) — simulated XFS metadata
   corruption on a loop device; reading `dmesg` for corruption messages;
   `xfs_repair` and why it requires the filesystem to be unmounted.
3. [`03-ext4-recovery`](03-ext4-recovery) — a destroyed ext4 superblock
   recovered from a backup copy; `e2fsck -n` (diagnose) vs actually
   fixing; unclean unmount vs real corruption.
4. [`04-raid-degraded`](04-raid-degraded) — a software RAID5 array
   (`mdadm`) running degraded after a member fails; replacing/re-adding a
   member; the risk window during a rebuild.
5. [`05-slow-disks`](05-slow-disks) — a service made slow by disk I/O
   contention, not CPU; proving it with `iostat -x` (`await`, `%util`);
   `ionice` and when it does (and doesn't) actually help.
6. [`06-nvme-failure`](06-nvme-failure) — a simulated failing drive
   (`dm-flakey`/`dm-error`) since a real NVMe hardware failure can't be
   reproduced on a VM; where real drive health shows up in `dmesg`/
   `smartctl`.
7. [`07-filesystem-read-only`](07-filesystem-read-only) — a filesystem
   the kernel flips read-only on its own after a write error; why
   `mount -o remount,rw` alone often just flips back.

## Prerequisites
- Linux VM, `sudo` access
- `lvm2`, `xfsprogs`, `e2fsprogs`, `mdadm`, `sysstat`, `fio`,
  `smartmontools`, `dmsetup` (part of `device-mapper`) — each lab's
  `setup.sh` installs what it needs if missing
- `losetup`, `dd` (part of `util-linux`/`coreutils`, present by default)

Each lab follows the same format as [Level 1](../linux) and
[Level 2](../networking): `README.md`, `solution.md`, `CONCEPTS.md`,
`setup.sh`, `check.sh`, `reset.sh`.
