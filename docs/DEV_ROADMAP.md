```markdown
# Screaming Penguin — Development Roadmap (v0 Focus)

This roadmap describes the initial milestones required to deliver Screaming Penguin v0 as a usable, documented, and testable installer.

## Milestone 0.1 — Repo Bootstrap & Documentation

- Establish initial repository structure (docs, installer, tools, tests, ci).
- Add core documentation:
  - `DESIGN_v0.md`
  - `DEV_ROADMAP.md`
  - `DEV_PHILOSOPHY.md`
  - `SP_BIBLE.md`
  - `NOVA_AGENT_ENTRYPOINT.md`
- Provide example config and schema stubs:
  - `config/installer-config.example.yml`
  - `docs/CONFIG_SCHEMA.md` (outline only).

**Exit criteria:**
- Repository layout is created.
- Documentation is present and committed.
- No runtime logic required yet.

---

## Milestone 0.2 — Initramfs & Runtime Skeleton

- Define the initramfs entrypoint layout:
  - `installer/initramfs/init`
  - `installer/initramfs/hooks/` for modular steps.
- Create empty or minimal runtime scripts:
  - `installer/runtime/sp-installer`
  - `installer/runtime/sp-disk-plan.sh`
  - `installer/runtime/sp-disk-apply.sh`
  - `installer/runtime/sp-rootfs-apply.sh`
  - `installer/runtime/sp-chroot-setup.sh`
  - `installer/runtime/sp-audio.sh`
  - `installer/runtime/lib/` helpers (`logging.sh`, `config_validation.sh`, `safety_checks.sh`).
- Ensure scripts are present with clear TODO markers but no destructive behavior.

**Exit criteria:**
- Installer scripts exist and are executable.
- Running in QEMU logs basic state transitions but does not touch disks.

---

## Milestone 0.3 — ISO / Disk Image Build Pipeline

- Implement `tools/make_installer_iso.sh` to:
  - Build a bootable p1 with kernel, initramfs, and GRUB.
  - Create a raw disk image with p1 (read-only) and p2 (FAT32).
- Document the build steps in `docs/ISO_BUILD.md`.
- Add a `Makefile` with convenience targets:
  - `make iso`
  - `make clean`

**Exit criteria:**
- Image builds successfully on a Debian-based host with documented dependencies.
- Image boots to initramfs in QEMU (BIOS and UEFI) and reaches the installer skeleton.

---

## Milestone 0.4 — Debian Rootfs Build Pipeline

- Implement `tools/make_rootfs_debian.sh` using `debootstrap`.
- Document the process in `docs/ROOTFS_BUILD.md`.
- Define minimal package set and cleanup behavior.
- Verify that the resulting `debian-rootfs.tar.gz` can be used with a manual installation flow.

**Exit criteria:**
- Rootfs tarball can be built reproducibly.
- Tarball size and contents are documented.
- Manual chroot tests confirm that the rootfs boots when wired into a VM.

---

## Milestone 0.5 — Full v0 Install Path (Single-Disk, Single-Root)

- Implement the full v0 state machine:
  - BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL → CONFIRM_INSTALL → EXECUTE_INSTALL → FINISH.
- Implement destructive operations only after safety checks:
  - Target disk verification.
  - USB protection.
  - Erase word confirmation (if enabled).
- Implement chroot configuration for:
  - Hostname.
  - Timezone.
  - Locale.
  - User/password/SSH.
  - GRUB installation for BIOS/UEFI.

**Exit criteria:**
- End-to-end install in QEMU yields a bootable Debian system.
- All v0 tests in `docs/TESTING_v0.md` pass.

---

## Milestone 0.6 — Test Harness & CI Skeleton

- Add QEMU-based test harness under `tests/harness/`.
- Define test scenarios in `docs/TESTING_v0.md`.
- Integrate minimal CI scaffolding:
  - Linting for scripts (shellcheck where applicable).
  - Markdown linting (optional).
  - Hook points for future automated QEMU runs.

**Exit criteria:**
- Core tests can be invoked locally with a single command.
- CI pipeline is defined and can be wired to a CI service later.

---

## Beyond v0 (High-Level)

Future work beyond v0 (not in immediate scope):

- Additional filesystems and layouts (LVM, btrfs, encryption).
- Multi-distro support via multiple rootfs tarballs.
- Network-based installation and content fetching.
- Richer audio feedback for accessibility.
- Configuration layering, profiles, and overrides.

```
