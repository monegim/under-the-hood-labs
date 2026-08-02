# Lab 5 — Overlay Filesystems

## Objective
Build an overlayfs mount by hand from `lowerdir`/`upperdir`/`workdir`,
watch copy-on-write happen file by file, and understand exactly what a
Docker image layer stack and a container's writable layer really are.

## Why this matters
Docker's `overlay2` storage driver (the default on virtually every modern
install) is a thin wrapper around exactly this kernel filesystem. Every
image layer is a `lowerdir`, the container's writable layer is the
`upperdir`, and "copy-up" is why editing a 1-byte file in a huge base image
doesn't rewrite gigabytes of data, why deleting a file in a running
container doesn't shrink the image, and why write-heavy workloads inside
containers can be slower than expected.

## Prerequisites
- overlay kernel module available
- `sudo` access

Check first:
```bash
cat /proc/filesystems | grep overlay
lsmod | grep overlay || sudo modprobe overlay
```

## Step 1 — Lay out the directories
```bash
OVL=$HOME/ovl
mkdir -p $OVL/{lower,upper,work,merged}
echo "from lower" > $OVL/lower/file1.txt
echo "from lower, shared" > $OVL/lower/file2.txt
```

## Step 2 — Mount the overlay
```bash
sudo mount -t overlay overlay \
  -o lowerdir=$OVL/lower,upperdir=$OVL/upper,workdir=$OVL/work \
  $OVL/merged
ls $OVL/merged
```
`merged` shows both files, sourced entirely from `lower` — `upper` is
still empty.

> Gotcha: `workdir` must be empty and on the SAME filesystem as `upperdir`
> — overlayfs uses it internally for atomic operations during copy-up.
> Mixing filesystems here is a real, common overlayfs mount failure (see
> Challenge A).

## Step 3 — Copy-on-write, watch it happen
```bash
echo "modified in merged" >> $OVL/merged/file1.txt
ls $OVL/upper
cat $OVL/lower/file1.txt
cat $OVL/merged/file1.txt
```
`file1.txt` now exists in `upper` (the copy-up just happened) — `lower`'s
copy is untouched. This is exactly what happens the first time a process
inside a container writes to a file that only exists in a read-only image
layer.

## Step 4 — Deleting a lower-only file
```bash
rm $OVL/merged/file2.txt
ls $OVL/merged
cat $OVL/lower/file2.txt
ls -la $OVL/upper
stat $OVL/upper/file2.txt
```
`file2.txt` is gone from `merged`, but still fully intact in `lower`. Look
closely at what appeared in `upper` instead.

> Gotcha: deleting a file that only exists in a lower layer doesn't delete
> any data — it creates a "whiteout" (a character device node, major/minor
> 0:0) in `upperdir` that masks the lower file from the merged view. This
> is exactly why `docker rm`-ing a file inside a running container doesn't
> shrink the underlying image: the bytes are still sitting in the
> read-only lower layers, just hidden.

## Step 5 — New files go straight to upper
```bash
echo "brand new" > $OVL/merged/file3.txt
ls $OVL/upper
```
No copy-up needed — it never existed in `lower`, so it's written directly.

## Step 6 — Stack multiple lower layers (like Docker image layers)
```bash
mkdir -p $OVL/lower2
echo "from lower2" > $OVL/lower2/file4.txt
sudo umount $OVL/merged
sudo mount -t overlay overlay \
  -o lowerdir=$OVL/lower2:$OVL/lower,upperdir=$OVL/upper,workdir=$OVL/work \
  $OVL/merged
ls $OVL/merged
```
`lowerdir` is colon-separated, and the LEFTMOST entry has the highest
precedence (topmost layer) — same ordering convention as Docker's image
layer stack, where the last-applied layer wins on file conflicts.

## Step 7 — Clean up
```bash
sudo umount $OVL/merged
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — upperdir and workdir on different filesystems:**
```bash
sudo mkdir -p /tmp/ovltest
sudo mount -t tmpfs tmpfs /tmp/ovltest
mkdir -p /tmp/ovltest/work
sudo mount -t overlay overlay \
  -o lowerdir=$OVL/lower,upperdir=$OVL/upper,workdir=/tmp/ovltest/work \
  $OVL/merged
```
The mount fails. This is a genuine Docker `overlay2` storage driver gotcha
— figure out exactly which constraint this violates and why overlayfs
enforces it.

**Challenge B — poking the upper layer directly while mounted:**
```bash
sudo mount -t overlay overlay \
  -o lowerdir=$OVL/lower,upperdir=$OVL/upper,workdir=$OVL/work \
  $OVL/merged
echo "tampered directly" >> $OVL/upper/file1.txt
cat $OVL/merged/file1.txt
diff <(cat $OVL/upper/file1.txt) <(cat $OVL/merged/file1.txt)
```
You modified a file inside `upperdir` directly, bypassing the `merged`
mountpoint entirely, while the overlay is still mounted. Compare what
`upper` and `merged` report. This maps directly to poking at Docker's
`/var/lib/docker/overlay2/<id>/diff` directory by hand while a container
using it is running — figure out why that's explicitly documented as
unsafe.

See `SOLUTION.md` only after you've formed your own diagnosis.
