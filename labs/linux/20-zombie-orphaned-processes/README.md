# Lab 20 — Zombie and Orphaned Processes

## Objective
Build a real zombie-accumulation incident (a parent that forks children
and never `wait()`s on them), learn why `kill -9` on a zombie does
absolutely nothing, and contrast it with an **orphaned** process (parent
dies, child gets reparented to init and lives on normally) - the two are
constantly confused, and that confusion is exactly what this lab targets.

## Why this matters
"Zombie" and "orphan" get used interchangeably by people who haven't had
to actually debug either one, but they're opposites in the one way that
matters operationally: a zombie is a **dead** child whose exit status
hasn't been collected yet - there is no process left to signal, at all.
An orphan is a perfectly **alive** child whose original parent died first
- it just has a new parent now (normally PID 1 or a systemd subreaper),
and behaves like any other running process. Confusing the two leads
straight to the classic wrong move: trying to `kill -9` a zombie and
concluding the kill "didn't work," when the real fix is fixing or killing
the *parent* so it actually reaps its children.

## Prerequisites
- Linux VM, Python 3
- No root required for the main lab

Check first:
```bash
which python3
ps -eo pid,ppid,stat,cmd | head -1
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This starts a Python parent process that forks 20 children, each of which
exits almost immediately, and never calls `wait()`/`waitpid()` on any of
them.

## Step 2 — See the zombies
```bash
PARENT_PID=$(cat /var/tmp/zombielab/parent.pid)
ps -eo pid,ppid,stat,cmd | awk -v p="$PARENT_PID" '$2 == p'
```
You should see roughly 20 entries in state `Z` (zombie, shown as
`<defunct>` in the `cmd` column), all sharing the same `PPID` - the parent
you just started.

## Step 3 — Try to kill one (it won't work)
```bash
ZPID=$(ps -eo pid,ppid,stat --no-headers | awk -v p="$PARENT_PID" '$2==p && $3~/^Z/ {print $1; exit}')
sudo kill -9 "$ZPID"
ps -p "$ZPID" -o pid,ppid,stat,cmd
```
> Gotcha: the zombie is still there (or, `ps -p` finds nothing because it
> was reaped for an unrelated reason - re-check with the `ps -eo` command
> from Step 2 and you'll still see other zombies under the same parent
> untouched by your `kill`). `SIGKILL` has nothing to deliver it to - a
> zombie is not a running process, it's a leftover process-table entry
> holding an exit status. There is no task to schedule, no signal handler
> to invoke, nothing for `kill` to actually do.

## Step 4 — Confirm it's the parent's problem, not the child's
```bash
ps -o pid,ppid,stat,cmd -p "$PARENT_PID"
```
The parent is alive and well (state `S`, sleeping) - it's just never
calling `wait()`. Zombies exist specifically to hold onto an exit status
until *this* process asks for it.

## Step 5 — Fix it properly
The durable fix is patching the parent to actually reap its children:
```bash
kill -9 "$PARENT_PID"
cat > /var/tmp/zombielab/zombie_parent_fixed.py <<'EOF'
#!/usr/bin/env python3
import os, time

print(f"parent: pid={os.getpid()}, forking 20 children AND reaping them properly...", flush=True)
pids = []
for i in range(20):
    pid = os.fork()
    if pid == 0:
        time.sleep(0.2)
        os._exit(0)
    pids.append(pid)
    time.sleep(0.05)

for pid in pids:
    os.waitpid(pid, 0)

print("parent: all children reaped, no zombies. sleeping.", flush=True)
time.sleep(3600)
EOF
nohup python3 /var/tmp/zombielab/zombie_parent_fixed.py > /var/tmp/zombielab/parent.log 2>&1 &
echo $! > /var/tmp/zombielab/parent.pid
disown
sleep 3
ps -eo pid,ppid,stat,cmd | awk -v p="$(cat /var/tmp/zombielab/parent.pid)" '$2 == p'
```
No zombies this time - every child's exit status gets collected by
`waitpid()` the moment it's available.

> Gotcha: killing the buggy parent (without fixing the code) also makes
> the zombies disappear almost instantly - not because `kill` touched the
> zombies, but because once the parent is gone, its already-dead children
> get reparented to init/systemd, which immediately reaps anything already
> a zombie as part of adopting it. That's a legitimate emergency
> workaround (stop the bleeding right now), but it's not the same as
> fixing the bug - restart the same buggy code and you're right back here.

## Step 6 — Contrast: an orphan (alive, reparented, NOT a zombie)
```bash
bash -c 'sleep 300 & echo $! > /var/tmp/zombielab/orphan.pid; exit 0'
sleep 1
ORPHAN=$(cat /var/tmp/zombielab/orphan.pid)
ps -o pid,ppid,stat,cmd -p "$ORPHAN"
```
The `bash -c '...'` process forked `sleep 300` and then exited
immediately. `sleep 300` didn't die with it - it got reparented (`PPID` is
now `1` or your system's PID-1-equivalent/systemd) and is running totally
normally: state `S`, no zombie, nothing wrong at all. This is an orphan.
It is alive. It will be reaped properly, the ordinary way, whenever it
actually exits - because its new parent (init/systemd) *does* call
`wait()`.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — find the leak among a room full of processes:**
```bash
for i in 1 2 3; do
    nohup python3 /var/tmp/zombielab/zombie_parent.py > /var/tmp/zombielab/svc$i.log 2>&1 &
    echo $! >> /var/tmp/zombielab/extra_parents.pid
    disown
done
sleep 3
```
Now there are several unrelated-looking parent processes on the box, each
leaking zombies, mixed in with everything else already running. Without
assuming you already know the PIDs (pretend you just got paged and don't):
find every zombie system-wide, group them by parent PID, and identify
which parent(s) are responsible and how many zombies each is holding.
Then think about the risk if this ran unbounded for days: each zombie
still occupies a slot in the kernel's finite PID space
(`cat /proc/sys/kernel/pid_max`) until reaped - what's the actual failure
mode if nobody catches this before PIDs run out?

**Challenge B — is this a zombie or an orphan, and does `kill -9` do
anything?**
```bash
ps -eo pid,ppid,stat,cmd | grep -E 'sleep 300|zombie_parent'
```
Run this while both Step 6's orphaned `sleep 300` and Step 2's zombies (or
Challenge A's, if you're continuing from there) are still around. Without
looking back at earlier steps, use only the `STAT` column and `PPID` to
work out, for each PID in that output, whether it's a zombie or an orphan
- then run `kill -9` on one of each and predict the outcome *before* you
run it. Explain why the same command produces two completely different
results depending on which kind of process you targeted.

See `solution.md` only after you've formed your own diagnosis.
