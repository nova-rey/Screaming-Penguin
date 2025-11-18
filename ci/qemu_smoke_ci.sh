#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${ISO_PATH:-dist/screaming-penguin.iso}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

echo "[QEMU-CI] Using ISO at: $ISO_PATH"
if [ ! -f "$ISO_PATH" ]; then
    echo "[QEMU-CI] ERROR: ISO not found at $ISO_PATH"
    exit 1
fi

ls -lh "$ISO_PATH" || true

if command -v xorriso >/dev/null 2>&1; then
    echo "[QEMU-CI] El Torito entries (xorriso):"
    xorriso -indev "$ISO_PATH" -report_el_torito plain || true
elif command -v isoinfo >/dev/null 2>&1; then
    echo "[QEMU-CI] El Torito entries (isoinfo):"
    isoinfo -d -i "$ISO_PATH" || true
else
    echo "[QEMU-CI] WARNING: No ISO inspection tool available."
fi

echo "[QEMU-CI] Booting ISO in QEMU..."
: > qemu-output.log
if timeout 60s "$QEMU_BIN" \
  -m 1024 \
  -no-reboot \
  -no-shutdown \
  -nographic \
  -boot order=d \
  -cdrom "$ISO_PATH" \
  -serial stdio \
  -monitor none \
  -nodefaults \
  -display none \
  >qemu-output.log 2>&1; then
  true
else
  echo "[QEMU-CI] QEMU exited (possibly due to timeout)."
fi

echo "[QEMU-CI] QEMU output (tail):"
tail -n 100 qemu-output.log || true

if grep -q "\[SP-INSTALLER\] Init starting" qemu-output.log; then
    echo "[QEMU-CI] Installer launched successfully."
    exit 0
fi

echo "[QEMU-CI] ERROR: Installer did not launch."
exit 1
