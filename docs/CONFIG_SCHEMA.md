```markdown
# Screaming Penguin — Config Schema (Outline)

This document will define the formal schema for `installer-config.yml`.

For v0, the draft schema is:

```yaml
version: 0.1

target:
  disk: nvme0n1
  wipe: true

filesystem:
  layout: single
  type: ext4
  boot_mode: auto

rootfs:
  path: /config/rootfs/debian-rootfs.tar.gz

system:
  hostname: penguin-01
  timezone: America/Chicago
  locale: en_US.UTF-8

user:
  name: rey
  sudo: true
  password_hash: "$6$..."

ssh:
  enable: true
  authorized_keys:
    - "ssh-ed25519 AAAAC3..."

safety:
  require_erase_word: true
```

Future work in this document:
•Define required vs optional fields.
•Specify allowed values and validation rules.
•Provide JSON Schema and/or YAML meta-schema for offline validation tooling.

---
```

### Rootfs Builder Integration (Phase 4)

The Screaming Penguin rootfs builder generates a Debian root filesystem tarball under:

dist/debian-rootfs--.tar.gz

For v1, the default suite is **bookworm** and the default architecture is **amd64**.

The installer expects the tarball to be provided at:

/config/rootfs/debian-rootfs.tar.gz

During later phases, the builder may optionally copy or symlink its output to this location for convenience.
