# Screaming Penguin v1.0.0 — Release Notes

Initial public release of the Screaming Penguin Installer, a deterministic,
config-driven Debian installation system.

---

## Features

- Automated Debian Bookworm installation
- x86_64 support
- BIOS + UEFI boot
- Full-disk wipe (EFI + ext4)
- Prebuilt Debian rootfs extraction
- Headless operation
- Optional audio cues
- User, SSH, timezone, locale configuration

---

## Limitations

- Single disk only  
- ext4 only  
- No encryption or LVM  
- No network configuration  
- No Secure Boot  
- No multi-user provisioning  

---

## Included Artifacts

- `screaming-penguin-v1.0.0.img`  
- `debian-rootfs-bookworm-amd64-v1.0.0.tar.gz`  
- `example-configs/`  
- `SHA256SUMS`

---

## Recommended Validation

- Test in QEMU before real hardware
- Confirm disk names carefully
- Examine `/config/logs/` after any failure

