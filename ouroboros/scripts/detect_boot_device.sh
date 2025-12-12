#!/usr/bin/env bash
set -euo pipefail

label_arg="${1:-""}"
default_label="${OUROBOROS_BOOT_LABEL:-OUROBOROS_BOOT}"

if [[ -n "$label_arg" ]]; then
  target_label="$label_arg"
elif [[ -n "$default_label" ]]; then
  target_label="$default_label"
else
  echo "[detect_boot_device] ERROR: No boot label provided via argument or OUROBOROS_BOOT_LABEL." >&2
  exit 1
fi

if ! command -v blkid >/dev/null 2>&1; then
  echo "[detect_boot_device] ERROR: blkid is required but not found." >&2
  exit 1
fi

mapfile -t matches < <(blkid -o device -t "LABEL=${target_label}")
count=${#matches[@]}
case "$count" in
  0)
    echo "[detect_boot_device] ERROR: no block device was found with label '${target_label}'." >&2
    exit 2
    ;;
  1)
    device_path="${matches[0]}"
    ;;
  *)
    echo "[detect_boot_device] ERROR: multiple devices matched label '${target_label}'; refusing to guess." >&2
    for dev in "${matches[@]}"; do
      echo "  - $dev" >&2
    done
    exit 3
    ;;
esac

printf '%s
' "$device_path"
