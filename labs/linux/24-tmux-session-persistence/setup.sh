#!/usr/bin/env bash
# Lab 24 setup — installs tmux if missing and writes the "remediation
# job" both demo paths will run: a script that takes ~15 seconds,
# logs its progress, and writes a DONE marker with a timestamp only if
# it runs to completion uninterrupted.
set -euo pipefail

LABDIR=/var/tmp/lab24
mkdir -p "$LABDIR"
rm -f "$LABDIR/DONE" "$LABDIR"/*.log

echo "[setup] checking for tmux..."
if ! command -v tmux >/dev/null 2>&1; then
    echo "[setup] installing tmux..."
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
fi
tmux -V

cat > "$LABDIR/job.sh" <<'EOF'
#!/usr/bin/env bash
# Stand-in for a real remediation job: e.g. a long DB migration, a
# rsync, a "drain and repair" script. Takes ~15 seconds, logs progress,
# and only writes DONE if it's still alive at the very end.
for i in $(seq 1 15); do
    echo "[job] progress: $i/15"
    sleep 1
done
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) job completed" > /var/tmp/lab24/DONE
EOF
chmod +x "$LABDIR/job.sh"

echo "[setup] done. Job script: $LABDIR/job.sh (~15s runtime, writes $LABDIR/DONE on success)"
