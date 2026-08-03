# Incident 05 — The Restart That Doesn't Help

## The page

> Upload queue depth has been climbing for the last hour and hasn't
> recovered. On-call already restarted `upload-worker.service` twice -
> `systemctl restart` took a long time to even return, and the queue
> still isn't draining. Whatever this is, restarting it isn't fixing it.

That last line is the whole page. Not "it's slow" or "it's erroring" -
restarting the thing that's supposed to fix it hasn't fixed it, twice.

## Environment

A single VM running:
- `upload-worker.service` - a systemd-managed process that picks up
  files from a local "pending" directory and copies them onto a
  network-mounted upload directory (`/mnt/uploads`, backed by NFS).
- The NFS mount itself, exported and mounted on the same VM (a common
  way to build this reproducibly without needing a second host or real
  storage hardware).

You have `sudo` access and the usual process/mount tools: `systemctl`,
`ps`, `/proc`, `mount`, `iptables`.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`systemctl status`, `ps -eo stat,wchan,cmd`, `/proc/<pid>/status`,
`mount`, etc.). There's no prescribed sequence - explore the environment
the way you would a real page, starting from the symptom above.

## Getting unstuck

- A process that ignores `systemctl restart` (and even `kill -9`) isn't
  necessarily broken or hung in userspace at all - what's the difference
  between a process that's *running slowly* and one that's *blocked
  inside the kernel*?
- `ps`'s `STAT` column has more values than just "running" and "sleeping"
  - what does the specific letter shown here mean, and is it something a
  signal can interrupt?
- If the process is blocked on I/O, what does it depend on that has
  nothing to do with the process's own code, its systemd unit file, or
  how many times you restart it?

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
