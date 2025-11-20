#!/bin/sh
# Minimal Screaming Penguin installer init for CI smoke testing

# Try to avoid dying on best-effort operations
set +e

# Mount essential pseudo filesystems (ignore failures)
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || \
    mount -t tmpfs devtmpfs /dev 2>/dev/null || true

# Emit the CI marker to both console and serial if available
if [ -c /dev/console ]; then
  echo "[SP-INSTALLER] init reached" >/dev/console 2>/dev/null || true
else
  echo "[SP-INSTALLER] init reached"
fi

echo "[SP-INSTALLER] init reached" >/dev/ttyS0 2>/dev/null || true

# Drop to an interactive shell for debugging
exec sh
