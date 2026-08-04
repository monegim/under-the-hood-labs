# Lab 18 — Solutions

## Challenge A — ltrace, missing environment variable

**Check:**
```bash
journalctl -u configapp-authcheck.service --no-pager | tail -5
ltrace -e getenv+fopen+strcmp /opt/configapp/authcheck
set -a; source /etc/configapp/authcheck.env; set +a
ltrace -e getenv+fopen+strcmp /opt/configapp/authcheck
```
Without the env var: `getenv("CONFIGAPP_TOKEN") = NULL`, then a `strcmp`
against the fallback `"default-insecure-token"` that never matches the
allow-list, so it's rejected. With the env var sourced into your own
shell: `getenv("CONFIGAPP_TOKEN") = "prod-secret-99213"`, and one
`strcmp(...) = 0` - a match, accepted.

**Diagnosis:** `configapp-authcheck.service` has no `EnvironmentFile=`, so
systemd execs the binary with systemd's own minimal environment - it never
saw `CONFIGAPP_TOKEN` at all. Your interactive shell has it because you
(or whoever wrote `authcheck.env`) sourced it by hand. Same binary, same
allow-list file, completely different environment at the point of
`getenv()` - which is exactly the kind of thing `ltrace` shows and `strace`
wouldn't (there's no failed syscall here; `getenv()` isn't a syscall at
all, it's a libc function reading the process's already-inherited
`environ`).

**Fix:**
```bash
sudo tee /etc/systemd/system/configapp-authcheck.service.d/override.conf > /dev/null <<'EOF'
[Service]
EnvironmentFile=/etc/configapp/authcheck.env
EOF
sudo systemctl daemon-reload
sudo systemctl start configapp-authcheck.service
journalctl -u configapp-authcheck.service --no-pager | tail -5
```
(Create the `.d` directory first if it doesn't exist:
`sudo mkdir -p /etc/systemd/system/configapp-authcheck.service.d`.)

**Lesson:** "it works when I run it myself" is the single most common tell
of an environment-inheritance bug. Your shell's environment (exported
variables, `.bashrc`/`.profile` side effects) is NOT what a systemd
service, cron job, or any other non-interactive invocation sees. When the
bug is "a library call returned something unexpected given the
environment," reach for `ltrace`, not `strace` - `getenv()`/`fopen()`/
`strcmp()` are libc calls, not syscalls, so `strace` won't show them by
name (it would show the underlying `read()`s `fopen()` makes, but not the
`getenv()` call at all, since reading `environ` doesn't touch the kernel).

---

## Challenge B — hung in read() on an unwritten FIFO

**Check:**
```bash
systemctl status configapp-consumer --no-pager
PID=$(systemctl show -p MainPID --value configapp-consumer)
sudo strace -p "$PID"
```
`systemctl status` says `active (running)` - completely normal-looking.
`strace -p` shows it sitting in:
```
read(3, ...
```
with no return - it's been blocked here since it started. Cross-check the
fd:
```bash
ls -l /proc/$PID/fd/3
```
shows it's the FIFO. Then the producer:
```bash
PPID=$(systemctl show -p MainPID --value configapp-producer)
sudo strace -p "$PPID"
```
shows it sitting in `nanosleep`/`clock_nanosleep` (the `sleep infinity`) -
alive, connected (it already opened its write end, which is why the
consumer's own `open()` succeeded in the first place), but never calling
`write()` at all.

**Diagnosis:** Opening a FIFO for reading blocks until a writer opens it
too - that part already succeeded here, which is exactly why
`systemctl status`/`ps` show a normal, running process instead of a
stuck-in-open one. The actual bug is one level deeper: the writer
connected and then never wrote anything, so the reader's `read()` has
nothing to return and no EOF to see either (EOF only happens when every
writer fd closes, and the producer is holding fd 3 open forever via
`sleep infinity`). Nothing here is "failed" in any sense `ps`/`systemctl`
can see - the process is alive, in an entirely normal `S` (interruptible
sleep) state, correctly doing exactly what its code says: waiting.

**Fix:**
```bash
sudo tee /opt/configapp/producer.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
exec 3>/run/configapp/eventpipe
while true; do
    echo "heartbeat $(date +%s)" >&3
    sleep 5
done
EOF
sudo systemctl restart configapp-producer.service
journalctl -u configapp-consumer --no-pager | tail -5
```
The consumer's `read()` immediately starts returning lines.

**Lesson:** a process can be textbook "healthy" by every signal `ps`/`top`/
`systemctl status` give you - running, correct state, no restarts, no
crash - and still be doing nothing useful, indefinitely, because it's
blocked on I/O that will never arrive. `strace -p` on a live PID is the
only one of these tools that shows you the actual syscall it's parked in
right now, which is what turns "looks fine" into "has been blocked in
`read()` on fd 3 since it started."
