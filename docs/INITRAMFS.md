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

### BusyBox Device Population Model

The installer initramfs intentionally avoids `udev`/`systemd` and runs as a tiny BusyBox-only environment. To keep block-device nodes available while the kernel is still probing hardware, `/init` now runs `sp_bootstrap_dev_nodes` early in `sp_bootstrap`:

- Mount `devtmpfs` (or a tmpfs fallback) on `/dev` (best-effort).
- Run `mdev -s` so BusyBox reads `/sys/block` and synthesizes `/dev/sdX*`, `/dev/mmcblkNp*`, and `/dev/nvmeNp*p*` nodes before config discovery.
- Ensure `/dev/console` exists (mknod if necessary) so rescue shells can bind standard I/O.

Because `/dev/disk/by-label` is not guaranteed inside this environment, config discovery now works directly from `/sys/block` and raw `/dev` names: it enumerates slot-specific heuristics (e.g., `sdX1`, `mmcblkNp1`, `nvme0n1p1`) and tries each candidate without pulling in util-linux tools. This approach only needs BusyBox (`mount`, `cat`, `echo`, `mdev`, `mknod`, `sleep`, etc.) and the `/dev` nodes that `mdev -s` creates.

### Rescue Mode Safety

Rescue mode now keeps PID 1 alive even when the shell exits:

- Diagnostics (sysfs, `/proc/partitions`, label listings) still run before entering the shell.
- Standard I/O is always bound to `/dev/console` (or the test override) so recovery shells remain visible.
- The shell runs inside a `while true; do ...; done` loop that logs each exit (`note=shell-exited`) and delays before relaunching, guaranteeing a live PID 1 and preventing kernel panics.

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

### Phase 1 — Utilities & Logging Implementation (P1-B)

P1-B wires the documented logging model into the real initramfs:

- A helper script (`initramfs/lib/log.sh`) provides:
  - `sp_log_init` to prepare `/run/sp/log` and the primary `init.log` file.
  - `sp_log_info`, `sp_log_warn`, and `sp_log_error` for tagged, leveled messages.
  - `sp_die` for fatal errors that log and optionally drop to a recovery shell.

- The main `init` script:
  - Sources `log.sh` during early boot.
  - Emits high-level tags:
    - `[SP-BOOT]` for initramfs startup and shutdown messages.
    - `[SP-INSTALLER]` when the installer entry point is reached.
  - Exits cleanly after reaching the current installer stub, preserving existing CI behavior.

The helpers are designed to be best-effort:
- Logging to the console is mandatory.
- Logging to `/run/sp/log/init.log` is opportunistic and must not cause failures if the path is unavailable.

Future phases will redirect logs to the config partition (e.g., `/config/logs/YYYYMMDD-HHMMSS/`) once it is mounted, but P1-B is limited to in-RAM logging and console output.

### Phase 1 — Config Stub Wiring (P1-C)

P1-C introduces a non-fatal config handling stub inside the initramfs:

- A helper script (`initramfs/lib/config.sh`) defines:
  - `sp_config_probe`, which:
    - Assumes that `/config` may already be mounted by the time init runs.
    - Looks for `/config/installer-config.yml`.
    - Logs what it finds using the `[SP-CONFIG]` tag.
    - Best-effort copies the config file into `/run/sp/config/installer-config.yml` for later use.

- The main `init` script:
  - Sources `config.sh` if present.
  - Calls `sp_config_probe` if it exists.
  - Treats all config-related issues as **non-fatal** in this phase.

The goal of P1-C is to shape the config handling surface and get useful logging without changing CI expectations. In other words, QEMU boots and exits exactly as before, but we now have structured `[SP-CONFIG]` log lines when a config partition is present.

Later phases (Phase 2 and beyond) will be responsible for:
- Actively discovering and mounting the config partition.
- Validating the structure of `installer-config.yml`.
- Enforcing config presence for real installs.
