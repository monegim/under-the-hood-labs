# Lab 24 — Surviving a Dropped Connection with tmux

## Objective
Run a ~15-second "remediation job" two ways — plain background job vs.
inside a detached tmux session — and see, directly, why only one of
them survives a dropped connection.

## Why this matters
The scenario that makes this matter isn't hypothetical: you're mid-incident,
you kick off something that takes a few minutes (a migration, a repair
script, a big `rsync`), and your SSH connection drops — VPN blip, laptop
sleeps, wifi hiccup. If that job was running in the plain foreground or
background of that SSH session, it dies with the connection, and you find
out when you reconnect and it's not there. tmux (and `screen` before it)
exists specifically to decouple a running process's lifetime from your
terminal's lifetime — the process's real parent becomes a persistent
background server, not your shell.

## Prerequisites
- A Linux VM, `sudo` access (only needed if `tmux` isn't already installed)

Check first:
```bash
tmux -V || echo "not installed yet — setup.sh will install it"
```

## Step 1 — Build the job
```bash
chmod +x setup.sh
./setup.sh
```
This writes `/var/tmp/lab24/job.sh` — a script that logs its progress
once a second for 15 seconds, then writes `/var/tmp/lab24/DONE` only if
it's still alive at the end.

## Step 2 — Watch it die without tmux
```bash
rm -f /var/tmp/lab24/DONE
bash -c '/var/tmp/lab24/job.sh' &
JOB_PID=$!
echo "job pid: $JOB_PID"
sleep 3
kill -HUP "$JOB_PID"   # simulating the SIGHUP a hung-up terminal delivers
sleep 15
cat /var/tmp/lab24/DONE 2>/dev/null || echo "no DONE marker — the job died"
```
> The `kill -HUP` here stands in for what actually happens at the kernel
> level when a real terminal disconnects: the process attached to that
> terminal gets sent `SIGHUP`. `job.sh` has no handler for it, so the
> default disposition applies — the process terminates, mid-job, with no
> warning and no cleanup.

## Step 3 — Run the same job inside tmux instead
```bash
rm -f /var/tmp/lab24/DONE
tmux new-session -d -s labjob '/var/tmp/lab24/job.sh'
tmux ls
sleep 18
cat /var/tmp/lab24/DONE
```
This time there's no `kill -HUP` step at all — and that omission is the
whole point, not an oversight. The job's actual parent process, from the
instant it started, is the `tmux` server (`pgrep tmux` will show it) —
not your shell, not your terminal, not your SSH connection. There is no
path for your connection dying to reach this job, because your
connection was never in its process tree to begin with. Detaching from a
tmux session (`Ctrl-b d`, or your connection dying while attached) has
nothing to hang up onto that would affect the job — you're just walking
away from and back to a server that was going to keep running regardless.

## Step 4 — Reattach and confirm
```bash
tmux new-session -d -s labjob2 '/var/tmp/lab24/job.sh; sleep 60'
sleep 3
tmux attach -t labjob2
```
(The `sleep 60` keeps the session alive after the job finishes so you
have time to actually attach and look around — `Ctrl-b d` to detach again
when you're done, or `exit`/`Ctrl-d` to end the session.) Notice `tmux
ls` from another terminal (or after detaching) still shows `labjob2` —
reattaching gets you back to exactly where the job left off, output and
all, because nothing about the session's terminal state was ever tied to
a connection that could drop.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — is tmux really required, or would `nohup` have worked?**
```bash
rm -f /var/tmp/lab24/DONE
nohup /var/tmp/lab24/job.sh > /var/tmp/lab24/nohup.log 2>&1 &
JOB_PID=$!
sleep 3
kill -HUP "$JOB_PID"
sleep 15
cat /var/tmp/lab24/DONE 2>/dev/null || echo "no DONE marker"
```
Run this and compare the result to Step 2. `nohup` means exactly what it
says — "no hangup" — and it shows here. So if `nohup &` also survives a
`SIGHUP`, what does tmux actually give you that `nohup` doesn't? (Hint:
try interacting with the job while it's running under each approach —
not just watching whether it survives, but whether you can *see* it or
send it input while it's in progress.)

**Challenge B — tmux can't retroactively protect a job that's already running:**
```bash
rm -f /var/tmp/lab24/DONE
bash /var/tmp/lab24/job.sh &
JOB_PID=$!
sleep 2
echo "oh no, I should have started this in tmux — let me fix that"
tmux new-session -d -s toolate
sleep 1
kill -HUP "$JOB_PID"
sleep 15
cat /var/tmp/lab24/DONE 2>/dev/null || echo "no DONE marker"
```
The job was already running before `tmux new-session` was ever typed.
Explain exactly why creating a tmux session afterward does nothing to
protect a process that's already someone else's child — and what you'd
actually have needed to do differently the moment you realized the job
should be protected.

See `solution.md` only after you've formed your own diagnosis.
