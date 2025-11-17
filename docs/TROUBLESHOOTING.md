# Screaming Penguin — Troubleshooting (v1.0.0)

This guide lists common failure modes in Screaming Penguin and how to diagnose
them using logs.

---

## Log Location

/config/logs/installer-YYYYMMDD-HHMMSS.log

---

## Common Errors

### Missing Rootfs
Ensure `/config/rootfs/debian-rootfs.tar.gz` exists.

### Incorrect Target Disk
Verify disk names using `lsblk` before installation.

### SSH Disabled + Missing Password
If SSH is disabled, user.password_hash must be present.

### GRUB Installation Failure
Switch boot_mode between `auto`, `bios`, or `uefi`.

---

## CONFIG Not Detected

If the installer cannot find `/config/installer-config.yml`:

- Ensure the partition label is exactly `CONFIG`
- Ensure the filesystem is FAT32 (vfat)
- Ensure the YAML file is named correctly
- For ISO installs, verify you created the CONFIG partition after flashing
- Check that Secure Boot is disabled (UEFI may hide partitions)

---

## Debug Checklist

- Save the full log
- Save installer-config.yml
- Save SHA256SUMS
- Reproduce in QEMU

