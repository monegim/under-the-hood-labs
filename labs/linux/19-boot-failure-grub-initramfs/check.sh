#!/usr/bin/env bash
# Lab 19 check — is the decoy initrd present and valid again (main
# incident resolved), and is the persistent GRUB default still safely
# pointed at a real, bootable entry (not the decoy)?
set -uo pipefail

PASS=0
DECOY_INITRD="/boot/initrd.img-lab19-test"

echo "[check] checking for the decoy initrd file..."
if [ -s "$DECOY_INITRD" ]; then
    echo "[check] $DECOY_INITRD exists and is non-empty."
else
    echo "[FAIL] $DECOY_INITRD is missing or empty - the incident is not resolved."
    PASS=1
fi

if [ -s "$DECOY_INITRD" ]; then
    echo "[check] checking it's actually a valid archive, not just an empty/garbage file..."
    FILETYPE=$(file -b "$DECOY_INITRD" 2>/dev/null || echo "unknown")
    echo "[check] file type: $FILETYPE"
    if echo "$FILETYPE" | grep -qiE 'cpio|gzip|compress'; then
        echo "[check] looks like a real initramfs archive."
    else
        echo "[FAIL] doesn't look like a valid initramfs archive: $FILETYPE"
        PASS=1
    fi
fi

echo "[check] confirming the persistent GRUB default has NOT been left pointed at the decoy entry..."
SAVED_ENTRY=$(sudo grub-editenv list 2>/dev/null | grep '^saved_entry=' || true)
echo "[check] grub-editenv: ${SAVED_ENTRY:-<none set>}"
if echo "$SAVED_ENTRY" | grep -qi 'lab19'; then
    echo "[FAIL] the persistent GRUB default still points at the Lab 19 decoy entry - every future reboot would hit it."
    PASS=1
else
    echo "[check] persistent default is safe."
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] decoy initrd is present/valid and the persistent GRUB default is safe."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
