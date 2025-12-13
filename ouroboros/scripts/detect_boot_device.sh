#!/bin/sh
set -eu

label_arg="${1:-}"
default_label="${OUROBOROS_BOOT_LABEL:-OUROBOROS_BOOT}"

target_label=""
if [ -n "$label_arg" ]; then
  target_label="$label_arg"
elif [ -n "$default_label" ]; then
  target_label="$default_label"
else
  echo "[detect_boot_device] ERROR: No boot label provided via argument or OUROBOROS_BOOT_LABEL." >&2
  exit 1
fi

if ! command -v blkid >/dev/null 2>&1; then
  echo "[detect_boot_device] ERROR: blkid is required but not found." >&2
  exit 1
fi

matches=$(blkid -o device -t "LABEL=${target_label}" 2>/dev/null || true)
match_count=0
selected_device=""
match_list=""
for dev in $matches; do
  if [ -z "$dev" ]; then
    continue
  fi
  match_count=$((match_count + 1))
  if [ "$match_count" -eq 1 ]; then
    selected_device="$dev"
  fi
  match_list="$match_list $dev"
done

if [ "$match_count" -eq 0 ]; then
  echo "[detect_boot_device] ERROR: no block device was found with label '${target_label}'." >&2
  exit 2
fi

if [ "$match_count" -gt 1 ]; then
  echo "[detect_boot_device] ERROR: multiple devices matched label '${target_label}'; refusing to guess." >&2
  for dev in $match_list; do
    if [ -n "$dev" ]; then
      echo "  - $dev" >&2
    fi
done
  exit 3
fi

printf '%s\n' "$selected_device"
