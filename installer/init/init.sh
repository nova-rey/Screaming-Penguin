#!/bin/sh
set -eu

# Minimal Screaming Penguin installer init (temporary bring-up)

if [ -c /dev/console ]; then
  echo "[SP-INSTALLER] init reached" > /dev/console
else
  echo "[SP-INSTALLER] init reached"
fi

echo "Screaming Penguin init shell (temporary bring-up)"
echo "You are in the initramfs environment."

if [ -x /bin/sh ]; then
  exec /bin/sh
fi

# Fallback: avoid immediate kernel panic if no shell is available
while :; do
  sleep 60
done
