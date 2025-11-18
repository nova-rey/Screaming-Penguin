#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${ISO_PATH:-dist/screaming-penguin.iso}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
INSTALLER_MARKER='[SP-INSTALLER] init starting'
QEMU_LOG="qemu-output.log"

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
: > "$QEMU_LOG"
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
  >"$QEMU_LOG" 2>&1; then
  true
else
  echo "[QEMU-CI] QEMU exited (possibly due to timeout)."
fi

echo "[QEMU-CI] QEMU output (tail):"
tail -n 100 "$QEMU_LOG" || true

if grep -q "$INSTALLER_MARKER" "$QEMU_LOG"; then
    echo "[QEMU-CI] Installer banner detected: $INSTALLER_MARKER"
    exit 0
fi

echo "[QEMU-CI] ERROR: Installer did not launch (marker not found)."
exit 1
