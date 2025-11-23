# Screaming Penguin — Initramfs Reconstruction

This document captures the teardown, validation, and seven-stage rebuild of the installer initramfs.

---

## Teardown and Validation

- Extracted the installer initramfs from the ISO to audit contents and permissions.
- Confirmed `/init` and `/bin/busybox` existed, but `/init` lacked executable permissions and never ran as PID1.
- Observed kernel boot reaching **"Run /init as init process"** before failing with **/init not found or not executable (error -2)**.
- Kernel exhausted fallback init paths and panicked; QEMU-CI never observed the required **"[SP-INSTALLER] init reached"** marker.
- Performed a minimal rebuild using only BusyBox and a stub init to validate QEMU behavior and confirm the permission issue.

## Seven-Stage Init Reconstruction

- **Stage 1:** Minimal init stub with hardcoded echo validated serial output.
- **Stage 2:** Rebuilt BusyBox unpack with PATH setup to reestablish shell applets.
- **Stage 3:** Reintroduced mode detection logic for installer vs. runtime selection.
- **Stage 4:** Added logging scaffold and serial pipe to retain early boot visibility.
- **Stage 5:** Added mount scaffolding and device probing placeholders.
- **Stage 6:** Reintroduced the config loader stub (no parsing yet) to restore flow.
- **Stage 7:** Restored full installer bootstrap with hooks, mode banners, and serial markers.

All seven stages passed across the CI suite and restored deterministic init execution under QEMU.

# Initramfs Design

This document describes how Screaming Penguin's initramfs is structured and how it will evolve across Phase 1 of the V1 roadmap.

## Core Responsibilities

The initramfs is responsible for:

- Bootstrapping a minimal userspace environment.
- Discovering the installer configuration partition.
- Selecting the correct target disk safely.
- Preparing filesystems and mounting them at known locations.
- Extracting and preparing the Debian rootfs for handoff.
- Emitting clear logs and error messages for every failure mode.

Later phases may add more features, but these remain the core responsibilities.

---

## Phase 1 — Utilities & Logging (P1-A Design)

P1-A defines what the initramfs *needs* before we start re-adding code.

### Required BusyBox Applets and Utilities

The initramfs environment must provide, at minimum, the following tools (via BusyBox or equivalent):

- `sh`, `ash` (shell for all init scripts)
- `mount`, `umount`
- `ls`, `cat`, `echo`, `grep`, `sed`, `awk`
- `blkid`, `lsblk` (or equivalent) for block device inspection
- `dmesg` (for low-level debugging, not required for normal operation)
- `mkdir`, `rm`, `mv`, `cp`, `ln`
- `sleep`, `sync`
- `uname`, `test`, `printf`

The guiding rule: every call made by init scripts must map to an applet that actually exists in the initramfs, and those applets should be explicitly documented here.

### Hardware and Block-Device Detection

At initramfs time, Screaming Penguin only cares about:

- The **installer medium** (the ISO/USB we booted from).
- One or more **candidate target disks** for installation.
- Optional **config partitions** (e.g., `/config` partition on the same USB or another removable device).

Design decisions for P1-A:

- Block devices are discovered via `/sys/block` and related metadata, not hard-coded device names.
- Basic classes we care about:
  - `virtio` disks in virtualized environments.
  - SATA/SCSI disks.
  - NVMe devices.
- The installer must be able to:
  - Identify which device is the boot/installer medium.
  - List remaining devices as candidates for installation.
- The exact selection logic and safety checks will be implemented in a later step, but the shape of the detection logic is defined here.

### Unified Logging Scheme

Screaming Penguin should have a single, predictable logging approach for initramfs:

- **Console output:** All major steps print tagged messages to the console:
  - `[SP-BOOT]` for core initramfs startup.
  - `[SP-CONFIG]` for config-partition discovery and parsing.
  - `[SP-DISK]` for disk enumeration and selection.
  - `[SP-FS]` for filesystem and partition operations.
  - `[SP-ROOTFS]` for rootfs extraction and chroot preparation.
- **On-disk logs:**
  - A primary log file path is reserved for P1-B implementation, for example:
    - `/run/sp/log/init.log` (in-RAM, for immediate use).
    - Later copied to `/config/logs/YYYYMMDD-HHMMSS/` once the config partition is mounted.
- **Log format:**
  - Timestamp (if available).
  - Tag (e.g., `[SP-DISK]`).
  - Message.
- **Log levels (informal for now):**
  - `INFO` — normal step progression.
  - `WARN` — recoverable or unexpected conditions.
  - `ERROR` — fatal conditions that will drop into recovery mode or abort the install.

P1-A does not require the logging implementation to exist yet; it defines where logs will live and how they should look so the implementation can be added without further design work.

### Error Surfaces

Early-boot must have clear, minimal error surfaces for:

- **Config partition failures:**
  - No config partition found.
  - Config partition found but not mountable.
  - Config file missing or malformed.
- **Disk selection failures:**
  - No eligible target disks found.
  - Ambiguous or unsafe selection scenario.
- **Filesystem/partitioning failures:**
  - Partition tools not available.
  - Partition commands fail.
  - Filesystem creation fails.
- **Rootfs extraction failures:**
  - Rootfs tarball missing.
  - Extraction fails (permissions, space, corruption).

For each of these failure classes, P1-A specifies that:

- A clear error tag must be printed (e.g., `[SP-ERROR][SP-CONFIG]`).
- The installer must either:
  - Drop into a recovery shell, **or**
  - Exit cleanly with a well-documented error code.

Implementation details (exact error codes, shell script layout) will be handled in P1-B and later steps.

---

## Future Expansion

Once P1-A is complete, P1-B will:

- Implement the logging helpers and error-reporting functions described here.
- Wire all init scripts to use these helpers consistently.
- Ensure CI tests can assert on visible tags (e.g., `[SP-INSTALLER] init reached`) to verify correct initramfs behavior.
