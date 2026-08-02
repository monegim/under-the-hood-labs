# Lab 5 — Concept: Overlay Filesystems

## What's actually going on

Overlayfs is a stackable filesystem — it doesn't store any bytes itself, it
composes a single merged view out of one or more existing directory trees
(`lowerdir`, possibly many, colon-separated) and one writable directory
(`upperdir`), all of which can live on entirely different underlying
filesystems (ext4, xfs, whatever). The kernel builds this merged view at the
VFS layer: for each path, overlayfs looks up dentries in `upperdir` first,
falls back to each `lowerdir` in order, and presents a single unified
directory listing and file namespace to anything reading through `merged`.
Crucially, the lower layers are treated as strictly read-only by the overlay
itself — overlayfs never writes into `lowerdir`, no matter what operation you
perform through `merged`. That constraint is what makes the whole design
work: you can stack the same read-only lower layers under many different
`upperdir`s simultaneously (many containers sharing one base image layer)
with zero risk of one container's writes affecting another's view, because
structurally nothing ever touches the lower layers' actual bytes.

Copy-up is the mechanism that makes "modify a file that lives in a read-only
lower layer" work without violating that read-only guarantee. The first time
a write touches a file that only exists in `lowerdir`, overlayfs doesn't
modify it in place — it copies the *entire file* up into `upperdir`
(preserving metadata), then redirects all subsequent access for that path to
the upper copy. `workdir` exists purely to make this copy-up atomic: the file
is staged there and then atomically renamed into place in `upperdir`, which
is only possible if `workdir` and `upperdir` are on the same filesystem
(atomic `rename()` doesn't cross filesystem boundaries) — this is exactly the
constraint Challenge A violates by putting `workdir` on a separate tmpfs.
This is also why editing one byte of a huge file in a container is
disproportionately expensive the first time: the entire file gets copied up,
not just the changed byte, so write-heavy workloads against large files that
originated in a base image can be far slower than the same operation against
a file that was already in the writable layer.

Deletion of a lower-only file (Step 4) can't actually erase anything from
the lower layer either — for the same read-only reason — so overlayfs
fabricates a *whiteout*: a character device special file with major/minor
number 0:0, created in `upperdir` at the same relative path as the deleted
file. When building the merged view, overlayfs treats a whiteout entry as an
explicit "this path does not exist here, stop looking in lower layers"
marker, rather than as a real device node. The underlying bytes are still
sitting untouched in `lowerdir` — this is precisely why deleting a file
inside a running container's writable layer never shrinks the base image on
disk, and why layer "squashing" (`docker build --squash` or multi-stage
builds) is a separate, deliberate operation to actually reclaim that space by
flattening whiteout-masked layers together.

Challenge B's "don't poke `upperdir` directly while mounted" rule follows
from overlayfs maintaining its own in-kernel cache of dentries and inodes
built from what it observed *through the mount* — it isn't re-scanning the
underlying directories on every lookup. Writing into `upperdir` through a
different path (bypassing the `merged` mountpoint) changes the on-disk state
without going through any of overlayfs's own bookkeeping, so its cached view
and the actual directory contents can disagree, and the kernel's own docs
explicitly call the result undefined behavior. This isn't a bug you can work
around — it's a structural consequence of overlayfs being a caching layer on
top of ordinary directories rather than a filesystem that owns its own
on-disk format the way ext4 or xfs does.

## Where this shows up in the real world

Docker's `overlay2` storage driver (the default on essentially every modern
Docker install, and what containerd uses too) is a thin, mostly-configuration
wrapper around exactly this kernel filesystem: each image layer is a
`lowerdir`, a running container's writable layer is its own private
`upperdir`/`workdir` pair under `/var/lib/docker/overlay2/<id>/`, and `diff`
and `merged` subdirectories in that path correspond directly to this lab's
`upper` and `merged`. The single most common real-world mistake this
maps to is exactly Challenge B: someone reaches directly into
`/var/lib/docker/overlay2/<container-id>/diff` to "quickly patch" a file
inside a running container instead of going through the container's own
filesystem (`docker cp`, or a shell inside the container) — Docker's own
docs warn against this for the identical reason the kernel does. Knowing
that a container's writable layer is nothing but an `upperdir`, and that
copy-up/whiteout is the entire mechanism behind "container storage grows
unexpectedly" or "deleting files doesn't reclaim image size," turns a
confusing disk-usage mystery into a five-minute `du` + layer-inspection
exercise instead of hours of guessing at "Docker storage bugs."

## Go deeper

- **Website/docs:** Linux kernel overlayfs docs — https://docs.kernel.org/filesystems/overlayfs.html — the official, authoritative source on `lowerdir`/`upperdir`/`workdir` semantics, copy-up, and whiteouts; this is the primary reference for everything in this lab.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/overlayfs.5.html — man page cross-reference for the mount options used in this lab.
- **Website/blog:** iximiuz Labs — https://iximiuz.com/en/posts/ — Ivan Velichko has posts specifically decomposing Docker image layers and overlay2 storage into the raw overlayfs mechanics; search for "overlay" or "image layers."
- **Book:** *Container Security* — Liz Rice — covers container filesystem layering (including overlayfs) from a "what can go wrong" security angle relevant to Challenge B.
- **Website/docs:** Docker's own storage driver docs (docs.docker.com, under "Storage drivers" / "overlayfs driver") — explains the `diff`/`merged`/`work` directory layout directly mapped from this lab; search "docker overlay2 storage driver" if not linking a specific URL you're unsure of.
