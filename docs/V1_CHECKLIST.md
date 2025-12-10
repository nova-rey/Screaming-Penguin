# Screaming Penguin — v1 Acceptance Checklist

This checklist defines the concrete conditions that must be satisfied before Screaming Penguin can be called **v1.0.0**.

Each item should be verified against a reference build and configuration.

---

## 1. Build & Image

- [ ] `tools/make_installer_iso.sh` (or equivalent) produces a bootable disk image on a supported Debian-based host.
- [ ] The disk image contains:
- [ ] Partition 1: writable FAT32 `/config` partition.
- [ ] Partition 2: read-only boot environment (EFI/GRUB, `/boot/vmlinuz-installer`, `/boot/initrd-installer.img`).
- [ ] `docs/ISO_BUILD.md` correctly describes the build steps and dependencies.
- [ ] A `Makefile` target (e.g., `make iso`) successfully builds the image.

---

## 2. Rootfs Tarball

- [ ] `tools/make_rootfs_debian.sh` (or equivalent) produces `debian-rootfs.tar.gz`.
- [ ] The tarball contains a minimal Debian system for `amd64` with:
  - [ ] `systemd-sysv` (or equivalent init).
  - [ ] `openssh-server`.
  - [ ] `sudo`.
  - [ ] `locales`.
  - [ ] `linux-image-amd64`.
  - [ ] `grub-pc` and `grub-efi-amd64`.
- [ ] `docs/ROOTFS_BUILD.md` matches the actual build behavior.
- [ ] The tarball can be used (outside Screaming Penguin) to boot a test VM when wired with a suitable bootloader.

---

## 3. Config Handling & Safety

Using `/config/installer-config.yml`:

- [ ] A valid config is parsed and validated successfully.
- [ ] The installer refuses to run when:
  - [ ] The config file is missing.
  - [ ] The `target.disk` device does not exist.
  - [ ] The `target.disk` resolves to the installer USB itself.
  - [ ] The rootfs tarball is missing or unreadable.
  - [ ] SSH is disabled and no password hash is provided.
- [ ] `safety.require_erase_word: true` enforces a confirmation prompt requiring the word `ERASE` before any destructive operation occurs.

---

## 4. Core Install Path

On a reference QEMU setup with a dedicated virtual target disk:

- [ ] The installer:
  - [ ] Boots in both BIOS and UEFI modes.
  - [ ] Mounts `/config` and opens log files under `/config/logs/`.
  - [ ] Transitions through the documented state machine:
    - BOOT_INIT → LOAD_CONFIG → PLAN_INSTALL → CONFIRM_INSTALL → EXECUTE_INSTALL → FINISH.
- [ ] Disk layout on the target disk after install:
  - [ ] GPT partition table.
  - [ ] EFI/BIOS system partition (FAT32).
  - [ ] Single ext4 root partition.
- [ ] The root partition contains a fully extracted Debian rootfs from the tarball.
- [ ] fstab, hostname, timezone, and locale are configured according to the config.
- [ ] A user account is created as specified, with the configured password hash.
- [ ] SSH is:
  - [ ] Enabled if `ssh.enable: true`.
  - [ ] Populated with the configured `authorized_keys` set.

---

## 5. Boot & Runtime Behavior

For the installed system:

- [ ] The system boots successfully in BIOS mode from the installed disk.
- [ ] The system boots successfully in UEFI mode from the installed disk.
- [ ] GRUB is correctly installed and loads the default kernel.
- [ ] The configured hostname appears in `hostname` and `uname -n`.
- [ ] The configured timezone is active (e.g., `timedatectl`).
- [ ] The configured locale is generated and active.
- [ ] The user can:
  - [ ] Log in via local console (if available) with the configured password.
  - [ ] Log in via SSH (if enabled) with an authorized key.

---

## 6. Logging & Completion

- [ ] The installer writes a timestamped log file to `/config/logs/` for each run.
- [ ] Logs include:
  - [ ] Start and end states.
  - [ ] Target disk identification.
  - [ ] High-level partitioning actions.
  - [ ] Error conditions when aborting.
- [ ] On successful completion:
  - [ ] The installer emits a completion cue (audio if available).
  - [ ] The system shuts down cleanly.

---

## 7. Documentation

- [ ] `README.md` provides:
  - [ ] A high-level description of the project.
  - [ ] A warning about full-disk wipe behavior.
  - [ ] A concise quickstart for building and running v1.
- [ ] `docs/DESIGN_v0.md` matches the implemented behavior.
- [ ] `docs/DEV_ROADMAP.md` matches the project’s actual milestone status.
- [ ] `docs/CONFIG_SCHEMA.md` describes all supported config keys and their validation rules.
- [ ] Example configs under `config/` are valid and up to date.

---

## 8. Release

- [ ] Repository is tagged `v1.0.0`.
- [ ] Reference artifacts for v1 (image, rootfs tarball, configs) are built and archived (locally or as release assets).
- [ ] A new entry is appended to `docs/SP_BIBLE.md` describing the v1.0.0 release.

When all boxes in this checklist are satisfied, Screaming Penguin is considered **v1 complete**.
