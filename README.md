# Under the Hood — SRE/DBRE Troubleshooting Labs

Most "hands-on Linux/networking/DBRE" content teaches you how to configure
things. This teaches you how to **troubleshoot** them — build the system,
break it on purpose, diagnose it with the same tools you'd use in a real
incident, then read a postmortem that explains not just the fix but *why*
it happened and why the obvious fix often doesn't work.

Structured like a game: six levels, increasing in scope and difficulty,
roughly 120 labs total once complete.

## Each lab contains

- `README.md` — objective, why it matters, step-by-step build (numbered,
  copy-pasteable), then 2 "break it" challenges — **no answers given here**
- `solution.md` — the diagnosis process and fix, written like a postmortem:
  root cause, why it happened, why common fixes don't work, the commands
  that reveal it, how to prevent it, real-world examples
- `CONCEPTS.md` — the mechanism explained properly (not just "run this
  command"), plus 3-6 curated resources (books, docs, YouTube channels) to
  go deeper
- `setup.sh` — builds the "before" broken state automatically
- `check.sh` — automatically verifies whether you actually fixed it
- `reset.sh` — restores the broken state so you can retry

## Levels

### Level 1 — Linux Basics (21 built / 21 planned) ✅
Not "how to use `ps`" — how Linux actually works under a real incident.
Split into two halves: **foundations** (build the underlying mechanism
yourself — namespaces, cgroups, overlayfs, a container from scratch,
eBPF) and **troubleshooting** (a simulated production incident per lab,
including strace/ltrace, boot failures, zombie processes, clock drift).
[`labs/linux/`](labs/linux)

Tools: `ps`, `top`/`htop`, `vmstat`, `iostat`, `strace`, `lsof`, `journalctl`, `/proc`, `systemctl`

### Level 2 — Networking (25 built / 25 planned) ✅
Every SRE should be comfortable debugging packets. [`labs/networking/`](labs/networking)

Tools: `tcpdump`, `ip`, `ss`, `bridge`, `conntrack`, `iptables`/`nftables`, `dig`, `mtr`, `tracepath`

### Level 3 — Storage (7 built / 15 planned)
LVM full, XFS corruption, ext4 recovery, RAID degraded, slow disks, a
simulated failing drive, filesystems the kernel flips read-only on its
own. Everything built on disposable loop devices — nothing touches a
real disk. [`labs/storage/`](labs/storage)

### Level 4 — Databases (13 built / 20 planned)
Exactly what a DBRE sees. MySQL (replication lag, GTID conflicts,
deadlocks, slow queries, metadata locks, disk full, binlog corruption,
connection storms — 8/8) and PostgreSQL (replication lag, WAL full,
autovacuum, index bloat, lock contention — 5/5).
[`labs/mysql/`](labs/mysql) · [`labs/postgres/`](labs/postgres)

### Level 5 — Kubernetes (9 built / 20 planned)
Pod networking, CoreDNS failure, etcd full, expired certs, stuck PVCs,
node pressure, CNI failure, broken ingress, API server unavailable — all
on a `kind` cluster. [`labs/kubernetes/`](labs/kubernetes)

### Level 6 — Production Incidents (5 built / 20 planned)
Combines two or more mechanisms from Levels 1-5 into a single synthetic
incident: a realistic on-call page, symptoms only, no hint which
subsystem is at fault. [`labs/incidents/`](labs/incidents)

## Status

**80 of ~120 labs are written.** Levels 1 (Linux Basics) and 2
(Networking) are now fully built out for their current scope — 21/21 and
25/25 respectively. Level 3 (Storage) is seeded at 7 labs, Level 4
(Databases) has both MySQL (8/8) and Postgres (5/5) complete for their
current scope, Level 5 (Kubernetes) is complete for its planned 9, and
Level 6 (Incidents) has a 5-incident seed.

Every lab across every level now has full `check.sh`/`reset.sh`
automation. Most labs also have `setup.sh`; the containerlab-based
networking labs (03 onward) instead build the "before" state live via
the README's own steps, matching that sub-format's existing convention.

**None of this has been run end-to-end on a live VM yet** — every command
was written from careful reasoning about real tool behavior, not from an
actual test run. Treat it as a first draft to dry-run before recording,
not verified fact. See [`CONTEXT.md`](CONTEXT.md) for the full list of
what's flagged as needing a live check — a few items are flagged as
genuinely low-confidence (exact `dm-flakey` argument syntax, `kind`+etcd
quota behavior, a couple of timing-sensitive PostgreSQL challenges) and
worth prioritizing in a dry run.

Remaining to reach ~120: Level 3 (Storage, more topics beyond the current
7), Level 4 (7 more topics across both databases), Level 5 (11 more
topics), Level 6 (15 more incidents). Levels 1 and 2 are done for now —
their original target counts (20 and 25) have been met.

## Prerequisites
- A Linux VM (tested on \[fill in your distro/version\])
- `iproute2`, `unshare`/`nsenter` (util-linux), root/sudo access
- Level 2 (Networking): Docker + [containerlab](https://containerlab.dev) + FRR
- Level 3 (Storage): `lvm2`, `xfsprogs`, `e2fsprogs`, `mdadm`, `sysstat`, `fio`, `smartmontools`, `dmsetup`
- Level 4 (Databases): MySQL/MariaDB or Docker + docker-compose, depending on the lab
- Level 5 (Kubernetes): Docker + [`kind`](https://kind.sigs.k8s.io/) + `kubectl`
- Level 6 (Incidents): Docker + docker-compose, containerlab for one incident
