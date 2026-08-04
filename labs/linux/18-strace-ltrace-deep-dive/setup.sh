#!/usr/bin/env bash
# Lab 18 setup — builds the main incident: configapp.service fails
# silently because it assumes a working directory systemd never actually
# gives it. This is the "diagnose it with strace" half of the lab.
#
# The Challenges (ltrace on a missing-env-var bug, and strace -p on a
# process hung in read() on a FIFO) are built by commands you run
# yourself from the README, the same way Lab 11/12/17 layer their
# challenges on top of the main incident.
set -euo pipefail

echo "[1/4] Installing strace, ltrace, gcc (needed later, for the challenges)..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq strace ltrace gcc > /dev/null

echo "[2/4] Writing configapp's app and config file..."
sudo mkdir -p /opt/configapp
sudo tee /opt/configapp/app.py > /dev/null <<'EOF'
#!/usr/bin/env python3
import sys, time

print("configapp: starting up...", flush=True)
try:
    with open("config.ini") as f:
        data = f.read()
except OSError:
    # Deliberately vague, like a lot of real app logging - it does NOT
    # print the path or the cwd it tried, just that loading failed.
    print("configapp: FATAL - could not read config file", file=sys.stderr, flush=True)
    sys.exit(1)

print("configapp: config loaded ok:", data.strip(), flush=True)
print("configapp: running", flush=True)
time.sleep(3600)
EOF

sudo tee /opt/configapp/config.ini > /dev/null <<'EOF'
port=8080
EOF

echo "[3/4] Installing configapp.service WITHOUT WorkingDirectory= (the bug)..."
sudo tee /etc/systemd/system/configapp.service > /dev/null <<'EOF'
[Unit]
Description=Lab 18 configapp (deliberately missing WorkingDirectory)

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/configapp/app.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "[4/4] Reloading systemd and starting it (it will fail/restart-loop)..."
sudo systemctl daemon-reload
sudo systemctl enable --now configapp.service > /dev/null || true
sleep 1

echo
echo "Done. Check the damage:"
echo "  systemctl status configapp --no-pager"
echo "  journalctl -u configapp --no-pager | tail -10"
