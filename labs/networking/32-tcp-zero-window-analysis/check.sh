#!/usr/bin/env bash
set -uo pipefail

# Lab 32 check - runs a fresh capture-and-transfer cycle and requires
# zero real TCP zero-window events, i.e. the receiver is actually
# draining data fast enough now, not just "the client didn't error."

if ! sudo ip netns exec server pgrep -f lab32-server.py >/dev/null 2>&1; then
  echo "[FAIL] no server process on 'server' - run setup.sh first"
  exit 1
fi

PCAP=$(mktemp /tmp/lab32-check-XXXX.pcap)
sudo ip netns exec client tcpdump -i veth-c -w "$PCAP" -n >/dev/null 2>&1 &
TCPDUMP_PID=$!
sleep 1

sudo ip netns exec client python3 /tmp/lab32-client.py

sleep 1
sudo kill "$TCPDUMP_PID" 2>/dev/null
wait "$TCPDUMP_PID" 2>/dev/null

ZW=$(tshark -r "$PCAP" -Y 'tcp.analysis.zero_window' 2>/dev/null | wc -l | tr -d ' ')
echo "[check] zero-window events observed: $ZW"
rm -f "$PCAP"

if [ "$ZW" -eq 0 ]; then
  echo "[PASS] no zero-window stalls - the receiver is keeping up."
  exit 0
else
  echo "[FAIL] $ZW zero-window event(s) observed - the receiver is still stalling the sender."
  exit 1
fi
