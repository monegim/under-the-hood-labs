#!/usr/bin/env bash
# Lab 27 setup — a container with a CFS CPU quota (0.5 CPU, via
# docker-compose's `cpus:`) that's too tight for a bursty workload.
# Averaged over any reasonable window, CPU usage looks moderate and
# unremarkable — the actual damage only shows up in the cgroup's own
# throttling counters, invisible to top/docker stats.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up app (cpus=0.5)..."
docker compose up -d

echo "[setup] waiting for the container to be ready..."
for i in $(seq 1 30); do
  docker exec lab27-app true >/dev/null 2>&1 && break
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[setup] ERROR: lab27-app never became ready" >&2
    exit 1
  fi
done

echo "[setup] installing stress-ng (used to generate a controlled CPU burst)..."
docker exec lab27-app sh -c "apt-get update -qq && apt-get install -y -qq stress-ng >/dev/null 2>&1"

echo "[setup] current CPU quota:"
docker exec lab27-app cat /sys/fs/cgroup/cpu.max

echo "[setup] baseline throttle stats:"
docker exec lab27-app grep -E "nr_throttled|throttled_usec" /sys/fs/cgroup/cpu.stat

echo
echo "Done. Time a fixed unit of 'work' (2 CPU-bound threads doing a fixed amount of computation):"
echo "  docker exec lab27-app bash -c \"time stress-ng --cpu 2 --cpu-method fibonacci --cpu-ops 4000000 --metrics-brief\""
echo "Then check the throttle stats again:"
echo "  docker exec lab27-app grep -E 'nr_throttled|throttled_usec' /sys/fs/cgroup/cpu.stat"
