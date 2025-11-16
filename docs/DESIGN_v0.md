# Screaming Penguin — v0 Design Document

## 1. Overview

Screaming Penguin is a **config-driven, automated Linux installer** delivered as a bootable USB image. It is optimized for **headless** and **inaccessible** environments where traditional graphical installers are impractical.

Instead of performing a package-by-package installation, Screaming Penguin v0 installs a **prebuilt Debian root filesystem (rootfs)** tarball to a target disk, then applies system configuration and bootloader setup according to a **YAML configuration file** stored on a writable partition.

The project targets **x86_64** systems with both **BIOS and UEFI** firmware support.

---

## 2. Goals and Non-Goals (v0)

### 2.1 Goals

- Provide a **repeatable, unattended installation path** for Debian-based systems via a single USB device.
- Use a **writable configuration partition** to drive behavior:
  - `installer-config.yml` (YAML) describes the installation.
  - A **rootfs tarball** supplies the system image.
- Support **full-disk wipe** installs only (no in-place upgrade).
- Support a simple layout:
  - GPT partition table.
  - **EFI/BIOS system partition**.
  - Single **ext4 root** partition.
- Provide strict **safety checks** to avoid accidental wipes, including:
  - Explicit target disk.
  - Protection against choosing the installer USB as the target.
  - Optional erase confirmation word.
  - Requirement for either SSH keys or a password.
- Optional **audio cues** to assist in headless or inaccessible environments.

### 2.2 Non-Goals (for v0)

- No multi-distro support (v0 is **Debian minimal rootfs only**).
- No interactive partition editor or multi-OS layouts.
- No support for LVM, btrfs, ZFS, RAID, or LUKS (future versions may add).
- No network-based installation or remote rootfs fetching.
- No complex installer UI (text or graphical). Interaction is minimal and optional.

---

## 3. System Architecture

### 3.1 USB Layout

The installer USB is a **two-partition** device:

| Partition | FS         | Mount Path | Purpose                                |
|----------:|------------|-----------:|----------------------------------------|
| p1        | ISO9660 / squashfs | (read-only) | Bootable system + installer environment |
| p2        | FAT32 (writable)   | `/config`    | Configuration, rootfs tarball, logs    |

Expected structure on `/config`:

- `/config/installer-config.yml` — main configuration file.
- `/config/rootfs/debian-rootfs.tar.gz` — prebuilt Debian rootfs tarball.
- `/config/logs/*.log` — installer logs.

Partition p1 is built as a bootable ISO9660 image containing a minimal Linux system, an initramfs, and the Screaming Penguin installer runtime. Partition p2 is a writable FAT32 partition to be populated/updated by the user.

### 3.2 Boot and Runtime Components

1. **Bootloader**
   - GRUB or Syslinux-based boot configuration on p1.
   - Supports both BIOS and UEFI boot.
   - Boots a Linux kernel with an initramfs containing BusyBox and the Screaming Penguin init logic.

2. **Initramfs Environment**
   - Based on **BusyBox**.
   - Responsibilities:
     - Discover and mount the `/config` partition (FAT32, p2).
     - Perform early **safety checks** (presence of config and rootfs).
     - Optionally initialize audio and emit a simple “Installer ready” cue.
     - Launch the main installer runtime.

3. **Installer Runtime**
   - Invoked from the initramfs once `/config` is mounted.
   - Implemented as a combination of **POSIX shell scripts** and a higher-level orchestrator (shell or Python 3) to:
     - Parse and validate YAML.
     - Plan and apply disk partitioning.
     - Extract the rootfs tarball.
     - Perform chroot-based configuration and bootloader installation.

4. **Chroot Configuration**
   - After rootfs extraction, the installer:
     - Binds necessary pseudo-filesystems (`/dev`, `/proc`, `/sys`).
     - Enters chroot.
     - Applies system configuration:
       - Hostname.
       - Timezone.
       - Locale.
       - User and password/SSH setup.
       - SSH daemon enablement.
       - GRUB installation and configuration.
     - Exits chroot and syncs to disk.

---

## 4. Config Schema (v0)

Configuration is supplied as YAML at `/config/installer-config.yml`.

### 4.1 Draft Schema

```yaml
version: 0.1

target:
  disk: nvme0n1              # required; no disk auto-guess
  wipe: true                 # v0: always full wipe

filesystem:
  layout: single             # future: 'lvm', 'btrfs', etc.
  type: ext4
  boot_mode: auto            # 'uefi', 'bios', 'auto'

rootfs:
  path: /config/rootfs/debian-rootfs.tar.gz

system:
  hostname: penguin-01
  timezone: America/Chicago
  locale: en_US.UTF-8

user:
  name: rey
  sudo: true
  password_hash: "$6$..."    # required if SSH disabled

ssh:
  enable: true
  authorized_keys:
    - "ssh-ed25519 AAAAC3..."

safety:
  require_erase_word: true

4.2 Validation Rules

The installer must reject the configuration and abort if:
•target.disk is missing.
•rootfs.path is missing or unreadable.
•target.disk resolves to the installer USB itself.
•ssh.enable is false and user.password_hash is missing (no login path).
•version is unsupported.

A separate docs/CONFIG_SCHEMA.md will formalize this, and a tool (tools/verify_config.sh or equivalent) can be used for offline validation.

⸻

5. State Machine and Control Flow

The installer follows a simple state machine:
1.BOOT_INIT
•Mount /config (FAT32).
•Confirm presence of installer-config.yml.
•Initialize logging in /config/logs/.
•Initialize audio (if available) and emit optional “Installer ready” signal.
2.LOAD_CONFIG
•Read YAML config.
•Validate structure and required fields.
3.PLAN_INSTALL
•Validate target disk and ensure it is not the USB device.
•Verify wipe: true (v0 requirement).
•Determine partitioning plan:
•GPT label.
•EFI/BIOS system partition (FAT32).
•Single root partition (ext4).
•Resolve boot_mode (uefi, bios, or auto based on system).
4.CONFIRM_INSTALL
•If safety.require_erase_word is true, prompt via console:
•Text: “Type ERASE to continue.”
•If the word is not provided correctly, abort and log.
5.EXECUTE_INSTALL
•Apply partition layout to target.disk.
•Create filesystems:
•mkfs.vfat for EFI/BIOS partition.
•mkfs.ext4 for root partition.
•Mount root partition at a temporary mountpoint.
•Extract rootfs tarball.
•Configure fstab and basic system settings.
•Bind-mount /dev, /proc, /sys.
•chroot into the new system and:
•Set hostname, timezone, locale.
•Create user and set password hash.
•Configure SSH (enable service, install authorized keys).
•Install GRUB for both BIOS/UEFI as appropriate.
•Unmount and sync.
6.FINISH
•Write final log to /config/logs/<timestamp>.log.
•Emit audio completion cue (if available).
•Perform a clean shutdown or reboot (configurable in future versions; v0 may default to shutdown).

⸻

6. Safety and Protection

Key protections in v0:
•USB Target Protection
The installer enumerates block devices and compares:
•Boot device (installer USB).
•Specified target.disk.
If they match, the installer must refuse to proceed and log the error.
•Erase Word Confirmation
When enabled, the installer requires an explicit confirmation string (“ERASE”) before applying any destructive operations.
•Login Path Guarantee
At least one of the following must be true:
•SSH is enabled with at least one authorized key.
•A user exists with a valid password hash.

If not, the installer aborts.

⸻

7. Base System Tools and Dependencies

The installer environment (p1) will include:
•Linux kernel with initramfs.
•BusyBox for core utilities.
•Disk tools:
•parted or sgdisk for partitioning.
•mkfs.vfat, mkfs.ext4.
•Filesystem tools:
•mount, umount, blkid.
•Archive tools:
•tar (and optionally rsync).
•Bootloader tools:
•grub-install, update-grub (within chroot).
•Optional audio:
•beep or espeak-ng depending on hardware and size constraints.

YAML parsing may be implemented via:
•Python 3 with pyyaml, or
•A small standalone binary (future optimization).

For v0, Python 3 in the installer runtime is acceptable.

⸻

8. Testing Strategy (v0)

Initial testing will focus on QEMU-based scenarios:
•Missing config file
•Remove /config/installer-config.yml.
•Expect: installer abort, log message in /config/logs/.
•Target disk not found
•Specify a non-existent disk in target.disk.
•Expect: abort with clear log message.
•USB mistakenly chosen as target
•Set target.disk to the installer device.
•Expect: abort, no changes to disk.
•Successful install
•Use a test virtual disk.
•Expect:
•System boots into Debian.
•Hostname/timezone/locale applied.
•User exists and can log in.
•SSH enabled if configured.
•GRUB boots under BIOS and UEFI where applicable.

Additional negative tests will be defined in docs/TESTING_v0.md.

⸻

9. Roadmap Beyond v0 (High-Level)

Out of scope for v0 but candidate future work:
•Additional filesystems (btrfs, LVM, encrypted root).
•Network-based rootfs fetching.
•Multi-distro support via multiple rootfs tarballs.
•More advanced audio feedback and progress reporting.
•Richer logging and telemetry.

This document defines the v0 baseline needed to begin implementation.

---
