# Lab 11 — Concept: Btrfs Checksums, Detection vs Healing, and Why Redundancy Is a Separate Decision

## What's actually going on

Btrfs checksums every block of data and metadata it writes by default —
this is not an opt-in feature the way it is on ext4/XFS (which have no
equivalent at all) or even on some other checksumming systems; it's on
from `mkfs.btrfs` unless deliberately disabled per-file with `nodatasum`.
Every read verifies the block's contents against its stored checksum
before handing it back to an application. This means btrfs can always
*detect* that a block's contents don't match what was written, on any
number of devices, including exactly one — the moment a checksum
mismatches, btrfs returns an I/O error for that read rather than quietly
serving corrupted bytes, and logs a `csum failed` message identifying
what was affected. Detection is a property of checksumming alone and
needs nothing beyond a single device to work.

*Healing* — actually reconstructing the correct bytes and rewriting them
over the bad copy — is a completely separate capability that depends on
whether a second, verified-good copy of that specific block exists
somewhere. This is where the `-d`/`-m` profile flags to `mkfs.btrfs`
matter: they set the redundancy profile independently for data (`-d`)
and metadata (`-m`). `single` means exactly one copy exists, anywhere;
`dup` means two copies exist on the *same* device, at different
physical locations — real redundancy, just not surviving a whole-device
failure; `raid1`/`raid10`/etc. spread copies across multiple physical
devices, the kind of redundancy that survives losing an entire disk.
Btrfs's default single-device `mkfs.btrfs` behavior of using `dup` for
metadata but `single` for data (this lab makes both flags explicit
rather than relying on version-dependent heuristics) reflects a real
design judgment: losing a chunk of file data is bad, but losing metadata
— the B-tree structures describing where every file, extent, and
directory actually lives — can cascade into losing access to far more
than one file, so metadata gets the cheap insurance of a second on-disk
copy by default even with no additional hardware. Data does not, because
duplicating all data by default would double effective disk usage for
every single-device btrfs filesystem, which most users would not want as
a silent default.

`btrfs scrub` is the tool that turns "detection" into an actual
maintenance operation: it proactively reads and checksum-verifies every
block in the filesystem (rather than waiting for something to read a bad
block naturally) and, for every mismatch found, either repairs it from a
redundant copy (reported as a *corrected* error) or, if no redundant copy
exists for that block, reports it as an *uncorrectable* error and leaves
it as-is — there is nothing else the scrub can do with a single bad copy
and no source of truth to compare it against. This is exactly the
distinction Challenge A surfaces: the same corruption event, on the same
filesystem, produces two different outcomes depending purely on whether
it happened to land on a `dup`-profile metadata block or a
`single`-profile data block. `btrfs check`, separately, is an offline
(filesystem must be unmounted) structural consistency checker for the
B-tree layout itself — closer in spirit to `fsck` for a traditional
filesystem — and its `--repair` flag carries a real, well-documented
reputation for being riskier to reach for casually than `xfs_repair` or
`e2fsck -y`, because correctly repairing a copy-on-write B-tree structure
after damage is a harder problem in general than repairing a simpler
on-disk layout, and community guidance consistently treats it as a
"understand what you're doing, back up first" tool rather than a routine
fix.

## Where this shows up in the real world

Btrfs (like ZFS, Lab 10) exists specifically because "the write/read
succeeded" has never actually meant "the bytes are correct" on any real
storage medium — silent bit rot from developing hardware faults, cosmic-ray
bit flips, firmware bugs, and cabling issues are all real, documented
phenomena that non-checksumming filesystems have no way to notice at
all. Any team running btrfs in production for its checksum guarantees
should be running `btrfs scrub` on a regular schedule (commonly monthly)
for the same reason ZFS shops schedule scrubs — corruption sitting
undetected in data nobody reads recently is corruption a scrub is the
only thing that will ever surface. The `--repair` caution is a real,
recurring topic in btrfs mailing lists and community troubleshooting
threads, and is one of the most consistently repeated pieces of
practical advice for anyone new to operating btrfs day to day.

## Go deeper

- **Website/docs:** Linux kernel docs —
  https://docs.kernel.org/filesystems/btrfs.html — official kernel
  documentation for btrfs, including checksumming and profile behavior.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — has a
  precise, practical btrfs page covering `mkfs.btrfs` profiles, scrub,
  and `btrfs check`/`--repair` caveats specifically.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ —
  reference for `mkfs.btrfs(8)`, `btrfs-scrub(8)`, and `btrfs-check(8)`.
- **Book:** *Systems Performance* — Brendan Gregg — file system chapters
  cover checksumming filesystem design and the performance tradeoffs
  involved.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  btrfs administration content covering profiles, scrubbing, and
  filesystem checks.

**Confidence flag:** the specific `btrfs scrub status -d` output field
names ("corrected errors" / "uncorrectable errors") and the exact
`btrfs check --help` warning wording referenced in this lab are written
from documented, widely-discussed btrfs behavior and community guidance,
but have **not** been tested live against a real invocation in this
environment — the general field names and counts are stable across
recent `btrfs-progs` versions, but exact wording may differ by version.
The default single-device metadata profile being `dup` is also
version-dependent in upstream `mkfs.btrfs` heuristics (older versions
could default to `single` for metadata on devices detected as
non-rotational); this lab sidesteps that ambiguity entirely by passing
`-d single -m dup` explicitly in `setup.sh` rather than relying on
auto-detection, which is the higher-confidence, deliberate choice
here.
