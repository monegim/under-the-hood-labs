# Lab 26 — Solutions

## Challenge A — multiple writers, multiple deleted inodes

**Check:**
```bash
df -h /var/tmp
sudo lsof +L1 | grep -i lab26
```
You'll see two separate `bash` PIDs, each holding fd 3 open to its own
`app.log (deleted)` entry, with two different inode numbers (the column
right before the block-size/offset numbers in `lsof` output). `du -sh
/var/tmp/lab26` still shows almost nothing, because neither deleted file
has a directory entry anymore.

**Diagnosis:** each run of `setup.sh` started an independent writer and
deleted its own file. Nothing in the setup script checks for or cleans up
a previous run, so the two incidents just stack. This is exactly what
happens in production when the same "rotate without reopening" bug fires
on multiple log files, or the same buggy rotation cron fires more than
once before anyone notices — each occurrence is a separate leak, and
`lsof +L1` (system-wide) is the only way to see all of them at once
instead of chasing them one at a time.

**Fix:**
```bash
sudo lsof +L1 | grep -i lab26 | awk '{print $2, $4}' | sort -u
# for each PID/FD pair found:
sudo sh -c ": > /proc/<PID>/fd/<FD>"
```
Or, since this is a lab and both writers are disposable:
```bash
pkill -f 'app.log'
```

**Lesson:** never assume there's exactly one offender. Search system-wide
(`lsof +L1`, no path filter) before declaring the incident closed — a
partial fix that still leaves one leaking process is why disk usage climbs
right back up an hour later.

---

## Challenge B — killing the parent isn't enough

**Check:**
```bash
PARENT=$(cat /var/tmp/lab26b/parent.pid)
CHILD=$(cat /var/tmp/lab26b/child.pid)
kill "$PARENT"
sleep 3
df -h /var/tmp
sudo lsof +L1 | grep -i lab26b
ps -o pid,ppid,stat,cmd -p "$PARENT" -p "$CHILD"
```
`df` usage keeps climbing. `lsof` still shows an open, growing fd to the
deleted file — but now on the *child's* PID, not the parent's. `ps` shows
the parent (`$PARENT`) as `Z` (zombie/`<defunct>`) — it's dead, just not
reaped yet — while the child is still alive and running.

**Diagnosis:** when the parent process did `exec 3>>app.log` and then
forked a background worker, that `fork()` duplicated the parent's entire
file descriptor table into the child — including fd 3. From that point on,
fd 3 in the parent and fd 3 in the child point at the same open file
description (same inode, same offset), but they are two **independent**
references. Killing the parent only closes the parent's copy of fd 3; the
child's copy is untouched and keeps the inode (and the disk space) alive.
This is exactly the shape of the bug in real prefork servers (Apache
`prefork` MPM, PHP-FPM, Gunicorn workers) — a master process opens a log
file before forking workers, and every worker inherits that fd. "Restart
the app" often means restarting the master, which does nothing for
workers still holding the old fd unless they get killed too (or the master
does a full stop-then-start instead of a graceful reload).

**Fix — either works, but they teach different lessons:**
```bash
# Option 1: kill every remaining holder
sudo lsof +L1 | grep -i lab26b | awk '{print $2}' | sort -u | xargs -r kill

# Option 2: truncate via ANY one of the fds — it's the same inode,
# so it doesn't matter which PID's fd you go through
sudo sh -c ": > /proc/$CHILD/fd/3"
```
Option 2 reclaims the space immediately regardless of how many processes
still hold the file open, because truncation acts on the underlying inode,
not on any one process's reference to it.

**Lesson:** "restart the process" is not one action — if the process you
killed had already forked children that inherited the same fd, the leak
survives the restart. Always re-check (`lsof +L1`) after a "fix" instead of
assuming the first kill worked; and prefer truncating the fd directly when
you're not 100% sure you've found every holder.
