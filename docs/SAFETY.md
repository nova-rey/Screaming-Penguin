# Screaming Penguin — Safety & Warnings

Screaming Penguin performs destructive, irreversible actions. This document
summarizes mandatory safety rules for v1.

---

## Disk Wipe Behavior

- The installer wipes the **entire target disk**.
- There is no undelete, no confirmation beyond optional `ERASE`, and no safety net.

---

## Conditions That Abort the Install

Installer will **refuse to continue** if:

- Target disk is missing
- Target disk appears to be the USB device
- Rootfs tarball missing or unreadable
- SSH disabled AND no password_hash provided
- Unsupported filesystem/layout
- Invalid YAML

---

## Recommended Testing Practice

- Always test your config first in QEMU.
- Keep backups of important data.
- Use `/config/logs` for diagnosing issues.
- Prefer predictable disk names (e.g., nvme0n1).

---

## Anti-Footgun Measures

- `require_erase_word: true` strongly recommended for physical machines.
- Install cannot proceed without explicit clarity from the config file.
