# Screaming Penguin — Configuration Reference

This document describes every field in the `installer-config.yml` used by the
Screaming Penguin automated installer.

---

## Top-Level Structure

```yaml
version: 0.1
target:
filesystem:
rootfs:
system:
user:
ssh:
safety:


⸻

target

target:
  disk: nvme0n1
  wipe: true

Fields

disk (required)
Block device name.
Must NOT refer to the USB stick itself.

wipe (boolean)
Always true in v1. No partial installs.

⸻

filesystem

filesystem:
  layout: single
  type: ext4
  boot_mode: auto

Fields

layout
Only single is supported.

type
Must be ext4.

boot_mode
•auto
•bios
•uefi

When set to auto, installer chooses based on system firmware.

⸻

rootfs

rootfs:
  path: /config/rootfs/debian-rootfs.tar.gz

Location of the Debian rootfs tarball. Must exist prior to install.

⸻

system

system:
  hostname: penguin-01
  timezone: America/Chicago
  locale: en_US.UTF-8

Hostname, locale, timezone applied inside the chroot.

⸻

user

user:
  name: rey
  sudo: true
  password_hash: "$6$..."

password_hash required if SSH is disabled.

⸻

ssh

ssh:
  enable: true
  authorized_keys:
    - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."

When enabled, SSH will be configured in the target system.

If disabled, password must exist.

⸻

safety

safety:
  require_erase_word: true

When true, installer will require the user to type ERASE before proceeding.

⸻

Full Example

See config/examples/ for complete working configurations.
