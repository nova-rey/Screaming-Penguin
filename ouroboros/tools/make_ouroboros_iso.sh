#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$root_dir/build"
dist_dir="$root_dir/dist"
initramfs_src="$root_dir/initramfs_root"
scripts_src="$root_dir/scripts"
iso_name="sp-ouroboros.iso"
iso_path="$dist_dir/$iso_name"
initramfs_stage="$build_dir/initramfs"
initramfs_image="$build_dir/initramfs.img"
iso_root="$build_dir/iso-root"

err() {
  echo "[make_ouroboros_iso] ERROR: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "missing required command '$1'"
  fi
}

require_command cpio
require_command gzip
require_command realpath
require_command xorriso
require_command find
require_command sort
require_command head

initramfs_src="$(realpath "$initramfs_src")"
if [ ! -d "$initramfs_src" ]; then
  err "missing initramfs source directory: $initramfs_src"
fi

scripts_src="$(realpath "$scripts_src")"
if [ ! -d "$scripts_src" ]; then
  err "missing scripts directory: $scripts_src"
fi

mkdir -p "$build_dir" "$dist_dir"

isolinux_bin="/usr/lib/ISOLINUX/isolinux.bin"
ldlinux_c32="/usr/lib/syslinux/modules/bios/ldlinux.c32"
isohdpfx_bin="/usr/lib/ISOLINUX/isohdpfx.bin"

for path in "$isolinux_bin" "$ldlinux_c32" "$isohdpfx_bin"; do
  if [ ! -e "$path" ]; then
    err "required isolinux component missing: $path"
  fi
done

find_kernel_image() {
  local candidate
  candidate="/boot/vmlinuz-$(uname -r)"
  if [ -f "$candidate" ]; then
    realpath "$candidate"
    return 0
  fi

  candidate=$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*' 2>/dev/null | sort | head -n1 || true)
  if [ -n "$candidate" ]; then
    realpath "$candidate"
    return 0
  fi

  err "no kernel image found under /boot; install linux-image-<version>"
}

copy_kernel_with_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    err "kernel image is not readable; rerun as root or make it world-readable"
  fi

  echo "[make_ouroboros_iso] Copying kernel with sudo to work around permissions"
  sudo cp "$1" "$iso_root/vmlinuz"
  sudo chown "$(id -u):$(id -g)" "$iso_root/vmlinuz"
}

stage_initramfs() {
  echo "[make_ouroboros_iso] Staging initramfs payload"
  rm -rf "$initramfs_stage"
  mkdir -p "$initramfs_stage"

  cp -a "$initramfs_src/." "$initramfs_stage"
  mkdir -p "$initramfs_stage/ouroboros"
  cp -a "$scripts_src" "$initramfs_stage/ouroboros/"
  mkdir -p "$initramfs_stage"/{proc,sys,dev,run,tmp}

  busybox_bin="$initramfs_stage/bin/busybox"
  if [ ! -x "$busybox_bin" ]; then
    err "busybox binary not found in initramfs payload: $busybox_bin"
  fi

  (cd "$initramfs_stage/bin" && \
    for tool in sh mount lsblk blkid dd sgdisk realpath; do
      ln -sf busybox "$tool"
    done)

  echo "[make_ouroboros_iso] Creating compressed initramfs image"
  rm -f "$initramfs_image"
  (cd "$initramfs_stage" && \
    find . -print0 | cpio --null -ov --format=newc | gzip -9n > "$initramfs_image")
}

prepare_iso_root() {
  echo "[make_ouroboros_iso] Preparing ISO root layout"
  rm -rf "$iso_root"
  mkdir -p "$iso_root/isolinux"

  cp "$isolinux_bin" "$iso_root/isolinux/"
  cp "$ldlinux_c32" "$iso_root/isolinux/"
}

write_isolinux_cfg() {
  cat <<'CFG' > "$iso_root/isolinux/isolinux.cfg"
PROMPT 0
TIMEOUT 20
DEFAULT sp-ouroboros
LABEL sp-ouroboros
  KERNEL /vmlinuz
  INITRD /initramfs.img
  APPEND init=/init rd.auto=0 loglevel=3 console=ttyS0,115200n8
CFG
}

build_iso() {
  echo "[make_ouroboros_iso] Copying kernel and initramfs"
  kernel_image=$(find_kernel_image)
  echo "[make_ouroboros_iso] Using kernel: $kernel_image"

  mkdir -p "$iso_root"
  if ! cp "$kernel_image" "$iso_root/vmlinuz"; then
    copy_kernel_with_sudo "$kernel_image"
  fi
  cp "$initramfs_image" "$iso_root/initramfs.img"

  write_isolinux_cfg

  echo "[make_ouroboros_iso] Building ISO $iso_path"
  rm -f "$iso_path"
  xorriso -as mkisofs \
    -r -J -joliet-long \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -isohybrid-mbr "$isohdpfx_bin" \
    -A SP_OUROBOROS -V SP_OUROBOROS \
    -o "$iso_path" "$iso_root"
}

prepare_iso_root
stage_initramfs
build_iso
