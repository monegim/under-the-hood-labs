#!/usr/bin/env bash
# Lab 5 — Overlay Filesystems — check.sh
#
# Verifies the overlay built by README.md Steps 1-5 is in the exact state
# those steps are supposed to leave it in:
#   - the overlay is mounted at $OVL/merged
#   - Step 3's copy-up happened: upper/file1.txt exists and contains the
#     appended line, lower/file1.txt is untouched
#   - Step 4's whiteout happened: merged/file2.txt is gone, lower/file2.txt
#     is untouched, and upper/file2.txt is a char device 0:0 (the whiteout)
#   - Step 5's new file went straight to upper: merged/file3.txt exists
#
# This checks the state currently on disk — run it any time after Step 5
# and before Step 7's cleanup umount.
#
# Usage: bash check.sh — if you run this as `sudo bash check.sh` instead,
# REAL_HOME resolution below still points $OVL at the invoking user's
# directory rather than /root's (sudo resets $HOME by default).
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 5 — Overlay Filesystems"
echo

if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
fi
REAL_HOME="${REAL_HOME:-$HOME}"

OVL="$REAL_HOME/ovl"

# --- overlay is mounted ---
if mount | grep -q "on $OVL/merged type overlay"; then
    ok "overlay is mounted at $OVL/merged"
else
    bad "no overlay mount found at $OVL/merged (did you run Step 2?)"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

# --- Step 3: copy-up of file1.txt ---
if [ -f "$OVL/upper/file1.txt" ]; then
    ok "file1.txt exists in upper (copy-up happened)"
    if grep -q "modified in merged" "$OVL/upper/file1.txt" 2>/dev/null; then
        ok "upper/file1.txt contains the appended line from Step 3"
    else
        bad "upper/file1.txt exists but doesn't contain the expected 'modified in merged' line — did you run Step 3?"
    fi
else
    bad "upper/file1.txt does not exist — no copy-up has happened yet (run Step 3)"
fi

if [ -f "$OVL/lower/file1.txt" ] && grep -q "^from lower$" "$OVL/lower/file1.txt" 2>/dev/null \
   && ! grep -q "modified in merged" "$OVL/lower/file1.txt" 2>/dev/null; then
    ok "lower/file1.txt is untouched by the copy-up"
else
    bad "lower/file1.txt is missing or was itself modified — copy-up should never touch the lower layer"
fi

# --- Step 4: whiteout of file2.txt ---
if [ ! -e "$OVL/merged/file2.txt" ]; then
    ok "file2.txt is gone from the merged view (deleted in Step 4)"
else
    bad "merged/file2.txt still exists — did you run Step 4 (rm \$OVL/merged/file2.txt)?"
fi

if [ -f "$OVL/lower/file2.txt" ]; then
    ok "lower/file2.txt is still fully intact (deletion never touches lower data)"
else
    bad "lower/file2.txt is missing — the lower layer should never lose data from a merged-view delete"
fi

if [ -e "$OVL/upper/file2.txt" ]; then
    MAJMIN=$(stat -c '%t:%T' "$OVL/upper/file2.txt" 2>/dev/null || true)
    if [ -c "$OVL/upper/file2.txt" ] && [ "$MAJMIN" = "0:0" ]; then
        ok "upper/file2.txt is a whiteout (char device 0:0) masking the lower file"
    else
        bad "upper/file2.txt exists but isn't a 0:0 char device whiteout (type/majmin: $MAJMIN)"
    fi
else
    bad "upper/file2.txt (the whiteout marker) does not exist — was file2.txt actually deleted through \$OVL/merged?"
fi

# --- Step 5: new file goes straight to upper ---
if [ -f "$OVL/upper/file3.txt" ] && grep -q "brand new" "$OVL/upper/file3.txt" 2>/dev/null; then
    ok "file3.txt was written directly to upper (Step 5)"
else
    bad "upper/file3.txt missing or wrong content — did you run Step 5?"
fi

if [ -f "$OVL/merged/file3.txt" ]; then
    ok "file3.txt is visible in the merged view"
else
    bad "merged/file3.txt is not visible even though it should be a plain new file"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] Overlay copy-up/whiteout mechanics all match what README.md Steps 1-5 build."
    exit 0
else
    exit 1
fi
