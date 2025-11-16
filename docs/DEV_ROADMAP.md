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

**Goal:** Build a bootable USB-style disk image with the required two-partition layout.

**Tasks:**

- Implement `tools/make_installer_iso.sh` (or equivalent) to:
  - Build a minimal initramfs-based Linux environment with Screaming Penguin runtime.
  - Produce a p1 image containing:
    - Kernel, initramfs, GRUB configuration.
    - ISO9660 or squashfs content as required.
  - Create a raw disk image with:
    - Partition 1: read-only boot environment (p1).
    - Partition 2: writable `/config` (FAT32).
- Add `docs/ISO_BUILD.md` describing:
  - Host build dependencies.
  - Build steps.
  - How to write the final image to a USB drive.
- Add `Makefile` targets:
  - `make iso` — builds the image.
  - `make clean` — cleans build artifacts.

**Done When:**

- On a supported build host, `make iso` produces a disk image with both partitions.
- The image boots in QEMU (BIOS and UEFI) into the initramfs and reaches the installer skeleton.

---

### Milestone 4 — Debian Rootfs Build Pipeline

**Goal:** Provide a reproducible way to generate the Debian rootfs tarball used by the installer.

**Tasks:**

- Implement `tools/make_rootfs_debian.sh` using `debootstrap` to create:
  - A minimal Debian rootfs for `amd64`.
  - Required packages (e.g., `systemd-sysv`, `openssh-server`, `sudo`, `locales`, `linux-image-amd64`, `grub-pc`, `grub-efi-amd64`).
- Document the process in `docs/ROOTFS_BUILD.md`:
  - Build host requirements.
  - Commands used.
  - Cleanup steps.
- Define expectations for the tarball:
  - Path: `/config/rootfs/debian-rootfs.tar.gz`.
  - Ownership and permissions.
  - No hard-coded hostname, fstab, or device-specific GRUB configuration.

**Done When:**

- The rootfs tarball builds successfully on a supported build host.
- Manual testing (outside Screaming Penguin) confirms that the rootfs can be booted when wired into a VM and configured with GRUB.

---

### Milestone 5 — Installer Runtime v1 (Core Install Path)

**Goal:** Implement the full v1 installer behavior on a single target disk.

**Tasks:**

- Implement all states in the installer state machine:

  - **BOOT_INIT**
    - Mount `/config`.
    - Initialize logging under `/config/logs/`.
    - Optional audio cue (“Installer ready”).

  - **LOAD_CONFIG**
    - Read `/config/installer-config.yml`.
    - Validate required fields according to `docs/CONFIG_SCHEMA.md`.
    - Reject unsafe or incomplete configs.

  - **PLAN_INSTALL**
    - Enumerate block devices and determine the installer USB.
    - Verify that `target.disk` exists and is not the installer USB.
    - Enforce `wipe: true` for v1.
    - Plan GPT layout: EFI/BIOS partition + single ext4 root.

  - **CONFIRM_INSTALL**
    - If `safety.require_erase_word: true`, prompt:
      - “Type ERASE to continue.”
    - Abort if the confirmation is not provided correctly.

  - **EXECUTE_INSTALL**
    - Apply partition plan to `target.disk`.
    - Create filesystems:
      - `mkfs.vfat` for EFI/BIOS partition.
      - `mkfs.ext4` for root partition.
    - Mount root partition.
    - Extract the Debian rootfs tarball.
    - Configure base system (fstab, hostname, timezone, locale).
    - Bind-mount `/dev`, `/proc`, `/sys`.
    - chroot:
      - Create user and set password hash.
      - Configure SSH (enable and install authorized_keys, if enabled).
      - Install and configure GRUB for BIOS/UEFI.
    - Unmount, sync, and clean up.

  - **FINISH**
    - Write a final status entry to `/config/logs/<timestamp>.log`.
    - Emit a completion cue (audio if available).
    - Shut down the system cleanly.

**Done When:**

- An end-to-end run in QEMU, with a valid config and rootfs tarball, produces a bootable Debian system matching the config.

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
