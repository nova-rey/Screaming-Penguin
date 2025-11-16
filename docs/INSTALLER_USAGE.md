# Screaming Penguin — Installer Usage Guide

This guide provides the exact steps required to:

- Write the installer ISO to USB
- Prepare the `/config` partition
- Run the installer
- Understand its output
- Retrieve logs

---

## 1. Write the ISO to USB

### Linux

```sh
sudo dd if=screaming-penguin-v1.0.0.iso of=/dev/sdX bs=4M status=progress
sudo sync

Windows

Use Rufus or Balena Etcher and select:
•Image: the ISO you downloaded
•Mode: ISO or DD mode (either works)

macOS

diskutil list
sudo dd if=screaming-penguin-v1.0.0.iso of=/dev/diskX bs=4m
sync


⸻

2. Prepare the /config Partition

After imaging, reinsert the USB. Two partitions appear:
•p1: read-only boot system
•p2 (/config): writable configuration partition

Place the following required files:

/config/installer-config.yml
/config/rootfs/debian-rootfs.tar.gz

Optional:

/config/logs/       (installer creates this automatically)


⸻

3. Required Files

installer-config.yml

Defines the installation plan, target disk, hostname, locale, users, and SSH.

See CONFIG_REFERENCE.md for full schema.

debian-rootfs.tar.gz

Prebuilt Debian Bookworm root filesystem.

⸻

4. Boot the Target System
1.Insert the USB stick into the destination machine.
2.Boot from USB (BIOS/UEFI).
3.Screaming Penguin starts automatically.

You will see:
•A startup message
•Config validation
•Disk planning
•Confirmation prompt (ERASE if required)
•Progress logs

⸻

5. Logs

Installer writes logs to:

/config/logs/installer-YYYYMMDD-HHMMSS.log

---

6. Finishing

On success, the installer:
•Installs GRUB to the target disk
•Unmounts everything safely
•Optionally plays a completion beep
•Shuts down or reboots automatically

---
