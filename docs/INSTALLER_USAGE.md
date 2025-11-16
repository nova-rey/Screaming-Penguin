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

## Headless Behavior

Screaming Penguin is designed for unattended environments:

- No graphical UI
- Optional audio notification at start and finish
- All logs persisted to `/config/logs`

---

## Troubleshooting

See `TROUBLESHOOTING.md` for detailed failure modes and log extraction.
