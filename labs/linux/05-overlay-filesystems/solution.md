# Lab 5 — Solutions

## Challenge A — upperdir and workdir on different filesystems

**Check:**
```bash
dmesg | tail -5
```
The `mount` command fails outright, typically with something like
`mount: /home/.../merged: wrong fs type, bad option, bad superblock` and
`dmesg` showing an overlayfs-specific complaint about `workdir` and
`upperdir`.

**Diagnosis:** overlayfs requires `upperdir` and `workdir` to live on the
SAME underlying filesystem. `workdir` is used internally for atomic
rename-based operations during copy-up (a file is first prepared in
`workdir`, then atomically moved into `upperdir`) — that atomicity
guarantee only holds if both directories are on one filesystem, since
atomic rename across filesystems isn't possible. Here, `upperdir` is on
your regular disk-backed filesystem and `workdir` is on a separate tmpfs
mount — two different filesystems, so the kernel refuses the mount.

**Fix:**
```bash
mkdir -p $OVL/work
sudo mount -t overlay overlay \
  -o lowerdir=$OVL/lower,upperdir=$OVL/upper,workdir=$OVL/work \
  $OVL/merged
```
Put `workdir` back on the same filesystem as `upperdir`.

**Lesson:** `upperdir` and `workdir` are not independent configuration
knobs — they're a matched pair that must share a filesystem. This is
exactly why Docker's `overlay2` storage driver keeps a container's `diff`
(upper) and `work` directories side by side under the same
`/var/lib/docker/overlay2/<id>/` path rather than letting you point them
at arbitrary separate mounts.

---

## Challenge B — poking the upper layer directly while mounted

**Check:**
```bash
diff <(cat $OVL/upper/file1.txt) <(cat $OVL/merged/file1.txt)
```
Depending on kernel version and caching state, `merged` may not
immediately reflect the direct edit to `upper`, or directory/inode
metadata between the two views can become inconsistent for a while.

**Diagnosis:** overlayfs maintains its own in-kernel cache of the merged
view (dentries/inodes) built from the state of `lowerdir`/`upperdir` at
mount time and as seen through its own mount operations. The kernel
documentation for overlayfs explicitly states that the underlying
`upperdir`/`lowerdir` directories must not be modified by any means other
than through the overlay mount itself — doing so is documented as
producing undefined behavior. Writing directly into `upper`, bypassing
`merged`, sidesteps overlayfs's own bookkeeping entirely.

**Fix:** there isn't one — this is a "don't do this" scenario, not a bug to
patch. If a change needs to happen, make it through `$OVL/merged`, never
directly against `upper` or `lower` while the overlay is mounted.

**Lesson:** this exact mistake happens in production when someone reaches
directly into Docker's `/var/lib/docker/overlay2/<container-id>/diff`
directory to "quickly fix" a file inside a running container's writable
layer instead of going through the container's own filesystem view —
Docker's docs warn against this for the same reason: the overlay's
in-kernel state and the on-disk directories can disagree once you bypass
the mount.
