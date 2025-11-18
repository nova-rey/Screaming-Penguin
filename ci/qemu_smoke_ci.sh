#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${ISO_PATH:-dist/screaming-penguin.iso}"
KERNEL_PATH="${SP_QEMU_KERNEL:-}"
KERNEL_ARGS=()

if [ ! -f "$ISO_PATH" ]; then
    echo "[QEMU-CI] ERROR: ISO not found at $ISO_PATH"
    exit 1
fi

if [ -n "$KERNEL_PATH" ]; then
    if [ -f "$KERNEL_PATH" ]; then
        echo "[QEMU-CI] Using explicit kernel: $KERNEL_PATH"
        KERNEL_ARGS=(-kernel "$KERNEL_PATH")
    else
        echo "[QEMU-CI] WARNING: SP_QEMU_KERNEL is set but file not found: $KERNEL_PATH"
        echo "[QEMU-CI] Proceeding with ISO boot only."
    fi
fi

echo "[QEMU-CI] Booting ISO in QEMU..."

timeout 40s qemu-system-x86_64 \
  -m 1024 \
  -cdrom "$ISO_PATH" \
  -nographic \
  -no-reboot \
  "${KERNEL_ARGS[@]}" \
  2>&1 | tee qemu.log || true

if grep -q "SP-INSTALLER" qemu.log; then
    echo "[QEMU-CI] Installer initramfs launched successfully."
    exit 0
fi

echo "[QEMU-CI] ERROR: Installer did not launch."
exit 1
