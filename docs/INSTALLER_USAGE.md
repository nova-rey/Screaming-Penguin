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

### Path A: Raw .img (Linux / macOS, recommended)

On Linux (and other Unix-like systems), the simplest path is to use the
raw `.img` artifact:

1. Download the release bundle and locate `screaming-penguin.img`.
2. Identify your USB device (for example `/dev/sdX` or `/dev/diskN`).
3. Write the image:

   ```sh
   sudo dd if=screaming-penguin.img of=/dev/sdX bs=4M conv=fsync status=progress
   ```

4. Safely eject the USB stick.

The raw image already contains a small CONFIG partition. Mount that
partition and copy your installer-config.yml (or installer-config.yaml)
into the root of the CONFIG volume before booting the target machine.

### Path B: ISO (Windows / generic USB tools)

For Windows users (and anyone who prefers ISO-centric tools such as Rufus),
use the `screaming-penguin.iso` artifact:

1. Download `screaming-penguin.iso` from the release or CI artifacts.
2. Use your preferred USB tool (e.g. Rufus, Balena Etcher, etc.) to write
   the ISO to a USB stick. A single large bootable partition will be created.
3. After flashing, **shrink** the main partition to free ~1–2 GiB of space:
   - On Windows, open **Disk Management**.
   - Locate the USB device and right-click the main volume.
   - Choose **Shrink Volume…** and free at least 1024–2048 MB.
4. Create a new partition in the freed space:
   - Format it as **FAT32**.
   - Label it `CONFIG`.
5. Mount the new `CONFIG` partition and copy your `installer-config.yml`
   (or `installer-config.yaml`) into its root.
6. Safely eject the USB stick and boot the target machine from USB.

At boot time, Screaming Penguin will look for a FAT32 partition labeled
`CONFIG` and load the installer configuration from there.

---

## Headless Behavior

Screaming Penguin is designed for unattended environments:

- No graphical UI
- Optional audio notification at start and finish
- All logs persisted to `/config/logs`

---

## Troubleshooting

See `TROUBLESHOOTING.md` for detailed failure modes and log extraction.

