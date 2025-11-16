# Screaming Penguin — Troubleshooting

Common problems and how to diagnose them.

---

## Where to Find Logs

Installer logs:

/config/logs/installer-YYYYMMDD-HHMMSS.log

---

## Common Failures

### Missing rootfs

**Error:**  
`rootfs tarball not found`

Fix: Ensure file exists at `/config/rootfs/debian-rootfs.tar.gz`.

---

### Incorrect target disk

**Error:**  
`target disk not found` or installer aborts due to safety check.

Fix: Verify the correct device name (e.g., `lsblk`).

---

### SSH disabled but password missing

Fix: Provide `password_hash`.

---

### GRUB Install Failure

- Some hardware requires BIOS/UEFI override.
- Try switching `boot_mode` between `bios`/`uefi`/`auto`.

---

## Collecting Debug Info

1. Save `/config/logs/*.log`.
2. Provide `installer-config.yml`.
3. Provide rootfs tarball checksum.

---

If issues persist, file a GitHub issue with:
- Log file  
- ISO version  
- Config file  
- Hardware/QEMU details  
