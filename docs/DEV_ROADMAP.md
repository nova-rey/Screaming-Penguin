# Screaming Penguin — Development Roadmap

This roadmap defines a straight, narrow path to Screaming Penguin **v1.0.0** — a deterministic, config-driven Debian installer that boots from a USB image, wipes a target disk, installs a prebuilt root filesystem, and produces a fully bootable system.

The roadmap is intentionally conservative. Each step builds toward a single, clear identity:

> **Screaming Penguin v1** is a headless-friendly, Debian-only, full-disk-wipe installer driven by a YAML config file and a prebuilt rootfs tarball.

---

## 1. v1 Scope Summary

v1 must be able to:

- Boot from a USB image on **x86_64** hardware (BIOS and UEFI).
- Mount a writable `/config` partition from the installer USB.
- Read and validate `/config/installer-config.yml`.
- Refuse to run if:
  - The target disk is missing or not found.
  - The target disk is the installer USB itself.
  - The rootfs tarball is missing or unreadable.
  - SSH is disabled and no password is configured (no login path).
- Wipe the target disk and create a **GPT** layout with:
  - An EFI/BIOS system partition (FAT32).
  - A single **ext4** root partition.
- Extract a prebuilt **Debian minimal rootfs** tarball onto the root partition.
- chroot into the new system and configure:
  - Hostname.
  - Timezone.
  - Locale.
  - User + password (hashed).
  - SSH daemon and authorized keys (if enabled).
  - GRUB bootloader for BIOS and UEFI.
- Write installer logs back to `/config/logs/`.
- Emit a minimal completion cue (optional audio).
- Shut down cleanly.

Out of scope for v1:

- Non-Debian distros.
- Non-ext4 root filesystems.
- LVM, btrfs, RAID, encryption.
- Network-based installation or rootfs download.
- Multi-OS layouts or non-destructive installs.
- Text or graphical installer UI beyond minimal prompts.

---

## 2. Milestones to v1

Each milestone is intended to be small, reviewable, and testable on its own. v1 is achieved when all milestones are complete and the acceptance criteria in `docs/V1_CHECKLIST.md` are satisfied.

### Milestone 1 — Repo Foundation & Documentation

**Goal:** Establish a clear, documented base for development.

**Tasks:**

- Create and maintain:
  - `docs/DESIGN_v0.md` — architecture and behavior description.
  - `docs/DEV_ROADMAP.md` — this roadmap.
  - `docs/DEV_PHILOSOPHY.md` — development principles.
  - `docs/SP_BIBLE.md` — additive history log.
  - `docs/NOVA_AGENT_ENTRYPOINT.md` — agent standing orders.
  - `docs/CONFIG_SCHEMA.md` — config schema outline.
  - `docs/V1_CHECKLIST.md` — v1 acceptance criteria.
- Create initial repository structure:
  - `docs/`, `installer/`, `installer/initramfs/`, `installer/runtime/`, `installer/runtime/lib/`,
    `tools/`, `rootfs/`, `tests/`, `tests/integration/`, `tests/harness/`, `ci/`.
- Provide a sample config:
  - `config/installer-config.example.yml`.

**Done When:**

- All documents above exist and reflect the current design.
- The repository structure is present and aligned with `DESIGN_v0.md`.

---

### Milestone 2 — Initramfs & Runtime Skeleton

**Goal:** Establish the structural foundation of the installer’s boot environment and runtime orchestration without implementing destructive or state-changing operations.

**Tasks:**

- Create the initramfs entrypoint and hook structure:
  - `installer/initramfs/init`
  - `installer/initramfs/hooks/` (mount-config, audio-init, runtime-launch placeholders)
- Create the Screaming Penguin runtime skeleton:
  - `installer/runtime/sp-installer`
  - `installer/runtime/sp-disk-plan.sh`
  - `installer/runtime/sp-disk-apply.sh`
  - `installer/runtime/sp-rootfs-apply.sh`
  - `installer/runtime/sp-chroot-setup.sh`
  - `installer/runtime/sp-audio.sh`
  - `installer/runtime/lib/logging.sh`
  - `installer/runtime/lib/config_validation.sh`
  - `installer/runtime/lib/safety_checks.sh`
- Implement a placeholder state machine:
  - BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL → CONFIRM_INSTALL → EXECUTE_INSTALL → FINISH
  - Each state logs “Entered <STATE>” and performs no real logic.
- Ensure all scripts are non-destructive and contain only structure, TODO markers, and logging.
- Ensure the installer skeleton boots in QEMU and transitions through states without error before aborting safely.

**Done When:**

- The image boots into the initramfs.
- The runtime launches and logs each state transition.
- No destructive operations exist in any script.
- QEMU demonstrates a full dry-run path through the installer lifecycle.

---

### Milestone 3 — ISO / USB Image Build Pipeline

**Goal:** Produce a bootable, two-partition disk image that contains the Screaming Penguin initramfs environment and a writable `/config` partition, without performing any installation on target disks. This milestone delivers the installer **image**, not the installation logic.

**Target Artifact:**

- A raw disk image, e.g.:
  - `dist/screaming-penguin.img`

**Required Layout:**

- GPT partition table on the image.
- Partition 1 (p1):
  - Purpose: bootable read-only environment.
  - Contents: Linux kernel, initramfs, bootloader (GRUB or equivalent), runtime scripts.
  - Presentation: ISO9660 and/or squashfs as appropriate for the bootloader.
- Partition 2 (p2):
  - Filesystem: FAT32.
  - Label: `SP_CONFIG` (or equivalent).
  - Mount point at runtime: `/config`.
  - Purpose: configuration, rootfs tarball, installer logs.

**Tasks:**

- Define and document the image build process in `docs/ISO_BUILD.md`, including:
  - Host dependencies (e.g., `parted`, `sgdisk`, `mkfs.vfat`, `xorriso` or `grub-mkrescue`).
  - Conceptual steps for:
    - Creating a raw image file.
    - Partitioning the image with GPT into p1 and p2.
    - Populating p1 with kernel, initramfs, and bootloader configuration.
    - Formatting p2 as FAT32 and preparing it for `/config`.
  - Expected outputs and locations, including `dist/screaming-penguin.img`.
- Reserve the script entrypoint:
  - `tools/make_installer_iso.sh`
  - This script will, in later checkpoints, implement the actual build logic.
- Ensure the roadmap clearly states:
  - Milestone 3 operates only on **image files**, not on real block devices (e.g., `/dev/sdX`, `/dev/nvme0n1`).
  - No installation to target disks is performed in this milestone.
  - The image must be suitable for:
    - Writing to a USB device via `dd`/`pv` on a host system.
    - Booting under both BIOS and UEFI firmware via QEMU.

**Done When:**

- `docs/ISO_BUILD.md` describes the intended build pipeline and artifact layout.
- `docs/DEV_ROADMAP.md` clearly reflects that Milestone 3:
  - Produces a bootable installer image.
  - Does not yet implement any target-disk installation logic.
- The entrypoint `tools/make_installer_iso.sh` is defined in documentation as the canonical image builder (implementation will follow in a later milestone).

---

## Phase 4 — Debian Rootfs Builder (v1)

**Goal:**  
Provide a reproducible, scripted method to build the Debian root filesystem tarball expected by the Screaming Penguin installer. This rootfs tarball is later extracted onto the target disk during installation.

**Default suite:** Debian Bookworm (stable)  
**Architecture:** amd64 (x86_64)  
**Scope:** Build only — no installer logic changes.

---

### Deliverables

1. **Rootfs Builder Script (`tools/build_debian_rootfs.sh`)**  
   - Uses `debootstrap` or `mmdebstrap` to produce a minimal Debian Bookworm filesystem under `build/rootfs/`.
   - Performs minimal sanitization (lock root password, generic hostname).
   - Archives the result into:  
     `dist/debian-rootfs-bookworm-amd64.tar.gz`

2. **Makefile Target**  
   - `make rootfs` calls the builder script.

3. **Documentation**  
   - `docs/ROOTFS_BUILD.md` describing usage, requirements, and assumptions.
   - Updated `docs/CONFIG_SCHEMA.md` clarifying how `rootfs.path` maps to the generated tarball.

4. **Safety Requirements**  
   - Builder must operate *only* under `build/` and `dist/`.
   - Builder must never modify the host system or touch real block devices.
   - Any `chroot` must occur only inside the working rootfs directory.

---

### Not in Scope (Phase 4)

- Bootloader installation  
- Target disk partitioning  
- Installer state-machine changes  
- User/SSH/timezone/locale config  
- CI execution of full rootfs builds (optional for later phases)  

Phase 4 produces the rootfs artifact; Phase 5 will consume it.

---

## Phase 5 — Installer Runtime (v1 Core)

**Goal:**  
Implement the complete Screaming Penguin installer runtime as a deterministic, safe, state-driven system capable of installing a Debian Bookworm (amd64) root filesystem onto a target disk using a configuration file located on the USB `/config` partition.

---

### Functional Overview

Phase 5 converts the existing ISO/runtime scaffolding into a full Linux installer with the following capabilities:

1. Boot into a minimal initramfs environment.
2. Read and parse `/config/installer-config.yml`.
3. Validate required configuration fields (disk, rootfs path, user/SSH requirements, hostname, locale, timezone).
4. Enforce safety checks (target disk must exist, must not be the USB itself, rootfs must be present, password/SSH rules).
5. Execute the state machine:
   - **BOOT_INIT:** Mount `/config`, initialize logging, optional audio.
   - **LOAD_CONFIG:** Parse YAML and validate schema.
   - **PLAN_INSTALL:** Verify target disk, plan GPT layout (EFI + ext4).
   - **CONFIRM_INSTALL:** Require ERASE confirmation if configured.
   - **EXECUTE_INSTALL:** Partition target disk, create filesystems, extract rootfs, chroot to configure system, install GRUB.
   - **FINISH:** Write logs and announce completion.
6. Perform complete system configuration in chroot:
   - hostname
   - locale/timezone
   - user creation and sudo permissions
   - root password or SSH keys
   - GRUB installation (UEFI + BIOS)
7. Write final logs to `/config/logs/<timestamp>.log`.

---

### Deliverables

- `docs/INSTALLER_RUNTIME.md` describing the state machine, chroot behavior, safety model, and execution flow.
- Additions to `docs/CONFIG_SCHEMA.md` documenting exact installer requirements for Phase 5.
- Placeholder file: `installer/` directory with non-executable placeholders for future runtime scripts.
- Bible entry marking the Phase 5 kickoff.

---

### Safety Requirements (Phase 5)

- Installer must refuse to run if:
  - target disk is missing or equals the USB device.
  - rootfs tarball is missing or unreadable.
  - configuration fails schema validation.
  - password is missing **and** SSH is disabled.
  - ERASE confirmation is required but not supplied.

- Installer must never:
  - Touch arbitrary block devices.
  - Modify the host (initramfs) environment.
  - Perform `chroot` outside the extracted rootfs.
  - Proceed on partial failures.

---

### Out of Scope for Phase 5

- Networking configuration beyond enabling SSH.
- LVM, btrfs, RAID, encryption, ZFS, or multi-disk layouts.
- Package customization or additional repositories.
- UI menus or interactive install flows.
- Automated updates or rollback behavior.
- Non-Debian distributions.

---

### Definition of Done

Phase 5 is complete when:
- Installer boots and reaches BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL.
- Executes full installation on a QEMU disk using a valid config.
- Resulting system boots into Debian Bookworm with correct hostname, user, locale, SSH, GRUB.
- Logs are written reliably to `/config/logs/`.
- CI smoke test reaches at least LOAD_CONFIG.
- Documentation and schema updates reflect runtime truth.

---

### Milestone 6 — Test Harness & v1 Acceptance Tests

**Goal:** Provide a minimal but meaningful QEMU-based test harness and clearly defined v1 acceptance scenarios.

**Tasks:**

- Add scripts under `tests/harness/` to:
  - Boot the Screaming Penguin image in QEMU with a virtual target disk.
  - Capture logs and exit status.
- Define test scenarios in `docs/TESTING_v0.md` (or update to `docs/TESTING_v1.md` if preferred):
  - Missing config file → installer aborts, logs error.
  - Target disk not found → installer aborts, logs error.
  - USB device chosen as target → installer aborts, logs error, does not destroy the USB.
  - Successful install → system boots into Debian with expected hostname/user/SSH.
- Provide convenience scripts or make targets to run a subset of tests locally.

**Done When:**

- The harness can be run on a development machine to exercise at least the core v1 scenarios.
- All v1 tests listed in `docs/V1_CHECKLIST.md` pass for a reference configuration.

---

### Milestone 7 — User-Facing Documentation & Packaging

**Goal:** Make Screaming Penguin usable by others with clear instructions and minimal friction.

**Tasks:**

- Update or create:
  - `README.md` — high-level project overview and quickstart.
  - `docs/ISO_BUILD.md` — image build instructions.
  - `docs/ROOTFS_BUILD.md` — rootfs build instructions.
  - `docs/CONFIG_SCHEMA.md` — config reference and examples.
- Provide example configs under `config/` for common scenarios.
- Document safety expectations and caveats:
  - Full-disk wipe.
  - No auto-selection of target disks.
  - Requirement for proper backup and test usage first (e.g., VMs).

**Done When:**

- A new user with a Debian-based host can:
  - Build the image and rootfs.
  - Write to a USB stick.
  - Prepare a config.
  - Perform a successful v1 install following the documentation.

---

### Milestone 8 — v1.0.0 Release

**Goal:** Declare v1 complete and publish the artifacts.

**Tasks:**

- Tag the repository with `v1.0.0`.
- Capture reference artifacts (local-only or release assets):
  - `screaming-penguin-v1.img` — installer image.
  - `debian-rootfs-v1.tar.gz` — reference rootfs tarball.
  - Example configs.
- Ensure all v1 acceptance criteria in `docs/V1_CHECKLIST.md` are satisfied.
- Append a new entry to `docs/SP_BIBLE.md` summarizing the v1 release (handled in the PR that actually achieves v1).

**Done When:**

- The tagged v1.0.0 commit:
  - Builds cleanly.
  - Passes all v1 tests.
  - Has complete, accurate documentation.

---
