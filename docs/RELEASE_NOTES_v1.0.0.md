# Screaming Penguin v1.0.0 — Release Notes

Initial public release of Screaming Penguin, a deterministic, config-driven,
non-interactive Linux installer targeting Debian Bookworm.

---

## Features

- x86_64 installation support
- BIOS + UEFI compatibility
- Full-disk wipe with GPT layout
- ext4 root filesystem
- Prebuilt Debian Bookworm rootfs
- Automated chroot configuration:
  - hostname
  - locale/timezone
  - user creation
  - SSH (optional)
  - GRUB installation
- Headless-friendly operation
- Optional audio cue support
- `/config/logs` for persistent installer logs

---

## Constraints (v1 Limitations)

- No encryption or LVM
- No multi-disk or RAID
- No Secure Boot handling
- No custom partitioning
- Single-user provisioning
- ext4 only

---

## Known Issues

- Some hardware may require manual BIOS boot priority
- Certain USB controllers enumerate inconsistently
- Secure Boot unsupported

---

## Recommended Usage

Use QEMU first to validate your config before running on hardware.
