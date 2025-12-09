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
  rootfs:
    tarball: /config/os/rootfs.tar.gz
    target_mount: /mnt/target
    hostname: screaming-penguin
    timezone: Etc/UTC
    locale: en_US.UTF-8 UTF-8
    username: penguin
    password_hash: "$6$..."
    ssh_authorized_keys:
      - "ssh-ed25519 AAAAC3..."

target:
  disk: nvme0n1
  wipe: true

filesystem:
  layout: single
  type: ext4
  boot_mode: auto

system:
  hostname: penguin-01
  timezone: America/Chicago
  locale: en_US.UTF-8

user:
  name: penguin
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

### Phase 11 — Rootfs deployment & chroot configuration

- Phase 11 extracts `installer.rootfs.tarball` (default `/config/os/rootfs.tar.gz`) from `/config/os/` into `installer.rootfs.target_mount` (default `/mnt/target`), bind-mounts `/dev`, `/proc`, `/sys`, and `/run`, and chroots to configure the installed system.
- `installer.rootfs.hostname`, `installer.rootfs.timezone`, and `installer.rootfs.locale` seed `/etc/hostname`, `/etc/timezone`, and `/etc/locale.gen`; `installer.rootfs.username`, `installer.rootfs.password_hash`, and `installer.rootfs.ssh_authorized_keys` create the primary user inside the chroot.
- The stage respects the debug toggles:
  - `SP_SKIP_ROOTFS_DEPLOY=1` skips the mount/extract phase while still emitting `[SP-INSTALLER] rootfs` markers.
  - `SP_SKIP_CHROOT_CONFIG=1` skips hostname/timezone/locale/user/SSH configuration while leaving the extracted tree in place.
  - `SP_DEBUG_ROOTFS=1` emits extra `[SP-INSTALLER] rootfs` markers around each deploy and chroot step for log tracing.

### Phase 12 — Bootloader install & fstab generation

- After the rootfs is deployed, Phase 12 mounts the EFI partition (`SP_DISK_EXECUTE_EFI_PART`), generates `/etc/fstab` with UUID references discovered via `blkid`, writes a minimal GRUB 2 config (`/boot/grub/grub.cfg`), and runs `grub-install --target=<grub_efi_target>` inside the chroot so the new system can boot.
- The stage is gated behind the new toggle lifecycle:
  - `SP_ENABLE_BOOTLOADER=1` must be set before any GRUB work begins.
  - `SP_SKIP_BOOTLOADER=1` skips the stage but still emits `[SP-INSTALLER] bootloader` markers.
  - `SP_DEBUG_BOOTLOADER=1` emits extra debug context for each helper.
- `installer.bootloader` exposes tuning knobs:
  - `efi_mount_point` (default `/boot/efi`) controls where the EFI partition is mounted for GRUB and fstab entries.
  - `fstab_root_options` (`defaults,noatime`) / `fstab_efi_options` (`umask=0077,fmask=0077,dmask=0077`) dictate the `/etc/fstab` option strings.
- `grub_efi_target` (`x86_64-efi`) and `bootloader_id` (`screaming-penguin`) configure `grub-install`.
- `menu_entry`, `grub_timeout`, and `grub_cfg_path` define the boot menu entry text, timeout, and config location.
- The stage still writes `installer.bootloader` defaults even when the block is omitted.

### Phase 13 — Installer media bootability

- Phase 13 ensures that the raw `.img` builder is a valid UEFI ROM: `tools/make_installer_img.sh` now writes a GPT table whose first partition is a FAT32 EFI System Partition, copies `/boot/vmlinuz-installer` + `/boot/initrd-installer.img` into that partition, installs `grubx64.efi` under `/EFI/BOOT/BOOTX64.EFI`, and drops a minimal `EFI/BOOT/grub.cfg` that loads the upstream installer kernel/initrd.
- The shared `tools/grub_shared.sh` helper renders the canonical `linux`/`initrd` lines so both the `.img` and `.iso` builders keep their loader arguments synchronized while the ISO path retains its serial/BIOS extras.
- An installer-media test mounts the ESP via loop, validates that the filesystem reports FAT32, and asserts that `/EFI/BOOT/BOOTX64.EFI` plus `grub.cfg` referencing `vmlinuz-installer`/`initrd-installer.img` exist to prove the USB image can boot.

Future work: document how target kernels/initrds are discovered before writing `grub.cfg` and how the final system can regenerate GRUB via `update-grub`.
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
- `installer.rootfs.tarball` (default `/config/os/rootfs.tar.gz`) must be readable on the config partition.
- `installer.rootfs.hostname`, `.timezone`, `.locale`, and `.username` must be supplied (legacy `system.*` / `user.name` values are accepted as fallbacks).
- If SSH is disabled, `installer.rootfs.password_hash` or `user.password_hash` is required so a login path exists.
- If SSH is enabled, at least one entry must appear under `installer.rootfs.ssh_authorized_keys` or `ssh.authorized_keys`.
- If `safety.require_erase_word` is true, the installer will prompt for `ERASE` and abort on mismatch.

These requirements are evaluated during the LOAD_CONFIG state.
