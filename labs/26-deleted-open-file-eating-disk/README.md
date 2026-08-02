# Lab 26 — Deleted-But-Open File Eating Disk

## Objective
Reproduce the classic "`df` says the disk is full but `du` can't find any big
files" incident, find the culprit with `lsof`/`/proc`, and reclaim the space
without a full service restart.

## Why this matters
On Linux, deleting a file only unlinks its name from the directory. If a
process still has the file open, the inode and its data blocks stay alive —
the space is not freed until every process holding an fd to it closes that
fd. This happens constantly in production: a naive log-rotation cron job
does `mv app.log app.log.1 && touch app.log` (or just `rm`s old logs) without
sending the app a signal (`SIGHUP`/`logrotate`'s `postrotate` hook) to reopen
its log file. The app keeps writing into the "deleted" file forever, disk
usage climbs, and `du -sh /var/log` shows nothing near the size `df` reports
missing — because `du` walks directory entries, and this file has none
anymore.

## Prerequisites
- `lsof`, `fuser`, `bash`, `/proc` mounted (standard on any Linux VM)
- `sudo` access

Check first:
```bash
which lsof fuser
df -h /var/tmp
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This starts a background process writing to `/var/tmp/lab26/app.log`, lets
it run for a few seconds, then deletes the file out from under it —
simulating a log-rotation job that never told the app to reopen its log.

## Step 2 — Confirm the confusing symptom
```bash
df -h /var/tmp
ls -la /var/tmp/lab26/
du -sh /var/tmp/lab26/
```
> The file is gone from `ls`/`du`'s point of view, but `df` on the
> filesystem still shows the space in use. This mismatch — `df` vs `du`
> disagreeing — is the signature of this exact incident class. It is
> almost always a deleted-but-open file (or a bind mount hiding data
> underneath it — different lab, same "df/du disagree" symptom).

## Step 3 — Find the process holding it open
```bash
sudo lsof +L1 | grep -i lab26
```
`+L1` shows only files with a link count under 1 — i.e., unlinked
(deleted) files still open. You should see something like:
```
bash    12345  root    3w   REG   0,50   52428800      0 12345678 /var/tmp/lab26/app.log (deleted)
```
The `(deleted)` marker and the `0` link count are the tell. Note the PID
(`12345`) and the fd number (`3`).

Cross-check with `/proc` directly:
```bash
WRITER_PID=$(cat /var/tmp/lab26/writer.pid)
ls -la /proc/$WRITER_PID/fd/
```
> Gotcha: the symlink target in `/proc/<pid>/fd/<N>` will literally read
> `/var/tmp/lab26/app.log (deleted)`. That suffix is added by the kernel
> for display purposes only — it's not part of any real path, don't try to
> `cat` it.

## Step 4 — Confirm the size matches what `df` is missing
```bash
sudo ls -la /proc/$WRITER_PID/fd/3
```
The size shown here (via `stat`, since `ls -la` on a `/proc/fd` symlink
shows the symlink itself, not the target) — use:
```bash
sudo stat -L /proc/$WRITER_PID/fd/3
```
That's exactly the space `df` sees as used and `du` can't account for.

## Step 5 — Fix it without killing the process
You have two real options in production:

**Option A — truncate the fd in place (no restart, no dropped writes):**
```bash
sudo sh -c ": > /proc/$WRITER_PID/fd/3"
```
This truncates the underlying (still-open) inode to zero length. The
process keeps its fd, keeps writing, disk space is reclaimed immediately.
This is the preferred fix for a service you can't afford to restart.

**Option B — restart the process:**
```bash
kill "$(cat /var/tmp/lab26/writer.pid)"
```
On restart, most apps reopen their log file by path and get a fresh,
correctly-named inode. This is the "just restart it" fix — works, but
costs you an outage window and loses in-flight state.

Verify space is reclaimed:
```bash
df -h /var/tmp
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A:**
```bash
./setup.sh
./setup.sh
```
Run `setup.sh` twice in a row without cleaning up in between. You now have
two independent writer processes (two different PIDs), each holding open a
fd to its own now-deleted inode. `df` shows more space missing than a
single writer would explain. Find every offending process — not just the
first one you spot — and reclaim all the space.

**Challenge B:**
```bash
mkdir -p /var/tmp/lab26b
rm -f /var/tmp/lab26b/app.log
bash -c '
  exec 3>>/var/tmp/lab26b/app.log
  echo $$ > /var/tmp/lab26b/parent.pid
  ( while true; do head -c 1048576 /dev/urandom >&3; sleep 2; done ) &
  echo $! > /var/tmp/lab26b/child.pid
  wait
' &
disown
sleep 3
rm -f /var/tmp/lab26b/app.log
```
This simulates a prefork-style app (think Apache/PHP-FPM/Gunicorn): a
parent opens the log file, then forks a worker that inherits the same open
fd. Now try the "obvious" fix:
```bash
kill "$(cat /var/tmp/lab26b/parent.pid)"
df -h /var/tmp
```
Space isn't reclaimed. Figure out why killing the parent wasn't enough,
and what the correct fix is here.

See `SOLUTION.md` only after you've formed your own diagnosis.
