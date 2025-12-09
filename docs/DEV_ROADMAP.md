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
   - Updated `docs/CONFIG_SCHEMA.md` clarifying how `installer.rootfs.tarball` maps to the generated tarball and defaults to `/config/os/rootfs.tar.gz`.

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

## Phase 6 — QEMU Test Harness & v1 Acceptance Tests

**Goal:**  
Provide a repeatable, automated way to verify that Screaming Penguin can install a Debian Bookworm (amd64) system onto a virtual disk and boot it successfully under QEMU, using a known-good configuration.

Phase 6 focuses on testing and verification only. No installer or rootfs behavior changes are introduced in this phase.

---

### Functional Overview

Phase 6 introduces a QEMU-based test harness that can:

1. Build or reuse the Screaming Penguin installer image and Debian rootfs artifacts.
2. Create a blank virtual disk image as the installation target.
3. Boot the Screaming Penguin image in QEMU, attaching:
   - the installer image as the boot device, and
   - the blank disk image as the target disk,
   - a /config tree containing a known-good installer config and rootfs tarball.
4. Allow the installer to run to completion non-interactively.
5. Boot the installed system in QEMU (using the installed disk image as the boot device).
6. Capture console logs for both install and post-install boot phases and verify success markers.

The test harness exists purely in the project’s filesystem and must not touch real block devices.

---

### v1 Acceptance Tests (Initial Matrix)

Phase 6 defines a small, explicit set of acceptance scenarios:

1. **Case 1 — Happy Path Basic Install**
   - Single virtual disk.
   - SSH enabled with at least one authorized key.
   - User with sudo permissions.
   - Expected outcome:
     - Installer completes all states without error.
     - Install log shows progression through BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL → CONFIRM_INSTALL → EXECUTE_INSTALL → FINISH.
     - Installed system boots in QEMU.
     - Console log from installed system shows the configured hostname.

2. **Case 2 — SSH Disabled, Password Required**
   - SSH explicitly disabled.
   - `user.password_hash` provided.
   - Expected outcome:
     - Installer accepts the configuration and performs a full install.
     - No SSH keys required.
     - Installed system boots successfully.

3. **Case 3 — Safety Failure: Wrong ERASE Word**
   - `safety.require_erase_word: true`.
   - Harness provides incorrect ERASE confirmation.
   - Expected outcome:
     - Installer aborts in CONFIRM_INSTALL.
     - No partitioning or filesystem operations are performed on the virtual target disk.

The initial matrix may be expanded in later phases, but Phase 6 considers these three cases sufficient for v1 acceptance.

---

### Artifacts and Harness Layout

Phase 6 will introduce a lightweight harness structure:

- `tests/harness/`
  - Location for QEMU harness scripts (Phase 6 Prompt B).
- `config/installer-config.qemu-basic.yml`
  - Example known-good configuration for the QEMU happy-path install.
- `build/`
  - Directory where QEMU disk images and logs are written.
- `dist/`
  - Existing directory where the Screaming Penguin image and rootfs tarball are stored.

All harness operations must be confined to the repository’s own directories (`build/`, `dist/`, `tests/`, `config/`) and must not touch real `/dev/sdX` devices.

---

### Out of Scope for Phase 6

- Changes to installer logic or rootfs builder behavior.
- Network configuration or SSH into the running guest.
- Performance benchmarking or stress testing.
- Multi-disk installs, RAID, encryption, or non-Debian distributions.
- Complex CI orchestration; Phase 6 only introduces the harness design and basic wiring. CI integration is handled in later prompts for this phase.

---

### Definition of Done

Phase 6 is complete when:

- A QEMU test harness exists that can:
  - Run an end-to-end install onto a virtual disk image.
  - Boot the resulting installed system in QEMU.
  - Capture logs for both phases.
- A documented test matrix describes the v1 acceptance cases and expected outcomes.
- A Makefile target and/or documented commands can run the harness end-to-end (added in Phase 6 Prompt B/C).
- SP Bible entries record Phase 6 kickoff and completion.

---

## Phase 7 — User Docs, Packaging, and v1 Release Prep

**Goal:**  
Prepare Screaming Penguin for its initial public release by creating clear,
user-facing documentation, defining release artifact structure, introducing a
packaging workflow, and establishing versioning and distribution guidelines.

Phase 7 introduces no installer or rootfs behavior changes. It focuses on making
the project understandable, usable, and shippable by developers and end-users.

---

### Deliverables

1. User Documentation Set:
   - `docs/GETTING_STARTED.md`
   - `docs/INSTALLER_USAGE.md`
   - `docs/CONFIG_REFERENCE.md`
   - `docs/SAFETY.md`
   - `docs/TROUBLESHOOTING.md`
   - Refined `README.md` with concise overview and links to docs.

2. Release Packaging:
   - Define the v1.0.0 release bundle layout:
     - Installer ISO image
     - Debian rootfs tarball
     - Example configs bundle
     - SHA256 checksums and metadata
   - Introduce `make dist-release` in Phase 7 Prompt B to assemble the bundle.

3. Versioning & Release Notes:
   - Introduce semantic version scheme.
   - Add `docs/RELEASE_NOTES_v1.0.0.md` for the initial release notes.

---

### Out of Scope

- No runtime or installer logic changes.
- No new states in the installer state machine.
- No modifications to rootfs building mechanics.
- No additional acceptance tests.
- No release automation or publishing in CI (handled in future phases).

---

### Definition of Done

Phase 7 is complete when:
- All user-facing docs exist and provide clear guidance.
- README points to the correct docs.
- Release bundle structure is documented.
- A `dist-release` packaging mechanism exists (added in Prompt B).
- Versioning rules and release notes are established.
- Bible entries record Phase 7 kickoff and completion.

---

## Phase 8 — v1.0.0 Release Preparation

**Goal:**  
Finalize documentation, polish presentation, and prepare Screaming Penguin for
its first public release (v1.0.0). No installer logic will change in this
phase. All work focuses on final user-facing docs, release readiness, and
ensuring the project presents a stable and complete v1.

---

### Deliverables

1. Documentation polish across:
   - README cleanup
   - `GETTING_STARTED.md`
   - `INSTALLER_USAGE.md`
   - `CONFIG_REFERENCE.md`
   - `SAFETY.md`
   - `TROUBLESHOOTING.md`
   - `RELEASE_NOTES_v1.0.0.md`

2. Release readiness:
   - Confirm that all docs accurately describe v1 behavior and workflow
   - Ensure examples and terminology match final installer behavior
   - Create a final VERSION file during Phase 8 Prompt C

3. Presentation cleanup:
   - Remove outdated scaffolding lines from the README
   - Ensure docs no longer refer to Phase 7 or transitional states
   - Add a release readiness checklist to CI_OVERVIEW.md or a new doc

---

### Out of Scope

- No behavior or logic changes to the installer or rootfs builder
- No new features or supported configurations
- No CI workflow automation for publishing releases
- No branding or design changes beyond small cleanup

---

### Definition of Done

Phase 8 is complete when:
- Documents reflect the finished v1 system
- README reads cleanly and professionally
- Release notes for v1.0.0 are complete
- The repo is ready for a human-triggered GitHub Release
- Bible entries mark both the start and completion of Phase 8

---

## Phase 10 — Minimal Boot Runtime for ISO Builds

This phase introduces a proper boot runtime for the ISO build pipeline.  
The goals are:

- Implement a minimal Debian-based runtime containing `vmlinuz` and `initrd.img`.
- Add a `make runtime` target to produce these artifacts.
- Wire ISO generation so it depends on the runtime being built.
- Repair and harden the NOVA_AGENT_ENTRYPOINT.md file.
- Update documentation to reflect the new ISO build chain.

- [x] Add parallel ISO build path (`make iso`) using a minimal Debian
      boot runtime and hybrid ISO image, suitable for Windows USB tools.

No installer behavior changes are planned for this phase.


## Hotfix Phase 10.5 — ISO Boot / Initramfs Wiring

- **P10.5·A** — Document the current ISO boot failure (kernel dropping to initramfs) and design the custom installer initramfs / GRUB wiring.
- **P10.5·B** — Implement `build_installer_initramfs.sh`, integrate the custom installer initrd into the ISO builder, and update GRUB to boot with `root=/dev/ram0 rdinit=/init`.
- **P10.5·C** — Add CI smoke tests for the installer initramfs and GRUB config; run QEMU-based sanity tests to validate the full boot path.
## Phase 9 — Disk layout planner

**Goal:** Provide a declarative GPT plan for the EFI and root partitions without touching the target disk, so later phases can safely apply the same plan under the write gate.

**Tasks:**
- Add `installer/runtime/lib/disk_layout.sh` and support `installer.disk_layout` tuning knobs (EFI size, alignments, reserved MiB) plus the existing `target.disk` target.
- Expose the plan surface via `sp_print_layout_plan`, and let init scripts log the plan body between `[SP-INSTALLER] disk-layout plan START/END` when `SP_DEBUG_DISK_LAYOUT=1` so CI/tests can verify the JSON output.
- Update config schema, installer contract, and architecture docs to describe the planner, and record Phase 9 in `docs/Phase9_Roadmap.md` and the master roadmap.
- Keep the write gate enforced and refuse to run destructive commands until Phase 10 consumes the plan and writes the GPT table/filesystems.

**Done When:** the planner produces a deterministic plan for one EFI + one root partition, the plan is observable via logs, and no partitioning tool has been invoked yet.

## Phase 10 — Disk execution & mkfs harness

**Goal:** Apply the Phase 9 GPT plan to the target disk, format the EFI FAT32 and ext4 root volumes, and prove the destructive path via a virtual-disk harness so CI can gate real disks safely.

**Tasks:**
- Add `installer/runtime/lib/disk_execute.sh` plus logging markers so the init script can re-validate `installer.write_gate`, re-read the plan, call `sgdisk`/`sfdisk`, and format partitions only when `SP_ENABLE_DISK_EXECUTE=1`.
- Extend `installer/init/init.sh` to source the executor, guard it behind readiness checks, and only run it when the gate and toggle align; keep non-destructive runs for CI smoke.
- Create `tests/installer/test_disk_execute.py`, which builds a 2–4 GiB virtual disk file, attaches it via loop if available, runs the planner/executor, verifies GPT type codes, and (when loop support exists) mounts both partitions.
- Update the config schema, installer contract, architecture docs, and the new `docs/Phase10_Roadmap.md` so downstream tooling knows how writes happen and that `[SP-INSTALLER] disk-exec START/END` wraps the work.

**Done When:** the executor rewrites the GPT table, formats EFI+root, logs the disk-exec window, and the harness proves a safe virtual-disk path that stays gated unless `SP_ENABLE_DISK_EXECUTE=1`.

## Phase 11 — Rootfs deploy & chroot configuration

**Goal:** Extract a prebuilt Debian rootfs tarball onto the freshly-formatted root partition, bind the virtual filesystems, and chroot to apply hostname, timezone, locale, user, and SSH-key configuration driven by `installer.rootfs.*`.

**Tasks:**
- Add `installer/runtime/lib/rootfs_deploy.sh`, hook it into `installer/init/init.sh` after `sp_execute_gpt_plan`, and emit `[SP-INSTALLER] rootfs START/END` markers so logs show the span.
- Parse `installer.rootfs.tarball` (default `/config/os/rootfs.tar.gz`), `installer.rootfs.target_mount`, and the hostname/timezone/locale/username/password/SSH-key fields, and honor the `SP_SKIP_ROOTFS_DEPLOY`, `SP_SKIP_CHROOT_CONFIG`, and `SP_DEBUG_ROOTFS` toggles for CI.
- Update `config/installer-config.example.yml`, `docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`, `docs/Phase11_Roadmap.md`, and the analysis notes so the new stage, default paths, and toggle semantics are documented.
- Add `tests/installer/test_rootfs_deploy.py` (and any supporting helpers) so CI can exercise tarball extraction and the configuration helpers in a non-destructive, temp-dir-friendly way.

**Done When:** the initramfs can extract `/config/os/rootfs.tar.gz` into `/mnt/target`, bind the usual `/dev|/proc|/sys|/run` mounts, chroot to configure hostname/timezone/locale/user/SSH, log `[SP-INSTALLER] rootfs` spans, and the new tests and docs confirm the behavior while honoring the skip/debug toggles.

## Phase 12 — Bootloader install & completion cues

**Goal:** Teach the installer how to mount the EFI partition, write a valid `/etc/fstab`, install GRUB via `grub-install --target=<grub_efi_target>`, and emit a final `[SP-INSTALLER] COMPLETE` marker so downstream systems know the entire pipeline finished.

**Tasks:**
- Add `installer/runtime/lib/bootloader.sh` that mounts the target root + EFI trees, writes `/etc/fstab` from `blkid` UUIDs, builds a minimal `/boot/grub/grub.cfg`, and runs `grub-install` inside the chroot while logging `[SP-INSTALLER] bootloader START/END`.
- Update `installer/init/init.sh` to source the bootloader helper right after rootfs, call `sp_install_bootloader_and_finalize`, and log the final completion cue.
- Extend `installer/runtime/lib/config_validation.sh`, `config/installer-config.example.yml`, and `docs/CONFIG_SCHEMA.md` with the optional `installer.bootloader` block plus defaults.
- Add `tests/installer/test_bootloader.py` to validate fstab generation, GRUB command assembly, gating, skip/debug flags, and the init shim reaching the bootloader stage only when `SP_ENABLE_BOOTLOADER=1`.
- Document the new stage in `docs/Phase12_Roadmap.md`, `docs/installer_contract.md`, `docs/architecture.md`, and update this roadmap to reference the new behavior and toggles.

**Done When:** the bootloader stage runs after rootfs, writes `/etc/fstab`, installs GRUB, honors `SP_ENABLE_BOOTLOADER`, and the docs/tests describe the new config block plus `[SP-INSTALLER] COMPLETE` signal.
