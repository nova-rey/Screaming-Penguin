#!/bin/sh
set -eu

log() {
  printf '[assert_usb_only_environment] %s\n' "$*" >&2
}

error_exit() {
  log "ERROR: $*"
  exit 1
}

resolve_sysfs_block() {
  readlink -f "/sys/class/block/$1" 2>/dev/null || true
}

resolve_physical_sysfs_block() {
  path="$(resolve_sysfs_block "$1")"
  if [ -z "$path" ]; then
    return 1
  fi
  if is_virtual_block_device "$path"; then
    return 1
  fi
  printf '%s' "$path"
}

is_virtual_block_device() {
  case "$1" in
    */virtual/*) return 0 ;;
  esac
  return 1
}

has_usb_ancestry() {
  current="$1"
  while [ -n "$current" ] && [ "$current" != "/" ]; do
    if [ -f "$current/uevent" ]; then
      if grep -Eq '^(ID_BUS|BUS)=usb$' "$current/uevent" 2>/dev/null; then
        return 0
      fi
    fi
    case "$current" in
      */usb[0-9]*/* | */usb[0-9]* )
        return 0
        ;;
    esac
    parent="$(dirname "$current")"
    if [ "$parent" = "$current" ]; then
      break
    fi
    current="$parent"
  done
  return 1
}

is_usb_device_name() {
  device="$1"
  if [ -z "$device" ]; then
    return 1
  fi
  if ! sysfs_path="$(resolve_physical_sysfs_block "$device")"; then
    return 1
  fi
  if has_usb_ancestry "$sysfs_path"; then
    return 0
  fi
  return 1
}

check_device_is_usb() {
  device_path="$1"
  device_name="${device_path##*/}"
  if is_usb_device_name "$device_name"; then
    return 0
  fi
  error_exit "Device '$device_path' is not USB-backed"
}

check_all_devices() {
  failure=0
  for sysblk in /sys/class/block/*; do
    [ -e "$sysblk" ] || continue
    name="$(basename "$sysblk")"
    if ! sysfs_path="$(resolve_physical_sysfs_block "$name")"; then
      continue
    fi
    if has_usb_ancestry "$sysfs_path"; then
      continue
    fi
    device_node="/dev/$name"
    if [ -e "$device_node" ]; then
      log "ERROR: Non-USB block device node detected: $device_node"
      failure=1
    fi
  done

  for disk_dir in /dev/disk/*; do
    [ -d "$disk_dir" ] || continue
    for link in "$disk_dir"/*; do
      [ -L "$link" ] || continue
      target="$(readlink -f "$link" 2>/dev/null || true)"
      [ -z "$target" ] && continue
      target_name="${target##*/}"
      if ! is_usb_device_name "$target_name"; then
        log "ERROR: Non-USB symlink detected: $link -> $target"
        failure=1
      fi
    done
  done

  if [ "$failure" -ne 0 ]; then
    error_exit "USB-only policy violation detected, aborting."
  fi
}

usage() {
  printf 'usage: %s [--check-device <dev>] [--mdev-hook]\n' "$0" >&2
}

main() {
  case "$1" in
    --check-device)
      if [ "$#" -ne 2 ]; then
        usage
        exit 1
      fi
      check_device_is_usb "$2"
      ;;
    --mdev-hook)
      if [ -n "${DEVNAME:-}" ]; then
        check_device_is_usb "/dev/$DEVNAME"
      else
        log 'INFO: mdev hook invoked without DEVNAME, skipping USB check.'
      fi
      ;;
    ''|*)
      check_all_devices
      ;;
  esac
}

if [ "$#" -eq 0 ]; then
  main
else
  main "$@"
fi
