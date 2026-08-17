#!/usr/bin/env bash
set -euo pipefail

# Lab 32 setup: client <-veth-> server. server runs a receiver with a
# tiny receive buffer that reads slowly (RECV_DELAY between each small
# read) - client sends data much faster than server can drain it,
# causing real TCP zero-window events. Safe to re-run - tears down
# first.

for ns in client server; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

sudo ip netns add client
sudo ip netns add server

sudo ip link add veth-c type veth peer name veth-s
sudo ip link set veth-c netns client
sudo ip link set veth-s netns server

sudo ip netns exec client ip addr add 10.50.0.1/24 dev veth-c
sudo ip netns exec client ip link set veth-c up
sudo ip netns exec client ip link set lo up

sudo ip netns exec server ip addr add 10.50.0.2/24 dev veth-s
sudo ip netns exec server ip link set veth-s up
sudo ip netns exec server ip link set lo up

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat > /tmp/lab32-server.py <<'EOF'
import os, socket

RCVBUF = int(os.environ.get("RCVBUF", "2048"))
READ_SIZE = int(os.environ.get("READ_SIZE", "512"))
READ_DELAY = float(os.environ.get("READ_DELAY", "0.2"))

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
if RCVBUF > 0:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, RCVBUF)
s.bind(("0.0.0.0", 9100))
s.listen(1)
print(f"[server] listening, RCVBUF={RCVBUF} READ_SIZE={READ_SIZE} READ_DELAY={READ_DELAY}", flush=True)
while True:
    conn, _ = s.accept()
    total = 0
    while True:
        data = conn.recv(READ_SIZE)
        if not data:
            break
        total += len(data)
        if READ_DELAY > 0:
            import time
            time.sleep(READ_DELAY)
    print(f"[server] connection done, received {total} bytes", flush=True)
    conn.close()
EOF

cat > /tmp/lab32-client.py <<'EOF'
import socket

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(("10.50.0.2", 9100))
payload = b"X" * 8192
for _ in range(4):
    s.sendall(payload)
s.close()
print("[client] done")
EOF

echo "[setup] starting the slow receiver on server (RCVBUF=2048, READ_DELAY=0.2s - the broken state)..."
sudo ip netns exec server pkill -f lab32-server.py 2>/dev/null || true
sleep 1
sudo ip netns exec server env RCVBUF=2048 READ_SIZE=512 READ_DELAY=0.2 python3 /tmp/lab32-server.py \
    >/tmp/lab32-server.log 2>&1 &
disown 2>/dev/null || true
sleep 1

echo
echo "Done. Try a capture-while-transferring:"
echo "  sudo ip netns exec client tcpdump -i veth-c -w /tmp/lab32.pcap -n &"
echo "  sleep 1"
echo "  sudo ip netns exec client python3 /tmp/lab32-client.py"
echo "  sleep 1; sudo pkill tcpdump"
echo "  tshark -r /tmp/lab32.pcap -Y 'tcp.analysis.zero_window'"
