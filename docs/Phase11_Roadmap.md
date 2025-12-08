# Phase 11 — Rootfs Deploy & Chroot Configuration

## Goal
- Take the GPT layout produced by Phase 10, deploy a prebuilt Debian rootfs tarball from the user-writable `/config` partition, and perform minimal chroot configuration (hostname, timezone, locale, primary user, and SSH keys) before handing control to future Phases.

## Delivery checklist
- `installer/runtime/lib/rootfs_deploy.sh` reads `installer.rootfs.*`, mounts the root partition, extracts the tarball at `/mnt/target`, bind-mounts `/dev|/proc|/sys|/run`, and chroots to write `/etc/hostname`, `/etc/timezone`, `/etc/locale.gen`, the primary user account, and any SSH authorized keys.
- Hooks the library into `installer/init/init.sh` immediately after `sp_execute_gpt_plan` so Phase 11 executes during INSTALL mode once the write gate and disk executor succeed.
- Defines the `SP_SKIP_ROOTFS_DEPLOY`, `SP_SKIP_CHROOT_CONFIG`, and `SP_DEBUG_ROOTFS` toggles so CI can exercise the logic without performing actual installs, and documents their semantics.
- Updates `config/installer-config.example.yml`, `docs/CONFIG_SCHEMA.md`, and the wider docs/roadmap/contract tree to capture the new schema, default `/config/os/rootfs.tar.gz` path, and the rootfs stage responsibilities.
- Adds `tests/installer/test_rootfs_deploy.py` to assert extraction, hostname/timezone/locale/user/SSH file updates, and skip/debug toggles in a temp-dir-friendly environment.

## Done when
- The init script logs `[SP-INSTALLER] rootfs START/END` spans, the rootfs stage succeeds whenever `sp_execute_gpt_plan` has written the GPT table, the new config fields are documented, and the tests cover the extraction and chroot helpers without requiring real disks.
