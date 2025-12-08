# Phase 11 Rootfs Deploy Analysis

## Context & Goals
- Phase 11 must live immediately after the disk executor in `installer/init/init.sh` and bring the GPT layout into a usable Debian rootfs inside `/mnt/target`.
- The config partition now guarantees `/config/installer-config.yml` plus `/config/os/rootfs.tar.gz` (default) and `/config/logs/…`.
- The new runtime logic will parse `installer.rootfs.*` values, honor `SP_SKIP_*` and `SP_DEBUG_ROOTFS`, and emit `[SP-INSTALLER] rootfs …` markers so CI can trace the span.

## Assumptions & Decisions
- The disk executor exports `SP_DISK_EXECUTE_ROOT_PART`, so the Phase 11 code can mount the root partition, extract the tarball, bind `/dev|/proc|/sys|/run`, and run chroot helpers from the same shell session.
- `installer.rootfs.tarball` defaults to `/config/os/rootfs.tar.gz` but can be overridden in the YAML; the code falls back to `/config/os/rootfs.tar.gz` when the field is missing or empty.
- Hostname/timezone/locale/user/SSH configuration live in `installer.rootfs.*` (with fallbacks to the existing `system`, `user`, and `ssh` keys for compatibility).
- Tests run in `tests/installer/test_rootfs_deploy.py` will simulate a target root directory and tarball inside temporary directories, exercising extraction and file writing without real mounts or chroots by leveraging the new `SP_SKIP_*` hooks and `SP_ROOTFS_TARGET_DIR` override.
- The Phase 11 runtime library will use helper functions (e.g., `sp_rootfs_resolve_config`, `sp_rootfs_mount_target`, `sp_rootfs_configure_system`, `sp_rootfs_configure_user`, `sp_rootfs_chroot`) so the test harness can call the pieces it can safely run and assert their effects.

## Implementation Outline
1. **Runtime library (`installer/runtime/lib/rootfs_deploy.sh`)**
   - Log with `[SP-INSTALLER] rootfs START/END` plus sub-markers for deploy vs. chroot when `SP_DEBUG_ROOTFS=1`.
   - Resolve `SP_CONFIG_PATH` with `yq` to pull `installer.rootfs.*`, default to `/config/os/rootfs.tar.gz`, `/mnt/target`, and sensible hostname/locale/timezone.
   - Mount `SP_DISK_EXECUTE_ROOT_PART` at the canonical target (overrideable via `SP_ROOTFS_TARGET_DIR` for tests) unless `SP_SKIP_ROOTFS_DEPLOY=1`.
   - Extract the tarball with `tar -xpf --numeric-owner` and bind-mount the virtual filesystems.
   - Inside the (bind-mounted) chroot, optionally run functions to write `/etc/hostname`, `/etc/hosts`, `/etc/localtime`, `/etc/timezone`, `/etc/locale.gen`, run `locale-gen`, create the primary user, lock the account when `password_hash` is absent, and drop SSH keys into `~/.ssh/authorized_keys`.
2. **Init wiring**
   - Source the rootfs library in `installer/init/init.sh` alongside the existing libs.
   - After `sp_execute_gpt_plan` succeeds and only when the install path was allowed (write gate + `SP_ENABLE_DISK_EXECUTE=1` + `SP_MODE=INSTALL`), call `sp_rootfs_deploy_and_configure`.
   - Log failures and exit non-zero so the initramfs does not continue to the idle shell when Phase 11 fails during a real install.
3. **Config updates**
   - `config/installer-config.example.yml` will gain an `installer.rootfs` block with the default tarball path, target mount, and the fields required for hostname/locale/timezone/user/SSH keys; other sections may remain for compatibility but the schema doc will highlight the new block.
   - `installer/runtime/lib/config_validation.sh` should read the new keys (with existing fields as fallbacks) so the schema stays in sync.
4. **Docs**
   - `docs/CONFIG_SCHEMA.md`: describe `installer.rootfs.{tarball,target_mount,hostname,timezone,locale,username,password_hash,ssh_authorized_keys}`, mention `/config/os/rootfs.tar.gz` default, explain SSH key seeding expectations, and link to the new env toggles.
   - `docs/installer_contract.md`: add a Phase 11 section explaining that after disk execution succeeds the installer extracts the tarball from `/config/os/rootfs.tar.gz`, binds virtual filesystems, and chroots to configure hostname/user/locale/timezone/SSH.
   - `docs/architecture.md`: extend the pipeline narrative/pairs so the flow reads planner → executor → rootfs deploy → finalize, and describe Phase 11’s overlays.
   - `docs/DEV_ROADMAP.md` (plus `docs/Phase11_Roadmap.md` if needed): mark Phase 11 as delivered with bullet points covering the new stage, env toggles, and default paths.
5. **Tests**
   - `tests/installer/test_rootfs_deploy.py` will build a tiny tarball (a few files), place it in a temp dir, and use overrides so `sp_rootfs_deploy_and_configure` extracts it into a temp target rather than real devices.
   - The test asserts the files exist, hostname/timezone/locale files are updated, and `authorized_keys` gets written when SSH keys are present.
   - Additional cases toggle `SP_SKIP_ROOTFS_DEPLOY`/`SP_SKIP_CHROOT_CONFIG` to prove the env switches skip their respective actions while still logging the markers.

## Files to Add/Modify
- `installer/runtime/lib/rootfs_deploy.sh`
- `installer/init/init.sh`
- `config/installer-config.example.yml`
- `docs/CONFIG_SCHEMA.md`
- `docs/installer_contract.md`
- `docs/architecture.md`
- `docs/DEV_ROADMAP.md`
- `docs/Phase11_Roadmap.md` (if no existing Phase 11 doc yet)
- `docs/analysis/p11-rootfs-deploy-analysis.md`
- `tests/installer/test_rootfs_deploy.py`
- `installer/runtime/lib/config_validation.sh` (to keep schema in sync)

## Tradeoffs & Limitations
- The new library will depend on `tar`, `mount`, `flag`, `locale-gen`, `useradd`/`groupadd`, and `chroot`, so running Phase 11 may fail on constrained initramfs builds unless these binaries exist or are shimmed.
- `SP_SKIP_ROOTFS_DEPLOY` and `SP_SKIP_CHROOT_CONFIG` exist to let CI tests exercise the logic without real mounts/chroots; real installs still require the underlying commands to succeed.
- Locale/user setup uses chrooted Debian tooling rather than rewriting `/etc/` files manually, which improves correctness but assumes the rootfs tarball contains the usual utilities.
