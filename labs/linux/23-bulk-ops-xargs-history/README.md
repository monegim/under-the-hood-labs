# Lab 23 — Bulk Cleanup with xargs and Shell History Tricks

## Objective
Clean up a stale cache directory with 60,000+ files and a handful of
runaway background processes — fast, safely, and without retyping long
commands — using `find | xargs` and shell history expansion (`!!`,
`!$`, `!*`).

## Why this matters
`rm *` stops working once you have "enough" files — not because
anything is broken, but because the shell expands the glob into one
enormous command line and hits a hard kernel limit on argument size.
`find | xargs` is the standard fix, and it scales to millions of files
because it batches automatically. Shell history expansion isn't just a
party trick either: `sudo !!` after a permission-denied is faster and
less error-prone than retyping a long command with `sudo` stuck on the
front, and during an actual incident, typing speed and typo risk both
matter.

## Prerequisites
- A Linux VM, `sudo` access
- `python3` (used only by `setup.sh` to generate files quickly)
- An interactive bash shell for the history-expansion steps (`!!`/`!$`/
  `!*` don't work inside non-interactive scripts — that's expected,
  they're an interactive-shell feature)

Check first:
```bash
python3 --version
echo $BASH_VERSION
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates `/var/tmp/lab23-cache/` (60,000 `.tmp` files across 60
subdirectories, plus a root-owned `quarantine/` subdirectory you can't
even see without `sudo`), and starts 8 runaway "worker" processes under
`/var/tmp/lab23-workers/` — plus one unrelated real process,
`network-worker-monitor.sh`, that just happens to have "worker" in its
name too.

## Step 2 — See why `rm *` won't work here
```bash
find /var/tmp/lab23-cache -name '*.tmp' | wc -l
rm /var/tmp/lab23-cache/*/*.tmp
```
The `rm` fails with `Argument list too long` — the shell expanded that
glob into a single command line with 60,000 filenames on it, and the
kernel has a hard limit on how big that can be (`getconf ARG_MAX`).
This isn't an `rm` bug; it would happen with any command given that many
arguments at once.

## Step 3 — Clean up with find + xargs
```bash
find /var/tmp/lab23-cache -name '*.tmp' -print0 | xargs -0 rm
```
`find` streams matching paths one at a time instead of building one
giant argument list, and `xargs` automatically batches them into
multiple `rm` invocations sized to stay under the argument limit. The
`-print0` / `xargs -0` pairing null-delimits each path instead of
splitting on whitespace — matters the moment any filename has a space
in it (more on that in Challenge A).

## Step 4 — Handle the part that needs sudo
```bash
find /var/tmp/lab23-cache -name '*.tmp' -delete
```
This still leaves `quarantine/`'s files behind — check:
```bash
find /var/tmp/lab23-cache -name '*.tmp' 2>&1
```
You'll see a `Permission denied` on `quarantine/` itself (it's
`root`-owned, mode 700). Rather than retype the whole command with
`sudo` stuck on the front:
```bash
sudo !!
```
`!!` re-runs your previous command verbatim; `sudo !!` re-runs it with
`sudo` prepended. Since this is a single `find ... -delete` command (not
a pipeline), sudo-ing the whole thing this way works cleanly.

## Step 5 — Clean up the workers
```bash
pgrep -f "/var/tmp/lab23-workers/worker-"
```
Confirm that lists exactly the 8 runaway workers — nothing else — before
you act on it:
```bash
pgrep -f "/var/tmp/lab23-workers/worker-" | xargs kill
```

## Step 6 — `!$` and `!*` in practice
```bash
mkdir -p /var/tmp/lab23-cleanup-log
echo "cache cleaned, workers killed" > !$/summary.txt
```
`!$` expands to just the *last argument* of the previous command
(`/var/tmp/lab23-cleanup-log`), so you don't have to retype a path you
just typed one line above. `!*` is the same idea for *all* arguments —
useful when the previous command took several:
```bash
touch /var/tmp/a.txt /var/tmp/b.txt /var/tmp/c.txt
chmod 644 !*
```

## Step 7 — Verify
```bash
find /var/tmp/lab23-cache -name '*.tmp' | wc -l
pgrep -fl worker
```
Should show 0 leftover files, and only `network-worker-monitor.sh` still
in the process list — not any of the 8 workers.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a filename with a space breaks naive xargs:**
```bash
mkdir -p /var/tmp/lab23-cache/dir999
touch "/var/tmp/lab23-cache/dir999/file 1.tmp" "/var/tmp/lab23-cache/dir999/file 2.tmp" /var/tmp/lab23-cache/dir999/file3.tmp
find /var/tmp/lab23-cache/dir999 -name '*.tmp' | xargs rm
```
(Note: no `-print0` / `-0` this time.) Check whether this actually
finished the job:
```bash
find /var/tmp/lab23-cache/dir999 -name '*.tmp'
ls -la /var/tmp/lab23-cache/dir999/
```
Something's still there, and `rm` almost certainly printed an error
about a file that doesn't exist. Figure out exactly what `xargs` did
with the filenames that contain spaces, and fix it properly (not by
renaming files to avoid spaces — that's not always an option on a real
system).

**Challenge B — a loose pattern kills more than intended:**
```bash
bash /var/tmp/lab23-important/network-worker-monitor.sh &
disown
bash /var/tmp/lab23-workers/worker-1.sh &
disown
```
(This restarts one worker and the important process fresh, since your
earlier cleanup already killed them.) Someone on the team says they
"cleaned up the leftover workers" by running:
```bash
pgrep -f worker | xargs kill
```
Check what's actually still running now (`pgrep -fl worker`), compare it
to what *should* still be running, and explain exactly why this pattern
was dangerous — then bring back whatever it shouldn't have killed, and
redo the cleanup with a pattern that can't make the same mistake.

See `solution.md` only after you've formed your own diagnosis.
