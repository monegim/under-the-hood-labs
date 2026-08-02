# Lab 3 — cgroups (v2)

## Objective
Build a cgroup by hand under the cgroup v2 unified hierarchy, put a process
in it, cap its memory and CPU, and watch the CGROUP controller (not the
system OOM killer) enforce the limit.

## Why this matters
`docker run --memory=100m --cpus=0.5` and Kubernetes
`resources.limits.memory`/`resources.limits.cpu` do exactly what this lab
does by hand: write numbers into `memory.max` and `cpu.max` files under
`/sys/fs/cgroup/`. When you see a pod status `OOMKilled`, or a
`container_cpu_cfs_throttled_seconds_total` metric climbing in Grafana,
this lab is the actual mechanism behind both.

## Prerequisites
- cgroup v2 (unified hierarchy) mounted
- `stress-ng` for generating controlled memory/CPU load
- `sudo` access

Check first:
```bash
mount | grep cgroup2
stat -fc %T /sys/fs/cgroup
cat /sys/fs/cgroup/cgroup.controllers
sudo apt-get update && sudo apt-get install -y stress-ng
```
`stat -fc %T /sys/fs/cgroup` should print `cgroup2fs`. If it doesn't, your
distro is running in hybrid (v1+v2) mode and paths in this lab may differ.

## Step 1 — Create a cgroup and enable controllers
```bash
sudo mkdir /sys/fs/cgroup/lab3
ls /sys/fs/cgroup/lab3
```
Notice the new directory has almost nothing useful in it yet — no
`memory.max`, no `cpu.max`. Controllers have to be explicitly delegated from
the parent:
```bash
cat /sys/fs/cgroup/cgroup.controllers
echo "+memory +cpu +pids" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
ls /sys/fs/cgroup/lab3
```
Now `memory.max`, `cpu.max`, `pids.max`, `cgroup.procs`, etc. exist.

> Gotcha: in cgroup v2, enabling a controller for a cgroup's CHILDREN is
> done by writing to the PARENT's `cgroup.subtree_control`, not the child's.
> This trips people up constantly — a fresh cgroup directory does not
> automatically support every controller; it has to be delegated top-down.
> The root cgroup is the one exception to the "no processes + controls"
> rule, which is why we can enable controllers here even though `/sys/fs/cgroup`
> itself has plenty of processes directly in it.

## Step 2 — Memory limit
```bash
echo $((50*1024*1024)) | sudo tee /sys/fs/cgroup/lab3/memory.max
cat /sys/fs/cgroup/lab3/memory.max
```
50 MiB hard cap. Now join the current shell to the cgroup — every process
you launch from this shell from now on will be a member too:
```bash
echo $$ | sudo tee /sys/fs/cgroup/lab3/cgroup.procs
cat /sys/fs/cgroup/lab3/cgroup.procs
```
Push past the limit:
```bash
stress-ng --vm 1 --vm-bytes 150M --vm-keep --timeout 30s
```
Check what happened:
```bash
dmesg -T | tail -20
cat /sys/fs/cgroup/lab3/memory.events
```
Look for a line like `Memory cgroup out of memory: Killed process ...` in
`dmesg`, and a non-zero `oom_kill` counter in `memory.events`. This is the
cgroup's own OOM killer acting — scoped to processes inside `lab3` — not
the system-wide OOM killer.

## Step 3 — CPU limit
`cpu.max` format is `$MAX $PERIOD` in microseconds — "50000 100000" means
50ms of CPU time allowed per 100ms period, i.e. 50% of one CPU:
```bash
echo "50000 100000" | sudo tee /sys/fs/cgroup/lab3/cpu.max
```
Still in the same shell (still a cgroup member), burn CPU:
```bash
stress-ng --cpu 1 --timeout 20s
```
In another terminal, watch enforcement happen:
```bash
watch -n1 cat /sys/fs/cgroup/lab3/cpu.stat
```
Watch `nr_throttled` and `throttled_usec` climb, and confirm with `top` that
the `stress-ng` worker is pinned around 50% CPU even if the box has idle
cores elsewhere.

## Step 4 — Tie it to containers
```bash
cat /sys/fs/cgroup/lab3/memory.current
cat /sys/fs/cgroup/lab3/cgroup.procs
```
This is precisely what `docker run --memory=50m --cpus=0.5 <image>` sets up
for you automatically, and what a Kubernetes pod's `resources.limits` get
translated into by the container runtime (containerd/CRI-O) on the node.
Clean up when done:
```bash
exit    # leave the shell you joined to the cgroup
sudo rmdir /sys/fs/cgroup/lab3
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — you limited more than you meant to:**
```bash
sudo mkdir /sys/fs/cgroup/lab3b
echo "+memory" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
echo $$ | sudo tee /sys/fs/cgroup/lab3b/cgroup.procs
echo $((10*1024*1024)) | sudo tee /sys/fs/cgroup/lab3b/memory.max
```
Now just try running an ordinary command in this same shell, e.g.:
```bash
apt list --installed
```
Something unexpected happens to your shell. Figure out why an "unrelated"
command management action caused this, given you only meant to constrain
one workload.

**Challenge B — throttled despite "plenty" of quota:**
```bash
sudo mkdir /sys/fs/cgroup/lab3c
echo "+cpu" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
echo $$ | sudo tee /sys/fs/cgroup/lab3c/cgroup.procs
echo "50000 100000" | sudo tee /sys/fs/cgroup/lab3c/cpu.max
stress-ng --cpu 4 --cpu-load 100 --timeout 20s
```
Watch `cpu.stat` (`nr_throttled`, `throttled_usec`) during this run. The
quota looks generous (50% of a CPU) but the workers get throttled hard and
fast. This is one of the most commonly misunderstood Kubernetes production
issues — figure out what "50000 100000" actually means when more than one
thread/process is running concurrently in the same cgroup.

See `SOLUTION.md` only after you've formed your own diagnosis.
