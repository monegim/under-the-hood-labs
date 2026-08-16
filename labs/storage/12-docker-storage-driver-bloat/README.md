# Lab 12 — Docker Storage Driver Bloat

## Objective
Fill up `/var/lib/docker` with dangling images, stopped containers, and
unused volumes until disk space runs out, then learn to actually see
where the space went with `docker system df` and reclaim it safely with
`docker system prune` — including the important gotcha that `-a` and
`--volumes` remove things a lot of people don't expect them to.

## Why this matters
Docker's `overlay2` storage driver keeps every image layer, every
stopped container's writable layer, and every named volume on disk until
something explicitly removes them — `docker stop` and even `docker rm`
don't touch layers other containers might still reference, and building
a new image version doesn't delete the old one's layers automatically.
On a host doing regular builds and deploys, this accumulates
continuously and silently: `df -h` eventually shows the root filesystem
filling up, but `df` has no idea *what* inside `/var/lib/docker` is
actually reclaimable versus in active use. `docker system df` is the
tool that answers that question, and `docker system prune` is how you
act on it — but reaching for `docker system prune -a --volumes` as a
reflex is how people accidentally delete a volume holding a database
nobody meant to touch.

## Prerequisites
- Linux VM, `sudo` access, Docker installed and running
- This lab uses a **dedicated loop-device-backed filesystem mounted at
  `/mnt/dockerlab`, with Docker's data-root pointed at it** via a
  temporary daemon config — not your host's real `/var/lib/docker` — so
  filling it up and pruning it doesn't touch anything else on the VM.

Check first:
```bash
which docker dockerd
sudo systemctl is-active docker
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates a 1G loop-device-backed ext4 filesystem mounted at
`/mnt/dockerlab`, points a second `dockerd` instance at it as its
data-root, then builds several small image versions (each producing a
dangling old image when rebuilt), runs and stops a handful of
containers, and creates a few named volumes — none of it removed, the
way a build host that never cleans up behaves after a while.

## Step 2 — See how full the storage is
```bash
df -h /mnt/dockerlab
```
`Use%` is climbing toward full on a filesystem that's supposed to be
"just Docker."

## Step 3 — See what Docker itself thinks is using the space
```bash
sudo docker -H unix:///var/run/dockerlab.sock system df
sudo docker -H unix:///var/run/dockerlab.sock system df -v
```
The summary view breaks space down by images, containers, and volumes,
including a **RECLAIMABLE** column. The `-v` (verbose) view lists every
individual image, container, and volume with its size and whether
anything currently references it.

## Step 4 — Find the dangling images specifically
```bash
sudo docker -H unix:///var/run/dockerlab.sock images -f dangling=true
```
These are image layers left behind by rebuilds — no tag points at them
anymore, but they weren't automatically deleted when superseded.

## Step 5 — Reclaim space the safe, incremental way
```bash
sudo docker -H unix:///var/run/dockerlab.sock container prune -f
sudo docker -H unix:///var/run/dockerlab.sock image prune -f
sudo docker -H unix:///var/run/dockerlab.sock system df
```
`container prune` removes stopped containers; plain `image prune`
(without `-a`) removes only dangling (untagged, unreferenced) images —
it leaves every tagged image alone, even ones with no running container,
because a tagged image might be needed again for the next deploy.
Compare `system df`'s **RECLAIMABLE** column before and after.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `-a` removes more than "the obviously unused stuff":**
```bash
sudo docker -H unix:///var/run/dockerlab.sock images
sudo docker -H unix:///var/run/dockerlab.sock image prune -a -f
sudo docker -H unix:///var/run/dockerlab.sock images
```
Compare the image list before and after. Diagnose exactly which
additional images `-a` removed that plain `image prune` left alone in
Step 5, and think through what breaks on a real build host if a
scheduled job runs this flag without anyone realizing what it actually
does to tagged-but-currently-unused images.

**Challenge B — `--volumes` doesn't ask twice:**
```bash
sudo docker -H unix:///var/run/dockerlab.sock volume ls
sudo docker -H unix:///var/run/dockerlab.sock run -d --name statefulcheck \
    -v dockerlab_appdata:/data alpine:latest sleep 30
sudo docker -H unix:///var/run/dockerlab.sock exec statefulcheck \
    sh -c 'echo "important" > /data/marker.txt'
sudo docker -H unix:///var/run/dockerlab.sock stop statefulcheck
sudo docker -H unix:///var/run/dockerlab.sock rm statefulcheck
sudo docker -H unix:///var/run/dockerlab.sock system prune -a -f --volumes
sudo docker -H unix:///var/run/dockerlab.sock volume ls
```
Diagnose what happened to `dockerlab_appdata` and the file just written
into it, exactly which of the two commands before the prune actually
made that volume eligible for removal (stopping the container, or
removing it), and which single flag on the `system prune` line was
responsible for volumes being touched at all. Think through how often a
real deploy (recreate a container against the same named volume) passes
through that exact same "volume exists, nothing currently references
it" window.

See `solution.md` only after you've formed your own diagnosis.
