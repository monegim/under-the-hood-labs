#!/usr/bin/env bash
# Lab 24 setup — builds a systemd ordering bug: a "webapp" service that
# depends on MySQL being ready, but is missing After=/Requires=.
#
# We can't reliably force the real boot-time race (on a fast VM, mysqld
# might win the race almost every time, making the lab flaky). Instead we
# deterministically reproduce the IDENTICAL failure symptom: stop mysql,
# then start webapp — this is exactly what happens on the boot where mysql
# loses the race, just forced instead of left to chance. The fix
# (After=+Requires=) is the same either way, and is verifiable with a real
# `sudo reboot` afterwards if you want to see it survive an actual boot.
set -euo pipefail

echo "[1/5] Installing mysql-server..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server > /dev/null

echo "[2/5] Writing the webapp's start script (just proves it can reach MySQL)..."
sudo tee /usr/local/bin/webapp.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
set -e
echo "webapp: checking MySQL connectivity..."
mysqladmin ping -h 127.0.0.1 --silent
echo "webapp: MySQL is up, starting..."
exec sleep infinity
EOF
sudo chmod +x /usr/local/bin/webapp.sh

echo "[3/5] Installing webapp.service WITHOUT After=/Requires= on mysql (the bug)..."
sudo tee /etc/systemd/system/webapp.service > /dev/null <<'EOF'
[Unit]
Description=Lab webapp (deliberately missing MySQL dependency)

[Service]
Type=simple
ExecStart=/usr/local/bin/webapp.sh
Restart=no

[Install]
WantedBy=multi-user.target
EOF

echo "[4/5] Reloading systemd and making sure mysql is running normally first..."
sudo systemctl daemon-reload
sudo systemctl enable --now mysql > /dev/null
sudo systemctl enable webapp > /dev/null

echo "[5/5] Forcing the losing side of the boot race: stop mysql, then start webapp..."
sudo systemctl stop mysql
sudo systemctl start webapp || true

echo
echo "Done. This is the same failure a real reboot would produce whenever"
echo "mysqld isn't ready before webapp starts."
echo
echo "Verify with:"
echo "  systemctl status webapp"
echo "  journalctl -u webapp --no-pager | tail -20"
