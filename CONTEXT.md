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

**2026-08-17 — fixed `mysql/12-proxysql-routing-failure`, MySQL now 17/12:**
the user asked to fix the ProxySQL routing-failure bug flagged the
previous session, and to keep adding MySQL DBRE labs. The fix uncovered
two more real, deeper issues in the same already-shipped lab, live-tested
before and after each fix:
1. Every admin-interface command used `docker exec lab12-primary mysql -h
   proxysql -P 6032 ...` (cross-container). ProxySQL's `admin` user
   rejects any connection that isn't local to the ProxySQL process itself
   — confirmed via a scratch two-container test — so every one of these
   commands failed with `User 'admin' can only connect locally`. Fixed by
   changing all 14 occurrences across setup.sh/check.sh/README.md/solution.md
   to `docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 ...` (exec
   into the ProxySQL container, connect to its own localhost). The
   client-traffic port (6033) does NOT have this restriction — confirmed
   separately — so those commands were left as cross-container as
   originally written.
2. Challenge A's reproduction wrapped the locking `SELECT ... FOR UPDATE`
   in `BEGIN; ...; COMMIT;` — live-tested and found this made the
   (still-broken) query rules succeed instead of failing, because
   ProxySQL pins every statement inside an open transaction to whichever
   backend connection the transaction is already using, so the broken
   rule-ordering bug never got a chance to misroute it. Fixed by
   reproducing as a standalone autocommit statement instead (which
   correctly fails), and added the transaction-pinning contrast as a
   documented follow-up in the same challenge, since it's a genuine,
   valuable, separately-verified lesson.
3. Challenge B's premise (`mysql_replication_hostgroups` with the
   original swapped writer/reader hostgroup numbers "silently un-fixing"
   a manual repair on a timer) did NOT reproduce under repeated live
   testing — waited 60+ seconds, toggled real `read_only` status on the
   primary directly, tried multiple variations; `mysql_servers` stayed
   correctly assigned every time. Rather than ship an unverified/likely-
   wrong technical claim, Challenge B was redesigned around a
   different, fully live-verified ProxySQL mechanism instead: query
   result caching (`cache_ttl` on a query rule) causing a read
   immediately after a correctly-routed write to return stale data,
   diagnosed via `stats_mysql_query_digest` showing `hostgroup = -1`
   (ProxySQL's marker for "answered from cache, no backend touched").
   `CONCEPTS.md` and `solution.md` were both rewritten to match.

Then added `mysql/16-auto-increment-exhaustion` and
`17-point-in-time-recovery`, both built and verified end-to-end against
live Docker containers. Real findings: `SHOW TABLE STATUS`'s
`Auto_increment` column can show a stale/cached value for InnoDB
immediately after writes — `SHOW CREATE TABLE` is the reliable, always-
live source, used throughout lab 16's scripts instead; converting
`TINYINT` to `TINYINT UNSIGNED` genuinely doubles usable AUTO_INCREMENT
headroom for zero storage cost (verified: exhaustion at 127 vs. 255);
`auto_increment_increment=10` causes a verified ~10x-faster ID
consumption rate than row count alone predicts. For lab 17: the official
`mysql:8.0` Docker image does not ship `mysqlbinlog` at all (verified via
`ls /usr/bin`) — worked around with a separate Debian `tools` container
providing `mariadb-binlog`, verified to correctly decode MySQL 8.0
ROW-format binlogs (treating MySQL's own GTID event as a safely-ignorable
pass-through) for position-based (not GTID-based — that compatibility
was not tested and is not relied on) start/stop-position replay; found
and worked around a real cross-tool gotcha where `mariadb-binlog`'s
decoded session-variable preamble includes `check_constraint_checks`,
which MySQL doesn't recognize, silently aborting a naive `| mysql` pipe
unless `--force` is used — this became Challenge A. Position-based
"skip just the bad transaction, keep everything before and after it"
recovery (two replay passes around a gap) was verified end-to-end and
became Challenge B.

A third lab — MySQL InnoDB tablespace corruption + `innodb_force_recovery`
— was attempted and abandoned after significant live testing. Corrupting
an `.ibd` file's data page (via `dd`, matching the established pattern
from `07-binlog-corruption`) reliably crashed the entire `mysqld`
process on any query touching the table, and this did NOT become
recoverable even at `innodb_force_recovery=6` (the maximum level) —
every level from 1 through 6 was tried live. Rather than ship a lab
whose "fix" step doesn't actually work, this topic was dropped for now.
If revisited, a gentler/more targeted corruption (flipping a handful of
bits rather than overwriting 512 bytes of pure random data, and/or
targeting bytes confirmed to fall within row-data rather than any
page structure) would need to be found and verified first — this may
be a case where `innodb_force_recovery` genuinely cannot save a page
this badly corrupted, in which case the lab's honest lesson would need
to become "know when force_recovery can't save you and a restore from
backup is the only path," which is itself defensible but changes the
lab's shape significantly from what was originally planned.

**2026-08-17 — `mysql/18-innodb-corruption-recovery` shipped (18/12),
second attempt at this topic:** the previous session's attempt at an
InnoDB corruption lab was abandoned after `dd`-overwriting 512 bytes of
a page with pure random data reliably crashed `mysqld` unrecoverably,
even at `innodb_force_recovery=6`. This session retried with a much
gentler fault — corrupting only the page's 4-byte checksum field,
leaving every actual row byte intact — and it worked cleanly: crashes
without `innodb_force_recovery`, fully recovers (all rows, verified via
`CHECKSUM TABLE`) at the lowest level (`1`). Real findings from
extensive live testing:
- `docker-compose.yml`'s primary service takes `--innodb-force-recovery=${FORCE_RECOVERY:-0}`,
  matching the env-var-override pattern from labs 06/15 — the fix is
  `docker compose stop primary && FORCE_RECOVERY=1 docker compose up -d primary`,
  no raw `docker run` needed.
- `innodb_force_recovery > 0` blocks all writes (`INSERT`, and anything
  implying one like `CREATE TABLE ... AS SELECT`) with a clean
  `ERROR 1881`, but does NOT block `DROP TABLE` — confirmed by direct
  testing, not assumed from docs. This became Challenge B: the full
  recovery has to cross a server restart (dump while still in recovery
  mode → copy the dump to the host, since the container gets recreated
  → restart clean → copy the dump back in → restore) because writing the
  salvaged data back requires being fully out of recovery mode.
- A genuinely corrupted row (not just checksum) still crashes at
  `innodb_force_recovery=1` and `=4`. At the maximum level (`6`), it did
  NOT crash — but `SELECT COUNT(*)` and an actual `SELECT id FROM
  orders` enumeration returned two different, both-wrong numbers, and
  the raw id list included a nonsense value no `AUTO_INCREMENT` could
  have produced. This became Challenge A: force_recovery=6 not crashing
  is not evidence of a successful recovery, and cross-checking two
  different query shapes against each other is the only way to catch it
  without an independent backup to compare against.
- An originally-planned Challenge A ("binary-search the bad id range,
  then salvage everything outside it with a single `WHERE id < x OR id
  > y` query") was tested repeatedly and found **not reliably
  reproducible** — the exact same query against what should have been
  identical corrupted state sometimes returned instantly, sometimes hung
  indefinitely (with `SHOW PROCESSLIST` showing queries stuck
  `executing` for minutes, never crashing or completing), depending on
  whether the server had already crashed once against that exact
  corrupted page in the current container's lifetime. This was dropped
  rather than shipped as an unreliable "expected exact output" exercise
  — the corrupted-row-content scenario was kept, but reframed around the
  force_recovery=6 silent-wrong-data finding instead, which reproduced
  reliably every time it was tested.
- Confirmed `mysqldump --master-data=2`/`mysqlbinlog`-adjacent findings
  from lab 17 generalize: the official `mysql:8.0` image's minimal
  Oracle-Linux-based userland lacks `which`, and `innochecksum` isn't
  present either (checked directly via `ls`, not inferred).

**2026-08-17 — Level 1 (Linux Basics) grew to 27/21: two performance
labs added.** User asked for Linux performance-optimization labs.
`perf`/flame-graph profiling was the first pick but doesn't work in
this environment at all — Docker Desktop's kernel identifies as
`6.12.76-linuxkit`, a custom build with no matching `linux-tools`
package in any standard distro repo (confirmed directly: `apt-get
install linux-tools-$(uname -r)` fails). Pivoted to two topics fully
verified via a `--privileged` container instead (chosen because THP is
a host-wide, non-namespaced kernel feature — a privileged container's
access to it is equivalent to a real VM's for this specific purpose,
not a namespaced approximation):
- `linux/26-transparent-hugepages` — `always` mode backs a plain
  mmap+touch workload (no API call requesting it) with real 2MB pages,
  confirmed via `/proc/vmstat`'s `thp_fault_alloc` counter increasing.
  `madvise` mode correctly leaves that same workload alone while still
  honoring an explicit `madvise(MADV_HUGEPAGE)` call from a different
  test program; `never` overrides even that explicit request with no
  error reported anywhere. An earlier attempt to demonstrate this via
  RSS memory bloat (many small sparse `mmap` regions) went nowhere —
  Python's `mmap.mmap()` doesn't guarantee 2MB alignment, so the
  allocations were never THP-eligible regardless of the sysfs setting;
  switched to counter-based verification (`thp_fault_alloc`,
  `/proc/<pid>/smaps_rollup`'s `AnonHugePages`) instead, which is also
  the more realistic diagnostic technique.
- `linux/27-cfs-cpu-throttling` — a container limited to `cpus: 0.5`
  makes a fixed CPU workload (2 threads, 4M fibonacci ops via
  `stress-ng`) take ~5x longer than unconstrained (322ms vs 67ms,
  measured directly), while `docker stats` reports ~25% CPU throughout
  — nowhere near the 50% quota, unremarkable-looking. Only
  `/sys/fs/cgroup/cpu.stat`'s `throttled_usec` shows the real story.
  Confirmed live that sizing concurrency off `nproc` (which reports the
  *host's* CPU count inside a container, not the cgroup quota) instead
  of the actual quota makes throttling measurably worse, not better:
  the same total work spread across `nproc` (10) threads instead of 2
  took ~2.3x longer and accumulated over 10x more throttled time.

**2026-08-17 — MySQL grew to 20/12: two ProxySQL labs added
(`19-proxysql-auth-mismatch`, `20-proxysql-runtime-not-persisted`),
each fully live-Docker-verified, each turning up a real surprise
mid-build.**

`19-proxysql-auth-mismatch` — the scenario: `appuser`'s password is
rotated directly on the MySQL backend without updating ProxySQL's
`mysql_users` copy. The first working version of `setup.sh` did NOT
actually reproduce the incident: it ran a "confirm baseline works"
query before rotating the password, which caused ProxySQL to pool a
backend connection using the still-valid old password — and MySQL does
not invalidate an already-authenticated session just because the
user's password changes later, so the pooled connection kept working
fine through the rotation. `SELECT 1` through ProxySQL kept succeeding,
and `check.sh` incorrectly reported `[PASS]` immediately after setup.
Root-caused live via `stats_mysql_connection_pool` (`ConnFree: 1`,
`ConnOK: 1`), confirmed by directly `KILL`ing the pooled connection's
PID on the backend (`information_schema.processlist`), which forced
ProxySQL to open a fresh connection and correctly surfaced `ERROR 1045
... Access denied for user 'appuser'@'172.26.0.3'` — no `ProxySQL
Error:` prefix, confirming it's a genuine backend-forwarded rejection,
not ProxySQL's own client-facing check. `setup.sh` now performs this
same kill deterministically as its last step, so the incident
reproduces reliably on every fresh run. `check.sh` was also changed to
read `appuser`'s password live from ProxySQL's `mysql_users` table
rather than hardcoding it, since ProxySQL's `mysql_users.password`
field does double duty as both the client-facing and backend-facing
credential — this makes the check correct regardless of which
direction the eventual fix goes (sync ProxySQL forward, or roll the
backend back). Challenge A (client sends the wrong password) was
confirmed to produce a visibly different, `ProxySQL Error:`-prefixed
rejection with `@127.0.0.1` as the host — a clean, live-verified
signal for telling client-side vs. backend-side auth failures apart.
Challenge B (broken `monitor` user password) initially looked
inconclusive — `monitor.mysql_server_ping_log` kept reporting success
for a full 8-second wait — until digging into
`mysql-monitor_ping_interval` (10s) vs. `mysql-monitor_connect_interval`
(60s, the default) explained why: the ping check reuses a persistent,
already-authenticated connection exactly like the main incident's
connection pool, so it never re-authenticates and never catches a
broken password; only the connect check opens a genuinely fresh
connection each interval, and it needs a full 60-second wait (not "a
few seconds," the first assumption) before `monitor.mysql_server_connect_log`
shows the failure. `mysql_servers.status` was confirmed to stay
`ONLINE` throughout, live-explained by
`mysql-monitor_ping_max_failures` existing as a variable (governing
ping-triggered shunning) with no connect-check equivalent at all.

`20-proxysql-runtime-not-persisted` — grew directly out of an
unresolved discrepancy from the lab 19 investigation: an earlier
`docker compose restart proxysql`, run mid-troubleshooting before
`setup.sh` had a `SAVE MYSQL USERS TO DISK` step, produced an
unexpected `ProxySQL Error:`-prefixed rejection for a user whose
client-side password had never changed. Investigating this directly
(rather than dismissing it) revealed the real mechanism and became
this lab's entire premise: restarting ProxySQL without ever having run
`SAVE ... TO DISK` doesn't just lose the in-memory RUNTIME config — it
reverts the *working* config tables (`mysql_users`, `mysql_servers`)
to empty too, confirmed by directly querying both `mysql_users` and
`disk.mysql_users` (ProxySQL's admin interface exposes a real,
separately queryable `disk` database backed by its on-disk SQLite
file) immediately after a restart and finding both sides empty. Two
challenges were live-verified end to end: Challenge A confirmed `SAVE
... TO DISK` is genuinely per-category (`mysql_servers` persisted,
`mysql_users` didn't, because only `SAVE MYSQL SERVERS TO DISK` was
run) — after a restart, the servers table came back fully intact while
the users table came back empty. Challenge B confirmed `LOAD MYSQL
USERS FROM DISK` is a real, distinctly-named footgun — it moves data
the *opposite* direction from every other command used in the lab (disk
→ working tables, overwriting them), and running it while an unsaved,
live change (`urgentuser`) sits in the working tables silently deletes
that change with no warning; verified precisely which user survived
(the previously-saved one) and which didn't (the not-yet-saved one).

**2026-08-17 (later same day) — Level 5 (Kubernetes) reached its
20/20 target: `20-scheduler-cannot-place-pod` added, fully
live-verified against a real `kind` cluster.**

Scenario: a Pod requesting far more CPU than a single-node `kind`
cluster has sits `Pending` forever with a completely valid spec, plus
two contrasting challenges (a `nodeSelector` matching no node's
labels; existing workloads already claiming the node's capacity before
a new, individually-reasonable request arrives). All three mechanisms
were run against a real cluster, not reasoned about from docs.

`setup.sh`'s first working version had a real, timing-dependent bug:
deploying the Deployment immediately after `kind create cluster`
returns raced kind's own removal of the control-plane node's startup
taint, and depending on timing the Pod would get rejected for
`untolerated taint(s)` instead of the intended `Insufficient cpu` —
confirmed live (`kubectl describe pod` genuinely showed the taint
message on one run, then the correct CPU message on a re-run seconds
later with no code change). Fixed by adding
`kubectl wait --for=condition=Ready node --all` between cluster
creation and deploying the workload; re-verified across multiple
`reset.sh` runs afterward with no further races.

The "existing workloads already ate the capacity" challenge was
deliberately designed to not depend on this machine's specific node
size: rather than hand-tuning exact CPU numbers against the 10
allocatable cores this Docker Desktop happened to report
(`kubectl describe node` confirmed 10, but that number is tied to
whatever the reader's own Docker Desktop VM is configured with, not a
constant), the baseline "filler" Deployment deliberately requests 20
replicas x 1 CPU each — 20 cores demanded, comfortably more than any
single-node `kind` cluster is likely to have — so it reliably
saturates the node's real Allocatable capacity regardless of exactly
what that capacity is. Confirmed live: on this 10-core node, 11 of 20
filler replicas stayed `Pending` and the node's own Allocated
Resources sat at 99% CPU; a subsequent `webapp` Pod requesting only
`200m` still failed to schedule with the identical `Insufficient cpu`
wording as the main lab's scenario, despite its own request being
completely reasonable in isolation — confirming the intended "same
error text, unrelated root cause" lesson. The fix (scaling the filler
deployment down) was confirmed to let `webapp` schedule with no change
to its own manifest at all.

**2026-08-17 (later still) — Level 6 (Incidents) grew to 9/20:
`07-the-database-with-room-to-spare` added, fully live-Docker-verified,
design revised twice mid-build after live testing contradicted the
original assumption.**

Scenario: signups fail while a disk-usage dashboard shows plenty of
free space, because an unrelated per-request logger exhausts a shared
filesystem's *inodes* (not bytes) that Postgres's data directory also
lives on. Mechanism chosen deliberately to portably reproduce "df -h
fine, writes fail" without a privileged loopback ext4 filesystem (used
elsewhere in the repo, e.g. `linux/11-disk-full-writes-fail`): a
Docker Compose named volume with `driver_opts: {type: tmpfs, device:
tmpfs, o: "size=256m,nr_inodes=3000"}`, shared between the `postgres`
and `request-logger` containers via a common mount point, PGDATA set
to a subdirectory of it. Confirmed live this reproduces the exact
`df -h`/`df -i` split intended: bytes usage stays under 25% throughout
while inode usage climbs to 100%.

The first design assumption — "once inodes are exhausted, ordinary
signup traffic through the app will start failing" — did NOT hold up
under live testing and required real investigation to fix. Root cause:
extending an already-open file (ordinary row growth in an existing
heap file) does not need a new inode at all; only *creating* a new
file does. Under light, steady single-row `/signup` traffic, Postgres
almost never needs to create a new file — WAL segments get recycled
(renamed, not created) as long as an old one is available, and a
table's free-space-map (`_fsm`) file is only created once, when the
table first crosses a small page-count threshold. Confirmed live: 100
sequential signups before inode exhaustion, then 30 more sequential
signups after exhaustion, all succeeded with HTTP 200 — the incident
did not reproduce at all under that design. A direct 50,000-row bulk
`INSERT` via `psql` (run purely to investigate, not shipped) did
reliably fail with `could not create file "base/16384/16386_fsm": No
space left on device`, isolating the real trigger: table growth that
crosses the fsm-creation threshold specifically *while* inodes are
already exhausted, not steady-state traffic in general. Confirmed via
a genuinely clean run (fresh `reset.sh`, no manual bulk insert) that
ordinary sequential `/signup` traffic *does* reliably trigger this
once enough of it accumulates after exhaustion — deterministically at
request #137, identically across multiple independent `reset.sh` runs.
`setup.sh` was rewritten around this: bring the stack up, wait for
`request-logger` to fully exhaust inodes first (confirmed via `df -i`
polling), *then* drive real `/signup` traffic in a loop until a write
actually fails (capped at 400 attempts, erroring loudly if none do,
rather than assuming a fixed count), so the incident is verified
live-broken by the time setup.sh exits rather than merely
probably-broken.

Also fixed along the way: a Postgres `POSTGRES_INITDB_ARGS:
"--wal-segsize=1"` tweak was tried first (suspecting WAL segment
rollover was the trigger) and left in place since it doesn't hurt, but
was confirmed via live testing to NOT be what actually causes the
reliable failure — the fsm-file creation is. A port conflict
(`5432` already bound by an unrelated local `manjeniq-dev-db`
container) was caught before any lab file was written and the
Postgres host port was moved to `5470` instead, avoiding any
interference with unrelated local project.

`labs/incidents/README.md`'s incident list was also missing entries
for three already-built-and-committed incidents from earlier in this
project (`06-the-rollout-that-lied`, `11-the-vanishing-changes`,
`16-the-flatlined-dashboard`) — added them alongside `07` in this same
pass, along with their actual environment prerequisites (`kind` for
06, a plain VM with no containers for 16).

**2026-08-17 (later still, part 2) — Level 6 (Incidents) grew to
10/20: `08-the-ipv6-only-timeouts` added, fully live-Docker-verified.
Also fixed a real bug in `labs/incidents/README.md`'s own incident
list, introduced in the previous session's edit.**

The README bug: the previous session added entries for incidents 06,
07, 11, and 16 to `labs/incidents/README.md`'s numbered list, but
wrote them using literal markdown ordered-list markers (`8.`, `9.`)
continuing the sequence from `7.` — which point at incidents 11 and
16, not incidents 8 and 9. Since most markdown renderers (including
GitHub's) ignore the literal number typed for non-first items in one
continuous ordered list and just auto-increment, this rendered
correctly as "8." and "9." on the page while linking to
`11-the-vanishing-changes` and `16-the-flatlined-dashboard` -
misleading given the directory names don't match the visible list
numbers, and actively wrong the moment a real `08-...`/`09-...`
incident gets added later, since editors reading the source `.md`
file would see `8.`/`9.` typed next to the wrong incidents. Fixed by
switching the entire list to `-` bullets, so incident numbers only
ever appear once, unambiguously, in the link text/directory name
itself, with no renderer-dependent auto-numbering involved at all.

`08-the-ipv6-only-timeouts`: deliberately combines two already-built,
single-mechanism Level 2 networking labs -
`networking/24-ipv6-dual-stack-issues` (half-broken IPv6 being worse
than fully absent, Happy Eyeballs) and `networking/28-iptables-ipv6-gap`
(`iptables`/`ip6tables` as two independently-maintained rule sets) -
into one incident. Built and verified on a real dual-stack Docker
network (`enable_ipv6: true`, explicit `ipv4_address`/`ipv6_address`
per service in `docker-compose.yml`, confirmed to work directly on
Docker 29.7.2 / Compose v5.3.1 with no daemon-wide legacy `--ipv6`
flag needed). Confirmed live, step by step, before writing any docs:

- Docker's embedded DNS returns both an AAAA and an A record for a
  dual-stack service name, IPv6 first (`socket.getaddrinfo()` output
  checked directly).
- `ip6tables -A INPUT -p tcp --dport <port> -j DROP` inside a
  container (needs `cap_add: [NET_ADMIN]`) produces a genuine silent
  drop — confirmed via `nc -zv` timing out at exactly the configured
  wait, `ping`/ICMPv6 to the same address continuing to succeed
  instantly the whole time, and a plain `curl -6` hanging for the
  full `--max-time` before failing — a categorically different result
  from `curl -4` to the same service, which succeeds in ~2ms.
- The actual application-level mechanism needed a live check rather
  than an assumption: does a plain `requests.post(url, timeout=N)`
  call (no custom Happy-Eyeballs logic, nothing special) actually
  recover via IPv4 after the IPv6 candidate times out, or does the
  whole request just fail once its timeout budget is spent on the
  first (IPv6) candidate? Confirmed via 5 repeated live runs: total
  request time lands at 5.01–5.05s every time (never fails outright),
  meaning Python's standard-library connection code applies the
  *remaining* timeout budget to the next `getaddrinfo()` candidate
  rather than a fresh timeout per candidate — reliable and precise
  enough to build `check.sh`'s fixed-threshold check around directly,
  with no flakiness observed across the verification runs.
- Two unrelated local port conflicts were hit and resolved without
  touching the conflicting containers: host port 8000 was already
  bound by an unrelated `manjeniq-dev` container (this lab's frontend
  moved to host port 8090), matching the same kind of pre-existing
  local-service collision handled for lab 07's Postgres port earlier
  the same day.

**2026-08-18 — Level 2 (Networking) grew to 33/25: four new labs
(`30-mangle-policy-routing`, `31-load-balancer-health-check-blind-spot`,
`32-tcp-zero-window-analysis`, `33-snat-vs-masquerade`), all
live-verified. `labs/networking/README.md` also created from scratch —
it never existed before this batch despite the level having 29 labs
already; the root README linked to the bare directory listing the
whole time.** Requested by the user directly ("need more on network
troubleshooting, wireshart, tcpdump, nat, snat, mangle, and
loadbalancing, and mysql") — scoped via `AskUserQuestion` to standalone
Level 2/4 labs (not Level 6 incidents), all four networking gap topics,
with MySQL scope deferred ("not sure yet, decide after seeing the
networking labs").

Verification environment: a single privileged Ubuntu 22.04 Docker
container (`labtest`) with `iproute2`/`iptables`/`tcpdump`/`tshark`/
`python3`/`haproxy` installed, used as the "Linux VM" substitute for
all four labs (`ip netns` + `iptables` work identically to a real VM
under `--privileged` + `--cap-add=NET_ADMIN`, already established
earlier in this project). A no-op `sudo` shim (`exec "$@"`) was
installed since the container runs as root already — the shipped
scripts still say `sudo`, matching what a real non-root VM user needs.

`30-mangle-policy-routing`: the ORIGINAL design marked a router's own
locally-generated traffic in `iptables -t mangle -A OUTPUT` (a router
directly `nc`-ing a downstream target) and set up the matching
`ip rule`/custom table correctly — confirmed via `ip rule show` and
`ip route get ... mark 0x64` that the policy routing config was
correct, yet a live packet capture on the actual `nc` connection showed
it still going out via the WRONG (main-table) interface, with the
wrong source address. Root cause: for a brand-new locally-generated
TCP connection, the kernel's route lookup (which picks source
address/interface) happens as part of building the very first SYN,
before `mangle OUTPUT` has run — so the mark never influences that
first, connection-defining route decision. This is a real,
kernel-level two-pass routing subtlety, not a config mistake. Fixed by
switching to the standard, more reliable real-world pattern: mark
*forwarded* traffic (a separate `client` namespace's traffic passing
*through* the router) in `mangle PREROUTING` instead — confirmed live
this reroutes correctly, matching how production multi-WAN/policy
routing setups actually mark traffic. Final topology: 5 namespaces
(`client`, `router`, `gwa` the default/unreachable path, `gwb` the only
real path, `target`). Both challenges (wrong `ip rule` priority placing
it after `main`; `ip rule` pointing at a table number with no matching
route) verified live and produce identical "timeout, no obvious error"
symptoms from the outside, distinguishable only by inspecting `ip rule
show` and `ip route show table N` as two separate facts. A real,
separate bug also surfaced and got fixed along the way: the first
`setup.sh` used an `nc -lk`-in-a-loop target listener that had a
restart gap between connections, causing ~1-in-3 spurious connection
failures even in the *fixed* state (caught via a 10-run stress test,
not a single test); replaced with a persistent Python
`socketserver.ThreadingTCPServer`, confirmed 10/10 clean afterward.

`31-load-balancer-health-check-blind-spot`: HAProxy + 3 Flask backends,
one (`backend3`) with a working `/healthz` but a permanently broken
`/api/data` (the "real" traffic path) — confirmed live via HAProxy's
own stats page showing `backend3` as fully `UP` (`L7OK/200`) while its
`HTTP 5xx responses` counter sat at 100%. `reset.sh` originally used
`git checkout -- haproxy/haproxy.cfg` to undo a reader's fix edit — a
real design flaw caught before committing anything: this file wasn't
tracked in git yet at that point, so the checkout would silently no-op
instead of reverting, and even after committing it's a fragile pattern
inconsistent with how every other lab in this repo handles "before"
state. Fixed by having `setup.sh` write `haproxy.cfg` fresh from an
embedded heredoc on every run instead, removing the git dependency
entirely. Challenge A (detection lag from HAProxy's default
`rise`/`fall`/`inter` thresholds) confirmed live by hard-stopping
`backend1` and counting real `000` connection failures (4-5,
consistently) before HAProxy's stats page flipped it to `DOWN`.
Challenge B (`option httpchk` removed entirely, falling back to a
Layer-4-only TCP check) confirmed live via HAProxy's own stats page
literally showing `L4OK` instead of an HTTP result — `backend3` stayed
`UP` throughout, exactly as predicted, strictly blinder than the main
lab's wrong-endpoint mistake.

`32-tcp-zero-window-analysis`: a Python receiver with a tiny
`SO_RCVBUF` (2048 bytes) reading in small, deliberately-delayed chunks
against a fast sender — confirmed live via `tshark -Y
'tcp.analysis.zero_window'` finding 15 flagged frames in a capture
where raw `tcpdump | grep 'win 0'` found the same packets only because
the exact string to search for was already known in advance. A real
timing bug surfaced and got fixed: `sudo VAR=val command` does NOT set
environment variables the way plain shell assignment does (sudo has no
special parsing for that syntax) — the original setup.sh's
`sudo RCVBUF=2048 ... ip netns exec ...` silently failed with `exec:
RCVBUF=2048: not found`, caught immediately when the server never
actually started listening; fixed with `sudo ip netns exec server env
RCVBUF=2048 ...` instead, using `env` as the actual mechanism for
setting variables on a single command under `sudo`. Also confirmed
live (and initially mistaken for a flaky check.sh) that the exact
zero-window *count* genuinely varies run to run (15, 30, 31 observed
across identical broken-state runs) due to real TCP timing jitter —
this is not a bug, since `check.sh`'s pass/fail logic only checks
zero-vs-nonzero, confirmed reliable across 5 repeated runs each of the
broken state (always FAIL) and the fixed state (always PASS, exactly
0 events every time).

`33-snat-vs-masquerade`: client → router → upstream, static `SNAT`
hardcoded to router's current external address, then that address
changes (simulating a DHCP renewal). First live test of the "IP
changes, SNAT breaks" premise was surprising: connectivity *kept
working* after the address change. Root-caused live: `upstream`'s ARP
cache still mapped the old, now-unbound address to router's unchanged
MAC address, so replies kept physically arriving at router's NIC
regardless of what IP was actually configured — confirmed by explicitly
flushing `upstream`'s ARP cache (`ip neigh flush all`), at which point
the connection genuinely timed out. This became both the fix for
`setup.sh` (explicitly flush ARP as part of fault injection, so the
incident reproduces immediately rather than requiring an indeterminate
real-world ARP cache expiry) and Challenge A's entire lesson (the same
misconfiguration is invisible for a real, unpredictable amount of time
before an unrelated cache-expiry event makes it fail). Confirmed
`MASQUERADE` survives the exact same address change with zero rule
changes, and separately confirmed (Challenge B) that "fixing" `SNAT` by
updating `--to-source` to the new address works once but breaks again,
identically, on a second address change — `MASQUERADE` survives both.

Root README's networking description, badge, Status paragraph, and
"Remaining to reach ~120" note all updated to 33/25 and 133/~120
total. `labs/networking/README.md` written from scratch (33 entries)
since it was genuinely missing — confirmed via direct `find`/`ls`, not
assumed; the internal-link checker apparently doesn't flag a level
directory lacking its own README, only broken links between existing
files.

**2026-08-18 (later same day) — fixed a stale committed file from the
previous batch, then Level 6 (Incidents) grew to 11/20:
`09-the-shared-proxy-meltdown` added, fully live-verified.**

Pre-existing bug found and fixed first: `labs/networking/31-load-balancer-health-check-blind-spot/haproxy/haproxy.cfg`
had been committed with `option httpchk`/`http-check expect` commented
out - the state left over from live-testing that lab's Challenge B
(the TCP-only-check scenario) right before the batch commit landed.
`setup.sh` always overwrites this file fresh via heredoc at runtime,
so the lab itself was never actually broken by this, but the tracked
file on GitHub was misleading (showed Challenge B's state as if it
were the lab's default). A system reminder flagged the file as
modified before this session's work began; verified via `git diff`
that the committed content genuinely had the comments in it (not a
local-only uncommitted change), restored the correct
`option httpchk GET /healthz` / `http-check expect status 200` lines,
confirmed the restored content matches `setup.sh`'s heredoc exactly
(`diff` against the extracted heredoc section), committed and pushed
as its own small fix commit before starting new work.

`09-the-shared-proxy-meltdown`: nginx as a single shared reverse
proxy in front of two unrelated services - `service-a` (the actual
subject of the page, always fast) and `service-b` (a lower-priority
internal tool whose one endpoint hangs indefinitely). `worker_connections`
set deliberately low (8) so the meltdown reproduces with just a
handful of concurrent hung requests. Confirmed live: `service-a`
answers in ~5ms when hit directly on its own port, but fails
immediately (`HTTP 000`) through nginx once a burst of ~6 concurrent
requests into `service-b`'s hung endpoint exhausts the shared pool -
proof the bottleneck is nginx's connection budget, not `service-a`
itself. Confirmed `proxy_connect_timeout` alone does not fix this
(verified live, twice, including a fully-clean container rebuild to
rule out residual state) - `service-b`'s process is alive and accepts
the TCP connection instantly, so the connect phase never has anything
to time out on; only `proxy_read_timeout` (guarding the
response-waiting phase) actually helps. A real, valuable nuance
surfaced during verification: even with the correct fix in place,
`service-a` doesn't recover *instantly* during an active burst against
`service-b` - it recovers within the configured `proxy_read_timeout`
window (confirmed at ~2s with `proxy_read_timeout 3s` set) as held
connections get released and freed back to the pool. `check.sh` was
designed around this from the start: it fires a fresh burst at
`service-b`, then polls `service-a` for recovery within a bounded
window (15s) rather than expecting instant success - correctly FAILs
throughout that window against the unfixed config (verified with a
completely fresh container, no leftover state) and correctly PASSes
within ~2-6s once the fix is applied.

A real bug was caught and fixed in `check.sh` before shipping: its
initial "is the environment even up" guard originally sent a request
to `service-a` *through nginx* - but that's the exact path that's
supposed to be failing during a live incident, so running `check.sh`
against a genuinely broken environment misreported it as "nginx is
not reachable - run setup.sh first" instead of correctly identifying
the incident as still active. Fixed by checking `systemctl is-active`
for the `nginx` and `service-a` systemd units directly instead of
making an HTTP request through the exact layer under test - matching
the pattern already used by `05-the-restart-that-doesnt-help`'s
`check.sh` (a filesystem/mountpoint check, not a request through the
broken path).

Verification method: since `systemd` isn't available in the Docker
container used as this project's "Linux VM" stand-in, the `systemctl`
service-management lines in `setup.sh`/`check.sh`/`reset.sh` could not
be directly executed in this environment - only their syntax was
checked. The actual reproducible mechanism (nginx config, the two
Python services, the burst-and-poll logic in `check.sh`) was fully
verified by extracting the exact embedded heredoc content from the
shipped scripts (`sed` between the `tee`/`EOF` markers) and running it
directly via plain background processes against multiple genuinely
clean container rebuilds - required because Docker's `pkill`/process
cleanup between test iterations proved unreliable mid-session (stray
`nginx` master processes survived `pkill`/targeted `kill -9` more
than once), and a first test that appeared to show fast "recovery" on
the *broken* config turned out to be contaminated by leftover
long-running `curl -m 60` processes from an earlier manual test
approaching their own timeout - caught by rerunning against a
provably clean container rather than trusting a single surprising
result.

**2026-08-18 (later still) — Level 6 (Incidents) grew to 12/20:
`10-the-fix-that-made-it-worse` added, fully live-verified, with a
design that changed significantly mid-build once live testing
revealed the first version's premise was backwards.**

Scenario: `client-traffic.service` (standing in for real recurring
checkout burst traffic) retries every failed request up to `RETRIES`
times immediately, no backoff, into `backend.service` (a small HTTP
service with a genuinely fixed, finite capacity via a
`ThreadPoolExecutor(max_workers=3)` and 0.3s of real work per
request). `RETRIES=3` was "the fix" - applied specifically to reduce
user-visible checkout errors - and instead turns a stable, tolerated
burst-time failure rate into a full, unrecovering outage.

Getting the underlying mechanism to actually behave this way took
substantial live iteration:

- First model: an instant-reject semaphore (`BoundedSemaphore`,
  non-blocking `acquire()`, immediate `503` if the pool is full).
  Confirmed live that this makes retries essentially *free* for the
  server - a rejected attempt costs the backend nothing (no queueing,
  no work started), so retries just added connection overhead without
  ever competing for the same constrained resource in a way that hurt
  throughput. Across multiple rate/retry combinations, logical failure
  rate stayed roughly flat or even improved slightly with retries
  enabled - the opposite of the intended lesson. Abandoned this model
  entirely rather than force the intended conclusion.
- Second model: a real bounded worker pool with an *unbounded queue*
  (`ThreadPoolExecutor(max_workers=3)`, `future.result()` blocks until
  the request's turn comes up and completes) plus a client-side
  request timeout (abandon and, if retries remain, immediately
  resubmit). This is much closer to how a real queue-based backend
  actually behaves - an abandoned-by-the-client request is still
  consuming a worker slot server-side, so retries genuinely compete
  with (and can starve) requests that would otherwise have succeeded.
- Even with the correct model, tuning the offered rate against
  capacity was extremely sensitive - burst sizes of 10-13 (at
  `BURST_INTERVAL=2s`, `CLIENT_TIMEOUT=1.0s`) consistently showed
  retries *helping* (enough slack existed between bursts for the
  extra attempts to be absorbed); burst size 14-15 crossed a sharp,
  narrow threshold into the intended runaway-failure regime. Confirmed
  this transition directly, side by side, at multiple burst sizes
  before locking in `BURST_SIZE=15`.
- A finite-duration test harness (fixed `TOTAL_TIME`, joining all
  threads with a timeout before reporting) initially suggested a
  *stable* elevated failure rate under retries (~76-78%, plateauing) -
  this turned out to be an artifact of the harness itself capping how
  long any single test run could observe the system, not evidence the
  backlog was actually stabilizing. Removing the fixed duration and
  running the actual shipped `client-traffic.py` (which runs
  indefinitely, exactly as `setup.sh` deploys it via systemd) revealed
  the real, more severe behavior: complete saturation (100% failure)
  within the first 10-second report window, with cumulative HTTP
  request volume growing *linearly forever* (270 → 570 → 870 → ... →
  2370 over 80 seconds, no sign of plateauing) - genuine unbounded
  backlog growth, not a new equilibrium. A matching control run with
  `RETRIES=0` over the same duration stayed at a flat, stable 40%
  failure rate the entire time, confirming the contrast is real and
  not measurement noise.
- The originally-planned `check.sh` threshold (fail above 20%) had to
  be revised to 60% once the real "healthy" baseline turned out to be
  a stable ~40%, not the near-zero baseline originally assumed -
  adjusted the README/solution narrative to match reality (a service
  deliberately sized for average, not peak, load, with a known,
  accepted non-zero burst-time failure rate) rather than force an
  unrealistic "normally near-perfect" story.
- Verification method: `systemd` unit files
  (`backend.service`/`client-traffic.service`) could not be directly
  executed in the Docker-container test environment used throughout
  this session (no `systemd`), so their syntax was checked but not
  run as actual systemd units. The real embedded Python scripts and
  the full retry/backlog mechanism were fully verified by extracting
  the exact heredoc content from `setup.sh` (same `sed` extraction
  technique used for incident 09) and running it directly as plain
  background processes.

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
