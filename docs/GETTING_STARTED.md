# Screaming Penguin — Getting Started

Screaming Penguin is a deterministic, configuration-driven Linux installer for
automated deployments. It installs a prebuilt Debian root filesystem (rootfs)
onto a target disk using a simple YAML configuration stored on a writable
partition of the installer USB.

This document provides a gentle intro and the minimum steps required to perform
a successful installation.

---

## What Screaming Penguin Is

- A non-interactive automated installer.
- Headless-friendly.
- Ideal for labs, homelabs, DevOps pipelines, kiosks, or inaccessible devices.
- Powered by a prebuilt Debian Bookworm rootfs.
- Controlled entirely through `/config/installer-config.yml`.

## What Screaming Penguin Is Not

- It is not a traditional Debian Installer.
- It does not support manual partitioning.
- It does not support multi-boot, LVM, RAID, encryption, or custom bootloaders.
- It wipes the target disk completely.

---

## Hardware Assumptions (v1 Limitations)

- x86_64 only  
- BIOS + UEFI supported  
- One target storage device  
- Full-disk wipe only  
- ext4 root filesystem  

---

## High-Level Installation Flow

1. Download the Screaming Penguin ISO and Debian rootfs tarball.
2. Write the ISO to a USB drive.
3. Mount USB `/config` and place:
   - `installer-config.yml`
   - `rootfs/debian-rootfs.tar.gz`
4. Boot target machine from USB.
5. Installer validates config.
6. Installer wipes target disk.
7. Partitions EFI + ext4.
8. Extracts rootfs.
9. Applies system configuration.
10. Installs GRUB.
11. Shuts down or reboots.

---

See `INSTALLER_USAGE.md` for full step-by-step instructions.
