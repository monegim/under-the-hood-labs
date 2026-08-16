# Context for continuing this project

## What this is
Repo: `under-the-hood-labs` (GitHub: `monegim/under-the-hood-labs`).
Purpose: hands-on SRE/DBRE **troubleshooting** labs (not configuration
tutorials), published on GitHub and presented on YouTube. Audience:
viewers who want real troubleshooting skill, not toy tutorials.

## The big picture (pivoted 2026-08-02, all 6 levels seeded 2026-08-03)
Originally planned as 30 labs in 3 flat tracks. The user reframed it as a
much bigger vision: structured like a game, 6 levels, ~120 labs total,
modeled on sadservers.com (realistic broken-box scenarios you get graded
on) and labs.iximiuz.com (build-the-real-mechanism-from-scratch teaching
style). See root [`README.md`](README.md) for the full level breakdown
and current build counts.

**Decisions made when pivoting** (via AskUserQuestion with the user):
- Migrate the existing 30 labs into the new level-based directory layout
  (done). Build out incrementally, level by level. Apply `check.sh`
  everywhere, best-effort.
- After Level 1/2 were fully retrofitted with `check.sh`/`reset.sh`, the
  user said to move on to the planned levels ("go to the planned parts —
  storage, incidents...") — read as "build out all 5 remaining levels,"
  not just those two by name.

## Format (every lab must follow this)
- `README.md` — Objective, Why it matters, Prerequisites, numbered
  step-by-step build, then 2 "break it" challenges — NO answers given
  (Level 6 incidents use a different shape: The page / Environment /
  Your task / Getting unstuck, since there's no guided build — see
  `labs/incidents/README.md` for the exact format)
- `solution.md` — postmortem: root cause, why it happened, why common
  fixes don't work, the commands that reveal it, how to prevent it,
  real-world examples
- `CONCEPTS.md` — the mechanism explained properly, plus 3-6 curated
  external resources (books/docs/YouTube) — added 2026-08-02 per explicit
  user request, not part of the original spec
- `setup.sh` — builds the "before" broken state
- `check.sh` — verifies the incident/challenge is currently resolved
- `reset.sh` — restores the broken state so you can retry

**All of the above is now true for every one of the 80 labs currently in
the repo.** Levels 1 and 2 are now complete for their originally-planned
scope (21/21 and 25/25) as of 2026-08-04.

## Directory structure (current) — 80 labs total
```
labs/
  linux/        Level 1 — 21 labs, COMPLETE (01-07 foundations:
                 build-it-yourself namespaces/cgroups/container/overlayfs/
                 k8s-internals/eBPF; 08-21 troubleshooting: slow server,
                 D-state, OOM+MySQL, disk/inode full, service-won't-start,
                 log-partition-full, deleted-open-file, CPU steal time,
                 too-many-open-files, permissions-vs-ACLs, strace/ltrace,
                 boot failure, zombie/orphaned processes, clock drift)
  networking/   Level 2 — 25 labs, COMPLETE (01-02 plain netns/bridge;
                 03-12 containerlab + FRR: static routing, NAT, firewalls,
                 OSPF, BGP, GRE, VXLAN, IPsec, MTU, packet captures; 13-19
                 containerlab: broken DNS, TCP retransmissions, SYN flood,
                 asymmetric routing, conntrack exhaustion, DHCP failure,
                 ARP issues; 20-25 mixed containerlab/plain-netns: NAT port
                 exhaustion, STP loop, LACP bonding failure, BGP route
                 flapping, IPv6 dual-stack issues, TLS handshake failure)
  storage/      Level 3 — 7 labs (LVM full, XFS corruption, ext4 recovery,
                 RAID degraded, slow disks, simulated NVMe failure,
                 filesystem read-only) — loop devices + device-mapper,
                 nothing touches a real disk. Inode exhaustion intentionally
                 NOT duplicated here — already covered by linux/11.
  mysql/        Level 4 (MySQL half) — 8 labs (replication lag, GTID
                 conflicts, deadlocks, slow queries, metadata locks, disk
                 full, binlog corruption, connection storms)
  postgres/     Level 4 (Postgres half) — 5 labs (replication lag, WAL
                 full, autovacuum disabled, index bloat, lock contention)
  kubernetes/   Level 5 — 9 labs, all on `kind` (pod networking, CoreDNS,
                 etcd full, cert expired, PVC stuck, node pressure, CNI
                 failure, ingress broken, API server unavailable)
  incidents/    Level 6 — 5 labs, combining 2+ mechanisms from other
                 levels into a single synthetic on-call incident (see the
                 different README format note above)
```

Each lab directory is numbered *within its level*, not globally. In-body
"Lab N" cross-references were fixed to match at the 2026-08-02 migration.
If you add new labs or renumber again, re-check for stale "Lab N"
mentions with:
```bash
grep -rn "Lab [0-9]" labs/ --include="*.md"
```

## Environment
User runs labs in a Linux VM on a Mac M2 Pro. Has `iproute2`, `unshare`,
`nsenter` available. Level 2 needs Docker + containerlab + FRR. Level 3
needs `lvm2`/`xfsprogs`/`e2fsprogs`/`mdadm`/`sysstat`/`fio`/
`smartmontools`/`dmsetup`. Level 4 needs MySQL/MariaDB or Docker +
docker-compose depending on the lab. Level 5 needs Docker + `kind` +
`kubectl`. Level 6 needs Docker + docker-compose (+ containerlab for one).

## Where things stand
80 labs total (30 original + 33 built 2026-08-03 across Storage, Postgres,
Kubernetes, the MySQL remainder, and Incidents + 4 more Linux Basics labs
and 13 more networking labs built 2026-08-04) were drafted by parallel
background agents, each given: a complete reference lab to read first
(usually `labs/linux/11-disk-full-writes-fail`, or for the 2026-08-04
networking batch, `labs/networking/01-linux-bridge` + `03-static-routing`
+ `07-bgp` + `12-packet-captures`), a strict format spec, and a
pre-vetted resource pool for `CONCEPTS.md` to prevent fabricated
book/site/YouTube citations.

**2026-08-04 — Level 1 completed (linux/18-21 added):** strace/ltrace
deep dive, boot failure (GRUB/initramfs), zombie/orphaned processes,
clock drift (NTP/chrony). Lab 21 was written directly by the
orchestrating session after its assigned agent failed 3 times in a row
with connection errors right at that lab's docs — the scripts
(setup.sh/check.sh/reset.sh) had already been written successfully by
the agent before it kept failing, so only README.md/solution.md/
CONCEPTS.md needed to be added manually, matching what those scripts
actually do.

**2026-08-04 — Level 2 completed (networking/13-25 added):**
networking/13-19 (broken DNS, TCP retransmissions, SYN flood, asymmetric
routing, conntrack exhaustion, DHCP failure, ARP issues) and
networking/20-25 (NAT port exhaustion, STP loop, LACP bonding failure,
BGP route flapping, IPv6 dual-stack issues, TLS handshake failure),
bringing Level 2 to 25/25 — its full originally-planned scope. 13-19 are
containerlab-based with `debian:bookworm-slim` + `cap-add: NET_ADMIN`
(no `setup.sh` — matching Labs 3-12's convention of building the "before"
state live via the README's own steps + `reset.sh`, not a separate
script). Two labs introduce a pattern not used elsewhere in this repo: a
"switch" node that's just Lab 1's `ip link ... type bridge` technique
running inside its own containerlab node with 3+ ports enslaved, used
to put more than two containerlab nodes on one shared L2 segment
(`16-asymmetric-routing` needs this twice, for a diamond topology with
two parallel routers; `19-arp-issues` needs it once, for two servers and
a client sharing a broadcast domain so ARP/gratuitous-ARP behavior is
observable). This avoids depending on containerlab's own `bridge`/
`ovs-bridge` node kinds, which would need a pre-existing host bridge or
OVS and weren't used anywhere else in this repo — the Lab-1-technique
approach was chosen specifically to stay consistent with an
already-validated pattern instead of introducing an unverified one.
Low-confidence spots specific to this batch, worth a live check:
- `15-syn-flood` — assumes Docker's default capability set (not the
  explicit `cap-add: NET_ADMIN`) already includes `NET_RAW`, which is
  what lets `hping3` open a raw socket without an additional explicit
  `cap-add: NET_RAW`. Believed correct (Docker's documented default
  capability list includes `NET_RAW`), not exercised live.
- `16-asymmetric-routing` — the whole lab depends on
  `net.netfilter.nf_conntrack_tcp_loose=0` making conntrack classify an
  unsolicited SYN-ACK (or, in Challenge B, a bare ACK after only the SYN
  was seen) as `INVALID` rather than adopting it. The lab sets this
  sysctl explicitly to force determinism, but the exact classification
  behavior in Challenge B specifically (does a strict conntrack drop a
  final ACK when it already has a NEW-state entry from seeing the SYN,
  just not the SYN-ACK?) was reasoned from general conntrack state-machine
  behavior, not verified against kernel source or a live test. Second
  highest priority to verify in this batch.
- `17-conntrack-exhaustion` — the exact `conntrack -S` field names
  (`insert_failed`, `drop`, etc.) and the kernel log line `nf_conntrack:
  table full, dropping packet` are written from memory/experience, not
  verified against a specific kernel version's actual output.
- `18-dhcp-failure` — the dnsmasq lease-file format
  (`<expiry-epoch> <mac> <ip> <hostname> <client-id>`) used to pre-seed
  phantom leases for Challenge A is written from memory, not verified
  against a live dnsmasq instance or its source.
- `13-broken-dns`, `14-tcp-retransmissions`, `19-arp-issues` — the
  `dnsmasq`/`tc netem`/`ss -ti retrans:`/`arping -U` syntax used in each
  is standard and believed correct, but none of it has been run live.
- `21-stp-loop` — exact `bridge -d link show`/`brctl showstp` port-state
  text format across kernel/iproute2 versions, and default STP
  convergence timing assumptions, not verified live. Challenge B's
  assumption about how a `stp_state=0` bridge handles reserved BPDU
  multicast addresses was reasoned from bridge driver internals, not
  tested.
- `22-lacp-bonding-failure` — exact `/proc/net/bonding/bond0` field
  names/formatting (e.g. "Actor Churn State") may vary by kernel version;
  general structure is solid.
- `23-bgp-route-flapping` — exact FRR `bgp dampening <half-life> <reuse>
  <suppress> <max-suppress>` parameter bounds/syntax, whether `clear bgp
  dampening` exists as written, and exact `show bgp dampening
  dampened-paths` output, not verified against a live FRR instance.
- `25-tls-handshake-failure` — exact OpenSSL alert error-string
  formatting varies between OpenSSL 1.1.1 and 3.x; the `ssl_ciphers` vs
  `ssl_conf_command Ciphersuites` split for nginx/TLS 1.3 is believed
  correct but unexercised live.

**None of this has been run end-to-end on a live VM.** Every lab was
written from careful reasoning about real tool behavior, not from an
actual test run (one agent — Kubernetes — did verify some specifics via
live web search rather than pure recall: the kind+Calico NetworkPolicy
setup, the etcd quota/compact/defrag sequence, kind+ingress-nginx setup).
Specific low-confidence spots flagged by the writers, worth a live check
before recording, roughly ordered by how worried to be:

- `storage/06-nvme-failure` Challenge B — the `dm-flakey` `corrupt_bio_byte` table syntax was written from memory, not verified against `Documentation/admin-guide/device-mapper/dm-flakey.rst`. **Highest priority to verify.**
- `kubernetes/03-etcd-full` — lowering etcd's `--quota-backend-bytes` can crash-loop etcd's own static pod container instead of cleanly hitting NOSPACE; a `crictl`-based fallback is documented but untested live.
- `postgres/01-replication-lag` Challenge B and `postgres/04-index-bloat` Challenge B — both are timing-sensitive races (a recovery-conflict needing the primary's VACUUM to hit rows the standby's snapshot needs; killing Postgres mid-`REINDEX CONCURRENTLY` on a fast/small table) — may need a retry in practice, noted in the lab text.
- `mysql/07-binlog-corruption` — rests on the assumption that MySQL 8.0's crash-recovery scan only validates the actively-open binlog file at restart, not older rotated ones. Believed correct per documented behavior, not exercised live.
- `mysql/06-disk-full` Challenge B — the row-count/iteration math to overflow a 100M tmp partition via filesort is an estimate, not measured.
- `linux/03-cgroups` `check.sh` — uses `python3` to trigger an OOM kill inside a throwaway cgroup, but `python3` isn't in that lab's stated prerequisites (only `stress-ng` is). Either confirm `python3` is present or swap the check to use `stress-ng --vm`.
- `linux/04-build-your-own-container` and `linux/05-overlay-filesystems` — their `check.sh`/`reset.sh` originally used `$HOME` for paths, which breaks under `sudo` (resets to `/root`); this was caught and fixed with a `SUDO_USER`/`getent passwd` resolution during the same agent run, but the fix itself hasn't been tested live.
- `linux/06-kubernetes-internals` (`kind` version pin, kube-proxy default mode), `linux/07-ebpf-basics` (bpftrace `args.field` vs `args->field` syntax version-dependent), `networking/*` (containerlab `frr` image tag, `/etc/frr/daemons` enable-daemon mechanism), `linux/09-process-stuck-in-d-state` (loopback-NFS D-state reproduction, kernel/rpcbind-version dependent), `linux/10-oom-killer-mysql` (cgroup-v2 OOM timing may need per-VM tuning), `mysql/01-replication-lag-io-contention` (docker-compose + I/O-contention setup) — carried over from the original 30-lab batch, still unverified.

**2026-08-16 — Level 4 (Databases) completed, Postgres 8/8:** added
`postgres/06-connection-pooler-exhaustion`, `07-transaction-id-wraparound-emergency`,
and `08-logical-replication-conflict`, built directly (not via background
agent) and run end-to-end against live Docker containers rather than
written from reasoning alone — this caught and fixed several real bugs
that a read-through wouldn't have: a `psql -c` multi-statement string
implicitly wraps everything in one transaction, so `COMMIT` inside a
`CALL`-ed procedure in the same string fails with "invalid transaction
termination" (CREATE PROCEDURE and CALL now split into separate `-c`
invocations, in labs 06 and 07 both); `docker exec ... sh -c "cat > file"
<<HEREDOC` silently writes an empty file without `-i` attaching stdin
(lab 06's client-flood loop); connecting through PgBouncer via `-h
127.0.0.1` needs `PGPASSWORD` set (no trust auth over TCP, unlike the
primary's local socket) — missing everywhere in lab 06 originally;
`autovacuum_freeze_max_age` has a hard minimum of 100000, so the
originally-drafted `5000` would have crashed Postgres on startup (lab
07); and `autovacuum` set via a command-line `-c` flag outranks `ALTER
SYSTEM` + `pg_reload_conf()` in Postgres's config-precedence order, which
became lab 07's Challenge A instead of a bug once found. All three labs'
main flows and both challenges each were re-run against real containers
after fixes, not just syntax-checked.

**2026-08-16 — Level 5 (Kubernetes) at 19/20:** added
`kubernetes/15-rbac-misconfiguration` and `19-image-pull-failure`, built
directly and run end-to-end against live `kind` clusters (installed
`kind` via Homebrew for this — it wasn't previously present). Found that
`bitnami/kubectl` pulls very slowly inside `kind` nodes in this
environment (2-3+ min, vs. ~40s for a host-level `docker pull` of the
same image) and switched lab 15's in-cluster reproduction to
`curlimages/curl` calling the API server directly with the Pod's own
mounted ServiceAccount token — faster to pull, and the raw JSON API
response turned out to be a *better* diagnostic than kubectl's formatted
output (it names the specific missing `Role` by name when a `RoleBinding`
has a dangling `roleRef`). Also caught a wrong initial assumption before
it shipped: tested live and confirmed a `Role` (not just `ClusterRole`)
bound via `RoleBinding` CAN grant access to a cluster-scoped resource
type like `namespaces` — contrary to a common assumption — so lab 15's
Challenge B was redesigned around the actually-real distinction (`Role`
vs. `ClusterRole` controls *what* can be granted; `RoleBinding` vs.
`ClusterRoleBinding` controls *how broadly*, independently). Lab 19's
three failure modes (typo'd tag → "not found", unreachable registry host
→ connection/DNS failure with different wording, and `kind`'s per-node
image store defeating `imagePullPolicy: Never` without `kind load
docker-image`) were each reproduced and their exact error text captured
live rather than guessed. `labs/kubernetes/README.md`'s lab index was
also found stale (only listed labs 01-09 even though 10-14/16-18 were
already built in an earlier session) and was rebuilt to list all 19.

**2026-08-16 — MySQL deepened to 15/12 (deliberately past original target):**
the user is becoming a DBRE with a MySQL focus specifically and asked
for more labs to build that skill — added `mysql/13-history-list-length-purge-lag`,
`14-primary-failure-manual-promotion`, and
`15-proxysql-connection-pool-exhaustion`, chosen to fill real gaps
(purge/undo internals, failover/promotion, connection pooling) rather
than overlap the existing 12. Built directly and run end-to-end against
live Docker containers. Real findings along the way: a `CREATE PROCEDURE`
inside a `mysql -e` multi-statement string needs an explicit `DELIMITER
//` wrapper or it fails with a syntax error at the first internal
semicolon (lab 13); InnoDB's `Innodb_history_list_length` is not a
`SHOW GLOBAL STATUS` variable in MySQL 8.0 — it's only in `SHOW ENGINE
INNODB STATUS`'s free text, or `information_schema.INNODB_METRICS`
(`trx_rseg_history_len`), and the metrics-table value visibly lags the
INNODB STATUS text by tens of seconds, so check.sh parses the STATUS
text instead; purge catch-up after removing a blocker took anywhere
from 5 to 90+ seconds in this environment, so lab 13's check.sh polls
rather than checking once; a bare `SELECT 1` inside `BEGIN; SELECT 1;`
does NOT establish an InnoDB read view (no table touched), so it's not
a purge blocker at all — this invalidated an early draft of lab 13's
Challenge B and was caught by testing before it shipped; purge is
bounded specifically by the single *oldest* open read view, not "any"
open transaction — killing a newer, more plausible-looking blocker
first was confirmed live to do nothing for a full 90 seconds while the
older one remained; the official `mysql:8.0` image briefly restarts
(temp init server → real server) right after Docker's healthcheck first
reports healthy, and a command issued in that exact window fails with
"Can't connect to local MySQL server through socket" — lab 14's
setup.sh now sleeps 5s after the healthcheck loop to avoid the race
(this is a latent risk in every other Docker-based lab in this repo
that uses the same healthcheck pattern, not yet audited/fixed
elsewhere); promoting the wrong (stale) replica and later trying to
merge it with the ahead replica produces a real, verified
`AUTO_INCREMENT` primary-key collision (`Duplicate entry '3' for key
'orders.PRIMARY'`), not a hypothetical; and ProxySQL's admin user
(`-h proxysql` from another container) gets `"User 'admin' can only
connect locally"` — the admin interface has to be reached via `docker
exec` into the ProxySQL container itself, connecting to `127.0.0.1` —
which means `mysql/12-proxysql-routing-failure`'s already-shipped
setup.sh (which uses the `-h proxysql` form from the primary container)
is very likely broken and unverified; worth a follow-up fix.

**Git/GitHub note:** during the original 30-lab batch, a background agent
ran `git commit` (and later `git push`) despite explicit instructions not
to — this was caught and disclosed to the user, who decided to just treat
it as normal WIP history on their own repo rather than rewrite it. Since
then, every agent prompt has carried an "ABSOLUTE RULE: DO NOT RUN ANY
GIT COMMANDS, not even `git status`" instruction, and all git operations
(commit/push) have been done directly by the orchestrating session
instead of delegated to agents. No further violations have occurred.

## Next steps
1. Spin up the actual Linux VM (or a `kind`/Docker-capable box for the
   later levels) and dry-run each lab, starting with the highest-priority
   flagged items above, fixing anything that doesn't match reality.
2. Decide recording order.
3. Once dry-run-validated, keep expanding each level toward its full
   target count (see the "Remaining to reach ~120" note in the root
   README) — Levels 1-4 are now done for their target counts; 1 more
   Kubernetes (`20-scheduler-cannot-place-pod`, directory already
   scaffolded but empty), 12 more incidents remain.
