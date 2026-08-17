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
