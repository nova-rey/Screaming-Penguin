#!/bin/sh
# Screaming Penguin - Image Builder (Phase 3 C1–C3)
# Safe, file-only raw disk image builder.
# This script MUST NOT touch real block devices.
#
# All destructive operations operate ONLY on files under ./build or ./dist.

set -eu

### CONFIGURATION ###
IMG_OUT="dist/screaming-penguin.img"
IMG_SIZE="3G"              # Adjustable
BUILD_DIR="build"
BOOT_TREE="$BUILD_DIR/boot-tree"     # Temporary boot environment
P1_SIZE_MB=512                         # Boot partition
P2_SIZE_MB=2048                        # Config partition

### PREP ###
mkdir -p "$BUILD_DIR" dist

echo "[SP-IMG] Cleaning build directory…"
rm -rf "$BUILD_DIR"/*
mkdir -p "$BOOT_TREE"

echo "[SP-IMG] Creating raw disk image $IMG_OUT…"
truncate -s "$IMG_SIZE" "$IMG_OUT"

### PARTITIONING ###
echo "[SP-IMG] Creating GPT table…"
parted -s "$IMG_OUT" mklabel gpt

echo "[SP-IMG] Creating boot partition (p1)…"
parted -s "$IMG_OUT" mkpart primary 1MiB "${P1_SIZE_MB}MiB"
echo "[SP-IMG] Setting legacy_boot flag (BIOS)…"
parted -s "$IMG_OUT" set 1 legacy_boot on

echo "[SP-IMG] Creating config partition (p2)…"
parted -s "$IMG_OUT" mkpart primary "${P1_SIZE_MB}MiB" "$((P1_SIZE_MB + P2_SIZE_MB))MiB"

### LOOP DEVICE SETUP ###
echo "[SP-IMG] Attaching loop device…"
LOOPDEV=$(losetup --find --show "$IMG_OUT")
trap 'losetup -d "$LOOPDEV" || true' EXIT

echo "[SP-IMG] Mapping partitions…"
kpartx -av "$LOOPDEV" >/dev/null
sleep 1

P1_DEV="/dev/mapper/$(basename "$LOOPDEV")p1"
P2_DEV="/dev/mapper/$(basename "$LOOPDEV")p2"

### FORMAT P2 (FAT32) ###
echo "[SP-IMG] Formatting p2 as FAT32…"
mkfs.vfat -n SP_CONFIG "$P2_DEV"

### BUILD BOOT TREE ###
# NOTE: p1 population (kernel, initramfs, GRUB) is minimal in Phase 3.
#       Real bootloader wiring arrives in Phase 4 or 5.

echo "[SP-IMG] Building minimal boot tree…"

mkdir -p "$BOOT_TREE/boot"

# Kernel and initramfs are expected to exist under installer/initramfs output.
# For Phase 3, we accept placeholders.
cp -a installer/initramfs "$BOOT_TREE/initramfs" 2>/dev/null || true
echo "Placeholder kernel" > "$BOOT_TREE/boot/vmlinuz-sp"
echo "Placeholder initramfs" > "$BOOT_TREE/boot/initrd.img-sp"

# Minimal GRUB directory for future expansion.
mkdir -p "$BOOT_TREE/EFI/BOOT"
echo "search --file --set=root /boot/vmlinuz-sp" > "$BOOT_TREE/boot/grub.cfg"
echo "linux /boot/vmlinuz-sp quiet" >> "$BOOT_TREE/boot/grub.cfg"
echo "initrd /boot/initrd.img-sp" >> "$BOOT_TREE/boot/grub.cfg"
echo "boot" >> "$BOOT_TREE/boot/grub.cfg"

### POPULATE P1 ###
echo "[SP-IMG] Populating boot partition p1…"
mkfs.ext2 "$P1_DEV"
mkdir -p "$BUILD_DIR/mount-p1"
mount "$P1_DEV" "$BUILD_DIR/mount-p1"

cp -a "$BOOT_TREE"/* "$BUILD_DIR/mount-p1/"

sync
umount "$BUILD_DIR/mount-p1"

### FINALIZE ###
echo "[SP-IMG] Cleaning up loop devices…"
kpartx -dv "$LOOPDEV" >/dev/null
losetup -d "$LOOPDEV"

echo "[SP-IMG] Image build complete."
echo "[SP-IMG] Output: $IMG_OUT"
