# Screaming Penguin — Configuration Reference (v1.0.0)

This reference describes all valid fields in `installer-config.yml` for
Screaming Penguin v1.0.0.

---

## Top-Level Fields

```yaml
version:
target:
filesystem:
rootfs:
system:
user:
ssh:
safety:


⸻

version

Required. Must be 0.1 for v1.0.0.

⸻

target

target:
  disk: nvme0n1
  wipe: true

Fields
disk — Required. Block device name such as sda, nvme0n1, or vda.
wipe — Must be true in v1.

⸻

filesystem

filesystem:
  layout: single
  type: ext4
  boot_mode: auto

Fields
•layout — Only single supported
•type — Must be ext4
•boot_mode — auto, bios, or uefi

⸻

rootfs

Path to the Debian root filesystem tarball:

rootfs:
  path: /config/rootfs/debian-rootfs.tar.gz


⸻

system

system:
  hostname: penguin
  timezone: America/Chicago
  locale: en_US.UTF-8


⸻

user

user:
  name: rey
  sudo: true
  password_hash: "$6$..."

Password hash is required when SSH is disabled.

⸻

ssh

ssh:
  enable: true
  authorized_keys:
    - "ssh-ed25519 AAAA..."


⸻

safety

safety:
  require_erase_word: true

When true, installer requires the literal word ERASE before proceeding on
physical hardware.

⸻

Complete Examples

See config/examples/ or the release bundle’s example-configs directory for
fully working configurations.

## ISO Workflow Notes

When using ISO builds, the installer does not embed any configuration.  
A standalone `CONFIG` partition must exist on the USB drive for the installer to
load settings. The partition label must be exactly `CONFIG`, case-insensitive.

---
