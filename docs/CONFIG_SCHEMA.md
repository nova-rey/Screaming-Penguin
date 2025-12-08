```markdown
# Screaming Penguin — Config Schema (Outline)

This document will define the formal schema for `installer-config.yml`.

For v0, the draft schema is:

```yaml
version: 0.1

installer:
  write_gate: true
  disk_layout:
    efi_size_mib: 512
    efi_alignment_mib: 1
    root_alignment_mib: 1
    root_reserved_mib: 4

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

### Phase 9 — Disk layout planning

- The Phase 9 planner targets the single device named under `target.disk` and never runs `sfdisk`, `sgdisk`, or any filesystem/tooling commands. It only makes decisions and emits a plan.
- `installer.disk_layout` exposes the tuning knobs documented above:
  - `efi_size_mib` (default `512`) declares the EFI System partition size in MiB.
  - `efi_alignment_mib` and `root_alignment_mib` (default `1`) align the partition start offsets in MiB.
  - `root_reserved_mib` (default `4`) reserves spare MiB at the end of the disk to keep rounding errors out of the layout.
- The planner outputs a JSON structure: the target disk path, `table: gpt`, and a `partitions` list where each entry records `index`, `role`, `type`, `start_mib`, `size_mib`, and `filesystem`. EFI entries use `role=efi`/`filesystem=fat32`, and the root entry uses `role=root`/`filesystem=ext4`.
- Debug boots (when `SP_DEBUG_DISK_LAYOUT=1`) print the plan to the console and also write `[SP-INSTALLER] disk-layout plan START/END` markers plus plan body lines to the serial log so later phases (and tests) can observe the declarative plan surface.

### Phase 10 — Disk execution

- Phase 10 consumes the deterministic JSON plan produced in Phase 9, re-validates `installer.write_gate`, and only writes the GPT table + filesystems when `SP_ENABLE_DISK_EXECUTE=1` and the gate is satisfied.
- The execution layer (`installer/runtime/lib/disk_execute.sh`) zaps the target, writes partitions via `sgdisk`, dumps/summarizes the layout with `sfdisk -l`, and formats the EFI partition with `mkfs.vfat -F 32` and the root partition with `mkfs.ext4 -F`. All commands log `[SP-INSTALLER] disk-exec` markers so CI/tests can detect the span.
- Until `SP_ENABLE_DISK_EXECUTE` is toggled, no destructive operations run and `installer.write_gate` continues to block writes. The Phase 10 harness lives under `tests/installer/test_disk_execute.py`, which drives a 2–4 GiB virtual disk file in `build/` so CI never touches real disks.
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

### Phase 12 — Bootloader & final stage

- Introduce an `installer.bootloader` block that controls the GRUB target (`grub_efi_target`, default `x86_64-efi`), bootloader ID (`grub_bootloader_id`, default `ScreamingPenguin`), timeout (`grub_timeout`, default `5`), and `/etc/fstab` tuning knobs (`fstab_root_options`, `fstab_root_freq`, `fstab_root_pass`, `fstab_efi_options`, `fstab_efi_freq`, `fstab_efi_pass`).
- The bootloader stage runs **after** the disk executor and rootfs deploy, rewrites `/etc/fstab` with the discovered EFI and root UUIDs, generates a minimal `grub.cfg`, installs GRUB into `/boot/efi`, and emits `[SP-INSTALLER] bootloader START/END` markers. The stage only runs when:
  - `installer.write_gate` remains true, and
  - `SP_ENABLE_BOOTLOADER=1` and `SP_ENABLE_DISK_EXECUTE=1` are both enabled.
- Use `SP_SKIP_BOOTLOADER=1` to skip the stage entirely and `SP_DEBUG_BOOTLOADER=1` to log command details without changing behavior so tests and CI can observe the bootloader command surface without touching disks.
