# Screaming Penguin — Installer Usage Guide (v1.0.0)

This guide provides full operational instructions for using the Screaming
Penguin installer, including USB preparation, configuration placement, booting,
confirmation prompts, and log retrieval.

---

## USB Image Layout

After writing `screaming-penguin-v1.0.0.img` to a USB device:

- **Partition 1 (read-only)**: Bootable installer system
- **Partition 2 (`/config`)**: Writable config + logs

---

## Required Files on `/config`

installer-config.yml
rootfs/debian-rootfs.tar.gz

Optional:

logs/

Installer creates `logs/` automatically.

---

## Installer Lifecycle

1. **BOOT_INIT**  
   Mounts `/config`, initializes logging.

2. **LOAD_CONFIG**  
   Loads YAML and validates schema.

3. **PLAN_INSTALL**  
   Verifies target disk and layout.

4. **CONFIRM_INSTALL**  
   Optionally requires the user to type `ERASE`.

5. **EXECUTE_INSTALL**  
   - Partition target disk
   - Create EFI + ext4 filesystems
   - Extract Debian Bookworm rootfs
   - Configure hostname, locale, timezone
   - Create user and SSH config
   - Install GRUB

6. **FINISH**
   Writes persistent logs and reboots or shuts down.

---

## CONFIG Partition Requirements

The installer reads configuration from a partition labeled `CONFIG`, containing
a file named `installer-config.yml`.

- IMG builds: CONFIG partition included
- ISO builds: user must create CONFIG partition after flashing

Refer to `USING_IMG.md` or `USING_ISO.md` for full instructions.

---

## Headless Behavior

Screaming Penguin is designed for unattended environments:

- No graphical UI
- Optional audio notification at start and finish
- All logs persisted to `/config/logs`

---

## Troubleshooting

See `TROUBLESHOOTING.md` for detailed failure modes and log extraction.

## Using the ISO on Windows/macOS

After flashing the ISO to a USB drive, the device will contain a single ISO9660
read-only partition. To supply configuration, create a second FAT32 partition:

1. Shrink the USB drive by 1–2 GB (Disk Management on Windows, Disk Utility on macOS).
2. Create a new FAT32 partition.
3. Name the partition `CONFIG` (uppercase recommended).
4. Copy your `installer-config.yml` and any optional files into the root of that partition.

The installer will automatically detect the `CONFIG` partition at boot.

## Using the IMG on Linux

Flashing the `.img` file with `dd` or GNOME Disks will create:

- A boot partition
- A writable config partition (`CONFIG`)
- The runtime filesystem

You may immediately place your `installer-config.yml` into the `CONFIG` partition
from Linux or any OS that can mount FAT32.
