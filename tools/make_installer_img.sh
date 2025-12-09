#!/bin/sh
# Screaming Penguin - Image Builder (Phase 13)
# Builds a GPT-based installer image with a FAT32 EFI System Partition.

set -eu

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$PROJECT_ROOT/build"

IMG_OUT="${SP_IMG_OUT:-$DIST_DIR/screaming-penguin.img}"
IMG_SIZE="${SP_IMG_SIZE:-3G}"
P1_SIZE_MB="${SP_IMG_BOOT_SIZE_MB:-512}"
P2_SIZE_MB="${SP_IMG_CONFIG_SIZE_MB:-2048}"
ESP_LABEL="${SP_IMG_BOOT_LABEL:-SP_BOOT}"
CONFIG_LABEL="${SP_IMG_CONFIG_LABEL:-SP_CONFIG}"
GRUB_HELPER="$PROJECT_ROOT/tools/grub_shared.sh"

if [ ! -f "$GRUB_HELPER" ]; then
    echo "[SP-IMG] Missing GRUB helper: $GRUB_HELPER" >&2
    exit 1
fi

# shellcheck source=tools/grub_shared.sh
. "$GRUB_HELPER"

sp_find_installer_artifact() {
    candidate="$1"
    fallback="$2"

    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
    fi

    if [ -n "$fallback" ] && [ -f "$fallback" ]; then
        printf '%s' "$fallback"
        return 0
    fi

    return 1
}

BOOT_TREE="$BUILD_DIR/boot-tree"
ESP_DIR="$BOOT_TREE/EFI/BOOT"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "[SP-IMG] Cleaning build directory…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$BOOT_TREE"

INSTALLER_KERNEL_PATH=""
INSTALLER_INITRD_PATH=""
if ! INSTALLER_KERNEL_PATH=$(sp_find_installer_artifact "$DIST_DIR/vmlinuz-installer" "$BUILD_DIR/runtime/vmlinuz"); then
    INSTALLER_KERNEL_PATH=""
fi
if ! INSTALLER_INITRD_PATH=$(sp_find_installer_artifact "$DIST_DIR/initrd-installer.img" "$BUILD_DIR/initrd-installer.img"); then
    INSTALLER_INITRD_PATH=""
fi

if [ -z "$INSTALLER_KERNEL_PATH" ] || [ -z "$INSTALLER_INITRD_PATH" ]; then
    printf '[SP-IMG] ERROR: Missing installer artifacts.\nEnsure dist/vmlinuz-installer and dist/initrd-installer.img exist (or build/runtime/vmlinuz + build/initrd-installer.img).\n' >&2
    exit 1
fi

echo "[SP-IMG] Creating raw disk image $IMG_OUT…"
truncate -s "$IMG_SIZE" "$IMG_OUT"

### PARTITIONING ###

echo "[SP-IMG] Creating GPT table…"
parted -s "$IMG_OUT" mklabel gpt >/dev/null

echo "[SP-IMG] Creating boot partition (p1)…"
parted -s "$IMG_OUT" mkpart primary 1MiB "${P1_SIZE_MB}"MiB >/dev/null
parted -s "$IMG_OUT" set 1 boot on >/dev/null
parted -s "$IMG_OUT" set 1 esp on >/dev/null
parted -s "$IMG_OUT" set 1 legacy_boot on >/dev/null

echo "[SP-IMG] Creating config partition (p2)…"
parted -s "$IMG_OUT" mkpart primary "${P1_SIZE_MB}"MiB "$((P1_SIZE_MB + P2_SIZE_MB))"MiB >/dev/null

### LOOP DEVICE SETUP ###

echo "[SP-IMG] Attaching loop device…"
LOOPDEV=$(losetup --find --show "$IMG_OUT")
cleanup() {
    echo "[SP-IMG] Cleaning up loop devices…"
    kpartx -dv "$LOOPDEV" >/dev/null 2>&1 || true
    losetup -d "$LOOPDEV" >/dev/null 2>&1 || true
}
trap cleanup EXIT


echo "[SP-IMG] Mapping partitions…"
kpartx -av "$LOOPDEV" >/dev/null
sleep 1

P1_DEV="/dev/mapper/$(basename "$LOOPDEV")p1"
P2_DEV="/dev/mapper/$(basename "$LOOPDEV")p2"

### FORMAT PARTITIONS ###

echo "[SP-IMG] Formatting p1 as FAT32 (ESP)…"
mkfs.vfat -n "$ESP_LABEL" "$P1_DEV"

echo "[SP-IMG] Formatting p2 as FAT32 (SP_CONFIG)…"
mkfs.vfat -n "$CONFIG_LABEL" "$P2_DEV"

### BOOT TREE ###

echo "[SP-IMG] Building boot tree…"
rm -rf "$BOOT_TREE"
mkdir -p "$BOOT_TREE/boot"
mkdir -p "$ESP_DIR"

cp "$INSTALLER_KERNEL_PATH" "$BOOT_TREE/boot/vmlinuz-installer"
cp "$INSTALLER_INITRD_PATH" "$BOOT_TREE/boot/initrd-installer.img"

GRUB_EFI_BINARY=""
if ! GRUB_EFI_BINARY=$(sp_resolve_grub_efi_binary); then
    GRUB_EFI_BINARY=""
fi

if [ -z "$GRUB_EFI_BINARY" ]; then
    echo "[SP-IMG] ERROR: grubx64.efi not found (install grub-efi-amd64-bin or set SP_GRUB_EFI_BIN)." >&2
    exit 1
fi

cp "$GRUB_EFI_BINARY" "$ESP_DIR/grubx64.efi"
cp "$ESP_DIR/grubx64.efi" "$ESP_DIR/BOOTX64.EFI"

cat <<'EOF_GRUB' > "$ESP_DIR/grub.cfg"
search --no-floppy --file /boot/vmlinuz-installer --set=root
set default=0
set timeout=0

menuentry "Screaming Penguin Installer" {
EOF_GRUB
sp_installer_grub_kernel_lines "quiet" "" >> "$ESP_DIR/grub.cfg"
cat <<'EOF_GRUB_END' >> "$ESP_DIR/grub.cfg"
}
EOF_GRUB_END

### POPULATE P1 ###

echo "[SP-IMG] Mounting boot partition…"
mkdir -p "$BUILD_DIR/mount-p1"
mount "$P1_DEV" "$BUILD_DIR/mount-p1"

cp -a "$BOOT_TREE"/. "$BUILD_DIR/mount-p1/"

sync

echo "[SP-IMG] Unmounting boot partition…"
umount "$BUILD_DIR/mount-p1"

### FINALIZE ###

echo "[SP-IMG] Image build complete."
echo "[SP-IMG] Output: $IMG_OUT"
