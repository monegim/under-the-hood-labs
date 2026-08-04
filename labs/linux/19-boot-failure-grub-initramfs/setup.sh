#!/usr/bin/env bash
# Lab 19 setup — builds a broken GRUB boot entry that is COMPLETELY safe
# to leave in place: it is never the default entry, and your real running
# kernel's own vmlinuz/initrd are never touched, moved, or renamed.
#
# We add a decoy menu entry ("Lab 19 - test kernel") that points at copies
# of your real kernel/initrd under new names, then delete the initrd copy -
# simulating the extremely common "kernel image landed but initramfs
# generation/copy never completed" incident (disk full mid-upgrade, a
# botched manual kernel install, an interrupted `update-initramfs` run).
#
# See README.md for why this lab does NOT force a real reboot into the
# broken entry by default.
set -euo pipefail

KVER="$(uname -r)"
DECOY_KERNEL="/boot/vmlinuz-lab19-test"
DECOY_INITRD="/boot/initrd.img-lab19-test"

echo "[1/5] Confirming the real kernel/initrd exist for $KVER..."
ls -la "/boot/vmlinuz-$KVER" "/boot/initrd.img-$KVER"

echo "[2/5] Creating decoy kernel/initrd copies (never referenced as default)..."
sudo cp "/boot/vmlinuz-$KVER" "$DECOY_KERNEL"
sudo cp "/boot/initrd.img-$KVER" "$DECOY_INITRD"

echo "[3/5] Adding a custom GRUB menu entry pointing at the decoy files..."
ROOT_UUID="$(findmnt -no UUID /)"
sudo mkdir -p /etc/grub.d
sudo tee /etc/grub.d/46_lab19 > /dev/null <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "Lab 19 - test kernel (DO NOT SELECT - decoy, do not boot this)" {
	echo "Loading Lab 19 test kernel..."
	linux $DECOY_KERNEL root=UUID=$ROOT_UUID ro
	echo "Loading Lab 19 test initrd..."
	initrd $DECOY_INITRD
}
EOF
sudo chmod +x /etc/grub.d/46_lab19

echo "[4/5] Regenerating grub.cfg (this only ADDS the decoy entry; your"
echo "      default boot entry and GRUB_DEFAULT are untouched)..."
GRUB_DEFAULT_BEFORE="$(grep -E '^GRUB_DEFAULT=' /etc/default/grub || echo 'GRUB_DEFAULT=0 (implicit)')"
sudo update-grub
echo "      GRUB_DEFAULT before: $GRUB_DEFAULT_BEFORE"
echo "      GRUB_DEFAULT after:  $(grep -E '^GRUB_DEFAULT=' /etc/default/grub || echo 'GRUB_DEFAULT=0 (implicit)')"

echo "[5/5] Deleting the decoy initrd - this is the bug: kernel present, initrd missing."
sudo rm -f "$DECOY_INITRD"

echo
echo "Done. The decoy entry now references a kernel that exists and an"
echo "initrd that does NOT. Your default boot entry is completely unaffected -"
echo "confirm with:"
echo "  sudo grub-editenv list"
echo "  cat /boot/grub/grub.cfg | grep -c '^menuentry'"
echo "Inspect the damage with:"
echo "  cat /boot/grub/grub.cfg | grep -A 12 'Lab 19 - test kernel'"
echo "  ls -la /boot/*lab19*"
