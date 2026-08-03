# Lab 4 — Concept: What "Degraded" Actually Means, and Why the Rebuild Window Is the Dangerous Part

## What's actually going on

RAID5 stores data striped across all member disks along with a rotating
parity block computed (via XOR) from the data blocks in each stripe.
This means any single missing member's data can always be reconstructed
on the fly from the parity block plus the remaining members in that
stripe — which is exactly what "degraded" mode is: the array keeps
serving reads and writes normally, but every operation touching the
missing member's data now costs an extra reconstruction step, and
critically, there is now zero redundancy left. `mdadm --detail` and `cat
/proc/mdstat` are how you observe this state directly — `--detail` shows
overall array `State` (`clean` vs `clean, degraded` vs `clean, FAILED`)
and each member's individual state (`active sync` for a healthy synced
member, `faulty` for one that's failed and hasn't been removed yet,
`spare`/`rebuilding` for one currently being resynced in), while
`/proc/mdstat` shows a live-updating `recovery` line with a percentage
once a rebuild starts.

Replacing a failed member is a three-step operation, and `mdadm` makes
each step explicit rather than automatic: `--fail` marks a member as
failed (the kernel stops trusting it, but it's still attached and listed
until removed), `--remove` actually detaches it from the array, and
`--add` (or `--re-add`) attaches a replacement and kicks off a rebuild —
the array reading every stripe across all surviving members and
reconstructing the missing member's data block by block onto the new
device. This rebuild is not instantaneous, and its duration scales with
disk size — on real multi-terabyte disks, particularly on RAID5 arrays
where the whole array must be read to reconstruct one disk, rebuilds
routinely take many hours. `speed_limit_min`/`speed_limit_max` (exposed
via `/proc/sys/dev/raid/`) let an administrator throttle how much I/O
bandwidth a rebuild is allowed to consume, trading a longer rebuild
window for less impact on production traffic sharing the same disks —
which is exactly the tradeoff this lab's Challenge A exploits to make the
danger window observable.

That danger window is the single most important thing to understand
about any redundant-but-not-doubly-redundant RAID level: for the entire
duration of a rebuild, the array has **zero** spare fault tolerance left.
RAID5 tolerates exactly one simultaneous failure by design — reconstruct
one missing disk from parity plus the rest, full stop — so a second
failure during that window (which is exactly when it's statistically
*more* likely, since the surviving disks are now all under sustained
heavy sequential read load reconstructing the replacement, a workload
pattern that reveals marginal/failing disks that had been quietly
degrading) means there is no longer enough surviving data to reconstruct
either failed member, and the array is unrecoverable through RAID alone.
This is precisely why RAID6 (tolerates 2 concurrent failures, at the cost
of a second parity disk and more write overhead) and hot spares (a
pre-attached idle disk that starts rebuilding automatically the instant a
failure is detected, shrinking the window between failure and rebuild
start) exist, and why "we have RAID" is never a substitute for actual
backups — RAID protects against a single-disk hardware failure causing
downtime, not against the many other ways data gets lost.

A write-intent bitmap (`mdadm --grow --bitmap=internal`) changes what a
*brief* absence costs. It's a small on-disk map tracking which regions of
the array have been written since each member was last confirmed in
sync. `--re-add`-ing a device that only recently dropped out lets `mdadm`
consult that bitmap and resync only the regions that actually changed
while it was gone, instead of a full disk rebuild — dramatically faster
for the common "controller blipped, disk timed out momentarily and got
kicked" case. `--add` never uses the bitmap this way; it always treats
the incoming device as blank and does a full rebuild, which is the
correct behavior for a genuinely new replacement disk that has none of
the array's history on it, but wasteful when the same device is coming
right back.

## Where this shows up in the real world

Any server or storage appliance using RAID5/6 hits this exact lifecycle
whenever a disk fails: alerting fires on the degraded state, an on-call
engineer replaces the physical disk, a rebuild runs, and the array
returns to full redundancy — the entire discipline of RAID monitoring
exists to make sure that window is as short and as closely watched as
possible. Real storage incidents involving "the whole array died" are
overwhelmingly rebuild-window double-failures, not first failures — which
is why storage vendors and SRE runbooks alike treat a degraded-array
alert as urgent-same-day, not "get to it this week." Understanding
`--add` vs `--re-add` and write-intent bitmaps matters directly for
minimizing planned-maintenance risk too — briefly pulling a disk for a
firmware update or cabling change and getting it back with a fast
bitmap-based resync, instead of a multi-hour full rebuild, is a real
technique used to shrink self-inflicted risk windows.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man4/md.4.html
  and `mdadm(8)` — canonical reference for RAID levels, `mdadm` flags,
  `--re-add` semantics, and the `speed_limit_min`/`speed_limit_max`
  sysctls.
- **Website/docs:** Red Hat's storage administration documentation —
  https://access.redhat.com/documentation — authoritative software RAID
  (`mdadm`) administration guides.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — has a
  detailed, practical RAID page covering array creation, failure,
  rebuilding, and bitmaps.
- **Book:** *Systems Performance* — Brendan Gregg — disk I/O chapters
  cover RAID performance characteristics relevant to understanding
  rebuild cost.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  has dedicated `mdadm`/RAID administration walkthroughs.

**Confidence flag:** the exact `/proc/mdstat` wording and timing for a
double-failure mid-rebuild (Challenge A), and the precise speedup
`--re-add` with a bitmap produces versus `--add` (Challenge B), have not
been verified on a live system — dry-run this lab and adjust timing
(`sleep` values, `speed_limit_max`) as needed so the window is reliably
catchable before recording.
