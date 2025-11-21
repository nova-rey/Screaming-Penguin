#!/bin/sh
# shellcheck shell=dash

# Minimal, POSIX-friendly bootstrap for the installer initramfs.

# Ensure a predictable PATH for BusyBox applets and any future tooling.
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

# Make BusyBox applets available under /bin for convenience.
if [ -x /bin/busybox ]; then
    /bin/busybox --install -s /bin 2>/dev/null || true
fi

# Mount essential virtual filesystems; tolerate failures to keep early boot stable.
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs devtmpfs /dev 2>/dev/null || true

# CI marker required by qemu_smoke_ci.sh.
echo "[SP-INSTALLER] init reached"

# Stage 1 breadcrumb for future debugging (not enforced by CI yet).
echo "[SP-INSTALLER] stage=bootstrapped"

# Placeholder: installer main will be wired in later stages. Keep the kernel happy.
exec sh -i </dev/console >/dev/console 2>&1
