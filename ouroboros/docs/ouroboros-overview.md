# Ouroboros Overview

## Concept

The Ouroboros ISO boot path copies itself into RAM, reimages the USB boot media from a pre-built image, and reboots to the refreshed media so the same stick can become a fresh Screaming Penguin runtime. Keeping Ouroboros assets under `ouroboros/` keeps the mainline repo clean while leaving a clear home for ISO-specific scripts, docs, and tooling.

## Core requirements

1. **RAM-resident runtime**
   * The live environment must be able to run with the boot medium unmounted so that the USB device can be safely wiped and re-imaged.
2. **Deterministic boot device detection**
   * Prefer a known volume label (e.g., `SP_OUROBOROS` or `OUROBOROS_BOOT`) via `/dev/disk/by-label/`.
   * Fall back to inspecting live-media mountpoints such as `/run/live/medium` or `/run/initramfs/live`.
3. **Strict safety**
   * Only the detected boot device is eligible for wiping.
   * Abort whenever detection is ambiguous or tools are missing.
   * Log clearly and drop to a shell rather than silently continuing.
4. **Prebuilt `.img` consumption**
   * The ISO packages a ready-to-flash runtime image (location TBD) and writes it to the boot device after all safety gates pass.

## Script responsibilities

- `ouroboros/scripts/detect_boot_device.sh` — labels the desired device via `blkid`, exits non-zero on zero or ambiguous matches, and prints the canonical block path for downstream scripts.
- `ouroboros/scripts/sanity_checks.sh` — ensures the expected tooling (`blkid`, `lsblk`, etc.) is available and announces whether the run remains a dry run.
- `ouroboros/scripts/assert_usb_only_environment.sh` — enforces a policy that only USB-backed block devices/symlinks exist in `/dev` and `/dev/disk/*`, aborting if any non-USB nodes are present.
- `ouroboros/scripts/reimage_usb_from_ram.sh` — orchestrates the dry-run flow, calls the assertion helper twice (before detection and to verify the final target), prompts for the destructive confirmation string, and leaves example `sgdisk`/`dd` commands commented out until fully validated.

## Initramfs behavior

`ouroboros/initramfs_root/init` currently:

1. Mounts `/proc`, `/sys`, and `/dev` so the basic utilities are available.
2. Calls `ouroboros/scripts/assert_usb_only_environment.sh` to lock down `/dev` entries before anything else runs.
3. Invokes `ouroboros/scripts/reimage_usb_from_ram.sh` and drops to an emergency shell on any failure.
4. On success it syncs and reboots; otherwise it stays interactive so operators can inspect the environment.

## Safety posture

- Default behavior is dry-run, logging each step without executing destructive commands.
- Real disc writes only run when `OUROBOROS_ENABLE_DESTRUCTIVE=1` **and** the operator types `I_ACKNOWLEDGE_OUROBOROS_DESTRUCTION` exactly.
- Boot device detection relies on labels and fails fast rather than guessing by `/dev/sdX` ordering or heuristics.
- The initramfs asserts the USB-only policy and drops to a shell on any unexpected device, so it never wakes up a destructive flow without verification.

## Future work hints

- `ouroboros/tools/make_ouroboros_iso.sh` will grow into a full ISO builder that stages the initramfs, `ouroboros/scripts/` assets, and the final ISO in `ouroboros/dist/`.
- `ouroboros/docs/qemu-test.md` documents how to smoke-test the stub ISO once the builder lands; this can remain the verification path for future iterations.
- Additional policy scripts can guard `/dev` before handing control to `reimage_usb_from_ram.sh` so any non-USB artifacts are reported and cause early aborts.
