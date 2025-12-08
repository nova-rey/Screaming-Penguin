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

### Phase 5 — Installer Runtime Requirements

The installer enforces the following rules:

- `target.disk` must be provided and must not match the USB device.
- `installer.write_gate` must be provided and must evaluate to `true` before any disk changes occur.
- `rootfs.path` must exist and point to a valid tarball.
- `user.name` must be provided.
- If SSH is disabled, `user.password_hash` is required.
- If SSH is enabled, at least one `authorized_keys` entry is required.
- If `safety.require_erase_word` is true, the installer will prompt for `ERASE` and abort on mismatch.

These requirements are evaluated during the LOAD_CONFIG state.
