# Lab 18 — strace/ltrace Deep Dive

## Objective
Diagnose a service that fails silently because of a bad working-directory
assumption, using `strace` to read syscalls and errnos instead of guessing.
Then contrast that with `ltrace` for a library-call-level bug, and with a
live `strace -p` attach on a process that isn't failing at all - it's just
hung forever in `read()`.

## Why this matters
`top` and `ps` tell you a process is running (or not) and how much CPU/RSS
it's using. They tell you nothing about *what it's doing right now* or
*why a syscall failed*. The single most common on-call mistake with a
misbehaving process is staring at `ps aux` and guessing, when the actual
answer is sitting one `strace` invocation away: the exact syscall, its
arguments, and its errno. `ltrace` is the same idea one layer up, at the
level of library calls (`getenv`, `fopen`, `strcmp`) instead of kernel
syscalls - useful when the bug is in how a program used a library
function, not in a syscall itself.

## Prerequisites
- Ubuntu VM, sudo access, systemd
- `strace`, `ltrace`, `gcc` (installed by `setup.sh`)

Check first:
```bash
uname -a
which strace ltrace gcc
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This installs `configapp.service`, a Python app that reads `config.ini`
with a plain relative-path `open()` - it assumes it's running from
`/opt/configapp`. The unit file has no `WorkingDirectory=`, so systemd
runs it with the default working directory (`/`) instead.

## Step 2 — Confirm the failure
```bash
systemctl status configapp --no-pager
```
Should show `failed`, or cycling through `activating (auto-restart)` /
`failed` every few seconds (`RestartSec=3`).

## Step 3 — Read the log (and notice it's not enough)
```bash
journalctl -u configapp --no-pager | tail -10
```
You'll see `configapp: FATAL - could not read config file` - no path, no
errno, nothing to actually act on. This is deliberately realistic: a lot
of real application logging is this vague. `ps`/`systemctl status`/the
app's own log have all told you *that* it's broken, not *why*.

## Step 4 — Reproduce it under strace
A unit that restart-loops every few seconds is hard to catch live with
`strace -p`. The more reliable move: reconstruct the exact command systemd
runs and invoke it yourself, under strace, from the same working directory
systemd would use:
```bash
systemctl cat configapp
```
Notice there's no `WorkingDirectory=` line at all - per `systemd.exec(5)`,
that means it defaults to `/`. Reproduce it exactly:
```bash
cd /
sudo strace -f -e trace=openat -o /tmp/configapp.strace /usr/bin/python3 /opt/configapp/app.py
```
(Ctrl+C it after a couple seconds - it'll print the FATAL line and keep
running past the exception in this manual invocation, which is fine, you
already have what you need.)

## Step 5 — Read the trace
```bash
grep config.ini /tmp/configapp.strace
```
```
openat(AT_FDCWD, "config.ini", O_RDONLY) = -1 ENOENT (No such file or directory)
```
> Gotcha: `AT_FDCWD` means "resolve this relative path against the
> process's current working directory." Since we `cd /` first (matching
> systemd's default), that open is really an attempt at `/config.ini`,
> not `/opt/configapp/config.ini`. This is the entire bug in one line -
> no log message told you this, but the syscall couldn't lie about which
> path it actually tried.

## Step 6 — Fix it
```bash
sudo mkdir -p /etc/systemd/system/configapp.service.d
sudo tee /etc/systemd/system/configapp.service.d/override.conf > /dev/null <<'EOF'
[Service]
WorkingDirectory=/opt/configapp
EOF
sudo systemctl daemon-reload
sudo systemctl restart configapp
systemctl status configapp --no-pager
journalctl -u configapp --no-pager | tail -5
```
You should now see `configapp: config loaded ok: port=8080`.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — same bug shape, but `ltrace` instead (missing environment
variable, not missing cwd):**
```bash
sudo tee /etc/configapp/allowed_tokens.txt > /dev/null <<'EOF'
prod-secret-99213
EOF
sudo tee /etc/configapp/authcheck.env > /dev/null <<'EOF'
CONFIGAPP_TOKEN=prod-secret-99213
EOF
sudo tee /opt/configapp/authcheck.c > /dev/null <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    char *token = getenv("CONFIGAPP_TOKEN");
    if (token == NULL) { printf("authcheck: no token in env, using default\n"); token = "default-insecure-token"; }
    FILE *f = fopen("/etc/configapp/allowed_tokens.txt", "r");
    if (!f) { printf("authcheck: FATAL - could not open allow-list\n"); return 1; }
    char line[128]; int ok = 0;
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        if (strcmp(line, token) == 0) { ok = 1; break; }
    }
    fclose(f);
    if (ok) { printf("authcheck: token accepted\n"); return 0; }
    printf("authcheck: token REJECTED\n"); return 2;
}
EOF
sudo gcc -O0 -o /opt/configapp/authcheck /opt/configapp/authcheck.c
sudo tee /etc/systemd/system/configapp-authcheck.service > /dev/null <<'EOF'
[Unit]
Description=Lab 18 authcheck (deliberately missing EnvironmentFile)
[Service]
Type=oneshot
ExecStart=/opt/configapp/authcheck
EOF
sudo systemctl daemon-reload
sudo systemctl start configapp-authcheck.service
journalctl -u configapp-authcheck.service --no-pager | tail -5
```
It fails with "token REJECTED". But when you (the admin who wrote
`authcheck.env`) run the exact same binary yourself:
```bash
set -a; source /etc/configapp/authcheck.env; set +a
/opt/configapp/authcheck
```
it works fine - "accepted." Same binary, same file, different outcome.
Use `ltrace` (not `strace`) to see why - this is a library call
(`getenv`), not a syscall:
```bash
ltrace -e getenv+fopen+strcmp /opt/configapp/authcheck
```
Run it once with the env var unset (systemd's actual conditions) and once
with it sourced (your conditions), and compare the `getenv(...)` return
value in each. Diagnose what's different about how systemd starts a
service versus how your interactive shell runs a command, and fix
`configapp-authcheck.service` so it gets the same environment your shell
has.

**Challenge B — looks perfectly healthy, but it's hung forever in
`read()`:**
```bash
sudo mkdir -p /run/configapp
sudo rm -f /run/configapp/eventpipe
sudo mkfifo /run/configapp/eventpipe
sudo chmod 666 /run/configapp/eventpipe
sudo tee /opt/configapp/producer.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
exec 3>/run/configapp/eventpipe
echo "producer: connected, waiting on upstream (this never actually happens)"
sleep infinity
EOF
sudo chmod +x /opt/configapp/producer.sh
sudo tee /opt/configapp/consumer.py > /dev/null <<'EOF'
#!/usr/bin/env python3
print("consumer: waiting for events...", flush=True)
with open("/run/configapp/eventpipe", "r") as f:
    while True:
        line = f.readline()
        if not line:
            print("consumer: pipe closed, exiting", flush=True)
            break
        print("consumer: got event:", line.strip(), flush=True)
EOF
sudo tee /etc/systemd/system/configapp-producer.service > /dev/null <<'EOF'
[Unit]
Description=Lab 18 event producer (deliberately stalls, never writes)
[Service]
Type=simple
ExecStart=/opt/configapp/producer.sh
EOF
sudo tee /etc/systemd/system/configapp-consumer.service > /dev/null <<'EOF'
[Unit]
Description=Lab 18 event consumer
After=configapp-producer.service
[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/configapp/consumer.py
EOF
sudo systemctl daemon-reload
sudo systemctl start configapp-producer.service
sleep 1
sudo systemctl start configapp-consumer.service
```
Check it the "normal" way first:
```bash
systemctl status configapp-consumer --no-pager
ps -o pid,ppid,stat,cmd -C python3
```
It looks completely fine - `active (running)`, state `S`, nothing in
`ps`/`systemctl status` suggests anything is wrong. Now use `strace` to
find out what it's actually doing:
```bash
PID=$(systemctl show -p MainPID --value configapp-consumer)
sudo strace -p "$PID"
```
Let it sit for a few seconds, then Ctrl+C. Also check the producer:
```bash
PPID=$(systemctl show -p MainPID --value configapp-producer)
sudo strace -p "$PPID"
```
Diagnose which syscall the consumer is stuck in, which fd it's on
(`ls -l /proc/$PID/fd`), and what the producer's own trace tells you about
why nothing is coming through. Then fix the producer so it actually
writes, and confirm the consumer's `read()` finally returns.

See `solution.md` only after you've formed your own diagnosis.
