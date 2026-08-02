#!/usr/bin/env bash
set -uo pipefail

# Lab 2 - VLANs: verify VLAN membership (ns1/ns2 on vid 10, ns3/ns4 on
# vid 20, veth5-br trunking both) and connectivity matches the README's
# same-VLAN / isolation / trunk tests.

fail=0

check_vid() {
  local port="$1" vid="$2" extra="$3"
  local out
  out=$(bridge vlan show dev "$port" 2>/dev/null)
  if echo "$out" | grep -q "$vid" && { [ -z "$extra" ] || echo "$out" | grep "$vid" | grep -q "$extra"; }; then
    echo "[PASS] $port carries vid $vid ${extra:+($extra)}"
  else
    echo "[FAIL] $port does not correctly carry vid $vid ${extra:+(expected $extra)}"
    echo "        actual: $(echo "$out" | tr '\n' ' ')"
    fail=1
  fi
}

echo "[check] br0 vlan_filtering enabled and UP"
if ip -d link show br0 2>/dev/null | grep -q "vlan_filtering 1" && ip link show br0 up >/dev/null 2>&1; then
  echo "[PASS] br0 is VLAN-filtering and UP"
else
  echo "[FAIL] br0 missing, down, or not vlan_filtering"
  fail=1
fi

echo "[check] access port VLAN membership"
check_vid veth1-br 10 "PVID"
check_vid veth2-br 10 "PVID"
check_vid veth3-br 20 "PVID"
check_vid veth4-br 20 "PVID"

echo "[check] trunk port carries both VLANs"
check_vid veth5-br 10 ""
check_vid veth5-br 20 ""

echo "[check] same-VLAN connectivity: ns1 -> ns2 (both VLAN 10)"
if sudo ip netns exec ns1 ping -c 2 -W 2 10.10.0.2 >/dev/null 2>&1; then
  echo "[PASS] ns1 reaches ns2"
else
  echo "[FAIL] ns1 cannot reach ns2"
  fail=1
fi

echo "[check] VLAN isolation: ns1 -> ns3 (VLAN 10 vs VLAN 20, must NOT reach)"
if sudo ip netns exec ns1 ping -c 2 -W 2 10.20.0.1 >/dev/null 2>&1; then
  echo "[FAIL] ns1 can reach ns3 - VLANs are not isolated"
  fail=1
else
  echo "[PASS] ns1 cannot reach ns3 (VLANs correctly isolated)"
fi

echo "[check] trunk connectivity: router -> ns1 (VLAN 10) and router -> ns3 (VLAN 20)"
if sudo ip netns exec router ping -c 2 -W 2 10.10.0.1 >/dev/null 2>&1; then
  echo "[PASS] router reaches ns1 over trunk VLAN 10"
else
  echo "[FAIL] router cannot reach ns1 over trunk VLAN 10"
  fail=1
fi
if sudo ip netns exec router ping -c 2 -W 2 10.20.0.1 >/dev/null 2>&1; then
  echo "[PASS] router reaches ns3 over trunk VLAN 20"
else
  echo "[FAIL] router cannot reach ns3 over trunk VLAN 20"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 2 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 2 topology has issues (see above)"
  exit 1
fi
