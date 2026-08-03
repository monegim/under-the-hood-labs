# Lab 8 — Solutions

## Challenge A — identifying the offending source

**Check:**
```bash
mysql -uroot -prootpass -e "
  SELECT host, COUNT(*) FROM information_schema.processlist GROUP BY host ORDER BY 2 DESC LIMIT 5;
"
```
In this lab, every `appuser` connection shows the same `host` (this VM's
loopback/hostname), because everything runs on one machine — so this
exact query mostly demonstrates the technique rather than revealing a
surprise.

**Diagnosis:** in production, this is exactly the query (or its
`SHOW PROCESSLIST` equivalent, or `SELECT host, COUNT(*) FROM
performance_schema.threads GROUP BY ...` for more detail) that
distinguishes "the whole fleet is under legitimately heavy load" from
"one specific app server, container, or deploy has gone rogue" — the
`host` column groups by client IP:port pairs, and a genuine traffic spike
tends to spread roughly evenly across your app tier's real host count,
while a single misbehaving pool instance shows up as a wildly
disproportionate count from one specific address.

**Fix:** once you've identified a specific offending host (not possible
to demonstrate distinctly in this single-VM lab, but the query is the
same either way), the fastest safe mitigation in production is usually to
pull that one host out of rotation at the load balancer/orchestrator
level — stopping it from opening *new* connections — rather than
globally bumping `max_connections` or killing connections fleet-wide,
which affects healthy hosts too.

**Lesson:** "which user/command is consuming connections" (Step 3) tells
you *what* is wrong; "which specific host" tells you *where* to act
first without punishing hosts that are behaving correctly. Both queries
are worth having ready before an incident, not improvised during one.

---

## Challenge B — open_files_limit silently capping connections

**Check:**
```bash
sudo journalctl -u mysql --no-pager | grep -i -E "max_connections|open.files|open_files_limit" | tail -10
mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'open_files_limit';"
mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'max_connections';"
```
The error log shows a message along the lines of `Changed limits:
max_open_files: 200 (requested Y), table_open_cache: ... (requested Z)` —
mysqld silently recalculated its *effective* connection ceiling downward
at startup because the OS-level open file descriptor limit
(`open_files_limit=200`) couldn't support 500 connections plus
`table_open_cache` plus mysqld's own internal file handles.
`max_connections` itself still reports `500` as configured, but the real,
enforced ceiling is much lower.

**Diagnosis:** every open connection, plus every open table file (subject
to `table_open_cache`), plus assorted internal files (logs, sockets),
consumes one OS file descriptor. `max_connections` is a MySQL-level
configuration value; `open_files_limit` is the actual OS-level ceiling
mysqld's process is allowed to hold open at all. MySQL is aware of this
tension at startup and computes a safe effective limit from whichever
resource is more constrained — but it does this silently (a log message,
not an error, and not something `SHOW VARIABLES LIKE 'max_connections'`
reflects) — so an operator who only checks the MySQL-level configuration
value sees a generous `500` and has no reason to suspect the real ceiling
is much lower.

**Fix:**
```bash
sudo systemctl stop mysql
# raise open_files_limit alongside max_connections — via systemd override
sudo mkdir -p /etc/systemd/system/mysql.service.d
sudo tee /etc/systemd/system/mysql.service.d/override.conf > /dev/null <<'EOF'
[Service]
LimitNOFILE=10000
EOF
sudo systemctl daemon-reload
sudo systemctl start mysql
mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'open_files_limit';"
```
The OS-level `LimitNOFILE` on the systemd unit (not just MySQL's own
`open_files_limit` config value, which is itself bounded by whatever the
OS/systemd allows the process) needs enough headroom for the connection
count you actually intend to support.

**Lesson:** `max_connections` is necessary but not sufficient — it's a
MySQL-level intention, not a guarantee, and mysqld will quietly cap
itself lower if the OS-level file descriptor budget can't support the
configured value. Always check `open_files_limit` (and the OS/systemd
`LimitNOFILE` behind it) alongside `max_connections` when sizing a MySQL
instance for a target connection count, and check the error log at
startup for a "changed limits" message any time the two don't match your
expectations.
