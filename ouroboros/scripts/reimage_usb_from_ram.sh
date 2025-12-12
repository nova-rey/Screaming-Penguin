#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/sanity_checks.sh"

boot_device="$("$script_dir/detect_boot_device.sh")"

cat <<-MSG
[reimage_usb_from_ram] Detected boot device: $boot_device
[reimage_usb_from_ram] Default behavior is dry-run. No write operations will happen unless destruction is explicitly allowed.
MSG

if [[ "${OUROBOROS_ENABLE_DESTRUCTIVE:-0}" != "1" ]]; then
  echo "[reimage_usb_from_ram] OUROBOROS_ENABLE_DESTRUCTIVE is not set to 1; skipping destructive steps." >&2
  exit 0
fi

if [[ -t 0 ]]; then
  read -rp "Type the confirmation string 'I_ACKNOWLEDGE_OUROBOROS_DESTRUCTION' to proceed: " confirmation
else
  echo "[reimage_usb_from_ram] ERROR: No TTY available for confirmation prompt." >&2
  exit 1
fi

if [[ "$confirmation" != "I_ACKNOWLEDGE_OUROBOROS_DESTRUCTION" ]]; then
  echo "[reimage_usb_from_ram] ERROR: Confirmation string did not match; aborting." >&2
  exit 1
fi

cat <<'END'
[reimage_usb_from_ram] Destructive mode acknowledged. (Placeholder - no real writes yet.)
# Example destructive sequence for future implementation:
# sgdisk --zap-all "$boot_device"
# dd if=/path/to/prebuilt.img of="$boot_device" bs=4M status=progress conv=fsync
END

