# Lab 14 — Swap Exhaustion

## Objective
Fill a dedicated swap file completely, watch a cgroup-scoped OOM kill
happen because there's no swap left to relieve memory pressure — not
because RAM itself ran out — and understand exactly why `vm.swappiness`
won't save you once swap is genuinely full.

## Why this matters
This is a different failure from "the box ran out of memory." A box can
have plenty of *RAM* headroom and still OOM-kill something, if the
specific cgroup a process lives in hits its memory limit and the swap
available to relieve that pressure is exhausted — two independent
capacity numbers (RAM headroom, swap headroom) that both have to hold
for a memory-hungry process to survive gracefully. `free -h`'s Swap row
reading near-zero available is a distinct signal from its Mem row
reading low, and conflating them sends you looking in the wrong place.

## Prerequisites
- A Linux VM, `sudo` access, cgroup v2 (unified hierarchy)
- `python3` (used only for the memory hog)

Check first:
```bash
stat -fc %T /sys/fs/cgroup   # should print "cgroup2fs"
python3 --version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates a dedicated 64M swapfile (your VM's own pre-existing swap,
if any, is never touched), a cgroup with `memory.max=200M`, and starts a
Python process inside that cgroup that allocates and touches 1MB at a
time, forever.

## Step 2 — Watch it fill
```bash
watch -n1 'free -h; echo; swapon --show; echo; cat /proc/swaps'
```
Watch the `Swap` row's `used` column climb toward the total as the
cgroup's memory pressure pushes anonymous pages out of RAM and into the
only swap available to it.

## Step 3 — Confirm the OOM kill
```bash
sudo journalctl -k --since "5 minutes ago" | grep -i "killed process\|out of memory"
tail -20 /var/lib/swaplab14/hog.log
```
Once swap is full *and* the cgroup's `memory.max` is also hit, there's
nowhere left to reclaim to — the cgroup-scoped OOM killer fires and
kills the hog (or whatever else happens to be in that cgroup).

## Step 4 — Confirm swap is actually the constraint, not RAM
```bash
free -h
```
Compare `Mem`'s `available` column to `Swap`'s `available` column —
system RAM headroom can look completely fine while swap specifically
reads at or near zero.

## Step 5 — Fix it: add emergency swap
```bash
sudo fallocate -l 128M /var/lib/swaplab14/emergency-swap
sudo chmod 600 /var/lib/swaplab14/emergency-swap
sudo mkswap /var/lib/swaplab14/emergency-swap
sudo swapon /var/lib/swaplab14/emergency-swap
swapon --show
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `swapoff` isn't free:**
```bash
./reset.sh
sleep 25   # let the swapfile actually fill first
sudo swapoff /var/lib/swaplab14/swapfile
```
Time how long this takes, and watch what happens to the system while
it's running (`vmstat 1` in another terminal). `swapoff` has to move
every currently-swapped-out page back into RAM before it can finish —
figure out what that means for a system where RAM is *also* under
pressure, and why "just turn the full swap off" isn't automatically a
safe, fast operation.

**Challenge B — `vm.swappiness=0` doesn't fix this:**
```bash
./reset.sh
sudo sysctl vm.swappiness=0
sleep 30
free -h
swapon --show
```
Swap fills up anyway, at essentially the same rate. `vm.swappiness`
supposedly controls the kernel's preference for swapping — so why did
setting it to the most conservative possible value not prevent this at
all? Figure out exactly what swappiness does and doesn't control, and
under what conditions it stops mattering entirely.

See `solution.md` only after you've formed your own diagnosis.
