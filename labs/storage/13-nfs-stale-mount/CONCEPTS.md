# Lab 13 — Concept: NFS Filehandles and Why They Go Stale

## What's actually going on

Unlike a local filesystem, where a process interacts with files through
kernel-managed inode structures it can trust to stay consistent, NFS
clients reference server-side files through an opaque token called a
**filehandle** — a blob of bytes the server hands back the first time a
client looks up a path, which the client then presents on every
subsequent operation instead of re-resolving the path each time. That
filehandle typically encodes, among other things, the filesystem's
identity (an `fsid`) and the specific inode it refers to — information
the server uses to find the right object quickly without a full path
lookup. Critically, the filehandle is generated once and cached; it is
never automatically refreshed just because time has passed or the
client re-reads the same path string.

`ESTALE` ("stale file handle") happens when the client presents a
filehandle whose encoded reference no longer resolves to anything valid
on the server — most commonly because the underlying filesystem object
was deleted and its inode number got reused by something else, or
(exactly what this lab does) because an entirely different filesystem
got mounted at the same export path, which changes the `fsid` component
embedded in every filehandle issued against the old one. From the
server's perspective, the client is asking about something that, as far
as the current filesystem is concerned, simply doesn't correspond to
anything real — there's no "retry later" available, because the
reference itself is permanently wrong, not temporarily unavailable.
This is exactly why `ESTALE` doesn't resolve on its own the way a
network blip does: retrying the same operation just presents the same
now-meaningless filehandle again.

Recovering requires the client to discard its cached filehandles and
get fresh ones — which is what re-mounting accomplishes, since a fresh
mount triggers fresh lookups from the root of the export. Any file
descriptor that was already open *before* the filehandle went stale
stays permanently stale even after the mount is fixed — remounting
doesn't retroactively repair already-open references, which is exactly
why Step 6 has to kill the old `tail -f` process specifically, not just
remount and hope.

`hard` vs `soft` and `umount -f` vs `umount -l` are really about the
same underlying question from two different angles: what should happen
to an operation that's currently stuck waiting on the server, and how
urgently do you need control back regardless of what that operation is
doing. `hard`/`soft` decide the *client's retry-vs-fail policy* before
anything gets stuck; `-f`/`-l` decide what to do with the *mount point
itself* after something already is.

## Where this shows up in the real world

Loopback NFS as used in this lab is a teaching convenience — real NFS
incidents typically involve an actual remote fileserver, but the exact
same mechanism applies: an NFS server rebuilt from backup, a storage
appliance failover that changes which physical filesystem backs an
export, or a Kubernetes NFS-backed PersistentVolume whose underlying
storage gets recreated, can all leave existing clients holding stale
filehandles against paths that still *look* the same from the outside.
It's a classic "the mount looks fine but nothing works" incident
specifically because `df`/`mount`/`mountpoint` all report success —
none of them actually exercise the filehandle, so none of them catch
the problem; only an actual read or write does.

## Go deeper

- **Website/docs:** `nfs(5)` man page — https://man7.org/linux/man-pages/man5/nfs.5.html — the canonical reference for NFS mount options, including `hard`/`soft`/`timeo`/`retrans`.
- **Website/docs:** `umount(8)` man page — https://man7.org/linux/man-pages/man8/umount.8.html — the authoritative reference for `-f` (force) vs `-l` (lazy) semantics.
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers file descriptor lifecycle and D-state/uninterruptible-sleep semantics directly relevant to why a stuck NFS read can't just be killed.
- **Website/docs:** Linux kernel NFS documentation — https://www.kernel.org/doc/html/latest/filesystems/nfs/index.html — official kernel-side NFS client/server documentation.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — has NFS setup/administration content alongside its broader Linux administration material.
