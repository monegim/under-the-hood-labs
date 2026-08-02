#!/usr/bin/env bash
# Lab 11 (MTU Issues) — verifies the GRE tunnel's MTU is correct for the
# underlay, that nothing is blocking ICMP "fragmentation needed" (which
# would blackhole PMTUD), and that PMTUD is actually working: a
# 1448-byte DF ping succeeds, and a 1449-byte DF ping is correctly
# rejected with a "Frag needed" message rather than silently timing out.
set -uo pipefail

LAB="mtu-lab"
HOSTA="clab-${LAB}-hostA"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
HOSTB="clab-${LAB}-hostB"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$HOSTA" "$R1" "$R2" "$HOSTB"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying gre1 MTU is 1476 on both r1 and r2 (not stale)..."
docker exec "$R1" ip link show gre1 2>/dev/null | grep -q "mtu 1476" || fail "r1's gre1 MTU is not 1476 (see Challenge B)"
docker exec "$R2" ip link show gre1 2>/dev/null | grep -q "mtu 1476" || fail "r2's gre1 MTU is not 1476 (see Challenge B)"

echo "[check] verifying underlay MTU is 1500 on both sides (not shrunk)..."
docker exec "$R1" ip link show eth2 2>/dev/null | grep -q "mtu 1500" || fail "r1's eth2 (underlay) MTU is not 1500"
docker exec "$R2" ip link show eth1 2>/dev/null | grep -q "mtu 1500" || fail "r2's eth1 (underlay) MTU is not 1500"

echo "[check] verifying no iptables rule is blackholing ICMP fragmentation-needed on r1..."
if docker exec "$R1" iptables -C OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP 2>/dev/null; then
  fail "r1 has an OUTPUT DROP rule for ICMP fragmentation-needed — PMTUD is blackholed (see Challenge A)"
fi

echo "[check] verifying a 1448-byte DF ping succeeds (fits the tunnel MTU)..."
docker exec "$HOSTA" ping -M do -s 1448 -c 2 -W 2 10.2.2.10 >/dev/null 2>&1 || fail "1448-byte DF ping hostA -> hostB failed"

echo "[check] verifying a 1449-byte DF ping is correctly rejected with 'Frag needed' (PMTUD working, not a silent blackhole)..."
OUT=$(docker exec "$HOSTA" ping -M do -s 1449 -c 2 -W 2 10.2.2.10 2>&1 || true)
echo "$OUT" | grep -qi "frag needed" || fail "1449-byte DF ping did not report 'Frag needed' — PMTUD appears blackholed:
$OUT"

echo "[PASS] tunnel MTU is correct, ICMP fragmentation-needed is not blocked, and PMTUD is working"
exit 0
