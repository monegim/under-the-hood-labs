# Lab 22 — Solutions

## Challenge A — still not enough headroom

**Check:**
```bash
systemctl show mysql.service -p MemoryMax -p Slice
sudo dmesg -T | tail -20 | grep -i oom
ps -o rss,cmd -C mysqld
```
`RSS` for mysqld sits well above 512M once you account for connection
buffers, thread stacks, and the InnoDB log buffer on top of the 512M pool —
and the slice cap is still 1200M shared with the hog.

**Diagnosis:** you did the arithmetic on the buffer pool alone and ignored
mysqld's other memory consumers (per-connection buffers, temp tables,
thread stacks) — a rule of thumb is real memory use is buffer pool size
plus 15-25% overhead, not buffer pool size on the nose. 512M pool + 700M
hog is already close to 1200M before overhead is even counted.

**Fix:** leave real margin, don't just barely fit:
```bash
sudo sed -i 's/innodb_buffer_pool_size=512M/innodb_buffer_pool_size=400M/' /etc/mysql/mysql.conf.d/zzz-lab22.cnf
sudo systemctl restart mysql
```

**Lesson:** sizing `innodb_buffer_pool_size` against total RAM (or a slice
limit) without leaving headroom for connection overhead, temp tables, and
whatever else runs on the box is the single most common cause of MySQL OOM
kills in production — leave 20-30% slack, don't size to the exact ceiling.

---

## Challenge B — the restart loop

**Check:**
```bash
systemctl status mysql --no-pager
sudo journalctl -k --since "5 min ago" | grep -c -i "killed process"
sudo journalctl -u mysql --since "5 min ago" | grep -i -E "start|stop"
```
`systemctl status` shows mysql as "active (running)" but with a very
recent start time and a nonzero restart count. `journalctl -k` shows
*multiple* "Killed process ... (mysqld)" lines, not one.

**Diagnosis:** the OOM kill isn't a one-time event — systemd's
`Restart=on-failure` on the mysql unit brings it right back up, it
re-allocates the same oversized buffer pool, gets OOM-killed again, and
repeats. From the outside this looks like "MySQL keeps randomly restarting"
or intermittent connection failures, not an obvious OOM problem, unless you
specifically count kill events over a time window instead of looking at
just the current status.

**Fix:** the loop won't stop until the actual memory math is fixed (see
Challenge A) — restarting or waiting doesn't help:
```bash
sudo sed -i 's/innodb_buffer_pool_size=[0-9]*M/innodb_buffer_pool_size=256M/' /etc/mysql/mysql.conf.d/zzz-lab22.cnf
sudo systemctl restart mysql
sudo systemctl stop oom-lab-hog3 2>/dev/null || true
```

**Lesson:** a service that's "up" right now can still be mid-crash-loop —
always check restart counts and historical log volume
(`journalctl -u <unit> --since ...`), not just current process status,
before declaring an incident resolved.
