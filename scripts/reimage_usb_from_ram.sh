#!/bin/sh
#
# reimage_usb_from_ram.sh
#
# Orchestrates detection of the boot USB and re-imaging it with a prebuilt .img.
# ALL destructive commands are currently COMMENTED OUT as placeholders.
#

set -eu

IMAGE_PATH="${OUROBOROS_IMAGE_PATH:-/image/sp-runtime.img}"

err() {
    echo "[ouroboros][reimage] ERROR: $*" >&2
    exit 1
}

pause_for_confirmation() {
    echo "==================================================================="
    echo "  Screaming Penguin — Ouroboros Installer (DESTRUCTIVE OPERATION)"
    echo
    echo "  This process will:"
    echo "    - Wipe the partition table on the detected boot USB device"
    echo "    - Write the image at: ${IMAGE_PATH}"
    echo "    - Potentially destroy ALL data on that USB device"
    echo
    echo "  NOTE: At this stage, the destructive commands are DISABLED and"
    echo "        present only as commented placeholders."
    echo "==================================================================="
    printf "Type 'I UNDERSTAND' to continue, or anything else to abort: "
    read -r reply || reply=""
    if [ "$reply" != "I UNDERSTAND" ]; then
        err "user did not confirm operation"
    fi
}

main() {
    if [ ! -f "$IMAGE_PATH" ]; then
        err "image file not found at ${IMAGE_PATH}"
    fi

    # Run sanity checks
    /scripts/sanity_checks.sh

    # Detect boot USB device
    boot_dev=$(/scripts/detect_boot_device.sh)
    echo "[ouroboros][reimage] boot device detected as: ${boot_dev}"

    pause_for_confirmation

    echo "[ouroboros][reimage] (DRY MODE) Would now wipe and re-image '${boot_dev}' with '${IMAGE_PATH}'."
    echo "[ouroboros][reimage] Destructive commands are commented out pending hardware validation."

    # Example of the real commands we intend to use later:
    #
    #   sgdisk --zap-all "${boot_dev}"
    #   dd if="${IMAGE_PATH}" of="${boot_dev}" bs=4M status=progress conv=fsync
    #   sync
    #
    # These remain commented until the image and detection logic are fully validated.

    echo "[ouroboros][reimage] completed in dry mode."
}

main "$@"
