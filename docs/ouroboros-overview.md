# Ouroboros ISO — Design Overview

The Ouroboros variant of Screaming Penguin is a **self-consuming installer**:

- It boots from a USB stick carrying an ISO.
- It runs entirely from RAM.
- It then rewrites the **same USB stick** with a prebuilt `.img`.
- It does not touch any other block devices.

## Core Requirements

1. **RAM-Resident Runtime**

   The live environment must be able to run with the boot medium unmounted so that the USB device can be safely wiped and re-imaged.

2. **Deterministic Boot Device Detection**

   We cannot guess that `/dev/sda` or `/dev/sdb` is the USB. Instead, we will:

   - Prefer a known volume label (e.g., `SP_OUROBOROS`) via `/dev/disk/by-label/`.
   - Fallback to inspecting live-media mountpoints such as `/run/live/medium` (Debian live) or similar.

3. **Strict Safety**

   - Only the detected boot device is eligible for wiping.
   - If detection is ambiguous or fails → abort with a clear error.
   - No attempt is made to auto-recover by guessing.

4. **Prebuilt `.img` Consumption**

   The ISO includes a prebuilt `.img` (location TBD, for example `/image/sp-runtime.img`) which will be written to the USB.

## Script Responsibilities

- `scripts/detect_boot_device.sh`
  Encapsulates all logic for reliably identifying the boot USB device. It must:

  - Print the device path (e.g., `/dev/sdX`) on success.
  - Exit non-zero with an error message on failure.

- `scripts/sanity_checks.sh`
  Validates that:

  - We are running as root.
  - We are running in the intended live/ramdisk context (best-effort checks).
  - Required tools (`dd`, `lsblk`, `sgdisk`, etc.) are present.

- `scripts/reimage_usb_from_ram.sh`
  Orchestrates:

  - Calling `sanity_checks.sh`.
  - Calling `detect_boot_device.sh`.
  - Printing what will happen and requiring explicit confirmation.
  - Wiping and re-imaging the USB (in future; currently commented out).

## Initramfs Behavior

The `initramfs_root/init` script will:

1. Perform minimal early boot setup (mount `/proc`, `/sys`, `/dev`).
2. Optionally pivot into a tiny RAM-based root (later).
3. Invoke `reimage_usb_from_ram.sh`.
4. On success, sync and reboot.
5. On failure, drop to an emergency shell.

For now, `init` will only perform basic setup and print placeholder messages.

## Future Work

- Integrate a real initramfs build pipeline.
- Add a basic TUI or confirmation prompt before destructive steps.
- Wire `tools/make_ouroboros_iso.sh` into the Screaming Penguin build system.
- Add hardware test notes and expected device matrices once validated on bare metal.
