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
