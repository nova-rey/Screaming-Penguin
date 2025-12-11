# Screaming Penguin — Ouroboros Installer ISO

This branch contains the **Ouroboros installer ISO** variant of Screaming Penguin.

The design goal is:

> Boot from an ISO → load fully into RAM → identify the USB device we booted from → safely wipe and re-image that same USB with a prebuilt `.img` → reboot, without ever touching any other disks.

## Status

- This branch is **scaffolding only**.
- All disk-wiping and imaging logic is present as **commented, non-executing placeholders**.
- The initramfs and ISO builder are not wired up yet.

## High-Level Flow (Intended)

1. Boot the ISO (labelled something like `SP_OUROBOROS`).
2. Kernel + initramfs load into RAM.
3. `init` inside the ramdisk:
   - Runs basic sanity checks to ensure:
     - We are running as PID 1.
     - We are running from RAM, not directly from a block device.
   - Calls a script to detect the **boot USB device** deterministically.
   - Calls a script that:
     - Confirms the user intends to re-image the USB.
     - Wipes the USB’s partition table.
     - Writes a prebuilt `.img` onto the USB.
4. System syncs and reboots. On next boot, the USB behaves as the new Screaming Penguin installer/runtime.

## Safety Guarantees (Design-Level)

- Only the device we originally booted from should ever be targeted.
- No assumptions are made about `/dev/sda`, `/dev/sdb`, etc.
- We rely on:
  - Stable volume label (e.g., `SP_OUROBOROS`), or
  - The mountpoint used by the live/ISO environment.

## Structure

- `docs/`
  - `ouroboros-overview.md` — deeper design notes.
- `scripts/`
  - `detect_boot_device.sh` — find the boot USB.
  - `sanity_checks.sh` — environment and safety validation.
  - `reimage_usb_from_ram.sh` — orchestrates wipe + image write (currently stubbed).
- `initramfs_root/`
  - `init` — init script for the RAM-based environment.
- `tools/`
  - `make_ouroboros_iso.sh` — ISO build script (scaffold).

## WARNING

At this stage, **no script in this branch should actually wipe or re-image a device** without explicit enabling. All destructive commands must stay commented out until the image and flow are fully validated.
