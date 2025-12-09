# Phase 12 — Bootloader Finalization Analysis

## Current state
- **Disk planner** (`installer/runtime/lib/disk_layout.sh`) still outputs a GPT plan for EFI+root and supports the existing tuning knobs (`efi_size_mib`, alignments, etc.). The init shim runs the planner early, exposes debug markers, and leaves the JSON plan in `SP_DISK_LAYOUT_LAST_PLAN` for later phases.
- **Disk executor** (`installer/runtime/lib/disk_execute.sh`) re-validates `installer.write_gate`, parses the saved plan, rewrites the GPT table, formats EFI with `mkfs.vfat`, and tracks `SP_DISK_EXECUTE_EFI_PART` / `SP_DISK_EXECUTE_ROOT_PART` for downstream stages. The executor is gated by `SP_ENABLE_DISK_EXECUTE=1`.
- **Rootfs deploy** (`installer/runtime/lib/rootfs_deploy.sh`) mounts the newly created root partition, extracts `/config/os/rootfs.tar.gz`, bind-mounts `/dev|/proc|/sys|/run`, and chroots to set hostname/timezone/locale/user/SSH. It honors the skip/debug toggles and currently unmounts before returning.
- **Init script** (`installer/init/init.sh`) sequences bootstrapping → write-gate → planner → executor → rootfs. It logs readiness/summary markers but ends with `sp_idle_shell` without a bootloader stage or `[SP-INSTALLER] COMPLETE` marker.
- **Docs/test harness** describe the existing phases up to P11 (see `docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`, `docs/Phase11_Roadmap.md`, and the installer tests under `tests/installer/`). No mention of bootloader work yet.

## Phase 12 requirements
- Introduce a new bootloader library (`installer/runtime/lib/bootloader.sh`) that:
  1. Honors the gate (`installer.write_gate == true`), the existing `SP_ENABLE_DISK_EXECUTE`, the new `SP_ENABLE_BOOTLOADER`, the skip flag (`SP_SKIP_BOOTLOADER`), and the debug toggle (`SP_DEBUG_BOOTLOADER`).
  2. Mounts the EFI partition (from `SP_DISK_EXECUTE_EFI_PART`) into the target tree, generates `/etc/fstab` with `blkid`-derived UUIDs, installs GRUB via `grub-install --target=<cfg>`, and writes a minimal `/boot/grub/grub.cfg` inside the chroot.
  3. Provides a wrapper `sp_install_bootloader_and_finalize` that emits `[SP-INSTALLER] bootloader START/END`, handles skips/failures gracefully, and integrates with the existing rootfs helper functions where possible.
- Update `installer/init/init.sh` to source the bootloader library, call the wrapper immediately after `sp_rootfs_deploy_and_configure`, and emit a final `[SP-INSTALLER] COMPLETE` indicator even when the bootloader stage is skipped or runs in debug mode.
- Extend `installer/runtime/lib/config_validation.sh` and `config/installer-config.example.yml` to cover an optional `installer.bootloader` section (default GRUB target, EFI mountpoint, bootloader ID, fstab options).
- Expand the documentation suite (`docs/CONFIG_SCHEMA.md`, `docs/installer_contract.md`, `docs/architecture.md`) to describe the bootloader phase, introduce `docs/Phase12_Roadmap.md`, and mention the new flags/behaviors in `docs/DEV_ROADMAP.md`.
- Add `tests/installer/test_bootloader.py` that:
  * Validates fstab generation (using stubbed `blkid` output).
  * Asserts the constructed `grub-install` command/chroot invocation.
  * Checks stage gating under `SP_ENABLE_BOOTLOADER`, `SP_SKIP_BOOTLOADER`, and debug flags.
  * Confirms the init script reaches the bootloader stage only when both write gate and toggles align.

## Risks & open questions
- GRUB config generation needs to pick kernel/initrd paths from the rootfs tarball. We should enumerate likely filenames (e.g., `/boot/vmlinuz*` and `/boot/initrd.img*`) and document the fallback logic in the roadmap.
- Tests must avoid touching real loop devices: stub `mount`, `umount`, and `chroot` calls, and guard the bootloader harness behind `SP_ENABLE_BOOTLOADER`.

## Next actions (Block B)
1. Author `installer/runtime/lib/bootloader.sh` with mounting, `blkid`, fstab, GRUB install, config generation, and the wrapper described above.
2. Wire the new stage into `installer/init/init.sh` and emit the final completion marker.
3. Update `config/installer-config.example.yml`, `installer/runtime/lib/config_validation.sh`, and all referenced docs and roadmap entries.
4. Create `tests/installer/test_bootloader.py` covering the new helper behaviours plus init-script gating.
5. Ensure documentation directories contain `docs/Phase12_Roadmap.md` and the analysis doc is saved.
