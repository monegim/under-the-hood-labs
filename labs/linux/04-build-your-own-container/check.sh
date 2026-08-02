#!/usr/bin/env bash
# Lab 4 — Build Your Own Container — check.sh
#
# This lab's "container" is a live process left running in a second
# terminal (README Step 3: "Leave this shell running; move to a second
# terminal for the next step"). This check finds THAT process by the same
# pgrep pattern the README itself uses in Step 4, and verifies each piece
# of isolation it's supposed to have:
#   - its own PID namespace (it is PID 1 inside its own namespace)
#   - its own mounted /proc (mounted at $ROOTFS/proc, not the host's /proc)
#   - its own UTS namespace (separate from the host's)
#   - its own mount namespace (separate from the host's)
#   - cgroup-limited (member of /sys/fs/cgroup/mycontainer, with
#     memory.max/cpu.max actually set — not just present but unset)
#
# If no container process is found, this fails and tells you to build it
# via README.md Steps 1-4 first — this check does not build one itself.
#
# Usage: sudo bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 4 — Build Your Own Container"
echo

ROOTFS="$HOME/mycontainer/rootfs"
CGROUP=/sys/fs/cgroup/mycontainer

# --- find the running container process (same pattern README Step 4 uses) ---
CONTAINER_PID=$(pgrep -f "chroot $ROOTFS" | head -n1)
if [ -z "${CONTAINER_PID:-}" ]; then
    bad "no running container process found (pgrep -f 'chroot $ROOTFS' matched nothing)"
    echo
    echo "Build it first: run README.md Steps 1-4 and leave the container shell"
    echo "running (Step 3) in one terminal before running this check from another."
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi
ok "found running container process, host PID $CONTAINER_PID"

# --- own PID namespace: container process is PID 1 inside it ---
if [ -r "/proc/$CONTAINER_PID/status" ] && grep -q '^NSpid:' "/proc/$CONTAINER_PID/status" 2>/dev/null; then
    INNER_PID=$(grep '^NSpid:' "/proc/$CONTAINER_PID/status" | awk '{print $NF}')
    if [ "$INNER_PID" = "1" ]; then
        ok "container process is PID 1 inside its own PID namespace"
    else
        bad "container process is not PID 1 inside its namespace (NSpid inner = $INNER_PID)"
    fi
else
    bad "could not read NSpid for PID $CONTAINER_PID (kernel too old, or process gone)"
fi

# --- own PID namespace differs from host's ---
HOST_PIDNS=$(sudo readlink "/proc/self/ns/pid" 2>/dev/null || true)
CONT_PIDNS=$(sudo readlink "/proc/$CONTAINER_PID/ns/pid" 2>/dev/null || true)
if [ -n "$CONT_PIDNS" ] && [ "$CONT_PIDNS" != "$HOST_PIDNS" ]; then
    ok "container has its own PID namespace ($CONT_PIDNS != host's $HOST_PIDNS)"
else
    bad "container's PID namespace matches the host's — not isolated"
fi

# --- own mount namespace differs from host's ---
HOST_MNTNS=$(sudo readlink "/proc/self/ns/mnt" 2>/dev/null || true)
CONT_MNTNS=$(sudo readlink "/proc/$CONTAINER_PID/ns/mnt" 2>/dev/null || true)
if [ -n "$CONT_MNTNS" ] && [ "$CONT_MNTNS" != "$HOST_MNTNS" ]; then
    ok "container has its own mount namespace ($CONT_MNTNS != host's $HOST_MNTNS)"
else
    bad "container's mount namespace matches the host's — not isolated"
fi

# --- own UTS namespace differs from host's ---
HOST_UTSNS=$(sudo readlink "/proc/self/ns/uts" 2>/dev/null || true)
CONT_UTSNS=$(sudo readlink "/proc/$CONTAINER_PID/ns/uts" 2>/dev/null || true)
if [ -n "$CONT_UTSNS" ] && [ "$CONT_UTSNS" != "$HOST_UTSNS" ]; then
    ok "container has its own UTS namespace ($CONT_UTSNS != host's $HOST_UTSNS)"
else
    bad "container's UTS namespace matches the host's — not isolated"
fi

# --- own mounted /proc: check via the chrooted view from the host side ---
# /proc/<pid>/root gives the chroot's root as seen from the host.
if sudo test -e "/proc/$CONTAINER_PID/root/proc/1/comm" 2>/dev/null; then
    INNER_COMM=$(sudo cat "/proc/$CONTAINER_PID/root/proc/1/comm" 2>/dev/null || true)
    ok "container's own /proc is mounted and populated (its PID 1 comm = '$INNER_COMM')"
else
    bad "container's \$ROOTFS/proc has no working PID 1 entry — /proc likely wasn't mounted inside the chroot (see Challenge A)"
fi

# --- cgroup-limited ---
CONT_CGROUP=$(sudo cat "/proc/$CONTAINER_PID/cgroup" 2>/dev/null || true)
if echo "$CONT_CGROUP" | grep -q "/mycontainer"; then
    ok "container process is a member of the mycontainer cgroup"
    if [ -f "$CGROUP/memory.max" ]; then
        MEMMAX=$(cat "$CGROUP/memory.max" 2>/dev/null || true)
        if [ "$MEMMAX" != "max" ] && [ -n "$MEMMAX" ]; then
            ok "mycontainer memory.max is actually set ($MEMMAX bytes), not left at 'max'"
        else
            bad "mycontainer memory.max is unset ('max') — limit was never applied"
        fi
    else
        bad "$CGROUP/memory.max does not exist"
    fi
    if [ -f "$CGROUP/cpu.max" ]; then
        CPUMAX=$(cat "$CGROUP/cpu.max" 2>/dev/null || true)
        CPUMAX_QUOTA=$(echo "$CPUMAX" | awk '{print $1}')
        if [ "$CPUMAX_QUOTA" != "max" ] && [ -n "$CPUMAX_QUOTA" ]; then
            ok "mycontainer cpu.max is actually set ($CPUMAX)"
        else
            bad "mycontainer cpu.max is unset ('$CPUMAX') — limit was never applied"
        fi
    else
        bad "$CGROUP/cpu.max does not exist"
    fi
else
    bad "container process's cgroup ($CONT_CGROUP) does not include mycontainer — limits set up in Step 2 were never applied to it (see Challenge B)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] Container has full expected isolation (PID, mount, UTS namespaces + own /proc + cgroup limits)."
    exit 0
else
    exit 1
fi
