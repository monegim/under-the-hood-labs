#!/usr/bin/env bash
# Lab 19 reset — remove all decoy GRUB entries/files and any persistent
# default override from the challenges, regenerate a clean grub.cfg, then
# re-run setup.sh to reproduce the main incident (missing decoy initrd).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] restoring the persistent GRUB default to entry 0, in case Challenge B changed it..."
sudo grub-set-default 0 2>/dev/null || true

echo "[reset] removing the Lab 19 custom grub.d script and decoy boot files..."
sudo rm -f /etc/grub.d/46_lab19
sudo rm -f /boot/vmlinuz-lab19-test /boot/initrd.img-lab19-test

echo "[reset] removing the Challenge A custom entry, if present..."
sudo rm -f /etc/grub.d/47_lab19_challenge_a

echo "[reset] regenerating grub.cfg..."
sudo update-grub

echo "[reset] re-running setup.sh to rebuild the main incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done. Confirm your default entry is untouched with: sudo grub-editenv list"
