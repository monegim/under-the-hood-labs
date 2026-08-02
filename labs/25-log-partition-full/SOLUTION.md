# Lab 25 — Solutions

## Challenge A — more than one writer

**Check:**
```bash
df -h /var/log/myapp
sudo lsof +D /var/log/myapp
```
`lsof +D` lists every open file handle under that mount — this time it
shows both `flaky-app.sh` and `flaky-app-2.sh` with different log files
open (`error.log` and `error2.log`).

**Diagnosis:** killing the process you already know about only stops half
the flood. `du -sh /var/log/myapp/*` would have shown two large files
instead of one, and a partial fix (kill one, declare victory) would leave
the partition filling right back up from the second writer.

**Fix:**
```bash
sudo pkill -f flaky-app
sudo truncate -s 0 /var/log/myapp/error.log /var/log/myapp/error2.log
df -h /var/log/myapp
```

**Lesson:** always enumerate every open file handle on a full filesystem
(`lsof +D <mount>`) before declaring the incident over — a single `pkill`
based on what you already suspect can miss a second, unrelated writer on
the same partition.

---

## Challenge B — journald fills up instead

**Check:**
```bash
journalctl --disk-usage
du -sh /var/log/journal/*
systemctl status crashloop-demo
```
`journalctl --disk-usage` reports the total size of the persistent journal,
growing quickly. `/var/log/journal/<machine-id>/` shows the actual
`.journal` files on disk.

**Diagnosis:** this service never touches a log file directly — everything
it prints to stdout/stderr is captured by `journald` and written to its own
binary journal store under `/var/log/journal/`. Without a configured cap,
journald will keep accepting data (bounded only by its own defaults, which
reserve a large fraction of the filesystem it lives on) — a crash-looping
service with `Restart=always` and no `RestartSec` backoff can generate an
enormous amount of journal data very quickly, the same shape of incident as
Challenge A but with a completely different place to look for the growth
(`du -sh /var/log` alone would NOT have shown this — it lives under
`/var/log/journal`, a directory `du -sh /var/log/*` does actually include,
but many people forget journald even writes there).

**Fix:** stop the loop, cap journald's footprint going forward, and reclaim
space now:
```bash
sudo systemctl stop crashloop-demo
sudo systemctl disable crashloop-demo

echo 'SystemMaxUse=200M' | sudo tee -a /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

sudo journalctl --vacuum-size=200M
journalctl --disk-usage
```

**Lesson:** `journald` is a log destination too, and it fills disk exactly
like a flat file would — `journalctl --disk-usage` and `SystemMaxUse=` in
`/etc/systemd/journald.conf` (plus `journalctl --vacuum-size=`/`--vacuum-time=`
for immediate cleanup) are the `du`/`logrotate` equivalents for anything
that logs via stdout under systemd, which today is most services.
