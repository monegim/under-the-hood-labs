#!/usr/bin/env bash
# Lab 20 setup — builds a CPU-hog "before" state.
#
# Mechanism: disguises a CPU-burning loop as a boring-sounding background
# job (/usr/local/bin/report-generator.sh), the way a real "someone's cron
# job is eating the box" incident looks in top. Uses `yes > /dev/null`,
# which is a single tight write-loop and reliably pins one core to 100%
# on any Linux VM — no special packages, no stress-ng dependency.
set -euo pipefail

echo "[1/3] Installing the 'report generator' (a disguised CPU hog)..."
sudo tee /usr/local/bin/report-generator.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
# Pretends to be a reporting job. Actually just burns CPU forever.
exec yes > /dev/null
EOF
sudo chmod +x /usr/local/bin/report-generator.sh

echo "[2/3] Starting it in the background (nohup, detached from this shell)..."
nohup /usr/local/bin/report-generator.sh > /tmp/report-generator.log 2>&1 &
disown
echo "      started with PID $!"

echo "[3/3] Done. The 'server' now feels slow system-wide."
echo
echo "Verify with:"
echo "  uptime"
echo "  top"
echo
echo "To clean up manually later: pkill -f report-generator.sh"
