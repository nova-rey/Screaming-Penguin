#!/bin/sh
# Minimal Screaming Penguin installer init for CI smoke testing

set -e

# Ensure kernel interfaces are mounted for basic tooling.
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true

# Direct all output to serial so QEMU CI can scrape it reliably.
exec >/dev/ttyS0 2>&1

echo "[SP-INSTALLER] init reached"

# Keep PID 1 alive; prefer an interactive shell on the console/serial.
if [ -x /bin/sh ]; then
    exec /bin/sh < /dev/ttyS0
fi

# Fallback idle loop if no shell is available
while :; do
    sleep 60
done
