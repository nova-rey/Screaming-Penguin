# Screaming Penguin — Installer Usage Guide (v1.0.0)

This guide provides full operational instructions for using the Screaming
Penguin installer, including USB preparation, configuration placement, booting,
confirmation prompts, and log retrieval.

---

## USB Image Layout

After writing `screaming-penguin-v1.0.0.img` to a USB device:

- **Partition 1 (`/config`)**: Writable config + logs. This FAT32 volume already contains `installer-config.yml`, `/config/os/rootfs.tar.gz`, and the logs directory, and placing it first keeps desktop environments from flagging the USB as a boot-only device.
- **Partition 2 (read-only)**: Bootable installer system (EFI/BIOS tree with `/EFI/BOOT/BOOTX64.EFI`, `/EFI/BOOT/grub.cfg`, `/boot/vmlinuz-installer`, and `/boot/initrd-installer.img`). The second partition remains an ESP as before, so UEFI firmware locates it by type rather than index.

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

Refer to `USING_IMG.md` for the canonical installer workflow. `USING_ISO.md`
remains in the tree for historical reference only; hybrid ISO builds are no longer
supported in this repository.

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

---

## Headless Behavior

Screaming Penguin is designed for unattended environments:

- No graphical UI
- Optional audio notification at start and finish
- All logs persisted to `/config/logs`

---

## Troubleshooting

See `TROUBLESHOOTING.md` for detailed failure modes and log extraction.
