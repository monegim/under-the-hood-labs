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
8. [`08-lvm-snapshot-full`](08-lvm-snapshot-full) — an LVM COW snapshot
   running out of allocated space as the origin volume changes, going
   Invalid; why undersized snapshots are a common backup-strategy
   mistake.
9. [`09-disk-quota-exceeded`](09-disk-quota-exceeded) — a user/group
   hitting their filesystem quota with plenty of disk space still free;
   `repquota`/`quota -u` to distinguish this from real disk-full or
   inode exhaustion.
10. [`10-zfs-pool-degraded`](10-zfs-pool-degraded) — a ZFS pool running
    DEGRADED after a vdev member fails; `zpool status`, `zpool scrub`,
    replacing a device.
11. [`11-btrfs-corruption`](11-btrfs-corruption) — btrfs's built-in data
    checksumming catching corruption ext4/xfs would silently miss;
    `btrfs scrub`/`btrfs check`; why self-healing needs redundancy this
    single-device demo doesn't have.
12. [`12-docker-storage-driver-bloat`](12-docker-storage-driver-bloat) —
    dangling images, stopped containers, and unused volumes filling
    `/var/lib/docker`; `docker system df` to see what's reclaimable;
    the real difference between plain `prune` and `-a --volumes`.
13. [`13-nfs-stale-mount`](13-nfs-stale-mount) — a loopback NFS export
    swapped out from under a client, producing a genuine "Stale file
    handle"; `hard` vs `soft` mounts; `umount -f` vs `umount -l`.
14. [`14-swap-exhaustion`](14-swap-exhaustion) — a dedicated swapfile
    filled completely inside a memory-limited cgroup, OOM-killing a
    process even though system RAM looks fine; why `vm.swappiness`
    can't fix an already-full swap.
15. [`15-io-scheduler-misconfiguration`](15-io-scheduler-misconfiguration) —
    the active I/O scheduler (not raw disk speed) deciding whether a
    latency-sensitive writer survives contention with a background hog;
    `none` vs `bfq`/`mq-deadline`; why `ionice` does nothing under `none`.

## Prerequisites
- Linux VM, `sudo` access, cgroup v2 (labs 14-15)
- `lvm2`, `xfsprogs`, `e2fsprogs`, `mdadm`, `sysstat`, `fio`,
  `smartmontools`, `dmsetup` (part of `device-mapper`), `zfsutils-linux`,
  `btrfs-progs`, `quota`, `nfs-kernel-server`/`nfs-common`, `docker` —
  each lab's `setup.sh` installs what it needs if missing
- `losetup`, `dd` (part of `util-linux`/`coreutils`, present by default)

Each lab follows the same format as [Level 1](../linux) and
[Level 2](../networking): `README.md`, `solution.md`, `CONCEPTS.md`,
`setup.sh`, `check.sh`, `reset.sh`.
