# Lab 6 — Concept: Simulating Drive Failure, and What Real NVMe Health Monitoring Actually Watches

## What's actually going on

You cannot make a real NVMe drive develop a hardware fault on demand for
a lab, so this lab uses Linux's device-mapper framework instead — the
same kernel subsystem LVM, RAID, and encrypted volumes are all built on
— to construct a virtual block device that behaves the way a failing
drive does at the I/O level, which is the part that's actually
observable and diagnosable from software. `dmsetup create <name>
--table "<start> <sectors> <target> <args>"` builds a mapped device
from a target driver and its arguments. `flakey` (target arguments:
underlying device, offset, an "up" interval, and a "down" interval, in
seconds, optionally followed by extra failure-mode features) cycles the
device between fully working and erroring on a schedule — a faithful
model of an *intermittently* failing drive, the kind throwing occasional
read/write errors from a developing hardware fault, marginal connector,
or firmware bug, without having died outright. `error` is simpler and
harsher: every single I/O operation fails, immediately and permanently —
what a fully dead drive or completely severed connection looks like, with
no window to "wait and retry" into. The distinction the lab's main
scenario and Challenge A draw out matters operationally: an
intermittently-failing device might justify a brief "let's see if this
clears" pause (rarely, and cautiously); a totally dead one never does —
there's no partial credit for waiting on zero working windows.

The most operationally important, and easy-to-underestimate, lesson from
the flapping pattern itself is that intermittent failure is *more*
dangerous than clean total failure, not less — precisely because it keeps
producing "it's working again!" moments that erode urgency. A drive that
throws errors for ten seconds, recovers for twenty, throws errors again,
is very often a drive on a failure trajectory, not a drive with a
transient, resolved problem — and treating each "it's back" moment as
resolution rather than as one more data point in a trend is a common,
costly mistake. This is exactly why real fleet monitoring keys off
cumulative counters and trend lines (SMART attributes accumulating over
time), not "is it responding right now."

`dm-flakey`'s optional `corrupt_bio_byte` feature demonstrates something
categorically scarier than any I/O error: it can flip a specific byte in
a write's data while letting the I/O operation itself report success —
modeling silent data corruption (sometimes called "bit rot") rather than
a detectable failure. Neither the block layer nor a non-checksumming
filesystem like plain ext4 or XFS has any way to notice this happened;
the write "succeeds," a later read "succeeds," and the bytes returned are
simply wrong, with zero entries anywhere in `dmesg`. This is the sharpest
possible illustration of why "no errors in the logs" cannot be treated as
"the data is correct" — it only means nothing along the path happened to
check.

Real NVMe/SSD health monitoring, since it can't be demonstrated
meaningfully against this lab's virtual device, is worth stating
explicitly: `smartctl -a /dev/nvmeX` (or `/dev/sdX` for SATA/SAS)
surfaces vendor-reported health attributes, and the ones that actually
predict imminent failure — as opposed to attributes that fluctuate
harmlessly — are specific: **reallocated sector count** and **pending
sector count** climbing above zero (the drive has already found bad
media and is quietly working around it — read this as "actively failing,
just not dead yet"), **UDMA/interface CRC error count** climbing
(suggests a cabling/connector problem more than a media problem, but
still degraded reliability), **percentage used / media wearout indicator**
for SSDs/NVMe approaching its rated endurance limit, and **uncorrectable
error count**. `dmesg` is where the *kernel's* real-time view of a
struggling drive shows up in production — I/O errors, reset/timeout
messages from the storage controller driver, or (for NVMe specifically)
namespace or controller error log entries — and is the first place to
look the moment a service starts reporting unexplained I/O failures on
real hardware.

## Where this shows up in the real world

Fleet-wide disk health monitoring (SMART attribute collection feeding
into alerting on reallocated-sector or pending-sector trends, not just
threshold crossing) is standard practice at any scale beyond a handful of
servers, precisely because the flapping/intermittent failure pattern is
the realistic early-warning signal, not a clean "disk is dead" event.
Silent data corruption is the specific, real reason ZFS and Btrfs exist
as checksumming filesystems, and why enterprise storage arrays checksum
data end-to-end — "the write succeeded" has never been sufficient
evidence that a write is byte-correct on any storage medium, spinning
disk, SSD, or NVMe alike.

## Go deeper

- **Website/docs:** Linux kernel docs — https://docs.kernel.org/filesystems/
  (also see `Documentation/admin-guide/device-mapper/dm-flakey.rst` and
  `dm-error` in the kernel source tree) — canonical reference for
  `dm-flakey`/`dm-error` target table syntax and features.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man8/dmsetup.8.html
  and `smartctl(8)` (from the smartmontools project) — reference for
  `dmsetup` usage and SMART attribute meanings.
- **Book:** *Systems Performance* — Brendan Gregg — disk reliability and
  performance monitoring chapters, useful background for what production
  disk monitoring actually watches.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — device-mapper and storage
  reliability administration guides.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  covers device-mapper and storage administration fundamentals.

**Confidence flag (the least-certain command in this entire lab set):**
the exact `dm-flakey` table syntax used for `corrupt_bio_byte` in
Challenge B (`... 1 corrupt_bio_byte 32 w 0 64`) is written from memory
of the general feature-argument pattern documented for `dm-flakey`
(`<num_features> <feature_arguments>`), but the precise argument order,
count, and meaning have **not** been verified against the actual kernel
documentation or tested live. Verify against
`Documentation/admin-guide/device-mapper/dm-flakey.rst` in the kernel
source before recording this challenge, and adjust the `dmsetup create`
line if the syntax differs. The base `flakey`/`error` table syntax used
everywhere else in this lab is more standard and higher-confidence, but
still untested live.
