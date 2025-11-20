#!/bin/sh
# Minimal Screaming Penguin installer init for CI smoke testing

# Best-effort logging to primary console and serial
{
  echo "[SP-INSTALLER] init reached" >/dev/console 2>/dev/null || true
  echo "[SP-INSTALLER] init reached" >/dev/ttyS0 2>/dev/null || true
} || true

# Keep PID 1 alive; prefer an interactive shell on the console
if [ -x /bin/sh ]; then
    exec /bin/sh </dev/console >/dev/console 2>&1
fi

# Fallback idle loop if no shell is available
while :; do
    sleep 60
done
