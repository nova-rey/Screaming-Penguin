# Phase 2 Checkpoint 1 Analysis

## Deep scan
- `ouroboros/initramfs_root/init` currently mounts `/proc`, `/sys`, and `/dev` (devtmpfs) and immediately invokes `ouroboros/scripts/reimage_usb_from_ram.sh`, so we already have a tight choke point before any detection logic runs.
- The `ouroboros/scripts/` helpers (`sanity_checks.sh`, `detect_boot_device.sh`, `reimage_usb_from_ram.sh`) are all POSIX `sh` and implement dry-run safeguards but have no USB-only checks.
- There is no existing policy namespace under `ouroboros/`; only `scripts/`, `tools/`, `build/`, `dist/`, and the stub ISO builder exist, but the BusyBox binary is staged under `ouroboros/initramfs_root/bin/busybox` so we can rely on the embedded initramfs payload.
- The upstream repo currently lacks device filtering: `/dev` is populated by devtmpfs, and `detect_boot_device.sh` simply chooses any block device by label without verifying that it is USB-backed.

## Human brief validation
- Preventing writes and avoiding `/dev/sdX` heuristics already align with current dry-run safeguards, so we can layer USB-only checks on top without touching destructive flows.
- We have access to `/sys/class/block` and the BusyBox toolchain in the initramfs, so verifying `ID_BUS=usb` and traversing sysfs ancestry is feasible within POSIX `sh`.
- The environment exposes BusyBox’s `mdev` binary, so we can anchor a device node policy around the existing initramfs tooling even if a full udev tree is not present yet.
- The new policy must sit under `ouroboros/`, which is satisfied by adding policy scripts, the `usb-only.rules` file, and the assertion helper there.

## Files requiring creation/modification
- `ouroboros/policy/usb-only.rules` (new full-file rule set that describes how to enforce USB-only block device exposure via the available device manager). 
- `ouroboros/scripts/assert_usb_only_environment.sh` (new paranoia helper that aborts if any non-USB block device node is exposed).
- `ouroboros/scripts/reimage_usb_from_ram.sh` (add USB allowlisting and ensure `assert_usb_only_environment.sh` is invoked/connected to the detection logic).
- `ouroboros/scripts/` additional helper(s) as needed (e.g., a script to sanitize `/dev` entries, parse sysfs, and call the policy rules).
- `ouroboros/initramfs_root/init` (call the USB-only policy enforcement early, before the reimage script, to keep non-USB targets from appearing).

## Implementation plan
1. Create a policy directory and author `ouroboros/policy/usb-only.rules` that maps the mdev/udev-style policy to a helper script so we can describe allowed USB-backed block device nodes in one place.
2. Add `ouroboros/scripts/assert_usb_only_environment.sh` (POSIX sh) that:
   * Enumerates `/sys/class/block` devices, resolves their sysfs paths, and determines USB ancestry via `ID_BUS` or `/usbX/` segments.
   * Uses that logic to remove or report any `/dev` entries that are not USB-backed.
   * Exposes helper functions that other scripts (reimage, init) can reuse for allowlisting a candidate.
3. Update `ouroboros/scripts/reimage_usb_from_ram.sh` to incorporate the USB allowlist: run the assertion helper early, verify that the detected boot device is USB-backed, and abort loudly if not.
4. Add an enforcement invocation around the existing init flow (likely a new helper script) so `ouroboros/initramfs_root/init` sanitizes `/dev` before calling the reimage script; this ensures non-USB devices never reach Phase 3.
5. Ensure all new scripts are executable and use `#!/bin/sh` shebangs; document the policy in the analysis file (append verification notes after tests).

## Constraints and next steps
- We must avoid real disk writes and keep destructive behavior gated by `OUROBOROS_ENABLE_DESTRUCTIVE`; all new logic is read-only.
- The policy needs to abort loudly if the environment cannot prove USB ancestry for a candidate, so the helper script will exit non-zero with a clear message in such cases.
- After Block B we will call `make iso` (or the available ISO builder) and follow the requested QEMU verification; results will be appended to this file during Block C.
- If the environment lacks a usable device manager for policy enforcement, we will document that fact as part of the abort condition (per the brief).

## Block C verification
- Running `bash tools/make_ouroboros_iso.sh` does not yet produce an ISO; the script simply prints the intended workflow and exits early, so no `sp-ouroboros-installer.iso` is created for this checkpoint.
- Because the builder is a scaffold and no ISO is emitted, we cannot boot the image under QEMU or exercise the requested non-USB abort cases; those steps must wait for a real ISO build later in the project.
