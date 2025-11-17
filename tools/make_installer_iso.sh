#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

echo "[SP-ISO] Building hybrid ISO image…"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/iso"
DIST_DIR="$ROOT/dist"
ISO="$DIST_DIR/screaming-penguin.iso"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "[SP-ISO] Preparing ISO tree…"
rm -rf "${BUILD_DIR:?}"/*
mkdir -p "$BUILD_DIR/iso/boot"
mkdir -p "$BUILD_DIR/iso/EFI/boot"

# Copy kernel + initramfs from the existing runtime build
cp "$ROOT/build/runtime/vmlinuz" "$BUILD_DIR/iso/boot/vmlinuz"
cp "$ROOT/build/runtime/initrd.img" "$BUILD_DIR/iso/boot/initrd.img"

# Minimal GRUB configs
cat > "$BUILD_DIR/iso/boot/grub.cfg" <<EOF
set default=0
set timeout=3
menuentry "Screaming Penguin Installer" {
    linux /boot/vmlinuz quiet
    initrd /boot/initrd.img
}
EOF

cat > "$BUILD_DIR/iso/EFI/boot/grub.cfg" <<EOF
search --file --no-floppy --set=root /boot/vmlinuz
set default=0
set timeout=3
menuentry "Screaming Penguin Installer" {
    linux /boot/vmlinuz quiet
    initrd /boot/initrd.img
}
EOF

# Copy GRUB EFI binary (use system grub-mkstandalone)
echo "[SP-ISO] Building EFI bootloader…"
grub-mkstandalone \
    --format=x86_64-efi \
    --output="$BUILD_DIR/iso/EFI/boot/bootx64.efi" \
    "boot/grub/grub.cfg=$BUILD_DIR/iso/EFI/boot/grub.cfg"

echo "[SP-ISO] Generating hybrid ISO…"
grub-mkrescue \
    -o "$ISO" \
    "$BUILD_DIR/iso"

echo "[SP-ISO] ISO created: $ISO"
