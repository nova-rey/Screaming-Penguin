#!/usr/bin/env bash
set -euo pipefail

ISO="dist/screaming-penguin.iso"

if [ ! -f "$ISO" ]; then
    echo "[QEMU-CI] ISO not found: $ISO"
    exit 1
fi

echo "[QEMU-CI] Booting ISO in QEMU..."

timeout 40s qemu-system-x86_64 \
  -m 1024 \
  -cdrom "$ISO" \
  -nographic \
  -no-reboot \
  -kernel none \
  2>&1 | tee qemu.log || true

if grep -q "SP-INSTALLER" qemu.log; then
    echo "[QEMU-CI] Installer initramfs launched successfully."
    exit 0
fi

echo "[QEMU-CI] ERROR: Installer did not launch."
exit 1
