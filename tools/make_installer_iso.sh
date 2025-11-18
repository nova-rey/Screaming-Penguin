#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

echo "[SP-ISO] Building hybrid ISO image…"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/iso"
DIST_DIR="$ROOT/dist"
ISO="$DIST_DIR/screaming-penguin.iso"
ISO_ROOT="$BUILD_DIR/iso"
SP_KERNEL_CMDLINE="quiet"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "[SP-ISO] Preparing ISO tree…"
rm -rf "${BUILD_DIR:?}"/*
mkdir -p "${ISO_ROOT}/boot/grub"
mkdir -p "${ISO_ROOT}/EFI/boot"

# Copy kernel + initramfs from the existing runtime build
cp "$ROOT/build/runtime/vmlinuz" "${ISO_ROOT}/boot/vmlinuz"
cp "$ROOT/build/runtime/initrd.img" "${ISO_ROOT}/boot/initrd.img"

# Minimal GRUB configs
cat > "${ISO_ROOT}/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5

menuentry "Screaming Penguin Installer" {
    linux /boot/vmlinuz ${SP_KERNEL_CMDLINE}
    initrd /boot/initrd.img
}
EOF

cat > "${ISO_ROOT}/EFI/boot/grub.cfg" <<EOF
search --file --no-floppy --set=root /boot/vmlinuz
set default=0
set timeout=5
menuentry "Screaming Penguin Installer" {
    linux /boot/vmlinuz ${SP_KERNEL_CMDLINE}
    initrd /boot/initrd.img
}
EOF

# Copy GRUB EFI binary (use system grub-mkstandalone)
echo "[SP-ISO] Building EFI bootloader…"
grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_ROOT}/EFI/boot/bootx64.efi" \
    "boot/grub/grub.cfg=${ISO_ROOT}/EFI/boot/grub.cfg"

echo "[SP-ISO] Generating hybrid ISO…"
grub-mkrescue \
    -o "$ISO" \
    "$ISO_ROOT"

echo "[SP-ISO] ISO created: $ISO"
