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

### Level 1 — Linux Basics (17 built / 20 planned)
Not "how to use `ps`" — how Linux actually works under a real incident.
Split into two halves: **foundations** (build the underlying mechanism
yourself — namespaces, cgroups, overlayfs, a container from scratch,
eBPF) and **troubleshooting** (a simulated production incident per lab).
[`labs/linux/`](labs/linux)

Tools: `ps`, `top`/`htop`, `vmstat`, `iostat`, `strace`, `lsof`, `journalctl`, `/proc`, `systemctl`

### Level 2 — Networking (12 built / 25 planned)
Every SRE should be comfortable debugging packets. [`labs/networking/`](labs/networking)

Tools: `tcpdump`, `ip`, `ss`, `bridge`, `conntrack`, `iptables`/`nftables`, `dig`, `mtr`, `tracepath`

### Level 3 — Storage (0 built / 15 planned)
LVM full, XFS corruption, ext4 recovery, RAID degraded, slow/failing disks,
read-only filesystems, inode exhaustion. [`labs/storage/`](labs/storage)

### Level 4 — Databases (1 built / 20 planned)
Exactly what a DBRE sees. MySQL (replication, GTIDs, deadlocks, slow
queries, metadata locks, binlog corruption, connection storms) and
PostgreSQL (replication lag, WAL full, autovacuum, index bloat, lock
contention). [`labs/mysql/`](labs/mysql) · [`labs/postgres/`](labs/postgres)

### Level 5 — Kubernetes (0 built / 20 planned)
Pod networking, CoreDNS failure, etcd full, expired certs, stuck PVCs,
node pressure, CNI failure, broken ingress, API server unavailable.
[`labs/kubernetes/`](labs/kubernetes)

### Level 6 — Production Incidents (0 built / 20 planned)
Combines everything above into a single synthetic incident: logs,
metrics, and a broken environment — no hints, find the root cause.
[`labs/incidents/`](labs/incidents)

## Status

**30 of ~120 labs are written** (Levels 1, 2, and a first Level 4 seed).
Levels 1 and 2 (all 30 of those labs) now have full `check.sh`/`reset.sh`
automation. Levels 3 (Storage), 5 (Kubernetes), 6 (Incidents), and the
rest of Level 4 (Postgres + the remaining MySQL topics) are actively being
built out with `check.sh`/`reset.sh` included from the start.

**None of this has been run end-to-end on a live VM yet** — every command
was written from careful reasoning about real tool behavior, not from an
actual test run. Treat it as a first draft to dry-run before recording,
not verified fact. See [`CONTEXT.md`](CONTEXT.md) for the full list of
what's flagged as needing a live check.

## Prerequisites
- A Linux VM (tested on \[fill in your distro/version\])
- `iproute2`, `unshare`/`nsenter` (util-linux), root/sudo access
- Level 2 (Networking): Docker + [containerlab](https://containerlab.dev) + FRR
- Level 4 (Databases): MySQL/MariaDB, Docker + docker-compose for the multi-node labs
