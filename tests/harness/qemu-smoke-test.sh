#!/bin/sh
# Screaming Penguin - QEMU Smoke Test (Phase 3)
# Boots the built image in QEMU (BIOS) to ensure kernel + initramfs + skeleton runtime load.

set -eu

IMG="dist/screaming-penguin.img"

if [ ! -f "$IMG" ]; then
    echo "[QEMU] Image not found: $IMG"
    echo "[QEMU] Run 'make iso' first."
    exit 1
fi

echo "[QEMU] Booting Screaming Penguin image (BIOS mode)…"

qemu-system-x86_64 \
    -m 1024 \
    -drive file="$IMG",format=raw \
    -serial stdio \
    -display none


echo "[QEMU] If logs appear from initramfs and sp-installer Phase 2 skeleton, the smoke test passed."
