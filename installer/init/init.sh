#!/bin/sh
# Minimal Screaming Penguin installer init for CI smoke testing

set -e

# Ensure kernel interfaces are mounted for basic tooling.
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true

MARKER="[SP-INSTALLER] init reached"

# Emit the marker on both the primary console and serial before redirecting
# stdout/stderr so CI can always scrape it, even if the redirect fails.
{
    echo "$MARKER" >/dev/console 2>/dev/null || true
    echo "$MARKER" >/dev/ttyS0 2>/dev/null || true
} || true

# Direct all output to serial so QEMU CI can scrape it reliably.
exec >/dev/ttyS0 2>&1

echo "$MARKER"

# Keep PID 1 alive; prefer an interactive shell on the console/serial.
if [ -x /bin/sh ]; then
    exec /bin/sh < /dev/ttyS0
fi

# Fallback idle loop if no shell is available
while :; do
    sleep 60
done
