#!/usr/bin/env bash
set -euo pipefail

ISO_PATH="${ISO_PATH:-dist/screaming-penguin.iso}"
KERNEL_PATH="${KERNEL_PATH:-build/runtime/vmlinuz}"
INITRD_PATH="${INITRD_PATH:-build/runtime-installer/initrd-installer.img}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
QEMU_TIMEOUT_SEC="${QEMU_TIMEOUT_SEC:-90}"
# Marker string printed by the installer to the console/serial log
INSTALL_MARKER='[SP-INSTALLER] init starting'
QEMU_LOG="qemu_smoke.log"

echo "[QEMU-CI] Using ISO at: $ISO_PATH"
if [ -f "$ISO_PATH" ]; then
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
else
    echo "[QEMU-CI] WARNING: ISO not found at $ISO_PATH (informational only)."
fi

if [ ! -f "$KERNEL_PATH" ] || [ ! -f "$INITRD_PATH" ]; then
    echo "[QEMU-CI] ERROR: Kernel or initrd missing for smoke test."
    ls -l "$KERNEL_PATH" "$INITRD_PATH" 2>/dev/null || true
    ls dist 2>/dev/null || true
    exit 1
fi

if command -v lsinitramfs >/dev/null 2>&1; then
    if ! lsinitramfs "$INITRD_PATH" | grep -Fx 'init'; then
        echo "[QEMU-CI] ERROR: /init not found inside initramfs ($INITRD_PATH)."
        exit 1
    fi
fi

rm -f "$QEMU_LOG"

echo "[QEMU-CI] Booting kernel+initrd in QEMU..."
timeout "${QEMU_TIMEOUT_SEC}s" "$QEMU_BIN" \
  -m 1024 \
  -kernel "$KERNEL_PATH" \
  -initrd "$INITRD_PATH" \
  -append "root=/dev/ram0 rw console=ttyS0,115200 console=tty0 quiet" \
  -nographic \
  -no-reboot -no-shutdown \
  -serial mon:stdio \
  >"$QEMU_LOG" 2>&1 || true

echo "[QEMU-CI] QEMU exited (possibly due to timeout or shutdown)."
echo "[QEMU-CI] Checking for installer marker: $INSTALL_MARKER"

if grep -F -- "$INSTALL_MARKER" "$QEMU_LOG"; then
    echo "[QEMU-CI] Installer marker found; smoke test passed."
    exit 0
else
    echo "[QEMU-CI] ERROR: Installer did not launch (marker not found)."
    echo "[QEMU-CI] Last 100 lines of QEMU log:"
    tail -n 100 "$QEMU_LOG" || true
    exit 1
fi
