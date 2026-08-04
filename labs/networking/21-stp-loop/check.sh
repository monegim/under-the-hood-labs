#!/usr/bin/env bash
# Lab 21 (STP Loop) - verifies STP is enabled on both bridges, exactly one
# of the four inter-switch ports has been put into blocking (the redundant
# path), and h1 can still reach h2 across the loop-free tree.
set -uo pipefail

fail=0

echo "[check] sw1/sw2 bridges exist"
for br in sw1 sw2; do
  if ! ip link show "$br" >/dev/null 2>&1; then
    echo "[FAIL] $br does not exist - run setup.sh first"
    exit 1
  fi
done

echo "[check] STP enabled on both bridges"
for br in sw1 sw2; do
  stp=$(cat "/sys/class/net/$br/bridge/stp_state" 2>/dev/null || echo "?")
  if [ "$stp" = "1" ]; then
    echo "[PASS] $br has stp_state=1"
  else
    echo "[FAIL] $br has stp_state=$stp (expected 1) - enable STP (README Step 6)"
    fail=1
  fi
done

echo "[check] port states on the four inter-switch links"
forwarding=0
blocking=0
for port in sw1-a sw1-b sw2-a sw2-b; do
  if ! ip link show "$port" >/dev/null 2>&1; then
    echo "[FAIL] $port does not exist"
    fail=1
    continue
  fi
  state=$(bridge -d link show dev "$port" 2>/dev/null | grep -oE 'state (forwarding|blocking|listening|learning|disabled)' | awk '{print $2}')
  echo "  $port: ${state:-unknown}"
  case "$state" in
    forwarding) forwarding=$((forwarding+1)) ;;
    blocking) blocking=$((blocking+1)) ;;
  esac
done

if [ "$blocking" -eq 1 ] && [ "$forwarding" -eq 3 ]; then
  echo "[PASS] exactly one redundant port is blocking, the other three are forwarding"
else
  echo "[FAIL] expected 1 blocking / 3 forwarding across sw1-a,sw1-b,sw2-a,sw2-b (got $blocking blocking / $forwarding forwarding) - STP may still be converging, wait and retry"
  fail=1
fi

echo "[check] h1 -> h2 connectivity (10.0.0.1 -> 10.0.0.2)"
if sudo ip netns exec h1 ping -c 3 -W 2 10.0.0.2 >/dev/null 2>&1; then
  echo "[PASS] h1 can ping h2 across the loop-free tree"
else
  echo "[FAIL] h1 cannot ping h2"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 21 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 21 topology has issues (see above)"
  exit 1
fi
