# Lab 13 — Concept: Log Rotation, journald's Binary Store, and Why "Just Add a Partition" Isn't Enough

## What's actually going on

Putting `/var/log` (or an app's logs) on its own dedicated partition is a
deliberate blast-radius decision: a runaway logger fills that partition
instead of the root filesystem, so the OS itself stays bootable and
functional even when logging goes haywire. But a dedicated partition only
contains the *damage*, not the *cause* — once it fills, every process
trying to write into it, including the offending app's own error handler,
gets `ENOSPC` ("No space left on device") the same way any other full
filesystem behaves, which is exactly what Step 4 demonstrates. A flaky app
logging every failed retry attempt in a tight, unthrottled loop is one of
the fastest ways to go from "fine" to "100% full" — not a slow leak over
weeks, but a partition maxed out in seconds to minutes, because disk
writes for tiny log lines are cheap and a bad retry loop can generate them
at very high frequency.

Finding the actual writer is a two-part check because file *size* and file
*openness* answer different questions. `du -sh` tells you which files on
disk are large right now — useful, but it says nothing about who's still
actively appending to them, and (as Challenge A shows) a directory can
have more than one large file from more than one independent writer,
so stopping the first process you find can still leave the partition
filling. `lsof +D <mount>` walks every process's open file descriptor
table and reports which ones currently hold a file open under that mount
— this is what actually proves which process(es) are the live writers,
as opposed to just which files happen to be big. Truncating a log
(`truncate -s 0`) rather than deleting it (`rm`) matters specifically
because the writing process still holds that file open by descriptor: an
`rm` would unlink the directory entry while the process keeps writing into
the now-nameless inode (exactly the deleted-but-open-file mechanism from
the Deleted-But-Open File lab), reclaiming nothing until the process closes it, whereas
truncating in place immediately frees the space while preserving the
open handle and giving you a paper trail instead of erasing evidence
outright.

`logrotate` is the standard fix for the file-based version of this
problem: it periodically checks configured log paths against size/age
rules and rotates them (rename, optionally compress, optionally signal the
writing process to reopen its file or truncate in place depending on the
`copytruncate` vs `create` strategy), keeping a bounded number of
generations instead of one ever-growing file. Challenge B shows the same
category of incident with a completely different mechanism underneath.
A service that logs to stdout/stderr under systemd never touches a flat
file at all — `journald` captures that output and writes it into its own
binary, indexed storage format under `/var/log/journal/<machine-id>/`.
Without an explicit cap (`SystemMaxUse=` in `/etc/systemd/journald.conf`),
journald will keep accepting and storing data, bounded only by its own
defaults (which reserve a substantial fraction of the filesystem it lives
on) — a crash-looping service with `Restart=always` and no backoff
(`RestartSec=0`) can generate an enormous volume of journal entries very
quickly, and `du -sh /var/log/myapp` (or any check scoped only to a
specific log directory) would never catch this, because the growth is
happening in an entirely separate directory tree that most people forget
journald even writes to. `journalctl --disk-usage` and `journalctl
--vacuum-size=`/`--vacuum-time=` are journald's direct equivalents of
`du`/`logrotate` for this binary log store.

## Where this shows up in the real world

A crash-looping process that logs every failed attempt — a connection
retry loop, a config-reload failure, a dependency that's down — is one of
the most common ways a production disk fills fast rather than slowly, and
it's exactly the incident shape most on-call runbooks are built around:
find the writer (`lsof +D`), stop the bleeding (kill or fix the retry
loop), reclaim space safely (truncate, don't blindly delete open files),
then prevent recurrence (rotation limits, and for systemd services,
`journald` caps). Teams that only know to check flat-file logs get
blindsided the first time the actual growth is happening inside
`/var/log/journal` instead, since a huge and growing fraction of modern
services log exclusively via stdout under systemd rather than to files
directly.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man8/logrotate.8.html — the canonical reference for `logrotate` configuration, including `copytruncate` vs `create` semantics.
- **Website/docs:** Arch Linux Wiki — https://wiki.archlinux.org — has clear, practical pages on `journald` configuration, `SystemMaxUse=`, and vacuuming.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/journald.conf.5.html — official `journald.conf` reference for storage limits and rotation-equivalent settings.
- **Book:** *Systems Performance* — Brendan Gregg — general methodology for tracking down which process/subsystem is consuming a suddenly-scarce resource.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — covers logrotate and journald administration in practical, hands-on detail.
